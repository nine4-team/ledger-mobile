import Foundation
import Testing
@testable import LedgeriOS

@Suite("Transaction Next Steps Calculation Tests")
struct TransactionNextStepsCalculationTests {

    // MARK: - Helpers

    private func makeTransaction(
        budgetCategoryId: String? = nil,
        amountCents: Int? = nil,
        receiptImages: [AttachmentRef]? = nil,
        purchasedBy: String? = nil,
        taxRatePct: Double? = nil
    ) -> Transaction {
        var tx = Transaction()
        tx.budgetCategoryId = budgetCategoryId
        tx.amountCents = amountCents
        tx.receiptImages = receiptImages
        tx.purchasedBy = purchasedBy
        tx.taxRatePct = taxRatePct
        return tx
    }

    private func makeCategory(id: String, type: BudgetCategoryType = .general) -> BudgetCategory {
        var cat = BudgetCategory()
        cat.id = id
        cat.name = "Test Category"
        cat.metadata = BudgetCategoryMetadata(categoryType: type, excludeFromOverallBudget: false)
        return cat
    }

    // MARK: - 5-step path (non-itemized category)

    @Test("5-step path: all steps incomplete")
    func fiveStepAllIncomplete() {
        let tx = makeTransaction()
        let steps = TransactionNextStepsCalculations.computeNextSteps(
            transaction: tx,
            itemCount: 0,
            budgetCategories: [:]
        )
        #expect(steps.count == 5)
        #expect(steps.allSatisfy { !$0.completed })
    }

    @Test("5-step path: all steps complete")
    func fiveStepAllComplete() {
        let cat = makeCategory(id: "cat1", type: .general)
        let tx = makeTransaction(
            budgetCategoryId: "cat1",
            amountCents: 5000,
            receiptImages: [AttachmentRef(url: "r1")],
            purchasedBy: "Alice"
        )
        let steps = TransactionNextStepsCalculations.computeNextSteps(
            transaction: tx,
            itemCount: 1,
            budgetCategories: ["cat1": cat]
        )
        #expect(steps.count == 5)
        #expect(TransactionNextStepsCalculations.allStepsComplete(steps))
    }

    @Test("5-step path: budget category step completed")
    func fiveStepBudgetCategoryComplete() {
        let cat = makeCategory(id: "cat1", type: .general)
        let tx = makeTransaction(budgetCategoryId: "cat1")
        let steps = TransactionNextStepsCalculations.computeNextSteps(
            transaction: tx,
            itemCount: 0,
            budgetCategories: ["cat1": cat]
        )
        let budgetStep = steps.first { $0.id == "budget-category" }
        #expect(budgetStep?.completed == true)
    }

    @Test("5-step path: amount step completed when positive")
    func fiveStepAmountComplete() {
        let tx = makeTransaction(amountCents: 1)
        let steps = TransactionNextStepsCalculations.computeNextSteps(
            transaction: tx,
            itemCount: 0,
            budgetCategories: [:]
        )
        let amountStep = steps.first { $0.id == "amount" }
        #expect(amountStep?.completed == true)
    }

    @Test("5-step path: amount step incomplete when zero")
    func fiveStepAmountZero() {
        let tx = makeTransaction(amountCents: 0)
        let steps = TransactionNextStepsCalculations.computeNextSteps(
            transaction: tx,
            itemCount: 0,
            budgetCategories: [:]
        )
        let amountStep = steps.first { $0.id == "amount" }
        #expect(amountStep?.completed == false)
    }

    @Test("5-step path: receipt step completed when images present")
    func fiveStepReceiptComplete() {
        let tx = makeTransaction(receiptImages: [AttachmentRef(url: "img/r1")])
        let steps = TransactionNextStepsCalculations.computeNextSteps(
            transaction: tx,
            itemCount: 0,
            budgetCategories: [:]
        )
        let receiptStep = steps.first { $0.id == "receipt" }
        #expect(receiptStep?.completed == true)
    }

    @Test("5-step path: items step completed when itemCount > 0")
    func fiveStepItemsComplete() {
        let steps = TransactionNextStepsCalculations.computeNextSteps(
            transaction: makeTransaction(),
            itemCount: 3,
            budgetCategories: [:]
        )
        let itemsStep = steps.first { $0.id == "items" }
        #expect(itemsStep?.completed == true)
    }

    @Test("5-step path: purchased-by step completed when set")
    func fiveStepPurchasedByComplete() {
        let tx = makeTransaction(purchasedBy: "client-card")
        let steps = TransactionNextStepsCalculations.computeNextSteps(
            transaction: tx,
            itemCount: 0,
            budgetCategories: [:]
        )
        let pbStep = steps.first { $0.id == "purchased-by" }
        #expect(pbStep?.completed == true)
    }

