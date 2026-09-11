import Foundation
import LedgerTargetCore
import PowerSync

enum ProjectSetupPowerSyncFailure: Error, Equatable, Sendable {
    case malformedLocalEvidence
    case operationNotFound
    case workspaceScopeRequired
}

enum ProjectSetupPowerSyncStoreCheckpoint: Equatable, Sendable {
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

actor ProjectSetupPowerSyncStore: ProjectSetupOperating {
    private let database: any PowerSyncDatabaseProtocol
    private let accountId: AccountID?
    private let principalId: PrincipalID?
    private let now: @Sendable () -> Date
    private let checkpoint: @Sendable (ProjectSetupPowerSyncStoreCheckpoint) throws -> Void
    private let watchRegistry = ProjectSetupOperationWatchRegistry()

    init(
        database: any PowerSyncDatabaseProtocol,
        accountId: AccountID? = nil,
        principalId: PrincipalID? = nil,
        now: @Sendable @escaping () -> Date = Date.init,
        checkpoint: @Sendable @escaping (ProjectSetupPowerSyncStoreCheckpoint) throws -> Void = { _ in }
    ) {
        self.database = database
        self.accountId = accountId
        self.principalId = principalId
        self.now = now
        self.checkpoint = checkpoint
    }

    public func create(_ command: CreateProjectCommand) async throws -> OperationReceipt {
        if let accountId, command.envelope.accountId != accountId {
            throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
        }
        if let principalId, command.envelope.actorPrincipalId != principalId {
            throw LedgerOfflineClientRuntimeFailure.principalScopeMismatch
        }
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
        let testCheckpoint = checkpoint

        try Task.checkCancellation()
        do {
            try testCheckpoint(.beforeTransaction)
            let receipt = try await database.writeTransaction { transaction in
                try Task.checkCancellation()
                let ownership = try LocalOperationIdentityGuard.inspect(
                    transaction: transaction,
                    operationId: command.envelope.operationId,
                    expectedFamily: .createProject,
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
                    try ProjectSetupReplayRow(cursor: cursor)
                }

                if let existingOperation {
                    guard ownership == .matchingOwner,
                          existingOperation.fingerprint == command.fingerprint.sha256 else {
                        throw OperationContractFailure.payloadMismatch(
                            command.envelope.operationId
                        )
                    }
                    let hasTypedOwnership = existingOperation.commandType
                        == LocalOperationCommandFamily.createProject.rawValue
                        && existingOperation.envelopeJSON == envelopeJSON
                    let hasUnambiguousLegacyOwnership = existingOperation.commandType == nil
                        && existingOperation.envelopeJSON == nil
                    guard existingOperation.accountId == command.envelope.accountId.rawValue,
                          existingOperation.principalId == command.envelope.actorPrincipalId.rawValue,
                          existingOperation.contractVersion == command.envelope.contractVersion.rawValue,
                          existingOperation.subjectId == command.draft.projectId.rawValue,
                          hasTypedOwnership || hasUnambiguousLegacyOwnership,
                          let localState = LocalOperationState(rawValue: existingOperation.localState) else {
                        throw ProjectSetupFailure.localAcceptanceFailed
                    }
                    let commands = try transaction.getAll(
                        sql: Self.replayCommandSQL,
                        parameters: [command.envelope.operationId.rawValue,
                                     LedgerPowerSyncTable.projectCommands]
                    ) { try ProjectSetupReplayCommand(cursor: $0) }
                    let projects = try transaction.getAll(
                        sql: Self.replayProjectSQL,
                        parameters: [command.envelope.operationId.rawValue]
                    ) { try ProjectSetupReplayProject(cursor: $0) }
                    let clients = try transaction.getAll(
                        sql: Self.replayClientSQL,
                        parameters: [command.envelope.operationId.rawValue]
                    ) { try ProjectSetupReplayClient(cursor: $0) }
                    let allocations = try transaction.getAll(
                        sql: Self.replayAllocationSQL,
                        parameters: [command.envelope.operationId.rawValue]
                    ) { try ProjectSetupReplayAllocation(cursor: $0) }
                    let expectsClient = command.draft.clientSelection.newClientDisplayName != nil
                    let pendingGraphIsComplete = projects.count == 1
                        && clients.count == (expectsClient ? 1 : 0)
                        && ProjectSetupReplayAllocation.matches(
                            allocations, command: command,
                            acceptedAtMilliseconds: existingOperation.acceptedAt
                        )
                    let terminalRowsMatch = projects.allSatisfy({ $0.matches(
                        command, acceptedAtMilliseconds: existingOperation.acceptedAt
                    ) }) && clients.allSatisfy({ $0.matches(
                        command, acceptedAtMilliseconds: existingOperation.acceptedAt
                    ) }) && ProjectSetupReplayAllocation.matchesPresent(
                        allocations, command: command,
                        acceptedAtMilliseconds: existingOperation.acceptedAt
                    )
                    let pendingGraphMatches = localState == .queued || localState == .applying
                        ? pendingGraphIsComplete
                        : terminalRowsMatch
                    guard commands.count <= 1, projects.count <= 1, clients.count <= 1,
                          commands.allSatisfy({ $0.matches(
                            command, envelopeJSON: envelopeJSON,
                            allocationsJSON: allocationsJSON,
                            capturedAtMilliseconds: projectCreatedAtMilliseconds
                          ) }),
                          projects.allSatisfy({ $0.matches(
                            command, acceptedAtMilliseconds: existingOperation.acceptedAt
                          ) }),
                          clients.allSatisfy({ $0.matches(
                            command, acceptedAtMilliseconds: existingOperation.acceptedAt
                          ) }),
                          pendingGraphMatches else {
                        throw ProjectSetupFailure.localAcceptanceFailed
                    }
                    if localState == .queued || localState == .applying {
                        guard commands.count == 1, projects.count == 1,
                              clients.count == (expectsClient ? 1 : 0),
                              existingOperation.updatedAt >= existingOperation.acceptedAt else {
                            throw ProjectSetupFailure.localAcceptanceFailed
                        }
                    } else if localState == .rejected {
                        guard commands.isEmpty, projects.isEmpty, clients.isEmpty,
                              allocations.isEmpty else {
                            throw ProjectSetupFailure.localAcceptanceFailed
                        }
                    }
                    return OperationReceipt(
                        operationId: command.envelope.operationId,
                        localState: localState
                    )
                }
                guard ownership == .unclaimed else {
                    throw ProjectSetupFailure.localAcceptanceFailed
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

                try Task.checkCancellation()
                try testCheckpoint(.operationWrite)
                _ = try transaction.execute(
                    sql: """
                    INSERT INTO \(LedgerPowerSyncTable.localOperations) (
                      id, account_id, actor_principal_id, contract_version,
                      fingerprint, subject_id, local_state, accepted_at_ms,
                      updated_at_ms, command_type, command_envelope_json
                    ) VALUES (?, ?, ?, ?, ?, ?, 'queued', ?, ?, 'create_project', ?)
                    """,
                    parameters: [
                        command.envelope.operationId.rawValue,
                        command.envelope.accountId.rawValue,
                        command.envelope.actorPrincipalId.rawValue,
                        command.envelope.contractVersion.rawValue,
                        command.fingerprint.sha256,
                        command.draft.projectId.rawValue,
                        acceptedAtMilliseconds,
                        acceptedAtMilliseconds,
                        envelopeJSON
                    ]
                )

                if let newClientDisplayName {
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

                try Task.checkCancellation()
                if newClientDisplayName == nil { try testCheckpoint(.projectionWrite) }
                _ = try transaction.execute(
                    sql: """
                    INSERT INTO \(LedgerPowerSyncTable.pendingProjects) (
                      id, account_id, client_id, display_name, description,
                      lifecycle, revision, category_configuration_revision,
                      created_at_ms, updated_at_ms,
                      created_by_principal_id, operation_id
                    ) VALUES (?, ?, ?, ?, ?, 'active', 1, ?, ?, ?, ?, ?)
                    """,
                    parameters: [
                        command.draft.projectId.rawValue,
                        command.envelope.accountId.rawValue,
                        command.draft.clientSelection.clientId.rawValue,
                        command.draft.displayName.rawValue,
                        command.draft.description,
                        "1",
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

                try Task.checkCancellation()
                try testCheckpoint(.commandWrite)
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
            throw ProjectSetupFailure.localAcceptanceFailed
        } catch let failure as LedgerOfflineClientRuntimeFailure {
            throw failure
        } catch let failure as OperationContractFailure {
            throw failure
        } catch let failure as ProjectSetupFailure {
            throw failure
        } catch {
            throw ProjectSetupFailure.localAcceptanceFailed
        }
    }

    nonisolated func watchOperation(
        _ operationId: OperationID
    ) -> AsyncThrowingStream<OperationSnapshot, Error> {
        guard accountId != nil, principalId != nil else {
            return Self.failedStream(ProjectSetupPowerSyncFailure.workspaceScopeRequired)
        }
        return AsyncThrowingStream { continuation in
            let watchId = UUID()
            let handle = ProjectSetupOperationWatchTaskHandle()
            let registration = Task {
                await watchRegistry.register(id: watchId, handle: handle)
            }
            let task = Task {
                let admitted = await registration.value
                guard admitted, !Task.isCancelled else {
                    continuation.finish()
                    if admitted { await watchRegistry.finished(id: watchId) }
                    return
                }
                do {
                    let updates = try database.watch(
                        sql: Self.operationWatchSQL,
                        parameters: [operationId.rawValue]
                    ) { cursor in
                        let id = try cursor.getString(name: "id")
                        let state = try cursor.getString(name: "local_state")
                        let updatedAt = try cursor.getInt64(name: "updated_at_ms")
                        let resultPhase = try cursor.getStringOptional(name: "result_phase")
                        let resultCompletedAt = try cursor.getInt64Optional(
                            name: "result_completed_at_ms"
                        )
                        return "\(id)|\(state)|\(updatedAt)|\(resultPhase ?? "")|\(resultCompletedAt ?? -1)"
                    }
                    for try await _ in updates {
                        try Task.checkCancellation()
                        let snapshot = try await self.operationSnapshot(operationId)
                        if case .terminated = continuation.yield(snapshot) { break }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
                await watchRegistry.finished(id: watchId)
            }
            handle.install(task)
            continuation.onTermination = { _ in handle.cancel() }
        }
    }

    func cancelAndDrainWatches() async {
        await watchRegistry.cancelAndDrain()
    }

    private func operationSnapshot(
        _ operationId: OperationID
    ) async throws -> OperationSnapshot {
        guard let accountId, let principalId else {
            throw ProjectSetupPowerSyncFailure.workspaceScopeRequired
        }
        try Task.checkCancellation()
        do {
            let snapshot = try await database.writeTransaction { transaction in
                try Task.checkCancellation()
                let operations = try transaction.getAll(
                    sql: Self.operationEvidenceSQL,
                    parameters: [operationId.rawValue]
                ) { try ProjectSetupOperationEvidence(cursor: $0) }
                guard operations.count <= 1 else {
                    throw ProjectSetupPowerSyncFailure.malformedLocalEvidence
                }
                guard let operation = operations.first else {
                    do {
                        let disposition = try LocalOperationIdentityGuard.inspect(
                            transaction: transaction,
                            operationId: operationId,
                            expectedFamily: .createProject,
                            expectedFingerprint: ""
                        )
                        if disposition == .unclaimed {
                            throw ProjectSetupPowerSyncFailure.operationNotFound
                        }
                    } catch let failure as ProjectSetupPowerSyncFailure {
                        throw failure
                    } catch {
                        throw ProjectSetupPowerSyncFailure.malformedLocalEvidence
                    }
                    throw ProjectSetupPowerSyncFailure.malformedLocalEvidence
                }
                guard try LocalOperationIdentityGuard.inspect(
                    transaction: transaction,
                    operationId: operationId,
                    expectedFamily: .createProject,
                    expectedFingerprint: operation.fingerprint
                ) == .matchingOwner else {
                    throw ProjectSetupPowerSyncFailure.malformedLocalEvidence
                }
                let results = try transaction.getAll(
                    sql: Self.operationResultSQL,
                    parameters: [operationId.rawValue]
                ) { try ProjectSetupOperationResultEvidence(cursor: $0) }
                guard results.count <= 1 else {
                    throw ProjectSetupPowerSyncFailure.malformedLocalEvidence
                }
                return try operation.snapshot(
                    expectedOperationId: operationId,
                    expectedAccountId: accountId,
                    expectedPrincipalId: principalId,
                    result: results.first
                )
            }
            try Task.checkCancellation()
            return snapshot
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as ProjectSetupPowerSyncFailure {
            throw failure
        } catch {
            throw ProjectSetupPowerSyncFailure.malformedLocalEvidence
        }
    }

    private nonisolated static func failedStream<Value: Sendable>(
        _ error: Error
    ) -> AsyncThrowingStream<Value, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
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
               json_extract(data, '$.data.project_created_at_ms') AS project_created_at_ms,
               json_extract(data, '$.data.project_id') AS project_id,
               json_extract(data, '$.data.client_selection_kind') AS client_selection_kind,
               json_extract(data, '$.data.client_id') AS client_id,
               json_extract(data, '$.data.new_client_display_name') AS new_client_display_name,
               json_extract(data, '$.data.project_display_name') AS project_display_name,
               json_extract(data, '$.data.description') AS description,
               json_extract(data, '$.data.category_allocations_json') AS allocations_json,
               json_extract(data, '$.data.fingerprint') AS fingerprint,
               json_extract(data, '$.data.envelope_json') AS envelope_json
        FROM ps_crud WHERE json_valid(data) = 1 AND json_extract(data, '$.id') = ?
          AND json_extract(data, '$.type') = ?
        """
    private static let replayProjectSQL = """
        SELECT id, account_id, client_id, display_name, description, lifecycle,
               revision, category_configuration_revision, created_at_ms, updated_at_ms,
               created_by_principal_id, operation_id
        FROM \(LedgerPowerSyncTable.pendingProjects) WHERE operation_id = ?
        """
    private static let replayClientSQL = """
        SELECT id, account_id, display_name, lifecycle, revision, created_at_ms,
               updated_at_ms, created_by_principal_id, operation_id
        FROM \(LedgerPowerSyncTable.pendingClients) WHERE operation_id = ?
        """
    private static let replayAllocationSQL = """
        SELECT id, account_id, project_id, category_id, allocation_minor_units,
               allocation_currency, revision, created_at_ms, updated_at_ms,
               created_by_principal_id, operation_id
        FROM \(LedgerPowerSyncTable.pendingProjectCategoryAllocations)
        WHERE operation_id = ? ORDER BY id
        """
    private static let operationWatchSQL = """
        SELECT operation.id, operation.local_state, operation.updated_at_ms,
               result.phase AS result_phase,
               result.completed_at_ms AS result_completed_at_ms
        FROM \(LedgerPowerSyncTable.localOperations) AS operation
        LEFT JOIN \(LedgerPowerSyncTable.operationResults) AS result
          ON result.id = operation.id
        WHERE operation.id = ?
        """
    private static let operationEvidenceSQL = """
        SELECT id, account_id, actor_principal_id, contract_version,
               fingerprint, subject_id, local_state, accepted_at_ms,
               updated_at_ms, command_type, command_expected_revision,
               command_envelope_json
        FROM \(LedgerPowerSyncTable.localOperations)
        WHERE id = ?
        """
    private static let operationResultSQL = """
        SELECT account_id, actor_principal_id, command_type,
               contract_version, command_fingerprint, envelope_sha256,
               request_sha256, subject_id, phase, result_code, error_code,
               client_created_at_ms, server_received_at_ms, completed_at_ms
        FROM \(LedgerPowerSyncTable.operationResults)
        WHERE id = ?
        """
}

private struct ProjectSetupOperationEvidence: Sendable {
    let operationId: String
    let accountId: String
    let principalId: String
    let contractVersion: String
    let fingerprint: String
    let subjectId: String
    let localState: String
    let acceptedAtMilliseconds: Int64
    let updatedAtMilliseconds: Int64
    let commandType: String?
    let expectedRevision: String?
    let envelopeJSON: String?

    init(cursor: any SqlCursor) throws {
        operationId = try cursor.getString(name: "id")
        accountId = try cursor.getString(name: "account_id")
        principalId = try cursor.getString(name: "actor_principal_id")
        contractVersion = try cursor.getString(name: "contract_version")
        fingerprint = try cursor.getString(name: "fingerprint")
        subjectId = try cursor.getString(name: "subject_id")
        localState = try cursor.getString(name: "local_state")
        acceptedAtMilliseconds = try cursor.getInt64(name: "accepted_at_ms")
        updatedAtMilliseconds = try cursor.getInt64(name: "updated_at_ms")
        commandType = try cursor.getStringOptional(name: "command_type")
        expectedRevision = try cursor.getStringOptional(name: "command_expected_revision")
        envelopeJSON = try cursor.getStringOptional(name: "command_envelope_json")
    }

    func snapshot(
        expectedOperationId: OperationID,
        expectedAccountId: AccountID,
        expectedPrincipalId: PrincipalID,
        result: ProjectSetupOperationResultEvidence?
    ) throws -> OperationSnapshot {
        guard operationId == expectedOperationId.rawValue,
              accountId == expectedAccountId.rawValue,
              principalId == expectedPrincipalId.rawValue,
              commandType == LocalOperationCommandFamily.createProject.rawValue,
              expectedRevision == nil,
              acceptedAtMilliseconds >= 0,
              updatedAtMilliseconds >= acceptedAtMilliseconds,
              let envelopeJSON,
              let envelopeData = envelopeJSON.data(using: .utf8),
              let envelope = try? OperationContractCodec.decode(
                OperationEnvelope<CreateProjectPayload>.self,
                from: envelopeData
              ),
              envelope.operationId == expectedOperationId,
              envelope.accountId == expectedAccountId,
              envelope.actorPrincipalId == expectedPrincipalId,
              envelope.contractVersion.rawValue == contractVersion,
              envelope.payload.projectId.rawValue == subjectId,
              envelope.preconditions.isEmpty,
              let typedFingerprint = try? OperationFingerprint(validating: fingerprint),
              (try? OperationFingerprint.make(for: envelope)) == typedFingerprint,
              let state = LocalOperationState(rawValue: localState) else {
            throw ProjectSetupPowerSyncFailure.malformedLocalEvidence
        }
        if let result {
            try result.validate(operation: self, envelope: envelope)
        }

        let acceptedAt = Self.date(acceptedAtMilliseconds)
        let effectiveUpdatedAtMilliseconds = max(
            updatedAtMilliseconds,
            result?.completedAtMilliseconds ?? updatedAtMilliseconds
        )
        let updatedAt = Self.date(effectiveUpdatedAtMilliseconds)
        let subject = LedgerEntityReference(
            kind: .project,
            id: try EntityID(validating: subjectId)
        )
        let operationState: OperationState
        let effectiveState = try result.map {
            guard let terminalState = LocalOperationState(rawValue: $0.phase) else {
                throw ProjectSetupPowerSyncFailure.malformedLocalEvidence
            }
            return terminalState
        } ?? state
        switch effectiveState {
        case .queued:
            operationState = .queued(attemptCount: 0, lastTransientError: nil)
        case .applying:
            operationState = .applying(attempt: 1, startedAt: updatedAt)
        case .applied:
            let completedAt = result.map { Self.date($0.completedAtMilliseconds) }
                ?? updatedAt
            let receivedAt = result.map { Self.date($0.serverReceivedAtMilliseconds) }
                ?? updatedAt
            operationState = .applied(AppliedOperationResult(
                resultCode: try ApplicationResultCode(
                    validating: result?.resultCode ?? "project_created"
                ),
                serverReceivedAt: receivedAt,
                completedAt: completedAt,
                affectedRevisions: [EntityRevision(entity: subject, revision: 1)]
            ))
        case .rejected:
            let code = result?.errorCode ?? "project_setup_rejected"
            operationState = .rejected(OperationRejection(
                error: ApplicationErrorSummary(
                    code: try ApplicationErrorCode(validating: code),
                    category: Self.errorCategory(code),
                    retryDisposition: Self.retryDisposition(code)
                ),
                rejectedAt: result.map { Self.date($0.completedAtMilliseconds) }
                    ?? updatedAt,
                conflictingEntities: Self.isConflict(code) ? [subject] : []
            ))
        case .superseded, .resolved:
            throw ProjectSetupPowerSyncFailure.malformedLocalEvidence
        }
        return OperationSnapshot(
            operationId: expectedOperationId,
            accountId: expectedAccountId,
            contractVersion: try OperationContractVersion(validating: contractVersion),
            fingerprint: typedFingerprint,
            acceptedAt: acceptedAt,
            updatedAt: updatedAt,
            state: operationState
        )
    }

    private static func date(_ milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }

    private static func isConflict(_ code: String) -> Bool {
        code.contains("conflict") || code.contains("not_selectable")
    }

    private static func errorCategory(_ code: String) -> ApplicationErrorCategory {
        if isConflict(code) { return .conflict }
        if code == "contract_unsupported" { return .unsupportedContract }
        return .validation
    }

    private static func retryDisposition(_ code: String) -> RetryDisposition {
        if code == "contract_unsupported" { return .afterClientUpdate }
        return isConflict(code) ? .afterUserCorrection : .never
    }
}

private struct ProjectSetupOperationResultEvidence: Sendable {
    let accountId: String
    let principalId: String
    let commandType: String
    let contractVersion: String
    let fingerprint: String
    let envelopeSHA256: String
    let requestSHA256: String?
    let subjectId: String
    let phase: String
    let resultCode: String?
    let errorCode: String?
    let clientCreatedAtMilliseconds: Int64
    let serverReceivedAtMilliseconds: Int64
    let completedAtMilliseconds: Int64

    init(cursor: any SqlCursor) throws {
        accountId = try cursor.getString(name: "account_id")
        principalId = try cursor.getString(name: "actor_principal_id")
        commandType = try cursor.getString(name: "command_type")
        contractVersion = try cursor.getString(name: "contract_version")
        fingerprint = try cursor.getString(name: "command_fingerprint")
        envelopeSHA256 = try cursor.getString(name: "envelope_sha256")
        requestSHA256 = try cursor.getStringOptional(name: "request_sha256")
        subjectId = try cursor.getString(name: "subject_id")
        phase = try cursor.getString(name: "phase")
        resultCode = try cursor.getStringOptional(name: "result_code")
        errorCode = try cursor.getStringOptional(name: "error_code")
        clientCreatedAtMilliseconds = try cursor.getInt64(name: "client_created_at_ms")
        serverReceivedAtMilliseconds = try cursor.getInt64(name: "server_received_at_ms")
        completedAtMilliseconds = try cursor.getInt64(name: "completed_at_ms")
    }

    func validate(
        operation: ProjectSetupOperationEvidence,
        envelope: OperationEnvelope<CreateProjectPayload>
    ) throws {
        let createdAtValue = envelope.clientCreatedAt.timeIntervalSince1970 * 1_000
        guard createdAtValue.isFinite,
              let createdAtMilliseconds = Int64(
                exactly: createdAtValue.rounded(.towardZero)
              ),
              accountId == operation.accountId,
              principalId == operation.principalId,
              commandType == LocalOperationCommandFamily.createProject.rawValue,
              contractVersion == operation.contractVersion,
              fingerprint == operation.fingerprint,
              envelopeSHA256 == operation.fingerprint,
              requestSHA256 == nil,
              subjectId == operation.subjectId,
              clientCreatedAtMilliseconds == createdAtMilliseconds,
              serverReceivedAtMilliseconds >= 0,
              completedAtMilliseconds >= serverReceivedAtMilliseconds else {
            throw ProjectSetupPowerSyncFailure.malformedLocalEvidence
        }
        let localPhaseAcceptsTerminalResult = operation.localState == phase
            || operation.localState == LocalOperationState.queued.rawValue
            || operation.localState == LocalOperationState.applying.rawValue
        guard localPhaseAcceptsTerminalResult else {
            throw ProjectSetupPowerSyncFailure.malformedLocalEvidence
        }
        switch phase {
        case "applied":
            guard resultCode == "project_created", errorCode == nil else {
                throw ProjectSetupPowerSyncFailure.malformedLocalEvidence
            }
        case "rejected":
            guard resultCode == nil,
                  errorCode.map(Self.knownRejectionCodes.contains) == true else {
                throw ProjectSetupPowerSyncFailure.malformedLocalEvidence
            }
        default:
            throw ProjectSetupPowerSyncFailure.malformedLocalEvidence
        }
    }

    private static let knownRejectionCodes: Set<String> = [
        "project_setup_command_encoding_invalid", "contract_unsupported",
        "project_setup_payload_invalid", "project_setup_fingerprint_mismatch",
        "project_setup_envelope_mismatch", "project_setup_category_allocation_invalid",
        "project_setup_category_not_selectable", "project_setup_identity_conflict",
        "project_setup_client_not_selectable",
        "project_setup_new_client_identity_conflict"
    ]
}

private final class ProjectSetupOperationWatchTaskHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var cancellationRequested = false

    func install(_ task: Task<Void, Never>) {
        let shouldCancel = lock.withLock {
            self.task = task
            return cancellationRequested
        }
        if shouldCancel { task.cancel() }
    }

    func cancel() {
        let installedTask = lock.withLock {
            cancellationRequested = true
            return task
        }
        installedTask?.cancel()
    }
}

private actor ProjectSetupOperationWatchRegistry {
    private var handles: [UUID: ProjectSetupOperationWatchTaskHandle] = [:]
    private var isClosing = false
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    func register(id: UUID, handle: ProjectSetupOperationWatchTaskHandle) -> Bool {
        guard !isClosing else {
            handle.cancel()
            return false
        }
        handles[id] = handle
        return true
    }

    func finished(id: UUID) {
        handles.removeValue(forKey: id)
        guard handles.isEmpty else { return }
        let waiters = drainWaiters
        drainWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
    }

    func cancelAndDrain() async {
        isClosing = true
        for handle in handles.values { handle.cancel() }
        guard !handles.isEmpty else { return }
        await withCheckedContinuation { drainWaiters.append($0) }
    }
}

private struct ProjectSetupReplayRow {
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

private struct ProjectSetupReplayCommand {
    let operation: String; let accountId: String; let principalId: String
    let contractVersion: String; let capturedAt: Int64; let projectId: String
    let selectionKind: String; let clientId: String; let newClientName: String?
    let projectName: String; let description: String?; let allocationsJSON: String
    let fingerprint: String; let envelopeJSON: String
    init(cursor: any SqlCursor) throws {
        operation = try cursor.getString(name: "operation")
        accountId = try cursor.getString(name: "account_id")
        principalId = try cursor.getString(name: "actor_principal_id")
        contractVersion = try cursor.getString(name: "contract_version")
        capturedAt = try cursor.getInt64(name: "project_created_at_ms")
        projectId = try cursor.getString(name: "project_id")
        selectionKind = try cursor.getString(name: "client_selection_kind")
        clientId = try cursor.getString(name: "client_id")
        newClientName = try cursor.getStringOptional(name: "new_client_display_name")
        projectName = try cursor.getString(name: "project_display_name")
        description = try cursor.getStringOptional(name: "description")
        allocationsJSON = try cursor.getString(name: "allocations_json")
        fingerprint = try cursor.getString(name: "fingerprint")
        envelopeJSON = try cursor.getString(name: "envelope_json")
    }
    func matches(
        _ command: CreateProjectCommand, envelopeJSON expectedEnvelope: String,
        allocationsJSON expectedAllocations: String, capturedAtMilliseconds: Int64
    ) -> Bool {
        operation == "PUT" && accountId == command.envelope.accountId.rawValue
            && principalId == command.envelope.actorPrincipalId.rawValue
            && contractVersion == command.envelope.contractVersion.rawValue
            && capturedAt == capturedAtMilliseconds && projectId == command.draft.projectId.rawValue
            && selectionKind == (command.draft.clientSelection.newClientDisplayName == nil ? "existing" : "new")
            && clientId == command.draft.clientSelection.clientId.rawValue
            && newClientName == command.draft.clientSelection.newClientDisplayName?.rawValue
            && projectName == command.draft.displayName.rawValue
            && description == command.draft.description && allocationsJSON == expectedAllocations
            && fingerprint == command.fingerprint.sha256 && envelopeJSON == expectedEnvelope
    }
}

private struct ProjectSetupReplayProject {
    let id: String; let accountId: String; let clientId: String; let name: String
    let description: String?; let lifecycle: String; let revision: Int64
    let configurationRevision: String; let createdAt: Int64; let updatedAt: Int64
    let principalId: String; let operationId: String
    init(cursor: any SqlCursor) throws {
        id = try cursor.getString(name: "id"); accountId = try cursor.getString(name: "account_id")
        clientId = try cursor.getString(name: "client_id"); name = try cursor.getString(name: "display_name")
        description = try cursor.getStringOptional(name: "description")
        lifecycle = try cursor.getString(name: "lifecycle"); revision = try cursor.getInt64(name: "revision")
        configurationRevision = try cursor.getString(name: "category_configuration_revision")
        createdAt = try cursor.getInt64(name: "created_at_ms"); updatedAt = try cursor.getInt64(name: "updated_at_ms")
        principalId = try cursor.getString(name: "created_by_principal_id")
        operationId = try cursor.getString(name: "operation_id")
    }
    func matches(_ command: CreateProjectCommand, acceptedAtMilliseconds: Int64) -> Bool {
        id == command.draft.projectId.rawValue && accountId == command.envelope.accountId.rawValue
            && clientId == command.draft.clientSelection.clientId.rawValue
            && name == command.draft.displayName.rawValue && description == command.draft.description
            && lifecycle == "active" && revision == 1 && configurationRevision == "1"
            && createdAt == acceptedAtMilliseconds && updatedAt == acceptedAtMilliseconds
            && principalId == command.envelope.actorPrincipalId.rawValue
            && operationId == command.envelope.operationId.rawValue
    }
}

private struct ProjectSetupReplayClient {
    let id: String; let accountId: String; let name: String; let lifecycle: String
    let revision: Int64; let createdAt: Int64; let updatedAt: Int64
    let principalId: String; let operationId: String
    init(cursor: any SqlCursor) throws {
        id = try cursor.getString(name: "id"); accountId = try cursor.getString(name: "account_id")
        name = try cursor.getString(name: "display_name"); lifecycle = try cursor.getString(name: "lifecycle")
        revision = try cursor.getInt64(name: "revision"); createdAt = try cursor.getInt64(name: "created_at_ms")
        updatedAt = try cursor.getInt64(name: "updated_at_ms")
        principalId = try cursor.getString(name: "created_by_principal_id")
        operationId = try cursor.getString(name: "operation_id")
    }
    func matches(_ command: CreateProjectCommand, acceptedAtMilliseconds: Int64) -> Bool {
        id == command.draft.clientSelection.clientId.rawValue
            && accountId == command.envelope.accountId.rawValue
            && name == command.draft.clientSelection.newClientDisplayName?.rawValue
            && lifecycle == "active" && revision == 1 && createdAt == acceptedAtMilliseconds
            && updatedAt == acceptedAtMilliseconds
            && principalId == command.envelope.actorPrincipalId.rawValue
            && operationId == command.envelope.operationId.rawValue
    }
}

private struct ProjectSetupReplayAllocation {
    let id: String; let accountId: String; let projectId: String; let categoryId: String
    let minorUnits: Int64?; let currency: String?; let revision: Int64
    let createdAt: Int64; let updatedAt: Int64; let principalId: String; let operationId: String
    init(cursor: any SqlCursor) throws {
        id = try cursor.getString(name: "id"); accountId = try cursor.getString(name: "account_id")
        projectId = try cursor.getString(name: "project_id"); categoryId = try cursor.getString(name: "category_id")
        minorUnits = try cursor.getInt64Optional(name: "allocation_minor_units")
        currency = try cursor.getStringOptional(name: "allocation_currency")
        revision = try cursor.getInt64(name: "revision"); createdAt = try cursor.getInt64(name: "created_at_ms")
        updatedAt = try cursor.getInt64(name: "updated_at_ms")
        principalId = try cursor.getString(name: "created_by_principal_id")
        operationId = try cursor.getString(name: "operation_id")
    }
    static func matches(
        _ rows: [Self], command: CreateProjectCommand, acceptedAtMilliseconds: Int64
    ) -> Bool {
        guard rows.count == command.draft.categoryAllocations.count else { return false }
        return command.draft.categoryAllocations.allSatisfy { expected in
            rows.contains { row in
                row.id == "\(command.envelope.operationId.rawValue):\(expected.categoryId.rawValue)"
                    && row.accountId == command.envelope.accountId.rawValue
                    && row.projectId == command.draft.projectId.rawValue
                    && row.categoryId == expected.categoryId.rawValue
                    && row.minorUnits == expected.allocation?.minorUnits
                    && row.currency == expected.allocation?.currency.rawValue
                    && row.revision == 1 && row.createdAt == acceptedAtMilliseconds
                    && row.updatedAt == acceptedAtMilliseconds
                    && row.principalId == command.envelope.actorPrincipalId.rawValue
                    && row.operationId == command.envelope.operationId.rawValue
            }
        }
    }

    static func matchesPresent(
        _ rows: [Self], command: CreateProjectCommand, acceptedAtMilliseconds: Int64
    ) -> Bool {
        guard rows.count <= command.draft.categoryAllocations.count else { return false }
        return rows.allSatisfy { row in
            command.draft.categoryAllocations.contains { expected in
                row.id == "\(command.envelope.operationId.rawValue):\(expected.categoryId.rawValue)"
                    && row.accountId == command.envelope.accountId.rawValue
                    && row.projectId == command.draft.projectId.rawValue
                    && row.categoryId == expected.categoryId.rawValue
                    && row.minorUnits == expected.allocation?.minorUnits
                    && row.currency == expected.allocation?.currency.rawValue
                    && row.revision == 1 && row.createdAt == acceptedAtMilliseconds
                    && row.updatedAt == acceptedAtMilliseconds
                    && row.principalId == command.envelope.actorPrincipalId.rawValue
                    && row.operationId == command.envelope.operationId.rawValue
            }
        }
    }
}
