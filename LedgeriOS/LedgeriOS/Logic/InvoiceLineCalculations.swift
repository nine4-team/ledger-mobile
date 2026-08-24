import Foundation

/// Pure calculations for the v2 invoicing model: sign derivation for a source
/// (item or transaction), and the three-way billable-membership split that
/// drives the To Invoice / Invoiced / Paid pipeline in the Billing subtab.
///
/// See `docs/specs/billing-invoicing.md` for the rules.
enum InvoiceLineCalculations {
    enum ItemBillingBasis: Equatable {
        case projectPrice
        case purchasePrice
    }

    enum ItemInvoiceability: Equatable {
        case billable(ItemBillingBasis)
        case notBillable
    }

    struct ReturnedPaidItemCreditContext: Hashable {
        var itemId: String
        var itemName: String
        var projectId: String
        var amountCents: Int
        var budgetCategoryId: String
        var paidInvoiceId: String
        var paidInvoiceLineId: String
        var lineId: String
    }

    private struct ReturnedPaidItemCreditCandidate {
        var invoice: Invoice
        var line: InvoiceLine
        var item: Item
        var itemId: String
        var lineId: String
    }

    static func returnedPaidItemCreditLineId(
        paidInvoiceId: String,
        paidInvoiceLineId: String,
        itemId: String
    ) -> String {
        "returnCredit:\(paidInvoiceId):\(paidInvoiceLineId):\(itemId)"
    }

