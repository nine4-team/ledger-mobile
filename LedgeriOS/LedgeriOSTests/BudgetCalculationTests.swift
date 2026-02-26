import Foundation
import Testing
@testable import LedgeriOS

@Suite("Budget Calculation Tests")
struct BudgetCalculationTests {

    let service = BudgetProgressService()

    // MARK: - normalizeSpendAmount

    @Test("Canceled transaction returns zero")
    func canceledTransactionReturnsZero() {
        var tx = Transaction()
        tx.amountCents = 5000
        tx.isCanceled = true

        #expect(service.normalizeSpendAmount(tx) == 0)
    }

    @Test("Normal transaction returns amount")
    func normalTransactionReturnsAmount() {
        var tx = Transaction()
        tx.amountCents = 5000
        tx.isCanceled = false

        #expect(service.normalizeSpendAmount(tx) == 5000)
    }

    @Test("Nil amount returns zero")
    func nilAmountReturnsZero() {
        let tx = Transaction()
        #expect(service.normalizeSpendAmount(tx) == 0)
    }

    @Test("Inventory sale business-to-project is positive")
    func inventorySaleBusinessToProject() {
        var tx = Transaction()
        tx.amountCents = 3000
        tx.isCanonicalInventorySale = true
        tx.inventorySaleDirection = .businessToProject

        #expect(service.normalizeSpendAmount(tx) == 3000)
    }

    @Test("Inventory sale project-to-business is negative")
    func inventorySaleProjectToBusiness() {
        var tx = Transaction()
        tx.amountCents = 3000
        tx.isCanonicalInventorySale = true
        tx.inventorySaleDirection = .projectToBusiness

        #expect(service.normalizeSpendAmount(tx) == -3000)
    }

    @Test("Inventory sale with nil direction is positive")
    func inventorySaleNilDirection() {
        var tx = Transaction()
        tx.amountCents = 3000
        tx.isCanonicalInventorySale = true
        tx.inventorySaleDirection = nil

        #expect(service.normalizeSpendAmount(tx) == 3000)
    }

    // MARK: - buildBudgetProgress

    @Test("Empty inputs produce zero totals")
    func emptyInputsProduceZero() {
        let result = service.buildBudgetProgress(
            transactions: [],
            categories: [],
            projectBudgetCategories: []
        )

        #expect(result.totalBudgetCents == 0)
        #expect(result.totalSpentCents == 0)
        #expect(result.categories.isEmpty)
    }

    @Test("Archived categories are excluded")
    func archivedCategoriesExcluded() {
        var cat = BudgetCategory()
        cat.id = "cat1"
        cat.name = "Old Category"
        cat.isArchived = true

        let result = service.buildBudgetProgress(
            transactions: [],
            categories: [cat],
            projectBudgetCategories: []
        )

        #expect(result.categories.isEmpty)
    }

    @Test("Budget totals computed correctly")
    func budgetTotalsComputed() {
        var cat1 = BudgetCategory()
        cat1.id = "cat1"
        cat1.name = "Furniture"
        cat1.metadata = BudgetCategoryMetadata(categoryType: .general, excludeFromOverallBudget: false)

        var cat2 = BudgetCategory()
        cat2.id = "cat2"
        cat2.name = "Fees"
        cat2.metadata = BudgetCategoryMetadata(categoryType: .fee, excludeFromOverallBudget: false)

        var pbc1 = ProjectBudgetCategory()
        pbc1.id = "cat1"
        pbc1.budgetCents = 200000

        var pbc2 = ProjectBudgetCategory()
        pbc2.id = "cat2"
        pbc2.budgetCents = 50000

        let result = service.buildBudgetProgress(
            transactions: [],
            categories: [cat1, cat2],
            projectBudgetCategories: [pbc1, pbc2]
        )

        #expect(result.totalBudgetCents == 250000)
        #expect(result.categories.count == 2)
    }

    @Test("Excluded categories don't count toward overall")
    func excludedCategoriesDontCount() {
        var cat = BudgetCategory()
        cat.id = "cat1"
        cat.name = "Design Fee"
        cat.metadata = BudgetCategoryMetadata(categoryType: .general, excludeFromOverallBudget: true)

        var pbc = ProjectBudgetCategory()
        pbc.id = "cat1"
        pbc.budgetCents = 50000

        var tx = Transaction()
        tx.amountCents = 20000
        tx.budgetCategoryId = "cat1"

        let result = service.buildBudgetProgress(
            transactions: [tx],
            categories: [cat],
            projectBudgetCategories: [pbc]
        )

        #expect(result.totalBudgetCents == 0)
        #expect(result.totalSpentCents == 0)
        #expect(result.categories.count == 1)
        #expect(result.categories.first?.budgetCents == 50000)
        #expect(result.categories.first?.spentCents == 20000)
    }

