import Foundation
import Testing
@testable import LedgeriOS

// MARK: - Test Helpers

private func makeItem(
    id: String? = nil,
    name: String = "",
    source: String? = nil,
    sku: String? = nil,
    notes: String? = nil,
    budgetCategoryId: String? = nil,
    purchasePriceCents: Int? = nil,
    projectPriceCents: Int? = nil,
    marketValueCents: Int? = nil
) -> Item {
    var item = Item()
    item.id = id
    item.name = name
    item.source = source
    item.sku = sku
    item.notes = notes
    item.budgetCategoryId = budgetCategoryId
    item.purchasePriceCents = purchasePriceCents
    item.projectPriceCents = projectPriceCents
    item.marketValueCents = marketValueCents
    return item
}

private func makeTransaction(
    id: String? = nil,
    source: String? = nil,
    transactionType: String? = nil,
    notes: String? = nil,
    purchasedBy: String? = nil,
    budgetCategoryId: String? = nil,
    amountCents: Int? = nil,
    isCanonicalInventorySale: Bool? = nil,
    inventorySaleDirection: InventorySaleDirection? = nil
) -> Transaction {
    var tx = Transaction()
    tx.id = id
    tx.source = source
    tx.transactionType = transactionType
    tx.notes = notes
    tx.purchasedBy = purchasedBy
    tx.budgetCategoryId = budgetCategoryId
    tx.amountCents = amountCents
    tx.isCanonicalInventorySale = isCanonicalInventorySale
    tx.inventorySaleDirection = inventorySaleDirection
    return tx
}

private func makeSpace(
    id: String? = nil,
    name: String = "",
    notes: String? = nil
) -> Space {
    var space = Space()
    space.id = id
    space.name = name
    space.notes = notes
    return space
}

private func makeCategory(
    id: String? = nil,
    name: String = ""
) -> BudgetCategory {
    var cat = BudgetCategory()
    cat.id = id
    cat.name = name
    return cat
}

// MARK: - Amount Prefix-Range Tests

@Suite("Amount Prefix-Range Parsing")
struct AmountPrefixRangeTests {

    @Test("Integer query: 40 → 4000...4099")
    func integerQuery() {
        let range = SearchCalculations.parseAmountQuery("40")
        #expect(range == 4000...4099)
    }

    @Test("One decimal query: 40.0 → 4000...4009")
    func oneDecimalQuery() {
        let range = SearchCalculations.parseAmountQuery("40.0")
        #expect(range == 4000...4009)
    }

    @Test("One decimal query: 40.1 → 4010...4019")
    func oneDecimalQueryVariant() {
        let range = SearchCalculations.parseAmountQuery("40.1")
        #expect(range == 4010...4019)
    }

    @Test("Two decimal query: 40.00 → 4000...4000 (exact)")
    func twoDecimalQuery() {
        let range = SearchCalculations.parseAmountQuery("40.00")
        #expect(range == 4000...4000)
    }

    @Test("Dollar sign stripped: $40 → same as 40")
    func dollarSignStripped() {
        let range = SearchCalculations.parseAmountQuery("$40")
        #expect(range == 4000...4099)
    }

    @Test("Comma stripped: 1,200 → 120000...120099")
    func commaStripped() {
        let range = SearchCalculations.parseAmountQuery("1,200")
        #expect(range == 120000...120099)
    }

    @Test("Dollar and comma: $1,200 → 120000...120099")
    func dollarAndComma() {
        let range = SearchCalculations.parseAmountQuery("$1,200")
        #expect(range == 120000...120099)
    }

    @Test("Invalid query returns nil")
    func invalidQueryNoAmountMatch() {
        #expect(SearchCalculations.parseAmountQuery("abc") == nil)
    }

    @Test("Empty query returns nil")
    func emptyQueryReturnsNil() {
        #expect(SearchCalculations.parseAmountQuery("") == nil)
    }

    @Test("Just dollar sign returns nil")
    func justDollarSign() {
        #expect(SearchCalculations.parseAmountQuery("$") == nil)
    }

