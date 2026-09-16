import Auth
import CryptoKit
import Foundation
import LedgerTargetCore
import PowerSync

/// Provider binding for the existing sign-in form. It does not create Ledger
/// memberships, select Accounts, open databases or implement session-end cleanup.
@MainActor
public final class SupabaseOnlineSignIn {
    public enum Failure: Error, LocalizedError, Equatable {
        case busy, signInFailed, signUpFailed, accountLookupFailed, noSession, syncNotConfigured, sessionRecoveryFailed, downloadedWorkRequiresReview
        public var errorDescription: String? {
            switch self {
            case .busy: "Please wait for the current sign-in attempt to finish."
            case .signInFailed: "Could not sign in. Check your connection and sign-in details, then try again."
            case .signUpFailed: "Could not create your sign-in. Check your connection and try again."
            case .accountLookupFailed: "Signed in, but Ledger could not load your Accounts. Please try again."
            case .noSession: "Please sign in again."
            case .syncNotConfigured: "The PowerSync service is not configured for this build yet."
            case .sessionRecoveryFailed: "Ledger could not finish the previous sign-out. Retry before opening downloaded Accounts."
            case .downloadedWorkRequiresReview: "This device has downloaded Account data. Open an Account and use Settings to review local work before signing out."
            }
        }
    }

    public enum SignUpResult: Equatable, Sendable { case confirmEmail, signedIn }
    private let client: AuthClient
    private let url: URL
    private let publishableKey: String
    private let http: URLSession
    private let offlineAdmissions: OfflineWorkspaceAdmissionStore?
    private let onAccessDenied: (@Sendable (WorkspaceSelectionIntent) async throws -> Void)?
    private let onSyncAccessDenied: (@Sendable (WorkspaceMembershipAuthorization) async throws -> Void)?
    private var inFlight = false
    private var selectedDirectory: (userId: UUID, snapshot: AuthorizedAccountListSnapshot)?

    #if canImport(Security)
    public convenience init(supabaseURL: URL, publishableKey: String, localDataNamespace: String,
                            redirectTo: URL) throws {
        guard (localDataNamespace == "apps.nine4.ledger.target" || localDataNamespace.hasPrefix("apps.nine4.ledger.target.")),
              !localDataNamespace.contains(where: { $0.isWhitespace }), redirectTo.scheme != nil else {
            throw SupabaseAuthenticatedAccountLookup.Failure.invalidConfiguration
        }
        try SupabaseAuthenticatedAccountLookup.validateConfiguration(
            supabaseURL: supabaseURL, publishableKey: publishableKey)
        // The namespace identifies the target build; the origin hash prevents
        // accidentally restoring another Supabase project's credentials.
        let origin = supabaseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let originHash = SHA256.hash(data: Data(origin.utf8)).map { String(format: "%02x", $0) }.joined()
        let keychainService = "\(localDataNamespace).auth.\(originHash)"
        try self.init(client: AuthClient(configuration: .init(
            url: supabaseURL.appendingPathComponent("auth/v1"), headers: ["apikey": publishableKey],
            redirectToURL: redirectTo, storageKey: "session", localStorage: KeychainLocalStorage(service: keychainService),
            fetch: { request in try await URLSession.shared.data(for: request) },
            emitLocalSessionAsInitialSession: true)),
            supabaseURL: supabaseURL, publishableKey: publishableKey,
            offlineAdmissions: OfflineWorkspaceAdmissionStore(keychain: LedgerPowerSyncKeychain(
                service: "\(localDataNamespace).offline.\(originHash)")),
            onAccessDenied: { selection in
                let identity = try LedgerWorkspaceRemovalRegistry.identity(environment: selection.environment,
                    principalId: selection.principalId, accountId: selection.accountId)
                try await LedgerWorkspaceAccessCoordinator.shared.remove(identity: identity) {
                    try LedgerWorkspaceRemovalRegistry.recordRemoval(environment: selection.environment,
                        principalId: selection.principalId, accountId: selection.accountId)
                }
            })
    }
    #endif

