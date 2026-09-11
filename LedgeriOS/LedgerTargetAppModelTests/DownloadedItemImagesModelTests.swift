import Foundation
import LedgerTargetCore
import LedgerTargetAppModel
import Testing

@Suite("Downloaded Item image presentation") @MainActor
struct DownloadedItemImagesModelTests {
    @Test("Export loads only the exact selected image after destination preparation")
    func exportSelectedImage() async throws {
        try await withGallery { model,feed,value,probe in
            let first = try #require(value.images.first)
            let otherObject = try DownloadedImageObjectReference(accountId: value.accountId,attachmentId: "second",
                sha256: first.object.contentSHA256.rawValue,byteCount: "3",mediaType: "image/png",
                storagePath: "accounts/account/attachments/second/\(first.object.contentSHA256.rawValue)")
            let selected = try DownloadedItemImage(referenceId: .init(validating: "second-ref"),itemId: value.itemId,
                object: otherObject,position: 1,isPrimary: false,setRevision: 1)
            let updated = try DownloadedItemImageCatalog(accountId: value.accountId,itemId: value.itemId,
                isComplete: true,images: [first,selected])
            feed.continuation.yield(updated);await expectState(model,.downloaded(updated))
            try await model.exportImage(accountId: value.accountId,itemId: value.itemId,image: selected,reader: feed,
                prepareDestination: { #expect(probe.reads == 0);probe.prepared = true },
                handoff: { probe.delivered = $0 })
            #expect(probe.loadedImage == selected && probe.allowedDownload == true)
            #expect(probe.loadedAccount == value.accountId && probe.loadedItem == value.itemId)
            #expect(probe.delivered == Data([1,2,3]))
            #expect(!model.isExporting)
        }
    }

    @Test("Invalid scope, removed reference and stale reference fail before permission",arguments: ["account","item","reference","cleared"])
    func exportInitialAuthorization(change: String) async throws {
        try await withGallery { model,feed,value,probe in
            let original = try #require(value.images.first)
            let selected = change == "reference" ? try DownloadedItemImage(referenceId: original.referenceId,
                itemId: original.itemId,object: original.object,position: original.position,isPrimary: original.isPrimary,setRevision: 2) : original
            if change == "cleared" { model.clear() }
            await #expect(throws: DownloadedItemImagesModel.ExportFailure.unavailable) {
                try await model.exportImage(accountId: change == "account" ? AccountID(validating: "foreign") : value.accountId,
                    itemId: change == "item" ? ItemID(validating: "foreign") : value.itemId,image: selected,reader: feed,
                    prepareDestination: { probe.prepared = true },handoff: { probe.delivered = $0 })
            }
            #expect(!probe.prepared && probe.reads == 0 && probe.delivered == nil && !model.isExporting)
        }
    }

