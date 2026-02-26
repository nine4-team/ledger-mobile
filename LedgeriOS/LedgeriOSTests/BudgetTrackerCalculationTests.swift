import Foundation
import Testing
@testable import LedgeriOS

@Suite("Budget Tracker Calculation Tests")
struct BudgetTrackerCalculationTests {

    // MARK: - spentLabel

    @Test("General category shows spent")
    func spentLabelGeneral() {
        let label = BudgetTrackerCalculations.spentLabel(spentCents: 25000, categoryType: .general)
        #expect(label == "$250 spent")
    }

    @Test("Fee category shows received")
    func spentLabelFee() {
        let label = BudgetTrackerCalculations.spentLabel(spentCents: 10000, categoryType: .fee)
        #expect(label == "$100 received")
    }

    @Test("Zero spent shows $0")
    func spentLabelZero() {
        let label = BudgetTrackerCalculations.spentLabel(spentCents: 0, categoryType: .general)
        #expect(label == "$0 spent")
    }

    // MARK: - remainingLabel

    @Test("Under budget shows remaining")
    func remainingUnderBudget() {
        let label = BudgetTrackerCalculations.remainingLabel(
            spentCents: 30000, budgetCents: 50000, categoryType: .general
        )
        #expect(label == "$200 remaining")
    }

    @Test("Over budget shows over")
    func remainingOverBudget() {
        let label = BudgetTrackerCalculations.remainingLabel(
            spentCents: 60000, budgetCents: 50000, categoryType: .general
        )
        #expect(label == "$100 over")
    }

    @Test("Fee over budget shows over received")
    func remainingFeeOverBudget() {
        let label = BudgetTrackerCalculations.remainingLabel(
            spentCents: 60000, budgetCents: 50000, categoryType: .fee
        )
        #expect(label == "$100 over received")
    }

    @Test("Zero budget shows no budget set")
    func remainingZeroBudget() {
        let label = BudgetTrackerCalculations.remainingLabel(
            spentCents: 15000, budgetCents: 0, categoryType: .general
        )
        #expect(label == "No budget set")
    }

    @Test("At budget shows $0 remaining")
    func remainingAtBudget() {
        let label = BudgetTrackerCalculations.remainingLabel(
            spentCents: 50000, budgetCents: 50000, categoryType: .general
        )
        #expect(label == "$0 remaining")
    }

    // MARK: - progressPercentage

    @Test("50% progress")
    func progressHalf() {
        let pct = BudgetTrackerCalculations.progressPercentage(spentCents: 5000, budgetCents: 10000)
        #expect(pct == 50.0)
    }

    @Test("100% progress")
    func progressFull() {
        let pct = BudgetTrackerCalculations.progressPercentage(spentCents: 10000, budgetCents: 10000)
        #expect(pct == 100.0)
    }

    @Test("150% overflow progress")
    func progressOverflow() {
        let pct = BudgetTrackerCalculations.progressPercentage(spentCents: 15000, budgetCents: 10000)
        #expect(pct == 150.0)
    }

    @Test("Zero budget returns 0%")
    func progressZeroBudget() {
        let pct = BudgetTrackerCalculations.progressPercentage(spentCents: 5000, budgetCents: 0)
        #expect(pct == 0.0)
    }

    @Test("0% progress with zero spent")
    func progressZeroSpent() {
        let pct = BudgetTrackerCalculations.progressPercentage(spentCents: 0, budgetCents: 10000)
        #expect(pct == 0.0)
    }

    // MARK: - isOverBudget

    @Test("Equal to budget is not over")
    func isOverBudgetEqual() {
        #expect(!BudgetTrackerCalculations.isOverBudget(spentCents: 10000, budgetCents: 10000))
    }

    @Test("Just over budget is over")
    func isOverBudgetJustOver() {
        #expect(BudgetTrackerCalculations.isOverBudget(spentCents: 10001, budgetCents: 10000))
    }

    @Test("Zero budget is not over")
    func isOverBudgetZero() {
        #expect(!BudgetTrackerCalculations.isOverBudget(spentCents: 5000, budgetCents: 0))
    }

    // MARK: - overflowPercentage

    @Test("No overflow returns 0")
    func overflowNone() {
        let pct = BudgetTrackerCalculations.overflowPercentage(spentCents: 5000, budgetCents: 10000)
        #expect(pct == 0.0)
    }

    @Test("50% over budget returns 50")
    func overflowFiftyPercent() {
        let pct = BudgetTrackerCalculations.overflowPercentage(spentCents: 15000, budgetCents: 10000)
        #expect(pct == 50.0)
    }

    @Test("Overflow caps at 100")
    func overflowCapped() {
        let pct = BudgetTrackerCalculations.overflowPercentage(spentCents: 30000, budgetCents: 10000)
        #expect(pct == 100.0)
    }
}
