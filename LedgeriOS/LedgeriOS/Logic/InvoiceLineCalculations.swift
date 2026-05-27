import Foundation

/// Pure calculations for the v2 invoicing model: sign derivation for a source
/// (item or transaction), and the three-way billable-membership split that
/// drives the To Invoice / Invoiced / Paid pipeline in the Billing subtab.
///
/// See `docs/specs/billing-invoicing.md` for the rules.
enum InvoiceLineCalculations {

    // MARK: - Sign derivation

    /// Items in a project represent goods purchased for the client, so every
    /// project item is a charge. Returned items that were on a paid invoice
    /// generate a separate credit *transaction* (see `InventoryOperationsService`);
    /// the item itself isn't signed as a credit.
    static func sign(for item: Item) -> InvoiceLineSign {
        .charge
    }

    /// Transaction sign is driven by reimbursement direction (or, for sale
    /// transactions without an explicit direction, shape).
    ///
    /// Returns nil for transactions that aren't billable — reassignments,
    /// inventory-internal moves, canceled, or any transaction whose direction
    /// can't be inferred.
    static func sign(for tx: Transaction) -> InvoiceLineSign? {
        guard tx.status != .canceled else { return nil }
        guard tx.settlementInvoiceId == nil else { return nil }
        guard let direction = ReportAggregationCalculations.reimbursementDirection(for: tx) else {
            return nil
        }
        switch direction {
        case .owedToCompany: return .charge
        case .owedToClient: return .credit
        }
    }

    /// Amount to bill for an item — project price if set, otherwise purchase price.
    static func amountCents(for item: Item) -> Int {
        if let p = item.projectPriceCents, p > 0 { return p }
        return item.purchasePriceCents ?? 0
    }

    /// Build a signed InvoiceLine from an item. Always a charge.
    static func makeLine(item: Item) -> InvoiceLine? {
        guard let id = item.id else { return nil }
        return InvoiceLine(
            sourceType: .item,
            sourceId: id,
            amountCents: amountCents(for: item),
            sign: sign(for: item),
            snapshotName: item.displayName.isEmpty ? nil : item.displayName
        )
    }

    /// Build a signed InvoiceLine from a transaction. Returns nil for
    /// non-billable transactions.
    static func makeLine(transaction tx: Transaction) -> InvoiceLine? {
        guard let id = tx.id else { return nil }
        guard let sign = sign(for: tx) else { return nil }
        return InvoiceLine(
            sourceType: .transaction,
            sourceId: id,
            amountCents: tx.amountCents ?? 0,
            sign: sign,
            snapshotName: tx.source ?? tx.notes
        )
    }

    // MARK: - Billable membership

    /// The three disjoint buckets for a project's billable activity, plus the
    /// "on a draft" set which is excluded from all three tabs but still excluded
    /// from the Create Invoice picker.
    struct BillableMembership {
        /// Billable and not on any invoice for this project.
        var toInvoiceItemIds: Set<String>
        var toInvoiceTransactionIds: Set<String>
        /// On a sent-but-unpaid invoice for this project.
        var invoicedItemIds: Set<String>
        var invoicedTransactionIds: Set<String>
        /// On a paid invoice for this project.
        var paidItemIds: Set<String>
        var paidTransactionIds: Set<String>
        /// On a draft invoice for this project. Not shown in any of the three
        /// tabs, but excluded from the picker when creating a *different* draft.
        var draftItemIds: Set<String>
        var draftTransactionIds: Set<String>

        /// Union of draft + sent + paid — every source already claimed by some
        /// non-voided invoice. Used to filter the To Invoice pool.
        var onAnyInvoiceItemIds: Set<String> {
            draftItemIds.union(invoicedItemIds).union(paidItemIds)
        }
        var onAnyInvoiceTransactionIds: Set<String> {
            draftTransactionIds.union(invoicedTransactionIds).union(paidTransactionIds)
        }
    }

