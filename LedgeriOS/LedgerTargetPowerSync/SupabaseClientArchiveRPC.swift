import Foundation
import LedgerTargetCore

public enum SupabaseClientArchiveRPCFailure: Error, Equatable, Sendable {
    case invalidBaseURL
    case invalidPublishableKey
    case serviceRoleCredentialRefused
    case emptyAccessToken
    case invalidResponse
    case requestRejected(statusCode: Int)
    case resultMismatch
}

public final class SupabaseClientArchiveRPC:
    ClientArchiveCommandApplying, @unchecked Sendable
{
    public typealias AccessTokenProvider = @Sendable () async throws -> String

    private let rpcURL: URL
    private let publishableKey: String
    private let accessTokenProvider: AccessTokenProvider
    private let session: URLSession

    public init(
        supabaseURL: URL,
        publishableKey: String,
        accessTokenProvider: @escaping AccessTokenProvider,
        session: URLSession = .shared
    ) throws {
        guard let scheme = supabaseURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme), supabaseURL.host != nil,
              supabaseURL.user == nil, supabaseURL.password == nil,
              supabaseURL.query == nil, supabaseURL.fragment == nil else {
            throw SupabaseClientArchiveRPCFailure.invalidBaseURL
        }
        guard !publishableKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SupabaseClientArchiveRPCFailure.invalidPublishableKey
        }
        guard !Self.isServiceRoleCredential(publishableKey) else {
            throw SupabaseClientArchiveRPCFailure.serviceRoleCredentialRefused
        }
        rpcURL = supabaseURL.appendingPathComponent("rest/v1/rpc/spike_archive_client")
        self.publishableKey = publishableKey
        self.accessTokenProvider = accessTokenProvider
        self.session = session
    }

    public func apply(
        _ request: ClientArchiveUploadRequest
    ) async throws -> ClientArchiveServerResult {
        guard let operationId = try? OperationID(validating: request.operationId),
              let accountId = try? AccountID(validating: request.accountId),
              ClientArchiveOperationIdentity.isValid(operationId, accountId: accountId) else {
            throw SupabaseClientArchiveRPCFailure.resultMismatch
        }
        let token = try await accessTokenProvider()
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SupabaseClientArchiveRPCFailure.emptyAccessToken
        }
        guard !Self.isServiceRoleCredential(token) else {
            throw SupabaseClientArchiveRPCFailure.serviceRoleCredentialRefused
        }

        var urlRequest = URLRequest(url: rpcURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/vnd.pgrst.object+json", forHTTPHeaderField: "Accept")
        urlRequest.setValue(publishableKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try ClientArchiveRPCBody(request: request).encodedData()

        let (data, response) = try await session.data(for: urlRequest)
        guard let response = response as? HTTPURLResponse else {
            throw SupabaseClientArchiveRPCFailure.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw SupabaseClientArchiveRPCFailure.requestRejected(statusCode: response.statusCode)
        }
        let result: ClientArchiveServerResult
        do { result = try JSONDecoder().decode(ClientArchiveServerResult.self, from: data) }
        catch { throw SupabaseClientArchiveRPCFailure.invalidResponse }
        guard LedgerPowerSyncUploadConnector.isValidClientArchiveResult(
            result, request: request
        ) else { throw SupabaseClientArchiveRPCFailure.resultMismatch }
        return result
    }

    static func isKnownRejectionCode(_ code: String) -> Bool {
        knownRejectionCodes.contains(code)
    }

    private static let knownRejectionCodes: Set<String> = [
        "client_archive_command_encoding_invalid",
        "client_archive_envelope_mismatch",
        "client_archive_fingerprint_mismatch",
        "client_archive_payload_invalid",
        "client_archive_revision_conflict",
        "contract_unsupported"
    ]

    private static func isServiceRoleCredential(_ credential: String) -> Bool {
        if credential.hasPrefix("sb_secret_") { return true }
        let segments = credential.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return false }
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let role = object["role"] as? String else { return false }
        return role == "service_role"
    }
}

private struct ClientArchiveRPCBody {
    let request: ClientArchiveUploadRequest

    func encodedData() throws -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let capturedAt = formatter.string(from: Date(
            timeIntervalSince1970: Double(request.clientCreatedAtMilliseconds) / 1_000
        ))
        return try JSONSerialization.data(
            withJSONObject: [
                "p_operation_id": request.operationId,
                "p_account_id": request.accountId,
                "p_actor_principal_id": request.actorPrincipalId,
                "p_contract_version": request.contractVersion,
                "p_client_captured_at": capturedAt,
                "p_client_id": request.clientId,
                "p_expected_revision": request.expectedRevision,
                "p_fingerprint": request.fingerprint,
                "p_envelope_json": request.envelopeJSON
            ],
            options: [.sortedKeys]
        )
    }
}
