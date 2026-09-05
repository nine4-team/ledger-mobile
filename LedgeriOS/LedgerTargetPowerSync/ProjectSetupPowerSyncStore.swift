import Foundation
import LedgerTargetCore
import PowerSync

actor ProjectSetupPowerSyncStore: ProjectSetupOperating {
    private let database: any PowerSyncDatabaseProtocol
    private let now: @Sendable () -> Date

    init(
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

                // Replay is deliberately resolved above. An operation accepted
                // before Client archive keeps its exact receipt; only a new
                // acceptance is subject to current effective lifecycle.
                if case .existing = command.draft.clientSelection {
                    let clientRows = try transaction.getAll(
                        sql: """
                        SELECT lifecycle
                        FROM (
                          SELECT authoritative.lifecycle, 0 AS source_order
                          FROM \(LedgerPowerSyncTable.clients) AS authoritative
                          WHERE authoritative.account_id = ? AND authoritative.id = ?
                          UNION ALL
                          SELECT pending.lifecycle, 1 AS source_order
                          FROM \(LedgerPowerSyncTable.pendingClients) AS pending
                          WHERE pending.account_id = ? AND pending.id = ?
                            AND pending.created_by_principal_id = ?
                            AND NOT EXISTS (
                              SELECT 1 FROM \(LedgerPowerSyncTable.clients) AS authoritative
                              WHERE authoritative.account_id = pending.account_id
                                AND authoritative.id = pending.id
                            )
                        )
                        ORDER BY source_order
                        """,
                        parameters: [
                            command.envelope.accountId.rawValue,
                            command.draft.clientSelection.clientId.rawValue,
                            command.envelope.accountId.rawValue,
                            command.draft.clientSelection.clientId.rawValue,
                            command.envelope.actorPrincipalId.rawValue
                        ]
                    ) { try $0.getString(name: "lifecycle") }
                    let archiveOverlayCount = try transaction.get(
                        sql: """
                        SELECT count(*)
                        FROM \(LedgerPowerSyncTable.clientArchiveOverlays)
                        WHERE account_id = ? AND client_id = ?
                        """,
                        parameters: [
                            command.envelope.accountId.rawValue,
                            command.draft.clientSelection.clientId.rawValue
                        ]
                    ) { try $0.getInt64(index: 0) }
                    let archiveOperationMissingOverlayCount = try transaction.get(
                        sql: """
                        SELECT count(*)
                        FROM \(LedgerPowerSyncTable.localOperations) AS operation
                        WHERE operation.account_id = ?
                          AND operation.subject_id = ?
                          AND operation.command_type = 'archive_client'
                          AND operation.local_state IN ('queued', 'applying', 'applied')
                          AND NOT EXISTS (
                            SELECT 1
                            FROM \(LedgerPowerSyncTable.clientArchiveOverlays) AS overlay
                            WHERE overlay.operation_id = operation.id
                              AND overlay.account_id = operation.account_id
                              AND overlay.actor_principal_id = operation.actor_principal_id
                              AND overlay.client_id = operation.subject_id
                              AND overlay.fingerprint = operation.fingerprint
                              AND overlay.expected_revision = operation.command_expected_revision
                              AND overlay.lifecycle = 'archived'
                          )
                          AND (
                            operation.local_state IN ('queued', 'applying')
                            OR (
                              operation.local_state = 'applied'
                              AND NOT (
                                operation.command_expected_revision IS NOT NULL
                                AND CAST(CAST(operation.command_expected_revision AS INTEGER) AS TEXT)
                                  = operation.command_expected_revision
                                AND CAST(operation.command_expected_revision AS INTEGER) > 0
                                AND CAST(operation.command_expected_revision AS INTEGER)
                                  < 9223372036854775807
                                AND EXISTS (
                                  SELECT 1
                                  FROM \(LedgerPowerSyncTable.clients) AS authoritative
                                  WHERE authoritative.account_id = operation.account_id
                                    AND authoritative.id = operation.subject_id
                                    AND (
                                      authoritative.revision
                                        > CAST(operation.command_expected_revision AS INTEGER) + 1
                                      OR (
                                        authoritative.revision
                                          = CAST(operation.command_expected_revision AS INTEGER) + 1
                                        AND authoritative.lifecycle = 'archived'
                                      )
                                    )
                                )
                              )
                            )
                          )
                        """,
                        parameters: [
                            command.envelope.accountId.rawValue,
                            command.draft.clientSelection.clientId.rawValue
                        ]
                    ) { try $0.getInt64(index: 0) }
                    // Some previously admitted typed selections predate a local
                    // Client row. Preserve that behavior while still refusing
                    // every represented non-active Client and every archive
                    // overlay. The trusted handler remains authoritative when
                    // the local Client row is absent.
                    guard clientRows.count <= 1,
                          clientRows.allSatisfy({ $0 == "active" }),
                          archiveOverlayCount == 0,
                          archiveOperationMissingOverlayCount == 0 else {
                        throw ProjectSetupFailure.localAcceptanceFailed
                    }
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
