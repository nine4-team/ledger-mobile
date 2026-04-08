import Foundation

/// Pure calculations for the project billing summary card.
///
/// Definitions:
/// - **Total Spent** — sum of all item `purchasePriceCents` + all non-itemized transaction `amountCents`.
/// - **Invoiced** — same sum, restricted to billingStatus ∈ {invoiced, paid}.
/// - **Collected** — same sum, restricted to billingStatus == paid.
/// - **Outstanding** — Total Spent − Collected.
///
/// A transaction counts as "non-itemized" (and therefore directly billable) when it has no
/// child items — i.e. `itemIds` is nil or empty. Itemized transactions are excluded so their
/// amounts are not double-counted; their items are summed instead.
enum BillingSummaryCalculations {

    struct Summary: Equatable {
        var totalSpentCents: Int
        var invoicedCents: Int
        var collectedCents: Int
        var outstandingCents: Int
    }

    static func summarize(items: [Item], transactions: [Transaction]) -> Summary {
        var totalSpent = 0
        var invoiced = 0
        var collected = 0

        for item in items {
            let cents = item.purchasePriceCents ?? 0
            totalSpent += cents
            switch item.billingStatus {
            case .invoiced:
                invoiced += cents
            case .paid:
                invoiced += cents
                collected += cents
            case .unbilled, .none:
                break
            }
        }

        for tx in transactions where isNonItemized(tx) {
            let cents = tx.amountCents ?? 0
            totalSpent += cents
            switch tx.billingStatus {
            case .invoiced:
                invoiced += cents
            case .paid:
                invoiced += cents
                collected += cents
            case .unbilled, .none:
                break
            }
        }

        return Summary(
            totalSpentCents: totalSpent,
            invoicedCents: invoiced,
            collectedCents: collected,
            outstandingCents: totalSpent - collected
        )
    }

    /// A transaction is treated as a directly-billable line when it has no child items.
    /// Itemized transactions derive their billing state from their items.
    static func isNonItemized(_ tx: Transaction) -> Bool {
        (tx.itemIds ?? []).isEmpty
    }
}
