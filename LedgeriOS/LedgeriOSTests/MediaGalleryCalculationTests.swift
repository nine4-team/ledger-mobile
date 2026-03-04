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

    // MARK: - shouldShowOptionsButton

    @Test("Options button visible when set primary available")
    func optionsButtonWithSetPrimary() {
        #expect(MediaGalleryCalculations.shouldShowOptionsButton(hasSetPrimary: true, hasRemove: false))
    }

    @Test("Options button visible when remove available")
    func optionsButtonWithRemove() {
        #expect(MediaGalleryCalculations.shouldShowOptionsButton(hasSetPrimary: false, hasRemove: true))
    }

    @Test("Options button hidden when no actions available")
    func optionsButtonHiddenNoActions() {
        #expect(!MediaGalleryCalculations.shouldShowOptionsButton(hasSetPrimary: false, hasRemove: false))
    }

    // MARK: - imageCounterLabel

    @Test("Counter shows 1 of 5 for first image")
    func counterFirstImage() {
        #expect(MediaGalleryCalculations.imageCounterLabel(currentIndex: 0, total: 5) == "1 of 5")
    }

    @Test("Counter shows 5 of 5 for last image")
    func counterLastImage() {
        #expect(MediaGalleryCalculations.imageCounterLabel(currentIndex: 4, total: 5) == "5 of 5")
    }

    // MARK: - canZoomIn / canZoomOut

    @Test("Can zoom in when below max")
    func canZoomInBelowMax() {
        #expect(MediaGalleryCalculations.canZoomIn(currentZoom: 1.0, maxZoom: 4.0))
    }

    @Test("Cannot zoom in at max")
    func cannotZoomInAtMax() {
        #expect(!MediaGalleryCalculations.canZoomIn(currentZoom: 4.0, maxZoom: 4.0))
    }

    @Test("Can zoom out when above min")
    func canZoomOutAboveMin() {
        #expect(MediaGalleryCalculations.canZoomOut(currentZoom: 2.0, minZoom: 1.0))
    }

    @Test("Cannot zoom out at min")
    func cannotZoomOutAtMin() {
        #expect(!MediaGalleryCalculations.canZoomOut(currentZoom: 1.0, minZoom: 1.0))
    }

    // MARK: - nextZoom / previousZoom

    @Test("Next zoom steps up by increment")
    func nextZoomStepsUp() {
        #expect(MediaGalleryCalculations.nextZoom(current: 1.0, step: 0.5, max: 4.0) == 1.5)
    }

    @Test("Next zoom clamps at max")
    func nextZoomClampsAtMax() {
        #expect(MediaGalleryCalculations.nextZoom(current: 3.8, step: 0.5, max: 4.0) == 4.0)
    }

    @Test("Previous zoom steps down by increment")
    func previousZoomStepsDown() {
        #expect(MediaGalleryCalculations.previousZoom(current: 2.0, step: 0.5, min: 1.0) == 1.5)
    }

    @Test("Previous zoom clamps at min")
    func previousZoomClampsAtMin() {
        #expect(MediaGalleryCalculations.previousZoom(current: 1.2, step: 0.5, min: 1.0) == 1.0)
    }

    // MARK: - shouldShowResetZoom

    @Test("Reset zoom visible when zoomed in")
    func resetZoomVisibleWhenZoomed() {
        #expect(MediaGalleryCalculations.shouldShowResetZoom(currentZoom: 2.0))
    }

    @Test("Reset zoom hidden at default zoom")
    func resetZoomHiddenAtDefault() {
        #expect(!MediaGalleryCalculations.shouldShowResetZoom(currentZoom: 1.0))
    }

    // MARK: - shouldShowAddTile

    @Test("Add tile visible when under limit with handler")
    func addTileVisibleUnderLimit() {
        #expect(MediaGalleryCalculations.shouldShowAddTile(currentCount: 3, maxAttachments: 10, hasAddHandler: true))
    }

    @Test("Add tile hidden at max")
    func addTileHiddenAtMax() {
        #expect(!MediaGalleryCalculations.shouldShowAddTile(currentCount: 10, maxAttachments: 10, hasAddHandler: true))
    }

    @Test("Add tile hidden without handler")
    func addTileHiddenNoHandler() {
        #expect(!MediaGalleryCalculations.shouldShowAddTile(currentCount: 3, maxAttachments: 10, hasAddHandler: false))
    }

    // MARK: - shouldShowUploadOverlay / uploadOverlayIcon

    @Test("Upload overlay visible when uploading")
    func uploadOverlayVisibleUploading() {
        #expect(MediaGalleryCalculations.shouldShowUploadOverlay(status: .uploading))
    }

    @Test("Upload overlay visible when failed")
    func uploadOverlayVisibleFailed() {
        #expect(MediaGalleryCalculations.shouldShowUploadOverlay(status: .failed))
    }

    @Test("Upload overlay hidden when nil")
    func uploadOverlayHiddenNil() {
        #expect(!MediaGalleryCalculations.shouldShowUploadOverlay(status: nil))
    }

    @Test("Upload icon nil for uploading (uses ProgressView)")
    func uploadIconNilForUploading() {
        #expect(MediaGalleryCalculations.uploadOverlayIcon(status: .uploading) == nil)
    }

    @Test("Upload icon shows icloud.slash for failed")
    func uploadIconForFailed() {
        #expect(MediaGalleryCalculations.uploadOverlayIcon(status: .failed) == "icloud.slash")
    }
}
