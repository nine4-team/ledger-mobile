import Foundation

/// Parses itemized receipt text (e.g. from HomeGoods / TJ Maxx receipts)
/// into structured item data ready for creation.
///
/// Expected line format:
///   DEPT - DESCRIPTION SKU $PRICE T
///   e.g. "53 - ACCENT FURNISH 252972 $129.99 T"
///
/// Ported from RN `receiptListParser.ts`.
enum ReceiptListParser {

    struct ParsedItem: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let sku: String
        let priceCents: Int
    }

    struct ParseResult: Equatable {
        let items: [ParsedItem]
        let skippedLines: [String]

        static func == (lhs: ParseResult, rhs: ParseResult) -> Bool {
            lhs.items.map(\.name) == rhs.items.map(\.name)
            && lhs.items.map(\.priceCents) == rhs.items.map(\.priceCents)
            && lhs.skippedLines == rhs.skippedLines
        }
    }

    /// Regex: dept-dash-description-sku-price-optional-tax-flag
    /// `^\d+\s*-\s*(.+?)\s+(\d{4,})\s+\$?([\d,]+\.\d{2})\s*T?\s*$`
    private static nonisolated(unsafe) let linePattern = /^\d+\s*-\s*(.+?)\s+(\d{4,})\s+\$?([\d,]+\.\d{2})\s*T?\s*$/

    static func parseReceiptText(_ text: String) -> ParseResult {
        var items: [ParsedItem] = []
        var skippedLines: [String] = []

        let lines = text.components(separatedBy: "\n")

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if let match = line.wholeMatch(of: linePattern) {
                let name = String(match.1).trimmingCharacters(in: .whitespaces)
                let sku = String(match.2)
                let priceStr = String(match.3).replacingOccurrences(of: ",", with: "")
                let priceCents = Int((Double(priceStr) ?? 0) * 100)

                items.append(ParsedItem(name: name, sku: sku, priceCents: priceCents))
            } else {
                skippedLines.append(line)
            }
        }

        return ParseResult(items: items, skippedLines: skippedLines)
    }
}
