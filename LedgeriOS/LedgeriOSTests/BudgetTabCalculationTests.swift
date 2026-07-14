import Foundation
import Testing
@testable import LedgeriOS

@Suite("Budget Tab Calculation Tests")
struct BudgetTabCalculationTests {

    // MARK: - Test Helpers

    private func makeCategoryProgress(
        id: String = "cat1",
        name: String = "Test",
        budgetCents: Int = 0,
        spentCents: Int = 0,
        categoryType: BudgetCategoryType = .general,
        excludeFromOverallBudget: Bool = false,
        isEnabled: Bool = true
    ) -> BudgetProgress.CategoryProgress {
        BudgetProgress.CategoryProgress(
            id: id, name: name, budgetCents: budgetCents,
            spentCents: spentCents, categoryType: categoryType,
            excludeFromOverallBudget: excludeFromOverallBudget,
            isEnabled: isEnabled
        )
    }

    private func makeTransaction(
        budgetCategoryId: String? = "cat1",
        amountCents: Int? = 10000,
        status: TransactionStatus? = nil,
        isCanonicalInventorySale: Bool? = nil,
        inventorySaleDirection: InventorySaleDirection? = nil
    ) -> Transaction {
        var tx = Transaction()
        tx.budgetCategoryId = budgetCategoryId
        tx.amountCents = amountCents
        tx.status = status
        tx.isCanonicalInventorySale = isCanonicalInventorySale
        tx.inventorySaleDirection = inventorySaleDirection
        return tx
    }

    private func makeBudgetCategory(
        id: String = "cat1",
        name: String = "Test",
        categoryType: BudgetCategoryType? = .general,
        excludeFromOverallBudget: Bool? = nil,
        isArchived: Bool? = nil
    ) -> BudgetCategory {
        var cat = BudgetCategory()
        cat.id = id
        cat.name = name
        cat.isArchived = isArchived
        cat.metadata = BudgetCategoryMetadata(
            categoryType: categoryType,
            excludeFromOverallBudget: excludeFromOverallBudget
        )
        return cat
    }

    private func makeProjectBudgetCategory(
        id: String = "cat1",
        budgetCents: Int? = 10000
    ) -> ProjectBudgetCategory {
        var pbc = ProjectBudgetCategory()
        pbc.id = id
        pbc.budgetCents = budgetCents
        return pbc
    }

    // MARK: - ProjectBudgetCategoryResolver

    @Test("Resolver returns account category definitions enabled by project rows")
    func resolverReturnsEnabledAccountCategories() {
        let categories = [
            makeBudgetCategory(id: "furnishings", name: "Furnishings"),
            makeBudgetCategory(id: "appliances", name: "Appliances"),
            makeBudgetCategory(id: "labor", name: "Labor")
        ]
        let rows = [
            makeProjectBudgetCategory(id: "furnishings"),
            makeProjectBudgetCategory(id: "labor")
        ]

        let result = ProjectBudgetCategoryResolver.resolve(
            projectBudgetCategoryRows: rows,
            accountBudgetCategories: categories
        )

        #expect(result.map(\.name) == ["Furnishings", "Labor"])
    }

    @Test("Resolver does not use account categories without a matching project row")
    func resolverRequiresProjectRow() {
        let result = ProjectBudgetCategoryResolver.resolve(
            projectBudgetCategoryRows: [makeProjectBudgetCategory(id: "furnishings")],
            accountBudgetCategories: [
                makeBudgetCategory(id: "furnishings", name: "Furnishings"),
                makeBudgetCategory(id: "not-enabled", name: "Not Enabled")
            ]
        )

        #expect(result.map(\.id) == ["furnishings"])
    }

    // MARK: - enabledCategories (CategoryProgress-based)

    @Test("Keeps enabled categories regardless of budget or spend")
    func enabledKeepsEnabledCategories() {
        let categories = [makeCategoryProgress(budgetCents: 0, spentCents: 0, isEnabled: true)]
        let result = BudgetTabCalculations.enabledCategories(allCategories: categories)
        #expect(result.count == 1)
    }

