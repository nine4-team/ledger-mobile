import LedgerTargetCore
import PowerSync

/// One concrete watch owns both tasks. Its caller must retain/await run through
/// cleanup, even after the public AsyncThrowingStream consumer has canceled.
struct DownloadedItemPlacementWatch: Sendable {
    let database: any PowerSyncDatabaseProtocol
    var subscribe: @Sendable (AccountID) async throws -> any SyncStreamSubscription

    init(database: any PowerSyncDatabaseProtocol,
         subscribe: (@Sendable (AccountID) async throws -> any SyncStreamSubscription)? = nil) {
        self.database = database
        self.subscribe = subscribe ?? { account in
            try await database.syncStream(name: "physical_account_items",
                params: ["account_id": .string(account.rawValue)]).subscribe()
        }
    }

    func run(accountId: AccountID, principalId: PrincipalID, scope: ItemPlacementScope,
             receive: @Sendable @escaping (DownloadedItemPlacements) async -> Bool) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let reader = CurrentItemPlacementLocalReader(database: database)
                for try await rows in try reader.watch(accountId: accountId, principalId: principalId, scope: scope) {
                    try Task.checkCancellation()
                    let value = try DownloadedItemPlacements(accountId: accountId, scope: scope, rows: rows.compactMap { $0 })
                    guard await receive(value) else { return }
                }
            }
            group.addTask {
                // Subscription is a local SDK operation. Never wait for first
                // network sync before emitting already downloaded rows.
                let subscription = try await subscribe(accountId)
                let lifetime = AsyncStream<Void>.makeStream()
                // Cancellation of iteration ends this suspension. Keep the
                // handle alive until cleanup; never use unsubscribeAll().
                for await _ in lifetime.stream { }
                lifetime.continuation.finish()
                // Await uncancelled cleanup before this child (and runtime
                // stream lease) ends. SDK 1.16.1 releases its reference on deinit.
                try await Task.detached { try await subscription.unsubscribe() }.value
            }
            do {
                _ = try await group.next()
                group.cancelAll()
                try await group.waitForAll()
            } catch {
                group.cancelAll()
                // Structured task scope waits for subscription cleanup even
                // when a query, cancellation or subscription has failed.
                throw error
            }
        }
    }
}
