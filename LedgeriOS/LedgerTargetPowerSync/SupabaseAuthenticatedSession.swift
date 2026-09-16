import Auth
import Foundation

/// Credentials for one signed-in identity, not Account access or offline unlock.
/// Keep this binding while an outbox is active; never retarget it on user change.
public struct SupabaseAuthenticatedSession: Sendable {
    enum SignOutResult: Equatable { case requestCompleted, localOnly }
    public enum Failure: Error, Equatable { case identityChanged }
    private let client: AuthClient
    private let requireLocalAccess: @Sendable () async throws -> Void
    public let userId: UUID

    public init(client: AuthClient, userId: UUID,
                requireLocalAccess: @escaping @Sendable () async throws -> Void = {}) {
        self.client = client
        self.userId = userId
        self.requireLocalAccess = requireLocalAccess
    }

    public func accessToken() async throws -> String {
        try await requireLocalAccess()
        try requireCurrentIdentity()
        let session = try await client.session
        try Task.checkCancellation()
        try await requireLocalAccess()
        guard session.user.id == userId, !session.user.isAnonymous,
              client.currentSession?.user.id == userId else { throw Failure.identityChanged }
        return session.accessToken
    }

    public func requireCurrentIdentity() throws {
        guard let session = client.currentSession, session.user.id == userId,
              !session.user.isAnonymous else { throw Failure.identityChanged }
    }

    /// Coordinator-only final step, after local durability/cleanup decisions.
    /// `.local` refers to this provider session, not a network-free operation.
    /// The pinned SDK removes stored credentials before contacting the server.
    func signOutThisDevice() async throws -> SignOutResult {
        guard client.currentSession != nil else { return .localOnly }
        try requireCurrentIdentity()
        do {
            try await client.signOut(scope: .local)
            guard client.currentSession == nil else { throw Failure.identityChanged }
            return .requestCompleted
        } catch {
            guard client.currentSession == nil else { throw error }
            // Offline logout still ends this device's session. Do not claim
            // remote revocation or retain usable credentials to retry later.
            return .localOnly
        }
    }
}
