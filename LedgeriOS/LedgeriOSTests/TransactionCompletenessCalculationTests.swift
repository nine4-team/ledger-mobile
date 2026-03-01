import Foundation
import Testing
@testable import LedgeriOS

@Suite("Transaction Completeness Calculation Tests")
struct TransactionCompletenessCalculationTests {

    // MARK: - Helpers

    private func makeTransaction(
        subtotalCents: Int? = nil,
        amountCents: Int? = nil,
        taxRatePct: Double? = nil
    ) -> Transaction {
        var txn = Transaction()
        txn.subtotalCents = subtotalCents
        txn.amountCents = amountCents
        txn.taxRatePct = taxRatePct
        return txn
    }

    private func makeItem(purchasePriceCents: Int?) -> Item {
        var item = Item()
        item.purchasePriceCents = purchasePriceCents
        return item
    }

    // MARK: - Subtotal Resolution

    @Test("Subtotal resolution: explicit subtotal takes priority")
    func subtotalExplicit() {
        let txn = makeTransaction(subtotalCents: 10000, amountCents: 10825, taxRatePct: 8.25)
        let (subtotal, missingTax, _) = TransactionCompletenessCalculations.resolveSubtotal(transaction: txn)
        #expect(subtotal == 10000)
        #expect(missingTax == false)
    }

    @Test("Subtotal resolution: inferred from amount + tax rate")
    func subtotalInferred() {
        // amount=10825, taxRate=8.25% → subtotal = round(10825 / 1.0825) = round(10000.0) = 10000
        let txn = makeTransaction(amountCents: 10825, taxRatePct: 8.25)
        let (subtotal, missingTax, inferredTax) = TransactionCompletenessCalculations.resolveSubtotal(transaction: txn)
        #expect(subtotal == 10000)
        #expect(missingTax == false)
        #expect(inferredTax == 825)
    }

    @Test("Subtotal resolution: fallback to amountCents with missingTaxData")
    func subtotalFallback() {
        let txn = makeTransaction(amountCents: 5000)
        let (subtotal, missingTax, inferredTax) = TransactionCompletenessCalculations.resolveSubtotal(transaction: txn)
        #expect(subtotal == 5000)
        #expect(missingTax == true)
        #expect(inferredTax == nil)
    }

    @Test("Subtotal resolution: nil when no valid amounts")
    func subtotalNil() {
        let txn = makeTransaction()
        let (subtotal, _, _) = TransactionCompletenessCalculations.resolveSubtotal(transaction: txn)
        #expect(subtotal == nil)
    }

    @Test("Subtotal resolution: nil when amounts are zero")
    func subtotalZero() {
        let txn = makeTransaction(subtotalCents: 0, amountCents: 0)
        let (subtotal, _, _) = TransactionCompletenessCalculations.resolveSubtotal(transaction: txn)
        #expect(subtotal == nil)
    }

    @Test("Subtotal resolution: does not infer when taxRate is zero")
    func subtotalTaxRateZero() {
        let txn = makeTransaction(amountCents: 5000, taxRatePct: 0)
        let (subtotal, missingTax, _) = TransactionCompletenessCalculations.resolveSubtotal(transaction: txn)
        #expect(subtotal == 5000)
        #expect(missingTax == true) // Falls through to fallback
    }

    // MARK: - Items Net Total

    @Test("Items net total sums purchasePriceCents")
    func itemsNetTotal() {
        let items = [makeItem(purchasePriceCents: 1000), makeItem(purchasePriceCents: 2000), makeItem(purchasePriceCents: 3000)]
        #expect(TransactionCompletenessCalculations.computeItemsNetTotal(items: items) == 6000)
    }

    @Test("Items net total treats nil as zero")
    func itemsNetTotalNil() {
        let items = [makeItem(purchasePriceCents: 1000), makeItem(purchasePriceCents: nil)]
        #expect(TransactionCompletenessCalculations.computeItemsNetTotal(items: items) == 1000)
    }

    @Test("Items net total returns zero for empty array")
    func itemsNetTotalEmpty() {
        #expect(TransactionCompletenessCalculations.computeItemsNetTotal(items: []) == 0)
    }

    // MARK: - Completeness Status: over

