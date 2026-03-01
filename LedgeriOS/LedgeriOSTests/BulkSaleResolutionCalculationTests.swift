import Foundation
import Testing
@testable import LedgeriOS

@Suite("Bulk Sale Resolution Calculation Tests")
struct BulkSaleResolutionCalculationTests {

    // MARK: - Helper factories

    private func makeItem(
        id: String? = nil,
        name: String = "",
        transactionId: String? = nil,
        budgetCategoryId: String? = nil
    ) -> Item {
        var item = Item()
        item.id = id
        item.name = name
        item.transactionId = transactionId
        item.budgetCategoryId = budgetCategoryId
        return item
    }

    private func makeCategory(id: String, name: String) -> BudgetCategory {
        var category = BudgetCategory()
        category.id = id
        category.name = name
        return category
    }

    // MARK: - eligibleForBulkReassign

    @Test("Items with transactionId are excluded")
    func eligibleExcludesItemsWithTransactionId() {
        let items = [
            makeItem(id: "a", transactionId: "txn1"),
            makeItem(id: "b", transactionId: "txn2"),
        ]
        let result = BulkSaleResolutionCalculations.eligibleForBulkReassign(items: items)
        #expect(result.isEmpty)
    }

    @Test("Items without transactionId are included")
    func eligibleIncludesItemsWithoutTransactionId() {
        let items = [
            makeItem(id: "a", transactionId: nil),
            makeItem(id: "b", transactionId: nil),
        ]
        let result = BulkSaleResolutionCalculations.eligibleForBulkReassign(items: items)
        #expect(result.count == 2)
    }

    @Test("Items with empty transactionId are included")
    func eligibleIncludesItemsWithEmptyTransactionId() {
        let items = [
            makeItem(id: "a", transactionId: ""),
        ]
        let result = BulkSaleResolutionCalculations.eligibleForBulkReassign(items: items)
        #expect(result.count == 1)
        #expect(result[0].id == "a")
    }

    @Test("Mix of items filters correctly for bulk reassign")
    func eligibleMixedItems() {
        let items = [
            makeItem(id: "a", transactionId: "txn1"),
            makeItem(id: "b", transactionId: nil),
            makeItem(id: "c", transactionId: ""),
            makeItem(id: "d", transactionId: "txn2"),
        ]
        let result = BulkSaleResolutionCalculations.eligibleForBulkReassign(items: items)
        let ids = result.compactMap(\.id)
        #expect(ids == ["b", "c"])
    }

    @Test("Empty input returns empty output for eligibleForBulkReassign")
    func eligibleEmptyInput() {
        let result = BulkSaleResolutionCalculations.eligibleForBulkReassign(items: [])
        #expect(result.isEmpty)
    }

    @Test("All items with transactionId returns empty")
    func eligibleAllHaveTransactionId() {
        let items = [
            makeItem(id: "a", transactionId: "txn1"),
            makeItem(id: "b", transactionId: "txn2"),
            makeItem(id: "c", transactionId: "txn3"),
        ]
        let result = BulkSaleResolutionCalculations.eligibleForBulkReassign(items: items)
        #expect(result.isEmpty)
    }

    // MARK: - resolveSaleCategories

    @Test("Item with budgetCategoryId maps to that categoryId")
    func resolveWithBudgetCategoryId() {
        let items = [makeItem(id: "a", budgetCategoryId: "cat1")]
        let categories = [makeCategory(id: "cat1", name: "Shoes")]
        let result = BulkSaleResolutionCalculations.resolveSaleCategories(items: items, categories: categories)
        #expect(result["a"] == "cat1")
    }

    @Test("Item without budgetCategoryId maps to nil")
    func resolveWithoutBudgetCategoryId() {
        let items = [makeItem(id: "a", budgetCategoryId: nil)]
        let categories: [BudgetCategory] = []
        let result = BulkSaleResolutionCalculations.resolveSaleCategories(items: items, categories: categories)
        #expect(result.keys.contains("a"))
        #expect(result["a"] as String?? == nil as String?)
    }