    @Test("Permission denial does not read bytes or deliver a copy")
    func exportPermissionDenied() async throws {
        try await withGallery { model,feed,value,probe in
            await #expect(throws: ExportTestFailure.denied) {
                try await model.exportImage(accountId: value.accountId,itemId: value.itemId,image: value.images[0],reader: feed,
                    prepareDestination: { throw ExportTestFailure.denied },handoff: { probe.delivered = $0 })
            }
            #expect(probe.reads == 0 && probe.delivered == nil && !model.isExporting)
        }
    }

    @Test("Clear, replacement generation and reference removal invalidate pending exports",
          arguments: ["permission","download"],["clear","reload","remove"])
    func exportScopeChanges(phase: String,change: String) async throws {
        try await withGallery { model,feed,value,probe in
            let gate = ExportGate()
            if phase == "download" { probe.gate = gate }
            let operation = Task {
                try await model.exportImage(accountId: value.accountId,itemId: value.itemId,image: value.images[0],reader: feed,
                    prepareDestination: { probe.prepared = true;if phase == "permission" { await gate.wait() } },
                    handoff: { probe.delivered = $0 })
            }
            await gate.expectEntered()
            var replacement: Task<Void,Never>?
            var replacementFeed: Feed?
            if change == "clear" { model.clear() }
            else if change == "remove" {
                let removed = try catalog(hasImage: false)
                feed.continuation.yield(removed);await expectState(model,.downloaded(removed))
            } else {
                let newFeed = Feed(load: probe.read)
                replacementFeed = newFeed
                replacement = Task { await model.load(accountId: value.accountId,itemId: value.itemId,reader: newFeed) }
                await expectState(model,.loading)
                newFeed.continuation.yield(value);await expectState(model,.downloaded(value))
            }
            gate.release()
            await #expect(throws: DownloadedItemImagesModel.ExportFailure.unavailable) { try await operation.value }
            #expect(probe.reads == (phase == "permission" ? 0 : 1))
            #expect(probe.delivered == nil && !model.isExporting)
            replacement?.cancel();replacementFeed?.continuation.finish();await replacement?.value
        }
    }

    @Test("Missing or empty bytes never reach the destination",arguments: [false,true])
    func exportMissingBytes(empty: Bool) async throws {
        try await withGallery { model,feed,value,probe in
            probe.bytes = empty ? Data() : nil
            await #expect(throws: DownloadedItemImagesModel.ExportFailure.missingBytes) {
                try await model.exportImage(accountId: value.accountId,itemId: value.itemId,image: value.images[0],reader: feed,
                    prepareDestination: { probe.prepared = true },handoff: { probe.delivered = $0 })
            }
            #expect(probe.reads == 1 && probe.delivered == nil && !model.isExporting)
        }
    }

    @Test("Duplicate exports stay blocked until the first destination completes")
    func exportDuplicate() async throws {
        try await withGallery { model,feed,value,probe in
            let gate = ExportGate()
            let operation = Task {
                try await model.exportImage(accountId: value.accountId,itemId: value.itemId,image: value.images[0],reader: feed,
                    prepareDestination: { probe.prepared = true },handoff: { _ in await gate.wait() })
            }
            await gate.expectEntered()
            await #expect(throws: DownloadedItemImagesModel.ExportFailure.alreadyExporting) {
                try await model.exportImage(accountId: value.accountId,itemId: value.itemId,image: value.images[0],reader: feed,
                    prepareDestination: { Issue.record("Duplicate requested permission") },handoff: { _ in Issue.record("Duplicate delivery") })
            }
            #expect(model.isExporting && probe.reads == 1)
            gate.release();try await operation.value
            #expect(!model.isExporting)
        }
    }

    @Test("Cancellation before handoff rejects; cancellation after handoff awaits actual completion",
          arguments: ["before","permission","download","handoff"])
    func exportCancellation(phase: String) async throws {
        try await withGallery { model,feed,value,probe in
            let gate = ExportGate()
            if phase == "download" { probe.gate = gate }
            var completed = false
            let operation = Task {
                try await model.exportImage(accountId: value.accountId,itemId: value.itemId,image: value.images[0],reader: feed,
                    prepareDestination: { probe.prepared = true;if phase == "permission" { await gate.wait() } },
                    handoff: { bytes in
                        if phase == "handoff" { await gate.wait() }
                        probe.delivered = bytes;completed = true
                    })
            }
            if phase != "before" { await gate.expectEntered() }
            operation.cancel()
            if phase == "handoff" { #expect(model.isExporting && !completed) }
            gate.release()
            if phase == "handoff" { try await operation.value;#expect(completed && probe.delivered != nil) }
            else { await #expect(throws: CancellationError.self) { try await operation.value };#expect(probe.delivered == nil) }
            if phase == "before" { #expect(!probe.prepared && probe.reads == 0) }
            #expect(!model.isExporting)
        }
    }

    @Test("Destination failure is propagated and releases the export lock")
    func exportDeliveryFailure() async throws {
        try await withGallery { model,feed,value,probe in
            await #expect(throws: ExportTestFailure.delivery) {
                try await model.exportImage(accountId: value.accountId,itemId: value.itemId,image: value.images[0],reader: feed,
                    prepareDestination: { probe.prepared = true },handoff: { _ in throw ExportTestFailure.delivery })
            }
            #expect(!model.isExporting && probe.reads == 1)
        }
    }

    private func withGallery(_ body: (DownloadedItemImagesModel,Feed,DownloadedItemImageCatalog,ExportProbe) async throws -> Void) async throws {
        let value = try catalog(), probe = ExportProbe()
        let feed = Feed(load: probe.read), model = DownloadedItemImagesModel()
        let task = Task { await model.load(accountId: value.accountId,itemId: value.itemId,reader: feed) }
        feed.continuation.yield(value);await expectState(model,.downloaded(value))
        do { try await body(model,feed,value,probe) }
        catch { task.cancel();feed.continuation.finish();await task.value;throw error }
        task.cancel();feed.continuation.finish();await task.value
    }

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
    let load: @Sendable (AccountID,ItemID,DownloadedItemImage,Bool) async throws -> Data?
    init(load: @escaping @Sendable (AccountID,ItemID,DownloadedItemImage,Bool) async throws -> Data? = { _,_,_,_ in throw DownloadedItemImageFailure.unavailable }) {
        (stream, continuation) = AsyncThrowingStream.makeStream();self.load = load
    }
    func watchDownloadedItemImages(accountId: AccountID, itemId: ItemID) -> AsyncThrowingStream<DownloadedItemImageCatalog, Error> { stream }
    func loadDownloadedItemImage(accountId: AccountID, itemId: ItemID, image: DownloadedItemImage, allowDownload: Bool) async throws -> Data? {
        try await load(accountId,itemId,image,allowDownload)
    }
}

private enum ExportTestFailure: Error { case denied,delivery }

@MainActor private final class ExportProbe {
    var prepared = false
    var reads = 0
    var loadedImage: DownloadedItemImage?
    var loadedAccount: AccountID?
    var loadedItem: ItemID?
    var allowedDownload = false
    var delivered: Data?
    var bytes: Data? = Data([1,2,3])
    var gate: ExportGate?
    func read(_ account: AccountID,_ item: ItemID,_ image: DownloadedItemImage,_ allow: Bool) async throws -> Data? {
        #expect(prepared)
        reads += 1;loadedAccount = account;loadedItem = item;loadedImage = image;allowedDownload = allow
        if let gate { await gate.wait() }
        return bytes
    }
}

@MainActor private final class ExportGate {
    private var continuation: CheckedContinuation<Void,Never>?
    private var entered = false
    func wait() async { entered = true;await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume();continuation = nil }
    func expectEntered() async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !entered && ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(1)) }
        #expect(entered)
    }
}
