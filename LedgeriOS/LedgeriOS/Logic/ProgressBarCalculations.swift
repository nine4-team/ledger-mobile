import Foundation

/// Pure functions for progress bar display calculations.
/// Used by ProgressBar and BudgetProgressView; testable without SwiftUI.
enum ProgressBarCalculations {

    /// Clamps a percentage value to 0...100.
    static func clampPercentage(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }

    /// Computes how far over budget as a percentage (0...100).
    /// Returns 0 when not over budget or budget is zero.
    static func overflowPercentage(spent: Int, budget: Int) -> Double {
        guard budget > 0, spent > budget else { return 0 }
        let overflow = Double(spent - budget) / Double(budget) * 100
        return min(overflow, 100)
    }
}
