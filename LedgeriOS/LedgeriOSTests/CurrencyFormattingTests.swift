import Foundation
import Testing
@testable import LedgeriOS

@Suite("CurrencyFormatting")
struct CurrencyFormattingTests {

    // MARK: - formatCents

    @Test("Zero cents formats as $0")
    func formatCentsZero() {
        #expect(CurrencyFormatting.formatCents(0) == "$0")
    }

    @Test("Positive whole dollar amount")
    func formatCentsWholeDollar() {
        #expect(CurrencyFormatting.formatCents(15000) == "$150")
    }

    @Test("Truncates partial cents to whole dollars")
    func formatCentsTruncates() {
        #expect(CurrencyFormatting.formatCents(15099) == "$150")
    }

    @Test("Negative amount")
    func formatCentsNegative() {
        #expect(CurrencyFormatting.formatCents(-5000) == "$-50")
    }

    // MARK: - formatCentsWithDecimals

    @Test("Formats with two decimal places")
    func formatDecimalsBasic() {
        #expect(CurrencyFormatting.formatCentsWithDecimals(15099) == "$150.99")
    }

    @Test("Zero with decimals shows $0.00")
    func formatDecimalsZero() {
        #expect(CurrencyFormatting.formatCentsWithDecimals(0) == "$0.00")
    }

    @Test("Single cent shows $0.01")
    func formatDecimalsSingleCent() {
        #expect(CurrencyFormatting.formatCentsWithDecimals(1) == "$0.01")
    }

    @Test("Exact dollars show .00")
    func formatDecimalsExactDollar() {
        #expect(CurrencyFormatting.formatCentsWithDecimals(10000) == "$100.00")
    }

    // MARK: - formatCentsCompact

    @Test("Under $1K falls back to whole dollars")
    func compactSmallAmount() {
        #expect(CurrencyFormatting.formatCentsCompact(50000) == "$500")
    }

    @Test("Exactly $1K shows $1K")
    func compactExactThousand() {
        #expect(CurrencyFormatting.formatCentsCompact(100_000) == "$1K")
    }

    @Test("$1,500 shows $1.5K")
    func compactFractionalThousand() {
        #expect(CurrencyFormatting.formatCentsCompact(150_000) == "$1.5K")
    }

    @Test("$15,000 shows $15K")
    func compactLargeThousand() {
        #expect(CurrencyFormatting.formatCentsCompact(1_500_000) == "$15K")
    }

    @Test("$1,000,000 shows $1M")
    func compactExactMillion() {
        #expect(CurrencyFormatting.formatCentsCompact(100_000_000) == "$1M")
    }

    @Test("$1,500,000 shows $1.5M")
    func compactFractionalMillion() {
        #expect(CurrencyFormatting.formatCentsCompact(150_000_000) == "$1.5M")
    }

    @Test("Negative large amount shows -$1.5K")
    func compactNegative() {
        #expect(CurrencyFormatting.formatCentsCompact(-150_000) == "-$1.5K")
    }

    @Test("Zero compact shows $0")
    func compactZero() {
        #expect(CurrencyFormatting.formatCentsCompact(0) == "$0")
    }
}
