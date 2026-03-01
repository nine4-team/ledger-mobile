import Foundation
import Testing
@testable import LedgeriOS

@Suite("Item Detail Calculation Tests")
struct ItemDetailCalculationTests {

    // MARK: - Helper factories

    private func makeItem(
        id: String? = nil,
        name: String = "",
        status: String? = nil,
        spaceId: String? = nil,
        transactionId: String? = nil,
        projectPriceCents: Int? = nil,
        purchasePriceCents: Int? = nil,
        bookmark: Bool? = nil,
        budgetCategoryId: String? = nil,
        projectId: String? = nil
    ) -> Item {
        var item = Item()
        item.id = id
        item.name = name
        item.status = status
        item.spaceId = spaceId
        item.transactionId = transactionId
        item.projectPriceCents = projectPriceCents
        item.purchasePriceCents = purchasePriceCents
        item.bookmark = bookmark
        item.budgetCategoryId = budgetCategoryId
        item.projectId = projectId
        return item
    }

    private func makeSpace(id: String, name: String) -> Space {
        var space = Space()
        space.id = id
        space.name = name
        return space
    }

    private func makeCategory(id: String, name: String) -> BudgetCategory {
        var category = BudgetCategory()
        category.id = id
        category.name = name
        return category
    }

    // MARK: - availableActions: status-based action sets

    @Test("to-purchase item gets full actions")
    func availableActionsToPurchase() {
        let item = makeItem(status: "to-purchase")
        let actions = ItemDetailCalculations.availableActions(for: item)

        #expect(actions.contains(.changeStatus))
        #expect(actions.contains(.setSpace))
        #expect(actions.contains(.setTransaction))
        #expect(actions.contains(.sellToBusiness))
        #expect(actions.contains(.sellToProject))
        #expect(actions.contains(.reassignToProject))
        #expect(actions.contains(.reassignToInventory))
        #expect(actions.contains(.moveToReturn))
        #expect(actions.contains(.makeCopies))
        #expect(actions.contains(.bookmark))
        #expect(actions.contains(.delete))
    }

    @Test("purchased item gets full actions")
    func availableActionsPurchased() {
        let item = makeItem(status: "purchased")
        let actions = ItemDetailCalculations.availableActions(for: item)

        #expect(actions.contains(.changeStatus))
        #expect(actions.contains(.sellToBusiness))
        #expect(actions.contains(.delete))
    }

    @Test("returned item gets only bookmark and delete")
    func availableActionsReturned() {
        let item = makeItem(status: "returned")
        let actions = ItemDetailCalculations.availableActions(for: item)

        #expect(actions.count == 2)
        #expect(actions.contains(.bookmark))
        #expect(actions.contains(.delete))
    }

    @Test("nil status item gets full actions (treated as active)")
    func availableActionsNilStatus() {
        let item = makeItem(status: nil)
        let actions = ItemDetailCalculations.availableActions(for: item)

        #expect(actions.contains(.changeStatus))
        #expect(actions.contains(.sellToBusiness))
        #expect(actions.contains(.delete))
        #expect(actions.count > 2)
    }

    // MARK: - availableActions: space toggle

    @Test("nil spaceId includes setSpace, not clearSpace")
    func availableActionsNilSpaceId() {
        let item = makeItem(spaceId: nil)
        let actions = ItemDetailCalculations.availableActions(for: item)

        #expect(actions.contains(.setSpace))
        #expect(!actions.contains(.clearSpace))
    }

    @Test("non-nil spaceId includes clearSpace, not setSpace")
    func availableActionsWithSpaceId() {
        let item = makeItem(spaceId: "space-1")
        let actions = ItemDetailCalculations.availableActions(for: item)

        #expect(actions.contains(.clearSpace))
        #expect(!actions.contains(.setSpace))
    }

    // MARK: - availableActions: transaction toggle

    @Test("nil transactionId includes setTransaction, not clearTransaction")
    func availableActionsNilTransactionId() {
        let item = makeItem(transactionId: nil)
        let actions = ItemDetailCalculations.availableActions(for: item)

        #expect(actions.contains(.setTransaction))
        #expect(!actions.contains(.clearTransaction))
    }

    @Test("non-nil transactionId includes clearTransaction, not setTransaction")
    func availableActionsWithTransactionId() {
        let item = makeItem(transactionId: "tx-1")
        let actions = ItemDetailCalculations.availableActions(for: item)

        #expect(actions.contains(.clearTransaction))
        #expect(!actions.contains(.setTransaction))
    }

    // MARK: - availableActions: bookmark toggle

    @Test("bookmarked item includes unbookmark, not bookmark")
    func availableActionsBookmarked() {
        let item = makeItem(bookmark: true)
        let actions = ItemDetailCalculations.availableActions(for: item)

        #expect(actions.contains(.unbookmark))
        #expect(!actions.contains(.bookmark))
    }

