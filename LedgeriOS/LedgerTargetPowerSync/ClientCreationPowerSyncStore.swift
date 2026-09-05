import Foundation
import LedgerTargetCore
import PowerSync

actor ClientCreationPowerSyncStore: ClientCreationOperating {
    private let database: any PowerSyncDatabaseProtocol
    private let now: @Sendable () -> Date

    init(
        database: any PowerSyncDatabaseProtocol,
        now: @Sendable @escaping () -> Date = Date.init
    ) {
        self.database = database
        self.now = now
    }

    public func create(_ command: CreateClientCommand) async throws -> OperationReceipt {
        let envelopeData = try OperationContractCodec.encode(command.envelope)
        guard let envelopeJSON = String(data: envelopeData, encoding: .utf8) else {
            throw ClientCreationFailure.invalidEncodedCommand
        }
        let acceptedAtMilliseconds = Self.milliseconds(now())
        let clientCreatedAtMilliseconds = Self.milliseconds(command.envelope.clientCreatedAt)

        do {
            let receipt = try await database.writeTransaction { transaction in
                let existingOperation = try transaction.getOptional(
                    sql: """
                    SELECT fingerprint, local_state
                    FROM \(LedgerPowerSyncTable.localOperations)
                    WHERE id = ?
                    """,
                    parameters: [command.envelope.operationId.rawValue]
                ) { cursor in
                    (
                        try cursor.getString(name: "fingerprint"),
                        try cursor.getString(name: "local_state")
                    )
                }

                if let existingOperation {
                    guard existingOperation.0 == command.fingerprint.sha256 else {
                        throw OperationContractFailure.payloadMismatch(command.envelope.operationId)
                    }
                    guard let localState = LocalOperationState(rawValue: existingOperation.1) else {
                        throw ClientCreationFailure.localAcceptanceFailed
                    }
                    return OperationReceipt(
                        operationId: command.envelope.operationId,
                        localState: localState
                    )
                }

                _ = try transaction.execute(
                    sql: """
                    INSERT INTO \(LedgerPowerSyncTable.localOperations) (
                      id, account_id, actor_principal_id, contract_version,
                      fingerprint, subject_id, local_state, accepted_at_ms,
                      updated_at_ms
                    ) VALUES (?, ?, ?, ?, ?, ?, 'queued', ?, ?)
                    """,
                    parameters: [
                        command.envelope.operationId.rawValue,
                        command.envelope.accountId.rawValue,
                        command.envelope.actorPrincipalId.rawValue,
                        command.envelope.contractVersion.rawValue,
                        command.fingerprint.sha256,
                        command.draft.clientId.rawValue,
                        acceptedAtMilliseconds,
                        acceptedAtMilliseconds
                    ]
                )

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

                return OperationReceipt(
                    operationId: command.envelope.operationId,
                    localState: .queued
                )
            }
            return try command.validate(receipt)
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
}
