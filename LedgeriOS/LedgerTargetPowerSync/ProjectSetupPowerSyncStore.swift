import Foundation
import LedgerTargetCore
import PowerSync

public actor ProjectSetupPowerSyncStore: ProjectSetupOperating {
    private let database: any PowerSyncDatabaseProtocol
    private let now: @Sendable () -> Date

    public init(
        database: any PowerSyncDatabaseProtocol,
        now: @Sendable @escaping () -> Date = Date.init
    ) {
        self.database = database
        self.now = now
    }

    public func create(_ command: CreateProjectCommand) async throws -> OperationReceipt {
        let envelopeData = try OperationContractCodec.encode(command.envelope)
        let allocationsData = try OperationContractCodec.encode(
            command.draft.categoryAllocations
        )
        guard let envelopeJSON = String(data: envelopeData, encoding: .utf8),
              let allocationsJSON = String(data: allocationsData, encoding: .utf8) else {
            throw ProjectSetupFailure.invalidEncodedCommand
        }

        let acceptedAtMilliseconds = Self.milliseconds(now())
        let projectCreatedAtMilliseconds = Self.milliseconds(command.envelope.clientCreatedAt)
        let selectionKind: String
        let newClientDisplayName: String?
        switch command.draft.clientSelection {
        case .existing:
            selectionKind = "existing"
            newClientDisplayName = nil
        case .newClient(let payload):
            selectionKind = "new"
            newClientDisplayName = payload.displayName.rawValue
        }

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
                        throw OperationContractFailure.payloadMismatch(
                            command.envelope.operationId
                        )
                    }
                    guard let localState = LocalOperationState(
                        rawValue: existingOperation.1
                    ) else {
                        throw ProjectSetupFailure.localAcceptanceFailed
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
                        command.draft.projectId.rawValue,
                        acceptedAtMilliseconds,
                        acceptedAtMilliseconds
                    ]
                )

                if let newClientDisplayName {
                    _ = try transaction.execute(
                        sql: """
                        INSERT INTO \(LedgerPowerSyncTable.pendingClients) (
                          id, account_id, display_name, lifecycle, revision,
                          created_at_ms, updated_at_ms, created_by_principal_id,
                          operation_id
                        ) VALUES (?, ?, ?, 'active', 1, ?, ?, ?, ?)
                        """,
                        parameters: [
                            command.draft.clientSelection.clientId.rawValue,
                            command.envelope.accountId.rawValue,
                            newClientDisplayName,
                            acceptedAtMilliseconds,
                            acceptedAtMilliseconds,
                            command.envelope.actorPrincipalId.rawValue,
                            command.envelope.operationId.rawValue
                        ]
                    )
                }

                _ = try transaction.execute(
                    sql: """
                    INSERT INTO \(LedgerPowerSyncTable.pendingProjects) (
                      id, account_id, client_id, display_name, description,
                      lifecycle, revision, created_at_ms, updated_at_ms,
                      created_by_principal_id, operation_id
                    ) VALUES (?, ?, ?, ?, ?, 'active', 1, ?, ?, ?, ?)
                    """,
                    parameters: [
                        command.draft.projectId.rawValue,
                        command.envelope.accountId.rawValue,
                        command.draft.clientSelection.clientId.rawValue,
                        command.draft.displayName.rawValue,
                        command.draft.description,
                        acceptedAtMilliseconds,
                        acceptedAtMilliseconds,
                        command.envelope.actorPrincipalId.rawValue,
                        command.envelope.operationId.rawValue
                    ]
                )

                for allocation in command.draft.categoryAllocations {
                    _ = try transaction.execute(
                        sql: """
                        INSERT INTO \(LedgerPowerSyncTable.pendingProjectCategoryAllocations) (
                          id, account_id, project_id, category_id,
                          allocation_minor_units, allocation_currency, revision,
                          created_at_ms, updated_at_ms, created_by_principal_id,
                          operation_id
                        ) VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?)
                        """,
                        parameters: [
                            "\(command.envelope.operationId.rawValue):\(allocation.categoryId.rawValue)",
                            command.envelope.accountId.rawValue,
                            command.draft.projectId.rawValue,
                            allocation.categoryId.rawValue,
                            allocation.allocation?.minorUnits,
                            allocation.allocation?.currency.rawValue,
                            acceptedAtMilliseconds,
                            acceptedAtMilliseconds,
                            command.envelope.actorPrincipalId.rawValue,
                            command.envelope.operationId.rawValue
                        ]
                    )
                }

                _ = try transaction.execute(
                    sql: """
                    INSERT INTO \(LedgerPowerSyncTable.projectCommands) (
                      id, account_id, actor_principal_id, contract_version,
                      project_created_at_ms, project_id, client_selection_kind,
                      client_id, new_client_display_name, project_display_name,
                      description, category_allocations_json, fingerprint,
                      envelope_json
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    parameters: [
                        command.envelope.operationId.rawValue,
                        command.envelope.accountId.rawValue,
                        command.envelope.actorPrincipalId.rawValue,
                        command.envelope.contractVersion.rawValue,
                        projectCreatedAtMilliseconds,
                        command.draft.projectId.rawValue,
                        selectionKind,
                        command.draft.clientSelection.clientId.rawValue,
                        newClientDisplayName,
                        command.draft.displayName.rawValue,
                        command.draft.description,
                        allocationsJSON,
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
        } catch let failure as ProjectSetupFailure {
            throw failure
        } catch {
            throw ProjectSetupFailure.localAcceptanceFailed
        }
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded(.towardZero))
    }
}
