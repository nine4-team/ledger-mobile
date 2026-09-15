import Auth
import Foundation

/// Credentials for one signed-in identity, not Account access or offline unlock.
/// Keep this binding while an outbox is active; never retarget it on user change.
public struct SupabaseAuthenticatedSession: Sendable {
    public enum Failure: Error, Equatable { case identityChanged }
    private let client: AuthClient
    public let userId: UUID

    public init(client: AuthClient, userId: UUID) {
        self.client = client
        self.userId = userId
    }

    public func accessToken() async throws -> String {
        try requireCurrentIdentity()
        let session = try await client.session
        try Task.checkCancellation()
        guard session.user.id == userId, !session.user.isAnonymous,
              client.currentSession?.user.id == userId else { throw Failure.identityChanged }
        return session.accessToken
    }

    public func requireCurrentIdentity() throws {
        guard let session = client.currentSession, session.user.id == userId,
              !session.user.isAnonymous else { throw Failure.identityChanged }
    }
}
