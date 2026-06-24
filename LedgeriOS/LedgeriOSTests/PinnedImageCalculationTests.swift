import Foundation
import Testing
@testable import LedgeriOS

@Suite("Pinned Image Calculation Tests")
struct PinnedImageCalculationTests {

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
