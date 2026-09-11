import Foundation

public enum SupabaseProjectCreationRPCFailure: Error, Equatable, Sendable {
    case invalidBaseURL
    case invalidPublishableKey
    case emptyAccessToken
    case invalidResponse
    case requestRejected(statusCode: Int)
    case resultMismatch
}

public final class SupabaseProjectCreationRPC: ProjectCreationCommandApplying, @unchecked Sendable {
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
        guard let scheme = supabaseURL.scheme,
              ["http", "https"].contains(scheme),
              supabaseURL.host != nil else {
            throw SupabaseProjectCreationRPCFailure.invalidBaseURL
        }
        guard !publishableKey.isEmpty else {
            throw SupabaseProjectCreationRPCFailure.invalidPublishableKey
        }
        rpcURL = supabaseURL.appendingPathComponent("rest/v1/rpc/spike_create_project")
        self.publishableKey = publishableKey
        self.accessTokenProvider = accessTokenProvider
        self.session = session
    }

    public func apply(_ request: ProjectCreationUploadRequest) async throws -> ProjectCreationServerResult {
        let token = try await accessTokenProvider()
        guard !token.isEmpty else {
            throw SupabaseProjectCreationRPCFailure.emptyAccessToken
        }
        var urlRequest = URLRequest(url: rpcURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/vnd.pgrst.object+json", forHTTPHeaderField: "Accept")
        urlRequest.setValue(publishableKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try ProjectRPCBody(request: request).encodedData()

        let (data, response) = try await session.data(for: urlRequest)
        guard let response = response as? HTTPURLResponse else {
            throw SupabaseProjectCreationRPCFailure.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw SupabaseProjectCreationRPCFailure.requestRejected(
                statusCode: response.statusCode
            )
        }
        let result = try JSONDecoder().decode(ProjectCreationServerResult.self, from: data)
        guard result.operationId == request.operationId,
              result.accountId == request.accountId,
              result.commandFingerprint == request.fingerprint,
              result.subjectId == request.projectId else {
            throw SupabaseProjectCreationRPCFailure.resultMismatch
        }
        return result
    }
}

private struct ProjectRPCBody {
    let pOperationId: String
    let pAccountId: String
    let pActorPrincipalId: String
    let pContractVersion: String
    let pProjectCreatedAt: String
    let pProjectId: String
    let pClientSelectionKind: String
    let pClientId: String
    let pNewClientDisplayName: String?
    let pProjectDisplayName: String
    let pDescription: String?
    let pCategoryAllocationsJSON: String
    let pFingerprint: String
    let pEnvelopeJson: String

    init(request: ProjectCreationUploadRequest) {
        pOperationId = request.operationId
        pAccountId = request.accountId
        pActorPrincipalId = request.actorPrincipalId
        pContractVersion = request.contractVersion
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        pProjectCreatedAt = formatter.string(from: Date(
            timeIntervalSince1970: Double(request.projectCreatedAtMilliseconds) / 1_000
        ))
        pProjectId = request.projectId
        pClientSelectionKind = request.clientSelectionKind
        pClientId = request.clientId
        pNewClientDisplayName = request.newClientDisplayName
        pProjectDisplayName = request.projectDisplayName
        pDescription = request.description
        pCategoryAllocationsJSON = request.categoryAllocationsJSON
        pFingerprint = request.fingerprint
        pEnvelopeJson = request.envelopeJSON
    }

    func encodedData() throws -> Data {
        guard let allocationBytes = pCategoryAllocationsJSON.data(using: .utf8),
              let allocations = try JSONSerialization.jsonObject(
                with: allocationBytes
              ) as? [[String: Any]] else {
            throw SupabaseProjectCreationRPCFailure.invalidResponse
        }
        return try JSONSerialization.data(withJSONObject: [
            "p_operation_id": pOperationId,
            "p_account_id": pAccountId,
            "p_actor_principal_id": pActorPrincipalId,
            "p_contract_version": pContractVersion,
            "p_project_created_at": pProjectCreatedAt,
            "p_project_id": pProjectId,
            "p_client_selection_kind": pClientSelectionKind,
            "p_client_id": pClientId,
            "p_new_client_display_name": (pNewClientDisplayName as Any?) ?? NSNull(),
            "p_project_display_name": pProjectDisplayName,
            "p_description": (pDescription as Any?) ?? NSNull(),
            "p_category_allocations": allocations,
            "p_fingerprint": pFingerprint,
            "p_envelope_json": pEnvelopeJson
        ])
    }
}