    static func returnedPaidItemCreditContexts(
        for items: [Item],
        invoices: [Invoice]
    ) -> [ReturnedPaidItemCreditContext] {
        let selectedItemsById: [String: Item] = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            guard let id = item.id else { return nil }
            return (id, item)
        })
        guard !selectedItemsById.isEmpty else { return [] }

        let existingCreditLineIds = Set(
            invoices
                .filter { $0.status != .canceled }
                .flatMap { $0.lines ?? [] }
                .map(\.id)
                .filter { $0.hasPrefix("returnCredit:") }
        )

        var candidatesByItemId: [String: [ReturnedPaidItemCreditCandidate]] = [:]
        for invoice in invoices {
            guard invoice.status == .paid else { continue }
            guard let invoiceId = invoice.id else { continue }
            for line in invoice.lines ?? [] {
                guard line.sourceType == .item,
                      line.sign == .charge,
                      let itemId = line.sourceId,
                      let item = selectedItemsById[itemId],
                      let paidLineCategoryId = line.budgetCategoryId?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !paidLineCategoryId.isEmpty else {
                    continue
                }
                let creditLineId = returnedPaidItemCreditLineId(
                    paidInvoiceId: invoiceId,
                    paidInvoiceLineId: line.id,
                    itemId: itemId
                )
                guard !existingCreditLineIds.contains(creditLineId) else { continue }
                candidatesByItemId[itemId, default: []].append(
                    ReturnedPaidItemCreditCandidate(invoice: invoice, line: line, item: item, itemId: itemId, lineId: creditLineId)
                )
            }
        }

        return candidatesByItemId.keys.sorted().compactMap { itemId in
            guard let candidate = candidatesByItemId[itemId]?.sorted(by: candidateSort).first else {
                return nil
            }
            guard let projectId = candidate.item.projectId ?? candidate.invoice.projectId else { return nil }
            guard let categoryId = candidate.line.budgetCategoryId?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !categoryId.isEmpty else {
                return nil
            }
            let itemName = candidate.item.displayName.isEmpty ? "item" : candidate.item.displayName
            return ReturnedPaidItemCreditContext(
                itemId: candidate.itemId,
                itemName: itemName,
                projectId: projectId,
                amountCents: candidate.line.amountCents,
                budgetCategoryId: categoryId,
                paidInvoiceId: candidate.invoice.id ?? "",
                paidInvoiceLineId: candidate.line.id,
                lineId: candidate.lineId
            )
        }
    }

    private static func candidateSort(
        lhs: ReturnedPaidItemCreditCandidate,
        rhs: ReturnedPaidItemCreditCandidate
    ) -> Bool {
        let leftDate = lhs.invoice.datePaid ?? lhs.invoice.dateSent ?? lhs.invoice.dateIssued ?? lhs.invoice.createdAt ?? .distantPast
        let rightDate = rhs.invoice.datePaid ?? rhs.invoice.dateSent ?? rhs.invoice.dateIssued ?? rhs.invoice.createdAt ?? .distantPast
        if leftDate != rightDate { return leftDate > rightDate }
        return (lhs.invoice.id ?? "") > (rhs.invoice.id ?? "")
    }

    // MARK: - Sign derivation

    /// Items in a project represent goods purchased for the client, so every
    /// project item is a charge. Returned items that were on a paid invoice
    /// generate ordinary created-invoice credit lines; the item itself isn't
    /// signed as a credit.
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
        guard tx.transactionType != .paymentToBusiness else { return nil }
        guard let direction = ReportAggregationCalculations.reimbursementDirection(for: tx) else {
            return nil
        }
        switch direction {
        case .owedToCompany: return .charge
        case .owedToClient: return .credit
        }
    }

    static func invoiceability(
        for item: Item,
        projectId: String,
        transactions: [Transaction],
        lineageEdges: [LineageEdge] = []
    ) -> ItemInvoiceability {
        guard item.status != .returned else { return .notBillable }
        guard item.projectId == projectId else { return .notBillable }

        let transactionById = Dictionary(uniqueKeysWithValues: transactions.compactMap { tx -> (String, Transaction)? in
            guard let id = tx.id else { return nil }
            return (id, tx)
        })

        if let transactionId = item.transactionId,
           let tx = transactionById[transactionId],
           tx.projectId == projectId {
            if tx.status == .canceled { return .notBillable }
            if tx.transactionType == .purchase,
               tx.source?.hasSuffix(" Inventory") == true {
                return .billable(.projectPrice)
            }
            if tx.reimbursementType == "owed-to-company",
               !tx.isInventoryMovement {
                return .billable(.purchasePrice)
            }
            return .notBillable
        }

        if lineageEdges.contains(where: { edge in
            edge.itemId == item.id &&
                edge.movementKind == "sold" &&
                edge.toProjectId == projectId
        }) {
            return .billable(.projectPrice)
        }

        if (item.currentSource ?? "").hasSuffix(" Inventory") {
            return .billable(.projectPrice)
        }

        return .notBillable
    }

    static func amountCents(
        for item: Item,
        projectId: String,
        transactions: [Transaction],
        lineageEdges: [LineageEdge] = []
    ) -> Int? {
        switch invoiceability(
            for: item,
            projectId: projectId,
            transactions: transactions,
            lineageEdges: lineageEdges
        ) {
        case .billable(.projectPrice):
            return item.normalizedProjectPriceCents ?? 0
        case .billable(.purchasePrice):
            return item.purchasePriceCents ?? 0
        case .notBillable:
            return nil
        }
    }

    /// Legacy amount fallback. New candidate code should call the overload that
    /// receives project transactions so it can choose project price vs purchase
    /// price from the item's billing basis.
    static func amountCents(for item: Item) -> Int {
        item.normalizedProjectPriceCents ?? 0
    }

    /// Build a signed InvoiceLine from an item. Always a charge.
    static func makeLine(item: Item) -> InvoiceLine? {
        guard let id = item.id else { return nil }
        return InvoiceLine(
            sourceType: .item,
            sourceId: id,
            amountCents: amountCents(for: item),
            sign: sign(for: item),
            budgetCategoryId: item.budgetCategoryId,
            snapshotName: item.displayName.isEmpty ? nil : item.displayName
        )
    }

    static func makeLine(
        item: Item,
        projectId: String,
        transactions: [Transaction],
        lineageEdges: [LineageEdge] = []
    ) -> InvoiceLine? {
        guard let id = item.id else { return nil }
        guard let amount = amountCents(
            for: item,
            projectId: projectId,
            transactions: transactions,
            lineageEdges: lineageEdges
        ) else { return nil }
        return InvoiceLine(
            sourceType: .item,
            sourceId: id,
            amountCents: amount,
            sign: .charge,
            budgetCategoryId: item.budgetCategoryId,
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
            budgetCategoryId: tx.budgetCategoryId,
            snapshotName: tx.source ?? tx.notes
        )
    }

    static func makeLine(feeInstallment installment: FeeInstallment) -> InvoiceLine? {
        guard let id = installment.id else { return nil }
        return InvoiceLine(
            sourceType: .feeInstallment,
            sourceId: id,
            amountCents: installment.amountCents,
            sign: .charge,
            budgetCategoryId: installment.budgetCategoryId,
            snapshotName: installment.label
        )
    }

    // MARK: - Billable membership

    /// The three disjoint buckets for a project's billable activity, plus the
    /// "on a created invoice" set which is excluded from all three tabs but still
    /// excluded from the Create Invoice picker.
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
        /// On a created invoice for this project. Not shown in any of the three
        /// tabs, but excluded from the picker when creating a *different* created invoice.
        var createdItemIds: Set<String>
        var createdTransactionIds: Set<String>

        /// Union of created + sent + paid — every source already claimed by some
        /// non-canceled invoice. Used to filter the To Invoice pool.
        var onAnyInvoiceItemIds: Set<String> {
            createdItemIds.union(invoicedItemIds).union(paidItemIds)
        }
        var onAnyInvoiceTransactionIds: Set<String> {
            createdTransactionIds.union(invoicedTransactionIds).union(paidTransactionIds)
        }
    }

    /// Compute the membership buckets for a project.
    ///
    /// - Parameters:
    ///   - projectId: the project we're computing for.
    ///   - items: candidate items (typically `projectContext.items`).
    ///   - transactions: candidate transactions (typically `projectContext.transactions`).
    ///   - invoices: all invoices for the account (typically `accountContext.allInvoices`).
    ///   - excludingInvoiceId: when a created invoice is being edited in the picker,
    ///     exclude its own membership so the editing invoice's current selection
    ///     is still pickable. Pass nil when not editing.
    static func billableMembership(
        projectId: String,
        items: [Item],
        transactions: [Transaction],
        invoices: [Invoice],
        budgetCategories: [String: BudgetCategory] = [:],
        lineageEdges: [LineageEdge] = [],
        excludingInvoiceId: String? = nil
    ) -> BillableMembership {
        var createdItems: Set<String> = []
        var createdTx: Set<String> = []
        var invoicedItems: Set<String> = []
        var invoicedTx: Set<String> = []
        var paidItems: Set<String> = []
        var paidTx: Set<String> = []

        for invoice in invoices {
            guard invoice.projectId == projectId else { continue }
            guard invoice.status != .canceled else { continue }
            if let excluded = excludingInvoiceId, invoice.id == excluded { continue }

            let itemIds = invoice.itemIds ?? []
            let txIds = invoice.transactionIds ?? []

            switch invoice.status ?? .created {
            case .created:
                createdItems.formUnion(itemIds)
                createdTx.formUnion(txIds)
            case .sent:
                invoicedItems.formUnion(itemIds)
                invoicedTx.formUnion(txIds)
            case .paid:
                paidItems.formUnion(itemIds)
                paidTx.formUnion(txIds)
            case .canceled:
                break
            }
        }

        let onAnyItems = createdItems.union(invoicedItems).union(paidItems)
        let onAnyTx = createdTx.union(invoicedTx).union(paidTx)

        var toInvoiceItems: Set<String> = []
        for item in items {
            guard let id = item.id else { continue }
            guard invoiceability(
                for: item,
                projectId: projectId,
                transactions: transactions,
                lineageEdges: lineageEdges
            ) != .notBillable else { continue }
            guard !onAnyItems.contains(id) else { continue }
            toInvoiceItems.insert(id)
        }

        var toInvoiceTx: Set<String> = []
        for tx in transactions {
            guard let id = tx.id else { continue }
            guard tx.projectId == projectId else { continue }
            // Only non-itemized transactions enter the pool directly — itemized
            // purchases bill via their items.
            guard BillingSummaryCalculations.isNonItemized(tx, budgetCategories: budgetCategories) else { continue }
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
            createdItemIds: createdItems,
            createdTransactionIds: createdTx
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
        invoices: [Invoice],
        budgetCategories: [String: BudgetCategory] = [:]
    ) -> PayableBalance {
        var toBusiness = 0
        var toClient = 0

        // Sent-but-unpaid invoices contribute live source-derived line amounts.
        for invoice in invoices {
            guard invoice.projectId == projectId else { continue }
            guard invoice.status == .sent else { continue }
            for line in invoice.lines ?? [] {
                let amount: Int
                switch line.sourceType {
                case .item:
                    amount = line.sourceId.flatMap { itemId in
                        items.first { $0.id == itemId }.flatMap {
                            amountCents(for: $0, projectId: projectId, transactions: transactions)
                        }
                    } ?? line.amountCents
                case .transaction:
                    amount = line.sourceId.flatMap { txId in
                        transactions.first { $0.id == txId }?.amountCents
                    } ?? line.amountCents
                case .feeInstallment:
                    amount = line.amountCents
                case .manual:
                    amount = line.amountCents
                }
                switch line.sign {
                case .charge: toBusiness += amount
                case .credit: toClient += amount
                }
            }
        }

        // Unbilled billable pool contributes by derived sign.
        let membership = billableMembership(
            projectId: projectId,
            items: items,
            transactions: transactions,
            invoices: invoices,
            budgetCategories: budgetCategories
        )
        for item in items {
            guard let id = item.id, membership.toInvoiceItemIds.contains(id) else { continue }
            toBusiness += amountCents(
                for: item,
                projectId: projectId,
                transactions: transactions
            ) ?? 0
        }
        for tx in transactions {
            guard let id = tx.id, membership.toInvoiceTransactionIds.contains(id) else { continue }
            switch sign(for: tx) {
            case .charge: toBusiness += tx.amountCents ?? 0
            case .credit: toClient += tx.amountCents ?? 0
            case .none: break
            }
        }

        for tx in transactions where tx.projectId == projectId && BillingSummaryCalculations.isActiveSettlement(tx) {
            toBusiness -= tx.amountCents ?? 0
        }

        return PayableBalance(toBusinessCents: max(toBusiness, 0), toClientCents: toClient)
    }
}

