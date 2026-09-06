import Foundation
import LedgerTargetCore
import PowerSync

enum ClientCreationPowerSyncStoreCheckpoint: Equatable, Sendable {
    case beforeTransaction
    case inventoryConstruction
    case inventoryRead
    case afterOwnershipInspection
    case operationWrite
    case projectionWrite
    case commandWrite
    case beforeCommit
    case afterCommit
}

actor ClientCreationPowerSyncStore: ClientCreationOperating {
    private let database: any PowerSyncDatabaseProtocol
    private let now: @Sendable () -> Date
    private let checkpoint: @Sendable (ClientCreationPowerSyncStoreCheckpoint) throws -> Void

    init(
        database: any PowerSyncDatabaseProtocol,
        now: @Sendable @escaping () -> Date = Date.init,
        checkpoint: @Sendable @escaping (ClientCreationPowerSyncStoreCheckpoint) throws -> Void = { _ in }
    ) {
        self.database = database
        self.now = now
        self.checkpoint = checkpoint
    }

    public func create(_ command: CreateClientCommand) async throws -> OperationReceipt {
        let envelopeData = try OperationContractCodec.encode(command.envelope)
        guard let envelopeJSON = String(data: envelopeData, encoding: .utf8) else {
            throw ClientCreationFailure.invalidEncodedCommand
        }
        let acceptedAtMilliseconds = Self.milliseconds(now())
        let clientCreatedAtMilliseconds = Self.milliseconds(command.envelope.clientCreatedAt)
        let testCheckpoint = checkpoint

        try Task.checkCancellation()
        do {
            try testCheckpoint(.beforeTransaction)
            let receipt = try await database.writeTransaction { transaction in
                try Task.checkCancellation()
                let ownership = try LocalOperationIdentityGuard.inspect(
                    transaction: transaction,
                    operationId: command.envelope.operationId,
                    expectedFamily: .createClient,
                    expectedFingerprint: command.fingerprint.sha256,
                    checkpoint: { point in
                        switch point {
                        case .inventoryConstruction:
                            try testCheckpoint(.inventoryConstruction)
                        case .inventoryRead:
                            try testCheckpoint(.inventoryRead)
                        }
                    }
                )
                try testCheckpoint(.afterOwnershipInspection)
                let existingOperation = try transaction.getOptional(
                    sql: """
                    SELECT account_id, actor_principal_id, contract_version,
                           fingerprint, subject_id, local_state, accepted_at_ms,
                           updated_at_ms, command_type,
                           command_envelope_json
                    FROM \(LedgerPowerSyncTable.localOperations)
                    WHERE id = ?
                    """,
                    parameters: [command.envelope.operationId.rawValue]
                ) { cursor in
                    try ClientCreationReplayRow(cursor: cursor)
                }

                if let existingOperation {
                    guard ownership == .matchingOwner,
                          existingOperation.fingerprint == command.fingerprint.sha256 else {
                        throw OperationContractFailure.payloadMismatch(command.envelope.operationId)
                    }
                    let hasTypedOwnership = existingOperation.commandType
                        == LocalOperationCommandFamily.createClient.rawValue
                        && existingOperation.envelopeJSON == envelopeJSON
                    let hasUnambiguousLegacyOwnership = existingOperation.commandType == nil
                        && existingOperation.envelopeJSON == nil
                    guard existingOperation.accountId == command.envelope.accountId.rawValue,
                          existingOperation.principalId == command.envelope.actorPrincipalId.rawValue,
                          existingOperation.contractVersion == command.envelope.contractVersion.rawValue,
                          existingOperation.subjectId == command.draft.clientId.rawValue,
                          hasTypedOwnership || hasUnambiguousLegacyOwnership,
                          let localState = LocalOperationState(rawValue: existingOperation.localState) else {
                        throw ClientCreationFailure.localAcceptanceFailed
                    }
                    let commands = try transaction.getAll(
                        sql: Self.replayCommandSQL,
                        parameters: [command.envelope.operationId.rawValue,
                                     LedgerPowerSyncTable.clientCommands]
                    ) { try ClientCreationReplayCommand(cursor: $0) }
                    let pending = try transaction.getAll(
                        sql: Self.replayPendingSQL,
                        parameters: [command.envelope.operationId.rawValue]
                    ) { try ClientCreationReplayPending(cursor: $0) }
                    guard commands.count <= 1, pending.count <= 1,
                          commands.allSatisfy({ $0.matches(
                            command,
                            envelopeJSON: envelopeJSON,
                            capturedAtMilliseconds: clientCreatedAtMilliseconds
                          ) }),
                          pending.allSatisfy({ $0.matches(
                            command,
                            acceptedAtMilliseconds: existingOperation.acceptedAt
                          ) }) else {
                        throw ClientCreationFailure.localAcceptanceFailed
                    }
                    if localState == .queued || localState == .applying {
                        guard commands.count == 1, pending.count == 1,
                              existingOperation.updatedAt >= existingOperation.acceptedAt else {
                            throw ClientCreationFailure.localAcceptanceFailed
                        }
                    } else if localState == .rejected {
                        guard commands.isEmpty, pending.isEmpty else {
                            throw ClientCreationFailure.localAcceptanceFailed
                        }
                    }
                    return OperationReceipt(
                        operationId: command.envelope.operationId,
                        localState: localState
                    )
                }
                guard ownership == .unclaimed else {
                    throw ClientCreationFailure.localAcceptanceFailed
                }

                try Task.checkCancellation()
                try testCheckpoint(.operationWrite)
                _ = try transaction.execute(
                    sql: """
                    INSERT INTO \(LedgerPowerSyncTable.localOperations) (
                      id, account_id, actor_principal_id, contract_version,
                      fingerprint, subject_id, local_state, accepted_at_ms,
                      updated_at_ms, command_type, command_envelope_json
                    ) VALUES (?, ?, ?, ?, ?, ?, 'queued', ?, ?, 'create_client', ?)
                    """,
                    parameters: [
                        command.envelope.operationId.rawValue,
                        command.envelope.accountId.rawValue,
                        command.envelope.actorPrincipalId.rawValue,
                        command.envelope.contractVersion.rawValue,
                        command.fingerprint.sha256,
                        command.draft.clientId.rawValue,
                        acceptedAtMilliseconds,
                        acceptedAtMilliseconds,
                        envelopeJSON
                    ]
                )

                try Task.checkCancellation()
                try testCheckpoint(.projectionWrite)
                _ = try transaction.execute(
                    sql: """
                    INSERT INTO \(LedgerPowerSyncTable.pendingClients) (
                      id, account_id, display_name, lifecycle, revision,
                      created_at_ms, updated_at_ms, created_by_principal_id,
                      operation_id
                    ) VALUES (?, ?, ?, 'active', 1, ?, ?, ?, ?)
                    """,
                    parameters: [
                        command.draft.clientId.rawValue,
                        command.envelope.accountId.rawValue,
                        command.draft.displayName.rawValue,
                        acceptedAtMilliseconds,
                        acceptedAtMilliseconds,
                        command.envelope.actorPrincipalId.rawValue,
                        command.envelope.operationId.rawValue
                    ]
                )

                try Task.checkCancellation()
                try testCheckpoint(.commandWrite)
                _ = try transaction.execute(
                    sql: """
                    INSERT INTO \(LedgerPowerSyncTable.clientCommands) (
                      id, account_id, actor_principal_id, contract_version,
                      client_created_at_ms, client_id, display_name, fingerprint,
                      envelope_json
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    parameters: [
                        command.envelope.operationId.rawValue,
                        command.envelope.accountId.rawValue,
                        command.envelope.actorPrincipalId.rawValue,
                        command.envelope.contractVersion.rawValue,
                        clientCreatedAtMilliseconds,
                        command.draft.clientId.rawValue,
                        command.draft.displayName.rawValue,
                        command.fingerprint.sha256,
                        envelopeJSON
                    ]
                )

                try Task.checkCancellation()
                try testCheckpoint(.beforeCommit)
                return OperationReceipt(
                    operationId: command.envelope.operationId,
                    localState: .queued
                )
            }
            try testCheckpoint(.afterCommit)
            try Task.checkCancellation()
            return try command.validate(receipt)
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as LocalOperationIdentityGuardFailure {
            if failure == .payloadMismatch {
                throw OperationContractFailure.payloadMismatch(command.envelope.operationId)
            }
            throw ClientCreationFailure.localAcceptanceFailed
        } catch let failure as OperationContractFailure {
            throw failure
        } catch let failure as ClientCreationFailure {
            throw failure
        } catch {
            throw ClientCreationFailure.localAcceptanceFailed
        }
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded(.towardZero))
    }

    private static let replayCommandSQL = """
        SELECT json_extract(data, '$.op') AS operation,
               json_extract(data, '$.data.account_id') AS account_id,
               json_extract(data, '$.data.actor_principal_id') AS actor_principal_id,
               json_extract(data, '$.data.contract_version') AS contract_version,
               json_extract(data, '$.data.client_created_at_ms') AS client_created_at_ms,
               json_extract(data, '$.data.client_id') AS client_id,
               json_extract(data, '$.data.display_name') AS display_name,
               json_extract(data, '$.data.fingerprint') AS fingerprint,
               json_extract(data, '$.data.envelope_json') AS envelope_json
        FROM ps_crud
        WHERE json_valid(data) = 1 AND json_extract(data, '$.id') = ?
          AND json_extract(data, '$.type') = ?
        """
    private static let replayPendingSQL = """
        SELECT id, account_id, display_name, lifecycle, revision, created_at_ms,
               updated_at_ms, created_by_principal_id, operation_id
        FROM \(LedgerPowerSyncTable.pendingClients) WHERE operation_id = ?
        """
}

private struct ClientCreationReplayRow {
    let accountId: String
    let principalId: String
    let contractVersion: String
    let fingerprint: String
    let subjectId: String
    let localState: String
    let acceptedAt: Int64
    let updatedAt: Int64
    let commandType: String?
    let envelopeJSON: String?

    init(cursor: any SqlCursor) throws {
        accountId = try cursor.getString(name: "account_id")
        principalId = try cursor.getString(name: "actor_principal_id")
        contractVersion = try cursor.getString(name: "contract_version")
        fingerprint = try cursor.getString(name: "fingerprint")
        subjectId = try cursor.getString(name: "subject_id")
        localState = try cursor.getString(name: "local_state")
        acceptedAt = try cursor.getInt64(name: "accepted_at_ms")
        updatedAt = try cursor.getInt64(name: "updated_at_ms")
        commandType = try cursor.getStringOptional(name: "command_type")
        envelopeJSON = try cursor.getStringOptional(name: "command_envelope_json")
    }
}

private struct ClientCreationReplayCommand {
    let operation: String; let accountId: String; let principalId: String
    let contractVersion: String; let capturedAt: Int64; let clientId: String
    let displayName: String; let fingerprint: String; let envelopeJSON: String
    init(cursor: any SqlCursor) throws {
        operation = try cursor.getString(name: "operation")
        accountId = try cursor.getString(name: "account_id")
        principalId = try cursor.getString(name: "actor_principal_id")
        contractVersion = try cursor.getString(name: "contract_version")
        capturedAt = try cursor.getInt64(name: "client_created_at_ms")
        clientId = try cursor.getString(name: "client_id")
        displayName = try cursor.getString(name: "display_name")
        fingerprint = try cursor.getString(name: "fingerprint")
        envelopeJSON = try cursor.getString(name: "envelope_json")
    }
    func matches(
        _ command: CreateClientCommand,
        envelopeJSON expectedEnvelope: String,
        capturedAtMilliseconds: Int64
    ) -> Bool {
        operation == "PUT" && accountId == command.envelope.accountId.rawValue
            && principalId == command.envelope.actorPrincipalId.rawValue
            && contractVersion == command.envelope.contractVersion.rawValue
            && capturedAt == capturedAtMilliseconds
            && clientId == command.draft.clientId.rawValue
            && displayName == command.draft.displayName.rawValue
            && fingerprint == command.fingerprint.sha256
            && envelopeJSON == expectedEnvelope
    }
}

private struct ClientCreationReplayPending {
    let id: String; let accountId: String; let displayName: String; let lifecycle: String
    let revision: Int64; let createdAt: Int64; let updatedAt: Int64
    let principalId: String; let operationId: String
    init(cursor: any SqlCursor) throws {
        id = try cursor.getString(name: "id")
        accountId = try cursor.getString(name: "account_id")
        displayName = try cursor.getString(name: "display_name")
        lifecycle = try cursor.getString(name: "lifecycle")
        revision = try cursor.getInt64(name: "revision")
        createdAt = try cursor.getInt64(name: "created_at_ms")
        updatedAt = try cursor.getInt64(name: "updated_at_ms")
        principalId = try cursor.getString(name: "created_by_principal_id")
        operationId = try cursor.getString(name: "operation_id")
    }
    func matches(_ command: CreateClientCommand, acceptedAtMilliseconds: Int64) -> Bool {
        id == command.draft.clientId.rawValue
            && accountId == command.envelope.accountId.rawValue
            && displayName == command.draft.displayName.rawValue && lifecycle == "active"
            && revision == 1 && createdAt == acceptedAtMilliseconds
            && updatedAt == acceptedAtMilliseconds
            && principalId == command.envelope.actorPrincipalId.rawValue
            && operationId == command.envelope.operationId.rawValue
    }
}
