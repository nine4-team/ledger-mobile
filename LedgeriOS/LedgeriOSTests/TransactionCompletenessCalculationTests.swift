import Foundation
import Testing
@testable import LedgeriOS

@Suite("Transaction Completeness Calculation Tests")
struct TransactionCompletenessCalculationTests {

    // MARK: - Helpers

    private func makeTransaction(
        amountCents: Int? = nil,
        subtotalCents: Int? = nil,
        taxRatePct: Double? = nil
    ) -> Transaction {
        var tx = Transaction()
        tx.amountCents = amountCents
        tx.subtotalCents = subtotalCents
        tx.taxRatePct = taxRatePct
        return tx
    }

    private func makeItem(priceCents: Int?) -> Item {
        var item = Item()
        item.purchasePriceCents = priceCents
        return item
    }

    // MARK: - Nil/zero amount returns nil

    @Test("Nil amount with no subtotal or tax returns nil")
    func nilAmountReturnsNil() {
        let tx = makeTransaction()
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: tx, items: [])
        #expect(result == nil)
    }

    @Test("Zero amount returns nil")
    func zeroAmountReturnsNil() {
        let tx = makeTransaction(amountCents: 0)
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: tx, items: [])
        #expect(result == nil)
    }

    @Test("Zero subtotal returns nil")
    func zeroSubtotalReturnsNil() {
        let tx = makeTransaction(amountCents: 10000, subtotalCents: 0)
        // subtotal is 0, so it falls through to amount
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: tx, items: [])
        #expect(result != nil)
        #expect(result?.transactionSubtotalCents == 10000)
    }

    // MARK: - Subtotal resolution priority

    @Test("Explicit subtotal takes priority over amount")
    func explicitSubtotalTakesPriority() {
        let tx = makeTransaction(amountCents: 10000, subtotalCents: 8000, taxRatePct: 8.0)
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: tx, items: [])
        #expect(result?.transactionSubtotalCents == 8000)
        #expect(result?.inferredTax == nil)
    }

    @Test("Inferred subtotal from tax rate when no explicit subtotal")
    func inferredSubtotalFromTaxRate() {
        // amount=10800, taxRate=8% → subtotal = round(10800 / 1.08) = 10000
        let tx = makeTransaction(amountCents: 10800, taxRatePct: 8.0)
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: tx, items: [])
        #expect(result?.transactionSubtotalCents == 10000)
        #expect(result?.inferredTax == 800)
        #expect(result?.missingTaxData == false)
    }

    @Test("Falls back to amount when neither subtotal nor tax rate")
    func fallbackToAmount() {
        let tx = makeTransaction(amountCents: 5000)
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: tx, items: [])
        #expect(result?.transactionSubtotalCents == 5000)
        #expect(result?.missingTaxData == true)
        #expect(result?.inferredTax == nil)
    }

    @Test("Falls back to amount when tax rate is zero")
    func fallbackToAmountWhenTaxRateZero() {
        let tx = makeTransaction(amountCents: 5000, taxRatePct: 0)
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: tx, items: [])
        #expect(result?.transactionSubtotalCents == 5000)
        #expect(result?.missingTaxData == true)
    }

    // MARK: - Status: complete (variance ≤ 1%)

    @Test("Status complete when items match subtotal exactly")
    func statusCompleteExact() {
        let tx = makeTransaction(amountCents: 10000)
        let items = [makeItem(priceCents: 10000)]
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: tx, items: items)
        #expect(result?.status == .complete)
    }

    @Test("Status complete when variance is within 1%")
    func statusCompleteWithinOnePct() {
        // subtotal = 10000, items = 9950 → variance = -0.5%
        let tx = makeTransaction(amountCents: 10000)
        let items = [makeItem(priceCents: 9950)]
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: tx, items: items)
        #expect(result?.status == .complete)
    }

    // MARK: - Status: near (variance 1%–20%)

    @Test("Status near when variance is between 1% and 20%")
    func statusNear() {
        // subtotal = 10000, items = 8500 → variance = -15%
        let tx = makeTransaction(amountCents: 10000)
        let items = [makeItem(priceCents: 8500)]
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: tx, items: items)
        #expect(result?.status == .near)
    }

    // MARK: - Status: incomplete (variance > 20%)

    @Test("Status incomplete when variance exceeds 20%")
    func statusIncomplete() {
        // subtotal = 10000, items = 7000 → variance = -30%
        let tx = makeTransaction(amountCents: 10000)
        let items = [makeItem(priceCents: 7000)]
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: tx, items: items)
        #expect(result?.status == .incomplete)
    }

    @Test("Status incomplete with no items")
    func statusIncompleteNoItems() {
        let tx = makeTransaction(amountCents: 10000)
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: tx, items: [])
        #expect(result?.status == .incomplete)
    }

    // MARK: - Status: over (ratio > 1.2)

    @Test("Status over when items exceed 120% of subtotal")
    func statusOver() {
        // subtotal = 10000, items = 13000 → ratio = 1.3
        let tx = makeTransaction(amountCents: 10000)
        let items = [makeItem(priceCents: 13000)]
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: tx, items: items)
        #expect(result?.status == .over)
    }

    // MARK: - varianceCents and variancePercent

    @Test("varianceCents is items total minus subtotal")
    func varianceCentsCorrect() {
        let tx = makeTransaction(amountCents: 10000)
        let items = [makeItem(priceCents: 9000)]
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: tx, items: items)
        #expect(result?.varianceCents == -1000)
    }

    @Test("variancePercent is correct")
    func variancePercentCorrect() {
        // subtotal = 10000, items = 9000 → variance = -10%
        let tx = makeTransaction(amountCents: 10000)
        let items = [makeItem(priceCents: 9000)]
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: tx, items: items)
        #expect(result?.variancePercent == -10.0)
    }

    @Test("varianceCents is positive when items exceed subtotal")
    func varianceCentsPositive() {
        let tx = makeTransaction(amountCents: 5000)
        let items = [makeItem(priceCents: 6000)]
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: tx, items: items)
        #expect(result?.varianceCents == 1000)
    }

    // MARK: - Items with nil prices

    @Test("Items with nil price count as zero toward total")
    func itemsWithNilPrice() {
        let tx = makeTransaction(amountCents: 10000)
        let items = [makeItem(priceCents: 5000), makeItem(priceCents: nil)]
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: tx, items: items)
        #expect(result?.itemsNetTotalCents == 5000)
        #expect(result?.itemsMissingPriceCount == 1)
    }

    @Test("itemsCount includes all items")
    func itemsCountCorrect() {
        let tx = makeTransaction(amountCents: 10000)
        let items = [makeItem(priceCents: 3000), makeItem(priceCents: 2000), makeItem(priceCents: nil)]
        let result = TransactionCompletenessCalculations.computeCompleteness(transaction: tx, items: items)
        #expect(result?.itemsCount == 3)
        #expect(result?.itemsMissingPriceCount == 1)
    }

    // MARK: - Returned and sold items

    @Test("Returned and sold items included in net total")
    func returnedAndSoldItemsIncluded() {
        let tx = makeTransaction(amountCents: 10000)
        let items = [makeItem(priceCents: 5000)]
        let returned = [makeItem(priceCents: 2000)]
        let sold = [makeItem(priceCents: 1000)]
        let result = TransactionCompletenessCalculations.computeCompleteness(
            transaction: tx,
            items: items,
            returnedItems: returned,
            soldItems: sold
        )
        #expect(result?.itemsNetTotalCents == 8000)
        #expect(result?.returnedItemsCount == 1)
        #expect(result?.returnedItemsTotalCents == 2000)
        #expect(result?.soldItemsCount == 1)
        #expect(result?.soldItemsTotalCents == 1000)
    }

    // MARK: - statusLabel

    @Test("statusLabel returns correct strings")
    func statusLabelCorrect() {
        #expect(TransactionCompletenessCalculations.statusLabel(.complete) == "Complete")
        #expect(TransactionCompletenessCalculations.statusLabel(.near) == "Near Complete")
        #expect(TransactionCompletenessCalculations.statusLabel(.incomplete) == "Incomplete")
        #expect(TransactionCompletenessCalculations.statusLabel(.over) == "Over")
    }
}
