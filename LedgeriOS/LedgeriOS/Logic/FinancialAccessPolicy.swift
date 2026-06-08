import Foundation

struct FinancialAccessPolicy: Equatable {
    let access: CompanyFinancialAccess
    let allowedFeeCategoryIds: Set<String>

    init(member: AccountMember?) {
        access = member?.resolvedCompanyFinancialAccess ?? .none
        allowedFeeCategoryIds = member?.resolvedAllowedFeeCategoryIds ?? []
    }

    init(access: CompanyFinancialAccess, allowedFeeCategoryIds: Set<String> = []) {
        self.access = access
        self.allowedFeeCategoryIds = allowedFeeCategoryIds
    }

    var hasFullFinancialAccess: Bool {
        access == .full
    }

    func canSeeCategory(_ category: BudgetCategory) -> Bool {
        guard category.isFeeCategory else { return true }
        guard let categoryId = category.id else { return access == .full }
        return canSeeFeeCategory(id: categoryId)
    }

    func visibleCategories(_ categories: [BudgetCategory]) -> [BudgetCategory] {
        categories.filter(canSeeCategory)
    }

    func canSeeTransaction(_ transaction: Transaction, categories: [BudgetCategory]) -> Bool {
        guard isCompanyFee(transaction, categories: categories) else { return true }
        guard let categoryId = transaction.budgetCategoryId else { return access == .full }
        return canSeeFeeCategory(id: categoryId)
    }

    func visibleTransactions(_ transactions: [Transaction], categories: [BudgetCategory]) -> [Transaction] {
        transactions.filter { canSeeTransaction($0, categories: categories) }
    }

    func canSeeInvoice(_ invoice: Invoice, transactions: [Transaction], categories: [BudgetCategory]) -> Bool {
        if access == .full { return true }

        if let containsCompanyRevenue = invoice.containsCompanyRevenue {
            guard containsCompanyRevenue else { return true }
            let feeIds = Set(invoice.feeCategoryIds ?? [])
            guard !feeIds.isEmpty else { return false }
            return access == .limited && feeIds.isSubset(of: allowedFeeCategoryIds)
        }

        let transactionLookup = Dictionary(uniqueKeysWithValues: transactions.compactMap { tx in
            tx.id.map { ($0, tx) }
        })

        var feeCategoryIds = Set<String>()
        var sawCompanyRevenue = false

        for transactionId in invoice.transactionIds ?? [] {
            guard let transaction = transactionLookup[transactionId] else {
                continue
            }
            if isCompanyFee(transaction, categories: categories) {
                sawCompanyRevenue = true
                guard let categoryId = transaction.budgetCategoryId else { return false }
                feeCategoryIds.insert(categoryId)
            }
        }

        for line in invoice.lines ?? [] {
            switch line.sourceType {
            case .transaction:
                guard let sourceId = line.sourceId, let transaction = transactionLookup[sourceId] else {
                    continue
                }
                if isCompanyFee(transaction, categories: categories) {
                    sawCompanyRevenue = true
                    guard let categoryId = transaction.budgetCategoryId else { return false }
                    feeCategoryIds.insert(categoryId)
                }
            case .manual:
                if line.sign == .charge {
                    return false
                }
            case .item:
                continue
            }
        }

        guard sawCompanyRevenue else { return true }
        guard access == .limited, !feeCategoryIds.isEmpty else { return false }
        return feeCategoryIds.isSubset(of: allowedFeeCategoryIds)
    }

    func visibleInvoices(_ invoices: [Invoice], transactions: [Transaction], categories: [BudgetCategory]) -> [Invoice] {
        invoices.filter { canSeeInvoice($0, transactions: transactions, categories: categories) }
    }

    private func canSeeFeeCategory(id: String) -> Bool {
        switch access {
        case .full:
            return true
        case .limited:
            return allowedFeeCategoryIds.contains(id)
        case .none:
            return false
        }
    }

    private func isCompanyFee(_ transaction: Transaction, categories: [BudgetCategory]) -> Bool {
        let category = categories.first { $0.id == transaction.budgetCategoryId }
        let storedType = transaction.transactionType ?? .purchase
        return TransactionTaxonomy.resolve(storedType: storedType, category: category) == .fee
    }
}