    @Test("Zero → 0...99")
    func zeroQuery() {
        let range = SearchCalculations.parseAmountQuery("0")
        #expect(range == 0...99)
    }

    @Test("Three decimal digits returns nil")
    func threeDecimalDigitsReturnsNil() {
        #expect(SearchCalculations.parseAmountQuery("40.000") == nil)
    }

    @Test("Amount match on item with purchasePriceCents")
    func amountMatchOnItem() {
        let item = makeItem(purchasePriceCents: 4050)
        let result = SearchCalculations.itemMatches(item: item, query: "40", categories: [])
        #expect(result == true)
    }

    @Test("One decimal excludes items outside range")
    func oneDecimalExcludesOutOfRange() {
        let item = makeItem(purchasePriceCents: 4050)
        let result = SearchCalculations.itemMatches(item: item, query: "40.0", categories: [])
        #expect(result == false)
    }

    @Test("One decimal includes items in range")
    func oneDecimalIncludesInRange() {
        let item = makeItem(purchasePriceCents: 4005)
        let result = SearchCalculations.itemMatches(item: item, query: "40.0", categories: [])
        #expect(result == true)
    }

    @Test("Two decimal exact match")
    func twoDecimalExactMatch() {
        let item = makeItem(purchasePriceCents: 4000)
        let result = SearchCalculations.itemMatches(item: item, query: "40.00", categories: [])
        #expect(result == true)
    }

    @Test("Two decimal no match on off-by-one")
    func twoDecimalNoMatchOffByOne() {
        let item = makeItem(purchasePriceCents: 4001)
        let result = SearchCalculations.itemMatches(item: item, query: "40.00", categories: [])
        #expect(result == false)
    }

    @Test("Amount match on projectPriceCents")
    func amountMatchProjectPrice() {
        let item = makeItem(projectPriceCents: 4050)
        let result = SearchCalculations.itemMatches(item: item, query: "40", categories: [])
        #expect(result == true)
    }

    @Test("Amount match on marketValueCents")
    func amountMatchMarketValue() {
        let item = makeItem(marketValueCents: 4050)
        let result = SearchCalculations.itemMatches(item: item, query: "40", categories: [])
        #expect(result == true)
    }

    @Test("Transaction amount match")
    func transactionAmountMatch() {
        let tx = makeTransaction(amountCents: 4050)
        let result = SearchCalculations.transactionMatches(transaction: tx, query: "40", categories: [])
        #expect(result == true)
    }

    @Test("Transaction amount no match")
    func transactionAmountNoMatch() {
        let tx = makeTransaction(amountCents: 5050)
        let result = SearchCalculations.transactionMatches(transaction: tx, query: "40", categories: [])
        #expect(result == false)
    }
}

// MARK: - SKU Normalization Tests

@Suite("SKU Normalization")
struct SKUNormalizationTests {

    @Test("normalizedSKU strips hyphens and lowercases")
    func hyphenStripped() {
        #expect(SearchCalculations.normalizedSKU("ABC-123") == "abc123")
    }

    @Test("normalizedSKU strips slashes")
    func slashStripped() {
        #expect(SearchCalculations.normalizedSKU("ABC/123") == "abc123")
    }

    @Test("normalizedSKU strips spaces")
    func spaceStripped() {
        #expect(SearchCalculations.normalizedSKU("ABC 123") == "abc123")
    }

    @Test("normalizedSKU is case insensitive")
    func caseInsensitive() {
        #expect(SearchCalculations.normalizedSKU("ABC123") == "abc123")
    }

    @Test("SKU search: ABC-123 query matches item with sku abc123")
    func skuSearchHyphen() {
        let item = makeItem(sku: "abc123")
        let result = SearchCalculations.itemMatches(item: item, query: "ABC-123", categories: [])
        #expect(result == true)
    }

