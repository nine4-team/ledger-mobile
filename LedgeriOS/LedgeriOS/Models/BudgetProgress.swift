import Foundation

struct BudgetProgress {
    let totalBudgetCents: Int
    let totalSpentCents: Int
    let categories: [CategoryProgress]

    struct CategoryProgress: Identifiable {
        let id: String
        let name: String
        let budgetCents: Int
        let spentCents: Int
        /// Canonical category behavior for budget display.
        let categoryType: BudgetCategoryType
        let excludeFromOverallBudget: Bool
        /// True when a ProjectBudgetCategory document exists (user explicitly enabled this category).
        var isEnabled: Bool = true

        var isFeeCategory: Bool { categoryType == .fee }

        init(
            id: String,
            name: String,
            budgetCents: Int,
            spentCents: Int,
            categoryType: BudgetCategoryType,
            excludeFromOverallBudget: Bool,
            isEnabled: Bool = true
        ) {
            self.id = id
            self.name = name
            self.budgetCents = budgetCents
            self.spentCents = spentCents
            self.categoryType = categoryType
            self.excludeFromOverallBudget = excludeFromOverallBudget
            self.isEnabled = isEnabled
        }
    }
}
