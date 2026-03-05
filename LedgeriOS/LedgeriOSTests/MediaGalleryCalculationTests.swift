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

    // MARK: - previousIndex / nextIndex

    @Test("Previous index wraps from first to last")
    func previousIndexWraps() {
        #expect(MediaGalleryCalculations.previousIndex(current: 0, total: 5) == 4)
    }

    @Test("Previous index decrements normally")
    func previousIndexDecrements() {
        #expect(MediaGalleryCalculations.previousIndex(current: 3, total: 5) == 2)
    }

    @Test("Previous index returns 0 for single item")
    func previousIndexSingleItem() {
        #expect(MediaGalleryCalculations.previousIndex(current: 0, total: 1) == 0)
    }

    @Test("Previous index returns 0 for empty gallery")
    func previousIndexEmpty() {
        #expect(MediaGalleryCalculations.previousIndex(current: 0, total: 0) == 0)
    }

    @Test("Next index wraps from last to first")
    func nextIndexWraps() {
        #expect(MediaGalleryCalculations.nextIndex(current: 4, total: 5) == 0)
    }

    @Test("Next index increments normally")
    func nextIndexIncrements() {
        #expect(MediaGalleryCalculations.nextIndex(current: 1, total: 5) == 2)
    }

    @Test("Next index returns 0 for single item")
    func nextIndexSingleItem() {
        #expect(MediaGalleryCalculations.nextIndex(current: 0, total: 1) == 0)
    }

    @Test("Next index returns 0 for empty gallery")
    func nextIndexEmpty() {
        #expect(MediaGalleryCalculations.nextIndex(current: 0, total: 0) == 0)
    }

    // MARK: - dismissProgress

    @Test("Dismiss progress is 0 at zero translation")
    func dismissProgressZero() {
        #expect(MediaGalleryCalculations.dismissProgress(translation: 0, threshold: 300) == 0)
    }

    @Test("Dismiss progress is 1 at threshold")
    func dismissProgressAtThreshold() {
        #expect(MediaGalleryCalculations.dismissProgress(translation: 300, threshold: 300) == 1)
    }

    @Test("Dismiss progress caps at 1 past threshold")
    func dismissProgressCaps() {
        #expect(MediaGalleryCalculations.dismissProgress(translation: 500, threshold: 300) == 1)
    }

    @Test("Dismiss progress works with negative translation (upward drag)")
    func dismissProgressNegative() {
        let progress = MediaGalleryCalculations.dismissProgress(translation: -150, threshold: 300)
        #expect(progress == 0.5)
    }

    @Test("Dismiss progress is 0 with zero threshold")
    func dismissProgressZeroThreshold() {
        #expect(MediaGalleryCalculations.dismissProgress(translation: 100, threshold: 0) == 0)
    }

    // MARK: - dismissScale

    @Test("Dismiss scale is 1.0 at zero progress")
    func dismissScaleAtRest() {
        #expect(MediaGalleryCalculations.dismissScale(progress: 0) == 1.0)
    }

    @Test("Dismiss scale is 0.7 at full progress")
    func dismissScaleAtFull() {
        #expect(MediaGalleryCalculations.dismissScale(progress: 1.0) == 0.7)
    }

    @Test("Dismiss scale at half progress")
    func dismissScaleAtHalf() {
        #expect(MediaGalleryCalculations.dismissScale(progress: 0.5) == 0.85)
    }

    // MARK: - dismissOpacity

    @Test("Dismiss opacity is 1.0 at zero progress")
    func dismissOpacityAtRest() {
        #expect(MediaGalleryCalculations.dismissOpacity(progress: 0) == 1.0)
    }

    @Test("Dismiss opacity is 0.0 at full progress")
    func dismissOpacityAtFull() {
        #expect(MediaGalleryCalculations.dismissOpacity(progress: 1.0) == 0.0)
    }

    @Test("Dismiss opacity at half progress")
    func dismissOpacityAtHalf() {
        #expect(MediaGalleryCalculations.dismissOpacity(progress: 0.5) == 0.5)
    }
}
