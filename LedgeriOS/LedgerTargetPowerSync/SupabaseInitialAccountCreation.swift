import Foundation
import LedgerTargetCore

public struct SupabaseInitialAccountCreation: InitialAccountCreating {
    private let url: URL
    private let key: String
    private let identity: SupabaseAuthenticatedSession
    private let http: URLSession

    public init(supabaseURL: URL, publishableKey: String, identity: SupabaseAuthenticatedSession,
                http: URLSession = .shared) throws {
        try SupabaseAuthenticatedAccountLookup.validateConfiguration(supabaseURL: supabaseURL,
            publishableKey: publishableKey)
        url = supabaseURL
        key = publishableKey
        self.identity = identity
        self.http = http
    }

    public func createInitialAccount(_ command: InitialAccountCreationRequest) async throws -> AccountSummary {
        struct Payload: Encodable { let p_request_id: UUID; let p_display_name: String }
        let bytes = try await send("spike_create_initial_account", body: JSONEncoder().encode(
            Payload(p_request_id: command.requestId, p_display_name: command.displayName.rawValue)))
        struct Result: Decodable { let accountId: AccountID; let displayName: AccountDisplayName }
        let result = try JSONDecoder().decode(Result.self, from: bytes)
        guard result.displayName == command.displayName else {
            throw SupabaseAuthenticatedAccountLookup.Failure.invalidResponse
        }
        return AccountSummary(id: result.accountId, displayName: result.displayName)
    }

    /// Explicit identity preparation is separate from read-only Account discovery.
    public func prepareIdentity() async throws -> PrincipalID {
        let bytes = try await send("spike_prepare_authenticated_principal", body: Data("{}".utf8))
        return try JSONDecoder().decode(PrincipalID.self, from: bytes)
    }

    private func send(_ function: String, body: Data) async throws -> Data {
        var request = URLRequest(url: url.appendingPathComponent("rest/v1/rpc/\(function)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(try await identity.accessToken())", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        let (bytes, response) = try await http.data(for: request)
        try Task.checkCancellation()
        try identity.requireCurrentIdentity()
        guard let response = response as? HTTPURLResponse else {
            throw SupabaseAuthenticatedAccountLookup.Failure.invalidResponse
        }
        guard response.statusCode == 200 else {
            throw SupabaseAuthenticatedAccountLookup.Failure.rejected(response.statusCode)
        }
        return bytes
    }
}