    init(client: AuthClient, supabaseURL: URL, publishableKey: String, http: URLSession = .shared,
         offlineAdmissions: OfflineWorkspaceAdmissionStore? = nil,
         onAccessDenied: (@Sendable (WorkspaceSelectionIntent) async throws -> Void)? = nil,
         onSyncAccessDenied: (@Sendable (WorkspaceMembershipAuthorization) async throws -> Void)? = nil) {
        self.client = client
        self.url = supabaseURL
        self.publishableKey = publishableKey
        self.http = http
        self.offlineAdmissions = offlineAdmissions
        self.onAccessDenied = onAccessDenied
        self.onSyncAccessDenied = onSyncAccessDenied
    }

    public var hasStoredSession: Bool { client.currentSession != nil }

    /// Entry-only logout must prove there is no downloaded work, including
    /// removed Accounts. Never equate an empty server directory with that proof.
    public func signOutWithoutDownloadedWork(
        clearCaches: @escaping @MainActor @Sendable () async throws -> Void
    ) async throws {
        guard !inFlight else { throw Failure.busy }
        guard let user = client.currentSession?.user else { throw Failure.noSession }
        guard let offlineAdmissions else { throw OfflineWorkspaceAdmissionStore.Failure.unavailable }
        try offlineAdmissions.requireIdentityAvailable(user.id)
        guard try offlineAdmissions.workspacesForSessionEnding(user.id).isEmpty else {
            throw Failure.downloadedWorkRequiresReview
        }
        inFlight = true
        defer { inFlight = false }
        let identity = boundIdentity(user.id)
        try await LedgerSessionEndCoordinator.end(targets: [], admissions: offlineAdmissions,
            userId: user.id, expectedWorkspaces: [], clearCachesAndEndProviderSession: {
                try await clearCaches()
                _ = try await identity.signOutThisDevice()
            })
        selectedDirectory = nil
    }