    @Test("SKU search: query abc123 matches item with sku ABC-123")
    func skuSearchReverse() {
        let item = makeItem(sku: "ABC-123")
        let result = SearchCalculations.itemMatches(item: item, query: "abc123", categories: [])
        #expect(result == true)
    }

    @Test("SKU partial match: query abc matches item with sku ABC-123")
    func skuPartialMatch() {
        let item = makeItem(sku: "ABC-123")
        let result = SearchCalculations.itemMatches(item: item, query: "abc", categories: [])
        #expect(result == true)
    }

    @Test("SKU no match when query doesn't appear")
    func skuNoMatch() {
        let item = makeItem(sku: "ABC-123")
        let result = SearchCalculations.itemMatches(item: item, query: "xyz", categories: [])
        #expect(result == false)
    }
}

// MARK: - Text Substring Tests

@Suite("Text Substring Matching")
struct TextSubstringTests {

    @Test("Name match: lamp matches Table Lamp")
    func nameMatch() {
        let item = makeItem(name: "Table Lamp")
        let result = SearchCalculations.itemMatches(item: item, query: "lamp", categories: [])
        #expect(result == true)
    }

    @Test("Case insensitive text: LAMP matches table lamp")
    func caseInsensitiveText() {
        let item = makeItem(name: "table lamp")
        let result = SearchCalculations.itemMatches(item: item, query: "LAMP", categories: [])
        #expect(result == true)
    }

    @Test("Nil field no match from name")
    func nilFieldNoMatch() {
        // Item name defaults to "" so use notes which can be nil
        let item = makeItem(name: "", notes: nil)
        let result = SearchCalculations.itemMatches(item: item, query: "lamp", categories: [])
        #expect(result == false)
    }

    @Test("Category name match")
    func categoryNameMatch() {
        let cat = makeCategory(id: "cat1", name: "Furnishings")
        let item = makeItem(budgetCategoryId: "cat1")
        let result = SearchCalculations.itemMatches(item: item, query: "furnish", categories: [cat])
        #expect(result == true)
    }

    @Test("Source field match on item")
    func sourceFieldMatch() {
        let item = makeItem(source: "Home Depot")
        let result = SearchCalculations.itemMatches(item: item, query: "depot", categories: [])
        #expect(result == true)
    }

    @Test("Notes field match on item")
    func notesFieldMatch() {
        let item = makeItem(notes: "Needs to be returned")
        let result = SearchCalculations.itemMatches(item: item, query: "returned", categories: [])
        #expect(result == true)
    }

    @Test("Transaction displayName (source) match")
    func transactionDisplayNameMatch() {
        let tx = makeTransaction(source: "Amazon")
        let result = SearchCalculations.transactionMatches(transaction: tx, query: "amaz", categories: [])
        #expect(result == true)
    }

    @Test("Transaction type match")
    func transactionTypeMatch() {
        let tx = makeTransaction(transactionType: "purchase")
        let result = SearchCalculations.transactionMatches(transaction: tx, query: "purchase", categories: [])
        #expect(result == true)
    }

    @Test("Transaction notes match")
    func transactionNotesMatch() {
        let tx = makeTransaction(notes: "Office supplies from Staples")
        let result = SearchCalculations.transactionMatches(transaction: tx, query: "staples", categories: [])
        #expect(result == true)
    }

    @Test("Transaction purchasedBy match")
    func transactionPurchasedByMatch() {
        let tx = makeTransaction(purchasedBy: "John Smith")
        let result = SearchCalculations.transactionMatches(transaction: tx, query: "smith", categories: [])
        #expect(result == true)
    }

    @Test("Transaction category name match")
    func transactionCategoryMatch() {
        let cat = makeCategory(id: "cat1", name: "Materials")
        let tx = makeTransaction(budgetCategoryId: "cat1")
        let result = SearchCalculations.transactionMatches(transaction: tx, query: "mater", categories: [cat])
        #expect(result == true)
    }

    @Test("Space name match")
    func spaceNameMatch() {
        let space = makeSpace(name: "Living Room")
        let result = SearchCalculations.spaceMatches(space: space, query: "living")
        #expect(result == true)
    }

