import Foundation
import Testing
@testable import LedgeriOS

@Suite("InventoryOperationsService — pure helpers")
struct InventoryOperationsServiceTests {

    // MARK: - Helpers

    private func makeItem(
        id: String = "item1",
        projectId: String? = "proj1",
        budgetCategoryId: String? = nil,
        purchasePriceCents: Int? = nil,
        transactionId: String? = nil,
        projectPriceCents: Int? = nil
    ) -> Item {
        var item = Item()
        item.id = id
        item.projectId = projectId
        item.budgetCategoryId = budgetCategoryId
        item.purchasePriceCents = purchasePriceCents
        item.transactionId = transactionId
        item.projectPriceCents = projectPriceCents
        return item
    }

    // MARK: - canonicalSaleId (H1)

    @Test("canonicalSaleId formats as SALE_projectId_direction_categoryId")
    func canonicalSaleIdFormat() {
        let id = InventoryOperationsService.canonicalSaleId(
            projectId: "proj123",
            direction: "project_to_business",
            categoryId: "catFurnishings"
        )
        #expect(id == "SALE_proj123_project_to_business_catFurnishings")
    }

    @Test("canonicalSaleId is unique per direction")
    func canonicalSaleIdDirectionUnique() {
        let a = InventoryOperationsService.canonicalSaleId(
            projectId: "proj1", direction: "business_to_project", categoryId: "cat1"
        )
        let b = InventoryOperationsService.canonicalSaleId(
            projectId: "proj1", direction: "project_to_business", categoryId: "cat1"
        )
        #expect(a != b)
    }

    @Test("canonicalSaleId is unique per category")
    func canonicalSaleIdCategoryUnique() {
        let a = InventoryOperationsService.canonicalSaleId(
            projectId: "proj1", direction: "business_to_project", categoryId: "cat1"
        )
        let b = InventoryOperationsService.canonicalSaleId(
            projectId: "proj1", direction: "business_to_project", categoryId: "cat2"
        )
        #expect(a != b)
    }

    // MARK: - amountDelta (H11)

    @Test("amountDelta sums purchasePriceCents across items")
    func amountDeltaSum() {
        let items = [
            makeItem(id: "i1", purchasePriceCents: 5000),
            makeItem(id: "i2", purchasePriceCents: 3000),
        ]
        #expect(InventoryOperationsService.amountDelta(for: items) == 8000)
    }

    @Test("amountDelta treats nil purchasePriceCents as zero")
    func amountDeltaNilAsZero() {
        let items = [
            makeItem(id: "i1", purchasePriceCents: 5000),
            makeItem(id: "i2", purchasePriceCents: nil),
        ]
        #expect(InventoryOperationsService.amountDelta(for: items) == 5000)
    }

    @Test("amountDelta returns zero for empty items")
    func amountDeltaEmpty() {
        #expect(InventoryOperationsService.amountDelta(for: []) == 0)
    }

    // MARK: - groupForSale (H12)

    @Test("groupForSale groups items by projectId + categoryId")
    func groupForSaleBasic() {
        let items = [
            makeItem(id: "i1", projectId: "proj1", budgetCategoryId: "cat1"),
            makeItem(id: "i2", projectId: "proj1", budgetCategoryId: "cat1"),
            makeItem(id: "i3", projectId: "proj1", budgetCategoryId: "cat2"),
        ]
        let groups = InventoryOperationsService.groupForSale(items: items, override: nil)
        #expect(groups.count == 2)
        let key1 = InventoryOperationsService.SaleGroupKey(projectId: "proj1", categoryId: "cat1")
        let key2 = InventoryOperationsService.SaleGroupKey(projectId: "proj1", categoryId: "cat2")
        #expect(groups[key1]?.count == 2)
        #expect(groups[key2]?.count == 1)
    }

    @Test("groupForSale uses override category for items with no budgetCategoryId")
    func groupForSaleOverride() {
        let items = [
            makeItem(id: "i1", projectId: "proj1", budgetCategoryId: nil),
            makeItem(id: "i2", projectId: "proj1", budgetCategoryId: "cat1"),
        ]
        let groups = InventoryOperationsService.groupForSale(items: items, override: "catOverride")
        let keyOverride = InventoryOperationsService.SaleGroupKey(projectId: "proj1", categoryId: "catOverride")
        let keyCat1 = InventoryOperationsService.SaleGroupKey(projectId: "proj1", categoryId: "cat1")
        #expect(groups[keyOverride]?.count == 1)
        #expect(groups[keyCat1]?.count == 1)
    }

    @Test("groupForSale falls back to 'uncategorized' when no category and no override")
    func groupForSaleFallback() {
        let items = [makeItem(id: "i1", projectId: "proj1", budgetCategoryId: nil)]
        let groups = InventoryOperationsService.groupForSale(items: items, override: nil)
        let key = InventoryOperationsService.SaleGroupKey(projectId: "proj1", categoryId: "uncategorized")
        #expect(groups[key]?.count == 1)
    }

    @Test("groupForSale skips items with no projectId")
    func groupForSaleSkipsNilProject() {
        let items = [
            makeItem(id: "i1", projectId: "proj1", budgetCategoryId: "cat1"),
            makeItem(id: "i2", projectId: nil, budgetCategoryId: "cat1"),
        ]
        let groups = InventoryOperationsService.groupForSale(items: items, override: nil)
        // Only the item with a projectId is included
        let total = groups.values.reduce(0) { $0 + $1.count }
        #expect(total == 1)
    }

    @Test("groupForSale separates items from different projects into different groups")
    func groupForSaleMultiProject() {
        let items = [
            makeItem(id: "i1", projectId: "proj1", budgetCategoryId: "cat1"),
            makeItem(id: "i2", projectId: "proj2", budgetCategoryId: "cat1"),
        ]
        let groups = InventoryOperationsService.groupForSale(items: items, override: nil)
        #expect(groups.count == 2)
    }

    @Test("item's own budgetCategoryId takes priority over override")
    func groupForSaleItemCategoryPriority() {
        let items = [makeItem(id: "i1", projectId: "proj1", budgetCategoryId: "ownCat")]
        let groups = InventoryOperationsService.groupForSale(items: items, override: "overrideCat")
        let keyOwn = InventoryOperationsService.SaleGroupKey(projectId: "proj1", categoryId: "ownCat")
        let keyOverride = InventoryOperationsService.SaleGroupKey(projectId: "proj1", categoryId: "overrideCat")
        #expect(groups[keyOwn]?.count == 1)
        #expect(groups[keyOverride] == nil)
    }
}
