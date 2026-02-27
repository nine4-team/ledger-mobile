import Foundation

/// Output type for a fully computed budget category row.
struct BudgetCategoryRowData: Identifiable {
    let id: String
    let category: BudgetProgress.CategoryProgress
    let spentCents: Int
    let budgetCents: Int
    let isOverBudget: Bool
    let spendLabel: String
    let remainingLabel: String
}

/// Pure functions for filtering, sorting, and labeling budget categories
/// in the Budget tab. Testable without SwiftUI.
enum BudgetTabCalculations {

    // MARK: - CategoryProgress-Based Functions (existing)

    /// Keeps categories that have a nonzero budget OR nonzero spending.
    /// Filters out categories with zero budget AND zero spending.
    static func enabledCategories(
        allCategories: [BudgetProgress.CategoryProgress]
    ) -> [BudgetProgress.CategoryProgress] {
        allCategories.filter { $0.budgetCents > 0 || $0.spentCents != 0 }
    }

    /// Sorts categories with fee categories last.
    /// Within each group (non-fee, fee), sorts alphabetically by name.
    static func sortCategories(
        _ categories: [BudgetProgress.CategoryProgress]
    ) -> [BudgetProgress.CategoryProgress] {
        let nonFee = categories
            .filter { $0.categoryType != .fee }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let fee = categories
            .filter { $0.categoryType == .fee }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return nonFee + fee
    }

    /// Returns a remaining/over label relative to budget, or delegates to
    /// `spentLabel` when the budget is zero.
    ///
    /// - Under/at budget: "$Y remaining"
    /// - Over budget (non-fee): "$Y over"
    /// - Over budget (fee): "$Y over received"
    /// - Zero budget: delegates to `spentLabel`
    static func remainingLabel(
        spentCents: Int,
        budgetCents: Int,
        categoryType: BudgetCategoryType
    ) -> String {
        guard budgetCents != 0 else {
            return spentLabel(spentCents: spentCents, categoryType: categoryType)
        }
        if spentCents <= budgetCents {
            let remaining = budgetCents - spentCents
            return "\(BudgetDisplayCalculations.formatCentsAsDollars(remaining)) remaining"
        } else {
            let over = spentCents - budgetCents
            let suffix = categoryType == .fee ? "over received" : "over"
            return "\(BudgetDisplayCalculations.formatCentsAsDollars(over)) \(suffix)"
        }
    }

    /// Formats a spent/received label based on category type.
    ///
    /// - Fee categories: "$X received"
    /// - All others: "$X spent"
    static func spentLabel(
        spentCents: Int,
        categoryType: BudgetCategoryType
    ) -> String {
        let formatted = BudgetDisplayCalculations.formatCentsAsDollars(spentCents)
        switch categoryType {
        case .fee:
            return "\(formatted) received"
        case .general, .itemized:
            return "\(formatted) spent"
        }
    }

    // MARK: - Transaction-Based Spend Normalization

    /// Normalizes a single transaction's contribution to category spend.
    ///
    /// Rules (FR-3.8):
    /// - `isCanceled == true` → $0
    /// - `status == "returned"` OR negative `amountCents` → subtracts (negative contribution)
    /// - `isCanonicalInventorySale == true` AND `inventorySaleDirection == .projectToBusiness` → subtracts
    /// - `isCanonicalInventorySale == true` AND `inventorySaleDirection == .businessToProject` → adds
    /// - All others → adds
    static func normalizeTransactionAmount(_ transaction: Transaction) -> Int {
        guard transaction.isCanceled != true else { return 0 }

        let amount = transaction.amountCents ?? 0

        if transaction.isCanonicalInventorySale == true {
            switch transaction.inventorySaleDirection {
            case .projectToBusiness:
                return -abs(amount)
            case .businessToProject:
                return abs(amount)
            case nil:
                return amount
            }
        }

        if transaction.status == "returned" || amount < 0 {
            return -abs(amount)
        }

        return amount
    }

    /// Computes the total spend for a category from its matching transactions.
    static func computeSpend(
        for categoryId: String,
        transactions: [Transaction]
    ) -> Int {
        transactions
            .filter { $0.budgetCategoryId == categoryId }
            .reduce(0) { $0 + normalizeTransactionAmount($1) }
    }

