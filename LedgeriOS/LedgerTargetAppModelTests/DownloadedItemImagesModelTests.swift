import Foundation
import LedgerTargetCore
import LedgerTargetAppModel
import Testing

@Suite("Downloaded Item image presentation") @MainActor
struct DownloadedItemImagesModelTests {
    @Test("Empty complete and incomplete catalogs remain distinct", arguments: [false, true])
    func emptyMetadata(complete: Bool) async throws {
        let value = try catalog(complete: complete, hasImage: false)
        let feed = Feed()
        let model = DownloadedItemImagesModel()
        let task = Task { await model.load(accountId: value.accountId, itemId: value.itemId, reader: feed) }
        feed.continuation.yield(value)
        await expectState(model, .downloaded(value))
        task.cancel(); feed.continuation.finish(); await task.value
        #expect(model.state == .idle)
    }

    @Test("Foreign Account or Item clears earlier visible metadata", arguments: [false, true])
    func foreignScope(account: Bool) async throws {
        let valid = try catalog()
        let foreign = try catalog(account: account ? "foreign" : "account", item: account ? "item" : "other")
        let feed = Feed()
        let model = DownloadedItemImagesModel()
        let task = Task { await model.load(accountId: valid.accountId, itemId: valid.itemId, reader: feed) }
        feed.continuation.yield(valid)
        await expectState(model, .downloaded(valid))
        feed.continuation.yield(foreign)
        feed.continuation.finish()
        await task.value
        #expect(model.state == .unavailable)
    }

    @Test("Source failure or normal stream end clears previously shown metadata", arguments: [false, true])
    func stopped(failure: Bool) async throws {
        let value = try catalog()
        let feed = Feed()
        let model = DownloadedItemImagesModel()
        let task = Task { await model.load(accountId: value.accountId, itemId: value.itemId, reader: feed) }
        feed.continuation.yield(value)
        await expectState(model, .downloaded(value))
        if failure { feed.continuation.finish(throwing: DownloadedItemImageFailure.unavailable) }
        else { feed.continuation.finish() }
        await task.value
        #expect(model.state == .unavailable)
    }

    @Test("Clear and replacement generation refuse late old-stream values", arguments: [false, true])
    func staleGeneration(replace: Bool) async throws {
        let oldValue = try catalog()
        let newValue = try catalog(item: "new", complete: false)
        let oldFeed = Feed(), newFeed = Feed()
        let model = DownloadedItemImagesModel()
        let oldTask = Task { await model.load(accountId: oldValue.accountId, itemId: oldValue.itemId, reader: oldFeed) }
        oldFeed.continuation.yield(oldValue)
        await expectState(model, .downloaded(oldValue))
        var newTask: Task<Void, Never>?
        if replace {
            newTask = Task { await model.load(accountId: newValue.accountId, itemId: newValue.itemId, reader: newFeed) }
            newFeed.continuation.yield(newValue)
            await expectState(model, .downloaded(newValue))
        } else { model.clear() }
        oldFeed.continuation.yield(oldValue)
        oldFeed.continuation.finish()
        await oldTask.value
        #expect(model.state == (replace ? .downloaded(newValue) : .idle))
        newTask?.cancel(); newFeed.continuation.finish(); await newTask?.value
    }

    private func catalog(account: String = "account", item: String = "item", complete: Bool = true,
                         hasImage: Bool = true) throws -> DownloadedItemImageCatalog {
        let accountId = try AccountID(validating: account), itemId = try ItemID(validating: item)
        let hash = String(repeating: "a", count: 64)
        let object = try DownloadedImageObjectReference(accountId: accountId, attachmentId: "image",
            sha256: hash, byteCount: "3", mediaType: "image/png",
            storagePath: "accounts/\(account)/attachments/image/\(hash)")
        let image = try DownloadedItemImage(referenceId: .init(validating: "ref"), itemId: itemId,
            object: object, position: 0, isPrimary: true, setRevision: 1)
        return try .init(accountId: accountId, itemId: itemId, isComplete: complete, images: hasImage ? [image] : [])
    }

    private func expectState(_ model: DownloadedItemImagesModel, _ state: DownloadedItemImagesModel.State) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while model.state != state && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(model.state == state)
    }
}

private struct Feed: DownloadedItemImageReading {
    let stream: AsyncThrowingStream<DownloadedItemImageCatalog, Error>
    let continuation: AsyncThrowingStream<DownloadedItemImageCatalog, Error>.Continuation
    init() { (stream, continuation) = AsyncThrowingStream.makeStream() }
    func watchDownloadedItemImages(accountId: AccountID, itemId: ItemID) -> AsyncThrowingStream<DownloadedItemImageCatalog, Error> { stream }
    func loadDownloadedItemImage(accountId: AccountID, itemId: ItemID, image: DownloadedItemImage, allowDownload: Bool) async throws -> Data? {
        throw DownloadedItemImageFailure.unavailable
    }
}
