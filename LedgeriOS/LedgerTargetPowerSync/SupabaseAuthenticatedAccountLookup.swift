import CryptoKit
import Foundation
import LedgerTargetCore

/// Online bootstrap lookup. Reuses Account selection snapshots; it neither
/// activates a workspace nor substitutes for the downloaded/offline directory.
public struct SupabaseAuthenticatedAccountLookup: Sendable {
    public enum Failure: Error, Equatable { case invalidConfiguration, invalidResponse, identityNotLinked, rejected(Int) }
    private let endpoint: URL
    private let publishableKey: String
    private let identity: SupabaseAuthenticatedSession
    private let session: URLSession

    public init(supabaseURL: URL, publishableKey: String,
                identity: SupabaseAuthenticatedSession, session: URLSession = .shared) throws {
        try Self.validateConfiguration(supabaseURL: supabaseURL, publishableKey: publishableKey)
        endpoint = supabaseURL.appendingPathComponent("rest/v1/rpc/spike_read_authenticated_accounts")
        self.publishableKey = publishableKey
        self.identity = identity
        self.session = session
    }

    static func validateConfiguration(supabaseURL: URL, publishableKey: String) throws {
        let loopback = ["localhost", "127.0.0.1", "::1"].contains(supabaseURL.host ?? "")
        guard supabaseURL.scheme == "https" || (supabaseURL.scheme == "http" && loopback),
              supabaseURL.host != nil, supabaseURL.user == nil, supabaseURL.password == nil,
              supabaseURL.query == nil, supabaseURL.fragment == nil,
              ["", "/"].contains(supabaseURL.path),
              publishableKey.hasPrefix("sb_publishable_"),
              !publishableKey.contains(where: { $0.isWhitespace }) else {
            throw Failure.invalidConfiguration
        }
    }

    public func load(environment: LedgerEnvironmentKind, now: Date = Date()) async throws -> AuthorizedAccountListSnapshot {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(try await identity.accessToken())", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{}".utf8)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        // A user switch during the request must not publish the former user's directory.
        try identity.requireCurrentIdentity()
        guard let response = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        guard response.statusCode == 200 else {
            struct ServerError: Decodable { let code: String; let message: String }
            if response.statusCode == 403, let error = try? JSONDecoder().decode(ServerError.self, from: data),
               error.code == "42501", error.message == "identity_not_linked" {
                throw Failure.identityNotLinked
            }
            throw Failure.rejected(response.statusCode)
        }
        struct Payload: Decodable { let principalId: PrincipalID; let accounts: [AccountSummary] }
        do {
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            let version = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return try AuthorizedAccountListSnapshot(environment: environment, principalId: payload.principalId,
                accounts: payload.accounts, isComplete: true, quality: .ready,
                localDataVersion: LocalDataVersion(validating: version), asOf: now)
        } catch { throw Failure.invalidResponse }
    }
}