    @Test("Space notes match")
    func spaceNotesMatch() {
        let space = makeSpace(notes: "Recently renovated")
        let result = SearchCalculations.spaceMatches(space: space, query: "renovat")
        #expect(result == true)
    }

    @Test("Space has no amount matching")
    func spaceNoAmountMatch() {
        let space = makeSpace(name: "Room")
        // "40" shouldn't match a space even if it were somehow amount-like
        let result = SearchCalculations.spaceMatches(space: space, query: "40")
        #expect(result == false)
    }
}

// MARK: - Full Search Tests

@Suite("Full Search Function")
struct FullSearchTests {

    @Test("Empty query returns all results")
    func emptyQueryReturnsAll() {
        let items = [makeItem(name: "A"), makeItem(name: "B")]
        let transactions = [makeTransaction(source: "X")]
        let spaces = [makeSpace(name: "Y")]

        let result = SearchCalculations.search(
            query: "",
            items: items,
            transactions: transactions,
            spaces: spaces,
            categories: []
        )
        #expect(result.items.count == 2)
        #expect(result.transactions.count == 1)
        #expect(result.spaces.count == 1)
    }

    @Test("Whitespace-only query returns all results")
    func whitespaceQueryReturnsAll() {
        let items = [makeItem(name: "A")]
        let result = SearchCalculations.search(
            query: "   ",
            items: items,
            transactions: [],
            spaces: [],
            categories: []
        )
        #expect(result.items.count == 1)
    }

    @Test("Query filters across all entity types")
    func queryFiltersAll() {
        let items = [makeItem(name: "Table Lamp"), makeItem(name: "Chair")]
        let transactions = [makeTransaction(source: "Lamp Store"), makeTransaction(source: "IKEA")]
        let spaces = [makeSpace(name: "Lamp Room"), makeSpace(name: "Kitchen")]

        let result = SearchCalculations.search(
            query: "lamp",
            items: items,
            transactions: transactions,
            spaces: spaces,
            categories: []
        )
        #expect(result.items.count == 1)
        #expect(result.items[0].name == "Table Lamp")
        #expect(result.transactions.count == 1)
        #expect(result.transactions[0].source == "Lamp Store")
        #expect(result.spaces.count == 1)
        #expect(result.spaces[0].name == "Lamp Room")
    }

    @Test("Amount query matches items and transactions but not spaces")
    func amountQueryCrossEntity() {
        let items = [makeItem(name: "Widget", purchasePriceCents: 4050)]
        let transactions = [makeTransaction(source: "Store", amountCents: 4025)]
        let spaces = [makeSpace(name: "Room")]

        let result = SearchCalculations.search(
            query: "40",
            items: items,
            transactions: transactions,
            spaces: spaces,
            categories: []
        )
        #expect(result.items.count == 1)
        #expect(result.transactions.count == 1)
        #expect(result.spaces.count == 0)
    }

    @Test("No matches returns empty results")
    func noMatchesReturnsEmpty() {
        let items = [makeItem(name: "Chair")]
        let transactions = [makeTransaction(source: "IKEA")]
        let spaces = [makeSpace(name: "Kitchen")]

        let result = SearchCalculations.search(
            query: "xyznonexistent",
            items: items,
            transactions: transactions,
            spaces: spaces,
            categories: []
        )
        #expect(result.items.isEmpty)
        #expect(result.transactions.isEmpty)
        #expect(result.spaces.isEmpty)
    }
}

// MARK: - Transaction Display Name Tests

@Suite("Transaction Display Name")
struct TransactionDisplayNameTests {

    // Priority 1: Source

    @Test("Uses source when available")
    func usesSource() {
        let tx = makeTransaction(source: "Home Depot")
        #expect(SearchCalculations.transactionDisplayName(for: tx) == "Home Depot")
    }

