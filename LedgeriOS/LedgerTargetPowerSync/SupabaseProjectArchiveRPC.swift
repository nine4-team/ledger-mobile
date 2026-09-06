import Foundation
import LedgerTargetCore

public enum SupabaseProjectArchiveRPCFailure: Error, Equatable, Sendable {
    case invalidBaseURL
    case invalidPublishableKey
    case serviceRoleCredentialRefused
    case emptyAccessToken
    case invalidResponse
    case requestRejected(statusCode: Int)
    case resultMismatch
}

public final class SupabaseProjectArchiveRPC:
    ProjectArchiveCommandApplying, @unchecked Sendable
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
              ["http", "https"].contains(scheme),
              supabaseURL.host != nil,
              supabaseURL.user == nil,
              supabaseURL.password == nil,
              supabaseURL.query == nil,
              supabaseURL.fragment == nil else {
            throw SupabaseProjectArchiveRPCFailure.invalidBaseURL
        }
        guard !publishableKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SupabaseProjectArchiveRPCFailure.invalidPublishableKey
        }
        guard !Self.isServiceRoleCredential(publishableKey) else {
            throw SupabaseProjectArchiveRPCFailure.serviceRoleCredentialRefused
        }
        rpcURL = supabaseURL.appendingPathComponent("rest/v1/rpc/spike_archive_project")
        self.publishableKey = publishableKey
        self.accessTokenProvider = accessTokenProvider
        self.session = session
    }

    public func apply(
        _ request: ProjectArchiveUploadRequest
    ) async throws -> ProjectArchiveServerResult {
        guard let operationId = try? OperationID(validating: request.operationId),
              let accountId = try? AccountID(validating: request.accountId),
              ProjectArchiveOperationIdentity.isValid(
                operationId,
                accountId: accountId
              ) else {
            throw SupabaseProjectArchiveRPCFailure.resultMismatch
        }
        let token = try await accessTokenProvider()
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SupabaseProjectArchiveRPCFailure.emptyAccessToken
        }
        guard !Self.isServiceRoleCredential(token) else {
            throw SupabaseProjectArchiveRPCFailure.serviceRoleCredentialRefused
        }

        var urlRequest = URLRequest(url: rpcURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(
            "application/vnd.pgrst.object+json",
            forHTTPHeaderField: "Accept"
        )
        urlRequest.setValue(publishableKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try ProjectArchiveRPCBody(request: request).encodedData()

        let (data, response) = try await session.data(for: urlRequest)
        guard let response = response as? HTTPURLResponse else {
            throw SupabaseProjectArchiveRPCFailure.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw SupabaseProjectArchiveRPCFailure.requestRejected(
                statusCode: response.statusCode
            )
        }
        let result: ProjectArchiveServerResult
        do {
            result = try JSONDecoder().decode(ProjectArchiveServerResult.self, from: data)
        } catch {
            throw SupabaseProjectArchiveRPCFailure.invalidResponse
        }
        guard LedgerPowerSyncUploadConnector.isValidArchiveResult(
            result,
            request: request
        ) else {
            throw SupabaseProjectArchiveRPCFailure.resultMismatch
        }
        return result
    }

    static func isKnownRejectionCode(_ code: String) -> Bool {
        knownRejectionCodes.contains(code)
    }

    private static let knownRejectionCodes: Set<String> = [
        "contract_unsupported",
        "project_archive_command_encoding_invalid",
        "project_archive_envelope_mismatch",
        "project_archive_fingerprint_mismatch",
        "project_archive_payload_invalid",
        "project_archive_revision_conflict"
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
              let role = object["role"] as? String else {
            return false
        }
        return role == "service_role"
    }
}

private struct ProjectArchiveRPCBody {
    let request: ProjectArchiveUploadRequest

    func encodedData() throws -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let createdAt = formatter.string(from: Date(
            timeIntervalSince1970: Double(request.clientCreatedAtMilliseconds) / 1_000
        ))
        return try JSONSerialization.data(
            withJSONObject: [
                "p_operation_id": request.operationId,
                "p_account_id": request.accountId,
                "p_actor_principal_id": request.actorPrincipalId,
                "p_contract_version": request.contractVersion,
                "p_project_captured_at": createdAt,
                "p_project_id": request.projectId,
                "p_expected_revision": request.expectedRevision,
                "p_fingerprint": request.fingerprint,
                "p_envelope_json": request.envelopeJSON
            ],
            options: [.sortedKeys]
        )
    }
}