    @Test("Filters out non-enabled categories even with budget or spend")
    func enabledFiltersNonEnabledCategories() {
        let categories = [makeCategoryProgress(budgetCents: 10000, spentCents: 500, isEnabled: false)]
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
            spentCents: 30000, budgetCents: 50000, isFeeCategory: false
        )
        #expect(label == "$200 remaining")
    }

    @Test("Over budget shows over")
    func remainingOverBudget() {
        let label = BudgetTabCalculations.remainingLabel(
            spentCents: 60000, budgetCents: 50000, isFeeCategory: false
        )
        #expect(label == "$100 over")
    }

    @Test("Fee over budget shows over received")
    func remainingFeeOverBudget() {
        let label = BudgetTabCalculations.remainingLabel(
            spentCents: 60000, budgetCents: 50000, isFeeCategory: true
        )
        #expect(label == "$100 over received")
    }

    @Test("Zero budget delegates to spent label")
    func remainingZeroBudgetDelegatesToSpent() {
        let label = BudgetTabCalculations.remainingLabel(
            spentCents: 15000, budgetCents: 0, isFeeCategory: false
        )
        #expect(label == "$150 spent")
    }

    // MARK: - spentLabel

    @Test("Non-fee category shows spent")
    func spentLabelGeneral() {
        let label = BudgetTabCalculations.spentLabel(
            spentCents: 25000, isFeeCategory: false
        )
        #expect(label == "$250 spent")
    }

    @Test("Fee category shows received")
    func spentLabelFee() {
        let label = BudgetTabCalculations.spentLabel(
            spentCents: 10000, isFeeCategory: true
        )
        #expect(label == "$100 received")
    }

    // MARK: - normalizeTransactionAmount (Spend Normalization)

    @Test("Canceled transaction contributes zero")
    func canceledTransactionContributesZero() {
        let tx = makeTransaction(amountCents: 10000, status: .canceled)
        let result = BudgetTabCalculations.normalizeTransactionAmount(tx)
        #expect(result == 0)
    }

    @Test("Returned transaction subtracts from spend")
    func returnedTransactionSubtracts() {
        var tx = makeTransaction(amountCents: 5000)
        tx.transactionType = .return
        let result = BudgetTabCalculations.normalizeTransactionAmount(tx)
        #expect(result == -5000)
    }

    @Test("Negative amountCents subtracts from spend")
    func negativeAmountSubtracts() {
        let tx = makeTransaction(amountCents: -3000)
        let result = BudgetTabCalculations.normalizeTransactionAmount(tx)
        #expect(result == -3000)
    }

    @Test("Canonical sale project-to-business subtracts")
    func canonicalSaleProjectToBusinessSubtracts() {
        let tx = makeTransaction(
            amountCents: 8000,
            isCanonicalInventorySale: true,
            inventorySaleDirection: .projectToBusiness
        )
        let result = BudgetTabCalculations.normalizeTransactionAmount(tx)
        #expect(result == -8000)
    }

    @Test("Canonical sale business-to-project adds")
    func canonicalSaleBusinessToProjectAdds() {
        let tx = makeTransaction(
            amountCents: 8000,
            isCanonicalInventorySale: true,
            inventorySaleDirection: .businessToProject
        )
        let result = BudgetTabCalculations.normalizeTransactionAmount(tx)
        #expect(result == 8000)
    }

    @Test("Canonical sale with nil direction adds (safe default)")
    func canonicalSaleNilDirectionAdds() {
        let tx = makeTransaction(
            amountCents: 5000,
            isCanonicalInventorySale: true,
            inventorySaleDirection: nil
        )
        let result = BudgetTabCalculations.normalizeTransactionAmount(tx)
        #expect(result == 5000)
    }

    @Test("Normal transaction adds to spend")
    func normalTransactionAdds() {
        let tx = makeTransaction(amountCents: 15000)
        let result = BudgetTabCalculations.normalizeTransactionAmount(tx)
        #expect(result == 15000)
    }

    @Test("Canceled overrides returned status")
    func canceledOverridesReturned() {
        let tx = makeTransaction(amountCents: 5000, status: .canceled)
        let result = BudgetTabCalculations.normalizeTransactionAmount(tx)
        #expect(result == 0)
    }

    @Test("Canceled overrides canonical sale")
    func canceledOverridesCanonicalSale() {
        let tx = makeTransaction(
            amountCents: 5000,
            status: .canceled,
            isCanonicalInventorySale: true,
            inventorySaleDirection: .businessToProject
        )
        let result = BudgetTabCalculations.normalizeTransactionAmount(tx)
        #expect(result == 0)
    }

    @Test("Nil amountCents treated as zero")
    func nilAmountTreatedAsZero() {
        let tx = makeTransaction(amountCents: nil)
        let result = BudgetTabCalculations.normalizeTransactionAmount(tx)
        #expect(result == 0)
    }

    // MARK: - computeSpend

    @Test("Computes spend for category from matching transactions")
    func computeSpendForCategory() {
        let transactions = [
            makeTransaction(budgetCategoryId: "cat1", amountCents: 10000),
            makeTransaction(budgetCategoryId: "cat1", amountCents: 5000),
            makeTransaction(budgetCategoryId: "cat2", amountCents: 20000),
        ]
        let result = BudgetTabCalculations.computeSpend(for: "cat1", transactions: transactions)
        #expect(result == 15000)
    }

    @Test("Compute spend ignores transactions in other categories")
    func computeSpendIgnoresOtherCategories() {
        let transactions = [
            makeTransaction(budgetCategoryId: "cat2", amountCents: 20000),
        ]
        let result = BudgetTabCalculations.computeSpend(for: "cat1", transactions: transactions)
        #expect(result == 0)
    }

    @Test("Compute spend applies normalization rules")
    func computeSpendAppliesNormalization() {
        var returnTx = Transaction()
        returnTx.budgetCategoryId = "cat1"
        returnTx.amountCents = 3000
        returnTx.transactionType = .return
        let transactions = [
            makeTransaction(budgetCategoryId: "cat1", amountCents: 10000),
            makeTransaction(budgetCategoryId: "cat1", amountCents: 5000, status: .canceled),
            returnTx,
        ]
        let result = BudgetTabCalculations.computeSpend(for: "cat1", transactions: transactions)
        // 10000 + 0 + (-3000) = 7000
        #expect(result == 7000)
    }

    // MARK: - Fee category label

    @Test("Fee category label is received")
    func feeCategoryLabelIsReceived() {
        let label = BudgetTabCalculations.spentLabel(spentCents: 5000, isFeeCategory: true)
        #expect(label == "$50 received")
    }

    @Test("General category label is spent")
    func generalCategoryLabelIsSpent() {
        let label = BudgetTabCalculations.spentLabel(spentCents: 5000, isFeeCategory: false)
        #expect(label == "$50 spent")
    }

    // MARK: - Fee categories sort last (raw)

    @Test("Fee categories sort last in raw category sort")
    func feeCategoriesSortLastRaw() {
        let categories = [
            makeBudgetCategory(id: "fee1", name: "Design Fee", categoryType: .fee),
            makeBudgetCategory(id: "gen1", name: "Materials", categoryType: .general),
            makeBudgetCategory(id: "gen2", name: "Appliances", categoryType: .general),
        ]
        let result = BudgetTabCalculations.sortRawCategories(categories)
        #expect(result.map(\.name) == ["Appliances", "Materials", "Design Fee"])
    }

    // MARK: - Overall budget exclusion

    @Test("Overall budget excludes excluded categories")
    func overallBudgetExcludesExcludedCategories() {
        let rows = [
            BudgetCategoryRowData(
                id: "cat1",
                category: makeCategoryProgress(id: "cat1", budgetCents: 10000, spentCents: 5000, excludeFromOverallBudget: true),
                spentCents: 5000, budgetCents: 10000, isOverBudget: false,
                spendLabel: "$50 spent", remainingLabel: "$50 remaining"
            ),
            BudgetCategoryRowData(
                id: "cat2",
                category: makeCategoryProgress(id: "cat2", budgetCents: 20000, spentCents: 15000, excludeFromOverallBudget: false),
                spentCents: 15000, budgetCents: 20000, isOverBudget: false,
                spendLabel: "$150 spent", remainingLabel: "$50 remaining"
            ),
        ]
        let overall = BudgetTabCalculations.overallBudgetRow(rows: rows)
        // Only cat2 is included (not excluded)
        #expect(overall.spentCents == 15000)
        #expect(overall.budgetCents == 20000)
    }

    @Test("Overall budget includes non-excluded categories")
    func overallBudgetIncludesNonExcludedCategories() {
        let rows = [
            BudgetCategoryRowData(
                id: "cat1",
                category: makeCategoryProgress(id: "cat1", budgetCents: 10000, spentCents: 5000, excludeFromOverallBudget: false),
                spentCents: 5000, budgetCents: 10000, isOverBudget: false,
                spendLabel: "$50 spent", remainingLabel: "$50 remaining"
            ),
            BudgetCategoryRowData(
                id: "cat2",
                category: makeCategoryProgress(id: "cat2", budgetCents: 20000, spentCents: 8000, excludeFromOverallBudget: false),
                spentCents: 8000, budgetCents: 20000, isOverBudget: false,
                spendLabel: "$80 spent", remainingLabel: "$120 remaining"
            ),
        ]
        let overall = BudgetTabCalculations.overallBudgetRow(rows: rows)
        #expect(overall.spentCents == 13000)
        #expect(overall.budgetCents == 30000)
    }

    // MARK: - Enabled category filter (raw models)

    @Test("Enabled category filter excludes zero budget zero spend")
    func enabledCategoryFilter() {
        let categories = [
            makeBudgetCategory(id: "active", name: "Active", categoryType: .general),
            makeBudgetCategory(id: "empty", name: "Empty", categoryType: .general),
        ]
        let projectBudgetCategories = [
            makeProjectBudgetCategory(id: "active", budgetCents: 10000),
            makeProjectBudgetCategory(id: "empty", budgetCents: 0),
        ]
        let transactions: [Transaction] = []
        let result = BudgetTabCalculations.enabledRawCategories(
            categories,
            projectBudgetCategories: projectBudgetCategories,
            transactions: transactions
        )
        #expect(result.count == 1)
        #expect(result[0].id == "active")
    }

    @Test("Enabled category filter excludes archived categories")
    func enabledCategoryFilterExcludesArchived() {
        let categories = [
            makeBudgetCategory(id: "active", name: "Active", categoryType: .general),
            makeBudgetCategory(id: "archived", name: "Archived", categoryType: .general, isArchived: true),
        ]
        let projectBudgetCategories = [
            makeProjectBudgetCategory(id: "active", budgetCents: 10000),
            makeProjectBudgetCategory(id: "archived", budgetCents: 10000),
        ]
        let result = BudgetTabCalculations.enabledRawCategories(
            categories,
            projectBudgetCategories: projectBudgetCategories,
            transactions: []
        )
        #expect(result.count == 1)
        #expect(result[0].id == "active")
    }

    // MARK: - applyPinning

    @Test("Pinned categories move to top in user-defined order")
    func applyPinningMovesToTop() {
        let categories = [
            makeCategoryProgress(id: "a", name: "Appliances"),
            makeCategoryProgress(id: "b", name: "Furniture"),
            makeCategoryProgress(id: "c", name: "Materials"),
        ]
        let result = BudgetTabCalculations.applyPinning(categories, pinnedCategoryIds: ["c", "a"])
        #expect(result.map(\.id) == ["c", "a", "b"])
    }

    @Test("Empty pinned list preserves existing order")
    func applyPinningEmptyPreservesOrder() {
        let categories = [
            makeCategoryProgress(id: "a", name: "Appliances"),
            makeCategoryProgress(id: "b", name: "Furniture"),
        ]
        let result = BudgetTabCalculations.applyPinning(categories, pinnedCategoryIds: [])
        #expect(result.map(\.id) == ["a", "b"])
    }

    @Test("Pinned ID not in categories is safely ignored")
    func applyPinningIgnoresMissingIds() {
        let categories = [
            makeCategoryProgress(id: "a", name: "Appliances"),
            makeCategoryProgress(id: "b", name: "Furniture"),
        ]
        let result = BudgetTabCalculations.applyPinning(categories, pinnedCategoryIds: ["nonexistent", "a"])
        #expect(result.map(\.id) == ["a", "b"])
    }

    @Test("All categories pinned returns all in pinned order")
    func applyPinningAllPinned() {
        let categories = [
            makeCategoryProgress(id: "a", name: "Appliances"),
            makeCategoryProgress(id: "b", name: "Furniture"),
        ]
        let result = BudgetTabCalculations.applyPinning(categories, pinnedCategoryIds: ["b", "a"])
        #expect(result.map(\.id) == ["b", "a"])
    }

    // MARK: - buildBudgetRows

    @Test("Build budget rows produces correct output")
    func buildBudgetRowsProducesCorrectOutput() {
        let categories = [
            makeBudgetCategory(id: "cat1", name: "Materials", categoryType: .general),
            makeBudgetCategory(id: "cat2", name: "Design Fee", categoryType: .fee),
        ]
        let projectBudgetCategories = [
            makeProjectBudgetCategory(id: "cat1", budgetCents: 50000),
            makeProjectBudgetCategory(id: "cat2", budgetCents: 20000),
        ]
        let transactions = [
            makeTransaction(budgetCategoryId: "cat1", amountCents: 30000),
            makeTransaction(budgetCategoryId: "cat2", amountCents: 25000),
        ]
        let rows = BudgetTabCalculations.buildBudgetRows(
            categories: categories,
            projectBudgetCategories: projectBudgetCategories,
            transactions: transactions
        )
        #expect(rows.count == 2)
        // Non-fee first (Materials), fee last (Design Fee)
        #expect(rows[0].id == "cat1")
        #expect(rows[0].spentCents == 30000)
        #expect(rows[0].spendLabel == "$300 spent")
        #expect(rows[1].id == "cat2")
        #expect(rows[1].spentCents == 25000)
        #expect(rows[1].spendLabel == "$250 received")
        #expect(rows[1].isOverBudget == true)
    }
}
