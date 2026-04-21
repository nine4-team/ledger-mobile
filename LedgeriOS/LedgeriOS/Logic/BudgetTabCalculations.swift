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

    /// Keeps only categories explicitly enabled for this project
    /// (have a ProjectBudgetCategory document).
    static func enabledCategories(
        allCategories: [BudgetProgress.CategoryProgress]
    ) -> [BudgetProgress.CategoryProgress] {
        allCategories.filter { $0.isEnabled }
    }

    /// Sorts categories with fee categories last.
    /// Within each group (non-fee, fee), sorts alphabetically by name.
    static func sortCategories(
        _ categories: [BudgetProgress.CategoryProgress]
    ) -> [BudgetProgress.CategoryProgress] {
        let nonFee = categories
            .filter { !$0.isFeeCategory }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let fee = categories
            .filter { $0.isFeeCategory }
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
        isFeeCategory: Bool
    ) -> String {
        guard budgetCents != 0 else {
            return spentLabel(spentCents: spentCents, isFeeCategory: isFeeCategory)
        }
        if spentCents <= budgetCents {
            let remaining = budgetCents - spentCents
            return "\(BudgetDisplayCalculations.formatCentsAsDollars(remaining)) remaining"
        } else {
            let over = spentCents - budgetCents
            let suffix = isFeeCategory ? "over received" : "over"
            return "\(BudgetDisplayCalculations.formatCentsAsDollars(over)) \(suffix)"
        }
    }

    /// Formats a spent/received label based on whether the category is a fee category.
    ///
    /// - Fee categories: "$X received"
    /// - All others: "$X spent"
    static func spentLabel(
        spentCents: Int,
        isFeeCategory: Bool
    ) -> String {
        let formatted = BudgetDisplayCalculations.formatCentsAsDollars(spentCents)
        return isFeeCategory ? "\(formatted) received" : "\(formatted) spent"
    }

    // MARK: - Pinning

    /// Reorders categories so pinned categories appear first (in the order
    /// specified by `pinnedCategoryIds`), followed by the remaining categories
    /// in their existing sort order.
    static func applyPinning(
        _ categories: [BudgetProgress.CategoryProgress],
        pinnedCategoryIds: [String]
    ) -> [BudgetProgress.CategoryProgress] {
        guard !pinnedCategoryIds.isEmpty else { return categories }

        let categoriesById = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let pinnedSet = Set(pinnedCategoryIds)

        // Pinned categories in user-defined order
        var pinned: [BudgetProgress.CategoryProgress] = []
        for id in pinnedCategoryIds {
            if let cat = categoriesById[id] {
                pinned.append(cat)
            }
        }

        // Remaining categories preserve existing sort order
        let remaining = categories.filter { !pinnedSet.contains($0.id) }

        return pinned + remaining
    }

    /// Returns only the categories whose IDs appear in `pinnedCategoryIds`,
    /// preserving the user's pin order. Silently skips IDs that don't match
    /// any category or categories with zero budget AND zero spending.
    static func pinnedCategories(
        allCategories: [BudgetProgress.CategoryProgress],
        pinnedCategoryIds: [String]
    ) -> [BudgetProgress.CategoryProgress] {
        guard !pinnedCategoryIds.isEmpty else { return [] }

        let categoriesById = Dictionary(
            uniqueKeysWithValues: allCategories.map { ($0.id, $0) }
        )

        return pinnedCategoryIds.compactMap { id in
            guard let category = categoriesById[id] else { return nil }
            guard category.budgetCents > 0 || category.spentCents != 0 else { return nil }
            return category
        }
    }

    // MARK: - Transaction-Based Spend Normalization

    /// Normalizes a single transaction's contribution to category spend.
    /// Dual-read path matching mcp-server/src/util/budget.ts `normalizeSpendAmount`.
    ///
    /// Cases (evaluated in order):
    /// 1. `status == .canceled` → 0
    /// 2. `type == .return` → -abs(amount)
    /// 3. `inventorySaleDirection` set → direction-based sign (covers both new
    ///    per-batch sales and legacy canonical sales):
    ///    - `.businessToProject` (inventory → project) → +abs(amount)
    ///    - `.projectToBusiness` (project → inventory) → -abs(amount)
    /// 4. Legacy canonical sale with no direction → amount as-stored
    /// 5. `type == .sale` with no direction → +abs(amount) (pre-direction per-batch)
    /// 6. Everything else (Purchase, etc.) → amount as-stored
    static func normalizeTransactionAmount(_ transaction: Transaction) -> Int {
        guard transaction.status != .canceled else { return 0 }

        let amount = transaction.amountCents ?? 0

        if transaction.transactionType == .return {
            return -abs(amount)
        }

        if let direction = transaction.inventorySaleDirection {
            switch direction {
            case .projectToBusiness:
                return -abs(amount)
            case .businessToProject:
                return abs(amount)
            }
        }

        if transaction.isCanonicalInventorySale == true {
            return amount
        }

        if transaction.transactionType == .sale {
            return abs(amount)
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
            .filter { !$0.isFeeCategory }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let fee = categories
            .filter { $0.isFeeCategory }
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
            let supported = category.resolvedSupportedTypes
            let isFee = category.isFeeCategory
            let exclude = category.metadata?.excludeFromOverallBudget ?? false
            let budget = budgetById[id] ?? 0
            let spent = computeSpend(for: id, transactions: transactions)

            let progress = BudgetProgress.CategoryProgress(
                id: id,
                name: category.name,
                budgetCents: budget,
                spentCents: spent,
                categoryType: catType,
                supportedTypes: supported,
                excludeFromOverallBudget: exclude
            )

            return BudgetCategoryRowData(
                id: id,
                category: progress,
                spentCents: spent,
                budgetCents: budget,
                isOverBudget: BudgetDisplayCalculations.isOverBudget(spent: spent, budget: budget),
                spendLabel: spentLabel(spentCents: spent, isFeeCategory: isFee),
                remainingLabel: remainingLabel(spentCents: spent, budgetCents: budget, isFeeCategory: isFee)
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
            spendLabel: spentLabel(spentCents: totalSpent, isFeeCategory: false),
            remainingLabel: remainingLabel(spentCents: totalSpent, budgetCents: totalBudget, isFeeCategory: false)
        )
    }
}