    @Test("Status is .over when ratio > 1.2")
    func statusOver() {
        // subtotal=10000, items=13000 → ratio=1.3 → over
        let txn = makeTransaction(subtotalCents: 10000)
        let items = [makeItem(purchasePriceCents: 13000)]
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: txn, items: items)
        #expect(result.status == .over)
        #expect(result.ratio! > 1.2)
    }

    // MARK: - Completeness Status: complete

    @Test("Status is .complete when |variance%| <= 1%")
    func statusComplete() {
        // subtotal=10000, items=10050 → variance=0.5% → complete
        let txn = makeTransaction(subtotalCents: 10000)
        let items = [makeItem(purchasePriceCents: 10050)]
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: txn, items: items)
        #expect(result.status == .complete)
    }

    @Test("Status is .complete when items exactly match subtotal")
    func statusCompleteExact() {
        let txn = makeTransaction(subtotalCents: 10000)
        let items = [makeItem(purchasePriceCents: 10000)]
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: txn, items: items)
        #expect(result.status == .complete)
        #expect(result.ratio == 1.0)
        #expect(result.variancePct == 0.0)
    }

    // MARK: - Completeness Status: near

    @Test("Status is .near when |variance%| <= 20%")
    func statusNear() {
        // subtotal=10000, items=8500 → variance=-15% → near
        let txn = makeTransaction(subtotalCents: 10000)
        let items = [makeItem(purchasePriceCents: 8500)]
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: txn, items: items)
        #expect(result.status == .near)
    }

    // MARK: - Completeness Status: incomplete

    @Test("Status is .incomplete when |variance%| > 20%")
    func statusIncomplete() {
        // subtotal=10000, items=7000 → variance=-30% → incomplete
        let txn = makeTransaction(subtotalCents: 10000)
        let items = [makeItem(purchasePriceCents: 7000)]
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: txn, items: items)
        #expect(result.status == .incomplete)
    }

    // MARK: - Nil status

    @Test("Status is nil when no valid subtotal")
    func statusNil() {
        let txn = makeTransaction()
        let items = [makeItem(purchasePriceCents: 1000)]
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: txn, items: items)
        #expect(result.status == nil)
        #expect(result.ratio == nil)
        #expect(result.variancePct == nil)
        #expect(result.subtotalCents == nil)
        #expect(result.itemsNetTotalCents == 1000)
    }

    // MARK: - Missing Price Count

    @Test("Missing price count tracks items with nil or zero price")
    func missingPriceCount() {
        let items = [
            makeItem(purchasePriceCents: 1000),
            makeItem(purchasePriceCents: nil),
            makeItem(purchasePriceCents: 0),
            makeItem(purchasePriceCents: 500),
        ]
        let txn = makeTransaction(subtotalCents: 2000)
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: txn, items: items)
        #expect(result.itemsMissingPriceCount == 2)
        #expect(result.itemsCount == 4)
    }

    // MARK: - Threshold Order

    @Test("Threshold order: ratio 1.21 is over even though variance > 20%")
    func thresholdOverTakesPriority() {
        // subtotal=10000, items=12100 → ratio=1.21, variance=21% → over (not incomplete)
        let txn = makeTransaction(subtotalCents: 10000)
        let items = [makeItem(purchasePriceCents: 12100)]
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: txn, items: items)
        #expect(result.status == .over)
    }

    @Test("Threshold boundary: ratio exactly 1.2 is not over")
    func thresholdBoundary12() {
        // subtotal=10000, items=12000 → ratio=1.2 exactly → NOT over (<=1.2), variance=20% → near
        let txn = makeTransaction(subtotalCents: 10000)
        let items = [makeItem(purchasePriceCents: 12000)]
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: txn, items: items)
        #expect(result.status == .near)
    }

    @Test("Threshold boundary: |variance| exactly 1% is complete")
    func thresholdBoundary1Pct() {
        // subtotal=10000, items=10100 → variance=1.0% → complete (<=1%)
        let txn = makeTransaction(subtotalCents: 10000)
        let items = [makeItem(purchasePriceCents: 10100)]
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: txn, items: items)
        #expect(result.status == .complete)
    }

    @Test("Threshold boundary: |variance| exactly 20% is near")
    func thresholdBoundary20Pct() {
        // subtotal=10000, items=8000 → variance=-20% → near (<=20%)
        let txn = makeTransaction(subtotalCents: 10000)
        let items = [makeItem(purchasePriceCents: 8000)]
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: txn, items: items)
        #expect(result.status == .near)
    }

    // MARK: - Zero Items

    @Test("Zero items with valid subtotal gives incomplete")
    func zeroItems() {
        let txn = makeTransaction(subtotalCents: 10000)
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: txn, items: [])
        #expect(result.status == .incomplete)
        #expect(result.itemsNetTotalCents == 0)
        #expect(result.ratio == 0.0)
    }

    // MARK: - Inferred Tax Integration

    @Test("Inferred tax computed correctly in full result")
    func inferredTaxInResult() {
        let txn = makeTransaction(amountCents: 10825, taxRatePct: 8.25)
        let items = [makeItem(purchasePriceCents: 10000)]
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: txn, items: items)
        #expect(result.subtotalCents == 10000)
        #expect(result.inferredTaxCents == 825)
        #expect(result.missingTaxData == false)
        #expect(result.status == .complete)
    }
}
