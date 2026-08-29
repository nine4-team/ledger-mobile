import Foundation
import Testing
@testable import LedgeriOS

@Suite("Pinned Image Calculation Tests")
struct PinnedImageCalculationTests {

    @Test("marked item IDs include linked marks across photos and ignore unassigned marks")
    func markedItemIdsAcrossPhotos() {
        let attachments = [
            AttachmentRef(
                url: "one",
                checkmarks: [
                    ImageCheckmark(id: "m1", x: 0.1, y: 0.2, itemId: "item1"),
                    ImageCheckmark(id: "legacy", x: 0.3, y: 0.4),
                ]
            ),
            AttachmentRef(
                url: "two",
                checkmarks: [ImageCheckmark(id: "m2", x: 0.5, y: 0.6, itemId: "item2")]
            ),
        ]

        #expect(PinnedImageCalculations.markedItemIds(in: attachments) == ["item1", "item2"])
    }

    @Test("multi-item marks contribute every linked item exactly once")
    func markedItemIdsIncludeMultiItemMarks() {
        let attachments = [AttachmentRef(
            url: "one",
            checkmarks: [
                ImageCheckmark(
                    id: "group",
                    x: 0.1,
                    y: 0.2,
                    itemId: "item1",
                    itemIds: ["item1", "item2", "item2", "item3"]
                ),
            ]
        )]

        #expect(PinnedImageCalculations.markedItemIds(in: attachments) == ["item1", "item2", "item3"])
    }

