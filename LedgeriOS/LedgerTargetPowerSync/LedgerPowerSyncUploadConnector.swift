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

public struct ProjectCreationUploadRequest: Equatable, Sendable {
    public let operationId: String
    public let accountId: String
    public let actorPrincipalId: String
    public let contractVersion: String
    public let projectCreatedAtMilliseconds: Int64
    public let projectId: String
    public let clientSelectionKind: String
    public let clientId: String
    public let newClientDisplayName: String?
    public let projectDisplayName: String
    public let description: String?
    public let categoryAllocationsJSON: String
    public let fingerprint: String
    public let envelopeJSON: String
}

public struct ProjectCreationServerResult: Codable, Equatable, Sendable {
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

public protocol ProjectCreationCommandApplying: Sendable {
    func apply(_ request: ProjectCreationUploadRequest) async throws -> ProjectCreationServerResult
}

final class LedgerPowerSyncUploadConnector: PowerSyncBackendConnectorProtocol, @unchecked Sendable {
    public typealias CredentialProvider = @Sendable () async throws -> PowerSyncCredentials?

    private let credentialProvider: CredentialProvider
    private let clientCreationApplier: any ClientCreationCommandApplying
    private let projectCreationApplier: (any ProjectCreationCommandApplying)?
    private let now: @Sendable () -> Date

    init(
        credentialProvider: @escaping CredentialProvider,
        clientCreationApplier: any ClientCreationCommandApplying,
        projectCreationApplier: (any ProjectCreationCommandApplying)? = nil,
        now: @Sendable @escaping () -> Date = Date.init
    ) {
        self.credentialProvider = credentialProvider
        self.clientCreationApplier = clientCreationApplier
        self.projectCreationApplier = projectCreationApplier
        self.now = now
    }

    public func fetchCredentials() async throws -> PowerSyncCredentials? {
        try await credentialProvider()
    }

    public func uploadData(database: any PowerSyncDatabaseProtocol) async throws {
        guard let transaction = try await database.getNextCrudTransaction() else { return }
        guard transaction.crud.count == 1, let entry = transaction.crud.first else {
            throw LedgerPowerSyncUploadFailure.invalidTransactionShape
        }
        switch entry.table {
        case LedgerPowerSyncTable.clientCommands:
            let request = try Self.clientCreationRequest(from: transaction.crud)
            let result = try await clientCreationApplier.apply(request)
            guard result.operationId == request.operationId,
                  result.accountId == request.accountId,
                  result.commandFingerprint == request.fingerprint,
                  result.subjectId == request.clientId,
                  Self.isValidTerminalResult(
                    phase: result.phase,
                    resultCode: result.resultCode,
                    errorCode: result.errorCode
                  ) else {
                throw LedgerPowerSyncUploadFailure.invalidServerResult
            }
            try await recordClientResult(result, request: request, database: database)
        case LedgerPowerSyncTable.projectCommands:
            guard let projectCreationApplier else {
                throw LedgerPowerSyncUploadFailure.unsupportedCommandTable(entry.table)
            }
            let request = try Self.projectCreationRequest(from: transaction.crud)
            let result = try await projectCreationApplier.apply(request)
            guard result.operationId == request.operationId,
                  result.accountId == request.accountId,
                  result.commandFingerprint == request.fingerprint,
                  result.subjectId == request.projectId,
                  Self.isValidTerminalResult(
                    phase: result.phase,
                    resultCode: result.resultCode,
                    errorCode: result.errorCode
                  ) else {
                throw LedgerPowerSyncUploadFailure.invalidServerResult
            }
            try await recordProjectResult(result, request: request, database: database)
        default:
            throw LedgerPowerSyncUploadFailure.unsupportedCommandTable(entry.table)
        }
        try await transaction.complete()
    }

    private func recordClientResult(
        _ result: ClientCreationServerResult,
        request: ClientCreationUploadRequest,
        database: any PowerSyncDatabaseProtocol
    ) async throws {
        try await database.writeTransaction { local in
            let operationFingerprint = try local.getOptional(
                sql: "SELECT fingerprint FROM \(LedgerPowerSyncTable.localOperations) WHERE id = ?",
                parameters: [request.operationId]
            ) { cursor in
                try cursor.getString(name: "fingerprint")
            }
            guard operationFingerprint == request.fingerprint else {
                throw LedgerPowerSyncUploadFailure.localOperationMismatch
            }
            _ = try local.execute(
                sql: """
                UPDATE \(LedgerPowerSyncTable.localOperations)
                SET local_state = ?, updated_at_ms = ?
                WHERE id = ? AND fingerprint = ?
                """,
                parameters: [
                    result.phase,
                    Int64((self.now().timeIntervalSince1970 * 1_000).rounded(.towardZero)),
                    request.operationId,
                    request.fingerprint
                ]
            )
            if result.phase == "rejected" {
                let overlayOperationId = try local.getOptional(
                    sql: "SELECT operation_id FROM \(LedgerPowerSyncTable.pendingClients) WHERE id = ?",
                    parameters: [request.clientId]
                ) { cursor in
                    try cursor.getString(name: "operation_id")
                }
                guard overlayOperationId == request.operationId else {
                    throw LedgerPowerSyncUploadFailure.pendingOverlayMismatch
                }
                _ = try local.execute(
                    sql: """
                    DELETE FROM \(LedgerPowerSyncTable.pendingClients)
                    WHERE id = ? AND operation_id = ?
                    """,
                    parameters: [request.clientId, request.operationId]
                )
            }
        }
    }

