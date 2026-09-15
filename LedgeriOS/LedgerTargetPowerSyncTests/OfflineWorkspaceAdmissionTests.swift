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

    private func admission() throws -> OfflineWorkspaceAdmission {
        let account = try AccountID(validating: UUID().uuidString)
        return try OfflineWorkspaceAdmission(authorization: .init(environment: .targetLocal, authUserId: UUID(),
            principalId: PrincipalID(validating: UUID().uuidString), accountId: account, role: .employee,
            financialAccess: .full), account: AccountSummary(id: account, displayName: AccountDisplayName(validating: "Downloaded Account")))
    }
}
