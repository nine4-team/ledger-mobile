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
        /// Legacy category-type field. Still populated during the taxonomy
        /// migration so readers haven't been swapped yet can find it. Phase 4
        /// removes this. Prefer `isFeeCategory` / `supportedTypes` going forward.
        let categoryType: BudgetCategoryType
        /// New-model transaction kinds this category accepts. Drives budget-tab
        /// coloring and labeling. See `docs/specs/transaction-type.md`. Derived
        /// from `categoryType` when callers haven't been migrated.
        let supportedTypes: [TransactionType]
        let excludeFromOverallBudget: Bool
        /// True when a ProjectBudgetCategory document exists (user explicitly enabled this category).
        var isEnabled: Bool = true

        var isFeeCategory: Bool { supportedTypes == [.fee] }

        init(
            id: String,
            name: String,
            budgetCents: Int,
            spentCents: Int,
            categoryType: BudgetCategoryType,
            supportedTypes: [TransactionType]? = nil,
            excludeFromOverallBudget: Bool,
            isEnabled: Bool = true
        ) {
            self.id = id
            self.name = name
            self.budgetCents = budgetCents
            self.spentCents = spentCents
            self.categoryType = categoryType
            self.supportedTypes = supportedTypes ?? Self.derive(from: categoryType)
            self.excludeFromOverallBudget = excludeFromOverallBudget
            self.isEnabled = isEnabled
        }

        private static func derive(from type: BudgetCategoryType) -> [TransactionType] {
            switch type {
            case .fee: return [.fee]
            case .expense: return [.expense]
            case .general: return [.expense]
            case .itemized: return [.purchase, .return]
            }
        }
    }
}