    @discardableResult
    public func recoverPendingSessionEnd(environment: ValidatedLedgerEnvironment,
        clearCaches: @escaping @MainActor @Sendable () async throws -> Void) async throws -> Bool {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw Failure.sessionRecoveryFailed
        }
        return try await recoverPendingSessionEnd(environment: environment, applicationSupportDirectory: root,
            clearCaches: clearCaches)
    }

    @discardableResult
    func recoverPendingSessionEnd(environment: ValidatedLedgerEnvironment, applicationSupportDirectory: URL,
        accessCoordinator: LedgerWorkspaceAccessCoordinator = .shared,
        clearCaches: @escaping @MainActor @Sendable () async throws -> Void) async throws -> Bool {
        guard !inFlight else { throw Failure.busy }
        guard let offlineAdmissions else { return false }
        inFlight = true
        defer { inFlight = false }
        do {
            let users = try offlineAdmissions.pendingSessionEndingUsers()
            for user in users {
                let workspaces = try offlineAdmissions.workspacesForSessionEnding(user)
                guard workspaces.allSatisfy({ $0.authorization.environment == environment.manifest.environment }) else {
                    throw Failure.sessionRecoveryFailed
                }
                let locations = try workspaces.map { workspace in
                    try LedgerWorkspaceRuntimeIsolation.resolve(validatedEnvironment: environment,
                        principalId: workspace.authorization.principalId, accountId: workspace.account.id,
                        applicationSupportDirectory: applicationSupportDirectory)
                }
                try await LedgerSessionEndCoordinator.recover(admissions: offlineAdmissions, userId: user,
                    locations: locations, accessCoordinator: accessCoordinator,
                    clearCachesAndEndProviderSession: { [self] in
                        try await clearCaches()
                        try await finishRecoveredProviderSession(user)
                    })
            }
            if !users.isEmpty { selectedDirectory = nil }
            return !users.isEmpty
        } catch { throw Failure.sessionRecoveryFailed }
    }

    private func finishRecoveredProviderSession(_ userId: UUID) async throws {
        // A different currently stored identity already replaced the old local
        // session; never sign that other user out during old cleanup recovery.
        guard client.currentSession == nil || client.currentSession?.user.id == userId else { return }
        _ = try await boundIdentity(userId).signOutThisDevice()
    }

    public func sessionEnding(runtime: LedgerOfflineClientRuntime,
                              authorization: WorkspaceMembershipAuthorization,
                              environment: ValidatedLedgerEnvironment,
                              clearCaches: @escaping @MainActor @Sendable () async throws -> Void)
        -> any AccountSessionEnding {
        SupabaseSessionEndingAdapter(runtime: runtime) { [self] request in
            guard !inFlight else { throw Failure.busy }
            guard let offlineAdmissions else { throw OfflineWorkspaceAdmissionStore.Failure.unavailable }
            guard client.currentSession == nil || client.currentSession?.user.id == authorization.authUserId else {
                throw SupabaseAuthenticatedSession.Failure.identityChanged
            }
            inFlight = true
            defer { inFlight = false }
            try await runtime.lifecycleOwner.requireWorkspaceScope(authorization)
            let workspaces = try offlineAdmissions.workspacesForSessionEnding(authorization.authUserId)
            guard workspaces.contains(where: { $0.authorization == authorization }),
                  workspaces.allSatisfy({ $0.authorization.environment == environment.manifest.environment }) else {
                throw Failure.accountLookupFailed
            }
            var opened: [LedgerOfflineClientRuntime] = []
            do {
                var targets = [LedgerSessionEndCoordinator.Target(runtime: runtime, request: request)]
                let root = runtime.location.structuredDatabaseURL.deletingLastPathComponent()
                    .deletingLastPathComponent().deletingLastPathComponent()
                guard try LedgerWorkspaceRuntimeIsolation.resolve(validatedEnvironment: environment,
                    principalId: authorization.principalId, accountId: authorization.accountId,
                    applicationSupportDirectory: root) == runtime.location else {
                    throw Failure.accountLookupFailed
                }
                for workspace in workspaces where workspace.account.id != authorization.accountId {
                    let access = workspace.authorization
                    let location = try LedgerWorkspaceRuntimeIsolation.resolve(validatedEnvironment: environment,
                        principalId: access.principalId, accountId: access.accountId, applicationSupportDirectory: root)
                    // Never manufacture a clean empty database for a missing or
                    // differently-versioned downloaded Account during logout.
                    guard FileManager.default.fileExists(atPath: location.structuredDatabaseURL.path) else {
                        throw Failure.accountLookupFailed
                    }
                    let other = try await LedgerPowerSyncLocalBootstrap.open(validatedEnvironment: environment,
                        principalId: access.principalId, accountId: access.accountId,
                        applicationSupportDirectory: root, dependencies: .live)
                    opened.append(other)
                    let summary = try await other.pendingWorkSummary()
                    let clean = try SessionEndRequest(disposition: .ordinaryCleanLogout,
                        expectedSummary: summary, requestedAt: summary.observedAt)
                    targets.append(.init(runtime: other, request: clean))
                }
                let identity = boundIdentity(authorization.authUserId)
                try await LedgerSessionEndCoordinator.end(targets: targets, admissions: offlineAdmissions,
                    userId: authorization.authUserId, expectedWorkspaces: workspaces,
                    clearCachesAndEndProviderSession: {
                        try await clearCaches()
                        _ = try await identity.signOutThisDevice()
                    })
                selectedDirectory = nil
            } catch {
                for other in opened { try? await other.close() }
                throw error
            }
        }
    }

    private func boundIdentity(_ userId: UUID) -> SupabaseAuthenticatedSession {
        let admissions = offlineAdmissions
        return SupabaseAuthenticatedSession(client: client, userId: userId) {
            try await admissions?.requireIdentityAvailable(userId)
        }
    }

    public func signIn(email: String, password: String) async throws {
        guard !inFlight else { throw Failure.busy }
        inFlight = true
        defer { inFlight = false }
        do {
            let session = try await client.signIn(email: email, password: password)
            try offlineAdmissions?.selectIdentity(session.user.id)
        }
        catch is CancellationError { throw CancellationError() }
        catch { throw Failure.signInFailed }
    }

    public func signUp(email: String, password: String) async throws -> SignUpResult {
        guard !inFlight else { throw Failure.busy }
        inFlight = true
        defer { inFlight = false }
        do {
            let response = try await client.signUp(email: email, password: password)
            if let session = response.session { try offlineAdmissions?.selectIdentity(session.user.id) }
            return response.session == nil ? .confirmEmail : .signedIn
        } catch is CancellationError { throw CancellationError() }
        catch { throw Failure.signUpFailed }
    }

    #if canImport(AuthenticationServices)
    public func signInWithGoogle(redirectTo: URL) async throws {
        guard !inFlight else { throw Failure.busy }
        inFlight = true
        defer { inFlight = false }
        do {
            let session = try await client.signInWithOAuth(provider: .google, redirectTo: redirectTo)
            try offlineAdmissions?.selectIdentity(session.user.id)
        }
        catch is CancellationError { throw CancellationError() }
        catch { throw Failure.signInFailed }
    }
    #endif

    public func accounts(environment: LedgerEnvironmentKind) async throws
        -> (identity: SupabaseAuthenticatedSession, snapshot: AuthorizedAccountListSnapshot) {
        guard !inFlight else { throw Failure.busy }
        guard let user = client.currentSession?.user, !user.isAnonymous else { throw Failure.noSession }
        try offlineAdmissions?.requireIdentityAvailable(user.id)
        inFlight = true
        defer { inFlight = false }
        let identity = boundIdentity(user.id)
        do {
            let lookup = try SupabaseAuthenticatedAccountLookup(supabaseURL: url,
                publishableKey: publishableKey, identity: identity, session: http)
            let snapshot: AuthorizedAccountListSnapshot
            do {
                snapshot = try await lookup.load(environment: environment)
            } catch SupabaseAuthenticatedAccountLookup.Failure.identityNotLinked {
                let onboarding = try SupabaseInitialAccountCreation(supabaseURL: url,
                    publishableKey: publishableKey, identity: identity, http: http)
                _ = try await onboarding.prepareIdentity()
                snapshot = try await lookup.load(environment: environment)
            }
            try offlineAdmissions?.requireIdentityAvailable(user.id)
            if !snapshot.accounts.isEmpty, let offlineAdmissions,
               let pending = try offlineAdmissions.pendingInitialAccountRequestId(userId: user.id, environment: environment) {
                // A lost creation response may be followed by discovery of the
                // created Account. Reconcile the exact saved receipt, not merely
                // any membership (which could instead come from an invitation).
                let provider = try SupabaseInitialAccountCreation(supabaseURL: url,
                    publishableKey: publishableKey, identity: identity, http: http)
                let command = try InitialAccountCreationRequest(requestId: pending, displayName: .init(validating: "My account"))
                if let created = try? await provider.createInitialAccount(command),
                   snapshot.accounts.contains(where: { $0.id == created.id }) {
                    try offlineAdmissions.completeInitialAccountRequest(userId: user.id, environment: environment, requestId: pending)
                }
                try Task.checkCancellation()
                try identity.requireCurrentIdentity()
            }
            try offlineAdmissions?.requireIdentityAvailable(user.id)
            selectedDirectory = (user.id, snapshot)
            return (identity, snapshot)
        } catch is CancellationError { throw CancellationError() }
        catch { throw Failure.accountLookupFailed }
    }

    public func createInitialAccount(environment: LedgerEnvironmentKind) async throws -> AccountSummary {
        guard !inFlight else { throw Failure.busy }
        guard let user = client.currentSession?.user, !user.isAnonymous else { throw Failure.noSession }
        guard let offlineAdmissions else { throw OfflineWorkspaceAdmissionStore.Failure.unavailable }
        guard let directory = selectedDirectory, directory.userId == user.id,
              directory.snapshot.environment == environment, directory.snapshot.isAuthoritativeEmpty else {
            throw Failure.accountLookupFailed
        }
        inFlight = true
        defer { inFlight = false }
        let id = try offlineAdmissions.initialAccountRequestId(userId: user.id, environment: environment)
        let command = try InitialAccountCreationRequest(requestId: id, displayName: .init(validating: "My account"))
        let provider = try SupabaseInitialAccountCreation(supabaseURL: url, publishableKey: publishableKey,
            identity: boundIdentity(user.id), http: http)
        let account = try await provider.createInitialAccount(command)
        try offlineAdmissions.completeInitialAccountRequest(userId: user.id, environment: environment, requestId: id)
        selectedDirectory = nil
        return account
    }

    /// No token refresh/network request. Absence of a provider session is not
    /// explicit logout; coordinated session ending must revoke local admission.
    public func downloadedWorkspaces(environment: LedgerEnvironmentKind) throws -> [OfflineWorkspaceAdmission] {
        guard client.currentSession?.user.isAnonymous != true else { throw Failure.noSession }
        guard let offlineAdmissions else { return [] }
        return try offlineAdmissions.downloaded(environment: environment, currentUserId: client.currentSession?.user.id)
    }

    public func requireOfflineAdmission(_ admission: OfflineWorkspaceAdmission) throws {
        guard try downloadedWorkspaces(environment: admission.authorization.environment).contains(admission) else {
            throw OfflineWorkspaceAdmissionStore.Failure.unavailable
        }
    }

    public func rememberDownloadedWorkspace(_ authorization: WorkspaceMembershipAuthorization,
                                            account: AccountSummary, runtime: LedgerOfflineClientRuntime) async throws {
        guard let offlineAdmissions else { throw OfflineWorkspaceAdmissionStore.Failure.unavailable }
        let identity = boundIdentity(authorization.authUserId)
        try identity.requireCurrentIdentity()
        // Directory completion, physical scope and membership all precede the
        // persisted grant. Sign-in or an HTTP permission response alone is insufficient.
        try await runtime.waitForCategoryWorkspaceReady(authorization)
        try identity.requireCurrentIdentity()
        try offlineAdmissions.selectIdentity(authorization.authUserId)
        try offlineAdmissions.remember(authorization, account: account)
    }

    public func authorize(_ selection: WorkspaceSelectionIntent) async throws -> WorkspaceMembershipAuthorization {
        guard !inFlight else { throw Failure.busy }
        guard let user = client.currentSession?.user, !user.isAnonymous else { throw Failure.noSession }
        try offlineAdmissions?.requireIdentityAvailable(user.id)
        guard let selectedDirectory, selectedDirectory.userId == user.id,
              selectedDirectory.snapshot.principalId == selection.principalId,
              selectedDirectory.snapshot.environment == selection.environment,
              selectedDirectory.snapshot.fingerprint == selection.sourceSnapshotFingerprint else {
            throw Failure.accountLookupFailed
        }
        inFlight = true
        defer { inFlight = false }
        let authorizer = try SupabaseWorkspaceAuthorization(supabaseURL: url, publishableKey: publishableKey,
            identity: boundIdentity(user.id), http: http)
        do {
            let authorization = try await authorizer.authorize(selection)
            try offlineAdmissions?.requireIdentityAvailable(user.id)
            return authorization
        }
        catch SupabaseWorkspaceAuthorization.Failure.accessDenied {
            // Only the exact authenticated membership denial reaches here;
            // expired tokens, outages and unrelated 403s are not revocation.
            try await onAccessDenied?(selection)
            throw SupabaseWorkspaceAuthorization.Failure.accessDenied
        }
    }

    /// Only completes an already-reported removal. The app observes the runtime's
    /// existing removal stream and invokes this outside the SDK callback stack.
    public func finishReportedWorkspaceRemoval(_ authorization: WorkspaceMembershipAuthorization) async throws {
        let scope = try LedgerWorkspaceRemovalRegistry.identity(environment: authorization.environment,
            principalId: authorization.principalId, accountId: authorization.accountId)
        try await LedgerWorkspaceAccessCoordinator.shared.finishReportedRemoval(identity: scope) {
            try LedgerWorkspaceRemovalRegistry.recordRemoval(environment: authorization.environment,
                principalId: authorization.principalId, accountId: authorization.accountId)
        }
    }

    func workspaceAccessCheck(_ authorization: WorkspaceMembershipAuthorization) throws
        -> @Sendable () async throws -> Void {
        let authorizer = try SupabaseWorkspaceAuthorization(supabaseURL: url, publishableKey: publishableKey,
            identity: boundIdentity(authorization.authUserId), http: http)
        let onDenied = onSyncAccessDenied
        let admissions = offlineAdmissions
        return {
            try await admissions?.requireIdentityAvailable(authorization.authUserId)
            try await authorizer.requireCurrentAccess(authorization) {
                if let onDenied { try await onDenied(authorization) }
                else {
                    let scope = try LedgerWorkspaceRemovalRegistry.identity(environment: authorization.environment,
                        principalId: authorization.principalId, accountId: authorization.accountId)
                    try await LedgerWorkspaceAccessCoordinator.shared.reportRemoval(identity: scope) {
                        try LedgerWorkspaceRemovalRegistry.recordRemoval(environment: authorization.environment,
                            principalId: authorization.principalId, accountId: authorization.accountId)
                    }
                }
            }
        }
    }

    /// Authorized online receipt read. This does not replace the downloaded
    /// working-set reader or confer offline completeness on cached RPC results.
    public func onlineTransactionReceipts(_ authorization: WorkspaceMembershipAuthorization) throws
        -> any TransactionReceiptReading {
        let identity = boundIdentity(authorization.authUserId)
        try identity.requireCurrentIdentity()
        return try SupabaseWorkspaceCommandRPC(url: url, key: publishableKey, authorization: authorization,
            identity: identity, http: http, revalidateAccess: workspaceAccessCheck(authorization))
    }

    /// Online review only; offline admission still requires durable complete evidence.
    public func onlineInventorySaleReviews(_ authorization: WorkspaceMembershipAuthorization) throws
        -> any InventorySaleReviewReading {
        let identity = boundIdentity(authorization.authUserId)
        try identity.requireCurrentIdentity()
        return try SupabaseWorkspaceCommandRPC(url: url, key: publishableKey, authorization: authorization,
            identity: identity, http: http, revalidateAccess: workspaceAccessCheck(authorization))
    }

    /// Bind the opened workspace's outbox once. A later sign-in cannot retarget
    /// these transports to the new user. Nil service URL means no downloads.
    public func startWorkspaceSync(_ runtime: LedgerOfflineClientRuntime,
                                   authorization: WorkspaceMembershipAuthorization,
                                   powerSyncURL: URL?) async throws {
        // Check the physical database's identity before downloads can start;
        // command-level guards alone protect uploads, not incoming rows.
        try await runtime.lifecycleOwner.requireWorkspaceScope(authorization)
        try offlineAdmissions?.requireIdentityAvailable(authorization.authUserId)
        let identity = boundIdentity(authorization.authUserId)
        try identity.requireCurrentIdentity()
        if let powerSyncURL {
            let loopback = ["localhost", "127.0.0.1", "::1"].contains(powerSyncURL.host ?? "")
            guard powerSyncURL.host != nil,
                  powerSyncURL.scheme == "https" || (powerSyncURL.scheme == "http" && loopback),
                  powerSyncURL.user == nil, powerSyncURL.password == nil,
                  powerSyncURL.query == nil, powerSyncURL.fragment == nil else {
                throw SupabaseAuthenticatedAccountLookup.Failure.invalidConfiguration
            }
        }
        let revalidate = try workspaceAccessCheck(authorization)
        try await runtime.lifecycleOwner.startMembershipRevalidation(authorization, check: revalidate)
        let media = try SupabaseAccountLogoDownload(baseURL: url, publishableKey: publishableKey,
            accessToken: {
                try await revalidate()
                return try await identity.accessToken()
            })
        try await runtime.lifecycleOwner.bindMediaDownload(authorization) { reference in
            guard reference.accountId == authorization.accountId else {
                throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
            }
            return try await media.download(reference)
        }
        let rpc = try SupabaseWorkspaceCommandRPC(url: url, key: publishableKey,
            authorization: authorization, identity: identity, http: http, revalidateAccess: revalidate)
        try await runtime.startSync(credentialProvider: {
            guard let powerSyncURL else { return nil }
            try await revalidate()
            return PowerSyncCredentials(endpoint: powerSyncURL.absoluteString, token: try await identity.accessToken())
        }, appliers: .init(clientCreation: rpc, projectCreation: rpc, categoryManagement: rpc, inventorySale: rpc, itemPriceEdit: rpc, uninvoicedReturn: rpc, expenseCreation: rpc, expenseEdit: rpc, invoiceCreation: rpc, invoiceRevision: rpc, feeCreation: rpc))
        let attachments = try SupabaseTransactionAttachmentUpload(supabaseURL: url,
            publishableKey: publishableKey, accessToken: {
                try await revalidate()
                return try await identity.accessToken()
            }, session: http)
        try await runtime.lifecycleOwner.startTransactionAttachmentUploads(using: attachments)
    }
}

@MainActor
private final class SupabaseSessionEndingAdapter: AccountSessionEnding {
    private let runtime: LedgerOfflineClientRuntime
    private let end: @MainActor @Sendable (SessionEndRequest) async throws -> Void
    init(runtime: LedgerOfflineClientRuntime,
         end: @escaping @MainActor @Sendable (SessionEndRequest) async throws -> Void) {
        self.runtime = runtime
        self.end = end
    }
    func pendingWorkSummary() async throws -> PendingLocalWorkSummary { try await runtime.pendingWorkSummary() }
    func endSession(_ request: SessionEndRequest) async throws { try await end(request) }
}