    @Test("non-bookmarked item includes bookmark, not unbookmark")
    func availableActionsNotBookmarked() {
        let item = makeItem(bookmark: false)
        let actions = ItemDetailCalculations.availableActions(for: item)

        #expect(actions.contains(.bookmark))
        #expect(!actions.contains(.unbookmark))
    }

    // MARK: - availableActions: returned item bookmark variants

    @Test("returned bookmarked item gets unbookmark and delete")
    func availableActionsReturnedBookmarked() {
        let item = makeItem(status: "returned", bookmark: true)
        let actions = ItemDetailCalculations.availableActions(for: item)

        #expect(actions.count == 2)
        #expect(actions[0] == .unbookmark)
        #expect(actions[1] == .delete)
    }

    @Test("returned non-bookmarked item gets bookmark and delete")
    func availableActionsReturnedNotBookmarked() {
        let item = makeItem(status: "returned", bookmark: false)
        let actions = ItemDetailCalculations.availableActions(for: item)

        #expect(actions.count == 2)
        #expect(actions[0] == .bookmark)
        #expect(actions[1] == .delete)
    }

    // MARK: - displayPrice

    @Test("both prices set returns projectPriceCents")
    func displayPriceBothSet() {
        let item = makeItem(projectPriceCents: 2000, purchasePriceCents: 1000)
        let result = ItemDetailCalculations.displayPrice(for: item)

        #expect(result == 2000)
    }

    @Test("only purchasePriceCents set returns purchasePriceCents")
    func displayPriceOnlyPurchase() {
        let item = makeItem(purchasePriceCents: 1000)
        let result = ItemDetailCalculations.displayPrice(for: item)

        #expect(result == 1000)
    }

    @Test("only projectPriceCents set returns projectPriceCents")
    func displayPriceOnlyProject() {
        let item = makeItem(projectPriceCents: 500)
        let result = ItemDetailCalculations.displayPrice(for: item)

        #expect(result == 500)
    }

    @Test("neither price set returns nil")
    func displayPriceNeitherSet() {
        let item = makeItem()
        let result = ItemDetailCalculations.displayPrice(for: item)

        #expect(result == nil)
    }

    // MARK: - resolveSpaceName

    @Test("known spaceId returns space name")
    func resolveSpaceNameKnown() {
        let spaces = [makeSpace(id: "s1", name: "Kitchen"), makeSpace(id: "s2", name: "Bedroom")]
        let result = ItemDetailCalculations.resolveSpaceName(spaceId: "s1", spaces: spaces)

        #expect(result == "Kitchen")
    }

    @Test("unknown spaceId returns nil")
    func resolveSpaceNameUnknown() {
        let spaces = [makeSpace(id: "s1", name: "Kitchen")]
        let result = ItemDetailCalculations.resolveSpaceName(spaceId: "s99", spaces: spaces)

        #expect(result == nil)
    }

    @Test("nil spaceId returns nil")
    func resolveSpaceNameNil() {
        let spaces = [makeSpace(id: "s1", name: "Kitchen")]
        let result = ItemDetailCalculations.resolveSpaceName(spaceId: nil, spaces: spaces)

        #expect(result == nil)
    }

    @Test("empty string spaceId returns nil")
    func resolveSpaceNameEmpty() {
        let spaces = [makeSpace(id: "s1", name: "Kitchen")]
        let result = ItemDetailCalculations.resolveSpaceName(spaceId: "", spaces: spaces)

        #expect(result == nil)
    }

    // MARK: - resolveCategoryName

    @Test("known categoryId returns category name")
    func resolveCategoryNameKnown() {
        let categories = [makeCategory(id: "c1", name: "Furniture"), makeCategory(id: "c2", name: "Paint")]
        let result = ItemDetailCalculations.resolveCategoryName(categoryId: "c1", categories: categories)

        #expect(result == "Furniture")
    }

    @Test("unknown categoryId returns nil")
    func resolveCategoryNameUnknown() {
        let categories = [makeCategory(id: "c1", name: "Furniture")]
        let result = ItemDetailCalculations.resolveCategoryName(categoryId: "c99", categories: categories)

        #expect(result == nil)
    }

    @Test("nil categoryId returns nil")
    func resolveCategoryNameNil() {
        let categories = [makeCategory(id: "c1", name: "Furniture")]
        let result = ItemDetailCalculations.resolveCategoryName(categoryId: nil, categories: categories)

        #expect(result == nil)
    }

    @Test("empty string categoryId returns nil")
    func resolveCategoryNameEmpty() {
        let categories = [makeCategory(id: "c1", name: "Furniture")]
        let result = ItemDetailCalculations.resolveCategoryName(categoryId: "", categories: categories)

        #expect(result == nil)
    }
}