// MARK: - Invoice membership helpers

/// Resolve the status of the first non-canceled invoice that references the
/// given item id. Returns nil when the item isn't on any invoice.
/// Paid wins over sent/created to drive the card badge priority.
func firstNonCanceledInvoiceStatus(forItemId id: String, in invoices: [Invoice]) -> InvoiceStatus? {
    return resolveInvoiceStatus(matching: id, in: invoices) { $0.itemIds ?? [] }
}

/// Resolve the status of the first non-canceled invoice that references the
/// given transaction id. Returns nil when the transaction isn't on any invoice.
func firstNonCanceledInvoiceStatus(forTransactionId id: String, in invoices: [Invoice]) -> InvoiceStatus? {
    return resolveInvoiceStatus(matching: id, in: invoices) { $0.transactionIds ?? [] }
}

private func resolveInvoiceStatus(
    matching id: String,
    in invoices: [Invoice],
    extract: (Invoice) -> [String]
) -> InvoiceStatus? {
    var best: InvoiceStatus? = nil
    for invoice in invoices {
        guard invoice.status != .canceled else { continue }
        guard extract(invoice).contains(id) else { continue }
        let status = invoice.status ?? .created
        if status == .paid { return .paid }
        if best == nil { best = status }
        else if best == .created && status == .sent { best = .sent }
    }
    return best
}