    @Test("placement assignments split evenly and allow an adjusted first location")
    func placementAssignmentsSplitConcreteItems() {
        let ids = (1...5).map { "item\($0)" }

        #expect(PinnedImageCalculations.placementAssignments(
            itemIds: ids,
            locationCount: 1
        ).map(\.count) == [5])
        #expect(PinnedImageCalculations.placementAssignments(
            itemIds: ids,
            locationCount: 2
        ).map(\.count) == [3, 2])
        #expect(PinnedImageCalculations.placementAssignments(
            itemIds: ids,
            locationCount: 2,
            firstLocationCount: 1
        ).map(\.count) == [1, 4])
    }

    @Test("bulk placement writes two marks and removes prior links atomically")
    func bulkPlacementReplacesPriorLinks() throws {
        let attachments = [
            AttachmentRef(
                url: "old-photo",
                checkmarks: [
                    ImageCheckmark(id: "old", x: 0.1, y: 0.2, itemId: "item1"),
                    ImageCheckmark(
                        id: "mixed",
                        x: 0.3,
                        y: 0.4,
                        itemId: "item2",
                        itemIds: ["item2", "unrelated"]
                    ),
                ]
            ),
            AttachmentRef(url: "new-photo"),
        ]

        let updated = PinnedImageCalculations.placingCheckmarks(
            assignments: [["item1", "item2"], ["item3", "item4"]],
            at: [CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.8, y: 0.7)],
            in: "new-photo",
            attachments: attachments,
            checkmarkIds: ["bouquet1", "bouquet2"]
        )

        let preserved = try #require(updated[0].checkmarks?.first)
        #expect(preserved.id == "mixed")
        #expect(preserved.linkedItemIds == ["unrelated"])
        let newMarks = try #require(updated[1].checkmarks)
        #expect(newMarks.map(\.id) == ["bouquet1", "bouquet2"])
        #expect(newMarks.map(\.linkedItemIds) == [["item1", "item2"], ["item3", "item4"]])
    }

    @Test("photo check progress counts only current space items")
    func photoCheckProgressIgnoresStaleAndUnassignedMarks() {
        let attachments = [AttachmentRef(
            url: "one",
            checkmarks: [
                ImageCheckmark(id: "current", x: 0.1, y: 0.2, itemId: "item1"),
                ImageCheckmark(id: "stale", x: 0.3, y: 0.4, itemId: "moved-item"),
                ImageCheckmark(id: "legacy", x: 0.5, y: 0.6),
            ]
        )]

        let progress = PinnedImageCalculations.photoCheckProgress(
            itemIds: ["item1", "item2", "item3"],
            attachments: attachments
        )

        #expect(progress.checkedCount == 1)
        #expect(progress.totalCount == 3)
        #expect(progress.remainingCount == 2)
        #expect(abs(progress.percentage - (100.0 / 3.0)) < 0.000_001)
        #expect(!progress.isComplete)
    }

    @Test("photo check progress completes only when a nonempty space is fully checked")
    func photoCheckProgressCompletion() {
        let attachments = [AttachmentRef(
            url: "one",
            checkmarks: [
                ImageCheckmark(id: "one", x: 0.1, y: 0.2, itemId: "item1"),
                ImageCheckmark(id: "two", x: 0.3, y: 0.4, itemId: "item2"),
            ]
        )]

        let complete = PinnedImageCalculations.photoCheckProgress(
            itemIds: ["item1", "item2"],
            attachments: attachments
        )
        let empty = PinnedImageCalculations.photoCheckProgress(
            itemIds: [],
            attachments: attachments
        )

        #expect(complete.remainingCount == 0)
        #expect(complete.percentage == 100)
        #expect(complete.isComplete)
        #expect(empty.checkedCount == 0)
        #expect(empty.totalCount == 0)
        #expect(empty.percentage == 0)
        #expect(!empty.isComplete)
    }

    @Test("placing a mark moves the item from another photo instead of duplicating it")
    func placingMarkEnforcesOnePhotoPerItem() throws {
        let attachments = [
            AttachmentRef(
                url: "one",
                checkmarks: [
                    ImageCheckmark(id: "old", x: 0.1, y: 0.2, itemId: "item1"),
                    ImageCheckmark(id: "other", x: 0.3, y: 0.4, itemId: "item2"),
                ]
            ),
            AttachmentRef(url: "two"),
        ]

        let updated = PinnedImageCalculations.placingCheckmark(
            for: "item1",
            at: CGPoint(x: 0.75, y: 0.25),
            in: "two",
            attachments: attachments,
            checkmarkId: "replacement"
        )

        let expectedOtherMark = ImageCheckmark(id: "other", x: 0.3, y: 0.4, itemId: "item2")
        #expect(updated[0].checkmarks == [expectedOtherMark])
        let replacement = try #require(updated[1].checkmarks?.first)
        let expectedReplacement = ImageCheckmark(
            id: "replacement",
            x: 0.75,
            y: 0.25,
            itemId: "item1"
        )
        #expect(replacement == expectedReplacement)
        let itemMarks = updated.flatMap { $0.checkmarks ?? [] }.filter { $0.itemId == "item1" }
        #expect(itemMarks.count == 1)
    }

    @Test("cleanup removes moved item marks while preserving unassigned and unrelated marks")
    func cleanupPreservesOtherMarks() {
        let attachments = [AttachmentRef(
            url: "one",
            checkmarks: [
                ImageCheckmark(id: "moved", x: 0.1, y: 0.2, itemId: "item1"),
                ImageCheckmark(id: "kept", x: 0.3, y: 0.4, itemId: "item2"),
                ImageCheckmark(id: "legacy", x: 0.5, y: 0.6),
            ]
        )]

        let updated = PinnedImageCalculations.removingCheckmarks(
            for: ["item1"],
            from: attachments
        )

        #expect(updated[0].checkmarks == [
            ImageCheckmark(id: "kept", x: 0.3, y: 0.4, itemId: "item2"),
            ImageCheckmark(id: "legacy", x: 0.5, y: 0.6),
        ])
    }

    @Test("cleanup removes only the moved item from a multi-item mark")
    func cleanupPreservesRemainingMultiItemLinks() throws {
        let attachments = [AttachmentRef(
            url: "one",
            checkmarks: [ImageCheckmark(
                id: "group",
                x: 0.1,
                y: 0.2,
                itemId: "item1",
                itemIds: ["item1", "item2", "item3"]
            )]
        )]

        let updated = PinnedImageCalculations.removingCheckmarks(
            for: ["item2"],
            from: attachments
        )

        let mark = try #require(updated[0].checkmarks?.first)
        #expect(mark.linkedItemIds == ["item1", "item3"])
    }

    @Test("clear all removes marks without removing attachments")
    func clearAllPreservesAttachments() {
        let attachments = [
            AttachmentRef(
                url: "one",
                checkmarks: [ImageCheckmark(id: "m1", x: 0.1, y: 0.2, itemId: "item1")]
            ),
            AttachmentRef(
                url: "two",
                checkmarks: [ImageCheckmark(id: "legacy", x: 0.3, y: 0.4)]
            ),
        ]

        let updated = PinnedImageCalculations.clearingCheckmarks(from: attachments)

        #expect(updated.map(\.url) == ["one", "two"])
        #expect(updated.allSatisfy { $0.checkmarks == nil })
    }

    // MARK: - Checkmark calibration

    @Test("Portrait image tap renders at the same point")
    func portraitImageTapRoundTrips() {
        let imageRect = PinnedImageCalculations.aspectFitRect(
            imageSize: CGSize(width: 900, height: 1600),
            in: CGSize(width: 390, height: 300)
        )
        let tap = CGPoint(x: 195, y: 150)

        let normalized = PinnedImageCalculations.normalizedImagePoint(for: tap, in: imageRect)
        let rendered = normalized.map {
            PinnedImageCalculations.renderedPoint(for: $0, in: imageRect)
        }

        #expect(normalized != nil)
        #expect(abs((normalized?.x ?? 0) - 0.5) < 0.000_001)
        #expect(abs((normalized?.y ?? 0) - 0.5) < 0.000_001)
        #expect(abs((rendered?.x ?? 0) - tap.x) < 0.001)
        #expect(abs((rendered?.y ?? 0) - tap.y) < 0.001)
    }

    @Test("Landscape image taps render within pixel tolerance")
    func landscapeImageTapsRoundTrip() {
        let imageRect = PinnedImageCalculations.aspectFitRect(
            imageSize: CGSize(width: 1600, height: 900),
            in: CGSize(width: 390, height: 300)
        )
        let taps = [
            CGPoint(x: imageRect.minX + 1, y: imageRect.minY + 1),
            CGPoint(x: imageRect.midX, y: imageRect.midY),
            CGPoint(x: imageRect.maxX - 1, y: imageRect.maxY - 1)
        ]

        for tap in taps {
            let normalized = PinnedImageCalculations.normalizedImagePoint(for: tap, in: imageRect)
            let rendered = normalized.map {
                PinnedImageCalculations.renderedPoint(for: $0, in: imageRect)
            }

            #expect(normalized != nil)
            #expect(abs((rendered?.x ?? 0) - tap.x) < 0.001)
            #expect(abs((rendered?.y ?? 0) - tap.y) < 0.001)
        }
    }

    @Test("Taps outside the image clamp to its edge")
    func outsideTapClampsToImageEdge() {
        let imageRect = CGRect(x: 100, y: 40, width: 200, height: 120)
        let normalized = PinnedImageCalculations.normalizedImagePoint(
            for: CGPoint(x: 20, y: 220),
            in: imageRect
        )

        #expect(normalized == CGPoint(x: 0, y: 1))
    }

    @Test("zoom and pan transforms round-trip photo points")
    func zoomPanPointRoundTrips() throws {
        let imageRect = CGRect(x: 20, y: 60, width: 350, height: 200)
        let original = CGPoint(x: 284, y: 127)
        let offset = CGSize(width: -48, height: 35)
        let rendered = PinnedImageCalculations.zoomedPoint(
            for: original,
            imageRect: imageRect,
            scale: 3.25,
            offset: offset
        )
        let recovered = try #require(PinnedImageCalculations.unzoomedPoint(
            for: rendered,
            imageRect: imageRect,
            scale: 3.25,
            offset: offset
        ))

        #expect(abs(recovered.x - original.x) < 0.001)
        #expect(abs(recovered.y - original.y) < 0.001)
    }

    @Test("pan clamps to scaled photo bounds")
    func panClampsToPhotoBounds() {
        let imageRect = CGRect(x: 0, y: 50, width: 400, height: 200)
        let result = PinnedImageCalculations.clampedPanOffset(
            CGSize(width: 900, height: -900),
            imageRect: imageRect,
            containerSize: CGSize(width: 400, height: 300),
            scale: 2
        )

        #expect(result == CGSize(width: 200, height: -50))
    }

    // MARK: - clampedFraction

    @Test("Clamps below minimum")
    func clampsBelowMin() {
        #expect(PinnedImageCalculations.clampedFraction(0.10) == 0.20)
    }

    @Test("Clamps above maximum")
    func clampsAboveMax() {
        #expect(PinnedImageCalculations.clampedFraction(0.60) == 0.50)
    }

    @Test("Passes through valid fraction")
    func passesThroughValid() {
        #expect(PinnedImageCalculations.clampedFraction(0.35) == 0.35)
    }

    @Test("Clamps to exact min boundary")
    func clampsExactMin() {
        #expect(PinnedImageCalculations.clampedFraction(0.20) == 0.20)
    }

    @Test("Clamps to exact max boundary")
    func clampsExactMax() {
        #expect(PinnedImageCalculations.clampedFraction(0.50) == 0.50)
    }

    @Test("Clamps with custom range")
    func clampsCustomRange() {
        #expect(PinnedImageCalculations.clampedFraction(0.10, min: 0.15, max: 0.40) == 0.15)
        #expect(PinnedImageCalculations.clampedFraction(0.50, min: 0.15, max: 0.40) == 0.40)
        #expect(PinnedImageCalculations.clampedFraction(0.25, min: 0.15, max: 0.40) == 0.25)
    }

    // MARK: - fractionAfterDrag

    @Test("Drag down increases fraction")
    func dragDownIncreases() {
        let result = PinnedImageCalculations.fractionAfterDrag(
            startFraction: 0.30,
            translationHeight: 100,
            totalHeight: 1000
        )
        #expect(result == 0.40)
    }

    @Test("Drag up decreases fraction")
    func dragUpDecreases() {
        let result = PinnedImageCalculations.fractionAfterDrag(
            startFraction: 0.30,
            translationHeight: -50,
            totalHeight: 1000
        )
        #expect(result == 0.25)
    }

    @Test("Drag clamps to min")
    func dragClampsToMin() {
        let result = PinnedImageCalculations.fractionAfterDrag(
            startFraction: 0.25,
            translationHeight: -200,
            totalHeight: 1000
        )
        #expect(result == 0.20)
    }

    @Test("Drag clamps to max")
    func dragClampsToMax() {
        let result = PinnedImageCalculations.fractionAfterDrag(
            startFraction: 0.45,
            translationHeight: 200,
            totalHeight: 1000
        )
        #expect(result == 0.50)
    }

    @Test("Zero total height returns start fraction")
    func zeroTotalHeight() {
        let result = PinnedImageCalculations.fractionAfterDrag(
            startFraction: 0.33,
            translationHeight: 100,
            totalHeight: 0
        )
        #expect(result == 0.33)
    }

    // MARK: - canPin

    @Test("Can pin image attachment")
    func canPinImage() {
        let attachment = AttachmentRef(url: "https://example.com/img.jpg", kind: .image)
        #expect(PinnedImageCalculations.canPin(attachment) == true)
    }

    @Test("Can pin PDF attachment")
    func canPinPDF() {
        let attachment = AttachmentRef(url: "https://example.com/doc.pdf", kind: .pdf)
        #expect(PinnedImageCalculations.canPin(attachment) == true)
    }

    @Test("Cannot pin file attachment")
    func cannotPinFile() {
        let attachment = AttachmentRef(url: "https://example.com/file.zip", kind: .file)
        #expect(PinnedImageCalculations.canPin(attachment) == false)
    }

    @Test("Cannot pin uploading image")
    func cannotPinUploading() {
        var attachment = AttachmentRef(url: "", kind: .image)
        attachment.isUploading = true
        #expect(PinnedImageCalculations.canPin(attachment) == false)
    }

    @Test("Can pin image with isUploading false")
    func canPinNotUploading() {
        var attachment = AttachmentRef(url: "https://example.com/img.jpg", kind: .image)
        attachment.isUploading = false
        #expect(PinnedImageCalculations.canPin(attachment) == true)
    }
}
