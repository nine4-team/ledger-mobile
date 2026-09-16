import Auth
import Foundation
import LedgerTargetCore
import Security
import Testing
@testable import LedgerTargetPowerSync

@Suite("Downloaded workspace admission", .serialized)
@MainActor
struct OfflineWorkspaceAdmissionTests {
    @Test func reconstructionNeedsNeitherProviderSessionNorNetwork() throws {
        let memory = CategoryAuthTestStorage()
        let store = makeStore(memory)
        let grant = try admission()
        try store.selectIdentity(grant.authorization.authUserId)
        try store.remember(grant.authorization, account: grant.account)
        let client = AuthClient(configuration: .init(url: URL(string: "https://target.invalid/auth/v1")!,
            localStorage: CategoryAuthTestStorage(), fetch: { _ in
                Issue.record("Offline entry must not contact Auth")
                throw URLError(.notConnectedToInternet)
            }, autoRefreshToken: false, emitLocalSessionAsInitialSession: true))
        let entry = SupabaseOnlineSignIn(client: client, supabaseURL: URL(string: "https://target.invalid")!,
            publishableKey: "sb_publishable_fixture", offlineAdmissions: makeStore(memory))
        #expect(!entry.hasStoredSession)
        #expect(try entry.downloadedWorkspaces(environment: .targetLocal) == [grant])
        try entry.requireOfflineAdmission(grant)
        #expect(try entry.downloadedWorkspaces(environment: .targetStaging).isEmpty)
        // There is deliberately no clock input or expiry field to advance.
        let json = try #require(memory.retrieve(key: "records"))
        #expect(!String(decoding: json, as: UTF8.self).contains("expires"))
    }

