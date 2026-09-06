import Foundation
import LedgerTargetCore
import PowerSync

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
    private let now: @Sendable () -> Date
    private let checkpoint: @Sendable (ProjectSetupPowerSyncStoreCheckpoint) throws -> Void

    init(
        database: any PowerSyncDatabaseProtocol,
        now: @Sendable @escaping () -> Date = Date.init,
        checkpoint: @Sendable @escaping (ProjectSetupPowerSyncStoreCheckpoint) throws -> Void = { _ in }
    ) {
        self.database = database
        self.now = now
        self.checkpoint = checkpoint
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
