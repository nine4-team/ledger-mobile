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
        let categoryType: BudgetCategoryType
        let excludeFromOverallBudget: Bool
    }
}
