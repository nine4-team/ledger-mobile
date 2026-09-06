import CryptoKit
import Foundation
import LedgerTargetCore
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

public struct ProjectArchiveUploadRequest: Equatable, Sendable {
    public let operationId: String
    public let accountId: String
    public let actorPrincipalId: String
    public let contractVersion: String
    public let clientCreatedAtMilliseconds: Int64
    public let projectId: String
    public let expectedRevision: String
    public let fingerprint: String
    public let envelopeJSON: String
}

public struct ProjectArchiveServerResult: Codable, Equatable, Sendable {
    public let operationId: String
    public let accountId: String
    public let actorPrincipalId: String
    public let commandType: String
    public let contractVersion: String
    public let commandFingerprint: String
    public let envelopeSHA256: String
    public let requestSHA256: String
    public let subjectId: String
    public let phase: String
    public let resultCode: String?
    public let errorCode: String?
    public let clientCreatedAtMilliseconds: Int64
    public let serverReceivedAtMilliseconds: Int64
    public let completedAtMilliseconds: Int64

    enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case accountId = "account_id"
        case actorPrincipalId = "actor_principal_id"
        case commandType = "command_type"
        case contractVersion = "contract_version"
        case commandFingerprint = "command_fingerprint"
        case envelopeSHA256 = "envelope_sha256"
        case requestSHA256 = "request_sha256"
        case subjectId = "subject_id"
        case phase
        case resultCode = "result_code"
        case errorCode = "error_code"
        case clientCreatedAtMilliseconds = "client_created_at_ms"
        case serverReceivedAtMilliseconds = "server_received_at_ms"
        case completedAtMilliseconds = "completed_at_ms"
    }
}

public protocol ProjectArchiveCommandApplying: Sendable {
    func apply(_ request: ProjectArchiveUploadRequest) async throws -> ProjectArchiveServerResult
}

public struct ClientArchiveUploadRequest: Equatable, Sendable {
    public let operationId: String
    public let accountId: String
    public let actorPrincipalId: String
    public let contractVersion: String
    public let clientCreatedAtMilliseconds: Int64
    public let clientId: String
    public let expectedRevision: String
    public let fingerprint: String
    public let envelopeJSON: String

    public init(
        operationId: String,
        accountId: String,
        actorPrincipalId: String,
        contractVersion: String,
        clientCreatedAtMilliseconds: Int64,
        clientId: String,
        expectedRevision: String,
        fingerprint: String,
        envelopeJSON: String
    ) {
        self.operationId = operationId
        self.accountId = accountId
        self.actorPrincipalId = actorPrincipalId
        self.contractVersion = contractVersion
        self.clientCreatedAtMilliseconds = clientCreatedAtMilliseconds
        self.clientId = clientId
        self.expectedRevision = expectedRevision
        self.fingerprint = fingerprint
        self.envelopeJSON = envelopeJSON
    }
}

public struct ClientArchiveServerResult: Codable, Equatable, Sendable {
    public let operationId: String
    public let accountId: String
    public let actorPrincipalId: String
    public let commandType: String
    public let contractVersion: String
    public let commandFingerprint: String
    public let envelopeSHA256: String
    public let requestSHA256: String
    public let subjectId: String
    public let phase: String
    public let resultCode: String?
    public let errorCode: String?
    public let clientCreatedAtMilliseconds: Int64
    public let serverReceivedAtMilliseconds: Int64
    public let completedAtMilliseconds: Int64

    enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case accountId = "account_id"
        case actorPrincipalId = "actor_principal_id"
        case commandType = "command_type"
        case contractVersion = "contract_version"
        case commandFingerprint = "command_fingerprint"
        case envelopeSHA256 = "envelope_sha256"
        case requestSHA256 = "request_sha256"
        case subjectId = "subject_id"
        case phase
        case resultCode = "result_code"
        case errorCode = "error_code"
        case clientCreatedAtMilliseconds = "client_created_at_ms"
        case serverReceivedAtMilliseconds = "server_received_at_ms"
        case completedAtMilliseconds = "completed_at_ms"
    }
}

public protocol ClientArchiveCommandApplying: Sendable {
    func apply(_ request: ClientArchiveUploadRequest) async throws -> ClientArchiveServerResult
}

final class LedgerPowerSyncUploadConnector: PowerSyncBackendConnectorProtocol, @unchecked Sendable {
    public typealias CredentialProvider = @Sendable () async throws -> PowerSyncCredentials?

    private let credentialProvider: CredentialProvider
    private let clientCreationApplier: any ClientCreationCommandApplying
    private let projectCreationApplier: (any ProjectCreationCommandApplying)?
    private let projectArchiveApplier: (any ProjectArchiveCommandApplying)?
    private let clientArchiveApplier: (any ClientArchiveCommandApplying)?
    private let now: @Sendable () -> Date

