import Foundation
import SwiftUI

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

    // MARK: - Threshold Colors

    /// Progress bar fill color based on spend percentage and category type.
    /// Normal budgets: green < 50%, yellow 50–74%, red ≥ 75%.
    /// Fee categories: reversed — green ≥ 75%, yellow 50–74%, red < 50%.
    static func progressColor(percentage: Double, categoryType: BudgetCategoryType) -> Color {
        if categoryType == .fee {
            if percentage >= 75 { return StatusColors.metBarComplete }
            if percentage >= 50 { return StatusColors.inProgressBar }
            return StatusColors.atRiskBar
        }
        if percentage >= 75 { return StatusColors.atRiskBar }
        if percentage >= 50 { return StatusColors.inProgressBar }
        return StatusColors.metBarComplete
    }

    /// Remaining-label text color based on spend percentage and category type.
    /// Same thresholds as progressColor, but uses systemRed when actually over budget
    /// for better text legibility in both light and dark modes.
    static func remainingTextColor(percentage: Double, categoryType: BudgetCategoryType) -> Color {
        if categoryType == .fee {
            if percentage >= 75 { return StatusColors.metBarComplete }
            if percentage >= 50 { return StatusColors.inProgressBar }
            return percentage > 100 ? Color(.systemRed) : StatusColors.atRiskBar
        }
        if percentage > 100 { return Color(.systemRed) }
        if percentage >= 75 { return StatusColors.atRiskBar }
        if percentage >= 50 { return StatusColors.inProgressBar }
        return StatusColors.metBarComplete
    }
}
