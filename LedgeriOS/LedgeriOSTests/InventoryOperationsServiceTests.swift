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
        type: TransactionType = .purchase,
        itemIds: [String] = [],
        budgetCategoryId: String = "furnishings"
    ) -> Transaction {
        var transaction = Transaction()
        transaction.id = id
        transaction.projectId = projectId
        transaction.source = source
        transaction.transactionType = type
        transaction.itemIds = itemIds
        transaction.budgetCategoryId = budgetCategoryId
        transaction.subtotalCents = 0
        transaction.amountCents = 0
        return transaction
    }

    private func makeInventoryItem(id: String, transactionId: String) -> Item {
        var item = Item()
        item.id = id
        item.projectId = nil
        item.transactionId = transactionId
        return item
    }

    // MARK: - Return project resolution

    @Test("return project resolves from current project-scoped inventory movement")
    func returnProjectResolvesFromCurrentMovement() {
        let item = makeInventoryItem(id: "item-1", transactionId: "return-1")
        let transaction = makeTransaction(
            id: "return-1",
            projectId: "project-home",
            source: "Business Inventory",
            type: .return,
            itemIds: ["item-1"]
        )

        #expect(InventoryOperationsService.returnProjectId(
            for: [item],
            transactions: [transaction]
        ) == "project-home")
    }

    @Test("return project does not resolve for ordinary inventory purchase")
    func ordinaryInventoryPurchaseIsNotReturn() {
        let item = makeInventoryItem(id: "item-1", transactionId: "purchase-1")
        var transaction = Transaction()
        transaction.id = "purchase-1"
        transaction.projectId = nil
        transaction.source = "Wayfair"
        transaction.transactionType = .purchase

        #expect(InventoryOperationsService.returnProjectId(
            for: [item],
            transactions: [transaction]
        ) == nil)
    }

    @Test("mixed source projects cannot resolve as one return")
    func mixedReturnProjectsDoNotResolve() {
        let items = [
            makeInventoryItem(id: "item-1", transactionId: "return-1"),
            makeInventoryItem(id: "item-2", transactionId: "return-2"),
        ]
        let transactions = [
            makeTransaction(id: "return-1", projectId: "project-a", source: "Business Inventory", type: .return, itemIds: ["item-1"]),
            makeTransaction(id: "return-2", projectId: "project-b", source: "Business Inventory", type: .return, itemIds: ["item-2"]),
        ]

        #expect(InventoryOperationsService.returnProjectId(
            for: items,
            transactions: transactions
        ) == nil)
    }

    @Test("project sale without an inventory source is not return provenance")
    func ordinaryProjectSaleIsNotReturn() {
        let item = makeInventoryItem(id: "item-1", transactionId: "sale-1")
        let transaction = makeTransaction(
            id: "sale-1",
            projectId: "project-home",
            source: "Customer",
            type: .sale,
            itemIds: ["item-1"]
        )

        #expect(InventoryOperationsService.returnProjectId(
            for: [item],
            transactions: [transaction]
        ) == nil)
    }

    @Test("sale-to-inventory resolves as return provenance")
    func saleToInventoryResolves() {
        let item = makeInventoryItem(id: "item-1", transactionId: "sale-1")
        let transaction = makeTransaction(
            id: "sale-1",
            projectId: "project-home",
            source: "Business Inventory",
            type: .sale,
            itemIds: ["item-1"]
        )

        #expect(InventoryOperationsService.returnProjectId(
            for: [item],
            transactions: [transaction]
        ) == "project-home")
    }

    @Test("transaction must still contain the inventory item")
    func staleTransactionMembershipIsNotReturn() {
        let item = makeInventoryItem(id: "item-1", transactionId: "return-1")
        let transaction = makeTransaction(
            id: "return-1",
            projectId: "project-home",
            source: "Business Inventory",
            type: .return,
            itemIds: []
        )

        #expect(InventoryOperationsService.returnProjectId(
            for: [item],
            transactions: [transaction]
        ) == nil)
    }

    @Test("canceled movement is not return provenance")
    func canceledMovementIsNotReturn() {
        let item = makeInventoryItem(id: "item-1", transactionId: "return-1")
        var transaction = makeTransaction(
            id: "return-1",
            projectId: "project-home",
            source: "Business Inventory",
            type: .return,
            itemIds: ["item-1"]
        )
        transaction.status = .canceled

        #expect(InventoryOperationsService.returnProjectId(
            for: [item],
            transactions: [transaction]
        ) == nil)
    }

    @Test("partial inventory snapshot blocks return instead of falling back")
    func partialSnapshotDoesNotResolve() {
        var item = makeInventoryItem(id: "item-1", transactionId: "return-1")
        item.inventoryEntryProjectId = "wrong-project"
        var transaction = makeTransaction(
            id: "return-1",
            projectId: "project-home",
            source: "Business Inventory",
            type: .return,
            itemIds: ["item-1"]
        )
        transaction.subtotalCents = 10_000
        transaction.amountCents = 10_825

        #expect(InventoryOperationsService.returnProjectId(
            for: [item],
            transactions: [transaction]
        ) == nil)
    }

    @Test("ambiguous multi-item legacy movement blocks return")
    func ambiguousLegacyMovementDoesNotResolve() {
        let item = makeInventoryItem(id: "item-1", transactionId: "return-1")
        var transaction = makeTransaction(
            id: "return-1",
            projectId: "project-home",
            source: "Business Inventory",
            type: .return,
            itemIds: ["item-1", "item-2"]
        )
        transaction.subtotalCents = 20_000
        transaction.amountCents = 21_650

        #expect(InventoryOperationsService.returnProjectId(
            for: [item],
            transactions: [transaction]
        ) == nil)
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
