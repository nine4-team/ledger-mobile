import Foundation

/// Pure formatting and calculation functions for BudgetCategoryTracker
/// and BudgetProgressPreview. Delegates to existing utilities where possible.
enum BudgetTrackerCalculations {

    /// Spent label — "$X spent" or "$X received" for fee categories.
    static func spentLabel(spentCents: Int, categoryType: BudgetCategoryType) -> String {
        BudgetTabCalculations.spentLabel(spentCents: spentCents, categoryType: categoryType)
    }

    /// Remaining label relative to budget.
    /// - Under/at budget: "$X remaining"
    /// - Over budget: "$X over" / "$X over received"
    /// - Zero budget: "No budget set"
    static func remainingLabel(spentCents: Int, budgetCents: Int, categoryType: BudgetCategoryType) -> String {
        guard budgetCents != 0 else { return "No budget set" }
        return BudgetTabCalculations.remainingLabel(
            spentCents: spentCents, budgetCents: budgetCents, categoryType: categoryType
        )
    }

    /// Progress as a percentage (0–100+). Can exceed 100 for overflow.
    /// Returns 0 when budget is zero.
    static func progressPercentage(spentCents: Int, budgetCents: Int) -> Double {
        guard budgetCents > 0 else { return 0 }
        return Double(spentCents) / Double(budgetCents) * 100
    }

    /// Whether spending exceeds the budget.
    static func isOverBudget(spentCents: Int, budgetCents: Int) -> Bool {
        BudgetDisplayCalculations.isOverBudget(spent: spentCents, budget: budgetCents)
    }

    /// Overflow percentage for ProgressBar — how far over budget (0–100).
    /// Returns 0 when not over budget.
    static func overflowPercentage(spentCents: Int, budgetCents: Int) -> Double {
        ProgressBarCalculations.overflowPercentage(spent: spentCents, budget: budgetCents)
    }
}
