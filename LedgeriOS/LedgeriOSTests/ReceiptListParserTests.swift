import Foundation
import Testing
@testable import LedgeriOS

/// Tests ported verbatim from `src/utils/__tests__/receiptListParser.test.ts`.
@Suite("Receipt List Parser Tests")
struct ReceiptListParserTests {

    @Test("Parses a standard receipt line")
    func standardLine() {
        let result = ReceiptListParser.parseReceiptText("53 - ACCENT FURNISH 252972 $129.99 T")
        #expect(result.items == [
            ReceiptListParser.ParsedReceiptItem(name: "ACCENT FURNISH", sku: "252972", priceCents: 12999),
        ])
        #expect(result.skippedLines == [])
    }

    @Test("Parses multiple lines")
    func multipleLines() {
        let text = """
        53 - ACCENT FURNISH 252972 $129.99 T
        56 - EVERYDAY Q LIN 092626 $6.99 T
        45 - FLORALS 924460 $229.99 T
        """
        let result = ReceiptListParser.parseReceiptText(text)
        #expect(result.items.count == 3)
        #expect(result.items[0] == ReceiptListParser.ParsedReceiptItem(name: "ACCENT FURNISH", sku: "252972", priceCents: 12999))
        #expect(result.items[1] == ReceiptListParser.ParsedReceiptItem(name: "EVERYDAY Q LIN", sku: "092626", priceCents: 699))
        #expect(result.items[2] == ReceiptListParser.ParsedReceiptItem(name: "FLORALS", sku: "924460", priceCents: 22999))
    }

    @Test("Skips blank lines silently")
    func blankLines() {
        let text = "53 - ACCENT FURNISH 252972 $129.99 T\n\n\n56 - EVERYDAY Q LIN 092626 $6.99 T"
        let result = ReceiptListParser.parseReceiptText(text)
        #expect(result.items.count == 2)
        #expect(result.skippedLines == [])
    }

    @Test("Handles duplicate lines as separate items")
    func duplicateLines() {
        let text = [
            "56 - EVERYDAY Q LIN 092626 $6.99 T",
            "56 - EVERYDAY Q LIN 092626 $6.99 T",
            "56 - EVERYDAY Q LIN 092626 $6.99 T",
        ].joined(separator: "\n")
        let result = ReceiptListParser.parseReceiptText(text)
        #expect(result.items.count == 3)
        #expect(result.items.allSatisfy { $0.name == "EVERYDAY Q LIN" })
    }

    @Test("Handles line without T suffix")
    func noTSuffix() {
        let result = ReceiptListParser.parseReceiptText("48 - WALL ART 323272 $45.00")
        #expect(result.items == [
            ReceiptListParser.ParsedReceiptItem(name: "WALL ART", sku: "323272", priceCents: 4500),
        ])
    }

    @Test("Handles price without dollar sign")
    func noDollarSign() {
        let result = ReceiptListParser.parseReceiptText("48 - WALL ART 323272 45.00 T")
        #expect(result.items == [
            ReceiptListParser.ParsedReceiptItem(name: "WALL ART", sku: "323272", priceCents: 4500),
        ])
    }

    @Test("Handles price with comma (e.g. $1,299.99)")
    func priceWithComma() {
        let result = ReceiptListParser.parseReceiptText("45 - FLORALS 924460 $1,299.99 T")
        #expect(result.items == [
            ReceiptListParser.ParsedReceiptItem(name: "FLORALS", sku: "924460", priceCents: 129999),
        ])
    }

    @Test("Collects unparseable lines into skippedLines")
    func unparseableLines() {
        let text = [
            "53 - ACCENT FURNISH 252972 $129.99 T",
            "SUBTOTAL: $500.00",
            "TAX: $41.25",
            "56 - EVERYDAY Q LIN 092626 $6.99 T",
        ].joined(separator: "\n")
        let result = ReceiptListParser.parseReceiptText(text)
        #expect(result.items.count == 2)
        #expect(result.skippedLines == ["SUBTOTAL: $500.00", "TAX: $41.25"])
    }

    @Test("Returns empty arrays for empty input")
    func emptyInput() {
        let result = ReceiptListParser.parseReceiptText("")
        #expect(result == ReceiptListParser.ReceiptParseResult(items: [], skippedLines: []))
    }

    @Test("Returns empty arrays for whitespace-only input")
    func whitespaceOnly() {
        let result = ReceiptListParser.parseReceiptText("   \n\n  \n  ")
        #expect(result == ReceiptListParser.ReceiptParseResult(items: [], skippedLines: []))
    }

    @Test("Trims leading/trailing whitespace from lines")
    func whitespaceTrimed() {
        let result = ReceiptListParser.parseReceiptText("  53 - ACCENT FURNISH 252972 $129.99 T  ")
        #expect(result.items == [
            ReceiptListParser.ParsedReceiptItem(name: "ACCENT FURNISH", sku: "252972", priceCents: 12999),
        ])
    }

    @Test("Handles the full example receipt from spec")
    func fullReceipt() {
        let text = """
        53 - ACCENT FURNISH 252972 $129.99 T
        56 - EVERYDAY Q LIN 092626 $6.99 T
        56 - EVERYDAY Q LIN 092626 $6.99 T
        56 - EVERYDAY Q LIN 092626 $6.99 T
        53 - ACCENT FURNISH 256577 $129.99 T
        11 - BATH SHOP 278078 $129.99 T
        56 - EVERYDAY Q LIN 092626 $6.99 T
        56 - EVERYDAY Q LIN 092626 $6.99 T
        56 - EVERYDAY Q LIN 092626 $6.99 T
        33 - DECORATIVE ACC 348059 $49.99 T
        33 - DECORATIVE ACC 348059 $49.99 T
        """
        let result = ReceiptListParser.parseReceiptText(text)
        #expect(result.items.count == 11)
        #expect(result.skippedLines == [])
        #expect(result.items[0] == ReceiptListParser.ParsedReceiptItem(name: "ACCENT FURNISH", sku: "252972", priceCents: 12999))
        #expect(result.items[10] == ReceiptListParser.ParsedReceiptItem(name: "DECORATIVE ACC", sku: "348059", priceCents: 4999))
    }

    @Test("Handles multi-section receipt with blank line separators")
    func multiSection() {
        let text = """
        63 - ALT/HANGING LI 522327 $29.99 T
        45 - FLORALS 904667 $19.99 T

        48 - WALL ART 330069 $29.99 T
        33 - DECORATIVE ACC 377616 $19.99 T
        """
        let result = ReceiptListParser.parseReceiptText(text)
        #expect(result.items.count == 4)
        #expect(result.skippedLines == [])
    }

    @Test("Handles SKU with leading zeros")
    func skuLeadingZeros() {
        let result = ReceiptListParser.parseReceiptText("56 - EVERYDAY Q LIN 092626 $6.99 T")
        #expect(result.items[0].sku == "092626")
    }
}
