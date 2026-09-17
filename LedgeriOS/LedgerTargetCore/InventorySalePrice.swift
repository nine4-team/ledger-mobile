import Foundation

/// Project-price normalization for sale review and uncollected price edits;
/// never use this to calculate a return or credit. The owning command persists
/// the result atomically with the corresponding charge.
public enum InventorySalePrice {
    public enum Failure: Error, Equatable, Sendable {
        case currencyMismatch
        case priceRequired
        case evidenceUnavailable
    }

    /// Absence requires an authoritative, complete scoped read. Never map an
    /// empty partial local query to confirmedAbsent.
    public enum Evidence: Equatable, Sendable {
        case unavailable
        case confirmedAbsent
        case known(Money)

        fileprivate func amount() throws -> Money? {
            switch self {
            case .unavailable: throw Failure.evidenceUnavailable
            case .confirmedAbsent: return nil
            case .known(let value): return value
            }
        }
    }

    /// Exact two-decimal price entry used by Ledger's existing dollar form.
    /// Reject precision/overflow rather than truncating through Int or Double.
    public static func parseEntry(_ text: String, currency: CurrencyCode) throws -> Money {
        do { return try Money.parsePositiveEntry(text, currency: currency) }
        catch { throw Failure.priceRequired }
    }

    public static func review(projectPrice: Evidence, purchaseCost: Evidence,
                              currency: CurrencyCode) throws -> Money {
        guard let price = try reviewCurrentPrice(projectPrice: projectPrice, purchaseCost: purchaseCost,
                                                currency: currency), price.minorUnits > 0 else {
            throw Failure.priceRequired
        }
        return price
    }

    /// Current Inventory state can be explicitly zero or unset without creating
    /// a sale. Sale/charge callers continue to use `review`, which requires a
    /// positive result. Both paths share the same cost floor and evidence rules.
    public static func reviewCurrentPrice(projectPrice: Evidence, purchaseCost: Evidence,
                                          currency: CurrencyCode) throws -> Money? {
        let projectPrice = try projectPrice.amount()
        let purchaseCost = try purchaseCost.amount()
        guard projectPrice.map({ $0.currency == currency }) ?? true,
              purchaseCost.map({ $0.currency == currency }) ?? true else {
            throw Failure.currencyMismatch
        }
        let amount = max(0, projectPrice?.minorUnits ?? 0, purchaseCost?.minorUnits ?? 0)
        if projectPrice == nil && amount == 0 { return nil }
        return Money(minorUnits: amount, currency: currency)
    }
}
