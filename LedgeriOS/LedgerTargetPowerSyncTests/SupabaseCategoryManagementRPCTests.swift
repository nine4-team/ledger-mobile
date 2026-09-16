import Foundation
import Auth
import LedgerTargetCore
import Testing
@testable import LedgerTargetPowerSync
#if canImport(Security)
import Security
#endif

@Suite("Category management HTTP contract", .serialized)
struct SupabaseCategoryManagementRPCTests {
    @Test("Provider logout removes this session even offline, without global logout", arguments: [false, true])
    func localSessionSignOut(offline: Bool) async throws {
        let user = UUID()
        let storage = CategoryAuthTestStorage()
        let auth = authClient(storage: storage, userId: user, logoutOffline: offline)
        _ = try await auth.signIn(email: "fixture@example.invalid", password: "fixture-password")
        let identity = SupabaseAuthenticatedSession(client: auth, userId: user)
        #expect(try await identity.signOutThisDevice() == (offline ? .localOnly : .requestCompleted))
        #expect(auth.currentSession == nil)
        #expect(try await identity.signOutThisDevice() == .localOnly)
        let reopened = authClient(storage: storage, userId: user)
        #expect(reopened.currentSession == nil)
    }

    @Test @MainActor func entrySignOutUsesExplicitEmptyLocalDirectory() async throws {
        let user = UUID()
        let auth = authClient(storage: CategoryAuthTestStorage(), userId: user)
        let memory = CategoryAuthTestStorage()
        let admissions = OfflineWorkspaceAdmissionStore(read: { memory.retrieve(key: "records") },
            write: { memory.store(key: "records", value: $0) }, requireNotRemoved: { _ in })
        let entry = SupabaseOnlineSignIn(client: auth, supabaseURL: URL(string: "https://target.invalid")!,
            publishableKey: "sb_publishable_fixture", offlineAdmissions: admissions)
        try await entry.signIn(email: "fixture@example.invalid", password: "fixture-password")
        try await entry.signOutWithoutDownloadedWork {
            #expect(auth.currentSession != nil)
            let pendingUsers = try admissions.pendingSessionEndingUsers()
            #expect(pendingUsers == [user])
        }
        #expect(auth.currentSession == nil)
        #expect(try admissions.pendingSessionEndingUsers().isEmpty)
    }

