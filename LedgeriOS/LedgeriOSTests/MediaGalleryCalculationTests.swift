import Foundation
import Testing
@testable import LedgeriOS

@Suite("Media Gallery Calculation Tests")
struct MediaGalleryCalculationTests {

    // MARK: - canAddAttachment

    @Test("Can add when under limit")
    func canAddUnderLimit() {
        let current = [AttachmentRef(url: "a"), AttachmentRef(url: "b")]
        #expect(MediaGalleryCalculations.canAddAttachment(current: current, maxAttachments: 5))
    }

    @Test("Cannot add when at limit")
    func cannotAddAtLimit() {
        let current = [AttachmentRef(url: "a"), AttachmentRef(url: "b"), AttachmentRef(url: "c")]
        #expect(!MediaGalleryCalculations.canAddAttachment(current: current, maxAttachments: 3))
    }

    @Test("Can add when empty")
    func canAddWhenEmpty() {
        #expect(MediaGalleryCalculations.canAddAttachment(current: [], maxAttachments: 5))
    }

    // MARK: - isAllowedKind

    @Test("Image allowed in mixed kinds")
    func imageAllowedInMixed() {
        #expect(MediaGalleryCalculations.isAllowedKind(.image, allowedKinds: [.image, .pdf]))
    }

    @Test("PDF not allowed when only images")
    func pdfNotAllowedInImagesOnly() {
        #expect(!MediaGalleryCalculations.isAllowedKind(.pdf, allowedKinds: [.image]))
    }

    // MARK: - primaryImage

    @Test("Returns attachment with isPrimary set")
    func returnsPrimaryImage() {
        let attachments = [
            AttachmentRef(url: "a", kind: .image),
            AttachmentRef(url: "b", kind: .image, isPrimary: true),
            AttachmentRef(url: "c", kind: .image),
        ]
        #expect(MediaGalleryCalculations.primaryImage(attachments)?.url == "b")
    }

    @Test("Falls back to first image when no primary")
    func fallsBackToFirstImage() {
        let attachments = [
            AttachmentRef(url: "a", kind: .pdf),
            AttachmentRef(url: "b", kind: .image),
            AttachmentRef(url: "c", kind: .image),
        ]
        #expect(MediaGalleryCalculations.primaryImage(attachments)?.url == "b")
    }

    @Test("Returns nil for empty attachments")
    func returnsNilForEmpty() {
        #expect(MediaGalleryCalculations.primaryImage([]) == nil)
    }

    // MARK: - gridColumns

    @Test("Zero items returns 1 column")
    func zeroItemsOneColumn() {
        #expect(MediaGalleryCalculations.gridColumns(for: 0) == 1)
    }

    @Test("One item returns 1 column")
    func oneItemOneColumn() {
        #expect(MediaGalleryCalculations.gridColumns(for: 1) == 1)
    }

    @Test("Three items returns 3 columns")
    func threeItemsThreeColumns() {
        #expect(MediaGalleryCalculations.gridColumns(for: 3) == 3)
    }

    @Test("Ten items capped at preferred columns")
    func tenItemsCapped() {
        #expect(MediaGalleryCalculations.gridColumns(for: 10) == 3)
    }

    // MARK: - thumbnailCount

    @Test("Counts only image attachments in mixed list")
    func countsOnlyImages() {
        let attachments = [
            AttachmentRef(url: "a", kind: .image),
            AttachmentRef(url: "b", kind: .pdf),
            AttachmentRef(url: "c", kind: .image),
            AttachmentRef(url: "d", kind: .file),
        ]
        #expect(MediaGalleryCalculations.thumbnailCount(attachments) == 2)
    }
}
