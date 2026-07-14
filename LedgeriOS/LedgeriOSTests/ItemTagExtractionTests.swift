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
        #expect(result.skuCandidates.contains("400293670643000799"))
        #expect(result.skuCandidates.contains("400293670643"))
    }

    @Test("Barcode item prefix is a chip but not an auto-fill")
    func barcodeItemPrefixIsChipOnly() {
        let result = ItemTagExtraction.extract(
            barcodePayloads: ["400297925640000999"],
            textObservations: [
                ItemTagTextObservation(text: "ROSS HOME DECOR $9.99", confidence: 0.86),
            ]
        )

        #expect(result.selectedSku == nil)
        #expect(result.skuCandidates.contains("400297925640"))
    }

    @Test("Barcode supports matching OCR SKU")
    func barcodeSupportsMatchingOcrSku() {
        let result = ItemTagExtraction.extract(
            barcodePayloads: ["400296767289000699"],
            textObservations: [
                ItemTagTextObservation(text: "400296767289", confidence: 0.82),
            ]
        )

        #expect(result.selectedSku == nil)
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

    // Fixtures curated from sku-extraction-pipeline-examples.md. Keeping the
    // inputs here makes the audit's expected behavior executable and reviewable.
    @Test("Roe Trinidad TJX barcodes derive corroborated STYLE", arguments: [
        ("35220251003999", "35", "220251", "$39.99"),
        ("33396076003499", "33", "396076", "$34.99"),
    ])
    func tjxBarcodeRegression(barcode: String, department: String, style: String, price: String) {
        let result = ItemTagExtraction.extract(
            barcodeObservations: [ItemTagBarcodeObservation(payload: barcode, sourceEngine: .vision, sourceImage: "02.jpg")],
            textObservations: [observation("DEPT \(department)  STYLE \(style)  TYPE 7  CAT 12  FLS T0626  OUR PRICE \(price)")],
            vendorHint: "HomeGoods"
        )

        #expect(result.selectedSku == style)
        #expect(result.candidates.first?.extractionMethod == .barcodeDerived)
        #expect(result.candidates.first?.department == department)
        #expect(result.candidates.first?.sourceImage == "02.jpg")
    }

    @Test("TJX barcode is not decoded without field and price corroboration")
    func tjxBarcodeRequiresCorroboration() {
        let result = ItemTagExtraction.extract(
            barcodePayloads: ["35220251003999"],
            textObservations: [observation("HOMEGOODS OUR PRICE $34.99")],
            vendorHint: "HomeGoods"
        )
        #expect(result.selectedSku == nil)
        #expect(!result.skuCandidates.contains("220251"))
    }

    @Test("Corrupted STYLE label yields its value, never the label")
    func corruptedStyleLabel() {
        let result = ItemTagExtraction.extract(textObservations: [observation("STVLE 389310")], vendorHint: "HomeGoods")
        #expect(result.selectedSku == "389310")
        #expect(!result.skuCandidates.contains("STVLE"))
    }

    @Test("Whole-document normalization cannot create phantom SKU")
    func preservesTokenBoundaries() {
        let receipt = "Survey 220 / 251\nApproval 003 / 999\nDate 07/14/26"
        #expect(!ItemTagExtraction.exactTokenMatch("220251", in: receipt))
        #expect(ItemTagExtraction.exactTokenMatch("220", in: receipt))
    }

    @Test("Known Roe Trinidad noise is rejected", arguments: [
        "S49.99", "S40.00", "$34.99", "T0626", "T0526", "060S",
        "18X18", "46X46CM", "AX70", "8ETE7S", "I700",
    ])
    func rejectsKnownNoise(value: String) {
        let result = ItemTagExtraction.extract(textObservations: [observation(value)])
        #expect(!result.skuCandidates.contains(value.uppercased()))
        #expect(result.rejectedCandidates.contains { $0.value == value.uppercased() })
    }

    @Test("Cross-engine disagreement does not choose either value")
    func crossEngineDisagreement() {
        let result = ItemTagExtraction.extract(textObservations: [
            observation("STYLE 382806", engine: .tesseract),
            observation("STYLE 382606", engine: .vision),
        ], vendorHint: "HomeGoods")
        #expect(result.selectedSku == nil)
        #expect(result.reviewFlags.contains("cross-engine-disagreement"))
    }

    @Test("Matching evidence is aggregated across engines and images")
    func aggregatesMatchingEvidence() {
        let result = ItemTagExtraction.extract(textObservations: [
            ItemTagTextObservation(text: "STYLE 382806", confidence: 0.91, sourceEngine: .vision, sourceImage: "phone.jpg"),
            ItemTagTextObservation(text: "STYLE 382806", confidence: 0.88, sourceEngine: .tesseract, sourceImage: "crop.jpg"),
        ], vendorHint: "HomeGoods")

        let candidate = result.candidates.first { $0.value == "382806" }
        #expect(candidate?.allEvidence.contains { $0.sourceEngine == .vision && $0.sourceImage == "phone.jpg" } == true)
        #expect(candidate?.allEvidence.contains { $0.sourceEngine == .tesseract && $0.sourceImage == "crop.jpg" } == true)
        #expect(!result.reviewFlags.contains("cross-engine-disagreement"))
        #expect(result.selectedSku == "382806")
    }

    @Test("Vision misread cannot overwrite barcode-backed 382806")
    func existingBarcodeBackedSkuWins() {
        let extraction = ItemTagExtraction.extract(textObservations: [observation("STYLE 382606", engine: .vision)], vendorHint: "HomeGoods")
        let decision = ItemTagSkuMutationPolicy.decide(existingSku: "382806", existingEvidence: .barcodeBacked, extraction: extraction)
        #expect(decision == .review(existing: "382806", proposed: "382606"))
    }

    @Test("Tag signal requests one retry then stops without guessing")
    func retryAndStop() {
        let initial = ItemTagExtraction.extract(textObservations: [observation("DEPT 35  OUR PRICE $39.99")], vendorHint: "HomeGoods")
        #expect(initial.retryRecommended)
        let retried = ItemTagExtraction.extract(textObservations: [observation("DEPT 35  OUR PRICE $39.99")], vendorHint: "HomeGoods", retryPerformed: true)
        #expect(!retried.retryRecommended)
        #expect(retried.selectedSku == nil)
        #expect(retried.reviewFlags.contains("tag-retry-exhausted-no-confident-sku"))
    }

    @Test("OCR routing is explicit by image profile")
    func engineRouting() {
        #expect(ItemTagExtractionService.engineRoute(for: .phonePhoto) == .visionPrimary)
        #expect(ItemTagExtractionService.engineRoute(for: .longReceiptPhoto) == .visionPrimary)
        #expect(ItemTagExtractionService.engineRoute(for: .cleanScan) == .tesseractPrimary)
        #expect(ItemTagExtractionService.engineRoute(for: .pdfRender) == .tesseractPrimary)
        #expect(ItemTagExtractionService.engineRoute(for: .tightCrop) == .tesseractPrimary)
    }

    private func observation(_ text: String, engine: ItemTagOCREngine = .vision) -> ItemTagTextObservation {
        ItemTagTextObservation(text: text, confidence: 0.95, sourceEngine: engine, sourceImage: "roe-regression.jpg")
    }
}
