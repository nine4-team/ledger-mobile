import LedgerTargetCore
import PowerSync

/// One concrete watch owns both tasks. Its caller must retain/await run through
/// cleanup, even after the public AsyncThrowingStream consumer has canceled.
struct DownloadedItemPlacementWatch: Sendable {
    let database: any PowerSyncDatabaseProtocol
    var subscribe: @Sendable (AccountID) async throws -> any SyncStreamSubscription
    var subscribeProject: @Sendable (AccountID, ProjectID) async throws -> any SyncStreamSubscription

    init(database: any PowerSyncDatabaseProtocol,
         subscribe: (@Sendable (AccountID) async throws -> any SyncStreamSubscription)? = nil,
         subscribeProject: (@Sendable (AccountID, ProjectID) async throws -> any SyncStreamSubscription)? = nil) {
        self.database = database
        self.subscribe = subscribe ?? { account in
            try await database.syncStream(name: "physical_account_items",
                params: ["account_id": .string(account.rawValue)]).subscribe()
        }
        self.subscribeProject = subscribeProject ?? { account, project in
            let identity = PropertyManagementReportStreamIdentity(accountId: account, projectId: project)
            return try await database.syncStream(name: identity.name, params: identity.parameters).subscribe()
        }
    }

    func run(accountId: AccountID, principalId: PrincipalID, scope: ItemPlacementScope,
             receive: @Sendable @escaping (DownloadedItemPlacements) async -> Bool) async throws {
        try await withOwnedSyncStreamWatch(subscribe: { try await subscribe(accountId) }, observe: {
            let reader = CurrentItemPlacementLocalReader(database: database)
            // The existing watch SQL depends on Spaces as well as Items,
            // placements, Projects and membership, even when it returns no Items.
            // Each table-change signal is reread atomically with facet choices.
            for try await _ in try reader.watch(accountId: accountId, principalId: principalId, scope: scope) {
                try Task.checkCancellation()
                let value = try await reader.readSnapshot(accountId: accountId, principalId: principalId, scope: scope)
                guard await receive(value) else { return }
            }
        })
    }

    func runHistory(accountId: AccountID, principalId: PrincipalID, itemId: ItemID,
                    receive: @Sendable @escaping (DownloadedItemPlacementHistory) async -> Bool) async throws {
        try await withOwnedSyncStreamWatch(subscribe: { try await subscribe(accountId) }, observe: {
            let reader = CurrentItemPlacementLocalReader(database: database)
            var projectId: ProjectID?
            var financialSubscription: (any SyncStreamSubscription)?
            do {
                for try await _ in try reader.watchHistory(accountId: accountId, principalId: principalId, itemId: itemId) {
                    try Task.checkCancellation()
                    let value = try await reader.readHistory(accountId: accountId, principalId: principalId, itemId: itemId)
                    guard await receive(value) else { break }
                    let scope = value.intervals.first(where: { $0.endedAt == nil })?.scope
                    let nextProject: ProjectID?
                    if case .project(let id) = scope { nextProject = id } else { nextProject = nil }
                    if projectId != nextProject {
                        if let old = financialSubscription {
                            financialSubscription = nil
                            try await Task.detached { try await old.unsubscribe() }.value
                        }
                        projectId = nextProject
                        if let projectId {
                            financialSubscription = try await subscribeProject(accountId, projectId)
                        }
                    }
                }
            } catch {
                if let subscription = financialSubscription {
                    try await Task.detached { try await subscription.unsubscribe() }.value
                }
                throw error
            }
            if let subscription = financialSubscription {
                try await Task.detached { try await subscription.unsubscribe() }.value
            }
        })
    }
}