    @Test("Item with empty budgetCategoryId maps to nil")
    func resolveWithEmptyBudgetCategoryId() {
        let items = [makeItem(id: "a", budgetCategoryId: "")]
        let categories: [BudgetCategory] = []
        let result = BulkSaleResolutionCalculations.resolveSaleCategories(items: items, categories: categories)
        #expect(result.keys.contains("a"))
        #expect(result["a"] as String?? == nil as String?)
    }

    @Test("Mix of items resolves correct category mapping")
    func resolveMixedItems() {
        let items = [
            makeItem(id: "a", budgetCategoryId: "cat1"),
            makeItem(id: "b", budgetCategoryId: nil),
            makeItem(id: "c", budgetCategoryId: "cat2"),
            makeItem(id: "d", budgetCategoryId: ""),
        ]
        let categories = [
            makeCategory(id: "cat1", name: "Shoes"),
            makeCategory(id: "cat2", name: "Hats"),
        ]
        let result = BulkSaleResolutionCalculations.resolveSaleCategories(items: items, categories: categories)
        #expect(result["a"] == "cat1")
        #expect(result["b"] as String?? == nil as String?)
        #expect(result["c"] == "cat2")
        #expect(result["d"] as String?? == nil as String?)
    }

    @Test("Item without id is skipped in resolveSaleCategories")
    func resolveSkipsItemWithoutId() {
        let items = [makeItem(id: nil, budgetCategoryId: "cat1")]
        let categories = [makeCategory(id: "cat1", name: "Shoes")]
        let result = BulkSaleResolutionCalculations.resolveSaleCategories(items: items, categories: categories)
        #expect(result.isEmpty)
    }

    @Test("Empty input returns empty map for resolveSaleCategories")
    func resolveEmptyInput() {
        let result = BulkSaleResolutionCalculations.resolveSaleCategories(items: [], categories: [])
        #expect(result.isEmpty)
    }

    // MARK: - itemsNeedingCategoryResolution

    @Test("Items without budgetCategoryId are returned")
    func needingResolutionWithoutCategory() {
        let items = [
            makeItem(id: "a", budgetCategoryId: nil),
            makeItem(id: "b", budgetCategoryId: nil),
        ]
        let result = BulkSaleResolutionCalculations.itemsNeedingCategoryResolution(items: items)
        #expect(result.count == 2)
    }

    @Test("Items with budgetCategoryId are excluded")
    func needingResolutionExcludesWithCategory() {
        let items = [
            makeItem(id: "a", budgetCategoryId: "cat1"),
            makeItem(id: "b", budgetCategoryId: "cat2"),
        ]
        let result = BulkSaleResolutionCalculations.itemsNeedingCategoryResolution(items: items)
        #expect(result.isEmpty)
    }

    @Test("Items with empty budgetCategoryId are returned")
    func needingResolutionIncludesEmptyCategory() {
        let items = [
            makeItem(id: "a", budgetCategoryId: ""),
        ]
        let result = BulkSaleResolutionCalculations.itemsNeedingCategoryResolution(items: items)
        #expect(result.count == 1)
        #expect(result[0].id == "a")
    }

    @Test("Mix of items filters correctly for category resolution")
    func needingResolutionMixedItems() {
        let items = [
            makeItem(id: "a", budgetCategoryId: "cat1"),
            makeItem(id: "b", budgetCategoryId: nil),
            makeItem(id: "c", budgetCategoryId: ""),
            makeItem(id: "d", budgetCategoryId: "cat2"),
        ]
        let result = BulkSaleResolutionCalculations.itemsNeedingCategoryResolution(items: items)
        let ids = result.compactMap(\.id)
        #expect(ids == ["b", "c"])
    }

    @Test("Empty input returns empty output for itemsNeedingCategoryResolution")
    func needingResolutionEmptyInput() {
        let result = BulkSaleResolutionCalculations.itemsNeedingCategoryResolution(items: [])
        #expect(result.isEmpty)
    }

    @Test("All items with categories returns empty for itemsNeedingCategoryResolution")
    func needingResolutionAllHaveCategories() {
        let items = [
            makeItem(id: "a", budgetCategoryId: "cat1"),
            makeItem(id: "b", budgetCategoryId: "cat2"),
            makeItem(id: "c", budgetCategoryId: "cat3"),
        ]
        let result = BulkSaleResolutionCalculations.itemsNeedingCategoryResolution(items: items)
        #expect(result.isEmpty)
    }
}
