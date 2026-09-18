import Foundation

/// Atomic server/download projection; fractions remain exact across platforms.
public struct LiveItemAdjustmentOrder: Codable, Equatable, Sendable {
    public let totalMinorUnits: String
    public let adjustmentsMinorUnits: String
    public let differenceNumerator: String?
    public let differenceDenominator: String?
    public let isBalanced: Bool
    public let isProvisional: Bool
    public let items: [Item]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalMinorUnits = try c.decode(String.self, forKey: .totalMinorUnits)
        adjustmentsMinorUnits = try c.decode(String.self, forKey: .adjustmentsMinorUnits)
        differenceNumerator = try c.decodeIfPresent(String.self, forKey: .differenceNumerator)
        differenceDenominator = try c.decodeIfPresent(String.self, forKey: .differenceDenominator)
        isBalanced = try c.decode(Bool.self, forKey: .isBalanced)
        isProvisional = try c.decode(Bool.self, forKey: .isProvisional)
        items = try c.decode([Item].self, forKey: .items)
        guard let total = Int64(totalMinorUnits), String(total) == totalMinorUnits,
              let adjustments = Int64(adjustmentsMinorUnits), String(adjustments) == adjustmentsMinorUnits,
              Set(items.map(\.itemId)).count == items.count else { throw TransactionReceiptSnapshot.Failure.invalidEvidence }
        let result = LiveItemAdjustments.calculate(totalMinorUnits: total, adjustmentsMinorUnits: adjustments,
            inputs: items.map { .init(itemId: $0.itemId, numerator: $0.numerator, denominator: $0.denominator,
                requestedProjectPriceMinorUnits: $0.requestedProjectPriceMinorUnits.flatMap(Int64.init), issue: $0.issue) })
        guard result.differenceNumerator == differenceNumerator, result.differenceDenominator == differenceDenominator,
              result.isBalanced == isBalanced, result.isProvisional == isProvisional,
              zip(items, result.prices).allSatisfy({ wire, price in
                  wire.projectPriceMinorUnits == price.projectPriceMinorUnits.map(String.init)
                    && wire.unadjustedMinorUnits == price.unadjustedMinorUnits.map(String.init)
                    && wire.adjustmentsMinorUnits == price.adjustmentsMinorUnits.map(String.init)
                    && wire.issue == price.issue
              }) else { throw TransactionReceiptSnapshot.Failure.invalidEvidence }
    }

    private enum CodingKeys: String, CodingKey {
        case totalMinorUnits, adjustmentsMinorUnits, differenceNumerator, differenceDenominator, isBalanced, isProvisional, items
    }
    public struct Item: Codable, Equatable, Sendable {
        public let itemId: String
        public let numerator: String?
        public let denominator: String?
        public let requestedProjectPriceMinorUnits: String?
        public let unadjustedMinorUnits: String?
        public let adjustmentsMinorUnits: String?
        public let projectPriceMinorUnits: String?
        public let issue: LiveItemAdjustments.Issue?
    }

    public var difference: Decimal? {
        guard let n = differenceNumerator.flatMap({ Decimal(string: $0) }),
              let d = differenceDenominator.flatMap({ Decimal(string: $0) }), d > 0 else { return nil }
        return n / d
    }

    public var unadjustedSubtotal: Decimal? {
        guard let total = Decimal(string: totalMinorUnits), let adjustment = Decimal(string: adjustmentsMinorUnits),
              let difference else { return nil }
        return total - adjustment - difference
    }
}
