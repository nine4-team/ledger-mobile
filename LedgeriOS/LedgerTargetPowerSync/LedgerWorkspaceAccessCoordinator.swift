import Foundation

/// Shared by all handles; removal blocks admission before close tasks run.
final class LedgerWorkspaceAccessFence: @unchecked Sendable {
    private let lock = NSLock()
    private var removed = false
    private var observers: [UUID: AsyncStream<Void>.Continuation] = [:]
    var isRemoved: Bool { lock.withLock { removed } }
    func markRemoved() {
        let pending = lock.withLock {
            removed = true
            let values = Array(observers.values)
            observers.removeAll()
            return values
        }
        for observer in pending {
            observer.yield(())
            observer.finish()
        }
    }

    func watchRemoval() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.observers.removeValue(forKey: id) }
            }
            let alreadyRemoved = lock.withLock {
                if removed { return true }
                observers[id] = continuation
                return false
            }
            if alreadyRemoved {
                continuation.yield(())
                continuation.finish()
            }
        }
    }
}

/// Serializes in-process bootstrap/removal for all handles of one stable
/// workspace. This is not an authentication provider or a grant of access.
actor LedgerWorkspaceAccessCoordinator {
    static let shared = LedgerWorkspaceAccessCoordinator()

    private struct Reference {
        weak var lifecycleOwner: AccountWorkspacePendingWorkRuntime?
    }
    private var fences: [String: LedgerWorkspaceAccessFence] = [:]
    private var runtimes: [String: [Reference]] = [:]

    func open(
        identity: String,
        body: @Sendable (LedgerWorkspaceAccessFence) async throws -> LedgerOfflineClientRuntime
    ) async throws -> LedgerOfflineClientRuntime {
        let fence = fence(for: identity)
        guard !fence.isRemoved else {
            throw LedgerPowerSyncLocalBootstrapFailure(stage: .workspaceAccessRemoved)
        }
        let runtime = try await body(fence)
        // The actor is reentrant while opening databases. Removal wins even
        // when that opening ignores cancellation or has already passed a check.
        if fence.isRemoved {
            try? await runtime.lockLocalAccessPreservingPendingWork()
            throw LedgerPowerSyncLocalBootstrapFailure(stage: .workspaceAccessRemoved)
        }
        if Task.isCancelled {
            try? await runtime.close()
            throw CancellationError()
        }
        runtimes[identity, default: []].removeAll { $0.lifecycleOwner == nil }
        runtimes[identity, default: []].append(Reference(lifecycleOwner: runtime.lifecycleOwner))
        return runtime
    }

    func remove(
        identity: String,
        persist: @Sendable () throws -> Void
    ) async throws {
        fence(for: identity).markRemoved()
        var persistenceFailed = false
        do { try persist() } catch { persistenceFailed = true }
        let active = runtimes[identity, default: []].compactMap(\.lifecycleOwner)
        // Do not retain closed workspaces or wait for one handle's drain before
        // asking the other handles to lock. Each lifecycle owns its own drain.
        let closeFailed = await withTaskGroup(of: Bool.self) { group in
            for runtime in active {
                group.addTask {
                    do {
                        try await runtime.lockAccessPreservingPendingWork()
                        return false
                    } catch { return true }
                }
            }
            var failed = false
            for await value in group { failed = failed || value }
            return failed
        }
        if persistenceFailed { throw LedgerOfflineClientRuntimeFailure.removalPersistenceFailed }
        if closeFailed { throw LedgerOfflineClientRuntimeFailure.removalCloseFailed }
    }

    private func fence(for identity: String) -> LedgerWorkspaceAccessFence {
        if let existing = fences[identity] { return existing }
        let created = LedgerWorkspaceAccessFence()
        fences[identity] = created
        return created
    }
}
