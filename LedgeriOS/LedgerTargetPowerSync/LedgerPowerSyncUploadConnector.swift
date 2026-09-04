import Foundation
import PowerSync

public struct ClientCreationUploadRequest: Equatable, Sendable {
    public let operationId: String
    public let accountId: String
    public let actorPrincipalId: String
    public let contractVersion: String
    public let clientCreatedAtMilliseconds: Int64
    public let clientId: String
    public let displayName: String
    public let fingerprint: String
    public let envelopeJSON: String
}

public struct ClientCreationServerResult: Codable, Equatable, Sendable {
    public let operationId: String
    public let accountId: String
    public let commandFingerprint: String
    public let subjectId: String
    public let phase: String
    public let resultCode: String?
    public let errorCode: String?

    enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case accountId = "account_id"
        case commandFingerprint = "command_fingerprint"
        case subjectId = "subject_id"
        case phase
        case resultCode = "result_code"
        case errorCode = "error_code"
    }
}

public protocol ClientCreationCommandApplying: Sendable {
    func apply(_ request: ClientCreationUploadRequest) async throws -> ClientCreationServerResult
}

public final class LedgerPowerSyncUploadConnector: PowerSyncBackendConnectorProtocol, @unchecked Sendable {
    public typealias CredentialProvider = @Sendable () async throws -> PowerSyncCredentials?

    private let credentialProvider: CredentialProvider
    private let clientCreationApplier: any ClientCreationCommandApplying
    private let now: @Sendable () -> Date

    public init(
        credentialProvider: @escaping CredentialProvider,
        clientCreationApplier: any ClientCreationCommandApplying,
        now: @Sendable @escaping () -> Date = Date.init
    ) {
        self.credentialProvider = credentialProvider
        self.clientCreationApplier = clientCreationApplier
        self.now = now
    }

    public func fetchCredentials() async throws -> PowerSyncCredentials? {
        try await credentialProvider()
    }

    public func uploadData(database: any PowerSyncDatabaseProtocol) async throws {
        guard let transaction = try await database.getNextCrudTransaction() else { return }
        let request = try Self.clientCreationRequest(from: transaction.crud)
        let result = try await clientCreationApplier.apply(request)
        guard result.operationId == request.operationId,
              result.accountId == request.accountId,
              result.commandFingerprint == request.fingerprint,
              result.subjectId == request.clientId,
              result.phase == "applied" || result.phase == "rejected" else {
            throw LedgerPowerSyncUploadFailure.invalidServerResult
        }
        try await transaction.complete()
        _ = try await database.execute(
            sql: """
            UPDATE \(LedgerPowerSyncTable.localOperations)
            SET local_state = ?, updated_at_ms = ?
            WHERE id = ? AND fingerprint = ?
            """,
            parameters: [
                result.phase,
                Int64((now().timeIntervalSince1970 * 1_000).rounded(.towardZero)),
                request.operationId,
                request.fingerprint
            ]
        )
    }

    static func clientCreationRequest(from entries: [CrudEntry]) throws -> ClientCreationUploadRequest {
        guard entries.count == 2,
              let clientEntry = entries.first(where: { $0.table == LedgerPowerSyncTable.clients }),
              let commandEntry = entries.first(where: { $0.table == LedgerPowerSyncTable.clientCommands }),
              clientEntry.op == .put,
              commandEntry.op == .put,
              let clientData = clientEntry.opData,
              let commandData = commandEntry.opData else {
            throw LedgerPowerSyncUploadFailure.invalidTransactionShape
        }

        func required(_ key: String) throws -> String {
            guard let nested = commandData[key], let value = nested else {
                throw LedgerPowerSyncUploadFailure.missingCommandField(key)
            }
            return value
        }

        let request = ClientCreationUploadRequest(
            operationId: commandEntry.id,
            accountId: try required("account_id"),
            actorPrincipalId: try required("actor_principal_id"),
            contractVersion: try required("contract_version"),
            clientCreatedAtMilliseconds: try Self.parseMilliseconds(required("client_created_at_ms")),
            clientId: try required("client_id"),
            displayName: try required("display_name"),
            fingerprint: try required("fingerprint"),
            envelopeJSON: try required("envelope_json")
        )

        guard clientEntry.id == request.clientId,
              clientData["account_id"] ?? nil == request.accountId,
              clientData["display_name"] ?? nil == request.displayName,
              clientData["pending_operation_id"] ?? nil == request.operationId else {
            throw LedgerPowerSyncUploadFailure.optimisticClientMismatch
        }
        return request
    }

    private static func parseMilliseconds(_ value: String) throws -> Int64 {
        guard let milliseconds = Int64(value) else {
            throw LedgerPowerSyncUploadFailure.invalidClientCreatedAt
        }
        return milliseconds
    }
}

public enum LedgerPowerSyncUploadFailure: Error, Equatable, Sendable {
    case invalidTransactionShape
    case missingCommandField(String)
    case invalidClientCreatedAt
    case optimisticClientMismatch
    case invalidServerResult
}
