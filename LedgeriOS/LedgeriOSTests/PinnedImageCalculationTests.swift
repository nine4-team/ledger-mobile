import Foundation
import Testing
@testable import LedgeriOS

@Suite("Pinned Image Calculation Tests")
struct PinnedImageCalculationTests {

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
