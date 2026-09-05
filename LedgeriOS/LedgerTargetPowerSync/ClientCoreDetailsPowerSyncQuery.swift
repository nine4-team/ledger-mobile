import Foundation
import LedgerTargetCore
import PowerSync

final class ClientCoreDetailsPowerSyncQuery: ClientCoreDetailsQuerying, @unchecked Sendable {
    private let database: any PowerSyncDatabaseProtocol
    private let principalId: PrincipalID
    private let boundAccountId: AccountID
    private let now: @Sendable () -> Date

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
            let task = Task {
                do {
                    continuation.yield(try ClientCoreDetailsUpdate(
                        request: request,
                        state: .waiting(.loading)
                    ))
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
                        SELECT scope.is_active, selected_clients.*
                        FROM selected_clients
                        CROSS JOIN scope
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
                        let snapshots = try localRows.map { try $0.snapshot() }
                        let status = database.currentStatus
                        let quality: ListSnapshotQuality
                        quality = Self.snapshotQuality(
                            hasPendingOperation: localRows.contains {
                                $0.pendingOperationId != nil
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
                        continuation.yield(try ClientCoreDetailsUpdate(
                            request: request,
                            state: .snapshot(local)
                        ))
                    }
                    continuation.finish()
                } catch {
                    do {
                        continuation.yield(try ClientCoreDetailsUpdate(
                            request: request,
                            state: .failed(failure: .retryable, cached: nil)
                        ))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
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
    }

    func snapshot() throws -> ClientCoreDetailsSnapshot {
        guard revision > 0, let lifecycle = DirectoryLifecycleState(rawValue: lifecycle) else {
            throw ClientCoreDetailsFailure.invalidEncodedClient
        }
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
}
