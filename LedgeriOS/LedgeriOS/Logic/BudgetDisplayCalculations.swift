import Foundation

/// Pure functions for formatting and computing budget display values.
/// Used by BudgetProgressView and testable without SwiftUI.
enum BudgetDisplayCalculations {
    static func categoryComesBefore(name: String, isFee: Bool, otherName: String, otherIsFee: Bool) -> Bool {
        if isFee != otherIsFee { return !isFee }
        return name.localizedCaseInsensitiveCompare(otherName) == .orderedAscending
    }

    /// Existing Budget tab labels, shared without importing its legacy models.
    static func spentLabel(spentCents: Int, isFeeCategory: Bool) -> String {
        let formatted = formatCentsAsDollars(spentCents)
        return isFeeCategory ? "\(formatted) received" : "\(formatted) spent"
    }

    static func remainingLabel(spentCents: Int, budgetCents: Int, isFeeCategory: Bool) -> String {
        guard budgetCents != 0 else {
            return spentLabel(spentCents: spentCents, isFeeCategory: isFeeCategory)
        }
        if spentCents <= budgetCents {
            return "\(formatCentsAsDollars(budgetCents - spentCents)) remaining"
        }
        let suffix = isFeeCategory ? "over received" : "over"
        return "\(formatCentsAsDollars(spentCents - budgetCents)) \(suffix)"
    }

    /// Formats cents as whole dollars: 15000 → "$150"
    static func formatCentsAsDollars(_ cents: Int) -> String {
        let dollars = cents / 100
        return "$\(dollars)"
    }

    /// Formats cents with decimal places: 15099 → "$150.99"
    static func formatCentsWithDecimals(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        return String(format: "$%.2f", dollars)
    }

    /// Ratio of spent to budget, clamped to 0...1.
    /// Returns 0 when budget is zero or negative.
    static func budgetRatio(spent: Int, budget: Int) -> Double {
        guard budget > 0 else { return 0 }
        return min(max(Double(spent) / Double(budget), 0), 1)
    }

    /// Whether spending exceeds the budget.
    static func isOverBudget(spent: Int, budget: Int) -> Bool {
        guard budget > 0 else { return false }
        return spent > budget
    }

    /// Label like "Spent $500 of $1,000" or compact "$500 / $1,000"
    static func budgetProgressLabel(spent: Int, budget: Int, compact: Bool) -> String {
        let spentStr = formatCentsAsDollars(spent)
        let budgetStr = formatCentsAsDollars(budget)
        if compact {
            return "\(spentStr) / \(budgetStr)"
        }
        return "Spent \(spentStr) of \(budgetStr)"
    }

    /// Percentage label like "50%" or "150%".
    /// Returns "0%" when budget is zero.
    static func budgetPercentageLabel(spent: Int, budget: Int) -> String {
        guard budget > 0 else { return "0%" }
        let pct = Int(round(Double(spent) / Double(budget) * 100))
        return "\(pct)%"
    }
}
