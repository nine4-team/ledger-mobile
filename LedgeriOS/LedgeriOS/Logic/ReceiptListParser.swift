import Foundation

/// Parses itemized receipt text (e.g. from HomeGoods / TJ Maxx receipts)
/// into structured item data ready for creation.
/// Port of `src/utils/receiptListParser.ts`.
///
/// Expected line format:
///   DEPT - DESCRIPTION SKU $PRICE T
///   e.g. "53 - ACCENT FURNISH 252972 $129.99 T"
enum ReceiptListParser {

    struct ParsedReceiptItem: Equatable {
        let name: String
        let sku: String
        let priceCents: Int
    }

    struct ReceiptParseResult: Equatable {
        let items: [ParsedReceiptItem]
        let skippedLines: [String]
    }

    /// Regex matching receipt line format:
    ///   ^\d+\s*-\s*(.+?)\s+(\d{4,})\s+\$?([\d,]+\.\d{2})\s*T?\s*$
    private static let lineRegex = try! NSRegularExpression(
        pattern: #"^\d+\s*-\s*(.+?)\s+(\d{4,})\s+\$?([\d,]+\.\d{2})\s*T?\s*$"#
    )

    /// Parses free-form receipt text into structured items.
    /// Blank lines are skipped silently.
    /// Non-matching lines are collected in `skippedLines`.
    static func parseReceiptText(_ text: String) -> ReceiptParseResult {
        var items: [ParsedReceiptItem] = []
        var skippedLines: [String] = []

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = lineRegex.firstMatch(in: line, range: range),
               match.numberOfRanges == 4,
               let nameRange = Range(match.range(at: 1), in: line),
               let skuRange = Range(match.range(at: 2), in: line),
               let priceRange = Range(match.range(at: 3), in: line) {

                let name = String(line[nameRange]).trimmingCharacters(in: .whitespaces)
                let sku = String(line[skuRange])
                let priceCents = priceToCents(String(line[priceRange]))

                items.append(ParsedReceiptItem(name: name, sku: sku, priceCents: priceCents))
            } else {
                skippedLines.append(line)
            }
        }

        return ReceiptParseResult(items: items, skippedLines: skippedLines)
    }

    /// Converts a price string (e.g. "129.99" or "1,299.99") to cents.
    private static func priceToCents(_ priceStr: String) -> Int {
        let cleaned = priceStr.replacingOccurrences(of: ",", with: "")
        guard let value = Double(cleaned) else { return 0 }
        return Int((value * 100).rounded())
    }
}