    @Test @MainActor func entrySignOutRefusesDownloadedAccountBeforeCacheCleanup() async throws {
        let user = UUID()
        let auth = authClient(storage: CategoryAuthTestStorage(), userId: user)
        let memory = CategoryAuthTestStorage()
        let admissions = OfflineWorkspaceAdmissionStore(read: { memory.retrieve(key: "records") },
            write: { memory.store(key: "records", value: $0) }, requireNotRemoved: { _ in })
        let entry = SupabaseOnlineSignIn(client: auth, supabaseURL: URL(string: "https://target.invalid")!,
            publishableKey: "sb_publishable_fixture", offlineAdmissions: admissions)
        try await entry.signIn(email: "fixture@example.invalid", password: "fixture-password")
        let access = try WorkspaceMembershipAuthorization(environment: .targetLocal, authUserId: user,
            principalId: .init(validating: "principal"), accountId: .init(validating: "account"),
            role: .employee, financialAccess: .full)
        let account = try AccountSummary(id: access.accountId, displayName: .init(validating: "Downloaded"))
        try admissions.remember(access, account: account)
        await #expect(throws: SupabaseOnlineSignIn.Failure.downloadedWorkRequiresReview) {
            try await entry.signOutWithoutDownloadedWork { Issue.record("Must not clear downloaded work") }
        }
        #expect(auth.currentSession?.user.id == user)
        #expect(try admissions.pendingSessionEndingUsers().isEmpty)
        #expect(try admissions.workspacesForSessionEnding(user).count == 1)
    }

    @Test func localSignOutCannotEndAChangedIdentity() async throws {
        let original = UUID()
        let auth = authClient(storage: CategoryAuthTestStorage(), userId: original, nextUserId: UUID())
        _ = try await auth.signIn(email: "fixture@example.invalid", password: "fixture-password")
        let identity = SupabaseAuthenticatedSession(client: auth, userId: original)
        let replacement = try await auth.signIn(email: "another@example.invalid", password: "fixture-password")
        await #expect(throws: SupabaseAuthenticatedSession.Failure.identityChanged) {
            try await identity.signOutThisDevice()
        }
        #expect(auth.currentSession?.user.id == replacement.user.id)
    }

    @Test @MainActor func pendingSessionEndBlocksStoredAuthAndPreviouslyBoundAccessCheck() async throws {
        let user = UUID()
        let auth = authClient(storage: CategoryAuthTestStorage(), userId: user)
        _ = try await auth.signIn(email: "fixture@example.invalid", password: "fixture-password")
        let memory = CategoryAuthTestStorage()
        let admissions = OfflineWorkspaceAdmissionStore(read: { memory.retrieve(key: "records") },
            write: { memory.store(key: "records", value: $0) }, requireNotRemoved: { _ in })
        try admissions.selectIdentity(user)
        let http = session()
        defer { http.invalidateAndCancel(); CategoryHTTPProtocol.handler = nil }
        CategoryHTTPProtocol.handler = { _ in
            Issue.record("Pending logout must deny before making an authenticated request")
            throw URLError(.notConnectedToInternet)
        }
        let entry = SupabaseOnlineSignIn(client: auth, supabaseURL: URL(string: "https://target.invalid")!,
            publishableKey: "sb_publishable_fixture", http: http, offlineAdmissions: admissions)
        let access = try WorkspaceMembershipAuthorization(environment: .targetLocal, authUserId: user,
            principalId: .init(validating: "principal"), accountId: .init(validating: "account"),
            role: .employee, financialAccess: .full)
        let previouslyBound = try entry.workspaceAccessCheck(access)
        let previouslyBoundReceipts = try entry.onlineTransactionReceipts(access)
        try admissions.beginSessionEnding(user, expectedWorkspaces: [])
        #expect(entry.hasStoredSession) // Stored credentials do not bypass local ending state.
        await #expect(throws: OfflineWorkspaceAdmissionStore.Failure.sessionEndingPending) {
            _ = try await entry.accounts(environment: .targetLocal)
        }
        await #expect(throws: OfflineWorkspaceAdmissionStore.Failure.sessionEndingPending) {
            try await previouslyBound()
        }
        await #expect(throws: OfflineWorkspaceAdmissionStore.Failure.sessionEndingPending) {
            _ = try await previouslyBoundReceipts.read(transactionId: .init(validating: "transaction"))
        }
        #expect(throws: OfflineWorkspaceAdmissionStore.Failure.sessionEndingPending) {
            try entry.downloadedWorkspaces(environment: .targetLocal)
        }
    }

    @Test func uninvoicedReturnUsesBoundAuthenticatedTransport() async throws {
        let auth = authClient(storage: CategoryAuthTestStorage(), userId: UUID())
        let signedIn = try await auth.signIn(email: "fixture@example.invalid", password: "fixture-password")
        let http = session()
        defer { http.invalidateAndCancel(); CategoryHTTPProtocol.handler = nil }
        let access = try WorkspaceMembershipAuthorization(environment: .targetLocal, authUserId: signedIn.user.id,
            principalId: .init(validating: "principal"), accountId: .init(validating: "account"),
            role: .employee, financialAccess: .none)
        let rpc = try SupabaseWorkspaceCommandRPC(url: URL(string: "https://target.invalid")!,
            key: "sb_publishable_fixture", authorization: access,
            identity: .init(client: auth, userId: signedIn.user.id), http: http)
        func command(account: String) throws -> ReturnUninvoicedItemsCommand {
            try .init(operationId: .init(validating: "return-op"), accountId: .init(validating: account),
                actorPrincipalId: access.principalId, capturedAt: Date(timeIntervalSince1970: 123),
                payload: .init(projectId: .init(validating: "project"), items: [
                    .init(itemId: .init(validating: "item"), placementId: .init(validating: "old"),
                        chargeId: .init(validating: "charge"), expectedChargeRevision: 1,
                        inventoryPlacementId: .init(validating: "new"), returnOccurrenceId: .init(validating: "return"))]))
        }
        let value = try command(account: "account"), wire = try ReturnUninvoicedItemsUploadRequest(value)
        CategoryHTTPProtocol.handler = { request in
            #expect(request.url?.path == "/rest/v1/rpc/spike_return_uninvoiced_items")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer signed-in-token")
            #expect(try requestBody(request) == wire.rpcBody)
            return try response(request, result: ["operation_id":"return-op", "account_id":"account",
                "actor_principal_id":"principal", "command_type":"return_uninvoiced_items",
                "contract_version":"return-uninvoiced-items-v1", "command_fingerprint":wire.fingerprint,
                "envelope_sha256":wire.fingerprint, "subject_id":"project", "phase":"applied",
                "result_code":"uninvoiced_items_returned", "client_created_at_ms":123000,
                "server_received_at_ms":124000, "completed_at_ms":124000])
        }
        #expect(try await rpc.apply(value).phase == "applied")
        CategoryHTTPProtocol.handler = { _ in throw URLError(.badURL) }
        await #expect(throws: SupabaseWorkspaceCommandRPC.Failure.scopeMismatch) {
            try await rpc.apply(command(account: "foreign"))
        }
    }

    @Test func feeCreationUsesBoundAuthenticatedTransport() async throws {
        let user = UUID(), auth = authClient(storage: CategoryAuthTestStorage(), userId: UUID())
        let signedIn = try await auth.signIn(email: "fixture@example.invalid", password: "fixture-password")
        let http = session()
        defer { http.invalidateAndCancel(); CategoryHTTPProtocol.handler = nil }
        let access = try WorkspaceMembershipAuthorization(environment: .targetLocal, authUserId: signedIn.user.id,
            principalId: .init(validating: "principal"), accountId: .init(validating: "account"),
            role: .employee, financialAccess: .full)
        let rpc = try SupabaseWorkspaceCommandRPC(url: URL(string: "https://target.invalid")!,
            key: "sb_publishable_fixture", authorization: access,
            identity: .init(client: auth, userId: signedIn.user.id), http: http)
        func command(account: String) throws -> CreateFeeInstallmentCommand {
            try .init(operationId: .init(validating: user.uuidString), actorPrincipalId: access.principalId,
                capturedAt: Date(timeIntervalSince1970: 123), draft: .init(accountId: .init(validating: account),
                    projectId: .init(validating: "project"), installmentId: .init(validating: "fee"),
                    categoryId: .init(validating: "category"), label: "Design fee",
                    amount: .init(minorUnits: 123, currency: .init(validating: "USD"))))
        }
        let value = try command(account: "account"), wire = try CreateFeeInstallmentUploadRequest(value)
        CategoryHTTPProtocol.handler = { request in
            #expect(request.url?.path == "/rest/v1/rpc/spike_create_fee_installment")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer signed-in-token")
            #expect(try requestBody(request) == wire.rpcBody)
            return try response(request, result: ["operation_id": value.envelope.operationId.rawValue,
                "account_id":"account", "actor_principal_id":"principal", "command_type":"create_fee_installment",
                "contract_version":"fee-installment-create-v1", "command_fingerprint":wire.fingerprint,
                "envelope_sha256":wire.fingerprint, "subject_id":"fee", "phase":"applied",
                "result_code":"fee_installment_created", "client_created_at_ms":123000,
                "server_received_at_ms":124000, "completed_at_ms":124000])
        }
        #expect(try await rpc.apply(value).phase == "applied")
        CategoryHTTPProtocol.handler = { _ in throw URLError(.badURL) }
        await #expect(throws: SupabaseWorkspaceCommandRPC.Failure.scopeMismatch) { try await rpc.apply(command(account: "foreign")) }
    }

    @Test func expenseEditUsesExistingAuthenticatedTransportAndValidatesResult() async throws {
        let user = UUID(), auth = authClient(storage: CategoryAuthTestStorage(), userId: UUID())
        // Use the authenticated identity returned by the fixture, not an invented scope.
        let signedIn = try await auth.signIn(email: "fixture@example.invalid", password: "fixture-password")
        let http = session()
        defer { http.invalidateAndCancel(); CategoryHTTPProtocol.handler = nil }
        let access = try WorkspaceMembershipAuthorization(environment: .targetLocal, authUserId: signedIn.user.id,
            principalId: .init(validating: "principal"), accountId: .init(validating: "account"),
            role: .employee, financialAccess: .full)
        let rpc = try SupabaseWorkspaceCommandRPC(url: URL(string: "https://target.invalid")!,
            key: "sb_publishable_fixture", authorization: access,
            identity: .init(client: auth, userId: signedIn.user.id), http: http)
        let draft = try BusinessPaidExpenseDraft(accountId: access.accountId, projectId: .init(validating: "project"),
            expenseId: .init(validating: "expense"), vendor: "Vendor", date: "2026-01-01",
            finalAmount: .init(minorUnits: 123, currency: .init(validating: "USD")),
            categoryId: .init(validating: "category"), notes: "Edited")
        let command = try EditExpenseCommand(operationId: .init(validating: user.uuidString),
            actorPrincipalId: access.principalId, capturedAt: Date(timeIntervalSince1970: 123), expectedRevision: 2, entry: draft)
        let wire = try EditExpenseUploadRequest(command)
        CategoryHTTPProtocol.handler = { request in
            #expect(request.url?.path == "/rest/v1/rpc/spike_edit_expense")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer signed-in-token")
            #expect(try requestBody(request) == wire.rpcBody)
            let response: [String: Any] = ["operation_id": command.envelope.operationId.rawValue,
                "account_id": "account", "actor_principal_id": "principal", "command_type": "edit_expense",
                "contract_version": "expense-edit-v1", "command_fingerprint": wire.fingerprint,
                "envelope_sha256": wire.fingerprint, "subject_id": "expense", "phase": "applied",
                "result_code": "expense_edited", "client_created_at_ms": 123000,
                "server_received_at_ms": 124000, "completed_at_ms": 124000]
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    try JSONSerialization.data(withJSONObject: response))
        }
        #expect(try await rpc.apply(command).phase == "applied")
        CategoryHTTPProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        await #expect(throws: SupabaseWorkspaceCommandRPC.Failure.rejected(403)) { try await rpc.apply(command) }
    }
    @Test func transactionReadUsesBoundWorkspaceAndExistingDenialHandling() async throws {
        let user = UUID()
        let auth = authClient(storage: CategoryAuthTestStorage(), userId: user)
        _ = try await auth.signIn(email: "fixture@example.invalid", password: "fixture-password")
        let http = session()
        defer { http.invalidateAndCancel(); CategoryHTTPProtocol.handler = nil }
        let access = try WorkspaceMembershipAuthorization(environment: .targetLocal, authUserId: user,
            principalId: PrincipalID(validating: "principal"), accountId: AccountID(validating: "account"),
            role: .employee, financialAccess: .full)
        let rpc = try SupabaseWorkspaceCommandRPC(url: URL(string: "https://target.invalid")!,
            key: "sb_publishable_fixture", authorization: access, identity: .init(client: auth, userId: user),
            http: http, revalidateAccess: { throw SupabaseWorkspaceAuthorization.Failure.accessDenied })
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let bytes = try Data(contentsOf: root.appendingPathComponent("LedgerTargetMCP/tests/fixtures/transaction-receipt.json"))
        let transactionId = try TransactionID(validating: "transaction")
        CategoryHTTPProtocol.handler = { request in
            #expect(request.url?.path == "/rest/v1/rpc/spike_read_transaction_receipt")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer signed-in-token")
            let body = try #require(JSONSerialization.jsonObject(with: requestBody(request)) as? [String: String])
            #expect(body.count == 2 && body["p_account_id"] == "account")
            #expect(["transaction", "other"].contains(body["p_transaction_id"] ?? ""))
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, bytes)
        }
        let receipt = try await rpc.read(transactionId: transactionId)
        #expect(receipt.auditStatus == .balanced)
        #expect(receipt.items.last?.name == "Historical chair")
        #expect(receipt.items.last?.sku == "CHAIR-2")
        await #expect(throws: TransactionReceiptSnapshot.Failure.scopeMismatch) {
            try await rpc.read(transactionId: TransactionID(validating: "other"))
        }
        CategoryHTTPProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        await #expect(throws: SupabaseWorkspaceAuthorization.Failure.accessDenied) {
            try await rpc.read(transactionId: transactionId)
        }
    }

    @Test(arguments: ["allowed", "removed", "forbidden", "wrong-code", "expired", "outage", "scope", "identity", "persistence"])
    @MainActor func syncRevalidationOnlyReportsVerifiedRemoval(mode: String) async throws {
        let user = UUID()
        let auth = authClient(storage: CategoryAuthTestStorage(), userId: user, nextUserId: UUID())
        let http = session()
        let denials = AsyncStream<WorkspaceMembershipAuthorization>.makeStream()
        defer { http.invalidateAndCancel(); CategoryHTTPProtocol.handler = nil }
        let entry = SupabaseOnlineSignIn(client: auth, supabaseURL: URL(string: "https://target.invalid")!,
            publishableKey: "sb_publishable_fixture", http: http, onSyncAccessDenied: {
                denials.continuation.yield($0)
                if mode == "persistence" { throw LedgerOfflineClientRuntimeFailure.removalPersistenceFailed }
            })
        try await entry.signIn(email: "fixture@example.invalid", password: "fixture-password")
        let access = try WorkspaceMembershipAuthorization(environment: .targetLocal, authUserId: user,
            principalId: PrincipalID(validating: "member"), accountId: AccountID(validating: "category-account"),
            role: .employee, financialAccess: .full)
        let check = try entry.workspaceAccessCheck(access)
        CategoryHTTPProtocol.handler = { request in
            #expect(mode != "identity", "Changed identity must fail before HTTP")
            #expect(request.url?.path == "/rest/v1/rpc/spike_authorize_workspace")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer signed-in-token")
            #expect(try JSONDecoder().decode([String: String].self, from: requestBody(request)) == ["p_account_id": "category-account"])
            if mode == "allowed" || mode == "scope" {
                return try response(request, result: ["principalId": "member", "accountId": "category-account",
                    "role": "employee", "financialAccess": mode == "scope" ? "limited" : "full"])
            }
            let status = mode == "expired" ? 401 : mode == "outage" ? 503 : 403
            return (try #require(HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)),
                try JSONSerialization.data(withJSONObject: ["code": mode == "wrong-code" ? "other" : "42501",
                    "message": mode == "forbidden" ? "identity_not_linked" : "workspace_access_denied"]))
        }
        switch mode {
        case "allowed": try await check()
        case "scope": await #expect(throws: SupabaseWorkspaceAuthorization.Failure.scopeChanged) { try await check() }
        case "identity":
            _ = try await auth.signIn(email: "another@example.invalid", password: "fixture-password")
            #expect(auth.currentSession?.user.id != user)
            await #expect(throws: SupabaseAuthenticatedSession.Failure.identityChanged) { try await check() }
        case "persistence":
            await #expect(throws: LedgerOfflineClientRuntimeFailure.removalPersistenceFailed) { try await check() }
        default:
            let expected: SupabaseWorkspaceAuthorization.Failure = mode == "removed" ? .accessDenied
                : .rejected(mode == "expired" ? 401 : mode == "outage" ? 503 : 403)
            await #expect(throws: expected) { try await check() }
        }
        denials.continuation.finish()
        var values: [WorkspaceMembershipAuthorization] = []
        for await value in denials.stream { values.append(value) }
        #expect(values == ((mode == "removed" || mode == "persistence") ? [access] : []))
    }

    @Test(arguments: [403, 401, 503])
    func rejectedWorkspaceUploadsRevalidateOnlyForbiddenRequests(status: Int) async throws {
        let user = UUID()
        let auth = authClient(storage: CategoryAuthTestStorage(), userId: user)
        _ = try await auth.signIn(email: "fixture@example.invalid", password: "fixture-password")
        let http = session()
        let checks = AsyncStream<Void>.makeStream()
        defer { http.invalidateAndCancel(); CategoryHTTPProtocol.handler = nil }
        let category = try command()
        let access = WorkspaceMembershipAuthorization(environment: .targetLocal, authUserId: user,
            principalId: category.envelope.actorPrincipalId, accountId: category.envelope.accountId,
            role: .employee, financialAccess: .full)
        let rpc = try SupabaseWorkspaceCommandRPC(url: URL(string: "https://target.invalid")!,
            key: "sb_publishable_fixture", authorization: access, identity: .init(client: auth, userId: user),
            http: http, revalidateAccess: {
                checks.continuation.yield(())
                throw SupabaseWorkspaceAuthorization.Failure.accessDenied
            })
        CategoryHTTPProtocol.handler = { request in
            (try #require(HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)), Data())
        }
        let client = ClientCreationUploadRequest(operationId: "client-op", accountId: access.accountId.rawValue,
            actorPrincipalId: access.principalId.rawValue, contractVersion: "client-create-v1", clientCreatedAtMilliseconds: 1_800_000_000_123,
            clientId: "client", displayName: "Client", fingerprint: "fingerprint", envelopeJSON: "exact-envelope")
        let project = ProjectCreationUploadRequest(operationId: "project-op", accountId: access.accountId.rawValue,
            actorPrincipalId: access.principalId.rawValue, contractVersion: "project-create-v1", projectCreatedAtMilliseconds: 1_800_000_000_123,
            projectId: "project", clientSelectionKind: "existing", clientId: "client", newClientDisplayName: nil,
            projectDisplayName: "Project", description: nil, categoryAllocationsJSON: "[]", fingerprint: "fingerprint", envelopeJSON: "exact-envelope")
        if status == 403 {
            await #expect(throws: SupabaseWorkspaceAuthorization.Failure.accessDenied) { try await rpc.apply(category) }
            await #expect(throws: SupabaseWorkspaceAuthorization.Failure.accessDenied) { try await rpc.apply(client) }
            await #expect(throws: SupabaseWorkspaceAuthorization.Failure.accessDenied) { try await rpc.apply(project) }
        } else {
            await #expect(throws: SupabaseCategoryManagementRPC.Failure.rejected(status)) { try await rpc.apply(category) }
            await #expect(throws: SupabaseWorkspaceCommandRPC.Failure.rejected(status)) { try await rpc.apply(client) }
            await #expect(throws: SupabaseWorkspaceCommandRPC.Failure.rejected(status)) { try await rpc.apply(project) }
        }
        checks.continuation.finish()
        var count = 0
        for await _ in checks.stream { count += 1 }
        #expect(count == (status == 403 ? 3 : 0))
    }

    @Test @MainActor func expiredOnlineSessionDoesNotExpireDownloadedWorkspace() async throws {
        let user = UUID()
        let nextUser = UUID()
        let auth = authClient(storage: CategoryAuthTestStorage(), userId: user,
            expiredOnSignIn: true, nextUserId: nextUser)
        let memory = CategoryAuthTestStorage()
        let admissions = OfflineWorkspaceAdmissionStore(read: { memory.retrieve(key: "local") },
            write: { memory.store(key: "local", value: $0) }, requireNotRemoved: { _ in })
        let entry = SupabaseOnlineSignIn(client: auth, supabaseURL: URL(string: "https://target.invalid")!,
            publishableKey: "sb_publishable_fixture", offlineAdmissions: admissions)
        try await entry.signIn(email: "fixture@example.invalid", password: "fixture-password")
        let access = try WorkspaceMembershipAuthorization(environment: .targetLocal, authUserId: user,
            principalId: PrincipalID(validating: "offline-principal"), accountId: AccountID(validating: "offline-account"),
            role: .employee, financialAccess: .full)
        try admissions.remember(access, account: AccountSummary(id: access.accountId,
            displayName: AccountDisplayName(validating: "Account")))
        #expect(try entry.downloadedWorkspaces(environment: .targetLocal).map(\.authorization) == [access])
        // Reading local admission must not refresh the expired fixture token.
        #expect(auth.currentSession?.accessToken == "signed-in-token")
        #expect((auth.currentSession?.expiresAt ?? 0) < Date().timeIntervalSince1970)
        _ = try await auth.signIn(email: "another@example.invalid", password: "fixture-password")
        #expect(throws: OfflineWorkspaceAdmissionStore.Failure.identityMismatch) {
            try entry.downloadedWorkspaces(environment: .targetLocal)
        }
        try await entry.signIn(email: "another@example.invalid", password: "fixture-password")
        #expect(try entry.downloadedWorkspaces(environment: .targetLocal).isEmpty)
    }

    @Test @MainActor func authenticatedAccountLookupUsesServerPrincipalAndExistingSelectionSnapshot() async throws {
        let user = UUID()
        let auth = authClient(storage: CategoryAuthTestStorage(), userId: user)
        let http = session()
        defer { http.invalidateAndCancel(); CategoryHTTPProtocol.handler = nil }
        let signIn = SupabaseOnlineSignIn(client: auth, supabaseURL: URL(string: "https://target.invalid")!,
            publishableKey: "sb_publishable_fixture", http: http)
        #expect(!signIn.hasStoredSession)
        try await signIn.signIn(email: "fixture@example.invalid", password: "fixture-password")
        #expect(signIn.hasStoredSession)
        CategoryHTTPProtocol.handler = { request in
            #expect(request.url?.path == "/rest/v1/rpc/spike_read_authenticated_accounts")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer signed-in-token")
            #expect(String(data: try requestBody(request), encoding: .utf8) == "{}")
            return try response(request, result: ["principalId": "server-principal", "accounts": [
                ["id": "b", "displayName": "Beta"], ["id": "a", "displayName": "Alpha"]]])
        }
        let directory = try await signIn.accounts(environment: .targetStaging)
        let snapshot = directory.snapshot
        #expect(directory.identity.userId == user)
        #expect(snapshot.principalId.rawValue == "server-principal")
        #expect(snapshot.accounts.map(\.id.rawValue) == ["a", "b"])
        #expect(snapshot.isComplete && snapshot.quality == .ready)
        #expect(!snapshot.isAuthoritativeEmpty)
    }

    @Test @MainActor func onlineFormBindingKeepsLookupFailureSeparateFromSignInFailure() async throws {
        let user = UUID()
        let auth = authClient(storage: CategoryAuthTestStorage(), userId: user)
        let http = session()
        defer { http.invalidateAndCancel(); CategoryHTTPProtocol.handler = nil }
        let signIn = SupabaseOnlineSignIn(client: auth, supabaseURL: URL(string: "https://target.invalid")!,
            publishableKey: "sb_publishable_fixture", http: http)
        await #expect(throws: SupabaseOnlineSignIn.Failure.noSession) {
            try await signIn.accounts(environment: .targetStaging)
        }
        try await signIn.signIn(email: "fixture@example.invalid", password: "fixture-password")
        CategoryHTTPProtocol.handler = { request in
            (try #require(HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)),
             Data("identity_not_linked".utf8))
        }
        await #expect(throws: SupabaseOnlineSignIn.Failure.accountLookupFailed) {
            try await signIn.accounts(environment: .targetStaging)
        }
        #expect(signIn.hasStoredSession)
        // Retry the directory, not the password, and never turn a failed lookup
        // into the authoritative empty state that enables Account creation.
        CategoryHTTPProtocol.handler = { request in
            try response(request, result: ["principalId": "server-principal", "accounts": []])
        }
        #expect(try await signIn.accounts(environment: .targetStaging).snapshot.isAuthoritativeEmpty)
    }

    @Test @MainActor func onlineFormBindingSanitizesProviderErrors() async throws {
        let client = AuthClient(configuration: .init(url: URL(string: "https://target.invalid/auth/v1")!,
            localStorage: CategoryAuthTestStorage(), fetch: { _ in
                throw URLError(.notConnectedToInternet)
            }, autoRefreshToken: false, emitLocalSessionAsInitialSession: true))
        let signIn = SupabaseOnlineSignIn(client: client, supabaseURL: URL(string: "https://target.invalid")!,
            publishableKey: "sb_publishable_fixture")
        await #expect(throws: SupabaseOnlineSignIn.Failure.signInFailed) {
            try await signIn.signIn(email: "fixture@example.invalid", password: "fixture-password")
        }
        await #expect(throws: SupabaseOnlineSignIn.Failure.signUpFailed) {
            try await signIn.signUp(email: "fixture@example.invalid", password: "fixture-password")
        }
        #expect(!signIn.hasStoredSession)
    }

    @Test func workspaceTransportsMapExistingClientAndProjectContracts() async throws {
        let user = UUID()
        let auth = authClient(storage: CategoryAuthTestStorage(), userId: user)
        _ = try await auth.signIn(email: "fixture@example.invalid", password: "fixture-password")
        let http = session()
        defer { http.invalidateAndCancel(); CategoryHTTPProtocol.handler = nil }
        let access = try WorkspaceMembershipAuthorization(environment: .targetStaging, authUserId: user,
            principalId: PrincipalID(validating: "principal"), accountId: AccountID(validating: "account"),
            role: .employee, financialAccess: .full)
        let rpc = try SupabaseWorkspaceCommandRPC(url: URL(string: "https://target.invalid")!,
            key: "sb_publishable_fixture", authorization: access,
            identity: .init(client: auth, userId: user), http: http)
        CategoryHTTPProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer signed-in-token")
            let body = try #require(JSONSerialization.jsonObject(with: requestBody(request)) as? [String: Any])
            #expect(body["p_account_id"] as? String == "account")
            #expect(body["p_actor_principal_id"] as? String == "principal")
            #expect(body["p_envelope_json"] as? String == "exact-envelope")
            let client = request.url?.path == "/rest/v1/rpc/spike_create_client"
            let time = try #require(body[client ? "p_client_created_at" : "p_project_created_at"] as? String)
            #expect(time.hasSuffix(".123Z"))
            if client {
                #expect(body["p_display_name"] as? String == "Client")
                #expect(body.count == 9)
            } else {
                #expect(request.url?.path == "/rest/v1/rpc/spike_create_project")
                #expect(body["p_new_client_display_name"] is NSNull)
                #expect(body["p_description"] is NSNull)
                #expect((body["p_category_allocations"] as? [Any])?.count == 0)
                #expect(body.count == 14)
            }
            return try response(request, result: ["operation_id": client ? "client-op" : "project-op",
                "account_id": "account", "command_fingerprint": "fingerprint", "subject_id": client ? "client" : "project",
                "phase": "applied", "result_code": "created", "error_code": NSNull()])
        }
        let client = ClientCreationUploadRequest(operationId: "client-op", accountId: "account",
            actorPrincipalId: "principal", contractVersion: "client-create-v1", clientCreatedAtMilliseconds: 1_800_000_000_123,
            clientId: "client", displayName: "Client", fingerprint: "fingerprint", envelopeJSON: "exact-envelope")
        #expect(try await rpc.apply(client).operationId == "client-op")
        let project = ProjectCreationUploadRequest(operationId: "project-op", accountId: "account",
            actorPrincipalId: "principal", contractVersion: "project-create-v1", projectCreatedAtMilliseconds: 1_800_000_000_123,
            projectId: "project", clientSelectionKind: "existing", clientId: "client", newClientDisplayName: nil,
            projectDisplayName: "Project", description: nil, categoryAllocationsJSON: "[]",
            fingerprint: "fingerprint", envelopeJSON: "exact-envelope")
        #expect(try await rpc.apply(project).operationId == "project-op")
        CategoryHTTPProtocol.handler = { _ in throw URLError(.badURL) }
        let foreign = ClientCreationUploadRequest(operationId: "client-op", accountId: "foreign",
            actorPrincipalId: "principal", contractVersion: "client-create-v1", clientCreatedAtMilliseconds: 1_800_000_000_123,
            clientId: "client", displayName: "Client", fingerprint: "fingerprint", envelopeJSON: "exact-envelope")
        await #expect(throws: SupabaseWorkspaceCommandRPC.Failure.scopeMismatch) { try await rpc.apply(foreign) }
    }

    @Test @MainActor func workspaceActivationChecksSelectedScopeAndSpecificDenial() async throws {
        let user = UUID()
        let client = authClient(storage: CategoryAuthTestStorage(), userId: user, nextUserId: UUID())
        let http = session()
        let denied = AsyncStream<WorkspaceSelectionIntent>.makeStream()
        defer { http.invalidateAndCancel(); CategoryHTTPProtocol.handler = nil }
        let signIn = SupabaseOnlineSignIn(client: client, supabaseURL: URL(string: "https://target.invalid")!,
            publishableKey: "sb_publishable_fixture", http: http,
            onAccessDenied: { denied.continuation.yield($0) })
        try await signIn.signIn(email: "fixture@example.invalid", password: "fixture-password")
        CategoryHTTPProtocol.handler = { request in
            try response(request, result: ["principalId": "principal", "accounts": [["id": "account", "displayName": "Account"]]])
        }
        let directory = try await signIn.accounts(environment: .targetStaging)
        let selection = try AccountSelectionPolicy.makeIntent(selecting: AccountID(validating: "account"),
            from: directory.snapshot, requestedAt: Date())
        CategoryHTTPProtocol.handler = { request in
            #expect(request.url?.path == "/rest/v1/rpc/spike_authorize_workspace")
            #expect(try JSONDecoder().decode([String: String].self, from: requestBody(request)) == ["p_account_id": "account"])
            return try response(request, result: ["principalId": "principal", "accountId": "account",
                "role": "employee", "financialAccess": "none"])
        }
        let access = try await signIn.authorize(selection)
        #expect(access.authUserId == user && access.principalId == selection.principalId)
        #expect(access.accountId == selection.accountId && access.environment == selection.environment)
        #expect(access.role == .employee && access.financialAccess == .none)
        for invalid in [["principalId": "other", "accountId": "account", "role": "owner", "financialAccess": "full"],
                        ["principalId": "principal", "accountId": "other", "role": "owner", "financialAccess": "full"],
                        ["principalId": "principal", "accountId": "account", "role": "owner", "financialAccess": "invented"]] {
            CategoryHTTPProtocol.handler = { request in try response(request, result: invalid) }
            await #expect(throws: SupabaseWorkspaceAuthorization.Failure.invalidResponse) {
                try await signIn.authorize(selection)
            }
        }
        for (status, message) in [(403, "workspace_access_denied"), (403, "identity_not_linked"),
                                  (401, "workspace_access_denied"), (503, "unavailable")] {
            CategoryHTTPProtocol.handler = { request in
                (try #require(HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)),
                 try JSONSerialization.data(withJSONObject: ["code": "42501", "message": message]))
            }
            let expected: SupabaseWorkspaceAuthorization.Failure = status == 403 && message == "workspace_access_denied"
                ? .accessDenied : .rejected(status)
            await #expect(throws: expected) { try await signIn.authorize(selection) }
        }
        denied.continuation.finish()
        var removals: [WorkspaceSelectionIntent] = []
        for await deniedSelection in denied.stream { removals.append(deniedSelection) }
        #expect(removals == [selection])
        let failedRemoval = SupabaseOnlineSignIn(client: client, supabaseURL: URL(string: "https://target.invalid")!,
            publishableKey: "sb_publishable_fixture", http: http,
            onAccessDenied: { _ in throw LedgerOfflineClientRuntimeFailure.removalPersistenceFailed })
        CategoryHTTPProtocol.handler = { request in
            try response(request, result: ["principalId": "principal", "accounts": [["id": "account", "displayName": "Account"]]])
        }
        let refreshedDirectory = try await failedRemoval.accounts(environment: .targetStaging)
        let refreshedSelection = try AccountSelectionPolicy.makeIntent(selecting: selection.accountId,
            from: refreshedDirectory.snapshot, requestedAt: Date())
        CategoryHTTPProtocol.handler = { request in
            (try #require(HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)),
             try JSONSerialization.data(withJSONObject: ["code": "42501", "message": "workspace_access_denied"]))
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.removalPersistenceFailed) {
            try await failedRemoval.authorize(refreshedSelection)
        }
        _ = try await client.signIn(email: "another@example.invalid", password: "fixture-password")
        await #expect(throws: SupabaseOnlineSignIn.Failure.accountLookupFailed) {
            try await failedRemoval.authorize(refreshedSelection)
        }
    }

    @Test(arguments: [false, true]) @MainActor
    func onlineSignupDoesNotAssumeEmailConfirmationMeansSignedIn(immediateSession: Bool) async throws {
        let user = User(id: UUID(), appMetadata: [:], userMetadata: [:], aud: "authenticated",
            createdAt: Date(), updatedAt: Date(), isAnonymous: false)
        let credentials = Session(accessToken: "test-token", tokenType: "bearer", expiresIn: 3600,
            expiresAt: Date().timeIntervalSince1970 + 3600, refreshToken: "test-refresh", user: user)
        let data = try immediateSession ? AuthClient.Configuration.jsonEncoder.encode(credentials)
            : AuthClient.Configuration.jsonEncoder.encode(user)
        let client = AuthClient(configuration: .init(url: URL(string: "https://target.invalid/auth/v1")!,
            localStorage: CategoryAuthTestStorage(), fetch: { request in
                #expect(request.url?.path == "/auth/v1/signup")
                return (data, try #require(HTTPURLResponse(url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: ["Content-Type": "application/json"])))
            }, autoRefreshToken: false, emitLocalSessionAsInitialSession: true))
        let signIn = SupabaseOnlineSignIn(client: client, supabaseURL: URL(string: "https://target.invalid")!,
            publishableKey: "sb_publishable_fixture")
        #expect(try await signIn.signUp(email: "fixture@example.invalid", password: "fixture-password") ==
            (immediateSession ? .signedIn : .confirmEmail))
        #expect(signIn.hasStoredSession == immediateSession)
    }

    @Test func accountLookupDistinguishesRealEmptyFromMissingMalformedOrPartialData() async throws {
        let user = UUID()
        let auth = authClient(storage: CategoryAuthTestStorage(), userId: user)
        _ = try await auth.signIn(email: "fixture@example.invalid", password: "fixture-password")
        let http = session()
        defer { http.invalidateAndCancel(); CategoryHTTPProtocol.handler = nil }
        let lookup = try SupabaseAuthenticatedAccountLookup(supabaseURL: URL(string: "https://target.invalid")!,
            publishableKey: "sb_publishable_fixture", identity: .init(client: auth, userId: user), session: http)
        CategoryHTTPProtocol.handler = { request in
            try response(request, result: ["principalId": "server-principal", "accounts": []])
        }
        #expect(try await lookup.load(environment: .targetStaging).isAuthoritativeEmpty)
        let malformed: [[String: Any]] = [[:], ["principalId": NSNull(), "accounts": []],
            ["principalId": "principal"], ["principalId": "principal", "accounts": NSNull()],
            ["principalId": "principal", "accounts": [["id": "a", "displayName": " "]]],
            ["principalId": "principal", "accounts": [["id": "a", "displayName": "One"],
                                                         ["id": "a", "displayName": "Duplicate"]]]]
        for payload in malformed {
            let bytes = try JSONSerialization.data(withJSONObject: payload)
            CategoryHTTPProtocol.handler = { request in
                (try #require(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)), bytes)
            }
            await #expect(throws: SupabaseAuthenticatedAccountLookup.Failure.invalidResponse) {
                try await lookup.load(environment: .targetStaging)
            }
        }
        for status in [206, 401, 403, 503] {
            CategoryHTTPProtocol.handler = { request in
                (try #require(HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)), Data())
            }
            await #expect(throws: SupabaseAuthenticatedAccountLookup.Failure.rejected(status)) {
                try await lookup.load(environment: .targetStaging)
            }
        }
    }

    @Test(arguments: [false, true])
    func sdkSessionRefreshAndReopenSupplyCurrentCredentials(expiredOnSignIn: Bool) async throws {
        let identity = UUID()
        let storage = CategoryAuthTestStorage()
        let auth = authClient(storage: storage, userId: identity, expiredOnSignIn: expiredOnSignIn)
        _ = try await auth.signIn(email: "fixture@example.invalid", password: "fixture-password")
        let command = try command()
        let http = session()
        defer { http.invalidateAndCancel(); CategoryHTTPProtocol.handler = nil }
        let rpc = try SupabaseCategoryManagementRPC(supabaseURL: URL(string: "https://target.invalid")!,
            publishableKey: "publishable-key", authClient: auth, authenticatedUserId: identity, session: http)
        CategoryHTTPProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") ==
                "Bearer \(expiredOnSignIn ? "refreshed-token" : "signed-in-token")")
            return try response(request, result: result(command))
        }
        #expect(try await rpc.apply(command).phase == "applied")
        _ = try await auth.refreshSession()
        CategoryHTTPProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer refreshed-token")
            return try response(request, result: result(command))
        }
        #expect(try await rpc.apply(command).phase == "applied")
        let reopened = authClient(storage: storage, userId: identity)
        let reopenedRPC = try SupabaseCategoryManagementRPC(supabaseURL: URL(string: "https://target.invalid")!,
            publishableKey: "publishable-key", authClient: reopened, authenticatedUserId: identity, session: http)
        #expect(try await reopenedRPC.apply(command).phase == "applied")
    }

    @Test func sdkSessionCannotRebindAnOldOutboxToAnotherUserOrAnonymousLogin() async throws {
        let identity = UUID()
        let storage = CategoryAuthTestStorage()
        let auth = authClient(storage: storage, userId: identity, nextUserId: UUID())
        _ = try await auth.signIn(email: "fixture@example.invalid", password: "fixture-password")
        let http = session()
        defer { http.invalidateAndCancel(); CategoryHTTPProtocol.handler = nil }
        CategoryHTTPProtocol.handler = { _ in
            Issue.record("Wrong or absent identity reached category HTTP")
            throw URLError(.badURL)
        }
        let rpc = try SupabaseCategoryManagementRPC(supabaseURL: URL(string: "https://target.invalid")!,
            publishableKey: "publishable-key", authClient: auth, authenticatedUserId: UUID(), session: http)
        await #expect(throws: SupabaseCategoryManagementRPC.Failure.sessionIdentityChanged) {
            try await rpc.apply(command())
        }
        let bound = try SupabaseCategoryManagementRPC(supabaseURL: URL(string: "https://target.invalid")!,
            publishableKey: "publishable-key", authClient: auth, authenticatedUserId: identity, session: http)
        _ = try await auth.signIn(email: "another@example.invalid", password: "fixture-password")
        await #expect(throws: SupabaseCategoryManagementRPC.Failure.sessionIdentityChanged) {
            try await bound.apply(command())
        }
        try await auth.signOut(scope: .local)
        await #expect(throws: SupabaseCategoryManagementRPC.Failure.sessionIdentityChanged) {
            try await bound.apply(command())
        }
        let anonymous = authClient(storage: CategoryAuthTestStorage(), userId: identity, anonymous: true)
        _ = try await anonymous.signIn(email: "fixture@example.invalid", password: "fixture-password")
        let anonymousRPC = try SupabaseCategoryManagementRPC(supabaseURL: URL(string: "https://target.invalid")!,
            publishableKey: "publishable-key", authClient: anonymous, authenticatedUserId: identity, session: http)
        await #expect(throws: SupabaseCategoryManagementRPC.Failure.sessionIdentityChanged) {
            try await anonymousRPC.apply(command())
        }
    }

    #if canImport(Security)
    @Test func keychainSessionReopenDoesNotRequireOnlineRefreshOrCrossNamespaces() async throws {
        // Only this unique test service is written or removed. Never use the
        // app's credential service, Firebase keys or a shared access group.
        let service = "apps.nine4.ledger.target.auth-test.\(UUID().uuidString)"
        let storage = KeychainLocalStorage(service: service)
        defer { try? storage.remove(key: "category-auth-test") }
        let user = UUID()
        let auth = authClient(storage: storage, userId: user, expiredOnSignIn: true)
        _ = try await auth.signIn(email: "fixture@example.invalid", password: "fixture-password")
        #expect(try storage.retrieve(key: "category-auth-test") != nil)

        let reopened = AuthClient(configuration: .init(url: URL(string: "https://target.invalid/auth/v1")!,
            storageKey: "category-auth-test", localStorage: storage,
            fetch: { _ in
                Issue.record("Reading a stored session must not make a network request")
                throw URLError(.notConnectedToInternet)
            }, autoRefreshToken: false, emitLocalSessionAsInitialSession: true))
        #expect(reopened.currentSession?.user.id == user)
        #expect(reopened.currentSession?.accessToken == "signed-in-token")
        #expect(reopened.currentSession?.isExpired == true)
        try SupabaseAuthenticatedSession(client: reopened, userId: user).requireCurrentIdentity()
        func lookupStatus(service: String) -> OSStatus {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service, kSecAttrAccount as String: "category-auth-test"]
            return SecItemCopyMatching(query as CFDictionary, nil)
        }
        // The SDK's Keychain implementation throws on absence rather than
        // returning nil. Check the specific OS status, not an arbitrary error.
        #expect(lookupStatus(service: service + ".other") == errSecItemNotFound)
        // Cached identity is not an online token refresh or an offline Account
        // grant. The separate workspace policy must enforce learned removal.
        try storage.remove(key: "category-auth-test")
        #expect(lookupStatus(service: service) == errSecItemNotFound)
    }
    #endif

    private func authClient(storage: any AuthLocalStorage, userId: UUID, anonymous: Bool = false,
                            expiredOnSignIn: Bool = false, nextUserId: UUID? = nil,
                            logoutOffline: Bool = false) -> AuthClient {
        AuthClient(configuration: .init(url: URL(string: "https://target.invalid/auth/v1")!,
            storageKey: "category-auth-test", localStorage: storage, fetch: { request in
                let url = try #require(request.url)
                if url.path.hasSuffix("/logout") {
                    #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == [
                        URLQueryItem(name: "scope", value: "local")])
                    if logoutOffline { throw URLError(.notConnectedToInternet) }
                }
                let token = url.query?.contains("refresh_token") == true ? "refreshed-token" : "signed-in-token"
                let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let identity = body.contains("another@example.invalid") ? (nextUserId ?? userId) : userId
                let lifetime: TimeInterval = expiredOnSignIn && token == "signed-in-token" ? -60 : 3600
                let credentials = Session(accessToken: token, tokenType: "bearer", expiresIn: 3600,
                    expiresAt: Date().timeIntervalSince1970 + lifetime, refreshToken: "fixture-refresh",
                    user: User(id: identity, appMetadata: [:], userMetadata: [:], aud: "authenticated",
                        createdAt: Date(), updatedAt: Date(), isAnonymous: anonymous))
                let response = try #require(HTTPURLResponse(url: url, statusCode: 200,
                    httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
                return (try AuthClient.Configuration.jsonEncoder.encode(credentials), response)
            }, autoRefreshToken: false, emitLocalSessionAsInitialSession: true))
    }

    @Test func sendsOneCanonicalEnvelopeWithCurrentUserCredentials() async throws {
        let command = try command()
        let session = session()
        defer { session.invalidateAndCancel(); CategoryHTTPProtocol.handler = nil }
        CategoryHTTPProtocol.handler = { request in
            #expect(request.url?.absoluteString == "https://target.invalid/rest/v1/rpc/spike_manage_categories")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "apikey") == "publishable-key")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer user-token")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.pgrst.object+json")
            let body = try #require(JSONSerialization.jsonObject(with: requestBody(request)) as? [String: String])
            #expect(Set(body.keys) == ["p_envelope_json"])
            #expect(body["p_envelope_json"] == String(decoding: try OperationContractCodec.encode(command.envelope), as: UTF8.self))
            return try response(request, result: result(command))
        }
        let rpc = try rpc(session)
        #expect(try await rpc.apply(command).phase == "applied")
    }

    @Test func everyTerminalResultMustMatchTheWholeSubmittedIdentity() async throws {
        let command = try command()
        let session = session()
        defer { session.invalidateAndCancel(); CategoryHTTPProtocol.handler = nil }
        let rpc = try rpc(session)
        let mismatches: [String: Any] = [
            "operation_id": "other", "account_id": "other", "actor_principal_id": "other",
            "command_type": "archive_project", "contract_version": "other-v1",
            "command_fingerprint": String(repeating: "0", count: 64),
            "envelope_sha256": String(repeating: "0", count: 64), "request_sha256": "unexpected",
            "subject_id": "hidden-category", "phase": "queued", "result_code": "unexpected",
            "client_created_at_ms": 1, "server_received_at_ms": -1, "completed_at_ms": 0
        ]
        for (field, value) in mismatches {
            CategoryHTTPProtocol.handler = { request in
                var altered = try result(command)
                altered[field] = value
                return try response(request, result: altered)
            }
            await #expect(throws: CategoryManagementFailure.receiptMismatch) { try await rpc.apply(command) }
        }
    }

    @Test func expectedRejectionsAreResultsButUnknownCodesAreNotAccepted() async throws {
        let command = try command()
        let session = session()
        defer { session.invalidateAndCancel(); CategoryHTTPProtocol.handler = nil }
        let rpc = try rpc(session)
        for code in CategoryManagementServerResult.rejections {
            CategoryHTTPProtocol.handler = { request in
                var rejected = try result(command)
                rejected["phase"] = "rejected"; rejected["result_code"] = NSNull()
                rejected["error_code"] = code
                return try response(request, result: rejected)
            }
            #expect(try await rpc.apply(command).error_code == code)
        }
        CategoryHTTPProtocol.handler = { request in
            var rejected = try result(command)
            rejected["phase"] = "rejected"; rejected["result_code"] = NSNull()
            rejected["error_code"] = "unrecognized_reason"
            return try response(request, result: rejected)
        }
        await #expect(throws: CategoryManagementFailure.receiptMismatch) { try await rpc.apply(command) }
    }

    @Test func authenticationHTTPAndMalformedResponseFailuresNeverBecomeSuccess() async throws {
        let command = try command()
        let session = session()
        defer { session.invalidateAndCancel(); CategoryHTTPProtocol.handler = nil }
        let rpc = try rpc(session)
        for status in [401, 403, 409, 503] {
            CategoryHTTPProtocol.handler = { request in
                (try #require(HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)), Data())
            }
            await #expect(throws: SupabaseCategoryManagementRPC.Failure.self) { try await rpc.apply(command) }
        }
        CategoryHTTPProtocol.handler = { request in
            (try #require(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)), Data("{}".utf8))
        }
        await #expect(throws: SupabaseCategoryManagementRPC.Failure.self) { try await rpc.apply(command) }
    }

    @Test func unsafeCredentialsAndInvalidNamespaceAreRefusedBeforeNetwork() async throws {
        let session = session()
        defer { session.invalidateAndCancel(); CategoryHTTPProtocol.handler = nil }
        CategoryHTTPProtocol.handler = { _ in
            Issue.record("Unsafe request reached HTTP transport")
            throw URLError(.badURL)
        }
        let privileged = "e30." + Data("{\"role\":\"service_role\"}".utf8).base64EncodedString() + ".x"
        for key in ["", "   ", "sb_secret_forbidden", privileged] {
            #expect(throws: SupabaseCategoryManagementRPC.Failure.self) {
                try SupabaseCategoryManagementRPC(supabaseURL: URL(string: "https://target.invalid")!,
                    publishableKey: key, accessToken: { "user-token" }, session: session)
            }
            let rpc = try SupabaseCategoryManagementRPC(supabaseURL: URL(string: "https://target.invalid")!,
                publishableKey: "public-key", accessToken: { key }, session: session)
            await #expect(throws: SupabaseCategoryManagementRPC.Failure.self) { try await rpc.apply(command()) }
        }
        let original = try command()
        let malformed = try CategoryManagementCommand(operationId: OperationID(validating: "arbitrary-id"),
            accountId: original.envelope.accountId, actorPrincipalId: original.envelope.actorPrincipalId,
            capturedAt: original.envelope.clientCreatedAt, payload: original.envelope.payload)
        await #expect(throws: CategoryManagementFailure.invalidCommand) { try await rpc(session).apply(malformed) }
    }

    @Test func normalizedMillisecondTimestampsValidateWithoutFloatingPointEqualityFailures() throws {
        for offset in 0..<1_000 {
            let command = try command(time: 1_800_000_000 + Double(offset) / 1_000)
            let bytes = try JSONSerialization.data(withJSONObject: result(command))
            try JSONDecoder().decode(CategoryManagementServerResult.self, from: bytes).validate(for: command)
        }
    }

    private func command(time: Double = 1_800_000_000.123) throws -> CategoryManagementCommand {
        let account = try AccountID(validating: "category-account")
        return try CategoryManagementCommand(operationId: CategoryManagementOperationIdentity.make(accountId: account, uuid: UUID()),
            accountId: account, actorPrincipalId: PrincipalID(validating: "member"), capturedAt: Date(timeIntervalSince1970: time),
            payload: .init(action: .create, categoryId: BudgetCategoryID(validating: "category"),
                name: BudgetCategoryName(validating: "Art & Décor"), kind: .general, excludesFromOverallBudget: false))
    }

    private func rpc(_ session: URLSession) throws -> SupabaseCategoryManagementRPC {
        try .init(supabaseURL: URL(string: "https://target.invalid")!, publishableKey: "publishable-key",
            accessToken: { "user-token" }, session: session)
    }
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CategoryHTTPProtocol.self]
        return URLSession(configuration: configuration)
    }
    private func result(_ command: CategoryManagementCommand) throws -> [String: Any] {
        let envelope = command.envelope
        return ["operation_id": envelope.operationId.rawValue, "account_id": envelope.accountId.rawValue,
            "actor_principal_id": envelope.actorPrincipalId.rawValue, "command_type": "manage_categories",
            "contract_version": "category-management-v1", "command_fingerprint": try command.fingerprint.sha256,
            "envelope_sha256": try command.fingerprint.sha256, "request_sha256": NSNull(), "subject_id": envelope.accountId.rawValue,
            "phase": "applied", "result_code": "categories_updated", "error_code": NSNull(),
            "client_created_at_ms": Int64((envelope.clientCreatedAt.timeIntervalSince1970 * 1000).rounded()),
            "server_received_at_ms": 1_800_000_010_000, "completed_at_ms": 1_800_000_010_001]
    }
    private func response(_ request: URLRequest, result: [String: Any]) throws -> (HTTPURLResponse, Data) {
        (try #require(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])), try JSONSerialization.data(withJSONObject: result))
    }
    private func requestBody(_ request: URLRequest) throws -> Data {
        if let data = request.httpBody { return data }
        let stream = try #require(request.httpBodyStream)
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

// Test-only session storage. The app must use the SDK's protected Keychain store.
final class CategoryAuthTestStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(key: String, value: Data) { lock.withLock { values[key] = value } }
    func retrieve(key: String) -> Data? { lock.withLock { values[key] } }
    func remove(key: String) { lock.withLock { _ = values.removeValue(forKey: key) } }
}

private final class CategoryHTTPProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badURL) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
