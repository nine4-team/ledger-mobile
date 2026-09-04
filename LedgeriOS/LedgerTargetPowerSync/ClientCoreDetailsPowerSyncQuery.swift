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
                        SELECT id, account_id, display_name, lifecycle, revision,
                               created_at_ms, updated_at_ms, pending_operation_id
                        FROM \(LedgerPowerSyncTable.clients)
                        WHERE account_id = ? AND id = ?
                        """,
                        parameters: [request.accountId.rawValue, request.clientId.rawValue]
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

    init(cursor: any SqlCursor) throws {
        id = try cursor.getString(name: "id")
        accountId = try cursor.getString(name: "account_id")
        displayName = try cursor.getString(name: "display_name")
        lifecycle = try cursor.getString(name: "lifecycle")
        revision = try cursor.getInt64(name: "revision")
        createdAtMilliseconds = try cursor.getInt64(name: "created_at_ms")
        updatedAtMilliseconds = try cursor.getInt64(name: "updated_at_ms")
        pendingOperationId = try cursor.getStringOptional(name: "pending_operation_id")
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
