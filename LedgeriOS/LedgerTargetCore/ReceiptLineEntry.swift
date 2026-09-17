import Foundation

/// Shared editable receipt wording and amounts; parent commands own authorization
/// and accounting locks. Codable keys retain existing saved Expense drafts.
public struct ReceiptLineEntry: Codable, Equatable, Sendable, Identifiable {
    public enum Failure: Error { case invalidQuantity }
    public let id: UUID
    public var sourceLineId: String?
    public var description = ""
    public var amountText = ""
    public var effect: NonItemReceiptLineEffect = .increase
    public var quantityText = ""
    public init(id: UUID = UUID()) { self.id = id }

    public init(line: NonItemReceiptLine, id: UUID = UUID()) {
        self.id = id
        sourceLineId = line.id.rawValue
        description = line.description.rawValue
        let units = line.magnitude.minorUnits
        amountText = "\(units / 100).\(String(format: "%02lld", units % 100))"
        effect = line.effect
        quantityText = line.quantity.map(String.init) ?? ""
    }

    public func receiptLine(currency: CurrencyCode) throws -> NonItemReceiptLine {
        let text = quantityText.trimmingCharacters(in: .whitespacesAndNewlines)
        let quantity: Int64?
        if text.isEmpty { quantity = nil }
        else {
            let digits = text.hasPrefix("-") ? text.dropFirst() : text[...]
            guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Int64(text) else { throw Failure.invalidQuantity }
            quantity = value
        }
        return try .init(id: .init(validating: sourceLineId ?? id.uuidString.lowercased()),
            description: .init(validating: description),
            magnitude: Money.parsePositiveEntry(amountText, currency: currency),
            effect: effect, quantity: quantity)
    }
}
