import Foundation

/// Pure functions for filtering, sorting, and labeling budget categories
/// in the Budget tab. Testable without SwiftUI.
enum BudgetTabCalculations {

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
}