    /// Compute the membership buckets for a project.
    ///
    /// - Parameters:
    ///   - projectId: the project we're computing for.
    ///   - items: candidate items (typically `projectContext.items`).
    ///   - transactions: candidate transactions (typically `projectContext.transactions`).
    ///   - invoices: all invoices for the account (typically `accountContext.allInvoices`).
    ///   - excludingInvoiceId: when a draft is being edited in the picker,
    ///     exclude its own membership so the editing invoice's current selection
    ///     is still pickable. Pass nil when not editing.
    static func billableMembership(
        projectId: String,
        items: [Item],
        transactions: [Transaction],
        invoices: [Invoice],
        excludingInvoiceId: String? = nil
    ) -> BillableMembership {
        var draftItems: Set<String> = []
        var draftTx: Set<String> = []
        var invoicedItems: Set<String> = []
        var invoicedTx: Set<String> = []
        var paidItems: Set<String> = []
        var paidTx: Set<String> = []

        for invoice in invoices {
            guard invoice.projectId == projectId else { continue }
            guard invoice.status != .voided else { continue }
            if let excluded = excludingInvoiceId, invoice.id == excluded { continue }

            let itemIds = invoice.itemIds ?? []
            let txIds = invoice.transactionIds ?? []

            switch invoice.status ?? .draft {
            case .draft:
                draftItems.formUnion(itemIds)
                draftTx.formUnion(txIds)
            case .sent:
                invoicedItems.formUnion(itemIds)
                invoicedTx.formUnion(txIds)
            case .paid:
                paidItems.formUnion(itemIds)
                paidTx.formUnion(txIds)
            case .voided:
                break
            }
        }

        let onAnyItems = draftItems.union(invoicedItems).union(paidItems)
        let onAnyTx = draftTx.union(invoicedTx).union(paidTx)

        var toInvoiceItems: Set<String> = []
        for item in items {
            guard let id = item.id else { continue }
            guard item.projectId == projectId else { continue }
            guard item.status != .returned else { continue }
            guard !onAnyItems.contains(id) else { continue }
            toInvoiceItems.insert(id)
        }

        var toInvoiceTx: Set<String> = []
        for tx in transactions {
            guard let id = tx.id else { continue }
            guard tx.projectId == projectId else { continue }
            // Only non-itemized transactions enter the pool directly — itemized
            // purchases bill via their items.
            guard BillingSummaryCalculations.isNonItemized(tx) else { continue }
            // Must be billable by shape (sign exists and non-canceled).
            guard sign(for: tx) != nil else { continue }
            guard !onAnyTx.contains(id) else { continue }
            toInvoiceTx.insert(id)
        }

        return BillableMembership(
            toInvoiceItemIds: toInvoiceItems,
            toInvoiceTransactionIds: toInvoiceTx,
            invoicedItemIds: invoicedItems,
            invoicedTransactionIds: invoicedTx,
            paidItemIds: paidItems,
            paidTransactionIds: paidTx,
            draftItemIds: draftItems,
            draftTransactionIds: draftTx
        )
    }

    /// Net total in cents for a set of signed lines.
    static func netTotalCents(lines: [InvoiceLine]) -> Int {
        lines.reduce(0) { $0 + $1.signedAmountCents }
    }

    // MARK: - Running balance

    /// Net Payable-to-Business / Payable-to-Client running balance for a
    /// project, derived from invoice membership and the unbilled billable pool.
    ///
    /// Payable-to-Business = +lines on sent-but-unpaid invoices + charge-signed
    /// unbilled activity.
    ///
    /// Payable-to-Client = −lines on sent-but-unpaid invoices + credit-signed
    /// unbilled activity (stored as positive magnitudes).
    struct PayableBalance: Equatable {
        var toBusinessCents: Int
        var toClientCents: Int
    }

    static func payableBalance(
        projectId: String,
        items: [Item],
        transactions: [Transaction],
        invoices: [Invoice]
    ) -> PayableBalance {
        var toBusiness = 0
        var toClient = 0

        // Sent-but-unpaid invoices contribute their stored signed lines.
        for invoice in invoices {
            guard invoice.projectId == projectId else { continue }
            guard invoice.status == .sent else { continue }
            for line in invoice.lines ?? [] {
                switch line.sign {
                case .charge: toBusiness += line.amountCents
                case .credit: toClient += line.amountCents
                }
            }
        }

        // Unbilled billable pool contributes by derived sign.
        let membership = billableMembership(
            projectId: projectId,
            items: items,
            transactions: transactions,
            invoices: invoices
        )
        for item in items {
            guard let id = item.id, membership.toInvoiceItemIds.contains(id) else { continue }
            toBusiness += amountCents(for: item)
        }
        for tx in transactions {
            guard let id = tx.id, membership.toInvoiceTransactionIds.contains(id) else { continue }
            switch sign(for: tx) {
            case .charge: toBusiness += tx.amountCents ?? 0
            case .credit: toClient += tx.amountCents ?? 0
            case .none: break
            }
        }

        for tx in transactions where tx.projectId == projectId && tx.settlementInvoiceId != nil {
            toBusiness -= tx.amountCents ?? 0
        }

        return PayableBalance(toBusinessCents: max(toBusiness, 0), toClientCents: toClient)
    }
}

// MARK: - Invoice membership helpers

/// Resolve the status of the first non-voided invoice that references the
/// given item id. Returns nil when the item isn't on any invoice.
/// Paid wins over sent/draft to drive the card badge priority.
func firstNonVoidedInvoiceStatus(forItemId id: String, in invoices: [Invoice]) -> InvoiceStatus? {
    return resolveInvoiceStatus(matching: id, in: invoices) { $0.itemIds ?? [] }
}

/// Resolve the status of the first non-voided invoice that references the
/// given transaction id. Returns nil when the transaction isn't on any invoice.
func firstNonVoidedInvoiceStatus(forTransactionId id: String, in invoices: [Invoice]) -> InvoiceStatus? {
    return resolveInvoiceStatus(matching: id, in: invoices) { $0.transactionIds ?? [] }
}

private func resolveInvoiceStatus(
    matching id: String,
    in invoices: [Invoice],
    extract: (Invoice) -> [String]
) -> InvoiceStatus? {
    var best: InvoiceStatus? = nil
    for invoice in invoices {
        guard invoice.status != .voided else { continue }
        guard extract(invoice).contains(id) else { continue }
        let status = invoice.status ?? .draft
        if status == .paid { return .paid }
        if best == nil { best = status }
        else if best == .draft && status == .sent { best = .sent }
    }
    return best
}
