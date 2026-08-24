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
        tx.status = .canceled

        #expect(service.normalizeSpendAmount(tx) == 0)
    }

    @Test("Normal transaction returns amount")
    func normalTransactionReturnsAmount() {
        var tx = Transaction()
        tx.amountCents = 5000

        #expect(service.normalizeSpendAmount(tx) == 5000)
    }

    @Test("Payment to business returns amount")
    func paymentToBusinessReturnsAmount() {
        var tx = Transaction()
        tx.amountCents = 5000
        tx.transactionType = .paymentToBusiness

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
        tx2.status = .canceled

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

@Suite("Fee Installment Tests")
struct FeeInstallmentTests {
    private let acct = "acc1"
    private let projectId = "proj1"

    private func makeProjectBudgetCategory(totalCents: Int?) -> ProjectBudgetCategory {
        var pbc = ProjectBudgetCategory()
        pbc.id = "fee-design"
        pbc.budgetCents = totalCents
        return pbc
    }

    private func makeInstallment(id: String, amountCents: Int, categoryId: String = "fee-design") -> FeeInstallment {
        var installment = FeeInstallment(
            accountId: acct,
            projectId: projectId,
            budgetCategoryId: categoryId,
            label: id,
            amountCents: amountCents
        )
        installment.id = id
        return installment
    }

    @Test("Fee installment totals are capped by project fee total")
    func installmentTotalsAreCappedByProjectFeeTotal() {
        let existing = [
            makeInstallment(id: "one", amountCents: 40_000),
            makeInstallment(id: "other-category", amountCents: 90_000, categoryId: "fee-other"),
        ]

        #expect(FeeInstallmentCalculations.invoicedCents(
            budgetCategoryId: "fee-design",
            installments: existing
        ) == 40_000)
        #expect(FeeInstallmentCalculations.toInvoiceCents(
            totalCents: 100_000,
            budgetCategoryId: "fee-design",
            installments: existing
        ) == 60_000)
        #expect(FeeInstallmentCalculations.canSave(
            amountCents: 60_000,
            totalCents: 100_000,
            budgetCategoryId: "fee-design",
            installments: existing
        ))
        #expect(!FeeInstallmentCalculations.canSave(
            amountCents: 60_001,
            totalCents: 100_000,
            budgetCategoryId: "fee-design",
            installments: existing
        ))
    }

    @Test("Fee installment update excludes current installment from cap")
    func updateExcludesCurrentInstallmentFromCap() {
        let existing = [
            makeInstallment(id: "one", amountCents: 40_000),
            makeInstallment(id: "two", amountCents: 20_000),
        ]

        #expect(FeeInstallmentCalculations.canSave(
            amountCents: 60_000,
            totalCents: 100_000,
            budgetCategoryId: "fee-design",
            installments: existing,
            excluding: "two"
        ))
        #expect(!FeeInstallmentCalculations.canSave(
            amountCents: 60_001,
            totalCents: 100_000,
            budgetCategoryId: "fee-design",
            installments: existing,
            excluding: "two"
        ))
    }

    @Test("FeeInstallmentsService create writes project-scoped installment")
    func createWritesProjectScopedInstallment() async throws {
        let batch = RecordingBatch()
        let service = FeeInstallmentsService(makeBatch: { batch })

        let id = try await service.createFeeInstallment(
            accountId: acct,
            projectId: projectId,
            budgetCategoryId: "fee-design",
            label: "Design Fee 1",
            amountCents: 50_000,
            sortOrder: 1,
            projectBudgetCategory: makeProjectBudgetCategory(totalCents: 100_000),
            existingInstallments: [],
            userId: "user1"
        )

        #expect(!id.isEmpty)
        #expect(batch.commitCalled)
        #expect(batch.sets.count == 1)
        let set = batch.sets[0]
        #expect(set.path == "accounts/\(acct)/projects/\(projectId)/feeInstallments/\(id)")
        #expect(set.fields["accountId"] as? String == acct)
        #expect(set.fields["projectId"] as? String == projectId)
        #expect(set.fields["budgetCategoryId"] as? String == "fee-design")
        #expect(set.fields["label"] as? String == "Design Fee 1")
        #expect(set.fields["amountCents"] as? Int == 50_000)
        #expect(set.fields["sortOrder"] as? Int == 1)
        #expect(set.fields["createdBy"] as? String == "user1")
        #expect(set.fields["updatedBy"] as? String == "user1")
        #expect(set.fields["createdAt"] != nil)
        #expect(set.fields["updatedAt"] != nil)
    }

    @Test("FeeInstallmentsService blocks amounts over project fee total")
    func createBlocksAmountOverProjectFeeTotal() async throws {
        let batch = RecordingBatch()
        let service = FeeInstallmentsService(makeBatch: { batch })

        do {
            _ = try await service.createFeeInstallment(
                accountId: acct,
                projectId: projectId,
                budgetCategoryId: "fee-design",
                label: "Too much",
                amountCents: 70_001,
                sortOrder: nil,
                projectBudgetCategory: makeProjectBudgetCategory(totalCents: 100_000),
                existingInstallments: [makeInstallment(id: "one", amountCents: 30_000)],
                userId: "user1"
            )
            Issue.record("Expected createFeeInstallment to reject an amount over the fee total")
        } catch FeeInstallmentsService.FeeInstallmentsServiceError.amountExceedsFeeTotal {
            #expect(batch.sets.isEmpty)
            #expect(!batch.commitCalled)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