    @Test("5-step path: whitespace-only purchasedBy is incomplete")
    func fiveStepPurchasedByWhitespace() {
        let tx = makeTransaction(purchasedBy: "   ")
        let steps = TransactionNextStepsCalculations.computeNextSteps(
            transaction: tx,
            itemCount: 0,
            budgetCategories: [:]
        )
        let pbStep = steps.first { $0.id == "purchased-by" }
        #expect(pbStep?.completed == false)
    }

    @Test("5-step path: no tax-rate step for non-itemized category")
    func fiveStepNoTaxStepForGeneralCategory() {
        let cat = makeCategory(id: "cat1", type: .general)
        let tx = makeTransaction(budgetCategoryId: "cat1")
        let steps = TransactionNextStepsCalculations.computeNextSteps(
            transaction: tx,
            itemCount: 0,
            budgetCategories: ["cat1": cat]
        )
        #expect(steps.count == 5)
        #expect(!steps.contains { $0.id == "tax-rate" })
    }

    // MARK: - 6-step path (itemized category)

    @Test("6-step path: tax-rate step added for itemized category")
    func sixStepTaxRateStepPresent() {
        let cat = makeCategory(id: "cat1", type: .itemized)
        let tx = makeTransaction(budgetCategoryId: "cat1")
        let steps = TransactionNextStepsCalculations.computeNextSteps(
            transaction: tx,
            itemCount: 0,
            budgetCategories: ["cat1": cat]
        )
        #expect(steps.count == 6)
        #expect(steps.last?.id == "tax-rate")
    }

    @Test("6-step path: tax-rate step incomplete when zero")
    func sixStepTaxRateIncomplete() {
        let cat = makeCategory(id: "cat1", type: .itemized)
        let tx = makeTransaction(budgetCategoryId: "cat1", taxRatePct: 0)
        let steps = TransactionNextStepsCalculations.computeNextSteps(
            transaction: tx,
            itemCount: 0,
            budgetCategories: ["cat1": cat]
        )
        let taxStep = steps.first { $0.id == "tax-rate" }
        #expect(taxStep?.completed == false)
    }

    @Test("6-step path: tax-rate step complete when positive")
    func sixStepTaxRateComplete() {
        let cat = makeCategory(id: "cat1", type: .itemized)
        let tx = makeTransaction(budgetCategoryId: "cat1", taxRatePct: 8.5)
        let steps = TransactionNextStepsCalculations.computeNextSteps(
            transaction: tx,
            itemCount: 0,
            budgetCategories: ["cat1": cat]
        )
        let taxStep = steps.first { $0.id == "tax-rate" }
        #expect(taxStep?.completed == true)
    }

    @Test("6-step path: no tax-rate step when category not in map")
    func sixStepNoTaxStepWhenCategoryMissing() {
        let tx = makeTransaction(budgetCategoryId: "missing-cat")
        let steps = TransactionNextStepsCalculations.computeNextSteps(
            transaction: tx,
            itemCount: 0,
            budgetCategories: [:]
        )
        // Category not found → hasBudgetCategory is false → no 6th step
        #expect(steps.count == 5)
    }

    // MARK: - allStepsComplete

    @Test("allStepsComplete returns true when all done")
    func allStepsCompleteTrue() {
        let cat = makeCategory(id: "cat1", type: .general)
        let tx = makeTransaction(
            budgetCategoryId: "cat1",
            amountCents: 5000,
            receiptImages: [AttachmentRef(url: "r1")],
            purchasedBy: "Alice"
        )
        let steps = TransactionNextStepsCalculations.computeNextSteps(
            transaction: tx,
            itemCount: 1,
            budgetCategories: ["cat1": cat]
        )
        #expect(TransactionNextStepsCalculations.allStepsComplete(steps))
    }

    @Test("allStepsComplete returns false when any step incomplete")
    func allStepsCompleteFalse() {
        let tx = makeTransaction(amountCents: 5000)
        let steps = TransactionNextStepsCalculations.computeNextSteps(
            transaction: tx,
            itemCount: 0,
            budgetCategories: [:]
        )
        #expect(!TransactionNextStepsCalculations.allStepsComplete(steps))
    }

    @Test("allStepsComplete returns false for empty array")
    func allStepsCompleteEmptyArray() {
        #expect(!TransactionNextStepsCalculations.allStepsComplete([]))
    }
}
