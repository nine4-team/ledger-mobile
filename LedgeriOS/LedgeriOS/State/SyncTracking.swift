import Foundation
import Network

// MARK: - NetworkMonitor

/// Observes NWPathMonitor and exposes `isConnected` as an @Observable property.
/// H6: Provides real-time connectivity state for offline UI indicators.
///
/// Debouncing: Going offline has a 5-second grace period to prevent banner flicker
/// on brief signal drops (elevator, cell handoff). Going online is instant.
@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isConnected: Bool = true

    private let monitor = NWPathMonitor()
    private var offlineGraceTask: Task<Void, Never>?

    /// Fires when connectivity is restored. Used to trigger upload queue processing.
    var onConnectivityRestored: (() -> Void)?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let nowConnected = path.status == .satisfied

                if nowConnected {
                    self.offlineGraceTask?.cancel()
                    self.offlineGraceTask = nil
                    let wasOffline = !self.isConnected
                    self.isConnected = true
                    if wasOffline { self.onConnectivityRestored?() }
                } else if self.offlineGraceTask == nil {
                    self.offlineGraceTask = Task {
                        try? await Task.sleep(for: .seconds(5))
                        guard !Task.isCancelled else { return }
                        self.isConnected = false
                    }
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "network-monitor", qos: .utility))
    }

    deinit {
        monitor.cancel()
    }
}
