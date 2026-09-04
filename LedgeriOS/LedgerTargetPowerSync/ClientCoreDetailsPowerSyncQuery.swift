import Foundation
import LedgerTargetCore
import PowerSync

public final class ClientCoreDetailsPowerSyncQuery: ClientCoreDetailsQuerying, @unchecked Sendable {
    private let database: any PowerSyncDatabaseProtocol
    private let now: @Sendable () -> Date

    public init(
        database: any PowerSyncDatabaseProtocol,
        now: @Sendable @escaping () -> Date = Date.init
    ) {
        self.database = database
        self.now = now
    }

    public func watchClientCoreDetails(
        _ request: ClientCoreDetailsRequest
    ) -> AsyncThrowingStream<ClientCoreDetailsUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(try ClientCoreDetailsUpdate(
                        request: request,
                        state: .waiting(.loading)
                    ))
                    let rows = try database.watch(
                        sql: """
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
                        WHERE authoritative.account_id = ? AND authoritative.id = ?
                        UNION ALL
                        SELECT pending.id, pending.account_id,
                               pending.display_name, pending.lifecycle,
                               pending.revision, pending.created_at_ms,
                               pending.updated_at_ms,
                               pending.operation_id AS pending_operation_id,
                               NULL AS reconciliation_operation_id
                        FROM \(LedgerPowerSyncTable.pendingClients) AS pending
                        WHERE pending.account_id = ? AND pending.id = ?
                          AND NOT EXISTS (
                            SELECT 1
                            FROM \(LedgerPowerSyncTable.clients) AS authoritative
                            WHERE authoritative.account_id = pending.account_id
                              AND authoritative.id = pending.id
                          )
                        """,
                        parameters: [
                            request.accountId.rawValue,
                            request.clientId.rawValue,
                            request.accountId.rawValue,
                            request.clientId.rawValue
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
                            hasSynced: status.hasSynced == true,
                            hasLastSyncedAt: status.lastSyncedAt != nil
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
                            try await database.execute(
                                sql: """
                                DELETE FROM \(LedgerPowerSyncTable.pendingClients)
                                WHERE id = ? AND account_id = ? AND operation_id = ?
                                """,
                                parameters: [row.id, row.accountId, operationId]
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
}

private struct PowerSyncClientRow: Sendable {
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
