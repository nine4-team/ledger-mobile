import Foundation

struct BudgetProgressService {
    func buildBudgetProgress(
        transactions: [Transaction],
        categories: [BudgetCategory],
        projectBudgetCategories: [ProjectBudgetCategory]
    ) -> BudgetProgress {
        let activeCategories = categories.filter { $0.isArchived != true }

        // Build a lookup: categoryId → budget cents
        var budgetByCategoryId: [String: Int] = [:]
        for pbc in projectBudgetCategories {
            if let id = pbc.id {
                budgetByCategoryId[id] = pbc.budgetCents ?? 0
            }
        }

        // Aggregate spending by category
        var spentByCategoryId: [String: Int] = [:]
        let activeTransactions = transactions.filter { $0.isCanceled != true }
        for tx in activeTransactions {
            guard let categoryId = tx.budgetCategoryId else { continue }
            let amount = normalizeSpendAmount(tx)
            spentByCategoryId[categoryId, default: 0] += amount
        }

        // Build category progress
        var categoryProgresses: [BudgetProgress.CategoryProgress] = []
        var totalBudget = 0
        var totalSpent = 0

        for category in activeCategories {
            guard let id = category.id else { continue }
            let budget = budgetByCategoryId[id] ?? 0
            let spent = spentByCategoryId[id] ?? 0
            let catType = category.metadata?.categoryType ?? .general
            let exclude = category.metadata?.excludeFromOverallBudget ?? false

            categoryProgresses.append(BudgetProgress.CategoryProgress(
                id: id,
                name: category.name,
                budgetCents: budget,
                spentCents: spent,
                categoryType: catType,
                excludeFromOverallBudget: exclude
            ))

            if !exclude {
                totalBudget += budget
                totalSpent += spent
            }
        }

        return BudgetProgress(
            totalBudgetCents: totalBudget,
            totalSpentCents: totalSpent,
            categories: categoryProgresses
        )
    }

    func normalizeSpendAmount(_ transaction: Transaction) -> Int {
        BudgetTabCalculations.normalizeTransactionAmount(transaction)
    }
}
