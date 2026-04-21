import Foundation

/// Pure calculations for the project billing summary card.
///
/// v2 derivation — paid-state lives only on the invoice. Membership in a
/// non-voided invoice drives Invoiced; membership in a paid invoice drives
/// Collected.
///
/// Definitions:
/// - **Total Spent** — sum of all item `purchasePriceCents` + all non-itemized
///   transaction `amountCents` for the project.
/// - **Invoiced** — same sum restricted to items/transactions referenced by
///   any non-voided invoice for the project.
/// - **Collected** — same sum restricted to items/transactions on a **paid**
///   invoice for the project.
/// - **Outstanding** — Total Spent − Collected.
///
/// A transaction counts as "non-itemized" (and therefore directly billable)
/// when it has no child items. Itemized transactions are excluded so their
/// amounts are not double-counted; their items are summed instead.
enum BillingSummaryCalculations {

    struct Summary: Equatable {
        var totalSpentCents: Int
        var invoicedCents: Int
        var collectedCents: Int
        var outstandingCents: Int
    }

    static func summarize(
        projectId: String?,
        items: [Item],
        transactions: [Transaction],
        invoices: [Invoice]
    ) -> Summary {
        // Collect the sets of ids on any non-voided invoice and on paid
        // invoices, scoped to the project when known.
        var onAnyInvoiceItems: Set<String> = []
        var onAnyInvoiceTxs: Set<String> = []
        var paidItems: Set<String> = []
        var paidTxs: Set<String> = []

        for invoice in invoices {
            if let pid = projectId, invoice.projectId != pid { continue }
            guard invoice.status != .voided else { continue }
            let itemIds = invoice.itemIds ?? []
            let txIds = invoice.transactionIds ?? []
            onAnyInvoiceItems.formUnion(itemIds)
            onAnyInvoiceTxs.formUnion(txIds)
            if invoice.status == .paid {
                paidItems.formUnion(itemIds)
                paidTxs.formUnion(txIds)
            }
        }

        var totalSpent = 0
        var invoiced = 0
        var collected = 0

        for item in items {
            let cents = item.purchasePriceCents ?? 0
            totalSpent += cents
            guard let id = item.id else { continue }
            if onAnyInvoiceItems.contains(id) { invoiced += cents }
            if paidItems.contains(id) { collected += cents }
        }

        for tx in transactions where isNonItemized(tx) {
            let cents = tx.amountCents ?? 0
            totalSpent += cents
            guard let id = tx.id else { continue }
            if onAnyInvoiceTxs.contains(id) { invoiced += cents }
            if paidTxs.contains(id) { collected += cents }
        }

        return Summary(
            totalSpentCents: totalSpent,
            invoicedCents: invoiced,
            collectedCents: collected,
            outstandingCents: totalSpent - collected
        )
    }

    /// A transaction is treated as a directly-billable line when it has no
    /// child items. Itemized transactions derive their billing state from
    /// their items.
    static func isNonItemized(_ tx: Transaction) -> Bool {
        (tx.itemIds ?? []).isEmpty
    }
}
