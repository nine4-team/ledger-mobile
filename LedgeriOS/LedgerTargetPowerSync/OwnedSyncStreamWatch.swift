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
