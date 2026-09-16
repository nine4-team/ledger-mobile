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
        case busy, signInFailed, signUpFailed, accountLookupFailed, noSession, syncNotConfigured
        public var errorDescription: String? {
            switch self {
            case .busy: "Please wait for the current sign-in attempt to finish."
            case .signInFailed: "Could not sign in. Check your connection and sign-in details, then try again."
            case .signUpFailed: "Could not create your sign-in. Check your connection and try again."
            case .accountLookupFailed: "Signed in, but Ledger could not load your Accounts. Please try again."
            case .noSession: "Please sign in again."
            case .syncNotConfigured: "The PowerSync service is not configured for this build yet."
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
        inFlight = true
        defer { inFlight = false }
        let identity = SupabaseAuthenticatedSession(client: client, userId: user.id)
        do {
            let lookup = try SupabaseAuthenticatedAccountLookup(supabaseURL: url,
                publishableKey: publishableKey, identity: identity, session: http)
            let snapshot = try await lookup.load(environment: environment)
            selectedDirectory = (user.id, snapshot)
            return (identity, snapshot)
        } catch is CancellationError { throw CancellationError() }
        catch { throw Failure.accountLookupFailed }
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
        let identity = SupabaseAuthenticatedSession(client: client, userId: authorization.authUserId)
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
        guard let selectedDirectory, selectedDirectory.userId == user.id,
              selectedDirectory.snapshot.principalId == selection.principalId,
              selectedDirectory.snapshot.environment == selection.environment,
              selectedDirectory.snapshot.fingerprint == selection.sourceSnapshotFingerprint else {
            throw Failure.accountLookupFailed
        }
        inFlight = true
        defer { inFlight = false }
        let authorizer = try SupabaseWorkspaceAuthorization(supabaseURL: url, publishableKey: publishableKey,
            identity: .init(client: client, userId: user.id), http: http)
        do { return try await authorizer.authorize(selection) }
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
            identity: .init(client: client, userId: authorization.authUserId), http: http)
        let onDenied = onSyncAccessDenied
        return {
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
        let identity = SupabaseAuthenticatedSession(client: client, userId: authorization.authUserId)
        try identity.requireCurrentIdentity()
        return try SupabaseWorkspaceCommandRPC(url: url, key: publishableKey, authorization: authorization,
            identity: identity, http: http, revalidateAccess: workspaceAccessCheck(authorization))
    }

    /// Online review only; offline admission still requires durable complete evidence.
    public func onlineInventorySaleReviews(_ authorization: WorkspaceMembershipAuthorization) throws
        -> any InventorySaleReviewReading {
        let identity = SupabaseAuthenticatedSession(client: client, userId: authorization.authUserId)
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
        let identity = SupabaseAuthenticatedSession(client: client, userId: authorization.authUserId)
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
        }, appliers: .init(clientCreation: rpc, projectCreation: rpc, categoryManagement: rpc, inventorySale: rpc, expenseCreation: rpc, expenseEdit: rpc))
        let attachments = try SupabaseTransactionAttachmentUpload(supabaseURL: url,
            publishableKey: publishableKey, accessToken: {
                try await revalidate()
                return try await identity.accessToken()
            }, session: http)
        try await runtime.lifecycleOwner.startTransactionAttachmentUploads(using: attachments)
    }
}