    // MARK: - Raw Model Row Building

    /// Filters raw BudgetCategory models to only those with non-zero budget or spend.
    /// Excludes archived categories.
    static func enabledRawCategories(
        _ categories: [BudgetCategory],
        projectBudgetCategories: [ProjectBudgetCategory],
        transactions: [Transaction]
    ) -> [BudgetCategory] {
        let budgetById = Dictionary(
            uniqueKeysWithValues: projectBudgetCategories.compactMap { pbc in
                pbc.id.map { ($0, pbc.budgetCents ?? 0) }
            }
        )

        return categories.filter { category in
            guard category.isArchived != true, let id = category.id else { return false }
            let budget = budgetById[id] ?? 0
            let spent = computeSpend(for: id, transactions: transactions)
            return budget > 0 || spent != 0
        }
    }

    /// Sorts raw BudgetCategory models: fee categories last, alphabetical within groups.
    static func sortRawCategories(_ categories: [BudgetCategory]) -> [BudgetCategory] {
        let nonFee = categories
            .filter { ($0.metadata?.categoryType ?? .general) != .fee }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let fee = categories
            .filter { ($0.metadata?.categoryType ?? .general) == .fee }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return nonFee + fee
    }

    /// Builds fully computed budget rows from raw models.
    static func buildBudgetRows(
        categories: [BudgetCategory],
        projectBudgetCategories: [ProjectBudgetCategory],
        transactions: [Transaction]
    ) -> [BudgetCategoryRowData] {
        let budgetById = Dictionary(
            uniqueKeysWithValues: projectBudgetCategories.compactMap { pbc in
                pbc.id.map { ($0, pbc.budgetCents ?? 0) }
            }
        )

        let enabled = enabledRawCategories(
            categories,
            projectBudgetCategories: projectBudgetCategories,
            transactions: transactions
        )
        let sorted = sortRawCategories(enabled)

        return sorted.compactMap { category -> BudgetCategoryRowData? in
            guard let id = category.id else { return nil }
            let catType = category.metadata?.categoryType ?? .general
            let exclude = category.metadata?.excludeFromOverallBudget ?? false
            let budget = budgetById[id] ?? 0
            let spent = computeSpend(for: id, transactions: transactions)

            let progress = BudgetProgress.CategoryProgress(
                id: id,
                name: category.name,
                budgetCents: budget,
                spentCents: spent,
                categoryType: catType,
                excludeFromOverallBudget: exclude
            )

            return BudgetCategoryRowData(
                id: id,
                category: progress,
                spentCents: spent,
                budgetCents: budget,
                isOverBudget: BudgetDisplayCalculations.isOverBudget(spent: spent, budget: budget),
                spendLabel: spentLabel(spentCents: spent, categoryType: catType),
                remainingLabel: remainingLabel(spentCents: spent, budgetCents: budget, categoryType: catType)
            )
        }
    }

    /// Computes the overall budget row by summing all non-excluded category rows.
    static func overallBudgetRow(rows: [BudgetCategoryRowData]) -> BudgetCategoryRowData {
        let included = rows.filter { !$0.category.excludeFromOverallBudget }
        let totalSpent = included.reduce(0) { $0 + $1.spentCents }
        let totalBudget = included.reduce(0) { $0 + $1.budgetCents }

        let progress = BudgetProgress.CategoryProgress(
            id: "overall",
            name: "Overall Budget",
            budgetCents: totalBudget,
            spentCents: totalSpent,
            categoryType: .general,
            excludeFromOverallBudget: false
        )

        return BudgetCategoryRowData(
            id: "overall",
            category: progress,
            spentCents: totalSpent,
            budgetCents: totalBudget,
            isOverBudget: BudgetDisplayCalculations.isOverBudget(spent: totalSpent, budget: totalBudget),
            spendLabel: spentLabel(spentCents: totalSpent, categoryType: .general),
            remainingLabel: remainingLabel(spentCents: totalSpent, budgetCents: totalBudget, categoryType: .general)
        )
    }
}