    init(
        credentialProvider: @escaping CredentialProvider,
        clientCreationApplier: any ClientCreationCommandApplying,
        projectCreationApplier: (any ProjectCreationCommandApplying)? = nil,
        projectArchiveApplier: (any ProjectArchiveCommandApplying)? = nil,
        clientArchiveApplier: (any ClientArchiveCommandApplying)? = nil,
        now: @Sendable @escaping () -> Date = Date.init
    ) {
        self.credentialProvider = credentialProvider
        self.clientCreationApplier = clientCreationApplier
        self.projectCreationApplier = projectCreationApplier
        self.projectArchiveApplier = projectArchiveApplier
        self.clientArchiveApplier = clientArchiveApplier
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
        case LedgerPowerSyncTable.projectArchiveCommands:
            guard let projectArchiveApplier else {
                throw LedgerPowerSyncUploadFailure.unsupportedCommandTable(entry.table)
            }
            let request = try Self.projectArchiveRequest(from: transaction.crud)
            try await markArchiveApplying(request, database: database)
            let result: ProjectArchiveServerResult
            do {
                result = try await projectArchiveApplier.apply(request)
                guard Self.isValidArchiveResult(result, request: request) else {
                    throw LedgerPowerSyncUploadFailure.invalidServerResult
                }
            } catch {
                try? await resetArchiveAfterTransientFailure(request, database: database)
                throw error
            }
            try await recordArchiveResult(result, request: request, database: database)
        case LedgerPowerSyncTable.clientArchiveCommands:
            guard let clientArchiveApplier else {
                throw LedgerPowerSyncUploadFailure.unsupportedCommandTable(entry.table)
            }
            let request = try Self.clientArchiveRequest(from: transaction.crud)
            try await markClientArchiveApplying(request, database: database)
            let result: ClientArchiveServerResult
            do {
                result = try await clientArchiveApplier.apply(request)
                guard Self.isValidClientArchiveResult(result, request: request) else {
                    throw LedgerPowerSyncUploadFailure.invalidServerResult
                }
            } catch {
                try? await resetClientArchiveAfterTransientFailure(
                    request, database: database
                )
                throw error
            }
            try await recordClientArchiveResult(result, request: request, database: database)
        default:
            throw LedgerPowerSyncUploadFailure.unsupportedCommandTable(entry.table)
        }
        try await transaction.complete()
    }

    private func markArchiveApplying(
        _ request: ProjectArchiveUploadRequest,
        database: any PowerSyncDatabaseProtocol
    ) async throws {
        let observedAt = try Self.milliseconds(now())
        try await database.writeTransaction { local in
            let operation = try local.getOptional(
                sql: """
                SELECT account_id, actor_principal_id, contract_version,
                       fingerprint, subject_id, local_state, command_type,
                       accepted_at_ms, updated_at_ms,
                       command_expected_revision, command_envelope_json,
                       terminal_phase, terminal_result_code, terminal_error_code,
                       terminal_envelope_sha256, terminal_request_sha256,
                       terminal_server_received_at_ms, terminal_completed_at_ms
                FROM \(LedgerPowerSyncTable.localOperations)
                WHERE id = ?
                """,
                parameters: [request.operationId]
            ) { try ArchiveLocalOperationEvidence(cursor: $0) }
            guard let operation,
                  operation.accountId == request.accountId,
                  operation.actorPrincipalId == request.actorPrincipalId,
                  operation.contractVersion == request.contractVersion,
                  operation.fingerprint == request.fingerprint,
                  operation.subjectId == request.projectId,
                  operation.commandType == "archive_project",
                  operation.commandExpectedRevision == request.expectedRevision,
                  operation.commandEnvelopeJSON == request.envelopeJSON,
                  let state = LocalOperationState(rawValue: operation.localState) else {
                throw LedgerPowerSyncUploadFailure.localOperationMismatch
            }

            let overlays = try local.getAll(
                sql: """
                SELECT account_id, actor_principal_id, project_id,
                       operation_id, fingerprint, expected_revision,
                       projected_revision, lifecycle, accepted_at_ms
                FROM \(LedgerPowerSyncTable.projectArchiveOverlays)
                WHERE operation_id = ?
                """,
                parameters: [request.operationId]
            ) { try ArchiveOverlayEvidence(cursor: $0) }
            guard overlays.count <= 1 else {
                throw LedgerPowerSyncUploadFailure.pendingOverlayMismatch
            }
            if let overlay = overlays.first {
                guard overlay.matches(request, acceptedAtMilliseconds: operation.acceptedAtMilliseconds) else {
                    throw LedgerPowerSyncUploadFailure.pendingOverlayMismatch
                }
            }
            if state == .queued || state == .applying {
                guard overlays.count == 1,
                      operation.hasNoTerminalEvidence else {
                    throw LedgerPowerSyncUploadFailure.pendingOverlayMismatch
                }
            } else if state == .rejected {
                guard overlays.isEmpty else {
                    throw LedgerPowerSyncUploadFailure.pendingOverlayMismatch
                }
            }

            let creationOperationId = try local.getOptional(
                sql: """
                SELECT operation_id
                FROM \(LedgerPowerSyncTable.pendingProjects)
                WHERE account_id = ? AND id = ?
                """,
                parameters: [request.accountId, request.projectId]
            ) { cursor in try cursor.getString(name: "operation_id") }
            if let creationOperationId, creationOperationId != request.operationId {
                let creationState = try local.getOptional(
                    sql: """
                    SELECT local_state
                    FROM \(LedgerPowerSyncTable.localOperations)
                    WHERE id = ?
                    """,
                    parameters: [creationOperationId]
                ) { cursor in try cursor.getString(name: "local_state") }
                guard creationState == LocalOperationState.applied.rawValue else {
                    throw LedgerPowerSyncUploadFailure.pendingDependencyNotApplied
                }
            }

            switch state {
            case .queued:
                let updatedAt = max(
                    observedAt,
                    max(operation.acceptedAtMilliseconds, operation.updatedAtMilliseconds)
                )
                _ = try local.execute(
                    sql: """
                    UPDATE \(LedgerPowerSyncTable.localOperations)
                    SET local_state = 'applying', updated_at_ms = ?
                    WHERE id = ? AND fingerprint = ? AND local_state = 'queued'
                    """,
                    parameters: [updatedAt, request.operationId, request.fingerprint]
                )
            case .applying, .applied, .rejected:
                break
            case .superseded, .resolved:
                throw LedgerPowerSyncUploadFailure.localOperationMismatch
            }
        }
    }

    private func resetArchiveAfterTransientFailure(
        _ request: ProjectArchiveUploadRequest,
        database: any PowerSyncDatabaseProtocol
    ) async throws {
        let observedAt = try Self.milliseconds(now())
        try await database.writeTransaction { local in
            let times = try local.getOptional(
                sql: """
                SELECT accepted_at_ms, updated_at_ms
                FROM \(LedgerPowerSyncTable.localOperations)
                WHERE id = ? AND fingerprint = ? AND local_state = 'applying'
                """,
                parameters: [request.operationId, request.fingerprint]
            ) { cursor in
                (
                    try cursor.getInt64(name: "accepted_at_ms"),
                    try cursor.getInt64(name: "updated_at_ms")
                )
            }
            guard let times else { return }
            let updatedAt = max(observedAt, max(times.0, times.1))
            _ = try local.execute(
                sql: """
                UPDATE \(LedgerPowerSyncTable.localOperations)
                SET local_state = 'queued', updated_at_ms = ?
                WHERE id = ? AND fingerprint = ? AND local_state = 'applying'
                """,
                parameters: [updatedAt, request.operationId, request.fingerprint]
            )
        }
    }

    private func recordArchiveResult(
        _ result: ProjectArchiveServerResult,
        request: ProjectArchiveUploadRequest,
        database: any PowerSyncDatabaseProtocol
    ) async throws {
        let observedAt = try Self.milliseconds(now())
        try await database.writeTransaction { local in
            let operation = try local.getOptional(
                sql: """
                SELECT account_id, actor_principal_id, contract_version,
                       fingerprint, subject_id, local_state, command_type,
                       accepted_at_ms, updated_at_ms,
                       command_expected_revision, command_envelope_json,
                       terminal_phase, terminal_result_code, terminal_error_code,
                       terminal_envelope_sha256, terminal_request_sha256,
                       terminal_server_received_at_ms, terminal_completed_at_ms
                FROM \(LedgerPowerSyncTable.localOperations)
                WHERE id = ?
                """,
                parameters: [request.operationId]
            ) { try ArchiveLocalOperationEvidence(cursor: $0) }
            guard let operation,
                  operation.accountId == request.accountId,
                  operation.actorPrincipalId == request.actorPrincipalId,
                  operation.contractVersion == request.contractVersion,
                  operation.fingerprint == request.fingerprint,
                  operation.subjectId == request.projectId,
                  operation.commandType == "archive_project",
                  operation.commandExpectedRevision == request.expectedRevision,
                  operation.commandEnvelopeJSON == request.envelopeJSON,
                  let previousState = LocalOperationState(rawValue: operation.localState) else {
                throw LedgerPowerSyncUploadFailure.localOperationMismatch
            }
            let terminalState = LocalOperationState(rawValue: result.phase)!
            let updatedAt = max(
                observedAt,
                max(operation.acceptedAtMilliseconds, operation.updatedAtMilliseconds)
            )
            if previousState == .applied || previousState == .rejected {
                guard previousState == terminalState,
                      operation.terminalPhase == result.phase,
                      operation.terminalResultCode == result.resultCode,
                      operation.terminalErrorCode == result.errorCode,
                      operation.terminalEnvelopeSHA256 == result.envelopeSHA256,
                      operation.terminalRequestSHA256 == result.requestSHA256,
                      operation.terminalServerReceivedAtMilliseconds
                        == result.serverReceivedAtMilliseconds,
                      operation.terminalCompletedAtMilliseconds
                        == result.completedAtMilliseconds else {
                    throw LedgerPowerSyncUploadFailure.invalidServerResult
                }
            } else {
                guard previousState == .applying || previousState == .queued else {
                    throw LedgerPowerSyncUploadFailure.localOperationMismatch
                }
                guard operation.terminalPhase == nil,
                      operation.terminalResultCode == nil,
                      operation.terminalErrorCode == nil,
                      operation.terminalEnvelopeSHA256 == nil,
                      operation.terminalRequestSHA256 == nil,
                      operation.terminalServerReceivedAtMilliseconds == nil,
                      operation.terminalCompletedAtMilliseconds == nil else {
                    throw LedgerPowerSyncUploadFailure.localOperationMismatch
                }
                if terminalState == .rejected {
                    let overlays = try local.getAll(
                        sql: """
                        SELECT account_id, actor_principal_id, project_id,
                               operation_id, fingerprint, expected_revision
                        FROM \(LedgerPowerSyncTable.projectArchiveOverlays)
                        WHERE operation_id = ?
                        """,
                        parameters: [request.operationId]
                    ) { cursor in
                        (
                            try cursor.getString(name: "account_id"),
                            try cursor.getString(name: "actor_principal_id"),
                            try cursor.getString(name: "project_id"),
                            try cursor.getString(name: "operation_id"),
                            try cursor.getString(name: "fingerprint"),
                            try cursor.getString(name: "expected_revision")
                        )
                    }
                    guard overlays.count == 1,
                          overlays[0].0 == request.accountId,
                          overlays[0].1 == request.actorPrincipalId,
                          overlays[0].2 == request.projectId,
                          overlays[0].3 == request.operationId,
                          overlays[0].4 == request.fingerprint,
                          overlays[0].5 == request.expectedRevision else {
                        throw LedgerPowerSyncUploadFailure.pendingOverlayMismatch
                    }
                }
                _ = try local.execute(
                    sql: """
                    UPDATE \(LedgerPowerSyncTable.localOperations)
                    SET local_state = ?, updated_at_ms = ?, terminal_phase = ?,
                        terminal_result_code = ?, terminal_error_code = ?,
                        terminal_envelope_sha256 = ?,
                        terminal_request_sha256 = ?,
                        terminal_server_received_at_ms = ?,
                        terminal_completed_at_ms = ?
                    WHERE id = ? AND fingerprint = ?
                    """,
                    parameters: [
                        result.phase, updatedAt, result.phase,
                        result.resultCode, result.errorCode, result.envelopeSHA256,
                        result.requestSHA256,
                        result.serverReceivedAtMilliseconds,
                        result.completedAtMilliseconds,
                        request.operationId, request.fingerprint
                    ]
                )
                if terminalState == .rejected {
                    _ = try local.execute(
                        sql: """
                        DELETE FROM \(LedgerPowerSyncTable.projectArchiveOverlays)
                        WHERE operation_id = ? AND account_id = ? AND project_id = ?
                          AND fingerprint = ?
                        """,
                        parameters: [
                            request.operationId, request.accountId,
                            request.projectId, request.fingerprint
                        ]
                    )
                }
            }
        }
    }

    private func markClientArchiveApplying(
        _ request: ClientArchiveUploadRequest,
        database: any PowerSyncDatabaseProtocol
    ) async throws {
        let observedAt = try Self.milliseconds(now())
        try await database.writeTransaction { local in
            let operation = try local.getOptional(
                sql: Self.archiveOperationEvidenceSQL,
                parameters: [request.operationId]
            ) { try ArchiveLocalOperationEvidence(cursor: $0) }
            guard let operation,
                  operation.accountId == request.accountId,
                  operation.actorPrincipalId == request.actorPrincipalId,
                  operation.contractVersion == request.contractVersion,
                  operation.fingerprint == request.fingerprint,
                  operation.subjectId == request.clientId,
                  operation.commandType == "archive_client",
                  operation.commandExpectedRevision == request.expectedRevision,
                  operation.commandEnvelopeJSON == request.envelopeJSON,
                  let state = LocalOperationState(rawValue: operation.localState) else {
                throw LedgerPowerSyncUploadFailure.localOperationMismatch
            }
            let overlays = try local.getAll(
                sql: """
                SELECT account_id, actor_principal_id, client_id, operation_id,
                       fingerprint, expected_revision, projected_revision,
                       lifecycle, accepted_at_ms
                FROM \(LedgerPowerSyncTable.clientArchiveOverlays)
                WHERE operation_id = ?
                """,
                parameters: [request.operationId]
            ) { try ClientArchiveOverlayEvidence(cursor: $0) }
            guard overlays.count <= 1 else {
                throw LedgerPowerSyncUploadFailure.pendingOverlayMismatch
            }
            if let overlay = overlays.first {
                guard overlay.matches(
                    request, acceptedAtMilliseconds: operation.acceptedAtMilliseconds
                ) else { throw LedgerPowerSyncUploadFailure.pendingOverlayMismatch }
            }
            if state == .queued || state == .applying {
                guard overlays.count == 1, operation.hasNoTerminalEvidence else {
                    throw LedgerPowerSyncUploadFailure.pendingOverlayMismatch
                }
            } else if state == .rejected {
                guard overlays.isEmpty else {
                    throw LedgerPowerSyncUploadFailure.pendingOverlayMismatch
                }
            }

            let dependencies = try local.getAll(
                sql: """
                SELECT DISTINCT dependency.operation_id, operation.local_state
                FROM (
                  SELECT operation_id
                  FROM \(LedgerPowerSyncTable.pendingClients)
                  WHERE account_id = ? AND id = ? AND operation_id <> ?
                  UNION ALL
                  SELECT operation_id
                  FROM \(LedgerPowerSyncTable.pendingProjects)
                  WHERE account_id = ? AND client_id = ? AND operation_id <> ?
                ) AS dependency
                LEFT JOIN \(LedgerPowerSyncTable.localOperations) AS operation
                  ON operation.id = dependency.operation_id
                """,
                parameters: [
                    request.accountId, request.clientId, request.operationId,
                    request.accountId, request.clientId, request.operationId
                ]
            ) {
                (try $0.getString(name: "operation_id"),
                 try $0.getStringOptional(name: "local_state"))
            }
            for dependency in dependencies {
                guard let rawState = dependency.1,
                      let dependencyState = LocalOperationState(rawValue: rawState) else {
                    throw LedgerPowerSyncUploadFailure.localOperationMismatch
                }
                if dependencyState == .queued || dependencyState == .applying {
                    throw LedgerPowerSyncUploadFailure.pendingDependencyNotApplied
                }
            }

            switch state {
            case .queued:
                let updatedAt = max(
                    observedAt,
                    max(operation.acceptedAtMilliseconds, operation.updatedAtMilliseconds)
                )
                _ = try local.execute(
                    sql: """
                    UPDATE \(LedgerPowerSyncTable.localOperations)
                    SET local_state = 'applying', updated_at_ms = ?
                    WHERE id = ? AND fingerprint = ? AND local_state = 'queued'
                    """,
                    parameters: [updatedAt, request.operationId, request.fingerprint]
                )
            case .applying, .applied, .rejected: break
            case .superseded, .resolved:
                throw LedgerPowerSyncUploadFailure.localOperationMismatch
            }
        }
    }

    private func resetClientArchiveAfterTransientFailure(
        _ request: ClientArchiveUploadRequest,
        database: any PowerSyncDatabaseProtocol
    ) async throws {
        let observedAt = try Self.milliseconds(now())
        try await database.writeTransaction { local in
            let times = try local.getOptional(
                sql: """
                SELECT accepted_at_ms, updated_at_ms
                FROM \(LedgerPowerSyncTable.localOperations)
                WHERE id = ? AND fingerprint = ? AND local_state = 'applying'
                """,
                parameters: [request.operationId, request.fingerprint]
            ) { (try $0.getInt64(index: 0), try $0.getInt64(index: 1)) }
            guard let times else { return }
            _ = try local.execute(
                sql: """
                UPDATE \(LedgerPowerSyncTable.localOperations)
                SET local_state = 'queued', updated_at_ms = ?
                WHERE id = ? AND fingerprint = ? AND local_state = 'applying'
                """,
                parameters: [
                    max(observedAt, max(times.0, times.1)),
                    request.operationId, request.fingerprint
                ]
            )
        }
    }

    private func recordClientArchiveResult(
        _ result: ClientArchiveServerResult,
        request: ClientArchiveUploadRequest,
        database: any PowerSyncDatabaseProtocol
    ) async throws {
        let observedAt = try Self.milliseconds(now())
        try await database.writeTransaction { local in
            let operation = try local.getOptional(
                sql: Self.archiveOperationEvidenceSQL,
                parameters: [request.operationId]
            ) { try ArchiveLocalOperationEvidence(cursor: $0) }
            guard let operation,
                  operation.accountId == request.accountId,
                  operation.actorPrincipalId == request.actorPrincipalId,
                  operation.contractVersion == request.contractVersion,
                  operation.fingerprint == request.fingerprint,
                  operation.subjectId == request.clientId,
                  operation.commandType == "archive_client",
                  operation.commandExpectedRevision == request.expectedRevision,
                  operation.commandEnvelopeJSON == request.envelopeJSON,
                  let previousState = LocalOperationState(rawValue: operation.localState),
                  let terminalState = LocalOperationState(rawValue: result.phase) else {
                throw LedgerPowerSyncUploadFailure.localOperationMismatch
            }
            let updatedAt = max(
                observedAt,
                max(operation.acceptedAtMilliseconds, operation.updatedAtMilliseconds)
            )
            if previousState == .applied || previousState == .rejected {
                guard previousState == terminalState,
                      operation.terminalPhase == result.phase,
                      operation.terminalResultCode == result.resultCode,
                      operation.terminalErrorCode == result.errorCode,
                      operation.terminalEnvelopeSHA256 == result.envelopeSHA256,
                      operation.terminalRequestSHA256 == result.requestSHA256,
                      operation.terminalServerReceivedAtMilliseconds == result.serverReceivedAtMilliseconds,
                      operation.terminalCompletedAtMilliseconds == result.completedAtMilliseconds else {
                    throw LedgerPowerSyncUploadFailure.invalidServerResult
                }
                return
            }
            guard previousState == .queued || previousState == .applying,
                  operation.hasNoTerminalEvidence else {
                throw LedgerPowerSyncUploadFailure.localOperationMismatch
            }
            if terminalState == .rejected {
                let overlays = try local.getAll(
                    sql: """
                    SELECT account_id, actor_principal_id, client_id, operation_id,
                           fingerprint, expected_revision, projected_revision,
                           lifecycle, accepted_at_ms
                    FROM \(LedgerPowerSyncTable.clientArchiveOverlays)
                    WHERE operation_id = ?
                    """,
                    parameters: [request.operationId]
                ) { try ClientArchiveOverlayEvidence(cursor: $0) }
                guard overlays.count == 1,
                      overlays[0].matches(
                          request,
                          acceptedAtMilliseconds: operation.acceptedAtMilliseconds
                      ) else { throw LedgerPowerSyncUploadFailure.pendingOverlayMismatch }
            }
            _ = try local.execute(
                sql: """
                UPDATE \(LedgerPowerSyncTable.localOperations)
                SET local_state = ?, updated_at_ms = ?, terminal_phase = ?,
                    terminal_result_code = ?, terminal_error_code = ?,
                    terminal_envelope_sha256 = ?, terminal_request_sha256 = ?,
                    terminal_server_received_at_ms = ?, terminal_completed_at_ms = ?
                WHERE id = ? AND fingerprint = ?
                """,
                parameters: [
                    result.phase, updatedAt, result.phase, result.resultCode,
                    result.errorCode, result.envelopeSHA256, result.requestSHA256,
                    result.serverReceivedAtMilliseconds, result.completedAtMilliseconds,
                    request.operationId, request.fingerprint
                ]
            )
            if terminalState == .rejected {
                _ = try local.execute(
                    sql: """
                    DELETE FROM \(LedgerPowerSyncTable.clientArchiveOverlays)
                    WHERE operation_id = ? AND account_id = ? AND client_id = ?
                      AND fingerprint = ?
                    """,
                    parameters: [
                        request.operationId, request.accountId,
                        request.clientId, request.fingerprint
                    ]
                )
            }
        }
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

    static func projectArchiveRequest(from entries: [CrudEntry]) throws -> ProjectArchiveUploadRequest {
        guard entries.count == 1,
              let commandEntry = entries.first,
              commandEntry.table == LedgerPowerSyncTable.projectArchiveCommands,
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

        let request = ProjectArchiveUploadRequest(
            operationId: commandEntry.id,
            accountId: try required("account_id"),
            actorPrincipalId: try required("actor_principal_id"),
            contractVersion: try required("contract_version"),
            clientCreatedAtMilliseconds: try Self.parseMilliseconds(
                required("client_created_at_ms")
            ),
            projectId: try required("project_id"),
            expectedRevision: try required("expected_revision"),
            fingerprint: try required("fingerprint"),
            envelopeJSON: try required("envelope_json")
        )
        guard let revision = UInt64(request.expectedRevision),
              String(revision) == request.expectedRevision,
              revision > 0,
              revision < UInt64(Int64.max),
              let typedOperationId = try? OperationID(validating: request.operationId),
              let typedAccountId = try? AccountID(validating: request.accountId),
              ProjectArchiveOperationIdentity.isValid(
                typedOperationId,
                accountId: typedAccountId
              ),
              let envelopeData = request.envelopeJSON.data(using: .utf8),
              let envelope = try? OperationContractCodec.decode(
                OperationEnvelope<ArchiveProjectPayload>.self,
                from: envelopeData
              ),
              envelope.operationId.rawValue == request.operationId,
              envelope.accountId.rawValue == request.accountId,
              envelope.actorPrincipalId.rawValue == request.actorPrincipalId,
              envelope.contractVersion.rawValue == request.contractVersion,
              envelope.payload.projectId.rawValue == request.projectId,
              envelope.clientCreatedAt == Date(
                timeIntervalSince1970: Double(request.clientCreatedAtMilliseconds) / 1_000
              ),
              envelope.preconditions == [
                .expectedRevision(
                    subject: LedgerEntityReference(
                        kind: .project,
                        id: try EntityID(validating: request.projectId)
                    ),
                    revision: revision
                )
              ],
              let fingerprint = try? OperationFingerprint(validating: request.fingerprint),
              (try? OperationFingerprint.make(for: envelope)) == fingerprint else {
            throw LedgerPowerSyncUploadFailure.invalidArchiveCommand
        }
        return request
    }

    static func clientArchiveRequest(from entries: [CrudEntry]) throws -> ClientArchiveUploadRequest {
        guard entries.count == 1,
              let commandEntry = entries.first,
              commandEntry.table == LedgerPowerSyncTable.clientArchiveCommands,
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
        let request = ClientArchiveUploadRequest(
            operationId: commandEntry.id,
            accountId: try required("account_id"),
            actorPrincipalId: try required("actor_principal_id"),
            contractVersion: try required("contract_version"),
            clientCreatedAtMilliseconds: try Self.parseMilliseconds(
                required("client_created_at_ms")
            ),
            clientId: try required("client_id"),
            expectedRevision: try required("expected_revision"),
            fingerprint: try required("fingerprint"),
            envelopeJSON: try required("envelope_json")
        )
        guard let revision = UInt64(request.expectedRevision),
              String(revision) == request.expectedRevision,
              revision > 0, revision < UInt64(Int64.max),
              let operationId = try? OperationID(validating: request.operationId),
              let accountId = try? AccountID(validating: request.accountId),
              ClientArchiveOperationIdentity.isValid(operationId, accountId: accountId),
              let envelopeData = request.envelopeJSON.data(using: .utf8),
              let envelope = try? OperationContractCodec.decode(
                  OperationEnvelope<ArchiveClientPayload>.self,
                  from: envelopeData
              ),
              (try? OperationContractCodec.encode(envelope)) == envelopeData,
              envelope.operationId.rawValue == request.operationId,
              envelope.accountId.rawValue == request.accountId,
              envelope.actorPrincipalId.rawValue == request.actorPrincipalId,
              envelope.contractVersion.rawValue == request.contractVersion,
              envelope.payload.clientId.rawValue == request.clientId,
              envelope.clientCreatedAt == Date(
                  timeIntervalSince1970: Double(request.clientCreatedAtMilliseconds) / 1_000
              ),
              envelope.preconditions == [
                  .expectedRevision(
                      subject: LedgerEntityReference(
                          kind: .client,
                          id: try EntityID(validating: request.clientId)
                      ),
                      revision: revision
                  )
              ],
              let fingerprint = try? OperationFingerprint(validating: request.fingerprint),
              (try? OperationFingerprint.make(for: envelope)) == fingerprint else {
            throw LedgerPowerSyncUploadFailure.invalidArchiveCommand
        }
        return request
    }

    static func isValidArchiveResult(
        _ result: ProjectArchiveServerResult,
        request: ProjectArchiveUploadRequest
    ) -> Bool {
        guard result.operationId == request.operationId,
              result.accountId == request.accountId,
              result.actorPrincipalId == request.actorPrincipalId,
              result.commandType == "archive_project",
              result.contractVersion == request.contractVersion,
              result.commandFingerprint == request.fingerprint,
              result.envelopeSHA256 == request.fingerprint,
              result.requestSHA256 == archiveRequestSHA256(request),
              result.subjectId == request.projectId,
              result.clientCreatedAtMilliseconds == request.clientCreatedAtMilliseconds,
              result.completedAtMilliseconds >= result.serverReceivedAtMilliseconds else {
            return false
        }
        switch result.phase {
        case "applied":
            return result.resultCode == "project_archived" && result.errorCode == nil
        case "rejected":
            return result.resultCode == nil
                && result.errorCode.map(SupabaseProjectArchiveRPC.isKnownRejectionCode) == true
        default:
            return false
        }
    }

    static func archiveRequestSHA256(_ request: ProjectArchiveUploadRequest) -> String {
        let fields = [
            request.operationId,
            request.accountId,
            request.actorPrincipalId,
            request.contractVersion,
            String(request.clientCreatedAtMilliseconds),
            request.projectId,
            request.expectedRevision,
            request.fingerprint,
            request.envelopeJSON
        ]
        var material = Data("project-archive-request-v1|".utf8)
        for field in fields {
            let bytes = Data(field.utf8)
            material.append(contentsOf: Data("v\(bytes.count):".utf8))
            material.append(bytes)
        }
        return SHA256.hash(data: material)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func isValidClientArchiveResult(
        _ result: ClientArchiveServerResult,
        request: ClientArchiveUploadRequest
    ) -> Bool {
        guard result.operationId == request.operationId,
              result.accountId == request.accountId,
              result.actorPrincipalId == request.actorPrincipalId,
              result.commandType == "archive_client",
              result.contractVersion == request.contractVersion,
              result.commandFingerprint == request.fingerprint,
              result.envelopeSHA256 == request.fingerprint,
              result.requestSHA256 == clientArchiveRequestSHA256(request),
              result.subjectId == request.clientId,
              result.clientCreatedAtMilliseconds == request.clientCreatedAtMilliseconds,
              result.serverReceivedAtMilliseconds >= 0,
              result.completedAtMilliseconds >= result.serverReceivedAtMilliseconds else {
            return false
        }
        switch result.phase {
        case "applied":
            return result.resultCode == "client_archived" && result.errorCode == nil
        case "rejected":
            return result.resultCode == nil
                && result.errorCode.map(SupabaseClientArchiveRPC.isKnownRejectionCode) == true
        default: return false
        }
    }

    static func clientArchiveRequestSHA256(_ request: ClientArchiveUploadRequest) -> String {
        let fields = [
            request.operationId, request.accountId, request.actorPrincipalId,
            request.contractVersion, String(request.clientCreatedAtMilliseconds),
            request.clientId, request.expectedRevision, request.fingerprint,
            request.envelopeJSON
        ]
        var material = Data("client-archive-request-v1|".utf8)
        for field in fields {
            let bytes = Data(field.utf8)
            material.append(contentsOf: Data("v\(bytes.count):".utf8))
            material.append(bytes)
        }
        return SHA256.hash(data: material)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static let archiveOperationEvidenceSQL = """
        SELECT account_id, actor_principal_id, contract_version,
               fingerprint, subject_id, local_state, command_type,
               accepted_at_ms, updated_at_ms, command_expected_revision,
               command_envelope_json, terminal_phase, terminal_result_code,
               terminal_error_code, terminal_envelope_sha256,
               terminal_request_sha256, terminal_server_received_at_ms,
               terminal_completed_at_ms
        FROM \(LedgerPowerSyncTable.localOperations)
        WHERE id = ?
        """

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

    private static func milliseconds(_ date: Date) throws -> Int64 {
        let value = date.timeIntervalSince1970 * 1_000
        guard value.isFinite,
              let milliseconds = Int64(exactly: value.rounded(.towardZero)),
              milliseconds >= 0 else {
            throw LedgerPowerSyncUploadFailure.invalidClientCreatedAt
        }
        return milliseconds
    }
}

private struct ArchiveLocalOperationEvidence {
    let accountId: String
    let actorPrincipalId: String
    let contractVersion: String
    let fingerprint: String
    let subjectId: String
    let localState: String
    let acceptedAtMilliseconds: Int64
    let updatedAtMilliseconds: Int64
    let commandType: String?
    let commandExpectedRevision: String?
    let commandEnvelopeJSON: String?
    let terminalPhase: String?
    let terminalResultCode: String?
    let terminalErrorCode: String?
    let terminalEnvelopeSHA256: String?
    let terminalRequestSHA256: String?
    let terminalServerReceivedAtMilliseconds: Int64?
    let terminalCompletedAtMilliseconds: Int64?

    init(cursor: any SqlCursor) throws {
        accountId = try cursor.getString(name: "account_id")
        actorPrincipalId = try cursor.getString(name: "actor_principal_id")
        contractVersion = try cursor.getString(name: "contract_version")
        fingerprint = try cursor.getString(name: "fingerprint")
        subjectId = try cursor.getString(name: "subject_id")
        localState = try cursor.getString(name: "local_state")
        acceptedAtMilliseconds = try cursor.getInt64(name: "accepted_at_ms")
        updatedAtMilliseconds = try cursor.getInt64(name: "updated_at_ms")
        commandType = try cursor.getStringOptional(name: "command_type")
        commandExpectedRevision = try cursor.getStringOptional(
            name: "command_expected_revision"
        )
        commandEnvelopeJSON = try cursor.getStringOptional(name: "command_envelope_json")
        terminalPhase = try cursor.getStringOptional(name: "terminal_phase")
        terminalResultCode = try cursor.getStringOptional(name: "terminal_result_code")
        terminalErrorCode = try cursor.getStringOptional(name: "terminal_error_code")
        terminalEnvelopeSHA256 = try cursor.getStringOptional(
            name: "terminal_envelope_sha256"
        )
        terminalRequestSHA256 = try cursor.getStringOptional(
            name: "terminal_request_sha256"
        )
        terminalServerReceivedAtMilliseconds = try cursor.getInt64Optional(
            name: "terminal_server_received_at_ms"
        )
        terminalCompletedAtMilliseconds = try cursor.getInt64Optional(
            name: "terminal_completed_at_ms"
        )
    }

    var hasNoTerminalEvidence: Bool {
        terminalPhase == nil
            && terminalResultCode == nil
            && terminalErrorCode == nil
            && terminalEnvelopeSHA256 == nil
            && terminalRequestSHA256 == nil
            && terminalServerReceivedAtMilliseconds == nil
            && terminalCompletedAtMilliseconds == nil
    }
}

private struct ArchiveOverlayEvidence {
    let accountId: String
    let actorPrincipalId: String
    let projectId: String
    let operationId: String
    let fingerprint: String
    let expectedRevision: String
    let projectedRevision: Int64
    let lifecycle: String
    let acceptedAtMilliseconds: Int64

    init(cursor: any SqlCursor) throws {
        accountId = try cursor.getString(name: "account_id")
        actorPrincipalId = try cursor.getString(name: "actor_principal_id")
        projectId = try cursor.getString(name: "project_id")
        operationId = try cursor.getString(name: "operation_id")
        fingerprint = try cursor.getString(name: "fingerprint")
        expectedRevision = try cursor.getString(name: "expected_revision")
        projectedRevision = try cursor.getInt64(name: "projected_revision")
        lifecycle = try cursor.getString(name: "lifecycle")
        acceptedAtMilliseconds = try cursor.getInt64(name: "accepted_at_ms")
    }

    func matches(
        _ request: ProjectArchiveUploadRequest,
        acceptedAtMilliseconds expectedAcceptedAt: Int64
    ) -> Bool {
        guard let revision = Int64(request.expectedRevision), revision > 0 else { return false }
        return accountId == request.accountId
            && actorPrincipalId == request.actorPrincipalId
            && projectId == request.projectId
            && operationId == request.operationId
            && fingerprint == request.fingerprint
            && expectedRevision == request.expectedRevision
            && projectedRevision == revision + 1
            && lifecycle == "archived"
            && acceptedAtMilliseconds == expectedAcceptedAt
    }
}

private struct ClientArchiveOverlayEvidence {
    let accountId: String
    let actorPrincipalId: String
    let clientId: String
    let operationId: String
    let fingerprint: String
    let expectedRevision: String
    let projectedRevision: Int64
    let lifecycle: String
    let acceptedAtMilliseconds: Int64

    init(cursor: any SqlCursor) throws {
        accountId = try cursor.getString(name: "account_id")
        actorPrincipalId = try cursor.getString(name: "actor_principal_id")
        clientId = try cursor.getString(name: "client_id")
        operationId = try cursor.getString(name: "operation_id")
        fingerprint = try cursor.getString(name: "fingerprint")
        expectedRevision = try cursor.getString(name: "expected_revision")
        projectedRevision = try cursor.getInt64(name: "projected_revision")
        lifecycle = try cursor.getString(name: "lifecycle")
        acceptedAtMilliseconds = try cursor.getInt64(name: "accepted_at_ms")
    }

    func matches(
        _ request: ClientArchiveUploadRequest,
        acceptedAtMilliseconds expectedAcceptedAt: Int64
    ) -> Bool {
        guard let revision = Int64(request.expectedRevision), revision > 0 else {
            return false
        }
        return accountId == request.accountId
            && actorPrincipalId == request.actorPrincipalId
            && clientId == request.clientId
            && operationId == request.operationId
            && fingerprint == request.fingerprint
            && expectedRevision == request.expectedRevision
            && projectedRevision == revision + 1
            && lifecycle == "archived"
            && acceptedAtMilliseconds == expectedAcceptedAt
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
    case pendingDependencyNotApplied
    case invalidArchiveCommand
}
