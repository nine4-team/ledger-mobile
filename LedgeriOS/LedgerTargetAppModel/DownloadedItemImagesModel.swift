import Foundation
import LedgerTargetCore
import Observation

@MainActor @Observable
public final class DownloadedItemImagesModel {
    public enum State: Equatable, Sendable {
        case idle, loading, unavailable
        case downloaded(DownloadedItemImageCatalog)
    }
    public private(set) var state: State = .idle
    private var generation = UUID()
    public init() {}

    public func load(accountId: AccountID, itemId: ItemID, reader: any DownloadedItemImageReading) async {
        let request = UUID()
        generation = request; state = .loading
        do {
            for try await catalog in reader.watchDownloadedItemImages(accountId: accountId, itemId: itemId) {
                try Task.checkCancellation()
                guard generation == request else { return }
                guard catalog.accountId.rawValue.utf8.elementsEqual(accountId.rawValue.utf8),
                      catalog.itemId.rawValue.utf8.elementsEqual(itemId.rawValue.utf8) else {
                    state = .unavailable; return
                }
                state = .downloaded(catalog)
            }
        } catch { }
        guard generation == request else { return }
        state = Task.isCancelled ? .idle : .unavailable
    }

    public func clear() { generation = UUID(); state = .idle }
}
