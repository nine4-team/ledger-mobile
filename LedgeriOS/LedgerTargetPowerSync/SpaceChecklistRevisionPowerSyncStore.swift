import Foundation
import LedgerTargetCore
import PowerSync

enum SpaceChecklistRevisionPowerSyncFailure: Error, Equatable, Sendable {
    case invalidAcceptanceTime
    case invalidOperationIdentity
    case malformedLocalEvidence
    case operationNotFound
}

public enum SpaceChecklistRevisionOperationIdentity {
    public static func make(accountId: AccountID, uuid: UUID) throws -> OperationID {
        try AccountBoundOperationIdentity.make(
            family: .spaceChecklistRevision,
            accountId: accountId,
            uuid: uuid
        )
    }

    static func isValid(_ operationId: OperationID, accountId: AccountID) -> Bool {
        AccountBoundOperationIdentity.isValid(
            operationId,
            family: .spaceChecklistRevision,
            accountId: accountId
        )
    }
}

enum SpaceChecklistRevisionPowerSyncStoreCheckpoint: Equatable, Sendable {
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

actor SpaceChecklistRevisionPowerSyncStore:
    SpaceChecklistRevising, RejectedOperationRecoveryQuerying
{
    private let database: any PowerSyncDatabaseProtocol
    private let accountId: AccountID
    private let principalId: PrincipalID
    private let now: @Sendable () -> Date
    private let checkpoint: @Sendable (SpaceChecklistRevisionPowerSyncStoreCheckpoint) throws -> Void
    private let watchRegistry = SpaceChecklistRevisionWatchRegistry()
    private var isClosed = false

    init(
        database: any PowerSyncDatabaseProtocol,
        accountId: AccountID,
        principalId: PrincipalID,
        now: @Sendable @escaping () -> Date = Date.init,
        checkpoint: @Sendable @escaping (
            SpaceChecklistRevisionPowerSyncStoreCheckpoint
        ) throws -> Void = { _ in }
    ) {
        self.database = database
        self.accountId = accountId
        self.principalId = principalId
        self.now = now
        self.checkpoint = checkpoint
    }

    func reviseChecklists(
        _ command: ReviseSpaceChecklistsCommand
    ) async throws -> OperationReceipt {
        guard !isClosed else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
        guard command.envelope.accountId == accountId else {
            throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
        }
        guard command.envelope.actorPrincipalId == principalId else {
            throw LedgerOfflineClientRuntimeFailure.principalScopeMismatch
        }
        guard SpaceChecklistRevisionOperationIdentity.isValid(
            command.envelope.operationId,
            accountId: accountId
        ) else {
            throw SpaceChecklistRevisionPowerSyncFailure.invalidOperationIdentity
        }

        let envelopeJSON = try Self.canonicalJSON(command.envelope)
        let collectionJSON = try Self.canonicalJSON(command.draft.collection)
        let capturedAtMilliseconds = try Self.milliseconds(command.envelope.clientCreatedAt)
        guard command.envelope.clientCreatedAt == Self.date(capturedAtMilliseconds) else {
            throw SpaceChecklistRevisionFailure.invalidEncodedCommand
        }
        let acceptedAtMilliseconds = try Self.milliseconds(now())
        let expectedRevision = command.draft.expectedRevision.rawValue
        guard expectedRevision > 0, expectedRevision < UInt64(Int64.max) else {
            throw SpaceChecklistRevisionFailure.revisionPreconditionMismatch
        }
        let testCheckpoint = checkpoint
        let scopedAccountId = accountId
        let scopedPrincipalId = principalId

        try Task.checkCancellation()
        do {
            try testCheckpoint(.beforeTransaction)
            let receipt = try await database.writeTransaction { transaction in
                try Task.checkCancellation()
                let ownership = try LocalOperationIdentityGuard.inspect(
                    transaction: transaction,
                    operationId: command.envelope.operationId,
                    expectedFamily: .reviseSpaceChecklists,
                    expectedFingerprint: command.fingerprint.sha256,
                    checkpoint: { point in
                        switch point {
                        case .inventoryConstruction: try testCheckpoint(.inventoryConstruction)
                        case .inventoryRead: try testCheckpoint(.inventoryRead)
                        }
                    }
                )
                try testCheckpoint(.afterOwnershipInspection)

                let operation = try transaction.getOptional(
                    sql: Self.operationEvidenceSQL,
                    parameters: [command.envelope.operationId.rawValue]
                ) { try SpaceChecklistRevisionOperationEvidence(cursor: $0) }
                if let operation {
                    guard ownership == .matchingOwner else {
                        throw SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence
                    }
                    try operation.validate(
                        command: command,
                        envelopeJSON: envelopeJSON
                    )
                    let commandRows = try transaction.getAll(
                        sql: Self.commandEvidenceSQL,
                        parameters: [command.envelope.operationId.rawValue]
                    ) { try SpaceChecklistRevisionCommandEvidence(cursor: $0) }
                    let overlays = try transaction.getAll(
                        sql: Self.overlayEvidenceSQL,
                        parameters: [command.envelope.operationId.rawValue]
                    ) { try SpaceChecklistRevisionOverlayEvidence(cursor: $0) }
                    guard commandRows.count <= 1, overlays.count <= 1,
                          commandRows.allSatisfy({
                              $0.matches(
                                  command: command,
                                  capturedAtMilliseconds: capturedAtMilliseconds,
                                  collectionJSON: collectionJSON,
                                  envelopeJSON: envelopeJSON
                              )
                          }),
                          overlays.allSatisfy({
                              $0.matches(
                                  command: command,
                                  acceptedAtMilliseconds: operation.acceptedAtMilliseconds,
                                  collectionJSON: collectionJSON
                              )
                          }),
                          let state = LocalOperationState(rawValue: operation.localState)
                    else {
                        throw SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence
                    }
                    switch state {
                    case .queued, .applying:
                        guard commandRows.count == 1, overlays.count == 1 else {
                            throw SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence
                        }
                    case .applied:
                        if overlays.isEmpty {
                            guard operation.checklistReadbackRevision
                                    == Int64(expectedRevision) + 1 else {
                                throw SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence
                            }
                            let authoritativeRevision = try transaction.getOptional(
                                sql: """
                                SELECT revision FROM \(LedgerPowerSyncTable.spaces)
                                WHERE account_id = ? AND id = ?
                                """,
                                parameters: [
                                    scopedAccountId.rawValue,
                                    command.draft.spaceId.rawValue
                                ]
                            ) { try $0.getInt64(name: "revision") }
                            guard let authoritativeRevision,
                                  authoritativeRevision > 0,
                                  UInt64(authoritativeRevision) >= expectedRevision + 1 else {
                                throw SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence
                            }
                        } else if operation.checklistReadbackRevision != nil {
                            throw SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence
                        }
                    case .rejected:
                        guard overlays.isEmpty else {
                            throw SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence
                        }
                    case .superseded, .resolved:
                        throw SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence
                    }
                    return OperationReceipt(
                        operationId: command.envelope.operationId,
                        localState: state
                    )
                }
                guard ownership == .unclaimed else {
                    throw SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence
                }
                let space = try transaction.getOptional(
                    sql: """
                    SELECT lifecycle, revision
                    FROM \(LedgerPowerSyncTable.spaces)
                    WHERE account_id = ? AND id = ?
                    """,
                    parameters: [scopedAccountId.rawValue, command.draft.spaceId.rawValue]
                ) { cursor in
                    (
                        try cursor.getString(name: "lifecycle"),
                        try cursor.getInt64(name: "revision")
                    )
                }
                guard let space else { throw SpaceChecklistRevisionFailure.subjectMismatch }
                guard space.0 == "active" else {
                    throw SpaceChecklistRevisionFailure.localAcceptanceFailed
                }
                guard space.1 > 0, UInt64(space.1) == expectedRevision else {
                    throw SpaceChecklistRevisionFailure.revisionPreconditionMismatch
                }

                _ = try transaction.execute(
                    sql: """
                    DELETE FROM \(LedgerPowerSyncTable.spaceChecklistRevisionOverlays)
                    WHERE account_id = ? AND space_id = ?
                      AND projected_revision <= ?
                      AND operation_id IN (
                        SELECT id FROM \(LedgerPowerSyncTable.localOperations)
                        WHERE local_state = 'applied'
                          AND command_type = 'revise_space_checklists'
                      )
                    """,
                    parameters: [
                        scopedAccountId.rawValue,
                        command.draft.spaceId.rawValue,
                        Int64(expectedRevision)
                    ]
                )
                let overlayCount = try transaction.get(
                    sql: """
                    SELECT count(*)
                    FROM \(LedgerPowerSyncTable.spaceChecklistRevisionOverlays)
                    WHERE account_id = ? AND space_id = ?
                    """,
                    parameters: [scopedAccountId.rawValue, command.draft.spaceId.rawValue]
                ) { try $0.getInt64(index: 0) }
                guard overlayCount == 0 else {
                    throw SpaceChecklistRevisionFailure.localAcceptanceFailed
                }

                try Task.checkCancellation()
                try testCheckpoint(.operationWrite)
                _ = try transaction.execute(
                    sql: """
                    INSERT INTO \(LedgerPowerSyncTable.localOperations) (
                      id, account_id, actor_principal_id, contract_version,
                      fingerprint, subject_id, local_state, accepted_at_ms,
                      updated_at_ms, command_type, command_expected_revision,
                      command_envelope_json
                    ) VALUES (?, ?, ?, ?, ?, ?, 'queued', ?, ?,
                              'revise_space_checklists', ?, ?)
                    """,
                    parameters: [
                        command.envelope.operationId.rawValue,
                        scopedAccountId.rawValue,
                        scopedPrincipalId.rawValue,
                        command.envelope.contractVersion.rawValue,
                        command.fingerprint.sha256,
                        command.draft.spaceId.rawValue,
                        acceptedAtMilliseconds,
                        acceptedAtMilliseconds,
                        String(expectedRevision),
                        envelopeJSON
                    ]
                )

                try Task.checkCancellation()
                try testCheckpoint(.projectionWrite)
                _ = try transaction.execute(
                    sql: """
                    INSERT INTO \(LedgerPowerSyncTable.spaceChecklistRevisionOverlays) (
                      id, account_id, actor_principal_id, space_id, operation_id,
                      fingerprint, expected_revision, projected_revision,
                      collection_json, accepted_at_ms
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    parameters: [
                        command.envelope.operationId.rawValue,
                        scopedAccountId.rawValue,
                        scopedPrincipalId.rawValue,
                        command.draft.spaceId.rawValue,
                        command.envelope.operationId.rawValue,
                        command.fingerprint.sha256,
                        String(expectedRevision),
                        Int64(expectedRevision) + 1,
                        collectionJSON,
                        acceptedAtMilliseconds
                    ]
                )

                try Task.checkCancellation()
                try testCheckpoint(.commandWrite)
                _ = try transaction.execute(
                    sql: """
                    INSERT INTO \(LedgerPowerSyncTable.spaceChecklistRevisionCommands) (
                      id, account_id, actor_principal_id, contract_version,
                      client_created_at_ms, space_id, expected_revision,
                      collection_json, fingerprint, envelope_json
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    parameters: [
                        command.envelope.operationId.rawValue,
                        scopedAccountId.rawValue,
                        scopedPrincipalId.rawValue,
                        command.envelope.contractVersion.rawValue,
                        capturedAtMilliseconds,
                        command.draft.spaceId.rawValue,
                        String(expectedRevision),
                        collectionJSON,
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
            throw SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence
        } catch let failure as LedgerOfflineClientRuntimeFailure {
            throw failure
        } catch let failure as OperationContractFailure {
            throw failure
        } catch let failure as SpaceChecklistRevisionPowerSyncFailure {
            throw failure
        } catch let failure as SpaceChecklistRevisionFailure {
            throw failure
        } catch {
            throw SpaceChecklistRevisionFailure.localAcceptanceFailed
        }
    }

    nonisolated func watchOperation(
        _ operationId: OperationID
    ) -> AsyncThrowingStream<OperationSnapshot, Error> {
        guard SpaceChecklistRevisionOperationIdentity.isValid(
            operationId,
            accountId: accountId
        ) else {
            return AsyncThrowingStream { continuation in
                continuation.finish(
                    throwing: SpaceChecklistRevisionPowerSyncFailure.invalidOperationIdentity
                )
            }
        }
        return AsyncThrowingStream { continuation in
            let id = UUID()
            let handle = SpaceChecklistRevisionWatchHandle()
            let registration = Task { await watchRegistry.register(id: id, handle: handle) }
            let task = Task {
                let admitted = await registration.value
                guard admitted, !Task.isCancelled else {
                    continuation.finish()
                    if admitted { await watchRegistry.finished(id: id) }
                    return
                }
                do {
                    let updates = try database.watch(
                        sql: Self.watchSQL,
                        parameters: [operationId.rawValue]
                    ) { try SpaceChecklistRevisionWatchEvidence(cursor: $0) }
                    for try await rows in updates {
                        try Task.checkCancellation()
                        guard rows.count <= 1 else {
                            throw SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence
                        }
                        guard let row = rows.first else {
                            throw SpaceChecklistRevisionPowerSyncFailure.operationNotFound
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
                } catch {
                    continuation.finish(throwing: error)
                }
                await watchRegistry.finished(id: id)
            }
            handle.install(task)
            continuation.onTermination = { _ in handle.cancel() }
        }
    }

    nonisolated func watchRejectedOperations(
        _ request: RejectedOperationRecoveryRequest
    ) -> AsyncThrowingStream<RejectedOperationRecoverySnapshot, Error> {
        do {
            try Self.validateRecoveryRequest(
                request,
                accountId: accountId,
                principalId: principalId
            )
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
        return AsyncThrowingStream { continuation in
            let id = UUID()
            let handle = SpaceChecklistRevisionWatchHandle()
            let registration = Task { await watchRegistry.register(id: id, handle: handle) }
            let task = Task {
                let admitted = await registration.value
                guard admitted, !Task.isCancelled else {
                    continuation.finish()
                    if admitted { await watchRegistry.finished(id: id) }
                    return
                }
                do {
                    let rows = try database.watch(
                        sql: Self.recoveryWatchSQL,
                        parameters: [
                            request.accountId.rawValue,
                            request.actorPrincipalId.rawValue,
                            request.subject.id.rawValue
                        ]
                    ) { try SpaceChecklistRecoveryEvidence(cursor: $0) }
                    for try await evidence in rows {
                        try Task.checkCancellation()
                        let candidates = try evidence.map {
                            try $0.candidate(request: request)
                        }
                        continuation.yield(try RejectedOperationRecoverySnapshot(
                            request: request,
                            candidates: candidates
                        ))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
                await watchRegistry.finished(id: id)
            }
            handle.install(task)
            continuation.onTermination = { _ in handle.cancel() }
        }
    }

    func rejectedOperations(
        _ request: RejectedOperationRecoveryRequest
    ) async throws -> RejectedOperationRecoverySnapshot {
        guard !isClosed else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
        try Self.validateRecoveryRequest(
            request,
            accountId: accountId,
            principalId: principalId
        )
        try Task.checkCancellation()
        let evidence = try await database.getAll(
            sql: Self.recoveryWatchSQL,
            parameters: [
                request.accountId.rawValue,
                request.actorPrincipalId.rawValue,
                request.subject.id.rawValue
            ]
        ) { try SpaceChecklistRecoveryEvidence(cursor: $0) }
        try Task.checkCancellation()
        return try RejectedOperationRecoverySnapshot(
            request: request,
            candidates: evidence.map { try $0.candidate(request: request) }
        )
    }

    func cancelAndDrainWatches() async {
        isClosed = true
        await watchRegistry.cancelAndDrain()
    }

    fileprivate nonisolated static func canonicalJSON<Value: Encodable>(
        _ value: Value
    ) throws -> String {
        guard let json = String(
            data: try OperationContractCodec.encode(value),
            encoding: .utf8
        ) else {
            throw SpaceChecklistRevisionFailure.invalidEncodedCommand
        }
        return json
    }

    fileprivate nonisolated static func milliseconds(_ date: Date) throws -> Int64 {
        let value = date.timeIntervalSince1970 * 1_000
        guard value.isFinite,
              let milliseconds = Int64(exactly: value.rounded(.towardZero)),
              milliseconds >= 0 else {
            throw SpaceChecklistRevisionPowerSyncFailure.invalidAcceptanceTime
        }
        return milliseconds
    }

    nonisolated static func date(_ milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }

    private static let operationEvidenceSQL = """
        SELECT account_id, actor_principal_id, contract_version, fingerprint,
               subject_id, local_state, accepted_at_ms, updated_at_ms,
               command_type, command_expected_revision, command_envelope_json,
               terminal_phase, terminal_result_code, terminal_error_code,
               terminal_envelope_sha256, terminal_request_sha256,
               terminal_server_received_at_ms, terminal_completed_at_ms,
               checklist_readback_revision
        FROM \(LedgerPowerSyncTable.localOperations)
        WHERE id = ?
        """

    private static let commandEvidenceSQL = """
        SELECT json_extract(data, '$.id') AS operation_id,
               json_extract(data, '$.op') AS operation,
               json_extract(data, '$.type') AS table_name,
               json_extract(data, '$.data.account_id') AS account_id,
               json_extract(data, '$.data.actor_principal_id') AS actor_principal_id,
               json_extract(data, '$.data.contract_version') AS contract_version,
               json_extract(data, '$.data.client_created_at_ms') AS client_created_at_ms,
               json_extract(data, '$.data.space_id') AS space_id,
               json_extract(data, '$.data.expected_revision') AS expected_revision,
               json_extract(data, '$.data.collection_json') AS collection_json,
               json_extract(data, '$.data.fingerprint') AS fingerprint,
               json_extract(data, '$.data.envelope_json') AS envelope_json
        FROM ps_crud
        WHERE json_valid(data) = 1 AND json_extract(data, '$.id') = ?
          AND json_extract(data, '$.type') =
            '\(LedgerPowerSyncTable.spaceChecklistRevisionCommands)'
        """

    private static let overlayEvidenceSQL = """
        SELECT account_id, actor_principal_id, space_id, operation_id,
               fingerprint, expected_revision, projected_revision,
               collection_json, accepted_at_ms
        FROM \(LedgerPowerSyncTable.spaceChecklistRevisionOverlays)
        WHERE operation_id = ?
        """

    private static let watchSQL = """
        SELECT operation.id, operation.account_id,
               operation.actor_principal_id, operation.contract_version,
               operation.fingerprint, operation.subject_id,
               operation.local_state, operation.accepted_at_ms,
               operation.updated_at_ms, operation.command_type,
               operation.command_expected_revision,
               operation.command_envelope_json, operation.terminal_phase,
               operation.terminal_result_code, operation.terminal_error_code,
               operation.terminal_envelope_sha256,
               operation.terminal_request_sha256,
               operation.terminal_server_received_at_ms,
               operation.terminal_completed_at_ms,
               operation.checklist_readback_revision,
               authoritative.revision AS authoritative_revision,
               overlay.operation_id AS overlay_operation_id,
               overlay.account_id AS overlay_account_id,
               overlay.actor_principal_id AS overlay_actor_principal_id,
               overlay.space_id AS overlay_space_id,
               overlay.fingerprint AS overlay_fingerprint,
               overlay.expected_revision AS overlay_expected_revision,
               overlay.projected_revision AS overlay_projected_revision,
               overlay.collection_json AS overlay_collection_json,
               overlay.accepted_at_ms AS overlay_accepted_at_ms
        FROM \(LedgerPowerSyncTable.localOperations) AS operation
        LEFT JOIN \(LedgerPowerSyncTable.spaceChecklistRevisionOverlays) AS overlay
          ON overlay.operation_id = operation.id
        LEFT JOIN \(LedgerPowerSyncTable.spaces) AS authoritative
          ON authoritative.account_id = operation.account_id
         AND authoritative.id = operation.subject_id
        WHERE operation.id = ?
        """

    private static let recoveryWatchSQL = """
        SELECT source.id, source.account_id, source.actor_principal_id,
               source.contract_version, source.fingerprint, source.subject_id,
               source.local_state, source.accepted_at_ms, source.updated_at_ms,
               source.command_type, source.command_expected_revision,
               source.command_envelope_json, source.terminal_phase,
               source.terminal_result_code, source.terminal_error_code,
               source.terminal_envelope_sha256, source.terminal_request_sha256,
               source.terminal_server_received_at_ms,
               source.terminal_completed_at_ms, source.checklist_readback_revision
        FROM \(LedgerPowerSyncTable.localOperations) AS source
        WHERE source.account_id = ? AND source.actor_principal_id = ?
          AND source.subject_id = ?
          AND source.command_type = 'revise_space_checklists'
          AND source.local_state = 'rejected'
        ORDER BY source.terminal_completed_at_ms DESC,
                 source.accepted_at_ms DESC, source.id ASC
        """

    private nonisolated static func validateRecoveryRequest(
        _ request: RejectedOperationRecoveryRequest,
        accountId: AccountID,
        principalId: PrincipalID
    ) throws {
        guard request.accountId == accountId else {
            throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
        }
        guard request.actorPrincipalId == principalId else {
            throw LedgerOfflineClientRuntimeFailure.principalScopeMismatch
        }
        guard request.family == .reviseSpaceChecklists,
              request.subject.kind == .space else {
            throw RejectedOperationRecoveryFailure.invalidRequest
        }
    }
}

private struct SpaceChecklistRevisionOperationEvidence {
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
    let terminalPhase: String?
    let terminalResultCode: String?
    let terminalErrorCode: String?
    let terminalEnvelopeSHA256: String?
    let terminalRequestSHA256: String?
    let terminalServerReceivedAtMilliseconds: Int64?
    let terminalCompletedAtMilliseconds: Int64?
    let checklistReadbackRevision: Int64?

    init(cursor: any SqlCursor) throws {
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
        terminalPhase = try cursor.getStringOptional(name: "terminal_phase")
        terminalResultCode = try cursor.getStringOptional(name: "terminal_result_code")
        terminalErrorCode = try cursor.getStringOptional(name: "terminal_error_code")
        terminalEnvelopeSHA256 = try cursor.getStringOptional(name: "terminal_envelope_sha256")
        terminalRequestSHA256 = try cursor.getStringOptional(name: "terminal_request_sha256")
        terminalServerReceivedAtMilliseconds = try cursor.getInt64Optional(
            name: "terminal_server_received_at_ms"
        )
        terminalCompletedAtMilliseconds = try cursor.getInt64Optional(
            name: "terminal_completed_at_ms"
        )
        checklistReadbackRevision = try cursor.getInt64Optional(
            name: "checklist_readback_revision"
        )
    }

    func validate(
        command: ReviseSpaceChecklistsCommand,
        envelopeJSON expectedEnvelopeJSON: String
    ) throws {
        guard accountId == command.envelope.accountId.rawValue,
              principalId == command.envelope.actorPrincipalId.rawValue,
              contractVersion == command.envelope.contractVersion.rawValue,
              fingerprint == command.fingerprint.sha256,
              subjectId == command.draft.spaceId.rawValue,
              commandType == "revise_space_checklists",
              expectedRevision == String(command.draft.expectedRevision.rawValue),
              envelopeJSON == expectedEnvelopeJSON,
              acceptedAtMilliseconds >= 0,
              updatedAtMilliseconds >= acceptedAtMilliseconds,
              let state = LocalOperationState(rawValue: localState) else {
            throw SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence
        }
        let terminalFields: [Any?] = [
            terminalPhase, terminalResultCode, terminalErrorCode,
            terminalEnvelopeSHA256, terminalRequestSHA256,
            terminalServerReceivedAtMilliseconds, terminalCompletedAtMilliseconds
        ]
        let expectedReadbackRevision = Int64(
            exactly: command.draft.expectedRevision.rawValue
        ).flatMap { $0 < Int64.max ? $0 + 1 : nil }
        switch state {
        case .queued, .applying:
            guard !terminalFields.contains(where: { $0 != nil }),
                  checklistReadbackRevision == nil else {
                throw SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence
            }
        case .applied:
            guard terminalPhase == "applied",
                  terminalResultCode == "space_checklists_revised",
                  terminalErrorCode == nil,
                  (checklistReadbackRevision == nil
                    || checklistReadbackRevision == expectedReadbackRevision) else {
                throw SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence
            }
        case .rejected:
            guard terminalPhase == "rejected", terminalResultCode == nil,
                  checklistReadbackRevision == nil,
                  terminalErrorCode.map(
                      SupabaseSpaceChecklistRevisionRPC.isKnownRejectionCode
                  ) == true else {
                throw SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence
            }
        case .superseded, .resolved:
            throw SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence
        }
        if state == .applied || state == .rejected {
            guard terminalEnvelopeSHA256 == fingerprint,
                  terminalRequestSHA256?.count == 64,
                  let received = terminalServerReceivedAtMilliseconds,
                  let completed = terminalCompletedAtMilliseconds,
                  received >= 0, completed >= received else {
                throw SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence
            }
        }
    }
}

private struct SpaceChecklistRecoveryEvidence {
    let id: String
    let operation: SpaceChecklistRevisionOperationEvidence

    init(cursor: any SqlCursor) throws {
        id = try cursor.getString(name: "id")
        operation = try SpaceChecklistRevisionOperationEvidence(cursor: cursor)
    }

    func candidate(
        request: RejectedOperationRecoveryRequest
    ) throws -> RejectedOperationRecoveryCandidate {
        guard let operationId = try? OperationID(validating: id),
              SpaceChecklistRevisionOperationIdentity.isValid(
                  operationId,
                  accountId: request.accountId
              ),
              operation.localState == LocalOperationState.rejected.rawValue,
              let envelopeJSON = operation.envelopeJSON,
              let envelopeData = envelopeJSON.data(using: .utf8),
              let envelope = try? OperationContractCodec.decode(
                  OperationEnvelope<ReviseSpaceChecklistsPayload>.self,
                  from: envelopeData
              ),
              (try? OperationContractCodec.encode(envelope)) == envelopeData,
              let expectedRevisionText = operation.expectedRevision,
              let expectedRevision = UInt64(expectedRevisionText),
              String(expectedRevision) == expectedRevisionText,
              expectedRevision > 0,
              expectedRevision < UInt64(Int64.max),
              let accepted = try? Self.exactDate(operation.acceptedAtMilliseconds),
              let updated = try? Self.exactDate(operation.updatedAtMilliseconds),
              let rejectedMilliseconds = operation.terminalCompletedAtMilliseconds,
              let rejected = try? Self.exactDate(rejectedMilliseconds),
              let errorCode = operation.terminalErrorCode,
              SupabaseSpaceChecklistRevisionRPC.isKnownRejectionCode(errorCode)
        else {
            throw RejectedOperationRecoveryFailure.localEvidenceMalformed
        }

        let draft: SpaceChecklistRevisionDraft
        let command: ReviseSpaceChecklistsCommand
        do {
            draft = try SpaceChecklistRevisionDraft(
                accountId: envelope.accountId,
                actorPrincipalId: envelope.actorPrincipalId,
                operationContractVersion: envelope.contractVersion,
                spaceId: envelope.payload.spaceId,
                collection: envelope.payload.collection,
                expectedRevision: ExpectedSpaceRevision(expectedRevision),
                capturedAt: envelope.clientCreatedAt
            )
            command = try ReviseSpaceChecklistsCommand(
                operationId: operationId,
                draft: draft
            )
            try operation.validate(command: command, envelopeJSON: envelopeJSON)
        } catch {
            throw RejectedOperationRecoveryFailure.localEvidenceMalformed
        }

        let uploadRequest: SpaceChecklistRevisionUploadRequest
        do {
            uploadRequest = SpaceChecklistRevisionUploadRequest(
                operationId: operationId.rawValue,
                accountId: envelope.accountId.rawValue,
                actorPrincipalId: envelope.actorPrincipalId.rawValue,
                contractVersion: envelope.contractVersion.rawValue,
                clientCreatedAtMilliseconds:
                    try SpaceChecklistRevisionPowerSyncStore.milliseconds(
                        envelope.clientCreatedAt
                    ),
                spaceId: envelope.payload.spaceId.rawValue,
                expectedRevision: expectedRevisionText,
                collectionJSON:
                    try SpaceChecklistRevisionPowerSyncStore.canonicalJSON(
                        envelope.payload.collection
                    ),
                fingerprint: command.fingerprint.sha256,
                envelopeJSON: envelopeJSON
            )
        } catch {
            throw RejectedOperationRecoveryFailure.localEvidenceMalformed
        }
        guard operation.terminalRequestSHA256
                == LedgerPowerSyncUploadConnector
                    .spaceChecklistRevisionRequestSHA256(uploadRequest) else {
            throw RejectedOperationRecoveryFailure.localEvidenceMalformed
        }

        let isConflict = errorCode.contains("conflict")
            || errorCode.contains("revision")
        let subject = command.subject
        let rejection: OperationRejection
        do {
            rejection = OperationRejection(
                error: ApplicationErrorSummary(
                    code: try ApplicationErrorCode(validating: errorCode),
                    category: errorCode == "contract_unsupported"
                        ? .unsupportedContract
                        : (isConflict ? .conflict : .validation),
                    retryDisposition: errorCode == "contract_unsupported"
                        ? .afterClientUpdate
                        : (isConflict ? .afterUserCorrection : .never)
                ),
                rejectedAt: rejected,
                conflictingEntities: isConflict ? [subject] : []
            )
            return try RejectedOperationRecoveryCandidate(
                command: .reviseSpaceChecklists(command),
                acceptedAt: accepted,
                updatedAt: updated,
                rejection: rejection
            ).validating(request: request)
        } catch {
            throw RejectedOperationRecoveryFailure.localEvidenceMalformed
        }
    }

    private static func exactDate(_ milliseconds: Int64) throws -> Date {
        guard milliseconds >= 0 else {
            throw RejectedOperationRecoveryFailure.localEvidenceMalformed
        }
        let date = SpaceChecklistRevisionPowerSyncStore.date(milliseconds)
        let roundTrip = date.timeIntervalSince1970 * 1_000
        guard roundTrip.isFinite,
              Int64(exactly: roundTrip.rounded()) == milliseconds else {
            throw RejectedOperationRecoveryFailure.localEvidenceMalformed
        }
        return date
    }
}

private struct SpaceChecklistRevisionCommandEvidence {
    let operationId: String?
    let operation: String?
    let tableName: String?
    let accountId: String?
    let principalId: String?
    let contractVersion: String?
    let capturedAtMilliseconds: Int64?
    let spaceId: String?
    let expectedRevision: String?
    let collectionJSON: String?
    let fingerprint: String?
    let envelopeJSON: String?

    init(cursor: any SqlCursor) throws {
        operationId = try cursor.getStringOptional(name: "operation_id")
        operation = try cursor.getStringOptional(name: "operation")
        tableName = try cursor.getStringOptional(name: "table_name")
        accountId = try cursor.getStringOptional(name: "account_id")
        principalId = try cursor.getStringOptional(name: "actor_principal_id")
        contractVersion = try cursor.getStringOptional(name: "contract_version")
        capturedAtMilliseconds = try cursor.getInt64Optional(name: "client_created_at_ms")
        spaceId = try cursor.getStringOptional(name: "space_id")
        expectedRevision = try cursor.getStringOptional(name: "expected_revision")
        collectionJSON = try cursor.getStringOptional(name: "collection_json")
        fingerprint = try cursor.getStringOptional(name: "fingerprint")
        envelopeJSON = try cursor.getStringOptional(name: "envelope_json")
    }

    func matches(
        command: ReviseSpaceChecklistsCommand,
        capturedAtMilliseconds expectedCapturedAtMilliseconds: Int64,
        collectionJSON expectedCollectionJSON: String,
        envelopeJSON expectedEnvelopeJSON: String
    ) -> Bool {
        operationId == command.envelope.operationId.rawValue
            && operation == "PUT"
            && tableName == LedgerPowerSyncTable.spaceChecklistRevisionCommands
            && accountId == command.envelope.accountId.rawValue
            && principalId == command.envelope.actorPrincipalId.rawValue
            && contractVersion == command.envelope.contractVersion.rawValue
            && capturedAtMilliseconds == expectedCapturedAtMilliseconds
            && spaceId == command.draft.spaceId.rawValue
            && expectedRevision == String(command.draft.expectedRevision.rawValue)
            && collectionJSON == expectedCollectionJSON
            && fingerprint == command.fingerprint.sha256
            && envelopeJSON == expectedEnvelopeJSON
    }
}

private struct SpaceChecklistRevisionOverlayEvidence {
    let accountId: String
    let principalId: String
    let spaceId: String
    let operationId: String
    let fingerprint: String
    let expectedRevision: String
    let projectedRevision: Int64
    let collectionJSON: String
    let acceptedAtMilliseconds: Int64

    init(cursor: any SqlCursor) throws {
        accountId = try cursor.getString(name: "account_id")
        principalId = try cursor.getString(name: "actor_principal_id")
        spaceId = try cursor.getString(name: "space_id")
        operationId = try cursor.getString(name: "operation_id")
        fingerprint = try cursor.getString(name: "fingerprint")
        expectedRevision = try cursor.getString(name: "expected_revision")
        projectedRevision = try cursor.getInt64(name: "projected_revision")
        collectionJSON = try cursor.getString(name: "collection_json")
        acceptedAtMilliseconds = try cursor.getInt64(name: "accepted_at_ms")
    }

    func matches(
        command: ReviseSpaceChecklistsCommand,
        acceptedAtMilliseconds expectedAcceptedAtMilliseconds: Int64,
        collectionJSON expectedCollectionJSON: String
    ) -> Bool {
        let revision = command.draft.expectedRevision.rawValue
        return accountId == command.envelope.accountId.rawValue
            && principalId == command.envelope.actorPrincipalId.rawValue
            && spaceId == command.draft.spaceId.rawValue
            && operationId == command.envelope.operationId.rawValue
            && fingerprint == command.fingerprint.sha256
            && expectedRevision == String(revision)
            && revision < UInt64(Int64.max)
            && projectedRevision == Int64(revision) + 1
            && collectionJSON == expectedCollectionJSON
            && acceptedAtMilliseconds == expectedAcceptedAtMilliseconds
    }
}

private struct SpaceChecklistRevisionWatchEvidence {
    let operation: SpaceChecklistRevisionOperationEvidence
    let overlay: SpaceChecklistRevisionOverlayEvidence?
    let authoritativeRevision: Int64?

    init(cursor: any SqlCursor) throws {
        operation = try SpaceChecklistRevisionOperationEvidence(cursor: cursor)
        authoritativeRevision = try cursor.getInt64Optional(name: "authoritative_revision")
        let overlayOperationId = try cursor.getStringOptional(name: "overlay_operation_id")
        if overlayOperationId == nil {
            overlay = nil
        } else {
            overlay = try SpaceChecklistRevisionOverlayEvidence(
                accountId: cursor.getString(name: "overlay_account_id"),
                principalId: cursor.getString(name: "overlay_actor_principal_id"),
                spaceId: cursor.getString(name: "overlay_space_id"),
                operationId: cursor.getString(name: "overlay_operation_id"),
                fingerprint: cursor.getString(name: "overlay_fingerprint"),
                expectedRevision: cursor.getString(name: "overlay_expected_revision"),
                projectedRevision: cursor.getInt64(name: "overlay_projected_revision"),
                collectionJSON: cursor.getString(name: "overlay_collection_json"),
                acceptedAtMilliseconds: cursor.getInt64(name: "overlay_accepted_at_ms")
            )
        }
    }

    func snapshot(
        expectedOperationId: OperationID,
        accountId: AccountID,
        principalId: PrincipalID
    ) throws -> OperationSnapshot {
        guard let envelopeJSON = operation.envelopeJSON,
              let bytes = envelopeJSON.data(using: .utf8),
              let envelope = try? OperationContractCodec.decode(
                  OperationEnvelope<ReviseSpaceChecklistsPayload>.self,
                  from: bytes
              ),
              envelope.operationId == expectedOperationId,
              envelope.accountId == accountId,
              envelope.actorPrincipalId == principalId,
              SpaceChecklistRevisionOperationIdentity.isValid(
                  expectedOperationId,
                  accountId: accountId
              ),
              let fingerprint = try? OperationFingerprint(
                  validating: operation.fingerprint
              ),
              (try? OperationFingerprint.make(for: envelope)) == fingerprint,
              let expectedRevisionText = operation.expectedRevision,
              let expectedRevision = UInt64(expectedRevisionText),
              String(expectedRevision) == expectedRevisionText,
              operation.subjectId == envelope.payload.spaceId.rawValue,
              envelope.preconditions == [
                .expectedRevision(
                    subject: LedgerEntityReference(
                        kind: .space,
                        id: try EntityID(validating: envelope.payload.spaceId.rawValue)
                    ),
                    revision: expectedRevision
                )
              ],
              let localState = LocalOperationState(rawValue: operation.localState)
        else {
            throw SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence
        }

        let command = try ReviseSpaceChecklistsCommand(
            operationId: expectedOperationId,
            draft: SpaceChecklistRevisionDraft(
                accountId: accountId,
                actorPrincipalId: principalId,
                operationContractVersion: envelope.contractVersion,
                spaceId: envelope.payload.spaceId,
                collection: envelope.payload.collection,
                expectedRevision: ExpectedSpaceRevision(expectedRevision),
                capturedAt: envelope.clientCreatedAt
            )
        )
        try operation.validate(command: command, envelopeJSON: envelopeJSON)
        if localState == .applied || localState == .rejected {
            let request = SpaceChecklistRevisionUploadRequest(
                operationId: expectedOperationId.rawValue,
                accountId: accountId.rawValue,
                actorPrincipalId: principalId.rawValue,
                contractVersion: envelope.contractVersion.rawValue,
                clientCreatedAtMilliseconds:
                    try SpaceChecklistRevisionPowerSyncStore.milliseconds(
                        envelope.clientCreatedAt
                    ),
                spaceId: envelope.payload.spaceId.rawValue,
                expectedRevision: String(expectedRevision),
                collectionJSON:
                    try SpaceChecklistRevisionPowerSyncStore.canonicalJSON(
                        envelope.payload.collection
                    ),
                fingerprint: fingerprint.sha256,
                envelopeJSON: envelopeJSON
            )
            guard operation.terminalRequestSHA256
                    == LedgerPowerSyncUploadConnector
                        .spaceChecklistRevisionRequestSHA256(request) else {
                throw SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence
            }
        }
        if let overlay {
            guard overlay.matches(
                command: command,
                acceptedAtMilliseconds: operation.acceptedAtMilliseconds,
                collectionJSON: try SpaceChecklistRevisionPowerSyncStore.canonicalJSON(
                    command.draft.collection
                )
            ) else {
                throw SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence
            }
        }
        switch localState {
        case .queued, .applying:
            guard overlay != nil else {
                throw SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence
            }
        case .applied:
            if overlay == nil {
                guard expectedRevision < UInt64(Int64.max),
                      operation.checklistReadbackRevision
                        == Int64(expectedRevision) + 1,
                      let authoritativeRevision,
                      authoritativeRevision > 0,
                      UInt64(authoritativeRevision) >= expectedRevision + 1 else {
                    throw SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence
                }
            } else if operation.checklistReadbackRevision != nil {
                throw SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence
            }
        case .rejected:
            guard overlay == nil else {
                throw SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence
            }
        case .superseded, .resolved:
            throw SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence
        }

        let acceptedAt = SpaceChecklistRevisionPowerSyncStore.date(
            operation.acceptedAtMilliseconds
        )
        let updatedAt = SpaceChecklistRevisionPowerSyncStore.date(
            operation.updatedAtMilliseconds
        )
        let subject = LedgerEntityReference(
            kind: .space,
            id: try EntityID(validating: envelope.payload.spaceId.rawValue)
        )
        let state: OperationState
        switch localState {
        case .queued:
            state = .queued(attemptCount: 0, lastTransientError: nil)
        case .applying:
            state = .applying(attempt: 1, startedAt: updatedAt)
        case .applied:
            guard let received = operation.terminalServerReceivedAtMilliseconds,
                  let completed = operation.terminalCompletedAtMilliseconds else {
                throw SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence
            }
            state = .applied(AppliedOperationResult(
                resultCode: try ApplicationResultCode(
                    validating: "space_checklists_revised"
                ),
                serverReceivedAt: SpaceChecklistRevisionPowerSyncStore.date(received),
                completedAt: SpaceChecklistRevisionPowerSyncStore.date(completed),
                affectedRevisions: [
                    EntityRevision(entity: subject, revision: expectedRevision + 1)
                ]
            ))
        case .rejected:
            guard let code = operation.terminalErrorCode,
                  let completed = operation.terminalCompletedAtMilliseconds else {
                throw SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence
            }
            let isConflict = code.contains("conflict") || code.contains("revision")
            state = .rejected(OperationRejection(
                error: ApplicationErrorSummary(
                    code: try ApplicationErrorCode(validating: code),
                    category: code == "contract_unsupported"
                        ? .unsupportedContract
                        : (isConflict ? .conflict : .validation),
                    retryDisposition: code == "contract_unsupported"
                        ? .afterClientUpdate
                        : (isConflict ? .afterUserCorrection : .never)
                ),
                rejectedAt: SpaceChecklistRevisionPowerSyncStore.date(completed),
                conflictingEntities: isConflict ? [subject] : []
            ))
        case .superseded, .resolved:
            throw SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence
        }
        return OperationSnapshot(
            operationId: expectedOperationId,
            accountId: accountId,
            contractVersion: envelope.contractVersion,
            fingerprint: fingerprint,
            acceptedAt: acceptedAt,
            updatedAt: updatedAt,
            state: state
        )
    }
}

private extension SpaceChecklistRevisionOverlayEvidence {
    init(
        accountId: String,
        principalId: String,
        spaceId: String,
        operationId: String,
        fingerprint: String,
        expectedRevision: String,
        projectedRevision: Int64,
        collectionJSON: String,
        acceptedAtMilliseconds: Int64
    ) {
        self.accountId = accountId
        self.principalId = principalId
        self.spaceId = spaceId
        self.operationId = operationId
        self.fingerprint = fingerprint
        self.expectedRevision = expectedRevision
        self.projectedRevision = projectedRevision
        self.collectionJSON = collectionJSON
        self.acceptedAtMilliseconds = acceptedAtMilliseconds
    }
}

private final class SpaceChecklistRevisionWatchHandle: @unchecked Sendable {
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

private actor SpaceChecklistRevisionWatchRegistry {
    private var handles: [UUID: SpaceChecklistRevisionWatchHandle] = [:]
    private var isClosing = false
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    func register(id: UUID, handle: SpaceChecklistRevisionWatchHandle) -> Bool {
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