    @Test func identitySwitchAndMissingAdmissionNeverGrantAnotherWorkingSet() throws {
        let store = makeStore(CategoryAuthTestStorage())
        let first = try admission()
        #expect(throws: OfflineWorkspaceAdmissionStore.Failure.identityMismatch) {
            try store.remember(first.authorization, account: first.account)
        }
        try store.selectIdentity(first.authorization.authUserId)
        #expect(try store.downloaded(environment: .targetLocal, currentUserId: nil).isEmpty)
        try store.remember(first.authorization, account: first.account)
        let another = UUID()
        #expect(throws: OfflineWorkspaceAdmissionStore.Failure.identityMismatch) {
            try store.downloaded(environment: .targetLocal, currentUserId: another)
        }
        try store.selectIdentity(another)
        #expect(try store.downloaded(environment: .targetLocal, currentUserId: another).isEmpty)
        try store.selectIdentity(first.authorization.authUserId)
        #expect(try store.downloaded(environment: .targetLocal, currentUserId: nil) == [first])
    }

    @Test func learnedRemovalAndUnavailableProtectionFailClosedWithoutDeletingRecords() throws {
        let memory = CategoryAuthTestStorage()
        var denial: LedgerWorkspaceRemovalFailure?
        let store = makeStore(memory) { _ in if let denial { throw denial } }
        let grant = try admission()
        try store.selectIdentity(grant.authorization.authUserId)
        try store.remember(grant.authorization, account: grant.account)
        let saved = memory.retrieve(key: "records")
        denial = .removed
        #expect(try store.downloaded(environment: .targetLocal, currentUserId: nil).isEmpty)
        #expect(throws: LedgerWorkspaceRemovalFailure.removed) {
            try store.remember(grant.authorization, account: grant.account)
        }
        denial = .unavailable
        #expect(throws: LedgerWorkspaceRemovalFailure.unavailable) {
            try store.downloaded(environment: .targetLocal, currentUserId: nil)
        }
        #expect(memory.retrieve(key: "records") == saved)
    }

    @Test func corruptRecordAndStorageFailureDoNotBecomeAnEmptyAuthorizedDirectory() throws {
        let memory = CategoryAuthTestStorage()
        memory.store(key: "records", value: Data("broken".utf8))
        #expect(throws: (any Error).self) {
            try makeStore(memory).downloaded(environment: .targetLocal, currentUserId: nil)
        }
        let failing = OfflineWorkspaceAdmissionStore(read: { nil }, write: { _ in
            throw OfflineWorkspaceAdmissionStore.Failure.unavailable
        }, requireNotRemoved: { _ in })
        #expect(throws: OfflineWorkspaceAdmissionStore.Failure.unavailable) { try failing.selectIdentity(UUID()) }
    }

    @Test func interruptedEndingLocksIdentityButRetainsEveryAccountForRecovery() throws {
        let memory = CategoryAuthTestStorage()
        let store = makeStore(memory)
        let first = try admission()
        let second = try admission(userId: first.authorization.authUserId)
        let userId = first.authorization.authUserId
        try store.selectIdentity(userId)
        try store.remember(first.authorization, account: first.account)
        try store.remember(second.authorization, account: second.account)
        let directory = try store.workspacesForSessionEnding(userId)
        #expect(directory == [first, second])
        try store.beginSessionEnding(userId, expectedWorkspaces: directory)
        let reopened = makeStore(memory)
        #expect(try reopened.workspacesForSessionEnding(userId) == directory)
        #expect(throws: OfflineWorkspaceAdmissionStore.Failure.sessionEndingPending) {
            try reopened.downloaded(environment: .targetLocal, currentUserId: nil)
        }
        #expect(throws: OfflineWorkspaceAdmissionStore.Failure.sessionEndingPending) {
            try reopened.selectIdentity(userId)
        }
        #expect(throws: OfflineWorkspaceAdmissionStore.Failure.sessionEndingPending) {
            try reopened.remember(first.authorization, account: first.account)
        }
        #expect(throws: OfflineWorkspaceAdmissionStore.Failure.sessionEndingPending) {
            try reopened.requireIdentityAvailable(userId)
        }
        try reopened.completeSessionEnding(userId)
        #expect(try reopened.downloaded(environment: .targetLocal, currentUserId: nil).isEmpty)
        try reopened.selectIdentity(userId)
        #expect(try reopened.workspacesForSessionEnding(userId).isEmpty)
    }

    @Test func endingCannotForgetAnotherIdentityOrAChangedDirectory() throws {
        let store = makeStore(CategoryAuthTestStorage())
        let first = try admission()
        let another = try admission()
        let userId = first.authorization.authUserId
        try store.selectIdentity(userId)
        try store.remember(first.authorization, account: first.account)
        #expect(throws: OfflineWorkspaceAdmissionStore.Failure.invalidRecord) {
            try store.beginSessionEnding(userId, expectedWorkspaces: [])
        }
        #expect(try store.downloaded(environment: .targetLocal, currentUserId: nil) == [first])
        try store.beginSessionEnding(userId, expectedWorkspaces: [first])
        try store.selectIdentity(another.authorization.authUserId)
        try store.remember(another.authorization, account: another.account)
        try store.completeSessionEnding(userId)
        #expect(try store.downloaded(environment: .targetLocal, currentUserId: nil) == [another])
        #expect(throws: OfflineWorkspaceAdmissionStore.Failure.invalidRecord) {
            try store.completeSessionEnding(another.authorization.authUserId)
        }
    }

    @Test func failedEndingPersistenceDoesNotReportSuccessOrLoseRecoveryDirectory() throws {
        let memory = CategoryAuthTestStorage()
        var failWrites = false
        let store = OfflineWorkspaceAdmissionStore(read: { memory.retrieve(key: "records") }, write: {
            if failWrites { throw OfflineWorkspaceAdmissionStore.Failure.unavailable }
            memory.store(key: "records", value: $0)
        }, requireNotRemoved: { _ in })
        let grant = try admission()
        let userId = grant.authorization.authUserId
        try store.selectIdentity(userId)
        try store.remember(grant.authorization, account: grant.account)
        failWrites = true
        #expect(throws: OfflineWorkspaceAdmissionStore.Failure.unavailable) {
            try store.beginSessionEnding(userId, expectedWorkspaces: [grant])
        }
        #expect(try store.downloaded(environment: .targetLocal, currentUserId: nil) == [grant])
        failWrites = false
        try store.beginSessionEnding(userId, expectedWorkspaces: [grant])
        failWrites = true
        #expect(throws: OfflineWorkspaceAdmissionStore.Failure.unavailable) {
            try store.completeSessionEnding(userId)
        }
        #expect(try makeStore(memory).workspacesForSessionEnding(userId) == [grant])
        #expect(throws: OfflineWorkspaceAdmissionStore.Failure.sessionEndingPending) {
            try makeStore(memory).requireIdentityAvailable(userId)
        }
    }

    @Test func emptySessionCleanupRequiresExplicitPlanAndRecovers() async throws {
        let memory = CategoryAuthTestStorage()
        let store = makeStore(memory)
        let user = UUID()
        try store.selectIdentity(user)
        await #expect(throws: OfflineWorkspaceAdmissionStore.Failure.unavailable) {
            try await LedgerSessionEndCoordinator.end(targets: [], admissions: store, userId: user,
                expectedWorkspaces: [], clearCachesAndEndProviderSession: {
                    throw OfflineWorkspaceAdmissionStore.Failure.unavailable
                })
        }
        let reopened = makeStore(memory)
        #expect(try reopened.approvedSessionEndingRequests(user).isEmpty)
        #expect(throws: OfflineWorkspaceAdmissionStore.Failure.sessionEndingPending) {
            try reopened.requireIdentityAvailable(user)
        }
        try await LedgerSessionEndCoordinator.recover(admissions: reopened, userId: user,
            locations: [], clearCachesAndEndProviderSession: {})
        #expect(try reopened.pendingSessionEndingUsers().isEmpty)

        try reopened.selectIdentity(user)
        try reopened.beginSessionEnding(user, expectedWorkspaces: [])
        await #expect(throws: OfflineWorkspaceAdmissionStore.Failure.invalidRecord) {
            try await LedgerSessionEndCoordinator.recover(admissions: reopened, userId: user,
                locations: [], clearCachesAndEndProviderSession: {
                    Issue.record("A missing plan is not approved empty cleanup")
                })
        }
    }

    @Test func emptySessionCleanupCannotOmitDownloadedWork() async throws {
        let store = makeStore(CategoryAuthTestStorage())
        let grant = try admission()
        try store.selectIdentity(grant.authorization.authUserId)
        try store.remember(grant.authorization, account: grant.account)
        await #expect(throws: OfflineWorkspaceAdmissionStore.Failure.invalidRecord) {
            try await LedgerSessionEndCoordinator.end(targets: [], admissions: store,
                userId: grant.authorization.authUserId, expectedWorkspaces: [],
                clearCachesAndEndProviderSession: { Issue.record("Must not sign out with omitted work") })
        }
        #expect(try store.workspacesForSessionEnding(grant.authorization.authUserId) == [grant])
        #expect(try store.pendingSessionEndingUsers().isEmpty)
    }

    @Test func approvedWholeSessionIntentIsAtomicCompleteAndCannotBeReplaced() throws {
        let memory = CategoryAuthTestStorage()
        var rejectSave = false
        var writes = 0
        let store = OfflineWorkspaceAdmissionStore(read: { memory.retrieve(key: "records") }, write: {
            if rejectSave { throw OfflineWorkspaceAdmissionStore.Failure.unavailable }
            writes += 1
            memory.store(key: "records", value: $0)
        }, requireNotRemoved: { _ in })
        let first = try admission()
        let second = try admission(userId: first.authorization.authUserId)
        let user = first.authorization.authUserId
        let workspaces = [first, second]
        try store.selectIdentity(user)
        for workspace in workspaces { try store.remember(workspace.authorization, account: workspace.account) }
        let requests = try workspaces.map { workspace in
            let summary = try PendingLocalWorkSummary(environment: workspace.authorization.environment,
                principalId: workspace.authorization.principalId, accountId: workspace.account.id,
                snapshotRevision: 1, observedAt: Date(timeIntervalSince1970: 123), queuedOperationCount: 0,
                applyingOperationCount: 0, unresolvedRejectedOperationCount: 0, unverifiedAttachmentCount: 0)
            return try SessionEndRequest(disposition: .ordinaryCleanLogout, expectedSummary: summary,
                requestedAt: summary.observedAt)
        }
        let bindings = try Dictionary(uniqueKeysWithValues: requests.map { request in
            (try LedgerWorkspaceRemovalRegistry.identity(environment: request.expectedSummary.environment,
                principalId: request.expectedSummary.principalId, accountId: request.expectedSummary.accountId),
             String(repeating: "a", count: 64))
        })
        for invalid in [[requests[0]], [requests[0], requests[0]]] {
            #expect(throws: OfflineWorkspaceAdmissionStore.Failure.invalidRecord) {
                try store.beginApprovedSessionEnding(user, expectedWorkspaces: workspaces, requests: invalid, workspaceBindings: bindings)
            }
        }
        let saved = memory.retrieve(key: "records")
        rejectSave = true
        #expect(throws: OfflineWorkspaceAdmissionStore.Failure.unavailable) {
            try store.beginApprovedSessionEnding(user, expectedWorkspaces: workspaces, requests: requests, workspaceBindings: bindings)
        }
        #expect(memory.retrieve(key: "records") == saved)
        rejectSave = false
        let priorWrites = writes
        try store.beginApprovedSessionEnding(user, expectedWorkspaces: workspaces, requests: requests, workspaceBindings: bindings)
        #expect(writes == priorWrites + 1)
        #expect(try makeStore(memory).approvedSessionEndingRequests(user) == requests)
        try store.beginApprovedSessionEnding(user, expectedWorkspaces: workspaces, requests: requests, workspaceBindings: bindings)
        #expect(writes == priorWrites + 1)
        #expect(throws: OfflineWorkspaceAdmissionStore.Failure.invalidRecord) {
            try store.beginSessionEnding(user, expectedWorkspaces: workspaces)
        }
        try store.completeSessionEnding(user)
        #expect(throws: OfflineWorkspaceAdmissionStore.Failure.invalidRecord) {
            try store.approvedSessionEndingRequests(user)
        }
    }

    @Test func nativeKeychainAdmissionIsPersistentAndNotSynchronizable() throws {
        let service = "ledger.offline-admission-test.\(UUID())"
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "admissions"]
        defer {
            #expect(SecItemDelete(query as CFDictionary) == errSecSuccess)
        }
        let store = OfflineWorkspaceAdmissionStore(keychain: try LedgerPowerSyncKeychain(service: service))
        let grant = try admission()
        try store.selectIdentity(grant.authorization.authUserId)
        try store.remember(grant.authorization, account: grant.account)
        let reopened = OfflineWorkspaceAdmissionStore(keychain: try LedgerPowerSyncKeychain(service: service))
        #expect(try reopened.downloaded(environment: .targetLocal, currentUserId: nil) == [grant])
        var attributes = query
        attributes[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        #expect(SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess)
        let values = try #require(result as? [String: Any])
        #if os(iOS)
        #expect(values[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        #else
        // macOS's login Keychain does not return the iOS accessibility field.
        // Do not claim that this macOS test proves iOS device-lock behavior.
        #expect(values[kSecAttrService as String] as? String == service)
        #endif
        #expect(values[kSecAttrSynchronizable as String] as? Bool != true)
    }

    private func makeStore(_ memory: CategoryAuthTestStorage,
                           requireNotRemoved: @escaping (WorkspaceMembershipAuthorization) throws -> Void = { _ in })
        -> OfflineWorkspaceAdmissionStore {
        OfflineWorkspaceAdmissionStore(read: { memory.retrieve(key: "records") },
            write: { memory.store(key: "records", value: $0) }, requireNotRemoved: requireNotRemoved)
    }

    private func admission(userId: UUID = UUID()) throws -> OfflineWorkspaceAdmission {
        let account = try AccountID(validating: UUID().uuidString)
        return try OfflineWorkspaceAdmission(authorization: .init(environment: .targetLocal, authUserId: userId,
            principalId: PrincipalID(validating: UUID().uuidString), accountId: account, role: .employee,
            financialAccess: .full), account: AccountSummary(id: account, displayName: AccountDisplayName(validating: "Downloaded Account")))
    }
}
