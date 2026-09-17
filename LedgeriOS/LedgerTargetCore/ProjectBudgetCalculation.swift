import Foundation

/// Composes existing accounting facts; it does not store another financial ledger.
/// The provider must supply one authorized, complete snapshot. Pending operations,
/// missing downloads and unsupported Transfer evidence are not empty input sets.
public enum ProjectBudgetCalculation {
    public enum Failure: Error, Equatable { case scopeMismatch, duplicateSource, missingEvidence, unsupportedTransfer }

    public static func calculate(categories: [BudgetCategoryDefinitionSnapshot], currency: CurrencyCode,
        review: InvoiceCreationReview, live: [LiveInvoiceContents], paid: [FrozenInvoiceContents],
        itemRows: ProjectInvoicingItems, transactions: [TransactionDetailSnapshot],
        transfers: [ProjectBudgetTransfer] = []) throws -> [ProjectBudgetCategorySegment] {
        let scope = review.scope
        guard scope.ownerKind == .project, scope.accountId == itemRows.accountId,
              scope.projectId == itemRows.projectId,
              categories.allSatisfy({ $0.accountId == scope.accountId }),
              live.allSatisfy({ $0.selection.scope == scope }), paid.allSatisfy({ $0.scope == scope }),
              transactions.allSatisfy({ $0.classification.scope == scope }),
              transfers.allSatisfy({ $0.pair.route.source == scope || $0.pair.route.destination == scope }) else { throw Failure.scopeMismatch }
        guard Set(categories.map(\.id)).count == categories.count,
              Set(paid.map(\.invoiceId)).count == paid.count,
              Set(paid.map(\.purchaseId)).count == paid.count,
              Set(live.map(\.invoiceId)).count == live.count,
              Set(transactions.map(\.transactionId)).count == transactions.count,
              Set(transfers.map(\.pair.operationId)).count == transfers.count else { throw Failure.duplicateSource }
        let transferIDs = transfers.flatMap { [$0.pair.sourceTransactionId, $0.pair.destinationTransactionId] }
        guard Set(transferIDs).count == transferIDs.count,
              Set(transferIDs).isDisjoint(with: transactions.map(\.transactionId)) else { throw Failure.duplicateSource }
        let known = Set(categories.map(\.id))
        var paidAmounts: [BudgetCategoryID: Money] = [:], unpaidAmounts: [BudgetCategoryID: Money] = [:]
        var sources = Set<LiveInvoiceSource>()
        var sourceEvidence: [LiveInvoiceSource: (Money, BudgetCategoryID, Bool)] = [:]
        func add(_ amount: Money, category: BudgetCategoryID, isPaid: Bool) throws {
            guard known.contains(category) else { throw Failure.missingEvidence }
            guard amount.currency == currency else { throw ProjectBudgetSegmentFailure.currencyMismatch }
            if isPaid {
                paidAmounts[category] = try (paidAmounts[category] ?? .zero(currency: currency)).adding(amount)
            } else {
                unpaidAmounts[category] = try (unpaidAmounts[category] ?? .zero(currency: currency)).adding(amount)
            }
        }
        for invoice in paid {
            for line in invoice.lines {
                let source: LiveInvoiceSource
                switch line.source {
                case .item(_, let id, _): source = .itemOccurrence(id)
                case .expense(let id): source = .expense(id)
                case .feeInstallment(let id): source = .feeInstallment(id)
                }
                guard sources.insert(source).inserted else { throw Failure.duplicateSource }
                sourceEvidence[source] = (line.signedAmount, line.categoryId, true)
                try add(line.signedAmount, category: line.categoryId, isPaid: true)
            }
        }
        let collectedIDs = Set(paid.map(\.invoiceId))
        // Independent watches can retain the previous live version briefly.
        // The frozen version of the same Invoice is authoritative, as in Fee rows.
        let open = review.candidates + live.filter { !collectedIDs.contains($0.invoiceId) }.flatMap(\.lines)
        for line in open {
            guard sources.insert(line.selection.source).inserted else { throw Failure.duplicateSource }
            sourceEvidence[line.selection.source] = (line.selection.reviewedAmount, line.categoryId, false)
            try add(line.selection.reviewedAmount, category: line.categoryId, isPaid: false)
        }
        for row in itemRows.rows where row.occurrence.polarity == .charge {
            guard let evidence = sourceEvidence[.itemOccurrence(row.occurrence.id)],
                  evidence.0 == row.amount, evidence.1 == row.categoryId,
                  evidence.2 == (row.availability == .paid) else { throw Failure.missingEvidence }
        }
        // Credits are explicit facts absent from positive Invoice candidates;
        // their settlement is a separate, not-yet-approved workflow.
        for row in itemRows.rows where row.occurrence.polarity == .credit {
            guard row.availability == .available, let category = row.categoryId else { throw Failure.missingEvidence }
            try add(row.amount, category: category, isPaid: false)
        }
        for transaction in transactions {
            switch transaction.origin {
            case .importedClientPayment:
                guard let invoice = paid.first(where: { $0.purchaseId == transaction.transactionId }),
                      invoice.total == transaction.amount else { throw Failure.missingEvidence }
                // Its frozen lines were counted above; never add the lump sum.
            case .vendorPayment:
                guard !paid.contains(where: { $0.purchaseId == transaction.transactionId }),
                      let category = transaction.category?.id else { throw Failure.missingEvidence }
                let amount: Money
                switch transaction.classification.type {
                case .purchase: amount = transaction.amount
                case .return: amount = try transaction.amount.negated()
                case .transfer: throw Failure.unsupportedTransfer
                }
                try add(amount, category: category, isPaid: true)
            }
        }
        for transfer in transfers {
            for item in transfer.items {
                switch item.basis {
                case .openCharge:
                    // The moved open occurrence contributes through candidates
                    // or its Invoice; the Transfer must not add it again.
                    break
                case .paidLine(let line):
                    let amount = transfer.pair.route.source == scope
                        ? try line.signedAmount.negated() : line.signedAmount
                    try add(amount, category: line.categoryId, isPaid: true)
                }
            }
        }
        return try categories.map {
            try .init(category: $0, clientPaid: paidAmounts[$0.id] ?? .zero(currency: currency),
                invoicingUnpaid: unpaidAmounts[$0.id] ?? .zero(currency: currency))
        }
    }
}
