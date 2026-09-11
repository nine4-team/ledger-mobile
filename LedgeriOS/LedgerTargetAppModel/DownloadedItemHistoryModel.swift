import Foundation
import LedgerTargetCore
import Observation

public enum DownloadedItemHistoryState: Equatable, Sendable {
    case idle, loading, unavailable
    case downloaded(DownloadedItemPlacementHistory)
}

/// A local physical-history view, not financial history or a completeness claim.
@MainActor @Observable
public final class DownloadedItemHistoryModel {
    public private(set) var state: DownloadedItemHistoryState = .idle
    private var generation = UUID()
    public init() {}

    public func load(accountId: AccountID, itemId: ItemID,
                     reader: any DownloadedItemPlacementHistoryReading) async {
        let request = UUID()
        generation = request
        state = .loading
        do {
            for try await snapshot in reader.watchDownloadedItemPlacementHistory(accountId: accountId, itemId: itemId) {
                try Task.checkCancellation()
                guard generation == request else { return }
                guard snapshot.accountId.rawValue.utf8.elementsEqual(accountId.rawValue.utf8),
                      snapshot.itemId.rawValue.utf8.elementsEqual(itemId.rawValue.utf8) else {
                    state = .unavailable
                    return
                }
                state = .downloaded(snapshot)
            }
            guard generation == request else { return }
            // A completed watch can no longer deliver access removal or Item
            // deletion. Offline is supported by a live local database watch,
            // not by keeping a snapshot after that watch has ended.
            state = Task.isCancelled ? .idle : .unavailable
        } catch {
            guard generation == request else { return }
            state = Task.isCancelled ? .idle : .unavailable
        }
    }

    public func clear() {
        generation = UUID()
        state = .idle
    }
}
