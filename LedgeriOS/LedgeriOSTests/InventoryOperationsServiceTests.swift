import Foundation
import Testing
@testable import LedgeriOS

@Suite("InventoryOperationsService — pure helpers")
struct InventoryOperationsServiceTests {

    // MARK: - Helpers

    private func makeItem(
        id: String = "item1",
        purchasePriceCents: Int? = nil,
        projectPriceCents: Int? = nil,
        taxRatePct: Double? = nil
    ) -> Item {
        var item = Item()
        item.id = id
        item.purchasePriceCents = purchasePriceCents
        item.projectPriceCents = projectPriceCents
        item.taxRatePct = taxRatePct
        return item
    }

    // MARK: - computeBatchTotals

    @Test("computeBatchTotals — subtotalCents sums projectPriceCents only")
    func subtotalProjectPriceOnly() {
        let items = [
            makeItem(id: "i1", purchasePriceCents: 5000, projectPriceCents: 7000),
            makeItem(id: "i2", purchasePriceCents: 3000, projectPriceCents: nil),
        ]
        let (subtotalCents, _) = InventoryOperationsService.computeBatchTotals(items)
        #expect(subtotalCents == 7000)
    }

    @Test("computeBatchTotals — amountCents applies tax when taxRatePct > 0")
    func amountWithTax() {
        let items = [
            makeItem(id: "i1", purchasePriceCents: 10000, projectPriceCents: 12000, taxRatePct: 10.0),
        ]
        let (subtotalCents, amountCents) = InventoryOperationsService.computeBatchTotals(items)
        #expect(subtotalCents == 12000)
        // 12000 * 1.10 = 13200
        #expect(amountCents == 13200)
    }

    @Test("computeBatchTotals — no tax: amountCents equals subtotalCents")
    func amountNoTax() {
        let items = [
            makeItem(id: "i1", purchasePriceCents: 5000, projectPriceCents: 6000),
        ]
        let (subtotalCents, amountCents) = InventoryOperationsService.computeBatchTotals(items)
        #expect(subtotalCents == 6000)
        #expect(amountCents == 6000)
    }

    @Test("computeBatchTotals — nil prices contribute 0")
    func nilPricesZero() {
        let items = [makeItem(id: "i1", purchasePriceCents: nil, projectPriceCents: nil)]
        let (subtotalCents, amountCents) = InventoryOperationsService.computeBatchTotals(items)
        #expect(subtotalCents == 0)
        #expect(amountCents == 0)
    }

    @Test("computeBatchTotals — empty items returns zero")
    func emptyItems() {
        let (subtotalCents, amountCents) = InventoryOperationsService.computeBatchTotals([])
        #expect(subtotalCents == 0)
        #expect(amountCents == 0)
    }

    @Test("computeBatchTotals — taxRatePct of 0 treated same as nil (no tax)")
    func zeroTaxRate() {
        let items = [
            makeItem(id: "i1", purchasePriceCents: 5000, projectPriceCents: 6000, taxRatePct: 0),
        ]
        let (_, amountCents) = InventoryOperationsService.computeBatchTotals(items)
        #expect(amountCents == 6000) // No tax applied
    }

    @Test("computePurchasePriceTotals — sums purchasePriceCents only")
    func purchasePriceTotals() {
        let items = [
            makeItem(id: "i1", purchasePriceCents: 5000, projectPriceCents: 7000, taxRatePct: 10),
            makeItem(id: "i2", purchasePriceCents: nil, projectPriceCents: 3000),
        ]
        let (subtotalCents, amountCents) = InventoryOperationsService.computePurchasePriceTotals(items)
        #expect(subtotalCents == 5000)
        #expect(amountCents == 5000)
    }

    // MARK: - todayDateString

    @Test("todayDateString returns yyyy-MM-dd format")
    func todayDateFormat() {
        let today = InventoryOperationsService.todayDateString()
        // Should be 10 characters: YYYY-MM-DD
        #expect(today.count == 10)
        #expect(today.contains("-"))
    }
}
