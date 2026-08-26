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

    private func makeTransaction(
        id: String,
        projectId: String,
        source: String,
        type: TransactionType = .purchase
    ) -> Transaction {
        var transaction = Transaction()
        transaction.id = id
        transaction.projectId = projectId
        transaction.source = source
        transaction.transactionType = type
        return transaction
    }

    // MARK: - computeBatchTotals

    @Test("computeBatchTotals — missing project price uses purchase price")
    func subtotalUsesPurchasePriceFallback() {
        let items = [
            makeItem(id: "i1", purchasePriceCents: 5000, projectPriceCents: 7000),
            makeItem(id: "i2", purchasePriceCents: 3000, projectPriceCents: nil),
        ]
        let (subtotalCents, _) = InventoryOperationsService.computeBatchTotals(items)
        #expect(subtotalCents == 10000)
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

    @Test("project-origin acquisition ignores malformed project markup")
    func projectOriginAcquisitionUsesPurchaseCost() {
        let items = [
            makeItem(id: "i1", purchasePriceCents: 1000, projectPriceCents: 1500, taxRatePct: 10),
        ]
        let totals = InventoryOperationsService.computeProjectOriginAcquisitionTotals(items)
        #expect(totals.subtotalCents == 1000)
        #expect(totals.amountCents == 1000)
    }

    @Test("current inventory Purchase overrides stale source metadata")
    func transactionProvesInventoryOrigin() {
        var item = makeItem(id: "i1", purchasePriceCents: 699, projectPriceCents: 965)
        item.projectId = "project"
        item.transactionId = "inventory-purchase"
        item.source = "Hobby Lobby"
        item.currentSource = "Hobby Lobby"
        let transaction = makeTransaction(
            id: "inventory-purchase",
            projectId: "project",
            source: "1584 Design Inventory"
        )

        let split = InventoryOperationsService.splitByOrigin([item], transactions: [transaction])
        #expect(split.returnItems.map(\.id) == ["i1"])
        #expect(split.saleItems.isEmpty)
    }

    @Test("vendor Purchase overrides misleading inventory metadata")
    func transactionProvesProjectOrigin() {
        var item = makeItem(id: "i1", purchasePriceCents: 1000, projectPriceCents: 1500)
        item.projectId = "project"
        item.transactionId = "vendor-purchase"
        item.source = "Wayfair"
        item.currentSource = "1584 Design Inventory"
        let transaction = makeTransaction(
            id: "vendor-purchase",
            projectId: "project",
            source: "Wayfair"
        )

        let split = InventoryOperationsService.splitByOrigin([item], transactions: [transaction])
        #expect(split.saleItems.map(\.id) == ["i1"])
        #expect(split.returnItems.isEmpty)
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

@Suite("Item price floor")
struct ItemPricePolicyTests {
    @Test("Missing project price inherits purchase price")
    func missingProjectPrice() {
        #expect(ItemPricePolicy.normalizedProjectPriceCents(
            purchasePriceCents: 12_500,
            projectPriceCents: nil
        ) == 12_500)
    }

    @Test("Project price below purchase price is raised")
    func lowerProjectPrice() {
        #expect(ItemPricePolicy.normalizedProjectPriceCents(
            purchasePriceCents: 12_500,
            projectPriceCents: 0
        ) == 12_500)
    }

    @Test("Higher project price is preserved")
    func higherProjectPrice() {
        #expect(ItemPricePolicy.normalizedProjectPriceCents(
            purchasePriceCents: 12_500,
            projectPriceCents: 15_000
        ) == 15_000)
    }

    @Test("Partial purchase-price update uses stored project price")
    func mergedPartialUpdate() {
        var item = Item()
        item.purchasePriceCents = 12_500
        item.projectPriceCents = 15_000

        let raised = ItemPricePolicy.normalizedUpdateFields(
            existing: item,
            fields: ["purchasePriceCents": 17_500]
        )
        #expect(raised["projectPriceCents"] as? Int == 17_500)

        let preserved = ItemPricePolicy.normalizedUpdateFields(
            existing: item,
            fields: ["purchasePriceCents": 10_000]
        )
        #expect(preserved["projectPriceCents"] as? Int == 15_000)
    }
}