    @Test("Source takes priority over canonical inventory sale")
    func sourcePriorityOverCanonical() {
        let tx = makeTransaction(
            source: "Home Depot",
            isCanonicalInventorySale: true,
            inventorySaleDirection: .businessToProject
        )
        #expect(SearchCalculations.transactionDisplayName(for: tx) == "Home Depot")
    }

    @Test("Whitespace-only source falls through")
    func whitespaceSourceFallsThrough() {
        let tx = makeTransaction(id: "abc123def", source: "   ")
        #expect(SearchCalculations.transactionDisplayName(for: tx) == "abc123")
    }

    // Priority 2: Canonical inventory sale label

    @Test("Canonical inventory sale with businessToProject → To Inventory")
    func canonicalBusinessToProject() {
        let tx = makeTransaction(
            isCanonicalInventorySale: true,
            inventorySaleDirection: .businessToProject
        )
        #expect(SearchCalculations.transactionDisplayName(for: tx) == "To Inventory")
    }

    @Test("Canonical inventory sale with projectToBusiness → From Inventory")
    func canonicalProjectToBusiness() {
        let tx = makeTransaction(
            isCanonicalInventorySale: true,
            inventorySaleDirection: .projectToBusiness
        )
        #expect(SearchCalculations.transactionDisplayName(for: tx) == "From Inventory")
    }

    @Test("Canonical inventory sale with no direction → Inventory Transfer")
    func canonicalNoDirection() {
        let tx = makeTransaction(isCanonicalInventorySale: true)
        #expect(SearchCalculations.transactionDisplayName(for: tx) == "Inventory Transfer")
    }

    @Test("isCanonicalInventorySale=false does not trigger inventory label")
    func canonicalFalseSkips() {
        let tx = makeTransaction(
            id: "xyz789abc",
            isCanonicalInventorySale: false,
            inventorySaleDirection: .businessToProject
        )
        // Should fall through to ID prefix
        #expect(SearchCalculations.transactionDisplayName(for: tx) == "xyz789")
    }

    // Priority 3: ID prefix

    @Test("ID prefix used when no source and not canonical sale")
    func idPrefixFallback() {
        let tx = makeTransaction(id: "abc123def456")
        #expect(SearchCalculations.transactionDisplayName(for: tx) == "abc123")
    }

    @Test("Short ID returns full ID")
    func shortIdReturnsFullId() {
        let tx = makeTransaction(id: "abc")
        #expect(SearchCalculations.transactionDisplayName(for: tx) == "abc")
    }

    // Priority 4: Fallback

    @Test("Falls back to Untitled Transaction when no source, not canonical, no ID")
    func fallsBackToUntitled() {
        let tx = makeTransaction(source: nil)
        #expect(SearchCalculations.transactionDisplayName(for: tx) == "Untitled Transaction")
    }

    @Test("Empty source with no ID falls back to Untitled Transaction")
    func emptySourceNoIdFallback() {
        let tx = makeTransaction(source: "")
        #expect(SearchCalculations.transactionDisplayName(for: tx) == "Untitled Transaction")
    }

    // Search integration with display name

    @Test("Search matches canonical inventory sale label")
    func searchMatchesCanonicalLabel() {
        let tx = makeTransaction(
            isCanonicalInventorySale: true,
            inventorySaleDirection: .businessToProject
        )
        let result = SearchCalculations.transactionMatches(transaction: tx, query: "inventory", categories: [])
        #expect(result == true)
    }

    @Test("Search matches From Inventory label")
    func searchMatchesFromInventory() {
        let tx = makeTransaction(
            isCanonicalInventorySale: true,
            inventorySaleDirection: .projectToBusiness
        )
        let result = SearchCalculations.transactionMatches(transaction: tx, query: "from inv", categories: [])
        #expect(result == true)
    }

    @Test("Search matches ID prefix when no source")
    func searchMatchesIdPrefix() {
        let tx = makeTransaction(id: "abc123def456")
        let result = SearchCalculations.transactionMatches(transaction: tx, query: "abc123", categories: [])
        #expect(result == true)
    }
}
