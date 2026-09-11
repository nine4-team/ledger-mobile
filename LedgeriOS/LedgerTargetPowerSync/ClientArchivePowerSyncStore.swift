import Foundation
import LedgerTargetCore
import PowerSync

enum ClientArchivePowerSyncFailure: Error, Equatable, Sendable {
    case invalidAcceptanceTime
    case invalidOperationIdentity
    case malformedLocalEvidence
    case operationNotFound
}

public enum ClientArchiveOperationIdentity {
    public static func make(accountId: AccountID, uuid: UUID) throws -> OperationID {
        try AccountBoundOperationIdentity.make(
            family: .clientArchive,
            accountId: accountId,
            uuid: uuid
        )
    }

    static func isValid(_ operationId: OperationID, accountId: AccountID) -> Bool {
        AccountBoundOperationIdentity.isValid(
            operationId,
            family: .clientArchive,
            accountId: accountId
        )
    }
}

enum ClientArchivePowerSyncStoreCheckpoint: Equatable, Sendable {
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

actor ClientArchivePowerSyncStore: ClientArchiving {
    private let database: any PowerSyncDatabaseProtocol
    private let accountId: AccountID
    private let principalId: PrincipalID
    private let now: @Sendable () -> Date
    private let checkpoint: @Sendable (ClientArchivePowerSyncStoreCheckpoint) throws -> Void
    private let watchRegistry = ClientArchiveOperationWatchRegistry()

    init(
        database: any PowerSyncDatabaseProtocol,
        accountId: AccountID,
        principalId: PrincipalID,
        now: @Sendable @escaping () -> Date = Date.init,
        checkpoint: @Sendable @escaping (ClientArchivePowerSyncStoreCheckpoint) throws -> Void = { _ in }
    ) {
        self.database = database
        self.accountId = accountId
        self.principalId = principalId
        self.now = now
        self.checkpoint = checkpoint
    }

    func archive(_ command: ArchiveClientCommand) async throws -> OperationReceipt {
        guard command.envelope.accountId == accountId else {
            throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
        }
        guard command.envelope.actorPrincipalId == principalId else {
            throw LedgerOfflineClientRuntimeFailure.principalScopeMismatch
        }
        guard ClientArchiveOperationIdentity.isValid(
            command.envelope.operationId,
            accountId: accountId
        ) else {
            throw ClientArchivePowerSyncFailure.invalidOperationIdentity
        }

        let envelopeData = try OperationContractCodec.encode(command.envelope)
        guard let envelopeJSON = String(data: envelopeData, encoding: .utf8) else {
            throw ClientArchiveFailure.invalidEncodedCommand
        }
        let acceptedAtMilliseconds = try Self.milliseconds(
            now(), failure: .invalidAcceptanceTime
        )
        let capturedAtMilliseconds = try Self.milliseconds(
            command.envelope.clientCreatedAt, failure: .malformedLocalEvidence
        )
        guard command.envelope.clientCreatedAt == Self.date(capturedAtMilliseconds) else {
            throw ClientArchiveFailure.invalidEncodedCommand
        }
        let scopedAccountId = accountId.rawValue
        let scopedPrincipalId = principalId.rawValue
        let testCheckpoint = checkpoint

        try Task.checkCancellation()
        do {
            try testCheckpoint(.beforeTransaction)
            let receipt = try await database.writeTransaction { transaction in
                try Task.checkCancellation()
                let ownership = try LocalOperationIdentityGuard.inspect(
                    transaction: transaction,
                    operationId: command.envelope.operationId,
                    expectedFamily: .archiveClient,
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
                let replay = try transaction.getOptional(
                    sql: Self.replaySQL,
                    parameters: [command.envelope.operationId.rawValue]
                ) { try ClientArchiveReplayRow(cursor: $0) }
                if let replay {
                    guard ownership == .matchingOwner else {
                        throw ClientArchivePowerSyncFailure.malformedLocalEvidence
                    }
                    let commandRows = try transaction.getAll(
                        sql: """
                        SELECT data,
                               json_type(data, '$.data.client_created_at_ms')
                                 AS client_created_at_type
                        FROM ps_crud
                        WHERE json_extract(data, '$.id') = ?
                          AND json_extract(data, '$.type') = ?
                        """,
                        parameters: [
                            command.envelope.operationId.rawValue,
                            LedgerPowerSyncTable.clientArchiveCommands
                        ]
                    ) {
                        try ClientArchiveReplayCommand(cursor: $0)
                    }
                    let overlays = try transaction.getAll(
                        sql: """
                        SELECT account_id, actor_principal_id, client_id,
                               operation_id, fingerprint, expected_revision,
                               projected_revision, lifecycle, accepted_at_ms
                        FROM \(LedgerPowerSyncTable.clientArchiveOverlays)
                        WHERE operation_id = ?
                        """,
                        parameters: [command.envelope.operationId.rawValue]
                    ) { try ClientArchiveReplayOverlay(cursor: $0) }
                    guard overlays.count <= 1 else {
                        throw ClientArchivePowerSyncFailure.malformedLocalEvidence
                    }
                    return try replay.receipt(
                        for: command,
                        envelopeJSON: envelopeJSON,
                        capturedAtMilliseconds: capturedAtMilliseconds,
                        commandRows: commandRows,
                        overlays: overlays
                    )
                }
                guard ownership == .unclaimed else {
                    throw ClientArchivePowerSyncFailure.malformedLocalEvidence
                }

                let revision = command.draft.expectedRevision.rawValue
                guard revision > 0, revision < UInt64(Int64.max) else {
                    throw ClientArchiveFailure.revisionPreconditionMismatch
                }
                let clients = try transaction.getAll(
                    sql: """
                    SELECT lifecycle, revision
                    FROM (
                      SELECT authoritative.lifecycle, authoritative.revision, 0 AS source_order
                      FROM \(LedgerPowerSyncTable.clients) AS authoritative
                      WHERE authoritative.account_id = ? AND authoritative.id = ?
                      UNION ALL
                      SELECT pending.lifecycle, pending.revision, 1 AS source_order
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
                        scopedAccountId, command.draft.clientId.rawValue,
                        scopedAccountId, command.draft.clientId.rawValue,
                        scopedPrincipalId
                    ]
                ) {
                    (try $0.getString(name: "lifecycle"),
                     try $0.getInt64(name: "revision"))
                }
                guard clients.count == 1 else { throw ClientArchiveFailure.subjectMismatch }
                guard clients[0].0 == "active" else {
                    throw ClientArchiveFailure.localAcceptanceFailed
                }
                guard clients[0].1 > 0, UInt64(clients[0].1) == revision else {
                    throw ClientArchiveFailure.revisionPreconditionMismatch
                }
                let overlayCount = try transaction.get(
                    sql: "SELECT count(*) FROM \(LedgerPowerSyncTable.clientArchiveOverlays) WHERE account_id = ? AND client_id = ?",
                    parameters: [scopedAccountId, command.draft.clientId.rawValue]
                ) { try $0.getInt64(index: 0) }
                guard overlayCount == 0 else {
                    throw ClientArchivePowerSyncFailure.malformedLocalEvidence
                }

                let projectedRevision = Int64(revision) + 1
                try Task.checkCancellation()
                try testCheckpoint(.operationWrite)
                _ = try transaction.execute(
                    sql: """
                    INSERT INTO \(LedgerPowerSyncTable.localOperations) (
                      id, account_id, actor_principal_id, contract_version,
                      fingerprint, subject_id, local_state, accepted_at_ms,
                      updated_at_ms, command_type, command_expected_revision,
                      command_envelope_json
                    ) VALUES (?, ?, ?, ?, ?, ?, 'queued', ?, ?, 'archive_client', ?, ?)
                    """,
                    parameters: [
                        command.envelope.operationId.rawValue, scopedAccountId,
                        scopedPrincipalId, command.envelope.contractVersion.rawValue,
                        command.fingerprint.sha256, command.draft.clientId.rawValue,
                        acceptedAtMilliseconds, acceptedAtMilliseconds,
                        String(revision), envelopeJSON
                    ]
                )
                try Task.checkCancellation()
                try testCheckpoint(.projectionWrite)
                _ = try transaction.execute(
                    sql: """
                    INSERT INTO \(LedgerPowerSyncTable.clientArchiveOverlays) (
                      id, account_id, actor_principal_id, client_id, operation_id,
                      fingerprint, expected_revision, projected_revision,
                      lifecycle, accepted_at_ms
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'archived', ?)
                    """,
                    parameters: [
                        command.envelope.operationId.rawValue, scopedAccountId,
                        scopedPrincipalId, command.draft.clientId.rawValue,
                        command.envelope.operationId.rawValue,
                        command.fingerprint.sha256, String(revision),
                        projectedRevision, acceptedAtMilliseconds
                    ]
                )
                try Task.checkCancellation()
                try testCheckpoint(.commandWrite)
                _ = try transaction.execute(
                    sql: """
                    INSERT INTO \(LedgerPowerSyncTable.clientArchiveCommands) (
                      id, account_id, actor_principal_id, contract_version,
                      client_created_at_ms, client_id, expected_revision,
                      fingerprint, envelope_json
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    parameters: [
                        command.envelope.operationId.rawValue, scopedAccountId,
                        scopedPrincipalId, command.envelope.contractVersion.rawValue,
                        capturedAtMilliseconds, command.draft.clientId.rawValue,
                        String(revision), command.fingerprint.sha256, envelopeJSON
                    ]
                )
                try Task.checkCancellation()
                try testCheckpoint(.beforeCommit)
                return OperationReceipt(
                    operationId: command.envelope.operationId, localState: .queued
                )
            }
            try testCheckpoint(.afterCommit)
            try Task.checkCancellation()
            return try command.validate(receipt)
        } catch is CancellationError { throw CancellationError() }
          catch let error as LocalOperationIdentityGuardFailure {
            if error == .payloadMismatch {
                throw OperationContractFailure.payloadMismatch(command.envelope.operationId)
            }
            throw ClientArchivePowerSyncFailure.malformedLocalEvidence
        } catch let error as LedgerOfflineClientRuntimeFailure { throw error }
          catch let error as OperationContractFailure { throw error }
          catch let error as ClientArchiveFailure { throw error }
          catch let error as ClientArchivePowerSyncFailure { throw error }
          catch { throw ClientArchiveFailure.localAcceptanceFailed }
    }

    nonisolated func watchOperation(
        _ operationId: OperationID
    ) -> AsyncThrowingStream<OperationSnapshot, Error> {
        guard ClientArchiveOperationIdentity.isValid(operationId, accountId: accountId) else {
            return Self.failedStream(ClientArchivePowerSyncFailure.invalidOperationIdentity)
        }
        return AsyncThrowingStream { continuation in
            let watchId = UUID()
            let handle = ClientArchiveOperationWatchTaskHandle()
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
                        sql: Self.operationSQL,
                        parameters: [operationId.rawValue]
                    ) { try ClientArchiveOperationRow(cursor: $0) }
                    for try await rows in updates {
                        try Task.checkCancellation()
                        guard rows.count <= 1 else {
                            throw ClientArchivePowerSyncFailure.malformedLocalEvidence
                        }
                        guard let row = rows.first else {
                            throw ClientArchivePowerSyncFailure.operationNotFound
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
                } catch { continuation.finish(throwing: error) }
                await watchRegistry.finished(id: watchId)
            }
            handle.install(task)
            continuation.onTermination = { _ in handle.cancel() }
        }
    }

    func cancelAndDrainWatches() async {
        await watchRegistry.cancelAndDrain()
    }

    private nonisolated static func failedStream<Value: Sendable>(
        _ error: Error
    ) -> AsyncThrowingStream<Value, Error> {
        AsyncThrowingStream { $0.finish(throwing: error) }
    }

    private static func milliseconds(
        _ date: Date,
        failure: ClientArchivePowerSyncFailure
    ) throws -> Int64 {
        let value = date.timeIntervalSince1970 * 1_000
        guard value.isFinite,
              let milliseconds = Int64(exactly: value.rounded(.towardZero)),
              milliseconds >= 0 else { throw failure }
        return milliseconds
    }

    private static func date(_ milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }

    private static let replaySQL = """
        SELECT operation.account_id, operation.actor_principal_id,
               operation.contract_version, operation.fingerprint,
               operation.subject_id, operation.local_state,
               operation.accepted_at_ms, operation.updated_at_ms,
               operation.command_type, operation.command_expected_revision,
               operation.command_envelope_json, operation.terminal_phase,
               operation.terminal_result_code, operation.terminal_error_code,
               operation.terminal_envelope_sha256,
               operation.terminal_request_sha256,
               operation.terminal_server_received_at_ms,
               operation.terminal_completed_at_ms
        FROM \(LedgerPowerSyncTable.localOperations) AS operation
        WHERE operation.id = ?
        """

    private static let operationSQL = """
        SELECT operation.*, overlay.operation_id AS overlay_operation_id,
               overlay.account_id AS overlay_account_id,
               overlay.actor_principal_id AS overlay_actor_principal_id,
               overlay.client_id AS overlay_client_id,
               overlay.fingerprint AS overlay_fingerprint,
               overlay.expected_revision AS overlay_expected_revision,
               overlay.projected_revision AS overlay_projected_revision,
               overlay.lifecycle AS overlay_lifecycle,
               overlay.accepted_at_ms AS overlay_accepted_at_ms,
               result.account_id AS result_account_id,
               result.actor_principal_id AS result_actor_principal_id,
               result.command_type AS result_command_type,
               result.contract_version AS result_contract_version,
               result.command_fingerprint AS result_fingerprint,
               result.envelope_sha256 AS result_envelope_sha256,
               result.request_sha256 AS result_request_sha256,
               result.subject_id AS result_subject_id,
               result.phase AS result_phase, result.result_code,
               result.error_code,
               result.client_created_at_ms AS result_client_created_at_ms,
               result.server_received_at_ms, result.completed_at_ms
        FROM \(LedgerPowerSyncTable.localOperations) AS operation
        LEFT JOIN \(LedgerPowerSyncTable.clientArchiveOverlays) AS overlay
          ON overlay.operation_id = operation.id
        LEFT JOIN \(LedgerPowerSyncTable.operationResults) AS result
          ON result.id = operation.id
        WHERE operation.id = ?
        """
}

private final class ClientArchiveOperationWatchTaskHandle: @unchecked Sendable {
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

private actor ClientArchiveOperationWatchRegistry {
    private var handles: [UUID: ClientArchiveOperationWatchTaskHandle] = [:]
    private var isClosing = false
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    func register(id: UUID, handle: ClientArchiveOperationWatchTaskHandle) -> Bool {
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

private struct ClientArchiveReplayRow {
    let accountId: String
    let principalId: String
    let contractVersion: String
    let fingerprint: String
    let subjectId: String
    let localState: String
    let acceptedAt: Int64
    let updatedAt: Int64
    let commandType: String?
    let expectedRevision: String?
    let envelopeJSON: String?
    let terminalPhase: String?
    let terminalResultCode: String?
    let terminalErrorCode: String?
    let terminalEnvelopeSHA256: String?
    let terminalRequestSHA256: String?
    let terminalServerReceivedAt: Int64?
    let terminalCompletedAt: Int64?

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
        expectedRevision = try cursor.getStringOptional(name: "command_expected_revision")
        envelopeJSON = try cursor.getStringOptional(name: "command_envelope_json")
        terminalPhase = try cursor.getStringOptional(name: "terminal_phase")
        terminalResultCode = try cursor.getStringOptional(name: "terminal_result_code")
        terminalErrorCode = try cursor.getStringOptional(name: "terminal_error_code")
        terminalEnvelopeSHA256 = try cursor.getStringOptional(name: "terminal_envelope_sha256")
        terminalRequestSHA256 = try cursor.getStringOptional(name: "terminal_request_sha256")
        terminalServerReceivedAt = try cursor.getInt64Optional(name: "terminal_server_received_at_ms")
        terminalCompletedAt = try cursor.getInt64Optional(name: "terminal_completed_at_ms")
    }

    func receipt(
        for command: ArchiveClientCommand,
        envelopeJSON expectedEnvelope: String,
        capturedAtMilliseconds: Int64,
        commandRows: [ClientArchiveReplayCommand],
        overlays: [ClientArchiveReplayOverlay]
    ) throws -> OperationReceipt {
        guard fingerprint == command.fingerprint.sha256 else {
            throw OperationContractFailure.payloadMismatch(command.envelope.operationId)
        }
        guard accountId == command.envelope.accountId.rawValue,
              principalId == command.envelope.actorPrincipalId.rawValue,
              contractVersion == command.envelope.contractVersion.rawValue,
              subjectId == command.draft.clientId.rawValue,
              commandType == "archive_client",
              acceptedAt >= 0,
              updatedAt >= acceptedAt,
              expectedRevision == String(command.draft.expectedRevision.rawValue),
              envelopeJSON == expectedEnvelope,
              let state = LocalOperationState(rawValue: localState) else {
            throw ClientArchivePowerSyncFailure.malformedLocalEvidence
        }
        guard commandRows.count <= 1,
              commandRows.allSatisfy({
                $0.matches(
                    command,
                    envelopeJSON: expectedEnvelope,
                    capturedAtMilliseconds: capturedAtMilliseconds
                )
              }) else {
            throw ClientArchivePowerSyncFailure.malformedLocalEvidence
        }
        let revision = command.draft.expectedRevision.rawValue
        guard revision > 0, revision < UInt64(Int64.max) else {
            throw ClientArchivePowerSyncFailure.malformedLocalEvidence
        }
        if let overlay = overlays.first,
           !overlay.matches(command, acceptedAtMilliseconds: acceptedAt) {
            throw ClientArchivePowerSyncFailure.malformedLocalEvidence
        }
        let terminalFields: [Any?] = [
            terminalPhase, terminalResultCode, terminalErrorCode,
            terminalEnvelopeSHA256, terminalRequestSHA256,
            terminalServerReceivedAt, terminalCompletedAt
        ]
        let terminalFieldCount = terminalFields.reduce(into: 0) { count, value in
            if value != nil { count += 1 }
        }
        switch state {
        case .queued, .applying:
            guard commandRows.count == 1,
                  overlays.count == 1, terminalFieldCount == 0 else {
                throw ClientArchivePowerSyncFailure.malformedLocalEvidence
            }
        case .applied, .superseded, .rejected, .resolved:
            guard terminalFieldCount >= 6,
                  let terminalPhase,
                  terminalEnvelopeSHA256 == fingerprint,
                  let terminalRequestSHA256,
                  let terminalServerReceivedAt,
                  let terminalCompletedAt,
                  terminalServerReceivedAt >= 0,
                  terminalCompletedAt >= terminalServerReceivedAt,
                  let envelopeJSON,
                  let clientCreatedAtMilliseconds = Int64(exactly:
                    (command.envelope.clientCreatedAt.timeIntervalSince1970 * 1_000)
                        .rounded(.towardZero)
                  ),
                  clientCreatedAtMilliseconds >= 0 else {
                throw ClientArchivePowerSyncFailure.malformedLocalEvidence
            }
            let request = ClientArchiveUploadRequest(
                operationId: command.envelope.operationId.rawValue,
                accountId: command.envelope.accountId.rawValue,
                actorPrincipalId: command.envelope.actorPrincipalId.rawValue,
                contractVersion: command.envelope.contractVersion.rawValue,
                clientCreatedAtMilliseconds: clientCreatedAtMilliseconds,
                clientId: command.draft.clientId.rawValue,
                expectedRevision: String(revision),
                fingerprint: fingerprint,
                envelopeJSON: envelopeJSON
            )
            guard terminalRequestSHA256
                    == LedgerPowerSyncUploadConnector.clientArchiveRequestSHA256(request) else {
                throw ClientArchivePowerSyncFailure.malformedLocalEvidence
            }
            switch state {
            case .applied, .superseded:
                guard terminalPhase == "applied",
                      terminalResultCode == "client_archived",
                      terminalErrorCode == nil else {
                    throw ClientArchivePowerSyncFailure.malformedLocalEvidence
                }
            case .rejected, .resolved:
                guard overlays.isEmpty,
                      terminalPhase == "rejected",
                      terminalResultCode == nil,
                      terminalErrorCode.map(SupabaseClientArchiveRPC.isKnownRejectionCode)
                        == true else {
                    throw ClientArchivePowerSyncFailure.malformedLocalEvidence
                }
            case .queued, .applying:
                break
            }
        }
        return OperationReceipt(operationId: command.envelope.operationId, localState: state)
    }
}

private struct ClientArchiveReplayCommand {
    private struct TypedEnvelope: Decodable {
        struct Payload: Decodable {
            let clientCreatedAtMilliseconds: Int64

            enum CodingKeys: String, CodingKey {
                case clientCreatedAtMilliseconds = "client_created_at_ms"
            }
        }

        let data: Payload
    }

    let operationId: String
    let operation: String
    let table: String
    let accountId: String
    let actorPrincipalId: String
    let contractVersion: String
    let clientCreatedAtMilliseconds: Int64
    let clientId: String
    let expectedRevision: String
    let fingerprint: String
    let envelopeJSON: String

    init(cursor: any SqlCursor) throws {
        let json = try cursor.getString(name: "data")
        let capturedStorageType = try cursor.getString(
            name: "client_created_at_type"
        )
        guard let bytes = json.data(using: .utf8),
              let typedEnvelope = try? JSONDecoder().decode(TypedEnvelope.self, from: bytes),
              let root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              Set(root.keys).isSuperset(of: ["id", "op", "type", "data"]),
              let operationId = root["id"] as? String,
              let operation = root["op"] as? String,
              let table = root["type"] as? String,
              let data = root["data"] as? [String: Any],
              Set(data.keys) == [
                "account_id", "actor_principal_id", "contract_version",
                "client_created_at_ms", "client_id", "expected_revision",
                "fingerprint", "envelope_json"
              ],
              let accountId = data["account_id"] as? String,
              let actorPrincipalId = data["actor_principal_id"] as? String,
              let contractVersion = data["contract_version"] as? String,
              let clientId = data["client_id"] as? String,
              let expectedRevision = data["expected_revision"] as? String,
              let fingerprint = data["fingerprint"] as? String,
              let envelopeJSON = data["envelope_json"] as? String,
              capturedStorageType == "integer" else {
            throw ClientArchivePowerSyncFailure.malformedLocalEvidence
        }
        self.operationId = operationId
        self.operation = operation
        self.table = table
        self.accountId = accountId
        self.actorPrincipalId = actorPrincipalId
        self.contractVersion = contractVersion
        clientCreatedAtMilliseconds = typedEnvelope.data.clientCreatedAtMilliseconds
        self.clientId = clientId
        self.expectedRevision = expectedRevision
        self.fingerprint = fingerprint
        self.envelopeJSON = envelopeJSON
    }

    func matches(
        _ command: ArchiveClientCommand,
        envelopeJSON expectedEnvelopeJSON: String,
        capturedAtMilliseconds expectedCapturedAtMilliseconds: Int64
    ) -> Bool {
        operationId == command.envelope.operationId.rawValue
            && operation == "PUT"
            && table == LedgerPowerSyncTable.clientArchiveCommands
            && accountId == command.envelope.accountId.rawValue
            && actorPrincipalId == command.envelope.actorPrincipalId.rawValue
            && contractVersion == command.envelope.contractVersion.rawValue
            && clientCreatedAtMilliseconds == expectedCapturedAtMilliseconds
            && clientCreatedAtMilliseconds >= 0
            && clientId == command.draft.clientId.rawValue
            && expectedRevision == String(command.draft.expectedRevision.rawValue)
            && fingerprint == command.fingerprint.sha256
            && envelopeJSON == expectedEnvelopeJSON
    }
}

private struct ClientArchiveReplayOverlay {
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
        _ command: ArchiveClientCommand,
        acceptedAtMilliseconds expectedAcceptedAtMilliseconds: Int64
    ) -> Bool {
        let expected = command.draft.expectedRevision.rawValue
        return accountId == command.envelope.accountId.rawValue
            && actorPrincipalId == command.envelope.actorPrincipalId.rawValue
            && clientId == command.draft.clientId.rawValue
            && operationId == command.envelope.operationId.rawValue
            && fingerprint == command.fingerprint.sha256
            && expectedRevision == String(expected)
            && expected > 0
            && expected < UInt64(Int64.max)
            && projectedRevision == Int64(expected) + 1
            && lifecycle == "archived"
            && acceptedAtMilliseconds == expectedAcceptedAtMilliseconds
    }
}

private struct ClientArchiveOperationRow {
    let operationId: String
    let accountId: String
    let principalId: String
    let contractVersion: String
    let fingerprint: String
    let clientId: String
    let localState: String
    let acceptedAt: Int64
    let updatedAt: Int64
    let commandType: String?
    let expectedRevision: String?
    let envelopeJSON: String?
    let terminalPhase: String?
    let terminalResultCode: String?
    let terminalErrorCode: String?
    let terminalEnvelopeSHA256: String?
    let terminalRequestSHA256: String?
    let terminalServerReceivedAt: Int64?
    let terminalCompletedAt: Int64?
    let overlayOperationId: String?
    let overlayAccountId: String?
    let overlayPrincipalId: String?
    let overlayClientId: String?
    let overlayFingerprint: String?
    let overlayExpectedRevision: String?
    let overlayProjectedRevision: Int64?
    let overlayLifecycle: String?
    let overlayAcceptedAt: Int64?
    let resultAccountId: String?
    let resultPrincipalId: String?
    let resultCommandType: String?
    let resultContractVersion: String?
    let resultFingerprint: String?
    let resultEnvelopeSHA256: String?
    let resultRequestSHA256: String?
    let resultSubjectId: String?
    let resultPhase: String?
    let resultCode: String?
    let resultErrorCode: String?
    let resultCapturedAt: Int64?
    let resultServerReceivedAt: Int64?
    let resultCompletedAt: Int64?

    init(cursor: any SqlCursor) throws {
        operationId = try cursor.getString(name: "id")
        accountId = try cursor.getString(name: "account_id")
        principalId = try cursor.getString(name: "actor_principal_id")
        contractVersion = try cursor.getString(name: "contract_version")
        fingerprint = try cursor.getString(name: "fingerprint")
        clientId = try cursor.getString(name: "subject_id")
        localState = try cursor.getString(name: "local_state")
        acceptedAt = try cursor.getInt64(name: "accepted_at_ms")
        updatedAt = try cursor.getInt64(name: "updated_at_ms")
        commandType = try cursor.getStringOptional(name: "command_type")
        expectedRevision = try cursor.getStringOptional(name: "command_expected_revision")
        envelopeJSON = try cursor.getStringOptional(name: "command_envelope_json")
        terminalPhase = try cursor.getStringOptional(name: "terminal_phase")
        terminalResultCode = try cursor.getStringOptional(name: "terminal_result_code")
        terminalErrorCode = try cursor.getStringOptional(name: "terminal_error_code")
        terminalEnvelopeSHA256 = try cursor.getStringOptional(name: "terminal_envelope_sha256")
        terminalRequestSHA256 = try cursor.getStringOptional(name: "terminal_request_sha256")
        terminalServerReceivedAt = try cursor.getInt64Optional(name: "terminal_server_received_at_ms")
        terminalCompletedAt = try cursor.getInt64Optional(name: "terminal_completed_at_ms")
        overlayOperationId = try cursor.getStringOptional(name: "overlay_operation_id")
        overlayAccountId = try cursor.getStringOptional(name: "overlay_account_id")
        overlayPrincipalId = try cursor.getStringOptional(name: "overlay_actor_principal_id")
        overlayClientId = try cursor.getStringOptional(name: "overlay_client_id")
        overlayFingerprint = try cursor.getStringOptional(name: "overlay_fingerprint")
        overlayExpectedRevision = try cursor.getStringOptional(name: "overlay_expected_revision")
        overlayProjectedRevision = try cursor.getInt64Optional(name: "overlay_projected_revision")
        overlayLifecycle = try cursor.getStringOptional(name: "overlay_lifecycle")
        overlayAcceptedAt = try cursor.getInt64Optional(name: "overlay_accepted_at_ms")
        resultAccountId = try cursor.getStringOptional(name: "result_account_id")
        resultPrincipalId = try cursor.getStringOptional(name: "result_actor_principal_id")
        resultCommandType = try cursor.getStringOptional(name: "result_command_type")
        resultContractVersion = try cursor.getStringOptional(name: "result_contract_version")
        resultFingerprint = try cursor.getStringOptional(name: "result_fingerprint")
        resultEnvelopeSHA256 = try cursor.getStringOptional(name: "result_envelope_sha256")
        resultRequestSHA256 = try cursor.getStringOptional(name: "result_request_sha256")
        resultSubjectId = try cursor.getStringOptional(name: "result_subject_id")
        resultPhase = try cursor.getStringOptional(name: "result_phase")
        resultCode = try cursor.getStringOptional(name: "result_code")
        resultErrorCode = try cursor.getStringOptional(name: "error_code")
        resultCapturedAt = try cursor.getInt64Optional(name: "result_client_created_at_ms")
        resultServerReceivedAt = try cursor.getInt64Optional(name: "server_received_at_ms")
        resultCompletedAt = try cursor.getInt64Optional(name: "completed_at_ms")
    }

    func snapshot(
        expectedOperationId: OperationID,
        accountId expectedAccountId: AccountID,
        principalId expectedPrincipalId: PrincipalID
    ) throws -> OperationSnapshot {
        guard operationId == expectedOperationId.rawValue,
              accountId == expectedAccountId.rawValue,
              principalId == expectedPrincipalId.rawValue,
              ClientArchiveOperationIdentity.isValid(expectedOperationId, accountId: expectedAccountId),
              commandType == "archive_client", acceptedAt >= 0, updatedAt >= acceptedAt,
              let revisionText = expectedRevision,
              let revision = UInt64(revisionText), String(revision) == revisionText,
              revision > 0, revision < UInt64(Int64.max),
              let envelopeJSON, let data = envelopeJSON.data(using: .utf8),
              let envelope = try? OperationContractCodec.decode(
                  OperationEnvelope<ArchiveClientPayload>.self, from: data
              ),
              (try? OperationContractCodec.encode(envelope)) == data,
              envelope.operationId.rawValue == operationId,
              envelope.accountId.rawValue == accountId,
              envelope.actorPrincipalId.rawValue == principalId,
              envelope.contractVersion.rawValue == contractVersion,
              envelope.payload.clientId.rawValue == clientId,
              envelope.preconditions == [
                  .expectedRevision(
                      subject: LedgerEntityReference(
                          kind: .client, id: try EntityID(validating: clientId)
                      ), revision: revision
                  )
              ],
              let typedFingerprint = try? OperationFingerprint(validating: fingerprint),
              (try? OperationFingerprint.make(for: envelope)) == typedFingerprint,
              let state = LocalOperationState(rawValue: localState) else {
            throw ClientArchivePowerSyncFailure.malformedLocalEvidence
        }
        try validateOverlay(state: state, revision: revision)
        let request = ClientArchiveUploadRequest(
            operationId: operationId, accountId: accountId,
            actorPrincipalId: principalId, contractVersion: contractVersion,
            clientCreatedAtMilliseconds: try Self.milliseconds(envelope.clientCreatedAt),
            clientId: clientId, expectedRevision: revisionText,
            fingerprint: fingerprint, envelopeJSON: envelopeJSON
        )
        let terminal = try terminalEvidence(
            request: request,
            expectedRequestSHA256: LedgerPowerSyncUploadConnector.clientArchiveRequestSHA256(request)
        )
        return OperationSnapshot(
            operationId: expectedOperationId, accountId: expectedAccountId,
            contractVersion: try OperationContractVersion(validating: contractVersion),
            fingerprint: typedFingerprint, acceptedAt: Self.date(acceptedAt),
            updatedAt: Self.date(updatedAt),
            state: try operationState(state, revision: revision, terminal: terminal)
        )
    }

    private func validateOverlay(state: LocalOperationState, revision: UInt64) throws {
        if let overlayOperationId {
            guard overlayOperationId == operationId, overlayAccountId == accountId,
                  overlayPrincipalId == principalId, overlayClientId == clientId,
                  overlayFingerprint == fingerprint,
                  overlayExpectedRevision == String(revision),
                  overlayProjectedRevision == Int64(revision) + 1,
                  overlayLifecycle == "archived", overlayAcceptedAt == acceptedAt else {
                throw ClientArchivePowerSyncFailure.malformedLocalEvidence
            }
        }
        switch state {
        case .queued, .applying:
            guard overlayOperationId != nil else {
                throw ClientArchivePowerSyncFailure.malformedLocalEvidence
            }
        case .rejected:
            guard overlayOperationId == nil else {
                throw ClientArchivePowerSyncFailure.malformedLocalEvidence
            }
        case .applied, .superseded, .resolved: break
        }
    }

    private func terminalEvidence(
        request: ClientArchiveUploadRequest,
        expectedRequestSHA256: String
    ) throws -> ClientArchiveTerminal? {
        let localFields: [Any?] = [terminalPhase, terminalResultCode,
            terminalErrorCode, terminalEnvelopeSHA256, terminalRequestSHA256,
            terminalServerReceivedAt, terminalCompletedAt]
        let local: ClientArchiveTerminal?
        if localFields.contains(where: { $0 != nil }) {
            guard let terminalPhase, terminalEnvelopeSHA256 == fingerprint,
                  terminalRequestSHA256 == expectedRequestSHA256,
                  let terminalServerReceivedAt, let terminalCompletedAt else {
                throw ClientArchivePowerSyncFailure.malformedLocalEvidence
            }
            local = try validatedTerminal(
                phase: terminalPhase, resultCode: terminalResultCode,
                errorCode: terminalErrorCode, receivedAt: terminalServerReceivedAt,
                completedAt: terminalCompletedAt
            )
        } else { local = nil }

        let resultFields: [Any?] = [resultAccountId, resultPrincipalId,
            resultCommandType, resultContractVersion, resultFingerprint,
            resultEnvelopeSHA256, resultRequestSHA256, resultSubjectId,
            resultPhase, resultCode, resultErrorCode, resultCapturedAt,
            resultServerReceivedAt, resultCompletedAt]
        guard resultFields.contains(where: { $0 != nil }) else { return local }
        guard resultAccountId == accountId, resultPrincipalId == principalId,
              resultCommandType == "archive_client",
              resultContractVersion == contractVersion,
              resultFingerprint == fingerprint, resultEnvelopeSHA256 == fingerprint,
              resultRequestSHA256 == expectedRequestSHA256,
              resultSubjectId == clientId,
              resultCapturedAt == request.clientCreatedAtMilliseconds,
              let resultPhase, let resultServerReceivedAt, let resultCompletedAt else {
            throw ClientArchivePowerSyncFailure.malformedLocalEvidence
        }
        let downloaded = try validatedTerminal(
            phase: resultPhase, resultCode: resultCode,
            errorCode: resultErrorCode, receivedAt: resultServerReceivedAt,
            completedAt: resultCompletedAt
        )
        guard local == nil || local == downloaded else {
            throw ClientArchivePowerSyncFailure.malformedLocalEvidence
        }
        return downloaded
    }

    private func validatedTerminal(
        phase: String, resultCode: String?, errorCode: String?,
        receivedAt: Int64, completedAt: Int64
    ) throws -> ClientArchiveTerminal {
        guard receivedAt >= 0, completedAt >= receivedAt else {
            throw ClientArchivePowerSyncFailure.malformedLocalEvidence
        }
        switch phase {
        case "applied":
            guard resultCode == "client_archived", errorCode == nil else {
                throw ClientArchivePowerSyncFailure.malformedLocalEvidence
            }
        case "rejected":
            guard resultCode == nil,
                  errorCode.map(SupabaseClientArchiveRPC.isKnownRejectionCode) == true else {
                throw ClientArchivePowerSyncFailure.malformedLocalEvidence
            }
        default: throw ClientArchivePowerSyncFailure.malformedLocalEvidence
        }
        return ClientArchiveTerminal(
            phase: phase, resultCode: resultCode, errorCode: errorCode,
            receivedAt: Self.date(receivedAt), completedAt: Self.date(completedAt)
        )
    }

    private func operationState(
        _ state: LocalOperationState,
        revision: UInt64,
        terminal: ClientArchiveTerminal?
    ) throws -> OperationState {
        let subject = LedgerEntityReference(
            kind: .client, id: try EntityID(validating: clientId)
        )
        switch state {
        case .queued: return .queued(attemptCount: 0, lastTransientError: nil)
        case .applying: return .applying(attempt: 1, startedAt: Self.date(updatedAt))
        case .applied, .superseded:
            guard let terminal, terminal.phase == "applied", let code = terminal.resultCode else {
                throw ClientArchivePowerSyncFailure.malformedLocalEvidence
            }
            let applied = AppliedOperationResult(
                resultCode: try ApplicationResultCode(validating: code),
                serverReceivedAt: terminal.receivedAt,
                completedAt: terminal.completedAt,
                affectedRevisions: [EntityRevision(entity: subject, revision: revision + 1)]
            )
            if state == .superseded {
                return .superseded(
                    original: applied,
                    correction: CorrectionReference(
                        operationId: try OperationID(validating: operationId),
                        correctedAt: Self.date(updatedAt)
                    )
                )
            }
            return .applied(applied)
        case .rejected, .resolved:
            guard let terminal, terminal.phase == "rejected", let code = terminal.errorCode else {
                throw ClientArchivePowerSyncFailure.malformedLocalEvidence
            }
            let conflict = Self.isConflict(code)
            let rejection = OperationRejection(
                error: ApplicationErrorSummary(
                    code: try ApplicationErrorCode(validating: code),
                    category: conflict ? .conflict : (code == "contract_unsupported" ? .unsupportedContract : .validation),
                    retryDisposition: conflict ? .afterUserCorrection : (code == "contract_unsupported" ? .afterClientUpdate : .never)
                ),
                rejectedAt: terminal.completedAt,
                conflictingEntities: conflict ? [subject] : []
            )
            if state == .resolved {
                return .resolved(
                    rejection: rejection,
                    resolution: RejectionResolution(
                        code: try ResolutionCode(validating: "retry_replaced"),
                        resolvedAt: Self.date(updatedAt)
                    )
                )
            }
            return .rejected(rejection)
        }
    }

    private static func isConflict(_ code: String) -> Bool {
        code.contains("revision") || code.contains("lifecycle")
            || code.contains("conflict") || code.contains("not_active")
    }

    private static func date(_ milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }

    private static func milliseconds(_ date: Date) throws -> Int64 {
        let value = date.timeIntervalSince1970 * 1_000
        guard value.isFinite,
              let milliseconds = Int64(exactly: value.rounded(.towardZero)),
              milliseconds >= 0 else {
            throw ClientArchivePowerSyncFailure.malformedLocalEvidence
        }
        return milliseconds
    }
}

private struct ClientArchiveTerminal: Equatable {
    let phase: String
    let resultCode: String?
    let errorCode: String?
    let receivedAt: Date
    let completedAt: Date
}
