import Foundation

/// Destination sale review only; never use this to calculate a return or credit.
/// The owning sale command persists the result atomically with placement/charge.
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
        try resolve(projectPrice: projectPrice.amount(), purchaseCost: purchaseCost.amount(), currency: currency)
    }

    /// Preserve markup and raise a missing/below-cost project price to cost.
    /// Missing or nonpositive values are not permission to invent a free sale.
    private static func resolve(projectPrice: Money?, purchaseCost: Money?, currency: CurrencyCode) throws -> Money {
        guard projectPrice.map({ $0.currency == currency }) ?? true,
              purchaseCost.map({ $0.currency == currency }) ?? true else {
            throw Failure.currencyMismatch
        }
        let amount = max(0, projectPrice?.minorUnits ?? 0, purchaseCost?.minorUnits ?? 0)
        guard amount > 0 else { throw Failure.priceRequired }
        return Money(minorUnits: amount, currency: currency)
    }
}
