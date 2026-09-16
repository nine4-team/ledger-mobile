import Foundation

/// Shared Transaction/Expense receipt evidence; callers establish authorization
/// and completeness before formatting. CSV escaping belongs to the serializer.
public enum ReceiptLineExport {
    public static func readable(_ lines: [NonItemReceiptLine]) -> String {
        lines.map { line in
            let quantity = line.quantity.map { "; quantity=\($0)" } ?? ""
            return "\(line.id.rawValue): \(line.description.rawValue) [\(line.effect.rawValue); \(line.magnitude.minorUnits) \(line.magnitude.currency.rawValue) minor units\(quantity)]"
        }.joined(separator: "\n")
    }

    public static func structured(_ lines: [NonItemReceiptLine]) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(lines.map(Line.init)), as: UTF8.self)
    }

    // Decimal strings preserve all Int64 digits in spreadsheet JSON consumers.
    private struct Line: Encodable {
        let id, description, amountMinorUnits, currency, effect: String
        let quantity: String?
        init(_ line: NonItemReceiptLine) {
            id = line.id.rawValue; description = line.description.rawValue
            amountMinorUnits = String(line.magnitude.minorUnits)
            currency = line.magnitude.currency.rawValue; effect = line.effect.rawValue
            quantity = line.quantity.map(String.init)
        }
    }
}
