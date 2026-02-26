import Foundation
import Testing
@testable import LedgeriOS

@Suite("Budget Display Calculation Tests")
struct BudgetDisplayCalculationTests {

    // MARK: - formatCentsAsDollars

    @Test("Formats positive cents as whole dollars")
    func formatPositiveCents() {
        #expect(BudgetDisplayCalculations.formatCentsAsDollars(15000) == "$150")
    }

    @Test("Formats zero cents")
    func formatZeroCents() {
        #expect(BudgetDisplayCalculations.formatCentsAsDollars(0) == "$0")
    }

    @Test("Formats cents that truncate remainder")
    func formatTruncatesRemainder() {
        #expect(BudgetDisplayCalculations.formatCentsAsDollars(15099) == "$150")
    }

    @Test("Formats negative cents")
    func formatNegativeCents() {
        #expect(BudgetDisplayCalculations.formatCentsAsDollars(-5000) == "$-50")
    }

    @Test("Formats large amount")
    func formatLargeAmount() {
        #expect(BudgetDisplayCalculations.formatCentsAsDollars(10_000_000) == "$100000")
    }

    // MARK: - formatCentsWithDecimals

    @Test("Formats cents with decimal places")
    func formatWithDecimals() {
        #expect(BudgetDisplayCalculations.formatCentsWithDecimals(15099) == "$150.99")
    }

    @Test("Formats zero with decimals")
    func formatZeroWithDecimals() {
        #expect(BudgetDisplayCalculations.formatCentsWithDecimals(0) == "$0.00")
    }

    @Test("Formats exact dollars with .00")
    func formatExactDollars() {
        #expect(BudgetDisplayCalculations.formatCentsWithDecimals(10000) == "$100.00")
    }

    @Test("Formats single cent")
    func formatSingleCent() {
        #expect(BudgetDisplayCalculations.formatCentsWithDecimals(1) == "$0.01")
    }

    // MARK: - budgetRatio

    @Test("Ratio at 50% spending")
    func ratioHalf() {
        #expect(BudgetDisplayCalculations.budgetRatio(spent: 500, budget: 1000) == 0.5)
    }

    @Test("Ratio at 0% spending")
    func ratioZeroSpent() {
        #expect(BudgetDisplayCalculations.budgetRatio(spent: 0, budget: 1000) == 0.0)
    }

    @Test("Ratio at 100% spending")
    func ratioFull() {
        #expect(BudgetDisplayCalculations.budgetRatio(spent: 1000, budget: 1000) == 1.0)
    }

    @Test("Ratio clamped to 1.0 when over budget")
    func ratioClampedOver() {
        #expect(BudgetDisplayCalculations.budgetRatio(spent: 1500, budget: 1000) == 1.0)
    }

    @Test("Ratio returns 0 when budget is zero")
    func ratioZeroBudget() {
        #expect(BudgetDisplayCalculations.budgetRatio(spent: 500, budget: 0) == 0.0)
    }

    @Test("Ratio returns 0 when budget is negative")
    func ratioNegativeBudget() {
        #expect(BudgetDisplayCalculations.budgetRatio(spent: 500, budget: -100) == 0.0)
    }

    @Test("Ratio clamps negative spending to 0")
    func ratioNegativeSpent() {
        #expect(BudgetDisplayCalculations.budgetRatio(spent: -100, budget: 1000) == 0.0)
    }

    // MARK: - isOverBudget

    @Test("Not over budget when equal")
    func notOverWhenEqual() {
        #expect(!BudgetDisplayCalculations.isOverBudget(spent: 1000, budget: 1000))
    }

    @Test("Over budget when exceeds")
    func overWhenExceeds() {
        #expect(BudgetDisplayCalculations.isOverBudget(spent: 1001, budget: 1000))
    }

    @Test("Not over budget with zero budget")
    func notOverWithZeroBudget() {
        #expect(!BudgetDisplayCalculations.isOverBudget(spent: 100, budget: 0))
    }

    @Test("Not over budget when under")
    func notOverWhenUnder() {
        #expect(!BudgetDisplayCalculations.isOverBudget(spent: 500, budget: 1000))
    }

    // MARK: - budgetProgressLabel

    @Test("Full label format")
    func fullLabel() {
        let label = BudgetDisplayCalculations.budgetProgressLabel(spent: 50000, budget: 100000, compact: false)
        #expect(label == "Spent $500 of $1000")
    }

    @Test("Compact label format")
    func compactLabel() {
        let label = BudgetDisplayCalculations.budgetProgressLabel(spent: 50000, budget: 100000, compact: true)
        #expect(label == "$500 / $1000")
    }

    @Test("Label with zero values")
    func labelZeroValues() {
        let label = BudgetDisplayCalculations.budgetProgressLabel(spent: 0, budget: 0, compact: false)
        #expect(label == "Spent $0 of $0")
    }

    // MARK: - budgetPercentageLabel

    @Test("Percentage at 50%")
    func percentageHalf() {
        #expect(BudgetDisplayCalculations.budgetPercentageLabel(spent: 500, budget: 1000) == "50%")
    }

    @Test("Percentage at 0%")
    func percentageZeroSpent() {
        #expect(BudgetDisplayCalculations.budgetPercentageLabel(spent: 0, budget: 1000) == "0%")
    }

    @Test("Percentage over 100%")
    func percentageOver() {
        #expect(BudgetDisplayCalculations.budgetPercentageLabel(spent: 1500, budget: 1000) == "150%")
    }

    @Test("Percentage with zero budget returns 0%")
    func percentageZeroBudget() {
        #expect(BudgetDisplayCalculations.budgetPercentageLabel(spent: 500, budget: 0) == "0%")
    }

    @Test("Percentage rounds correctly")
    func percentageRounding() {
        #expect(BudgetDisplayCalculations.budgetPercentageLabel(spent: 333, budget: 1000) == "33%")
    }
}