    @Test("Spending aggregated by category")
    func spendingAggregatedByCategory() {
        var cat = BudgetCategory()
        cat.id = "cat1"
        cat.name = "Furniture"
        cat.metadata = BudgetCategoryMetadata(categoryType: .general, excludeFromOverallBudget: false)

        var pbc = ProjectBudgetCategory()
        pbc.id = "cat1"
        pbc.budgetCents = 100000

        var tx1 = Transaction()
        tx1.amountCents = 30000
        tx1.budgetCategoryId = "cat1"

        var tx2 = Transaction()
        tx2.amountCents = 20000
        tx2.budgetCategoryId = "cat1"

        let result = service.buildBudgetProgress(
            transactions: [tx1, tx2],
            categories: [cat],
            projectBudgetCategories: [pbc]
        )

        #expect(result.totalBudgetCents == 100000)
        #expect(result.totalSpentCents == 50000)
        #expect(result.categories.first?.spentCents == 50000)
    }

    @Test("Canceled transactions are excluded from spending")
    func canceledTransactionsExcluded() {
        var cat = BudgetCategory()
        cat.id = "cat1"
        cat.name = "Furniture"
        cat.metadata = BudgetCategoryMetadata(categoryType: .general, excludeFromOverallBudget: false)

        var pbc = ProjectBudgetCategory()
        pbc.id = "cat1"
        pbc.budgetCents = 100000

        var tx1 = Transaction()
        tx1.amountCents = 30000
        tx1.budgetCategoryId = "cat1"

        var tx2 = Transaction()
        tx2.amountCents = 20000
        tx2.budgetCategoryId = "cat1"
        tx2.isCanceled = true

        let result = service.buildBudgetProgress(
            transactions: [tx1, tx2],
            categories: [cat],
            projectBudgetCategories: [pbc]
        )

        #expect(result.totalSpentCents == 30000)
    }

    @Test("Transactions without category are not aggregated")
    func transactionsWithoutCategoryIgnored() {
        var cat = BudgetCategory()
        cat.id = "cat1"
        cat.name = "Furniture"
        cat.metadata = BudgetCategoryMetadata(categoryType: .general, excludeFromOverallBudget: false)

        var pbc = ProjectBudgetCategory()
        pbc.id = "cat1"
        pbc.budgetCents = 100000

        var tx = Transaction()
        tx.amountCents = 30000
        tx.budgetCategoryId = nil

        let result = service.buildBudgetProgress(
            transactions: [tx],
            categories: [cat],
            projectBudgetCategories: [pbc]
        )

        #expect(result.totalSpentCents == 0)
    }

    @Test("Multiple categories with mixed spending")
    func multipleCategoriesMixedSpending() {
        var cat1 = BudgetCategory()
        cat1.id = "cat1"
        cat1.name = "Furniture"
        cat1.metadata = BudgetCategoryMetadata(categoryType: .itemized, excludeFromOverallBudget: false)

        var cat2 = BudgetCategory()
        cat2.id = "cat2"
        cat2.name = "Labor"
        cat2.metadata = BudgetCategoryMetadata(categoryType: .general, excludeFromOverallBudget: false)

        var pbc1 = ProjectBudgetCategory()
        pbc1.id = "cat1"
        pbc1.budgetCents = 100000

        var pbc2 = ProjectBudgetCategory()
        pbc2.id = "cat2"
        pbc2.budgetCents = 50000

        var tx1 = Transaction()
        tx1.amountCents = 40000
        tx1.budgetCategoryId = "cat1"

        var tx2 = Transaction()
        tx2.amountCents = 25000
        tx2.budgetCategoryId = "cat2"

        let result = service.buildBudgetProgress(
            transactions: [tx1, tx2],
            categories: [cat1, cat2],
            projectBudgetCategories: [pbc1, pbc2]
        )

        #expect(result.totalBudgetCents == 150000)
        #expect(result.totalSpentCents == 65000)
        #expect(result.categories.count == 2)
    }
}
