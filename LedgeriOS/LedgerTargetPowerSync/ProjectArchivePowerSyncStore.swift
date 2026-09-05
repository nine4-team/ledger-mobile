import Foundation
import LedgerTargetCore
import PowerSync

enum ProjectArchivePowerSyncFailure: Error, Equatable, Sendable {
    case invalidAcceptanceTime
    case invalidOperationIdentity
    case malformedLocalEvidence
    case operationNotFound
}

public enum ProjectArchiveOperationIdentity {
    public static func make(accountId: AccountID, uuid: UUID) throws -> OperationID {
        try AccountBoundOperationIdentity.make(
            family: .projectArchive,
            accountId: accountId,
            uuid: uuid
        )
    }

    static func isValid(_ operationId: OperationID, accountId: AccountID) -> Bool {
        AccountBoundOperationIdentity.isValid(
            operationId,
            family: .projectArchive,
            accountId: accountId
        )
    }
}

actor ProjectArchivePowerSyncStore: ProjectArchiving {
    private let database: any PowerSyncDatabaseProtocol
    private let accountId: AccountID
    private let principalId: PrincipalID
    private let now: @Sendable () -> Date

    init(
        database: any PowerSyncDatabaseProtocol,
        accountId: AccountID,
        principalId: PrincipalID,
        now: @Sendable @escaping () -> Date = Date.init
    ) {
        self.database = database
        self.accountId = accountId
        self.principalId = principalId
        self.now = now
    }

    func archive(_ command: ArchiveProjectCommand) async throws -> OperationReceipt {
        guard command.envelope.accountId == accountId else {
            throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
        }
        guard command.envelope.actorPrincipalId == principalId else {
            throw LedgerOfflineClientRuntimeFailure.principalScopeMismatch
        }
        guard ProjectArchiveOperationIdentity.isValid(
            command.envelope.operationId,
            accountId: command.envelope.accountId
        ) else {
            throw ProjectArchivePowerSyncFailure.invalidOperationIdentity
        }

        let envelopeData = try OperationContractCodec.encode(command.envelope)
        guard let envelopeJSON = String(data: envelopeData, encoding: .utf8) else {
            throw ProjectArchiveFailure.invalidEncodedCommand
        }
        let acceptedAtMilliseconds = try Self.milliseconds(now())
        let clientCreatedAtMilliseconds = try Self.milliseconds(
            command.envelope.clientCreatedAt
        )
        guard command.envelope.clientCreatedAt == Date(
            timeIntervalSince1970: Double(clientCreatedAtMilliseconds) / 1_000
        ) else {
            throw ProjectArchiveFailure.invalidEncodedCommand
        }

        do {
            let receipt = try await database.writeTransaction { transaction in
                let existing = try transaction.getOptional(
                    sql: """
                    SELECT account_id, actor_principal_id, contract_version,
                           fingerprint, subject_id, local_state, command_type,
                           command_expected_revision, command_envelope_json,
                           terminal_phase, terminal_result_code,
                           terminal_error_code, terminal_envelope_sha256,
                           terminal_request_sha256,
                           terminal_server_received_at_ms,
                           terminal_completed_at_ms
                    FROM \(LedgerPowerSyncTable.localOperations)
                    WHERE id = ?
                    """,
                    parameters: [command.envelope.operationId.rawValue]
                ) { try ProjectArchiveReplayRow(cursor: $0) }
                if let existing {
                    guard existing.fingerprint == command.fingerprint.sha256 else {
                        throw OperationContractFailure.payloadMismatch(
                            command.envelope.operationId
                        )
                    }
                    guard existing.accountId == command.envelope.accountId.rawValue,
                          existing.actorPrincipalId
                            == command.envelope.actorPrincipalId.rawValue,
                          existing.contractVersion
                            == command.envelope.contractVersion.rawValue,
                          existing.subjectId == command.draft.projectId.rawValue,
                          existing.commandType == "archive_project",
                          existing.expectedRevision
                            == String(command.draft.expectedRevision.rawValue),
                          existing.envelopeJSON == envelopeJSON,
                          let state = LocalOperationState(rawValue: existing.localState) else {
                        throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
                    }
                    try existing.validateTerminal(state: state, command: command)
                    let overlays = try transaction.getAll(
                        sql: """
                        SELECT account_id, actor_principal_id, project_id,
                               operation_id, fingerprint, expected_revision,
                               projected_revision, lifecycle
                        FROM \(LedgerPowerSyncTable.projectArchiveOverlays)
                        WHERE operation_id = ?
                        """,
                        parameters: [command.envelope.operationId.rawValue]
                    ) { try ProjectArchiveReplayOverlay(cursor: $0) }
                    guard overlays.count <= 1 else {
                        throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
                    }
                    if let overlay = overlays.first {
                        guard overlay.matches(command) else {
                            throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
                        }
                    }
                    if state == .queued || state == .applying {
                        guard overlays.count == 1 else {
                            throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
                        }
                    } else if state == .rejected {
                        guard overlays.isEmpty else {
                            throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
                        }
                    }
                    return OperationReceipt(
                        operationId: command.envelope.operationId,
                        localState: state
                    )
                }

                let revision = command.draft.expectedRevision.rawValue
                guard revision > 0, revision < UInt64(Int64.max) else {
                    throw ProjectArchiveFailure.revisionPreconditionMismatch
                }

                let rows = try transaction.getAll(
                    sql: """
                    SELECT lifecycle, revision
                    FROM (
                      SELECT authoritative.lifecycle, authoritative.revision, 0 AS source_order
                      FROM \(LedgerPowerSyncTable.projects) AS authoritative
                      WHERE authoritative.account_id = ? AND authoritative.id = ?
                      UNION ALL
                      SELECT pending.lifecycle, pending.revision, 1 AS source_order
                      FROM \(LedgerPowerSyncTable.pendingProjects) AS pending
                      WHERE pending.account_id = ? AND pending.id = ?
                        AND pending.created_by_principal_id = ?
                        AND NOT EXISTS (
                          SELECT 1 FROM \(LedgerPowerSyncTable.projects) AS authoritative
                          WHERE authoritative.account_id = pending.account_id
                            AND authoritative.id = pending.id
                        )
                    )
                    ORDER BY source_order
                    """,
                    parameters: [
                        command.envelope.accountId.rawValue,
                        command.draft.projectId.rawValue,
                        command.envelope.accountId.rawValue,
                        command.draft.projectId.rawValue,
                        command.envelope.actorPrincipalId.rawValue
                    ]
                ) { cursor in
                    (
                        try cursor.getString(name: "lifecycle"),
                        try cursor.getInt64(name: "revision")
                    )
                }
                guard rows.count == 1 else {
                    throw ProjectArchiveFailure.subjectMismatch
                }
                guard rows[0].0 == "active" else {
                    throw ProjectArchiveFailure.localAcceptanceFailed
                }
                guard rows[0].1 > 0, UInt64(rows[0].1) == revision else {
                    throw ProjectArchiveFailure.revisionPreconditionMismatch
                }

                let overlayCount = try transaction.get(
                    sql: """
                    SELECT count(*)
                    FROM \(LedgerPowerSyncTable.projectArchiveOverlays)
                    WHERE account_id = ? AND project_id = ?
                    """,
                    parameters: [
                        command.envelope.accountId.rawValue,
                        command.draft.projectId.rawValue
                    ]
                ) { cursor in try cursor.getInt64(index: 0) }
                guard overlayCount == 0 else {
                    throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
                }

                let projectedRevision = Int64(revision) + 1
                _ = try transaction.execute(
                    sql: """
                    INSERT INTO \(LedgerPowerSyncTable.localOperations) (
                      id, account_id, actor_principal_id, contract_version,
                      fingerprint, subject_id, local_state, accepted_at_ms,
                      updated_at_ms, command_type, command_expected_revision,
                      command_envelope_json
                    ) VALUES (?, ?, ?, ?, ?, ?, 'queued', ?, ?, 'archive_project', ?, ?)
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
                        String(revision),
                        envelopeJSON
                    ]
                )
                _ = try transaction.execute(
                    sql: """
                    INSERT INTO \(LedgerPowerSyncTable.projectArchiveOverlays) (
                      id, account_id, actor_principal_id, project_id, operation_id,
                      fingerprint, expected_revision, projected_revision,
                      lifecycle, accepted_at_ms
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'archived', ?)
                    """,
                    parameters: [
                        command.envelope.operationId.rawValue,
                        command.envelope.accountId.rawValue,
                        command.envelope.actorPrincipalId.rawValue,
                        command.draft.projectId.rawValue,
                        command.envelope.operationId.rawValue,
                        command.fingerprint.sha256,
                        String(revision),
                        projectedRevision,
                        acceptedAtMilliseconds
                    ]
                )
                _ = try transaction.execute(
                    sql: """
                    INSERT INTO \(LedgerPowerSyncTable.projectArchiveCommands) (
                      id, account_id, actor_principal_id, contract_version,
                      client_created_at_ms, project_id, expected_revision,
                      fingerprint, envelope_json
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    parameters: [
                        command.envelope.operationId.rawValue,
                        command.envelope.accountId.rawValue,
                        command.envelope.actorPrincipalId.rawValue,
                        command.envelope.contractVersion.rawValue,
                        clientCreatedAtMilliseconds,
                        command.draft.projectId.rawValue,
                        String(revision),
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
        } catch let failure as LedgerOfflineClientRuntimeFailure {
            throw failure
        } catch let failure as OperationContractFailure {
            throw failure
        } catch let failure as ProjectArchiveFailure {
            throw failure
        } catch let failure as ProjectArchivePowerSyncFailure {
            throw failure
        } catch {
            throw ProjectArchiveFailure.localAcceptanceFailed
        }
    }

    nonisolated func watchOperation(
        _ operationId: OperationID
    ) -> AsyncThrowingStream<OperationSnapshot, Error> {
        guard ProjectArchiveOperationIdentity.isValid(operationId, accountId: accountId) else {
            return Self.failedStream(ProjectArchivePowerSyncFailure.invalidOperationIdentity)
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let updates = try database.watch(
                        sql: Self.operationSQL,
                        parameters: [operationId.rawValue]
                    ) { cursor in
                        try ProjectArchiveOperationRow(cursor: cursor)
                    }
                    for try await rows in updates {
                        try Task.checkCancellation()
                        guard rows.count <= 1 else {
                            throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
                        }
                        guard let row = rows.first else {
                            throw ProjectArchivePowerSyncFailure.operationNotFound
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
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private nonisolated static func failedStream<Value: Sendable>(
        _ error: Error
    ) -> AsyncThrowingStream<Value, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }

    private static func milliseconds(_ date: Date) throws -> Int64 {
        let value = date.timeIntervalSince1970 * 1_000
        guard value.isFinite,
              let milliseconds = Int64(exactly: value.rounded(.towardZero)),
              milliseconds >= 0 else {
            throw ProjectArchivePowerSyncFailure.invalidAcceptanceTime
        }
        return milliseconds
    }

    private static let operationSQL = """
        SELECT operation.id, operation.account_id, operation.actor_principal_id,
               operation.contract_version, operation.fingerprint,
               operation.subject_id, operation.local_state,
               operation.accepted_at_ms, operation.updated_at_ms,
               operation.command_type, operation.command_expected_revision,
               operation.command_envelope_json, operation.terminal_phase,
               operation.terminal_result_code, operation.terminal_error_code,
               operation.terminal_envelope_sha256,
               operation.terminal_request_sha256,
               operation.terminal_server_received_at_ms,
               operation.terminal_completed_at_ms,
               overlay.operation_id AS overlay_operation_id,
               overlay.account_id AS overlay_account_id,
               overlay.actor_principal_id AS overlay_actor_principal_id,
               overlay.project_id AS overlay_project_id,
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
               result.phase AS result_phase,
               result.result_code, result.error_code,
               result.client_created_at_ms AS result_client_created_at_ms,
               result.server_received_at_ms, result.completed_at_ms
        FROM \(LedgerPowerSyncTable.localOperations) AS operation
        LEFT JOIN \(LedgerPowerSyncTable.projectArchiveOverlays) AS overlay
          ON overlay.operation_id = operation.id
        LEFT JOIN \(LedgerPowerSyncTable.operationResults) AS result
          ON result.id = operation.id
        WHERE operation.id = ?
        """
}

private struct ProjectArchiveReplayRow {
    let accountId: String
    let actorPrincipalId: String
    let contractVersion: String
    let fingerprint: String
    let subjectId: String
    let localState: String
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

    init(cursor: any SqlCursor) throws {
        accountId = try cursor.getString(name: "account_id")
        actorPrincipalId = try cursor.getString(name: "actor_principal_id")
        contractVersion = try cursor.getString(name: "contract_version")
        fingerprint = try cursor.getString(name: "fingerprint")
        subjectId = try cursor.getString(name: "subject_id")
        localState = try cursor.getString(name: "local_state")
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
    }

    func validateTerminal(
        state: LocalOperationState,
        command: ArchiveProjectCommand
    ) throws {
        let fields: [Any?] = [
            terminalPhase, terminalResultCode, terminalErrorCode,
            terminalEnvelopeSHA256, terminalRequestSHA256,
            terminalServerReceivedAtMilliseconds, terminalCompletedAtMilliseconds
        ]
        if state == .queued || state == .applying {
            guard !fields.contains(where: { $0 != nil }) else {
                throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
            }
            return
        }
        guard let terminalPhase,
              let terminalEnvelopeSHA256,
              terminalEnvelopeSHA256 == command.fingerprint.sha256,
              let terminalRequestSHA256,
              let terminalServerReceivedAtMilliseconds,
              let terminalCompletedAtMilliseconds,
              terminalServerReceivedAtMilliseconds >= 0,
              terminalCompletedAtMilliseconds >= terminalServerReceivedAtMilliseconds,
              let envelopeJSON,
              let clientCreatedAtMilliseconds = Int64(exactly:
                (command.envelope.clientCreatedAt.timeIntervalSince1970 * 1_000)
                    .rounded(.towardZero)
              ) else {
            throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
        }
        let request = ProjectArchiveUploadRequest(
            operationId: command.envelope.operationId.rawValue,
            accountId: command.envelope.accountId.rawValue,
            actorPrincipalId: command.envelope.actorPrincipalId.rawValue,
            contractVersion: command.envelope.contractVersion.rawValue,
            clientCreatedAtMilliseconds: clientCreatedAtMilliseconds,
            projectId: command.draft.projectId.rawValue,
            expectedRevision: String(command.draft.expectedRevision.rawValue),
            fingerprint: command.fingerprint.sha256,
            envelopeJSON: envelopeJSON
        )
        guard terminalRequestSHA256
                == LedgerPowerSyncUploadConnector.archiveRequestSHA256(request) else {
            throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
        }
        switch state {
        case .applied, .superseded:
            guard terminalPhase == "applied",
                  terminalResultCode == "project_archived",
                  terminalErrorCode == nil else {
                throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
            }
        case .rejected, .resolved:
            guard terminalPhase == "rejected", terminalResultCode == nil,
                  terminalErrorCode.map(SupabaseProjectArchiveRPC.isKnownRejectionCode)
                    == true else {
                throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
            }
        case .queued, .applying:
            break
        }
    }
}

private struct ProjectArchiveReplayOverlay {
    let accountId: String
    let actorPrincipalId: String
    let projectId: String
    let operationId: String
    let fingerprint: String
    let expectedRevision: String
    let projectedRevision: Int64
    let lifecycle: String

    init(cursor: any SqlCursor) throws {
        accountId = try cursor.getString(name: "account_id")
        actorPrincipalId = try cursor.getString(name: "actor_principal_id")
        projectId = try cursor.getString(name: "project_id")
        operationId = try cursor.getString(name: "operation_id")
        fingerprint = try cursor.getString(name: "fingerprint")
        expectedRevision = try cursor.getString(name: "expected_revision")
        projectedRevision = try cursor.getInt64(name: "projected_revision")
        lifecycle = try cursor.getString(name: "lifecycle")
    }

    func matches(_ command: ArchiveProjectCommand) -> Bool {
        let expected = command.draft.expectedRevision.rawValue
        return accountId == command.envelope.accountId.rawValue
            && actorPrincipalId == command.envelope.actorPrincipalId.rawValue
            && projectId == command.draft.projectId.rawValue
            && operationId == command.envelope.operationId.rawValue
            && fingerprint == command.fingerprint.sha256
            && expectedRevision == String(expected)
            && expected < UInt64(Int64.max)
            && projectedRevision == Int64(expected) + 1
            && lifecycle == "archived"
    }
}

private struct ProjectArchiveOperationRow: Sendable {
    let operationId: String
    let accountId: String
    let principalId: String
    let contractVersion: String
    let fingerprint: String
    let subjectId: String
    let localState: String
    let acceptedAtMilliseconds: Int64
    let updatedAtMilliseconds: Int64
    let projectId: String
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
    let overlayOperationId: String?
    let overlayAccountId: String?
    let overlayActorPrincipalId: String?
    let overlayProjectId: String?
    let overlayFingerprint: String?
    let overlayExpectedRevision: String?
    let overlayProjectedRevision: Int64?
    let overlayLifecycle: String?
    let overlayAcceptedAtMilliseconds: Int64?
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
    let errorCode: String?
    let resultClientCreatedAtMilliseconds: Int64?
    let serverReceivedAtMilliseconds: Int64?
    let completedAtMilliseconds: Int64?

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
        projectId = subjectId
        commandType = try cursor.getStringOptional(name: "command_type")
        expectedRevision = try cursor.getStringOptional(name: "command_expected_revision")
        envelopeJSON = try cursor.getStringOptional(name: "command_envelope_json")
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
        overlayOperationId = try cursor.getStringOptional(name: "overlay_operation_id")
        overlayAccountId = try cursor.getStringOptional(name: "overlay_account_id")
        overlayActorPrincipalId = try cursor.getStringOptional(
            name: "overlay_actor_principal_id"
        )
        overlayProjectId = try cursor.getStringOptional(name: "overlay_project_id")
        overlayFingerprint = try cursor.getStringOptional(name: "overlay_fingerprint")
        overlayExpectedRevision = try cursor.getStringOptional(
            name: "overlay_expected_revision"
        )
        overlayProjectedRevision = try cursor.getInt64Optional(
            name: "overlay_projected_revision"
        )
        overlayLifecycle = try cursor.getStringOptional(name: "overlay_lifecycle")
        overlayAcceptedAtMilliseconds = try cursor.getInt64Optional(
            name: "overlay_accepted_at_ms"
        )
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
        errorCode = try cursor.getStringOptional(name: "error_code")
        resultClientCreatedAtMilliseconds = try cursor.getInt64Optional(
            name: "result_client_created_at_ms"
        )
        serverReceivedAtMilliseconds = try cursor.getInt64Optional(
            name: "server_received_at_ms"
        )
        completedAtMilliseconds = try cursor.getInt64Optional(name: "completed_at_ms")
    }

    func snapshot(
        expectedOperationId: OperationID,
        accountId expectedAccountId: AccountID,
        principalId expectedPrincipalId: PrincipalID
    ) throws -> OperationSnapshot {
        guard operationId == expectedOperationId.rawValue,
              accountId == expectedAccountId.rawValue,
              principalId == expectedPrincipalId.rawValue,
              ProjectArchiveOperationIdentity.isValid(
                expectedOperationId,
                accountId: expectedAccountId
              ),
              subjectId == projectId,
              acceptedAtMilliseconds >= 0,
              updatedAtMilliseconds >= acceptedAtMilliseconds,
              commandType == "archive_project",
              let expectedRevision,
              let envelopeJSON,
              let rawEnvelope = envelopeJSON.data(using: .utf8),
              let envelope = try? OperationContractCodec.decode(
                OperationEnvelope<ArchiveProjectPayload>.self,
                from: rawEnvelope
              ),
              envelope.operationId.rawValue == operationId,
              envelope.accountId.rawValue == accountId,
              envelope.actorPrincipalId.rawValue == principalId,
              envelope.contractVersion.rawValue == contractVersion,
              envelope.payload.projectId.rawValue == projectId,
              let typedFingerprint = try? OperationFingerprint(validating: fingerprint),
              (try? OperationFingerprint.make(for: envelope)) == typedFingerprint,
              let state = LocalOperationState(rawValue: localState) else {
            throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
        }

        let acceptedAt = Self.date(acceptedAtMilliseconds)
        let updatedAt = Self.date(updatedAtMilliseconds)
        let parsedExpectedRevision: UInt64?
        guard let parsed = UInt64(expectedRevision),
              String(parsed) == expectedRevision,
              parsed > 0,
              parsed < UInt64(Int64.max),
              envelope.preconditions == [
                .expectedRevision(
                    subject: LedgerEntityReference(
                        kind: .project,
                        id: try EntityID(validating: projectId)
                    ),
                    revision: parsed
                )
              ] else {
            throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
        }
        parsedExpectedRevision = parsed
        try validateOverlay(state: state, expectedRevision: expectedRevision)
        let request = ProjectArchiveUploadRequest(
                operationId: operationId,
                accountId: accountId,
                actorPrincipalId: principalId,
                contractVersion: contractVersion,
                clientCreatedAtMilliseconds: try Self.milliseconds(envelope.clientCreatedAt),
                projectId: projectId,
                expectedRevision: expectedRevision,
                fingerprint: fingerprint,
                envelopeJSON: envelopeJSON
        )
        let requestSHA256 = LedgerPowerSyncUploadConnector.archiveRequestSHA256(request)
        return OperationSnapshot(
            operationId: expectedOperationId,
            accountId: expectedAccountId,
            contractVersion: try OperationContractVersion(validating: contractVersion),
            fingerprint: typedFingerprint,
            acceptedAt: acceptedAt,
            updatedAt: updatedAt,
            state: try operationState(
                localState: state,
                expectedRevision: parsedExpectedRevision,
                updatedAt: updatedAt,
                expectedRequestSHA256: requestSHA256,
                expectedClientCreatedAtMilliseconds: request.clientCreatedAtMilliseconds
            )
        )
    }

    private func validateOverlay(
        state: LocalOperationState,
        expectedRevision: String
    ) throws {
        if let overlayOperationId {
            guard overlayOperationId == operationId,
                  overlayAccountId == accountId,
                  overlayActorPrincipalId == principalId,
                  overlayProjectId == projectId,
                  overlayFingerprint == fingerprint,
                  overlayExpectedRevision == expectedRevision,
                  let expected = Int64(expectedRevision),
                  overlayProjectedRevision == expected + 1,
                  overlayLifecycle == "archived",
                  overlayAcceptedAtMilliseconds == acceptedAtMilliseconds else {
                throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
            }
        }
        switch state {
        case .queued, .applying:
            guard overlayOperationId != nil else {
                throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
            }
        case .rejected:
            guard overlayOperationId == nil else {
                throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
            }
        case .applied, .superseded, .resolved:
            break
        }
    }

    private func operationState(
        localState: LocalOperationState,
        expectedRevision: UInt64?,
        updatedAt: Date,
        expectedRequestSHA256: String,
        expectedClientCreatedAtMilliseconds: Int64
    ) throws -> OperationState {
        let subject = LedgerEntityReference(
            kind: .project,
            id: try EntityID(validating: projectId)
        )
        let terminal = try terminalEvidence(
            expectedRequestSHA256: expectedRequestSHA256,
            expectedClientCreatedAtMilliseconds: expectedClientCreatedAtMilliseconds
        )
        let effectivePhase: String
        switch localState {
        case .queued, .applying:
            effectivePhase = terminal?.phase ?? localState.rawValue
        case .applied, .superseded:
            guard terminal?.phase == "applied" else {
                throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
            }
            effectivePhase = localState.rawValue
        case .rejected, .resolved:
            guard terminal?.phase == "rejected" else {
                throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
            }
            effectivePhase = localState.rawValue
        }
        switch effectivePhase {
        case "queued":
            return .queued(attemptCount: 0, lastTransientError: nil)
        case "applying":
            return .applying(attempt: 1, startedAt: updatedAt)
        case "applied":
            guard let terminal, let resultCode = terminal.resultCode else {
                throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
            }
            return .applied(AppliedOperationResult(
                resultCode: try ApplicationResultCode(validating: resultCode),
                serverReceivedAt: terminal.serverReceivedAt,
                completedAt: terminal.completedAt,
                affectedRevisions: expectedRevision.map {
                    [EntityRevision(entity: subject, revision: $0 + 1)]
                } ?? []
            ))
        case "rejected":
            guard let terminal, let code = terminal.errorCode else {
                throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
            }
            return .rejected(OperationRejection(
                error: ApplicationErrorSummary(
                    code: try ApplicationErrorCode(validating: code),
                    category: Self.errorCategory(code),
                    retryDisposition: Self.retryDisposition(code)
                ),
                rejectedAt: terminal.completedAt,
                conflictingEntities: Self.isConflict(code) ? [subject] : []
            ))
        case "superseded":
            guard let terminal, let resultCode = terminal.resultCode else {
                throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
            }
            let result = AppliedOperationResult(
                resultCode: try ApplicationResultCode(validating: resultCode),
                serverReceivedAt: terminal.serverReceivedAt,
                completedAt: terminal.completedAt,
                affectedRevisions: expectedRevision.map {
                    [EntityRevision(entity: subject, revision: $0 + 1)]
                } ?? []
            )
            return .superseded(
                original: result,
                correction: CorrectionReference(
                    operationId: try OperationID(validating: operationId),
                    correctedAt: updatedAt
                )
            )
        case "resolved":
            guard let terminal, let code = terminal.errorCode else {
                throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
            }
            let rejection = OperationRejection(
                error: ApplicationErrorSummary(
                    code: try ApplicationErrorCode(validating: code),
                    category: Self.errorCategory(code),
                    retryDisposition: Self.retryDisposition(code)
                ),
                rejectedAt: terminal.completedAt,
                conflictingEntities: Self.isConflict(code) ? [subject] : []
            )
            return .resolved(
                rejection: rejection,
                resolution: RejectionResolution(
                    code: try ResolutionCode(validating: "retry_replaced"),
                    resolvedAt: updatedAt
                )
            )
        default:
            throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
        }
    }

    private func terminalEvidence(
        expectedRequestSHA256: String,
        expectedClientCreatedAtMilliseconds: Int64
    ) throws -> TerminalEvidence? {
        let localFields: [Any?] = [
            terminalPhase, terminalResultCode, terminalErrorCode,
            terminalEnvelopeSHA256, terminalRequestSHA256,
            terminalServerReceivedAtMilliseconds,
            terminalCompletedAtMilliseconds
        ]
        let localTerminal: TerminalEvidence?
        if localFields.contains(where: { $0 != nil }) {
            guard let terminalPhase,
                  let terminalEnvelopeSHA256,
                  terminalEnvelopeSHA256 == fingerprint,
                  terminalRequestSHA256 == expectedRequestSHA256,
                  let terminalServerReceivedAtMilliseconds,
                  let terminalCompletedAtMilliseconds else {
                throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
            }
            localTerminal = try validatedTerminal(
                phase: terminalPhase,
                resultCode: terminalResultCode,
                errorCode: terminalErrorCode,
                serverReceivedAtMilliseconds: terminalServerReceivedAtMilliseconds,
                completedAtMilliseconds: terminalCompletedAtMilliseconds
            )
        } else {
            localTerminal = nil
        }

        let resultFields: [Any?] = [
            resultAccountId, resultPrincipalId, resultCommandType,
            resultContractVersion, resultFingerprint, resultEnvelopeSHA256,
            resultRequestSHA256, resultSubjectId, resultPhase, resultCode, errorCode,
            resultClientCreatedAtMilliseconds, serverReceivedAtMilliseconds,
            completedAtMilliseconds
        ]
        guard resultFields.contains(where: { $0 != nil }) else { return localTerminal }
        guard resultAccountId == accountId,
              resultPrincipalId == principalId,
              resultCommandType == "archive_project",
              resultContractVersion == contractVersion,
              resultFingerprint == fingerprint,
              resultEnvelopeSHA256 == fingerprint,
              resultRequestSHA256 == expectedRequestSHA256,
              resultSubjectId == projectId,
              resultClientCreatedAtMilliseconds == expectedClientCreatedAtMilliseconds,
              let resultPhase,
              let serverReceivedAtMilliseconds,
              let completedAtMilliseconds else {
            throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
        }
        let downloaded = try validatedTerminal(
            phase: resultPhase,
            resultCode: resultCode,
            errorCode: errorCode,
            serverReceivedAtMilliseconds: serverReceivedAtMilliseconds,
            completedAtMilliseconds: completedAtMilliseconds
        )
        if let localTerminal, localTerminal != downloaded {
            throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
        }
        return downloaded
    }

    private func validatedTerminal(
        phase: String,
        resultCode: String?,
        errorCode: String?,
        serverReceivedAtMilliseconds: Int64,
        completedAtMilliseconds: Int64
    ) throws -> TerminalEvidence {
        guard serverReceivedAtMilliseconds >= 0,
              completedAtMilliseconds >= serverReceivedAtMilliseconds else {
            throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
        }
        switch phase {
        case "applied":
            guard resultCode == "project_archived", errorCode == nil else {
                throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
            }
        case "rejected":
            guard resultCode == nil, let errorCode,
                  SupabaseProjectArchiveRPC.isKnownRejectionCode(errorCode) else {
                throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
            }
        default:
            throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
        }
        return TerminalEvidence(
            phase: phase,
            resultCode: resultCode,
            errorCode: errorCode,
            serverReceivedAt: Self.date(serverReceivedAtMilliseconds),
            completedAt: Self.date(completedAtMilliseconds)
        )
    }

    private static func date(_ milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }

    private static func milliseconds(_ date: Date) throws -> Int64 {
        let value = date.timeIntervalSince1970 * 1_000
        guard value.isFinite,
              let milliseconds = Int64(exactly: value.rounded(.towardZero)),
              milliseconds >= 0 else {
            throw ProjectArchivePowerSyncFailure.malformedLocalEvidence
        }
        return milliseconds
    }

    private static func isConflict(_ code: String) -> Bool {
        code.contains("revision") || code.contains("lifecycle") || code.contains("conflict")
    }

    private static func errorCategory(_ code: String) -> ApplicationErrorCategory {
        if isConflict(code) { return .conflict }
        if code == "contract_unsupported" { return .unsupportedContract }
        if code.contains("auth") { return .authorization }
        return .validation
    }

    private static func retryDisposition(_ code: String) -> RetryDisposition {
        if code == "contract_unsupported" { return .afterClientUpdate }
        return isConflict(code) ? .afterUserCorrection : .never
    }
}

private struct TerminalEvidence: Equatable {
    let phase: String
    let resultCode: String?
    let errorCode: String?
    let serverReceivedAt: Date
    let completedAt: Date
}
