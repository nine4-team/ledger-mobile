import Foundation

public enum SupabaseClientCreationRPCFailure: Error, Equatable, Sendable {
    case invalidBaseURL
    case invalidPublishableKey
    case emptyAccessToken
    case invalidResponse
    case requestRejected(statusCode: Int)
    case resultMismatch
}

public final class SupabaseClientCreationRPC: ClientCreationCommandApplying, @unchecked Sendable {
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
            throw SupabaseClientCreationRPCFailure.invalidBaseURL
        }
        guard !publishableKey.isEmpty else {
            throw SupabaseClientCreationRPCFailure.invalidPublishableKey
        }
        rpcURL = supabaseURL
            .appendingPathComponent("rest/v1/rpc/spike_create_client")
        self.publishableKey = publishableKey
        self.accessTokenProvider = accessTokenProvider
        self.session = session
    }

    public func apply(_ request: ClientCreationUploadRequest) async throws -> ClientCreationServerResult {
        let token = try await accessTokenProvider()
        guard !token.isEmpty else {
            throw SupabaseClientCreationRPCFailure.emptyAccessToken
        }
        var urlRequest = URLRequest(url: rpcURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/vnd.pgrst.object+json", forHTTPHeaderField: "Accept")
        urlRequest.setValue(publishableKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(RPCBody(request: request))

        let (data, response) = try await session.data(for: urlRequest)
        guard let response = response as? HTTPURLResponse else {
            throw SupabaseClientCreationRPCFailure.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw SupabaseClientCreationRPCFailure.requestRejected(statusCode: response.statusCode)
        }
        let result = try JSONDecoder().decode(ClientCreationServerResult.self, from: data)
        guard result.operationId == request.operationId,
              result.accountId == request.accountId,
              result.commandFingerprint == request.fingerprint,
              result.subjectId == request.clientId else {
            throw SupabaseClientCreationRPCFailure.resultMismatch
        }
        return result
    }
}

private struct RPCBody: Encodable {
    let pOperationId: String
    let pAccountId: String
    let pActorPrincipalId: String
    let pContractVersion: String
    let pClientCreatedAt: String
    let pClientId: String
    let pDisplayName: String
    let pFingerprint: String
    let pEnvelopeJson: String

    init(request: ClientCreationUploadRequest) {
        pOperationId = request.operationId
        pAccountId = request.accountId
        pActorPrincipalId = request.actorPrincipalId
        pContractVersion = request.contractVersion
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        pClientCreatedAt = formatter.string(from: Date(
            timeIntervalSince1970: Double(request.clientCreatedAtMilliseconds) / 1_000
        ))
        pClientId = request.clientId
        pDisplayName = request.displayName
        pFingerprint = request.fingerprint
        pEnvelopeJson = request.envelopeJSON
    }

    enum CodingKeys: String, CodingKey {
        case pOperationId = "p_operation_id"
        case pAccountId = "p_account_id"
        case pActorPrincipalId = "p_actor_principal_id"
        case pContractVersion = "p_contract_version"
        case pClientCreatedAt = "p_client_created_at"
        case pClientId = "p_client_id"
        case pDisplayName = "p_display_name"
        case pFingerprint = "p_fingerprint"
        case pEnvelopeJson = "p_envelope_json"
    }
}
