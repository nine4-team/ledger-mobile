import Observation

/// One instance belongs to one workspace presentation lifetime. Locking hides
/// all child views, even if their buffered observers continue during drainage.
@MainActor
@Observable
public final class WorkspaceAccessPresentation {
    public private(set) var isLocked = false
    // Mutated only on MainActor; nonisolated deinit only cancels the Sendable
    // handle after this owner is no longer reachable.
    @ObservationIgnored nonisolated(unsafe) private var observation: Task<Void, Never>?

    public init() {}

    public func observe(_ removals: AsyncStream<Void>) {
        guard observation == nil, !isLocked else { return }
        observation = Task { [weak self] in
            for await _ in removals {
                guard !Task.isCancelled else { return }
                self?.isLocked = true
                return
            }
        }
    }

    public func stop() {
        observation?.cancel()
        observation = nil
        // Stopping or late child data must never clear a learned removal.
    }

    deinit { observation?.cancel() }
}
