import Foundation
import Auth
import LedgerTargetCore

public struct CategoryManagementServerResult: Codable, Equatable, Sendable {
    let operation_id: String
    let account_id: String
    let actor_principal_id: String
    let command_type: String
    let contract_version: String
    let command_fingerprint: String
    let envelope_sha256: String
    let request_sha256: String?
    let subject_id: String
    let phase: String
    let result_code: String?
    let error_code: String?
    let client_created_at_ms: Int64
    let server_received_at_ms: Int64
    let completed_at_ms: Int64

    func validate(for command: CategoryManagementCommand) throws {
        let envelope = command.envelope
        guard operation_id == envelope.operationId.rawValue,
              account_id == envelope.accountId.rawValue,
              actor_principal_id == envelope.actorPrincipalId.rawValue,
              command_type == "manage_categories", contract_version == "category-management-v1",
              command_fingerprint == (try command.fingerprint.sha256),
              envelope_sha256 == command_fingerprint, request_sha256 == nil,
              subject_id == account_id,
              Double(client_created_at_ms) == (envelope.clientCreatedAt.timeIntervalSince1970 * 1000).rounded(),
              server_received_at_ms >= 0, completed_at_ms >= server_received_at_ms,
              (phase == "applied" && result_code == "categories_updated" && error_code == nil)
                || (phase == "rejected" && result_code == nil && Self.rejections.contains(error_code ?? "")) else {
            throw CategoryManagementFailure.receiptMismatch
        }
    }

    static let rejections: Set<String> = [
        "category_payload_invalid", "category_name_invalid", "category_unavailable",
        "category_order_invalid", "category_protected", "category_revision_conflict", "category_name_unavailable"
    ]
}

public protocol CategoryManagementCommandApplying: Sendable {
    func apply(_ command: CategoryManagementCommand) async throws -> CategoryManagementServerResult
}

public final class SupabaseCategoryManagementRPC: CategoryManagementCommandApplying, @unchecked Sendable {
    public enum Failure: Error, Equatable { case invalidEndpoint, unsafeCredential, invalidResponse, rejected(Int), sessionIdentityChanged }
    private let endpoint: URL
    private let publishableKey: String
    private let accessToken: @Sendable () async throws -> String
    private let session: URLSession

    /// Bind once when activating the authenticated user's workspace. The SDK
    /// refreshes credentials; a later sign-in must not rebind an old outbox.
    /// Account membership and the principal mapping remain server-authorized.
    public convenience init(supabaseURL: URL, publishableKey: String,
                            authClient: AuthClient, authenticatedUserId: UUID,
                            session: URLSession = .shared) throws {
        let identity = SupabaseAuthenticatedSession(client: authClient, userId: authenticatedUserId)
        try self.init(supabaseURL: supabaseURL, publishableKey: publishableKey,
            accessToken: {
                do { return try await identity.accessToken() }
                catch SupabaseAuthenticatedSession.Failure.identityChanged {
                    throw Failure.sessionIdentityChanged
                }
            }, session: session)
    }

    public init(supabaseURL: URL, publishableKey: String,
                accessToken: @escaping @Sendable () async throws -> String,
                session: URLSession = .shared) throws {
        guard ["http", "https"].contains(supabaseURL.scheme?.lowercased() ?? ""),
              supabaseURL.host != nil, supabaseURL.user == nil, supabaseURL.password == nil,
              supabaseURL.query == nil, supabaseURL.fragment == nil else { throw Failure.invalidEndpoint }
        try Self.validateCredential(publishableKey)
        endpoint = supabaseURL.appendingPathComponent("rest/v1/rpc/spike_manage_categories")
        self.publishableKey = publishableKey
        self.accessToken = accessToken
        self.session = session
    }

    public func apply(_ command: CategoryManagementCommand) async throws -> CategoryManagementServerResult {
        guard AccountBoundOperationIdentity.isValid(command.envelope.operationId,
            family: .categoryManagement, accountId: command.envelope.accountId) else {
            throw CategoryManagementFailure.invalidCommand
        }
        let token = try await accessToken()
        try Self.validateCredential(token)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.pgrst.object+json", forHTTPHeaderField: "Accept")
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["p_envelope_json":
            String(decoding: OperationContractCodec.encode(command.envelope), as: UTF8.self)])
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw Failure.rejected(response.statusCode) }
        let result: CategoryManagementServerResult
        do { result = try JSONDecoder().decode(CategoryManagementServerResult.self, from: data) }
        catch { throw Failure.invalidResponse }
        try result.validate(for: command)
        return result
    }

    private static func validateCredential(_ value: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !value.hasPrefix("sb_secret_") else { throw Failure.unsafeCredential }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 3 {
            var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
            if let bytes = Data(base64Encoded: payload),
               let json = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
               json["role"] as? String == "service_role" { throw Failure.unsafeCredential }
        }
    }
}
