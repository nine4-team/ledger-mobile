import Foundation
import Network

protocol SyncTracking: Sendable {
    func trackPendingWrite()
}

struct NoOpSyncTracker: SyncTracking {
    func trackPendingWrite() {}
}

// MARK: - NetworkMonitor

/// Observes NWPathMonitor and exposes `isConnected` as an @Observable property.
/// H6: Provides real-time connectivity state for offline UI indicators.
@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isConnected: Bool = true

    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: DispatchQueue(label: "network-monitor", qos: .utility))
    }

    deinit {
        monitor.cancel()
    }
}
