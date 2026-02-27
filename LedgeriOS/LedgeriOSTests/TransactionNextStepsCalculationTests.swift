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
        hasEmailReceipt: Bool? = nil,
        purchasedBy: String? = nil,
        taxRatePct: Double? = nil
    ) -> Transaction {
        var txn = Transaction()
        txn.budgetCategoryId = budgetCategoryId
        txn.amountCents = amountCents
        txn.receiptImages = receiptImages
        txn.hasEmailReceipt = hasEmailReceipt
        txn.purchasedBy = purchasedBy
        txn.taxRatePct = taxRatePct
        return txn
    }

    private func makeCategory(type: BudgetCategoryType) -> BudgetCategory {
        var cat = BudgetCategory()
        cat.id = "cat1"
        cat.name = "Test"
        cat.metadata = BudgetCategoryMetadata(categoryType: type)
        return cat
    }

    // MARK: - 5-Step (non-itemized)

    @Test("Non-itemized category produces 5 steps (no tax rate step)")
    func fiveStepsNonItemized() {
        let txn = makeTransaction()
        let cat = makeCategory(type: .general)
        let steps = TransactionNextStepsCalculations.computeNextSteps(
            transaction: txn, category: cat, items: []
        )
        #expect(steps.count == 5)
        #expect(!steps.contains { $0.id == "tax-rate" })
    }

    @Test("Nil category produces 5 steps")
    func fiveStepsNilCategory() {
        let txn = makeTransaction()
        let steps = TransactionNextStepsCalculations.computeNextSteps(
            transaction: txn, category: nil, items: []
        )
        #expect(steps.count == 5)
    }

    // MARK: - 6-Step (itemized)

    @Test("Itemized category produces 6 steps including tax rate")
    func sixStepsItemized() {
        let txn = makeTransaction()
        let cat = makeCategory(type: .itemized)
        let steps = TransactionNextStepsCalculations.computeNextSteps(
            transaction: txn, category: cat, items: []
        )
        #expect(steps.count == 6)
        #expect(steps.last?.id == "tax-rate")
        #expect(steps.last?.title == "Set the tax rate")
    }

    // MARK: - Individual Step Completion

    @Test("Budget category step complete when budgetCategoryId set")
    func budgetCategoryComplete() {
        let txn = makeTransaction(budgetCategoryId: "cat123")
        let steps = TransactionNextStepsCalculations.computeNextSteps(
            transaction: txn, category: nil, items: []
        )
        #expect(steps.first { $0.id == "budget-category" }?.isComplete == true)
    }

    @Test("Amount step complete when amountCents is non-zero")
    func amountComplete() {
        let txn = makeTransaction(amountCents: 5000)
        let steps = TransactionNextStepsCalculations.computeNextSteps(
            transaction: txn, category: nil, items: []
        )
        #expect(steps.first { $0.id == "amount" }?.isComplete == true)
    }

    @Test("Amount step incomplete when amountCents is zero")
    func amountIncompleteZero() {
        let txn = makeTransaction(amountCents: 0)
        let steps = TransactionNextStepsCalculations.computeNextSteps(
            transaction: txn, category: nil, items: []
        )
        #expect(steps.first { $0.id == "amount" }?.isComplete == false)
    }

    @Test("Receipt step complete when receipt images exist")
    func receiptCompleteWithImages() {
        let ref = AttachmentRef(url: "https://example.com/receipt.jpg")
        let txn = makeTransaction(receiptImages: [ref])
        let steps = TransactionNextStepsCalculations.computeNextSteps(
            transaction: txn, category: nil, items: []
        )
        #expect(steps.first { $0.id == "receipt" }?.isComplete == true)
    }

    @Test("Receipt step complete when hasEmailReceipt is true")
    func receiptCompleteWithEmail() {
        let txn = makeTransaction(hasEmailReceipt: true)
        let steps = TransactionNextStepsCalculations.computeNextSteps(
            transaction: txn, category: nil, items: []
        )
        #expect(steps.first { $0.id == "receipt" }?.isComplete == true)
    }

    @Test("Items step complete when items array is non-empty")
    func itemsComplete() {
        let item = Item()
        let txn = makeTransaction()
        let steps = TransactionNextStepsCalculations.computeNextSteps(
            transaction: txn, category: nil, items: [item]
        )
        #expect(steps.first { $0.id == "items" }?.isComplete == true)
    }

    @Test("Purchased-by step complete when purchasedBy set")
    func purchasedByComplete() {
        let txn = makeTransaction(purchasedBy: "client-card")
        let steps = TransactionNextStepsCalculations.computeNextSteps(
            transaction: txn, category: nil, items: []
        )
        #expect(steps.first { $0.id == "purchased-by" }?.isComplete == true)
    }

    @Test("Tax rate step complete when taxRatePct set")
    func taxRateComplete() {
        let txn = makeTransaction(taxRatePct: 8.25)
        let cat = makeCategory(type: .itemized)
        let steps = TransactionNextStepsCalculations.computeNextSteps(
            transaction: txn, category: cat, items: []
        )
        #expect(steps.first { $0.id == "tax-rate" }?.isComplete == true)
    }

    // MARK: - allStepsComplete

    @Test("allStepsComplete returns true when all steps done")
    func allComplete() {
        let ref = AttachmentRef(url: "https://example.com/receipt.jpg")
        let txn = makeTransaction(
            budgetCategoryId: "cat1",
            amountCents: 5000,
            receiptImages: [ref],
            purchasedBy: "client-card"
        )
        let item = Item()
        let steps = TransactionNextStepsCalculations.computeNextSteps(
            transaction: txn, category: nil, items: [item]
        )
        #expect(TransactionNextStepsCalculations.allStepsComplete(steps))
    }

    @Test("allStepsComplete returns false when any step incomplete")
    func notAllComplete() {
        let txn = makeTransaction(budgetCategoryId: "cat1", amountCents: 5000)
        let steps = TransactionNextStepsCalculations.computeNextSteps(
            transaction: txn, category: nil, items: []
        )
        #expect(!TransactionNextStepsCalculations.allStepsComplete(steps))
    }

    @Test("allStepsComplete returns true for empty array")
    func emptySteps() {
        #expect(TransactionNextStepsCalculations.allStepsComplete([]))
    }
}
