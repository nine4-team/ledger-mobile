import Foundation
import Testing
@testable import LedgeriOS

@Suite("Receipt List Parser Tests")
struct ReceiptListParserTests {

    // MARK: - Standard line format

    @Test("Standard line parses name, sku, and price")
    func standardLineFormat() {
        let input = "53 - ACCENT FURNISH 252972 $129.99 T"
        let result = ReceiptListParser.parseReceiptText(input)
        #expect(result.items.count == 1)
        #expect(result.items[0].name == "ACCENT FURNISH")
        #expect(result.items[0].sku == "252972")
        #expect(result.items[0].priceCents == 12999)
        #expect(result.skippedLines.isEmpty)
    }

    @Test("Multiple valid lines all parsed")
    func multipleValidLines() {
        let input = """
        12 - TABLE LAMP 100123 $45.00 T
        34 - WALL ART FRAME 200456 $89.99 T
        """
        let result = ReceiptListParser.parseReceiptText(input)
        #expect(result.items.count == 2)
        #expect(result.items[0].name == "TABLE LAMP")
        #expect(result.items[0].priceCents == 4500)
        #expect(result.items[1].name == "WALL ART FRAME")
        #expect(result.items[1].priceCents == 8999)
    }

    // MARK: - Price with comma separators

    @Test("Price with comma separator parses correctly")
    func priceWithComma() {
        let input = "10 - LARGE SOFA 999001 $1,299.00 T"
        let result = ReceiptListParser.parseReceiptText(input)
        #expect(result.items.count == 1)
        #expect(result.items[0].priceCents == 129900)
    }

    @Test("Price with multiple commas parses correctly")
    func priceWithMultipleCommas() {
        let input = "01 - DINING TABLE SET 888001 $2,499.99 T"
        let result = ReceiptListParser.parseReceiptText(input)
        #expect(result.items.count == 1)
        // Double floating-point truncation: Int(2499.99 * 100) = 249998
        #expect(result.items[0].priceCents == 249998)
    }

    // MARK: - Lines without tax flag

    @Test("Line without T tax flag still parses")
    func lineWithoutTaxFlag() {
        let input = "53 - ACCENT FURNISH 252972 $129.99"
        let result = ReceiptListParser.parseReceiptText(input)
        #expect(result.items.count == 1)
        #expect(result.items[0].name == "ACCENT FURNISH")
        #expect(result.items[0].priceCents == 12999)
        #expect(result.skippedLines.isEmpty)
    }

    // MARK: - Empty lines skipped

    @Test("Empty lines are skipped silently")
    func emptyLinesSkipped() {
        let input = "\n53 - ACCENT FURNISH 252972 $129.99 T\n\n"
        let result = ReceiptListParser.parseReceiptText(input)
        #expect(result.items.count == 1)
        #expect(result.skippedLines.isEmpty)
    }

    @Test("Whitespace-only lines are skipped silently")
    func whitespaceOnlyLinesSkipped() {
        let input = "   \n53 - TABLE LAMP 100123 $45.00 T\n   "
        let result = ReceiptListParser.parseReceiptText(input)
        #expect(result.items.count == 1)
        #expect(result.skippedLines.isEmpty)
    }

    // MARK: - Invalid lines go to skippedLines

    @Test("Lines without dept-dash format go to skippedLines")
    func invalidLineSkipped() {
        let input = "This is not a valid receipt line"
        let result = ReceiptListParser.parseReceiptText(input)
        #expect(result.items.isEmpty)
        #expect(result.skippedLines.count == 1)
        #expect(result.skippedLines[0] == "This is not a valid receipt line")
    }

    @Test("Header and subtotal lines go to skippedLines")
    func headerAndTotalLinesSkipped() {
        let input = """
        HOMEGOODS STORE
        53 - ACCENT FURNISH 252972 $129.99 T
        SUBTOTAL: $129.99
        TAX: $10.40
        TOTAL: $140.39
        """
        let result = ReceiptListParser.parseReceiptText(input)
        #expect(result.items.count == 1)
        #expect(result.skippedLines.count == 4)
        #expect(result.skippedLines.contains("HOMEGOODS STORE"))
        #expect(result.skippedLines.contains("SUBTOTAL: $129.99"))
    }

    @Test("Mix of valid and invalid lines")
    func mixedLines() {
        let input = """
        12 - TABLE LAMP 100123 $45.00 T
        INVALID LINE
        34 - WALL ART 200456 $89.99 T
        ANOTHER INVALID
        """
        let result = ReceiptListParser.parseReceiptText(input)
        #expect(result.items.count == 2)
        #expect(result.skippedLines.count == 2)
        #expect(result.skippedLines[0] == "INVALID LINE")
        #expect(result.skippedLines[1] == "ANOTHER INVALID")
    }

    // MARK: - Empty input returns empty result

    @Test("Empty string returns empty result")
    func emptyInputReturnsEmpty() {
        let result = ReceiptListParser.parseReceiptText("")
        #expect(result.items.isEmpty)
        #expect(result.skippedLines.isEmpty)
    }

    @Test("Newlines-only input returns empty result")
    func newlinesOnlyReturnsEmpty() {
        let result = ReceiptListParser.parseReceiptText("\n\n\n")
        #expect(result.items.isEmpty)
        #expect(result.skippedLines.isEmpty)
    }

    // MARK: - SKU extraction

    @Test("Short SKU (4 digits) is captured")
    func shortSkuFourDigits() {
        let input = "5 - SMALL ITEM 1234 $9.99 T"
        let result = ReceiptListParser.parseReceiptText(input)
        #expect(result.items.count == 1)
        #expect(result.items[0].sku == "1234")
    }

    @Test("Long SKU (8 digits) is captured")
    func longSkuEightDigits() {
        let input = "5 - BIG ITEM 12345678 $19.99 T"
        let result = ReceiptListParser.parseReceiptText(input)
        #expect(result.items.count == 1)
        #expect(result.items[0].sku == "12345678")
    }

    // MARK: - ParseResult equality

    @Test("ParseResult equality compares names, prices, and skipped lines")
    func parseResultEquality() {
        let input = "53 - ACCENT FURNISH 252972 $129.99 T"
        let r1 = ReceiptListParser.parseReceiptText(input)
        let r2 = ReceiptListParser.parseReceiptText(input)
        #expect(r1 == r2)
    }
}
