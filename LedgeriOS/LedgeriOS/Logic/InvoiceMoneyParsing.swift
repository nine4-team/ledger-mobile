import Foundation

/// Money parsing utilities for invoice text extraction.
/// Port of `src/utils/money.ts` — normalizes money strings from PDF text into standard decimal format.
enum InvoiceMoneyParsing {

    /// Normalizes a money string to a two-decimal-place string.
    /// Handles `$`, commas, parentheses (negative), minus signs.
    /// "$12.34" → "12.34", "($12.34)" → "-12.34", "1,234.56" → "1234.56"
    static func normalizeMoneyToTwoDecimalString(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Parentheses or minus sign indicate negative
        let isNegative = (trimmed.hasPrefix("(") && trimmed.hasSuffix(")")) || trimmed.contains("-")

        // Remove currency symbols, whitespace, parentheses — keep digits, dot, comma, minus
        let cleaned = trimmed
            .replacingOccurrences(of: "[^\\d.,-]", with: "", options: .regularExpression)
            .replacingOccurrences(of: ",", with: "")

        guard let num = Double(cleaned), num.isFinite else { return nil }

        let final = isNegative ? -abs(num) : num
        return String(format: "%.2f", final)
    }

    /// Parses a money string to a Double.
    /// "12.34" → 12.34, "$1,234.56" → 1234.56
    static func parseMoneyToNumber(_ input: String?) -> Double? {
        guard let input, !input.isEmpty else { return nil }
        guard let normalized = normalizeMoneyToTwoDecimalString(input) else { return nil }
        guard let n = Double(normalized), n.isFinite else { return nil }
        return n
    }

    /// Parses a dollar string to cents. "12.34" → 1234, "$1,234.56" → 123456
    static func parseCentsFromDollarString(_ input: String?) -> Int? {
        guard let dollars = parseMoneyToNumber(input) else { return nil }
        return Int(round(dollars * 100))
    }

    /// Returns absolute value of a money string. "-12.34" → "12.34"
    static func absMoneyString(_ input: String?) -> String? {
        guard let n = parseMoneyToNumber(input) else { return nil }
        return String(format: "%.2f", abs(n))
    }
}
