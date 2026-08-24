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
        canSeeTransaction(
            transaction,
            categoryById: Dictionary(uniqueKeysWithValues: categories.compactMap { category in
                category.id.map { ($0, category) }
            })
        )
    }

    private func canSeeTransaction(
        _ transaction: Transaction,
        categoryById: [String: BudgetCategory]
    ) -> Bool {
        guard isCompanyFee(transaction, categoryById: categoryById) else { return true }
        guard let categoryId = transaction.budgetCategoryId else { return access == .full }
        return canSeeFeeCategory(id: categoryId)
    }

    func visibleTransactions(_ transactions: [Transaction], categories: [BudgetCategory]) -> [Transaction] {
        let categoryById = Dictionary(uniqueKeysWithValues: categories.compactMap { category in
            category.id.map { ($0, category) }
        })
        return transactions.filter { canSeeTransaction($0, categoryById: categoryById) }
    }

    func canSeeInvoice(_ invoice: Invoice, transactions: [Transaction], categories: [BudgetCategory]) -> Bool {
        if access == .full { return true }

        if let containsCompanyRevenue = invoice.containsCompanyRevenue {
            guard containsCompanyRevenue else { return true }
            let feeIds = Set(invoice.feeCategoryIds ?? [])
            guard !feeIds.isEmpty else { return false }
            return access == .limited && feeIds.isSubset(of: allowedFeeCategoryIds)
        }

        return canSeeInvoice(
            invoice,
            transactionById: Dictionary(uniqueKeysWithValues: transactions.compactMap { transaction in
                transaction.id.map { ($0, transaction) }
            }),
            categoryById: Dictionary(uniqueKeysWithValues: categories.compactMap { category in
                category.id.map { ($0, category) }
            })
        )
    }

    private func canSeeInvoice(
        _ invoice: Invoice,
        transactionById: [String: Transaction],
        categoryById: [String: BudgetCategory]
    ) -> Bool {
        if access == .full { return true }

        if let containsCompanyRevenue = invoice.containsCompanyRevenue {
            guard containsCompanyRevenue else { return true }
            let feeIds = Set(invoice.feeCategoryIds ?? [])
            guard !feeIds.isEmpty else { return false }
            return access == .limited && feeIds.isSubset(of: allowedFeeCategoryIds)
        }

        var feeCategoryIds = Set<String>()
        var sawCompanyRevenue = false

        for transactionId in invoice.transactionIds ?? [] {
            guard let transaction = transactionById[transactionId] else {
                continue
            }
            if isCompanyFee(transaction, categoryById: categoryById) {
                sawCompanyRevenue = true
                guard let categoryId = transaction.budgetCategoryId else { return false }
                feeCategoryIds.insert(categoryId)
            }
        }

        for line in invoice.lines ?? [] {
            switch line.sourceType {
            case .transaction:
                guard let sourceId = line.sourceId, let transaction = transactionById[sourceId] else {
                    continue
                }
                if isCompanyFee(transaction, categoryById: categoryById) {
                    sawCompanyRevenue = true
                    guard let categoryId = transaction.budgetCategoryId else { return false }
                    feeCategoryIds.insert(categoryId)
                }
            case .feeInstallment, .manual:
                if line.sign == .charge {
                    sawCompanyRevenue = true
                    guard let categoryId = line.budgetCategoryId else { return false }
                    feeCategoryIds.insert(categoryId)
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
        if access == .full { return invoices }
        let transactionById = Dictionary(uniqueKeysWithValues: transactions.compactMap { transaction in
            transaction.id.map { ($0, transaction) }
        })
        let categoryById = Dictionary(uniqueKeysWithValues: categories.compactMap { category in
            category.id.map { ($0, category) }
        })
        return invoices.filter {
            canSeeInvoice($0, transactionById: transactionById, categoryById: categoryById)
        }
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

    private func isCompanyFee(
        _ transaction: Transaction,
        categoryById: [String: BudgetCategory]
    ) -> Bool {
        if transaction.transactionType == .paymentToBusiness { return true }
        let category = transaction.budgetCategoryId.flatMap { categoryById[$0] }
        let storedType = transaction.transactionType ?? .purchase
        return TransactionTaxonomy.resolve(storedType: storedType, category: category) == .fee
    }
}
