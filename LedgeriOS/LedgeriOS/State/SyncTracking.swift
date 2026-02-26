import Foundation

protocol SyncTracking: Sendable {
    func trackPendingWrite()
}

struct NoOpSyncTracker: SyncTracking {
    func trackPendingWrite() {}
}
