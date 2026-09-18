import PowerSync

/// Shared by Item and report watches: emit local data without waiting for the
/// network, retain exactly our subscription, and await cleanup before returning.
func withOwnedSyncStreamWatch(
    subscribe: @Sendable @escaping () async throws -> any SyncStreamSubscription,
    observe: @Sendable @escaping () async throws -> Void
) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await observe() }
        group.addTask {
            let subscription = try await subscribe()
            let lifetime = AsyncStream<Void>.makeStream()
            for await _ in lifetime.stream { }
            lifetime.continuation.finish()
            try await Task.detached { try await subscription.unsubscribe() }.value
        }
        do {
            _ = try await group.next()
            group.cancelAll()
            try await group.waitForAll()
        } catch {
            group.cancelAll()
            throw error
        }
    }
}

/// Project galleries share one SDK-refcounted subscription. Follow downloaded
/// placement changes, retaining the exact Item fallback for standalone/history
/// entry or Inventory. Catalog observation remains independent and offline-first.
func withOwnedItemImageStreamWatch(
    database: any PowerSyncDatabaseProtocol, accountId: String, itemId: String,
    observe: @Sendable @escaping () async throws -> Void
) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await observe() }
        group.addTask {
            let placements = try database.watch(sql: """
                SELECT project_id FROM spike_item_placements
                WHERE account_id=? AND item_id=? AND ended_at IS NULL AND scope_kind='project'
                """, parameters: [accountId, itemId]) { try $0.getStringOptional(name: "project_id") }
            var subscription: (any SyncStreamSubscription)?
            var previousProject: String?
            var hasScope = false
            do {
                for try await rows in placements {
                    try Task.checkCancellation()
                    let project = rows.count == 1 ? rows[0] : nil
                    guard !hasScope || project != previousProject else { continue }
                    if let old = subscription {
                        try await Task.detached { try await old.unsubscribe() }.value
                    }
                    subscription = nil
                    let name = project == nil ? "item_images" : "project_item_images"
                    let params: [String: JsonValue] = ["account_id": .string(accountId),
                        project == nil ? "item_id" : "project_id": .string(project ?? itemId)]
                    subscription = try await database.syncStream(name: name, params: params).subscribe()
                    previousProject = project
                    hasScope = true
                }
                if let old = subscription {
                    try await Task.detached { try await old.unsubscribe() }.value
                }
            } catch {
                if let old = subscription {
                    try await Task.detached { try await old.unsubscribe() }.value
                }
                throw error
            }
        }
        do {
            _ = try await group.next()
            group.cancelAll()
            try await group.waitForAll()
        } catch {
            group.cancelAll()
            throw error
        }
    }
}
