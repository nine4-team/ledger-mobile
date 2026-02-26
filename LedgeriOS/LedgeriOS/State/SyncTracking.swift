import Foundation

protocol SyncTracking {
    func trackPendingWrite()
}

struct NoOpSyncTracker: SyncTracking {
    func trackPendingWrite() {}
}
