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
        try await withOwnedSyncStreamWatch(subscribe: { try await subscribe(accountId) }, observe: {
            let reader = CurrentItemPlacementLocalReader(database: database)
            for try await rows in try reader.watch(accountId: accountId, principalId: principalId, scope: scope) {
                try Task.checkCancellation()
                let value = try DownloadedItemPlacements(accountId: accountId, scope: scope, rows: rows.compactMap { $0 })
                guard await receive(value) else { return }
            }
        })
    }
}
