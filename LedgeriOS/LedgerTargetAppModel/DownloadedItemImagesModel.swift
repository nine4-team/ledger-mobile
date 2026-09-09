import Foundation
import LedgerTargetCore
import Observation

@MainActor @Observable
public final class DownloadedItemImagesModel {
    public enum ExportFailure: Error, Equatable, Sendable {
        case alreadyExporting, unavailable, missingBytes
    }
    public enum State: Equatable, Sendable {
        case idle, loading, unavailable
        case downloaded(DownloadedItemImageCatalog)
    }
    public private(set) var state: State = .idle
    public private(set) var isExporting = false
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

    public func exportImage(accountId: AccountID, itemId: ItemID, image: DownloadedItemImage,
                            reader: any DownloadedItemImageReading,
                            prepareDestination: () async throws -> Void,
                            handoff: (Data) async throws -> Void) async throws {
        guard !isExporting else { throw ExportFailure.alreadyExporting }
        let request = generation
        try validateExport(accountId: accountId,itemId: itemId,image: image,generation: request)
        isExporting = true
        defer { isExporting = false }
        try await prepareDestination()
        try validateExport(accountId: accountId,itemId: itemId,image: image,generation: request)
        let bytes = try await reader.loadDownloadedItemImage(accountId: accountId,itemId: itemId,
            image: image,allowDownload: true)
        try validateExport(accountId: accountId,itemId: itemId,image: image,generation: request)
        guard let bytes, !bytes.isEmpty else { throw ExportFailure.missingBytes }
        // The native destination owns the copy from this point. Its handoff
        // continuation must await actual completion, including after cancellation.
        try await handoff(bytes)
    }

    private func validateExport(accountId: AccountID,itemId: ItemID,image: DownloadedItemImage,
                                generation request: UUID) throws {
        try Task.checkCancellation()
        guard generation == request, case .downloaded(let catalog) = state,
              catalog.accountId.rawValue.utf8.elementsEqual(accountId.rawValue.utf8),
              catalog.itemId.rawValue.utf8.elementsEqual(itemId.rawValue.utf8),
              catalog.images.contains(image) else { throw ExportFailure.unavailable }
    }
}