    private func recordProjectResult(
        _ result: ProjectCreationServerResult,
        request: ProjectCreationUploadRequest,
        database: any PowerSyncDatabaseProtocol
    ) async throws {
        try await database.writeTransaction { local in
            let operationFingerprint = try local.getOptional(
                sql: "SELECT fingerprint FROM \(LedgerPowerSyncTable.localOperations) WHERE id = ?",
                parameters: [request.operationId]
            ) { cursor in
                try cursor.getString(name: "fingerprint")
            }
            guard operationFingerprint == request.fingerprint else {
                throw LedgerPowerSyncUploadFailure.localOperationMismatch
            }
            _ = try local.execute(
                sql: """
                UPDATE \(LedgerPowerSyncTable.localOperations)
                SET local_state = ?, updated_at_ms = ?
                WHERE id = ? AND fingerprint = ?
                """,
                parameters: [
                    result.phase,
                    Int64((self.now().timeIntervalSince1970 * 1_000).rounded(.towardZero)),
                    request.operationId,
                    request.fingerprint
                ]
            )
            if result.phase == "rejected" {
                let projectOverlayOperationId = try local.getOptional(
                    sql: "SELECT operation_id FROM \(LedgerPowerSyncTable.pendingProjects) WHERE id = ?",
                    parameters: [request.projectId]
                ) { cursor in
                    try cursor.getString(name: "operation_id")
                }
                guard projectOverlayOperationId == request.operationId else {
                    throw LedgerPowerSyncUploadFailure.pendingOverlayMismatch
                }
                _ = try local.execute(
                    sql: """
                    DELETE FROM \(LedgerPowerSyncTable.pendingProjects)
                    WHERE id = ? AND operation_id = ?
                    """,
                    parameters: [request.projectId, request.operationId]
                )
                _ = try local.execute(
                    sql: """
                    DELETE FROM \(LedgerPowerSyncTable.pendingProjectCategoryAllocations)
                    WHERE project_id = ? AND operation_id = ?
                    """,
                    parameters: [request.projectId, request.operationId]
                )
                if request.clientSelectionKind == "new" {
                    let clientOverlayOperationId = try local.getOptional(
                        sql: "SELECT operation_id FROM \(LedgerPowerSyncTable.pendingClients) WHERE id = ?",
                        parameters: [request.clientId]
                    ) { cursor in
                        try cursor.getString(name: "operation_id")
                    }
                    guard clientOverlayOperationId == request.operationId else {
                        throw LedgerPowerSyncUploadFailure.pendingOverlayMismatch
                    }
                    _ = try local.execute(
                        sql: """
                        DELETE FROM \(LedgerPowerSyncTable.pendingClients)
                        WHERE id = ? AND operation_id = ?
                        """,
                        parameters: [request.clientId, request.operationId]
                    )
                }
            }
        }
    }

    static func clientCreationRequest(from entries: [CrudEntry]) throws -> ClientCreationUploadRequest {
        guard entries.count == 1,
              let commandEntry = entries.first,
              commandEntry.table == LedgerPowerSyncTable.clientCommands,
              commandEntry.op == .put,
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

        return request
    }

    static func projectCreationRequest(from entries: [CrudEntry]) throws -> ProjectCreationUploadRequest {
        guard entries.count == 1,
              let commandEntry = entries.first,
              commandEntry.table == LedgerPowerSyncTable.projectCommands,
              commandEntry.op == .put,
              let commandData = commandEntry.opData else {
            throw LedgerPowerSyncUploadFailure.invalidTransactionShape
        }

        func required(_ key: String) throws -> String {
            guard let nested = commandData[key], let value = nested else {
                throw LedgerPowerSyncUploadFailure.missingCommandField(key)
            }
            return value
        }

        return ProjectCreationUploadRequest(
            operationId: commandEntry.id,
            accountId: try required("account_id"),
            actorPrincipalId: try required("actor_principal_id"),
            contractVersion: try required("contract_version"),
            projectCreatedAtMilliseconds: try Self.parseMilliseconds(
                required("project_created_at_ms")
            ),
            projectId: try required("project_id"),
            clientSelectionKind: try required("client_selection_kind"),
            clientId: try required("client_id"),
            newClientDisplayName: commandData["new_client_display_name"] ?? nil,
            projectDisplayName: try required("project_display_name"),
            description: commandData["description"] ?? nil,
            categoryAllocationsJSON: try required("category_allocations_json"),
            fingerprint: try required("fingerprint"),
            envelopeJSON: try required("envelope_json")
        )
    }

    private static func isValidTerminalResult(
        phase: String,
        resultCode: String?,
        errorCode: String?
    ) -> Bool {
        switch phase {
        case "applied":
            return resultCode?.isEmpty == false && errorCode == nil
        case "rejected":
            return resultCode == nil && errorCode?.isEmpty == false
        default:
            return false
        }
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
    case invalidServerResult
    case unsupportedCommandTable(String)
    case localOperationMismatch
    case pendingOverlayMismatch
}
