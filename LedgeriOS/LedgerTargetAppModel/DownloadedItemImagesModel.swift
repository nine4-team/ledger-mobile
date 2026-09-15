import Foundation
import LedgerTargetCore
import Observation

/// Shared ordering for Item and Transaction media export. Destination completion
/// owns the bytes after handoff; cancellation must not release them prematurely.
public enum AuthorizedMediaExport {
    public enum Failure: Error, Equatable, Sendable {
        case alreadyExporting, unavailable, missingBytes
    }
    @MainActor public static func perform(validate: () throws -> Void,
        prepareDestination: () async throws -> Void, load: () async throws -> Data?,
        handoff: (Data) async throws -> Void) async throws {
        try Task.checkCancellation()
        try validate()
        try await prepareDestination()
        try Task.checkCancellation()
        try validate()
        let bytes = try await load()
        try Task.checkCancellation()
        try validate()
        guard let bytes, !bytes.isEmpty else { throw Failure.missingBytes }
        try await handoff(bytes)
    }
}

@MainActor @Observable
public final class DownloadedItemImagesModel {
    public typealias ExportFailure = AuthorizedMediaExport.Failure
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
        try await AuthorizedMediaExport.perform(validate: {
            try validateExport(accountId: accountId,itemId: itemId,image: image,generation: request)
        }, prepareDestination: prepareDestination, load: {
            try await reader.loadDownloadedItemImage(accountId: accountId,itemId: itemId,
                image: image,allowDownload: true)
        }, handoff: handoff)
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
