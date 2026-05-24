import Foundation
import Testing
@testable import LedgeriOS

@Suite("Item Tag Extraction Tests")
struct ItemTagExtractionTests {
    @Test("Barcode payload is evidence, not selected SKU")
    func barcodePayloadIsEvidenceOnly() {
        let result = ItemTagExtraction.extract(
            barcodePayloads: ["400293670643000799"],
            textObservations: [
                ItemTagTextObservation(text: "SKU: ABC-123", confidence: 0.92),
            ]
        )

        #expect(result.selectedSku == "ABC-123")
        #expect(result.barcodePayloads == ["400293670643000799"])
        #expect(result.skuCandidates.contains("400293670643000799"))
    }

    @Test("Barcode-only payload does not auto-select SKU")
    func barcodeOnlyDoesNotAutoSelectSku() {
        let result = ItemTagExtraction.extract(
            barcodePayloads: ["400293670643000799"],
            textObservations: []
        )

        #expect(result.selectedSku == nil)
        #expect(result.skuCandidates == ["400293670643000799"])
    }

    @Test("Barcode supports matching OCR SKU")
    func barcodeSupportsMatchingOcrSku() {
        let result = ItemTagExtraction.extract(
            barcodePayloads: ["400296767289000699"],
            textObservations: [
                ItemTagTextObservation(text: "400296767289", confidence: 0.82),
            ]
        )

        #expect(result.selectedSku == "400296767289")
        #expect(result.skuCandidates.first == "400296767289")
    }

    @Test("Barcode substrings must be long enough to auto-fill")
    func shortBarcodeSubstringsDoNotAutoSelect() {
        let result = ItemTagExtraction.extract(
            barcodePayloads: ["0789112613222"],
            textObservations: [
                ItemTagTextObservation(text: "124350733\n89112\n61322 2", confidence: 0.84),
            ]
        )

        #expect(result.selectedSku == nil)
        #expect(result.skuCandidates.contains("124350733"))
        #expect(result.skuCandidates.contains("61322"))
    }

    @Test("Dashed SKU candidates are still supported")
    func dashedSkuCandidatesAreStillSupported() {
        let result = ItemTagExtraction.extract(
            textObservations: [
                ItemTagTextObservation(text: "Item # 313-433-0203", confidence: 0.9),
            ]
        )

        #expect(result.selectedSku == "313-433-0203")
    }

    @Test("Loose barcode-shaped OCR stays a chip without auto-fill")
    func looseBarcodeShapedOcrDoesNotAutoSelect() {
        let result = ItemTagExtraction.extract(
            textObservations: [
                ItemTagTextObservation(text: "World Market 26446592 $29.99", confidence: 0.84),
            ]
        )

        #expect(result.selectedSku == nil)
        #expect(result.skuCandidates.contains("26446592"))
    }

    @Test("Standalone numeric item numbers stay chips without auto-fill")
    func standaloneNumericItemNumbersStayChips() {
        let result = ItemTagExtraction.extract(
            textObservations: [
                ItemTagTextObservation(text: "Honeybloom\n124350733\n12-23", confidence: 0.86),
            ]
        )

        #expect(result.selectedSku == nil)
        #expect(result.skuCandidates.contains("124350733"))
        #expect(!result.skuCandidates.contains("12-23"))
    }

    @Test("Extracts labeled SKU on same line")
    func extractsLabeledSku() {
        let result = ItemTagExtraction.extract(
            textObservations: [
                ItemTagTextObservation(text: "SKU: ABC-123", confidence: 0.94),
            ]
        )

        #expect(result.selectedSku == "ABC-123")
        #expect(result.rawText == "SKU: ABC-123")
    }

    @Test("Extracts SKU from next line after label")
    func extractsSkuOnNextLine() {
        let result = ItemTagExtraction.extract(
            textObservations: [
                ItemTagTextObservation(text: "STYLE\nCH-8891-BRN", confidence: 0.88),
            ]
        )

        #expect(result.selectedSku == "CH-8891-BRN")
    }

    @Test("Ranks labeled candidate over loose candidate")
    func ranksLabeledCandidateFirst() {
        let result = ItemTagExtraction.extract(
            textObservations: [
                ItemTagTextObservation(text: "Receipt 2024-01-10\nModel No. SF-001\nBatch XX-999", confidence: 0.9),
            ]
        )

        #expect(result.selectedSku == "SF-001")
    }

    @Test("Rejects price and phone shaped false positives")
    func rejectsFalsePositives() {
        let result = ItemTagExtraction.extract(
            textObservations: [
                ItemTagTextObservation(text: "$49.99\nCall 808-555-1212\nDate 12-31-2025", confidence: 0.9),
            ]
        )

        #expect(result.selectedSku == nil)
        #expect(result.skuCandidates.isEmpty)
    }

    @Test("Keeps UPC length numeric candidate")
    func keepsUpcCandidate() {
        let result = ItemTagExtraction.extract(
            textObservations: [
                ItemTagTextObservation(text: "UPC 012345678905", confidence: 0.91),
            ]
        )

        #expect(result.selectedSku == "012345678905")
    }

    @Test("Weak loose candidates do not auto-select SKU")
    func weakLooseCandidatesDoNotAutoSelect() {
        let result = ItemTagExtraction.extract(
            textObservations: [
                ItemTagTextObservation(text: "D&D Santal & Coco 15 oz 516G", confidence: 0.8),
                ItemTagTextObservation(text: "www.p65warnings.ca.gov/product", confidence: 0.8),
                ItemTagTextObservation(text: "NO103 all new material consisting of 100% polyester", confidence: 0.8),
            ]
        )

        #expect(result.selectedSku == nil)
        #expect(result.skuCandidates.contains("516G"))
        #expect(result.skuCandidates.contains("NO103"))
    }
}
