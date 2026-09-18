import Foundation

/// A single downloaded calculation revision. Its current price, inputs and
/// header provenance travel together; no separate receipt-row join is needed.
public struct LiveItemPricingContext: Decodable, Equatable, Sendable {
    public let transactionId: TransactionID
    public let revision: Int64
    public let priceRevision: Int64
    public let total: Money
    public let adjustments: Money
    public let isProvisional: Bool
    public let itemId: ItemID
    public let unadjusted: Money?
    public let itemAdjustments: Money?
    public let projectPrice: Money?
    public let requestedProjectPrice: Money?
    public let issue: LiveItemAdjustments.Issue?

    public func preview(requested: Money) -> LiveItemAdjustments.Price? {
        guard requested.currency == total.currency else { return nil }
        // Retain the authoritative order-wide penny assignment for unchanged
        // input; a one-Item preview cannot reconstruct sibling residuals.
        if requested == projectPrice {
            return .init(itemId: itemId.rawValue, unadjustedMinorUnits: unadjusted?.minorUnits,
                adjustmentsMinorUnits: itemAdjustments?.minorUnits,
                projectPriceMinorUnits: projectPrice?.minorUnits, issue: issue)
        }
        return LiveItemAdjustments.calculate(totalMinorUnits: total.minorUnits,
            adjustmentsMinorUnits: adjustments.minorUnits,
            inputs: [.init(itemId: itemId.rawValue, requestedProjectPriceMinorUnits: requested.minorUnits,
                           totalMinorUnits: total.minorUnits, adjustmentsMinorUnits: adjustments.minorUnits)]).prices.first
    }

    public init(from decoder: Decoder) throws {
        let wire = try Wire(from: decoder)
        func integer(_ text: String, minimum: Int64 = .min) throws -> Int64 {
            guard let value = Int64(text), String(value) == text, value >= minimum else {
                throw EditUncollectedItemPriceCommand.Failure.invalidRevision
            }
            return value
        }
        let currency = try CurrencyCode(validating: wire.currency)
        func money(_ value: String?) throws -> Money? {
            try value.map { Money(minorUnits: try integer($0), currency: currency) }
        }
        transactionId = try .init(validating: wire.transactionId)
        itemId = try .init(validating: wire.price.itemId)
        revision = try integer(wire.revision, minimum: 1)
        priceRevision = try integer(wire.priceRevision, minimum: 0)
        total = try Money(minorUnits: integer(wire.totalMinorUnits), currency: currency)
        adjustments = try Money(minorUnits: integer(wire.adjustmentsMinorUnits), currency: currency)
        isProvisional = wire.isProvisional
        unadjusted = try money(wire.price.unadjustedMinorUnits)
        itemAdjustments = try money(wire.price.adjustmentsMinorUnits)
        projectPrice = try money(wire.price.projectPriceMinorUnits)
        requestedProjectPrice = try money(wire.price.requestedProjectPriceMinorUnits)
        issue = wire.price.issue
        guard revision < .max, priceRevision < .max,
              issue == nil || (itemAdjustments == nil && projectPrice == nil) else {
            throw EditUncollectedItemPriceCommand.Failure.invalidRevision
        }
    }

    private struct Wire: Decodable {
        let transactionId, revision, priceRevision, totalMinorUnits, adjustmentsMinorUnits, currency: String
        let isProvisional: Bool
        let price: Price
        struct Price: Decodable {
            let itemId: String
            let unadjustedMinorUnits, adjustmentsMinorUnits, projectPriceMinorUnits, requestedProjectPriceMinorUnits: String?
            let issue: LiveItemAdjustments.Issue?
        }
    }
}
