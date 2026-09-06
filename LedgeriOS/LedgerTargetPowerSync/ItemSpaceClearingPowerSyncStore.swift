import Foundation
import LedgerTargetCore
import PowerSync

public enum ItemSpaceClearingPowerSyncStoreFailure: Error, Equatable, Sendable {
    case invalidAcceptanceTime
    case malformedLocalEvidence
    case operationNotFound

    public var diagnosticCode: String {
        switch self {
        case .invalidAcceptanceTime:
            "item_space_clearing_acceptance_time_invalid"
        case .malformedLocalEvidence:
            "item_space_clearing_local_evidence_malformed"
        case .operationNotFound:
            "item_space_clearing_operation_not_found"
        }
    }
}

enum ItemSpaceClearingPowerSyncStoreCheckpoint: Equatable, Sendable {
    case beforeTransaction
    case inventoryConstruction
    case inventoryRead
    case afterOwnershipInspection
    case existingRead
    case commandWrite
    case operationWrite
    case beforeCommit
    case afterCommit
    case watchConstruction
    case watchRead
    case watchIteration
}

actor ItemSpaceClearingPowerSyncStore: ItemSpaceAssignmentClearing {
    private let database: any PowerSyncDatabaseProtocol
    private let accountId: AccountID
    private let principalId: PrincipalID
    private let now: @Sendable () -> Date
    private let checkpoint: @Sendable (ItemSpaceClearingPowerSyncStoreCheckpoint) throws -> Void
    private let watchRegistry = ItemSpaceClearingOperationWatchRegistry()
    private var isClosed = false

    init(
        database: any PowerSyncDatabaseProtocol,
        accountId: AccountID,
        principalId: PrincipalID,
        now: @Sendable @escaping () -> Date = Date.init,
        checkpoint: @Sendable @escaping (
            ItemSpaceClearingPowerSyncStoreCheckpoint
        ) throws -> Void = { _ in }
    ) {
        self.database = database
        self.accountId = accountId
        self.principalId = principalId
        self.now = now
        self.checkpoint = checkpoint
    }

    func clearItemSpaceAssignments(
        _ command: ClearItemSpaceAssignmentsCommand
    ) async throws -> OperationReceipt {
        guard !isClosed else {
            throw LedgerOfflineClientRuntimeFailure.runtimeClosed
        }
        guard command.envelope.accountId == accountId else {
            throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
        }
        guard command.envelope.actorPrincipalId == principalId else {
            throw LedgerOfflineClientRuntimeFailure.principalScopeMismatch
        }

        let commandJSON = try Self.canonicalJSON(
            command,
            failure: ItemSpaceClearingFailure.invalidEncodedCommand
        )
        let envelopeJSON = try Self.canonicalJSON(
            command.envelope,
            failure: ItemSpaceClearingFailure.invalidEncodedCommand
        )
        let itemsJSON = try Self.itemsJSON(command.draft.items)
        let scope = Self.scopeEvidence(command.draft.scope)
        let scopedAccountId = accountId
        let scopedPrincipalId = principalId
        let acceptanceClock = now
        let testCheckpoint = checkpoint

        try Task.checkCancellation()
        do {
            try testCheckpoint(.beforeTransaction)
            try Task.checkCancellation()
            let receipt = try await database.writeTransaction { transaction in
                try Task.checkCancellation()
                let ownership = try LocalOperationIdentityGuard.inspect(
                    transaction: transaction,
                    operationId: command.envelope.operationId,
                    expectedFamily: .clearItemSpaceAssignments,
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
                try testCheckpoint(.existingRead)
                let existingCommand = try transaction.getOptional(
                    sql: Self.commandEvidenceSQL,
                    parameters: [command.envelope.operationId.rawValue]
                ) { cursor in
                    try ItemSpaceClearingCommandEvidenceRow(cursor: cursor)
                }
                let existingOperation = try transaction.getOptional(
                    sql: Self.operationEvidenceSQL,
                    parameters: [command.envelope.operationId.rawValue]
                ) { cursor in
                    try ItemSpaceClearingOperationEvidenceRow(cursor: cursor)
                }
                let existingResult = try transaction.getOptional(
                    sql: Self.resultEvidenceSQL,
                    parameters: [command.envelope.operationId.rawValue]
                ) { cursor in
                    try cursor.getString(name: "id")
                }

                if existingCommand != nil || existingOperation != nil || existingResult != nil {
                    guard ownership == .matchingOwner,
                          let existingCommand, let existingOperation,
                          existingResult == nil else {
                        throw ItemSpaceClearingPowerSyncStoreFailure
                            .malformedLocalEvidence
                    }
                    let storedCommand = try existingCommand.validatedCommand(
                        accountId: scopedAccountId,
                        principalId: scopedPrincipalId
                    )
                    guard let storedAcceptedAtMilliseconds =
                            existingCommand.acceptedAtMilliseconds else {
                        throw ItemSpaceClearingPowerSyncStoreFailure
                            .malformedLocalEvidence
                    }
                    try existingOperation.validate(
                        command: storedCommand,
                        acceptedAtMilliseconds: storedAcceptedAtMilliseconds
                    )
                    guard existingCommand.commandJSON == commandJSON,
                          existingCommand.itemsJSON == itemsJSON else {
                        throw OperationContractFailure.payloadMismatch(
                            command.envelope.operationId
                        )
                    }
                    return OperationReceipt(
                        operationId: command.envelope.operationId,
                        localState: .queued
                    )
                }
                guard ownership == .unclaimed else {
                    throw ItemSpaceClearingPowerSyncStoreFailure.malformedLocalEvidence
                }

                try Task.checkCancellation()
                let acceptedAtMilliseconds = try Self.acceptanceMilliseconds(
                    acceptanceClock()
                )
                try Task.checkCancellation()
                try testCheckpoint(.commandWrite)
                _ = try transaction.execute(
                    sql: Self.insertCommandSQL,
                    parameters: [
                        command.envelope.operationId.rawValue,
                        scopedAccountId.rawValue,
                        scopedPrincipalId.rawValue,
                        command.envelope.contractVersion.rawValue,
                        scope.kind,
                        scope.projectId,
                        itemsJSON,
                        command.fingerprint.sha256,
                        commandJSON,
                        acceptedAtMilliseconds
                    ]
                )

                try Task.checkCancellation()
                try testCheckpoint(.operationWrite)
                _ = try transaction.execute(
                    sql: Self.insertOperationSQL,
                    parameters: [
                        command.envelope.operationId.rawValue,
                        scopedAccountId.rawValue,
                        scopedPrincipalId.rawValue,
                        command.envelope.contractVersion.rawValue,
                        command.fingerprint.sha256,
                        command.subject.id.rawValue,
                        acceptedAtMilliseconds,
                        acceptedAtMilliseconds,
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
            throw ItemSpaceClearingPowerSyncStoreFailure.malformedLocalEvidence
        } catch let failure as LedgerOfflineClientRuntimeFailure {
            throw failure
        } catch let failure as OperationContractFailure {
            throw failure
        } catch let failure as ItemSpaceClearingPowerSyncStoreFailure {
            throw failure
        } catch let failure as ItemSpaceClearingFailure {
            throw failure
        } catch {
            throw ItemSpaceClearingFailure.localAcceptanceFailed
        }
    }

    nonisolated func watchOperation(
        _ operationId: OperationID
    ) -> AsyncThrowingStream<OperationSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let watchId = UUID()
            let handle = ItemSpaceClearingOperationWatchTaskHandle()
            let registration = Task {
                await watchRegistry.register(id: watchId, handle: handle)
            }
            let task = Task {
                let admitted = await registration.value
                guard admitted, !Task.isCancelled else {
                    if admitted {
                        continuation.finish(throwing: CancellationError())
                    } else {
                        continuation.finish(
                            throwing: LedgerOfflineClientRuntimeFailure.runtimeClosed
                        )
                    }
                    if admitted { await watchRegistry.finished(id: watchId) }
                    return
                }
                do {
                    try checkpoint(.watchConstruction)
                    let updates = try database.watch(
                        sql: Self.watchSQL,
                        parameters: [
                            operationId.rawValue,
                            accountId.rawValue,
                            principalId.rawValue
                        ]
                    ) { cursor in
                        try self.checkpoint(.watchRead)
                        return try ItemSpaceClearingJoinedEvidenceRow(cursor: cursor)
                    }
                    for try await rows in updates {
                        try Task.checkCancellation()
                        try checkpoint(.watchIteration)
                        guard rows.count <= 1 else {
                            throw ItemSpaceClearingPowerSyncStoreFailure
                                .malformedLocalEvidence
                        }
                        guard let row = rows.first else {
                            throw ItemSpaceClearingPowerSyncStoreFailure.operationNotFound
                        }
                        let snapshot = try row.snapshot(
                            expectedOperationId: operationId,
                            accountId: accountId,
                            principalId: principalId
                        )
                        if case .terminated = continuation.yield(snapshot) { break }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch let failure as LedgerOfflineClientRuntimeFailure {
                    continuation.finish(throwing: failure)
                } catch let failure as OperationContractFailure {
                    continuation.finish(throwing: failure)
                } catch let failure as ItemSpaceClearingPowerSyncStoreFailure {
                    continuation.finish(throwing: failure)
                } catch let failure as ItemSpaceClearingFailure {
                    continuation.finish(throwing: failure)
                } catch {
                    continuation.finish(
                        throwing: ItemSpaceClearingFailure.localAcceptanceFailed
                    )
                }
                await watchRegistry.finished(id: watchId)
            }
            handle.install(task)
            continuation.onTermination = { _ in handle.cancel() }
        }
    }

    func cancelAndDrainWatches() async {
        isClosed = true
        await watchRegistry.cancelAndDrain()
    }

    fileprivate nonisolated static func canonicalJSON<Value: Encodable>(
        _ value: Value,
        failure: ItemSpaceClearingFailure
    ) throws -> String {
        do {
            let data = try OperationContractCodec.encode(value)
            guard let value = String(data: data, encoding: .utf8) else {
                throw failure
            }
            return value
        } catch let failure as ItemSpaceClearingFailure {
            throw failure
        } catch {
            throw failure
        }
    }

    fileprivate nonisolated static func itemsJSON(
        _ items: [ItemSpaceClearingCandidate]
    ) throws -> String {
        let evidence = ItemSpaceClearingItemsEvidence(
            schemaVersion: "item_space_clearing_items_v1",
            items: items.map {
                ItemSpaceClearingItemEvidence(
                    itemId: $0.itemId.rawValue,
                    expectedRevision: String($0.expectedRevision.rawValue),
                    currentSpaceId: $0.currentSpaceId.rawValue
                )
            }
        )
        return try canonicalJSON(
            evidence,
            failure: ItemSpaceClearingFailure.invalidEncodedCommand
        )
    }

    private nonisolated static func scopeEvidence(
        _ scope: ItemPlacementScope
    ) -> (kind: String, projectId: String?) {
        switch scope {
        case .project(let projectId):
            ("project", projectId.rawValue)
        case .businessInventory:
            ("business_inventory", nil)
        }
    }

    private nonisolated static func acceptanceMilliseconds(_ date: Date) throws -> Int64 {
        let value = date.timeIntervalSince1970 * 1_000
        guard value.isFinite, value >= 0,
              let milliseconds = Int64(exactly: value.rounded(.towardZero)),
              milliseconds >= 0 else {
            throw ItemSpaceClearingPowerSyncStoreFailure.invalidAcceptanceTime
        }
        do {
            _ = try exactDate(milliseconds: milliseconds)
        } catch {
            throw ItemSpaceClearingPowerSyncStoreFailure.invalidAcceptanceTime
        }
        return milliseconds
    }

    fileprivate nonisolated static func exactDate(milliseconds: Int64) throws -> Date {
        let date = Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
        let roundTrip = date.timeIntervalSince1970 * 1_000
        guard date.timeIntervalSinceReferenceDate.isFinite,
              roundTrip.isFinite,
              Int64(exactly: roundTrip.rounded()) == milliseconds else {
            throw ItemSpaceClearingPowerSyncStoreFailure.malformedLocalEvidence
        }
        return date
    }

    private static let commandEvidenceSQL = """
        SELECT id, account_id, actor_principal_id, contract_version,
               scope_kind, project_id, items_json, fingerprint, command_json,
               accepted_at_ms
        FROM \(LedgerPowerSyncTable.itemSpaceClearingCommands)
        WHERE id = ?
        """

    private static let operationEvidenceSQL = """
        SELECT id, account_id, actor_principal_id, contract_version,
               fingerprint, subject_id, local_state, accepted_at_ms,
               updated_at_ms, command_type, command_expected_revision,
               command_envelope_json, terminal_phase, terminal_result_code,
               terminal_error_code, terminal_envelope_sha256,
               terminal_request_sha256, terminal_server_received_at_ms,
               terminal_completed_at_ms
        FROM \(LedgerPowerSyncTable.localOperations)
        WHERE id = ?
        """

    private static let resultEvidenceSQL = """
        SELECT id
        FROM \(LedgerPowerSyncTable.operationResults)
        WHERE id = ?
        """

    private static let insertCommandSQL = """
        INSERT INTO \(LedgerPowerSyncTable.itemSpaceClearingCommands) (
          id, account_id, actor_principal_id, contract_version,
          scope_kind, project_id, items_json, fingerprint, command_json,
          accepted_at_ms
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

    private static let insertOperationSQL = """
        INSERT INTO \(LedgerPowerSyncTable.localOperations) (
          id, account_id, actor_principal_id, contract_version, fingerprint,
          subject_id, local_state, accepted_at_ms, updated_at_ms, command_type,
          command_expected_revision, command_envelope_json,
          terminal_phase, terminal_result_code, terminal_error_code,
          terminal_envelope_sha256, terminal_request_sha256,
          terminal_server_received_at_ms, terminal_completed_at_ms
        ) VALUES (?, ?, ?, ?, ?, ?, 'queued', ?, ?, 'clear_item_space_assignments', NULL, ?,
                  NULL, NULL, NULL, NULL, NULL, NULL, NULL)
        """

    private static let watchSQL = """
        SELECT
          operation.id AS operation_id,
          operation.account_id AS operation_account_id,
          operation.actor_principal_id AS operation_actor_principal_id,
          operation.contract_version AS operation_contract_version,
          operation.fingerprint AS operation_fingerprint,
          operation.subject_id AS operation_subject_id,
          operation.local_state AS operation_local_state,
          operation.accepted_at_ms AS operation_accepted_at_ms,
          operation.updated_at_ms AS operation_updated_at_ms,
          operation.command_type AS operation_command_type,
          operation.command_expected_revision AS operation_command_expected_revision,
          operation.command_envelope_json AS operation_command_envelope_json,
          operation.terminal_phase AS operation_terminal_phase,
          operation.terminal_result_code AS operation_terminal_result_code,
          operation.terminal_error_code AS operation_terminal_error_code,
          operation.terminal_envelope_sha256 AS operation_terminal_envelope_sha256,
          operation.terminal_request_sha256 AS operation_terminal_request_sha256,
          operation.terminal_server_received_at_ms
            AS operation_terminal_server_received_at_ms,
          operation.terminal_completed_at_ms AS operation_terminal_completed_at_ms,
          command.id AS command_id,
          command.account_id AS command_account_id,
          command.actor_principal_id AS command_actor_principal_id,
          command.contract_version AS command_contract_version,
          command.scope_kind AS command_scope_kind,
          command.project_id AS command_project_id,
          command.items_json AS command_items_json,
          command.fingerprint AS command_fingerprint,
          command.command_json AS command_command_json,
          command.accepted_at_ms AS command_accepted_at_ms,
          result.id AS result_id
        FROM \(LedgerPowerSyncTable.localOperations) AS operation
        LEFT JOIN \(LedgerPowerSyncTable.itemSpaceClearingCommands) AS command
          ON command.id = operation.id
        LEFT JOIN \(LedgerPowerSyncTable.operationResults) AS result
          ON result.id = operation.id
        WHERE operation.id = ?
          AND operation.account_id = ?
          AND operation.actor_principal_id = ?
        """
}

private struct ItemSpaceClearingItemEvidence: Codable, Equatable, Sendable {
    let itemId: String
    let expectedRevision: String
    let currentSpaceId: String
}

private struct ItemSpaceClearingItemsEvidence: Codable, Equatable, Sendable {
    let schemaVersion: String
    let items: [ItemSpaceClearingItemEvidence]
}

private struct ItemSpaceClearingCommandEvidenceRow: Sendable {
    let operationId: String?
    let accountId: String?
    let principalId: String?
    let contractVersion: String?
    let scopeKind: String?
    let projectId: String?
    let itemsJSON: String?
    let fingerprint: String?
    let commandJSON: String?
    let acceptedAtMilliseconds: Int64?

    init(cursor: any SqlCursor, prefix: String = "") throws {
        operationId = try cursor.getStringOptional(name: "\(prefix)id")
        accountId = try cursor.getStringOptional(name: "\(prefix)account_id")
        principalId = try cursor.getStringOptional(name: "\(prefix)actor_principal_id")
        contractVersion = try cursor.getStringOptional(name: "\(prefix)contract_version")
        scopeKind = try cursor.getStringOptional(name: "\(prefix)scope_kind")
        projectId = try cursor.getStringOptional(name: "\(prefix)project_id")
        itemsJSON = try cursor.getStringOptional(name: "\(prefix)items_json")
        fingerprint = try cursor.getStringOptional(name: "\(prefix)fingerprint")
        commandJSON = try cursor.getStringOptional(name: "\(prefix)command_json")
        acceptedAtMilliseconds = try cursor.getInt64Optional(
            name: "\(prefix)accepted_at_ms"
        )
    }

    func validatedCommand(
        accountId expectedAccountId: AccountID,
        principalId expectedPrincipalId: PrincipalID
    ) throws -> ClearItemSpaceAssignmentsCommand {
        guard let operationId, let accountId, let principalId, let contractVersion,
              let scopeKind, let itemsJSON, let fingerprint, let commandJSON,
              let acceptedAtMilliseconds, acceptedAtMilliseconds >= 0,
              (try? ItemSpaceClearingPowerSyncStore.exactDate(
                  milliseconds: acceptedAtMilliseconds
              )) != nil,
              accountId == expectedAccountId.rawValue,
              principalId == expectedPrincipalId.rawValue,
              let commandData = commandJSON.data(using: .utf8),
              let command = try? OperationContractCodec.decode(
                  ClearItemSpaceAssignmentsCommand.self,
                  from: commandData
              ),
              (try? OperationContractCodec.encode(command)) == commandData,
              operationId == command.envelope.operationId.rawValue,
              accountId == command.envelope.accountId.rawValue,
              principalId == command.envelope.actorPrincipalId.rawValue,
              contractVersion == command.envelope.contractVersion.rawValue,
              fingerprint == command.fingerprint.sha256,
              itemsJSON == (try? ItemSpaceClearingPowerSyncStore.itemsJSON(
                  command.draft.items
              )) else {
            throw ItemSpaceClearingPowerSyncStoreFailure.malformedLocalEvidence
        }

        switch command.draft.scope {
        case .project(let commandProjectId):
            guard scopeKind == "project", projectId == commandProjectId.rawValue else {
                throw ItemSpaceClearingPowerSyncStoreFailure.malformedLocalEvidence
            }
        case .businessInventory:
            guard scopeKind == "business_inventory", projectId == nil else {
                throw ItemSpaceClearingPowerSyncStoreFailure.malformedLocalEvidence
            }
        }
        return command
    }
}

private struct ItemSpaceClearingOperationEvidenceRow: Sendable {
    let operationId: String?
    let accountId: String?
    let principalId: String?
    let contractVersion: String?
    let fingerprint: String?
    let subjectId: String?
    let localState: String?
    let acceptedAtMilliseconds: Int64?
    let updatedAtMilliseconds: Int64?
    let commandType: String?
    let expectedRevision: String?
    let envelopeJSON: String?
    let terminalPhase: String?
    let terminalResultCode: String?
    let terminalErrorCode: String?
    let terminalEnvelopeSHA256: String?
    let terminalRequestSHA256: String?
    let terminalServerReceivedAtMilliseconds: Int64?
    let terminalCompletedAtMilliseconds: Int64?

    init(cursor: any SqlCursor, prefix: String = "") throws {
        operationId = try cursor.getStringOptional(name: "\(prefix)id")
        accountId = try cursor.getStringOptional(name: "\(prefix)account_id")
        principalId = try cursor.getStringOptional(name: "\(prefix)actor_principal_id")
        contractVersion = try cursor.getStringOptional(name: "\(prefix)contract_version")
        fingerprint = try cursor.getStringOptional(name: "\(prefix)fingerprint")
        subjectId = try cursor.getStringOptional(name: "\(prefix)subject_id")
        localState = try cursor.getStringOptional(name: "\(prefix)local_state")
        acceptedAtMilliseconds = try cursor.getInt64Optional(
            name: "\(prefix)accepted_at_ms"
        )
        updatedAtMilliseconds = try cursor.getInt64Optional(
            name: "\(prefix)updated_at_ms"
        )
        commandType = try cursor.getStringOptional(name: "\(prefix)command_type")
        expectedRevision = try cursor.getStringOptional(
            name: "\(prefix)command_expected_revision"
        )
        envelopeJSON = try cursor.getStringOptional(
            name: "\(prefix)command_envelope_json"
        )
        terminalPhase = try cursor.getStringOptional(name: "\(prefix)terminal_phase")
        terminalResultCode = try cursor.getStringOptional(
            name: "\(prefix)terminal_result_code"
        )
        terminalErrorCode = try cursor.getStringOptional(
            name: "\(prefix)terminal_error_code"
        )
        terminalEnvelopeSHA256 = try cursor.getStringOptional(
            name: "\(prefix)terminal_envelope_sha256"
        )
        terminalRequestSHA256 = try cursor.getStringOptional(
            name: "\(prefix)terminal_request_sha256"
        )
        terminalServerReceivedAtMilliseconds = try cursor.getInt64Optional(
            name: "\(prefix)terminal_server_received_at_ms"
        )
        terminalCompletedAtMilliseconds = try cursor.getInt64Optional(
            name: "\(prefix)terminal_completed_at_ms"
        )
    }

    func validate(
        command: ClearItemSpaceAssignmentsCommand,
        acceptedAtMilliseconds expectedAcceptedAtMilliseconds: Int64
    ) throws {
        let terminalFields: [Any?] = [
            terminalPhase, terminalResultCode, terminalErrorCode,
            terminalEnvelopeSHA256, terminalRequestSHA256,
            terminalServerReceivedAtMilliseconds, terminalCompletedAtMilliseconds
        ]
        guard let operationId, let accountId, let principalId, let contractVersion,
              let fingerprint, let subjectId, let localState,
              let acceptedAtMilliseconds, let updatedAtMilliseconds,
              let commandType, let envelopeJSON,
              operationId == command.envelope.operationId.rawValue,
              accountId == command.envelope.accountId.rawValue,
              principalId == command.envelope.actorPrincipalId.rawValue,
              contractVersion == command.envelope.contractVersion.rawValue,
              fingerprint == command.fingerprint.sha256,
              subjectId == command.subject.id.rawValue,
              localState == LocalOperationState.queued.rawValue,
              acceptedAtMilliseconds == expectedAcceptedAtMilliseconds,
              updatedAtMilliseconds == expectedAcceptedAtMilliseconds,
              acceptedAtMilliseconds >= 0,
              commandType == "clear_item_space_assignments",
              expectedRevision == nil,
              envelopeJSON == (try? ItemSpaceClearingPowerSyncStore.canonicalJSON(
                  command.envelope,
                  failure: ItemSpaceClearingFailure.invalidEncodedCommand
              )),
              !terminalFields.contains(where: { $0 != nil }) else {
            throw ItemSpaceClearingPowerSyncStoreFailure.malformedLocalEvidence
        }
    }
}

private struct ItemSpaceClearingJoinedEvidenceRow: Sendable {
    let command: ItemSpaceClearingCommandEvidenceRow
    let operation: ItemSpaceClearingOperationEvidenceRow
    let resultId: String?

    init(cursor: any SqlCursor) throws {
        command = try ItemSpaceClearingCommandEvidenceRow(cursor: cursor, prefix: "command_")
        operation = try ItemSpaceClearingOperationEvidenceRow(
            cursor: cursor,
            prefix: "operation_"
        )
        resultId = try cursor.getStringOptional(name: "result_id")
    }

    func snapshot(
        expectedOperationId: OperationID,
        accountId: AccountID,
        principalId: PrincipalID
    ) throws -> OperationSnapshot {
        guard resultId == nil else {
            throw ItemSpaceClearingPowerSyncStoreFailure.malformedLocalEvidence
        }
        let storedCommand = try command.validatedCommand(
            accountId: accountId,
            principalId: principalId
        )
        guard storedCommand.envelope.operationId == expectedOperationId,
              let acceptedAtMilliseconds = command.acceptedAtMilliseconds else {
            throw ItemSpaceClearingPowerSyncStoreFailure.malformedLocalEvidence
        }
        try operation.validate(
            command: storedCommand,
            acceptedAtMilliseconds: acceptedAtMilliseconds
        )
        let acceptedAt = try ItemSpaceClearingPowerSyncStore.exactDate(
            milliseconds: acceptedAtMilliseconds
        )
        return OperationSnapshot(
            operationId: expectedOperationId,
            accountId: accountId,
            contractVersion: storedCommand.envelope.contractVersion,
            fingerprint: storedCommand.fingerprint,
            acceptedAt: acceptedAt,
            updatedAt: acceptedAt,
            state: .queued(attemptCount: 0, lastTransientError: nil)
        )
    }
}

private final class ItemSpaceClearingOperationWatchTaskHandle: @unchecked Sendable {
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

private actor ItemSpaceClearingOperationWatchRegistry {
    private var handles: [UUID: ItemSpaceClearingOperationWatchTaskHandle] = [:]
    private var isClosing = false
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    func register(
        id: UUID,
        handle: ItemSpaceClearingOperationWatchTaskHandle
    ) -> Bool {
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
