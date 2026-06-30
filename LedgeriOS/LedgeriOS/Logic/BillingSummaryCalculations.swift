import Foundation

/// Pure calculations for the project billing summary card.
///
/// Current derivation — invoices are demand, transactions are money movement.
///
/// Definitions:
/// - **Total Spent** — sum of all item `purchasePriceCents` + all non-itemized
///   transaction `amountCents` for the project.
/// - **Invoiced** — sent or paid invoice demand, including manual New Charge
///   lines.
/// - **Collected** — settlement transactions linked back to invoices.
/// - **Outstanding** — sent invoice demand minus linked settlements.
///
/// A transaction counts as "non-itemized" (and therefore directly billable)
/// when its linked budget category is not itemized. Empty `itemIds` is not
/// proof that a transaction is non-itemized; itemized rows can have missing
/// child item data that needs repair rather than invoice-as-service handling.
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
        invoices: [Invoice],
        budgetCategories: [String: BudgetCategory] = [:]
    ) -> Summary {
        let scopedItems = items.filter { item in
            guard let pid = projectId else { return true }
            return item.projectId == pid
        }
        let scopedTransactions = transactions.filter { tx in
            guard let pid = projectId else { return true }
            return tx.projectId == pid
        }

        let itemAmounts = Dictionary(uniqueKeysWithValues: scopedItems.compactMap { item -> (String, Int)? in
            guard let id = item.id else { return nil }
            return (id, item.purchasePriceCents ?? 0)
        })
        let nonItemizedTxAmounts = Dictionary(uniqueKeysWithValues: scopedTransactions.compactMap { tx -> (String, Int)? in
            guard let id = tx.id, isNonItemized(tx, budgetCategories: budgetCategories) else { return nil }
            return (id, tx.amountCents ?? 0)
        })

        let settlementByInvoiceId = Dictionary(grouping: scopedTransactions.compactMap { tx -> (String, Int)? in
            guard let invoiceId = tx.settlementInvoiceId else { return nil }
            return (invoiceId, tx.amountCents ?? 0)
        }, by: { $0.0 })
            .mapValues { entries in entries.reduce(0) { $0 + $1.1 } }

        var totalSpent = scopedItems.reduce(0) { $0 + ($1.purchasePriceCents ?? 0) }
        var invoiced = 0
        var collected = settlementByInvoiceId.values.reduce(0, +)
        var outstanding = 0

        for tx in scopedTransactions where isNonItemized(tx, budgetCategories: budgetCategories) {
            totalSpent += tx.amountCents ?? 0
        }

        for invoice in invoices {
            if let pid = projectId, invoice.projectId != pid { continue }
            guard invoice.status != .voided else { continue }

            let demand = demandCents(
                for: invoice,
                itemAmounts: itemAmounts,
                transactionAmounts: nonItemizedTxAmounts
            )

            switch invoice.status ?? .draft {
            case .draft, .voided:
                break
            case .sent:
                invoiced += demand
                let settled = invoice.id.flatMap { settlementByInvoiceId[$0] } ?? 0
                outstanding += max(demand - settled, 0)
            case .paid:
                invoiced += demand
                // Historical paid invoices may predate settlement transactions.
                if let invoiceId = invoice.id, settlementByInvoiceId[invoiceId] != nil {
                    break
                }
                collected += demand
            }
        }

        return Summary(
            totalSpentCents: totalSpent,
            invoicedCents: invoiced,
            collectedCents: collected,
            outstandingCents: outstanding
        )
    }

    /// A transaction is treated as a directly-billable line when its category
    /// is non-itemized. If category context is unavailable, falls back to the
    /// legacy itemIds heuristic for read compatibility.
    static func isNonItemized(
        _ tx: Transaction,
        budgetCategories: [String: BudgetCategory] = [:]
    ) -> Bool {
        guard tx.settlementInvoiceId == nil,
              tx.transactionType != .paymentToBusiness else {
            return false
        }

        if let category = tx.budgetCategoryId.flatMap({ budgetCategories[$0] }) {
            return !category.isItemsCategory
        }

        return (tx.itemIds ?? []).isEmpty
    }

    private static func demandCents(
        for invoice: Invoice,
        itemAmounts: [String: Int],
        transactionAmounts: [String: Int]
    ) -> Int {
        if let lines = invoice.lines {
            return InvoiceLineCalculations.netTotalCents(lines: lines)
        }
        if let total = invoice.totalCents {
            return total
        }

        let itemTotal = (invoice.itemIds ?? []).reduce(0) { $0 + (itemAmounts[$1] ?? 0) }
        let txTotal = (invoice.transactionIds ?? []).reduce(0) { $0 + (transactionAmounts[$1] ?? 0) }
        return itemTotal + txTotal
    }
}
