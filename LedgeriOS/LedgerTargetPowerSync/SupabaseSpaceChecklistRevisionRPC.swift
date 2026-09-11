import Foundation
import LedgerTargetCore

public enum SupabaseSpaceChecklistRevisionRPCFailure: Error, Equatable, Sendable {
    case invalidBaseURL
    case invalidPublishableKey
    case serviceRoleCredentialRefused
    case emptyAccessToken
    case invalidResponse
    case requestRejected(statusCode: Int)
    case resultMismatch
}

public final class SupabaseSpaceChecklistRevisionRPC:
    SpaceChecklistRevisionCommandApplying, @unchecked Sendable
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
            throw SupabaseSpaceChecklistRevisionRPCFailure.invalidBaseURL
        }
        guard !publishableKey.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw SupabaseSpaceChecklistRevisionRPCFailure.invalidPublishableKey
        }
        guard !Self.isServiceRoleCredential(publishableKey) else {
            throw SupabaseSpaceChecklistRevisionRPCFailure
                .serviceRoleCredentialRefused
        }
        rpcURL = supabaseURL.appendingPathComponent(
            "rest/v1/rpc/spike_revise_space_checklists"
        )
        self.publishableKey = publishableKey
        self.accessTokenProvider = accessTokenProvider
        self.session = session
    }

    public func apply(
        _ request: SpaceChecklistRevisionUploadRequest
    ) async throws -> SpaceChecklistRevisionServerResult {
        guard let operationId = try? OperationID(validating: request.operationId),
              let accountId = try? AccountID(validating: request.accountId),
              SpaceChecklistRevisionOperationIdentity.isValid(
                  operationId,
                  accountId: accountId
              ) else {
            throw SupabaseSpaceChecklistRevisionRPCFailure.resultMismatch
        }
        let token = try await accessTokenProvider()
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SupabaseSpaceChecklistRevisionRPCFailure.emptyAccessToken
        }
        guard !Self.isServiceRoleCredential(token) else {
            throw SupabaseSpaceChecklistRevisionRPCFailure
                .serviceRoleCredentialRefused
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
        urlRequest.httpBody = try Self.body(request)

        let (data, response) = try await session.data(for: urlRequest)
        guard let response = response as? HTTPURLResponse else {
            throw SupabaseSpaceChecklistRevisionRPCFailure.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw SupabaseSpaceChecklistRevisionRPCFailure.requestRejected(
                statusCode: response.statusCode
            )
        }
        let result: SpaceChecklistRevisionServerResult
        do {
            result = try JSONDecoder().decode(
                SpaceChecklistRevisionServerResult.self,
                from: data
            )
        } catch {
            throw SupabaseSpaceChecklistRevisionRPCFailure.invalidResponse
        }
        guard LedgerPowerSyncUploadConnector.isValidSpaceChecklistRevisionResult(
            result,
            request: request
        ) else {
            throw SupabaseSpaceChecklistRevisionRPCFailure.resultMismatch
        }
        return result
    }

    static func isKnownRejectionCode(_ code: String) -> Bool {
        knownRejectionCodes.contains(code)
    }

    private static let knownRejectionCodes: Set<String> = [
        "contract_unsupported",
        "space_checklist_revision_command_encoding_invalid",
        "space_checklist_revision_payload_invalid",
        "space_checklist_revision_fingerprint_mismatch",
        "space_checklist_revision_envelope_mismatch",
        "space_checklist_revision_conflict"
    ]

    private static func body(
        _ request: SpaceChecklistRevisionUploadRequest
    ) throws -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let capturedAt = formatter.string(
            from: Date(
                timeIntervalSince1970:
                    Double(request.clientCreatedAtMilliseconds) / 1_000
            )
        )
        guard let collectionBytes = request.collectionJSON.data(using: .utf8),
              let collection = try? JSONSerialization.jsonObject(
                  with: collectionBytes
              ) else {
            throw SupabaseSpaceChecklistRevisionRPCFailure.resultMismatch
        }
        return try JSONSerialization.data(
            withJSONObject: [
                "p_operation_id": request.operationId,
                "p_account_id": request.accountId,
                "p_actor_principal_id": request.actorPrincipalId,
                "p_contract_version": request.contractVersion,
                "p_space_captured_at": capturedAt,
                "p_space_id": request.spaceId,
                "p_expected_revision": request.expectedRevision,
                "p_collection": collection,
                "p_fingerprint": request.fingerprint,
                "p_envelope_json": request.envelopeJSON
            ],
            options: [.sortedKeys]
        )
    }

    private static func isServiceRoleCredential(_ credential: String) -> Bool {
        if credential.hasPrefix("sb_secret_") { return true }
        let segments = credential.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard segments.count == 3 else { return false }
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let role = object["role"] as? String else {
            return false
        }
        return role == "service_role"
    }
}
