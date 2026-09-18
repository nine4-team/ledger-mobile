import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Existing Item image capture admission")
struct ItemImageCaptureAdmissionTests {
    @Test("Offline captures preserve selected order, first-image intent and exact retry")
    func orderingAndRetry() throws {
        let first = try ItemImageCaptureAdmission.assigningPlacement(capture("z-first"), catalog: catalog(), pending: [])
        #expect(first.metadata?.placement == .init(localPosition: 0, makePrimaryIfEmpty: true))
        let saved = try receipt(first)
        let second = try ItemImageCaptureAdmission.assigningPlacement(capture("a-second"), catalog: catalog(), pending: [saved])
        #expect(second.metadata?.placement == .init(localPosition: 1, makePrimaryIfEmpty: false))
        #expect(try ItemImageCaptureAdmission.assigningPlacement(capture("z-first"), catalog: catalog(), pending: [saved]) == first)
        #expect(throws: ItemImageCaptureFailure.invalidCapture) {
            try ItemImageCaptureAdmission.assigningPlacement(capture("z-first", bytes: Data([9])), catalog: catalog(), pending: [saved])
        }
    }

    @Test("Pending originals consume capacity; full-gallery retry does not consume another slot")
    func capacity() throws {
        var saved: [AttachmentLocalDurabilityReceipt] = []
        for index in 0..<50 {
            let positioned = try ItemImageCaptureAdmission.assigningPlacement(capture("photo-\(index)"), catalog: catalog(), pending: saved)
            saved.append(try receipt(positioned))
        }
        #expect(throws: ItemImageCaptureFailure.galleryFull) {
            try ItemImageCaptureAdmission.assigningPlacement(capture("extra"), catalog: catalog(), pending: saved)
        }
        #expect(try ItemImageCaptureAdmission.assigningPlacement(capture("photo-0"), catalog: catalog(), pending: saved)
            .metadata?.placement?.localPosition == 0)
    }

    @Test("Missing catalog, wrong Item, PDF and caller-chosen placement cannot authorize acceptance")
    func boundaries() throws {
        #expect(throws: ItemImageCaptureFailure.unavailable) {
            try ItemImageCaptureAdmission.assigningPlacement(capture("new"), catalog: catalog(complete: false), pending: [])
        }
        #expect(throws: ItemImageCaptureFailure.invalidCapture) {
            try ItemImageCaptureAdmission.assigningPlacement(capture("new"), catalog: catalog(item: "other"), pending: [])
        }
        #expect(throws: ItemImageCaptureFailure.invalidCapture) {
            try ItemImageCaptureAdmission.assigningPlacement(capture("new", mediaType: "application/pdf"), catalog: catalog(), pending: [])
        }
        let raw = try capture("new")
        let forged = try LocalAttachmentCapture(attachmentId: raw.attachmentId, scope: raw.scope,
            capturedAt: raw.capturedAt, bytes: raw.bytes,
            metadata: .init(mediaType: "image/png", fileName: nil, placement: .init(localPosition: 42, makePrimaryIfEmpty: true)))
        #expect(throws: ItemImageCaptureFailure.invalidCapture) {
            try ItemImageCaptureAdmission.assigningPlacement(forged, catalog: catalog(), pending: [])
        }
    }

    private func capture(_ id: String, bytes: Data = Data([1, 2, 3]), mediaType: String = "image/png") throws -> LocalAttachmentCapture {
        try .init(attachmentId: .init(validating: id), scope: .init(environment: .targetLocal,
            principalId: .init(validating: "member"), accountId: .init(validating: "account"),
            parent: .init(kind: .item, id: .init(validating: "item"))),
            capturedAt: .init(validating: 1), bytes: bytes, metadata: .init(mediaType: mediaType, fileName: "Original.png"))
    }

    @Test("Pending gallery keeps selection order and exact originals, then accepts synchronized identity")
    func pendingGallery() throws {
        let empty = try DownloadedItemImageCatalog(accountId: .init(validating: "account"),
            itemId: .init(validating: "item"), isComplete: true, images: [], revision: 7)
        let first = try ItemImageCaptureAdmission.assigningPlacement(capture("z-first"), catalog: empty, pending: [])
        let saved = try receipt(first)
        let second = try ItemImageCaptureAdmission.assigningPlacement(capture("a-second"), catalog: empty, pending: [saved])
        let pending = try empty.includingPending([receipt(second), saved], scope: first.scope)
        #expect(pending.images.map { $0.id.rawValue } == ["z-first", "a-second"])
        #expect(pending.images.first?.localReceipt == saved)
        #expect(pending.primaryImage?.id.rawValue == "z-first")
        let original = try #require(pending.images.first)
        let synced = try DownloadedItemImage(referenceId: original.referenceId, itemId: original.itemId,
            object: original.object, position: 0, isPrimary: true, setRevision: 8)
        let published = try DownloadedItemImageCatalog(accountId: empty.accountId, itemId: empty.itemId,
            isComplete: true, images: [synced], revision: 8)
            .includingPending([saved, receipt(second)], scope: first.scope)
        #expect(published.images.count == 2)
        #expect(published.images.first?.localReceipt == nil)
        #expect(published.images.last?.localReceipt?.attachmentId == second.attachmentId)
        let pendingSecond = try #require(pending.images.last)
        let secondPublishedFirst = try DownloadedItemImage(referenceId: pendingSecond.referenceId,
            itemId: pendingSecond.itemId, object: pendingSecond.object, position: 0, isPrimary: false, setRevision: 8)
        let interrupted = try DownloadedItemImageCatalog(accountId: empty.accountId, itemId: empty.itemId,
            isComplete: true, images: [secondPublishedFirst], revision: 8)
            .includingPending([saved, receipt(second)], scope: first.scope,
                              rejections: [saved.attachmentId: "test_rejected"])
        #expect(interrupted.images.map(\.id.rawValue) == ["z-first", "a-second"])
        #expect(interrupted.images.map(\.position) == [0, 1])
        #expect(interrupted.primaryImage?.id.rawValue == "z-first")
        #expect(interrupted.localUploadRejections[saved.attachmentId] == "test_rejected")
        #expect(secondPublishedFirst.position == 0) // Presentation never mutates synchronized evidence.
        let foreignScope = try AttachmentCaptureScope(environment: .targetLocal,
            principalId: .init(validating: "someone-else"), accountId: empty.accountId, parent: first.scope.parent)
        #expect(try empty.includingPending([saved], scope: foreignScope).images.isEmpty)
    }
    private func receipt(_ capture: LocalAttachmentCapture) throws -> AttachmentLocalDurabilityReceipt {
        try .init(accepting: capture, persistedEvidence: .init(attachmentId: capture.attachmentId, scope: capture.scope,
            localObjectId: .init(validating: "local-\(capture.attachmentId.rawValue)"), byteCount: capture.byteCount,
            contentSHA256: capture.contentSHA256, persistedAt: .init(validating: 2)))
    }
    private func catalog(complete: Bool = true, item: String = "item") throws -> DownloadedItemImageCatalog {
        try .init(accountId: .init(validating: "account"), itemId: .init(validating: item), isComplete: complete, images: [])
    }
}
