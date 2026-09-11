import Foundation
import LedgerTargetCore
import PowerSync

final class ClientCoreDetailsPowerSyncQuery: ClientCoreDetailsQuerying, @unchecked Sendable {
    private let database: any PowerSyncDatabaseProtocol
    private let principalId: PrincipalID
    private let boundAccountId: AccountID
    private let now: @Sendable () -> Date
    private let watchRegistry = ClientCoreDetailsWatchRegistry()

    init(
        database: any PowerSyncDatabaseProtocol,
        principalId: PrincipalID,
        accountId: AccountID,
        now: @Sendable @escaping () -> Date = Date.init
    ) {
        self.database = database
        self.principalId = principalId
        boundAccountId = accountId
        self.now = now
    }

    public func watchClientCoreDetails(
        _ request: ClientCoreDetailsRequest
    ) -> AsyncThrowingStream<ClientCoreDetailsUpdate, Error> {
        guard request.accountId == boundAccountId else {
            return Self.failedStream(ClientCoreDetailsFailure.accountScopeMismatch)
        }

        return AsyncThrowingStream { continuation in
            let id = UUID()
            let handle = ClientCoreDetailsWatchTaskHandle()
            let registration = Task { await watchRegistry.register(id: id, handle: handle) }
            let task = Task {
                let admitted = await registration.value
                guard admitted, !Task.isCancelled else {
                    continuation.finish()
                    if admitted { await watchRegistry.finished(id: id) }
                    return
                }
                do {
                    if case .terminated = continuation.yield(try ClientCoreDetailsUpdate(
                        request: request,
                        state: .waiting(.loading)
                    )) {
                        continuation.finish()
                        await watchRegistry.finished(id: id)
                        return
                    }
                    try Task.checkCancellation()
                    let rows = try database.watch(
                        sql: """
                        WITH scope AS (
                          SELECT EXISTS (
                            SELECT 1
                            FROM \(LedgerPowerSyncTable.memberships)
                            WHERE account_id = ? AND principal_id = ? AND state = 'active'
                          ) AS is_active
                        ), selected_clients AS (
                          SELECT authoritative.id, authoritative.account_id,
                                 authoritative.display_name, authoritative.lifecycle,
                                 authoritative.revision, authoritative.created_at_ms,
                                 authoritative.updated_at_ms,
                                 NULL AS pending_operation_id,
                                 pending.operation_id AS reconciliation_operation_id
                          FROM \(LedgerPowerSyncTable.clients) AS authoritative
                          LEFT JOIN \(LedgerPowerSyncTable.pendingClients) AS pending
                            ON pending.account_id = authoritative.account_id
                           AND pending.id = authoritative.id
                           AND pending.created_by_principal_id = ?
                          WHERE authoritative.account_id = ? AND authoritative.id = ?
                            AND (SELECT is_active FROM scope)
                          UNION ALL
                          SELECT pending.id, pending.account_id,
                                 pending.display_name, pending.lifecycle,
                                 pending.revision, pending.created_at_ms,
                                 pending.updated_at_ms,
                                 pending.operation_id AS pending_operation_id,
                                 NULL AS reconciliation_operation_id
                          FROM \(LedgerPowerSyncTable.pendingClients) AS pending
                          WHERE pending.account_id = ? AND pending.id = ?
                            AND pending.created_by_principal_id = ?
                            AND (
                              NOT (SELECT is_active FROM scope)
                              OR NOT EXISTS (
                                SELECT 1
                                FROM \(LedgerPowerSyncTable.clients) AS authoritative
                                WHERE authoritative.account_id = pending.account_id
                                  AND authoritative.id = pending.id
                              )
                            )
                        )
                        SELECT scope.is_active, client.id, client.account_id,
                               client.display_name,
                               CASE WHEN archive.operation_id IS NOT NULL
                                          AND client.revision <= archive.projected_revision
                                    THEN archive.lifecycle ELSE client.lifecycle END AS lifecycle,
                               CASE WHEN archive.operation_id IS NOT NULL
                                          AND client.revision <= archive.projected_revision
                                    THEN archive.projected_revision ELSE client.revision END AS revision,
                               client.created_at_ms,
                               CASE WHEN archive.operation_id IS NOT NULL
                                    THEN max(client.updated_at_ms, archive.accepted_at_ms)
                                    ELSE client.updated_at_ms END AS updated_at_ms,
                               client.pending_operation_id,
                               client.reconciliation_operation_id,
                               client.lifecycle AS base_lifecycle,
                               client.revision AS base_revision,
                               archive.operation_id AS archive_operation_id,
                               archive.account_id AS archive_account_id,
                               archive.actor_principal_id AS archive_actor_principal_id,
                               archive.client_id AS archive_client_id,
                               archive.fingerprint AS archive_fingerprint,
                               archive.expected_revision AS archive_expected_revision,
                               archive.projected_revision AS archive_projected_revision,
                               archive.lifecycle AS archive_lifecycle,
                               archive.accepted_at_ms AS archive_accepted_at_ms,
                               operation.account_id AS archive_operation_account_id,
                               operation.actor_principal_id AS archive_operation_actor_principal_id,
                               operation.contract_version AS archive_operation_contract_version,
                               operation.fingerprint AS archive_operation_fingerprint,
                               operation.subject_id AS archive_operation_subject_id,
                               operation.local_state AS archive_operation_state,
                               operation.command_type AS archive_operation_command_type,
                               operation.command_expected_revision AS archive_operation_expected_revision,
                               operation.command_envelope_json AS archive_operation_envelope_json,
                               (SELECT count(*) FROM \(LedgerPowerSyncTable.clientArchiveOverlays) AS counted
                                 WHERE counted.account_id = client.account_id
                                   AND counted.client_id = client.id) AS archive_overlay_count,
                               (SELECT count(*) FROM \(LedgerPowerSyncTable.localOperations) AS pending_archive
                                 WHERE pending_archive.account_id = client.account_id
                                   AND pending_archive.subject_id = client.id
                                   AND pending_archive.command_type = 'archive_client'
                                   AND pending_archive.contract_version = 'client-archive-v1'
                                   AND pending_archive.local_state IN ('queued', 'applying', 'applied')
                                   AND NOT EXISTS (
                                     SELECT 1 FROM \(LedgerPowerSyncTable.clientArchiveOverlays) AS retained
                                     WHERE retained.operation_id = pending_archive.id
                                   )
                                   AND (
                                     pending_archive.local_state IN ('queued', 'applying')
                                     OR (
                                       pending_archive.local_state = 'applied'
                                       AND NOT (
                                         pending_archive.command_expected_revision IS NOT NULL
                                         AND CAST(CAST(pending_archive.command_expected_revision AS INTEGER) AS TEXT)
                                           = pending_archive.command_expected_revision
                                         AND CAST(pending_archive.command_expected_revision AS INTEGER) > 0
                                         AND (
                                           client.revision > CAST(pending_archive.command_expected_revision AS INTEGER) + 1
                                           OR (
                                             client.revision = CAST(pending_archive.command_expected_revision AS INTEGER) + 1
                                             AND client.lifecycle = 'archived'
                                           )
                                         )
                                       )
                                     )
                                   )) AS missing_archive_overlay_count
                        FROM selected_clients AS client
                        CROSS JOIN scope
                        LEFT JOIN \(LedgerPowerSyncTable.clientArchiveOverlays) AS archive
                          ON archive.account_id = client.account_id
                         AND archive.client_id = client.id
                        LEFT JOIN \(LedgerPowerSyncTable.localOperations) AS operation
                          ON operation.id = archive.operation_id
                        """,
                        parameters: [
                            request.accountId.rawValue,
                            principalId.rawValue,
                            principalId.rawValue,
                            request.accountId.rawValue,
                            request.clientId.rawValue,
                            request.accountId.rawValue,
                            request.clientId.rawValue,
                            principalId.rawValue
                        ]
                    ) { cursor in
                        try PowerSyncClientRow(cursor: cursor)
                    }

                    for try await localRows in rows {
                        let snapshots = try localRows.map {
                            try $0.snapshot(expectedPrincipalId: principalId.rawValue)
                        }
                        let status = database.currentStatus
                        let quality: ListSnapshotQuality
                        quality = Self.snapshotQuality(
                            hasPendingOperation: localRows.contains {
                                $0.pendingOperationId != nil || $0.archiveOperationId != nil
                            },
                            hasSynced: localRows.first?.scopeIsActive == true
                                && status.hasSynced == true,
                            hasLastSyncedAt: localRows.first?.scopeIsActive == true
                                && status.lastSyncedAt != nil
                        )
                        let versionSuffix = localRows.map(\.updatedAtMilliseconds).max() ?? 0
                        let local = try ClientCoreDetailsLocalSnapshot(
                            request: request,
                            rows: snapshots,
                            visibleRowCountBeforeFiltering: snapshots.count,
                            isCompleteForQuery: quality == .ready,
                            quality: quality,
                            localDataVersion: LocalDataVersion(
                                validating: "powersync-spike-\(versionSuffix)"
                            ),
                            asOf: now()
                        )
                        for row in localRows {
                            guard let operationId = row.reconciliationOperationId else {
                                continue
                            }
                            try await PowerSyncOverlayReconciler.reconcileClient(
                                database: database,
                                clientId: row.id,
                                accountId: row.accountId,
                                operationId: operationId
                            )
                        }
                        for row in localRows {
                            guard let operationId = row.archiveOperationId else { continue }
                            try await PowerSyncOverlayReconciler.reconcileClientArchive(
                                database: database,
                                clientId: row.id,
                                accountId: row.accountId,
                                operationId: operationId
                            )
                        }
                        if case .terminated = continuation.yield(try ClientCoreDetailsUpdate(
                            request: request,
                            state: .snapshot(local)
                        )) { break }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    do {
                        _ = continuation.yield(try ClientCoreDetailsUpdate(
                            request: request,
                            state: .failed(failure: .retryable, cached: nil)
                        ))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                await watchRegistry.finished(id: id)
            }
            handle.install(task)
            continuation.onTermination = { _ in handle.cancel() }
        }
    }

    func cancelAndDrainWatches() async {
        await watchRegistry.cancelAndDrain()
    }

    static func snapshotQuality(
        hasPendingOperation: Bool,
        hasSynced: Bool,
        hasLastSyncedAt: Bool
    ) -> ListSnapshotQuality {
        if hasPendingOperation { return .partial }
        if hasSynced { return .ready }
        if hasLastSyncedAt { return .stale }
        return .partial
    }

    private static func failedStream<Value: Sendable>(
        _ error: Error
    ) -> AsyncThrowingStream<Value, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }
}

private final class ClientCoreDetailsWatchTaskHandle: @unchecked Sendable {
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
        let installed = lock.withLock {
            cancellationRequested = true
            return task
        }
        installed?.cancel()
    }
}

private actor ClientCoreDetailsWatchRegistry {
    private var handles: [UUID: ClientCoreDetailsWatchTaskHandle] = [:]
    private var isClosing = false
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    func register(id: UUID, handle: ClientCoreDetailsWatchTaskHandle) -> Bool {
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

private struct PowerSyncClientRow: Sendable {
    let scopeIsActive: Bool
    let id: String
    let accountId: String
    let displayName: String
    let lifecycle: String
    let revision: Int64
    let createdAtMilliseconds: Int64
    let updatedAtMilliseconds: Int64
    let pendingOperationId: String?
    let reconciliationOperationId: String?
    let baseLifecycle: String?
    let baseRevision: Int64?
    let archiveOperationId: String?
    let archiveAccountId: String?
    let archiveActorPrincipalId: String?
    let archiveClientId: String?
    let archiveFingerprint: String?
    let archiveExpectedRevision: String?
    let archiveProjectedRevision: Int64?
    let archiveLifecycle: String?
    let archiveAcceptedAtMilliseconds: Int64?
    let archiveOperationAccountId: String?
    let archiveOperationActorPrincipalId: String?
    let archiveOperationContractVersion: String?
    let archiveOperationFingerprint: String?
    let archiveOperationSubjectId: String?
    let archiveOperationState: String?
    let archiveOperationCommandType: String?
    let archiveOperationExpectedRevision: String?
    let archiveOperationEnvelopeJSON: String?
    let archiveOverlayCount: Int64
    let missingArchiveOverlayCount: Int64

    init(cursor: any SqlCursor) throws {
        scopeIsActive = try cursor.getInt64(name: "is_active") == 1
        id = try cursor.getString(name: "id")
        accountId = try cursor.getString(name: "account_id")
        displayName = try cursor.getString(name: "display_name")
        lifecycle = try cursor.getString(name: "lifecycle")
        revision = try cursor.getInt64(name: "revision")
        createdAtMilliseconds = try cursor.getInt64(name: "created_at_ms")
        updatedAtMilliseconds = try cursor.getInt64(name: "updated_at_ms")
        pendingOperationId = try cursor.getStringOptional(name: "pending_operation_id")
        reconciliationOperationId = try cursor.getStringOptional(
            name: "reconciliation_operation_id"
        )
        baseLifecycle = try cursor.getStringOptional(name: "base_lifecycle")
        baseRevision = try cursor.getInt64Optional(name: "base_revision")
        archiveOperationId = try cursor.getStringOptional(name: "archive_operation_id")
        archiveAccountId = try cursor.getStringOptional(name: "archive_account_id")
        archiveActorPrincipalId = try cursor.getStringOptional(name: "archive_actor_principal_id")
        archiveClientId = try cursor.getStringOptional(name: "archive_client_id")
        archiveFingerprint = try cursor.getStringOptional(name: "archive_fingerprint")
        archiveExpectedRevision = try cursor.getStringOptional(name: "archive_expected_revision")
        archiveProjectedRevision = try cursor.getInt64Optional(name: "archive_projected_revision")
        archiveLifecycle = try cursor.getStringOptional(name: "archive_lifecycle")
        archiveAcceptedAtMilliseconds = try cursor.getInt64Optional(name: "archive_accepted_at_ms")
        archiveOperationAccountId = try cursor.getStringOptional(name: "archive_operation_account_id")
        archiveOperationActorPrincipalId = try cursor.getStringOptional(name: "archive_operation_actor_principal_id")
        archiveOperationContractVersion = try cursor.getStringOptional(name: "archive_operation_contract_version")
        archiveOperationFingerprint = try cursor.getStringOptional(name: "archive_operation_fingerprint")
        archiveOperationSubjectId = try cursor.getStringOptional(name: "archive_operation_subject_id")
        archiveOperationState = try cursor.getStringOptional(name: "archive_operation_state")
        archiveOperationCommandType = try cursor.getStringOptional(name: "archive_operation_command_type")
        archiveOperationExpectedRevision = try cursor.getStringOptional(name: "archive_operation_expected_revision")
        archiveOperationEnvelopeJSON = try cursor.getStringOptional(name: "archive_operation_envelope_json")
        archiveOverlayCount = try cursor.getInt64(name: "archive_overlay_count")
        missingArchiveOverlayCount = try cursor.getInt64(name: "missing_archive_overlay_count")
    }

    func snapshot(expectedPrincipalId: String) throws -> ClientCoreDetailsSnapshot {
        guard revision > 0, let lifecycle = DirectoryLifecycleState(rawValue: lifecycle) else {
            throw ClientCoreDetailsFailure.invalidEncodedClient
        }
        try validateArchiveOverlay(expectedPrincipalId: expectedPrincipalId)
        let summary = try ClientSummary(
            id: ClientID(validating: id),
            accountId: AccountID(validating: accountId),
            displayName: ClientDisplayName(validating: displayName),
            lifecycle: lifecycle,
            createdAt: Date(timeIntervalSince1970: Double(createdAtMilliseconds) / 1_000),
            updatedAt: Date(timeIntervalSince1970: Double(updatedAtMilliseconds) / 1_000)
        )
        return ClientCoreDetailsSnapshot(
            client: summary,
            locallyObservedRevision: ExpectedClientRevision(UInt64(revision))
        )
    }

    private func validateArchiveOverlay(expectedPrincipalId: String) throws {
        guard missingArchiveOverlayCount == 0 else {
            throw ClientCoreDetailsFailure.invalidEncodedClient
        }
        guard let operationId = archiveOperationId else {
            guard archiveOverlayCount == 0 else {
                throw ClientCoreDetailsFailure.invalidEncodedClient
            }
            return
        }
        guard archiveOverlayCount == 1, archiveAccountId == accountId,
              archiveActorPrincipalId == expectedPrincipalId,
              let actor = archiveActorPrincipalId, archiveClientId == id,
              archiveLifecycle == "archived", let fingerprint = archiveFingerprint,
              let expectedText = archiveExpectedRevision,
              let expected = UInt64(expectedText), String(expected) == expectedText,
              expected > 0, expected < UInt64(Int64.max),
              archiveProjectedRevision == Int64(expected) + 1,
              let acceptedAt = archiveAcceptedAtMilliseconds, acceptedAt >= 0,
              archiveOperationAccountId == accountId,
              archiveOperationActorPrincipalId == actor,
              archiveOperationContractVersion == "client-archive-v1",
              archiveOperationFingerprint == fingerprint,
              archiveOperationSubjectId == id,
              ["queued", "applying", "applied"].contains(archiveOperationState),
              archiveOperationCommandType == "archive_client",
              archiveOperationExpectedRevision == expectedText,
              let envelopeJSON = archiveOperationEnvelopeJSON,
              baseLifecycle != nil, baseRevision != nil,
              ClientArchiveOverlayCommandValidator.isValid(
                  operationId: operationId, accountId: accountId,
                  actorPrincipalId: actor, contractVersion: "client-archive-v1",
                  clientId: id, expectedRevision: expected,
                  fingerprint: fingerprint, envelopeJSON: envelopeJSON
              ) else {
            throw ClientCoreDetailsFailure.invalidEncodedClient
        }
    }
}
