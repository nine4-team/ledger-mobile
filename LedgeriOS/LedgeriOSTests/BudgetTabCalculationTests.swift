import Foundation
import Testing
@testable import LedgeriOS

@Suite("Budget Tab Calculation Tests")
struct BudgetTabCalculationTests {

    // MARK: - Test Helper

    private func makeCategoryProgress(
        id: String = "cat1",
        name: String = "Test",
        budgetCents: Int = 0,
        spentCents: Int = 0,
        categoryType: BudgetCategoryType = .general,
        excludeFromOverallBudget: Bool = false
    ) -> BudgetProgress.CategoryProgress {
        BudgetProgress.CategoryProgress(
            id: id, name: name, budgetCents: budgetCents,
            spentCents: spentCents, categoryType: categoryType,
            excludeFromOverallBudget: excludeFromOverallBudget
        )
    }

    // MARK: - enabledCategories

    @Test("Keeps category with nonzero budget")
    func enabledKeepsNonzeroBudget() {
        let categories = [makeCategoryProgress(budgetCents: 10000, spentCents: 0)]
        let result = BudgetTabCalculations.enabledCategories(allCategories: categories)
        #expect(result.count == 1)
    }

    @Test("Keeps category with zero budget but nonzero spending")
    func enabledKeepsNonzeroSpend() {
        let categories = [makeCategoryProgress(budgetCents: 0, spentCents: 500)]
        let result = BudgetTabCalculations.enabledCategories(allCategories: categories)
        #expect(result.count == 1)
    }

    @Test("Filters out zero-budget zero-spend categories")
    func enabledFiltersZeroBudgetZeroSpend() {
        let categories = [makeCategoryProgress(budgetCents: 0, spentCents: 0)]
        let result = BudgetTabCalculations.enabledCategories(allCategories: categories)
        #expect(result.isEmpty)
    }

    @Test("Empty input returns empty")
    func enabledEmptyInput() {
        let result = BudgetTabCalculations.enabledCategories(allCategories: [])
        #expect(result.isEmpty)
    }

    // MARK: - sortCategories

    @Test("Fee categories sort last")
    func sortFeeLastNonFeeFirst() {
        let categories = [
            makeCategoryProgress(id: "1", name: "Fees", categoryType: .fee),
            makeCategoryProgress(id: "2", name: "Materials", categoryType: .general),
        ]
        let result = BudgetTabCalculations.sortCategories(categories)
        #expect(result[0].id == "2")
        #expect(result[1].id == "1")
    }

    @Test("Within non-fee group, sorts alphabetically by name")
    func sortNonFeeAlphabetical() {
        let categories = [
            makeCategoryProgress(id: "1", name: "Lumber", categoryType: .general),
            makeCategoryProgress(id: "2", name: "Appliances", categoryType: .itemized),
            makeCategoryProgress(id: "3", name: "Drywall", categoryType: .general),
        ]
        let result = BudgetTabCalculations.sortCategories(categories)
        #expect(result.map(\.name) == ["Appliances", "Drywall", "Lumber"])
    }

    @Test("Within fee group, sorts alphabetically by name")
    func sortFeeAlphabetical() {
        let categories = [
            makeCategoryProgress(id: "1", name: "Permit Fee", categoryType: .fee),
            makeCategoryProgress(id: "2", name: "Architect Fee", categoryType: .fee),
            makeCategoryProgress(id: "3", name: "Materials", categoryType: .general),
        ]
        let result = BudgetTabCalculations.sortCategories(categories)
        #expect(result.map(\.name) == ["Materials", "Architect Fee", "Permit Fee"])
    }

    // MARK: - remainingLabel

    @Test("Under budget shows remaining")
    func remainingUnderBudget() {
        let label = BudgetTabCalculations.remainingLabel(
            spentCents: 30000, budgetCents: 50000, categoryType: .general
        )
        #expect(label == "$200 remaining")
    }

    @Test("Over budget shows over")
    func remainingOverBudget() {
        let label = BudgetTabCalculations.remainingLabel(
            spentCents: 60000, budgetCents: 50000, categoryType: .general
        )
        #expect(label == "$100 over")
    }

    @Test("Fee over budget shows over received")
    func remainingFeeOverBudget() {
        let label = BudgetTabCalculations.remainingLabel(
            spentCents: 60000, budgetCents: 50000, categoryType: .fee
        )
        #expect(label == "$100 over received")
    }

    @Test("Zero budget delegates to spent label")
    func remainingZeroBudgetDelegatesToSpent() {
        let label = BudgetTabCalculations.remainingLabel(
            spentCents: 15000, budgetCents: 0, categoryType: .general
        )
        #expect(label == "$150 spent")
    }

    // MARK: - spentLabel

    @Test("Non-fee category shows spent")
    func spentLabelGeneral() {
        let label = BudgetTabCalculations.spentLabel(
            spentCents: 25000, categoryType: .general
        )
        #expect(label == "$250 spent")
    }

    @Test("Fee category shows received")
    func spentLabelFee() {
        let label = BudgetTabCalculations.spentLabel(
            spentCents: 10000, categoryType: .fee
        )
        #expect(label == "$100 received")
    }
}
