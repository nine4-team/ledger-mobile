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
    transactionType: TransactionType? = nil,
    notes: String? = nil,
    purchasedBy: String? = nil,
    budgetCategoryId: String? = nil,
    amountCents: Int? = nil,
    isCanonicalInventorySale: Bool? = nil,
    inventorySaleDirection: InventorySaleDirection? = nil,
    status: TransactionStatus? = nil,
    isComplete: Bool? = nil
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
    tx.status = status
    tx.isComplete = isComplete
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

private func makeProtoItem(
    id: String? = nil,
    name: String? = nil,
    sku: String? = nil,
    notes: String? = nil,
    status: ProtoItemStatus? = nil,
    sourceHint: ProtoItemSourceHint? = nil,
    captureContext: ProtoItemCaptureContext? = nil,
    extractedSkuCandidates: [String]? = nil
) -> ProtoItem {
    var protoItem = ProtoItem()
    protoItem.id = id
    protoItem.name = name
    protoItem.sku = sku
    protoItem.notes = notes
    protoItem.status = status
    protoItem.sourceHint = sourceHint
    protoItem.captureContext = captureContext
    if let extractedSkuCandidates {
        var extracted = ProtoItemExtraction()
        extracted.skuCandidates = extractedSkuCandidates
        protoItem.extracted = extracted
    }
    return protoItem
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

// MARK: - Amount Match Tests

@Suite("Amount Prefix Match")
struct AmountMatchTests {

    // MARK: - amountMatch unit tests

    @Test("Partial dollar prefix: 637 matches $6,370.00")
    func partialDollarPrefix() {
        #expect(SearchCalculations.amountMatch(query: "637", cents: 637000) == true)
    }

    @Test("Full dollar: 6370 matches $6,370.00")
    func fullDollar() {
        #expect(SearchCalculations.amountMatch(query: "6370", cents: 637000) == true)
    }

    @Test("Trailing dot: 6370. matches $6,370.00")
    func trailingDot() {
        #expect(SearchCalculations.amountMatch(query: "6370.", cents: 637000) == true)
    }

    @Test("Full amount: 6370.00 matches $6,370.00")
    func fullAmount() {
        #expect(SearchCalculations.amountMatch(query: "6370.00", cents: 637000) == true)
    }

    @Test("Exact cents: 407.87 matches 40787")
    func exactCents() {
        #expect(SearchCalculations.amountMatch(query: "407.87", cents: 40787) == true)
    }

    @Test("Dollar prefix: 407 matches 40787")
    func dollarPrefix() {
        #expect(SearchCalculations.amountMatch(query: "407", cents: 40787) == true)
    }

    @Test("Dollar sign stripped: $6,370 matches 637000")
    func dollarSignAndCommaStripped() {
        #expect(SearchCalculations.amountMatch(query: "$6,370", cents: 637000) == true)
    }

    @Test("No false positive: 29 does NOT match $129.99")
    func noFalsePositive() {
        #expect(SearchCalculations.amountMatch(query: "29", cents: 12999) == false)
    }

    @Test("29 matches $29.99")
    func shortQueryMatches() {
        #expect(SearchCalculations.amountMatch(query: "29", cents: 2999) == true)
    }

    @Test("Negative cents: 407 matches -40787 via abs")
    func negativeCents() {
        #expect(SearchCalculations.amountMatch(query: "407", cents: -40787) == true)
    }

    @Test("Non-numeric query returns false")
    func nonNumericQuery() {
        #expect(SearchCalculations.amountMatch(query: "lamp", cents: 4050) == false)
    }

    @Test("Empty query returns false")
    func emptyQuery() {
        #expect(SearchCalculations.amountMatch(query: "", cents: 4050) == false)
    }

    @Test("Just dollar sign returns false")
    func justDollarSign() {
        #expect(SearchCalculations.amountMatch(query: "$", cents: 4050) == false)
    }

    @Test("Zero cents: 0 matches $0.00")
    func zeroCents() {
        #expect(SearchCalculations.amountMatch(query: "0", cents: 0) == true)
    }

    // MARK: - Integration with entity matchers

    @Test("Item amount match on purchasePriceCents")
    func itemAmountMatch() {
        let item = makeItem(purchasePriceCents: 637000)
        #expect(SearchCalculations.itemMatches(item: item, query: "637", categories: []) == true)
    }

    @Test("Item amount match on projectPriceCents")
    func itemProjectPriceMatch() {
        let item = makeItem(projectPriceCents: 4050)
        #expect(SearchCalculations.itemMatches(item: item, query: "40", categories: []) == true)
    }

    @Test("Item amount match on marketValueCents")
    func itemMarketValueMatch() {
        let item = makeItem(marketValueCents: 4050)
        #expect(SearchCalculations.itemMatches(item: item, query: "40", categories: []) == true)
    }

    @Test("Transaction amount match")
    func transactionAmountMatch() {
        let tx = makeTransaction(amountCents: 4050)
        #expect(SearchCalculations.transactionMatches(transaction: tx, query: "40", categories: []) == true)
    }

    @Test("Transaction amount no match")
    func transactionAmountNoMatch() {
        let tx = makeTransaction(amountCents: 5050)
        #expect(SearchCalculations.transactionMatches(transaction: tx, query: "40", categories: []) == false)
    }

    @Test("Inventory amount search includes active and canceled transactions with nil project scope")
    func inventoryAmountSearchIncludesBothProjectIdRepresentations() {
        let activeID = "hrjMH82zVSLejOKricfF"
        let canceledID = "kZG8HFTrF8hQqF51R37K"
        let transactions = [
            makeTransaction(id: activeID, amountCents: 119_821),
            makeTransaction(id: canceledID, amountCents: 119_821, status: .canceled),
            {
                var transaction = makeTransaction(id: "project-transaction", amountCents: 119_821)
                transaction.projectId = "project-1"
                return transaction
            }(),
        ]

        let inventoryTransactions = ScopeFilters.transactions(transactions, scope: .inventory)
        let results = SearchCalculations.search(
            query: "1198.21",
            items: [],
            transactions: inventoryTransactions,
            spaces: [],
            categories: []
        )

        #expect(Set(results.transactions.compactMap(\.id)) == [activeID, canceledID])
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
        let tx = makeTransaction(transactionType: .purchase)
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

    @Test("Proto item name match")
    func protoItemNameMatch() {
        let protoItem = makeProtoItem(name: "Brass Lamp")
        let result = SearchCalculations.protoItemMatches(protoItem: protoItem, query: "lamp")
        #expect(result == true)
    }

    @Test("Proto item normalized SKU match")
    func protoItemNormalizedSkuMatch() {
        let protoItem = makeProtoItem(sku: "ABC-123")
        let result = SearchCalculations.protoItemMatches(protoItem: protoItem, query: "abc123")
        #expect(result == true)
    }

    @Test("Proto item extracted SKU candidate match")
    func protoItemExtractedSkuCandidateMatch() {
        let protoItem = makeProtoItem(extractedSkuCandidates: ["HD/400-XYZ"])
        let result = SearchCalculations.protoItemMatches(protoItem: protoItem, query: "400xyz")
        #expect(result == true)
    }

    @Test("Proto item status and source hint match")
    func protoItemStatusAndSourceHintMatch() {
        let protoItem = makeProtoItem(status: .inReview, sourceHint: .fromInventory)
        #expect(SearchCalculations.protoItemMatches(protoItem: protoItem, query: "in review") == true)
        #expect(SearchCalculations.protoItemMatches(protoItem: protoItem, query: "from_inventory") == true)
    }
}

// MARK: - Full Search Tests

@Suite("Full Search Function")
struct FullSearchTests {

    @Test("Empty query returns all results")
    func emptyQueryReturnsAll() {
        let items = [makeItem(name: "A"), makeItem(name: "B")]
        let protoItems = [makeProtoItem(name: "Draft")]
        let transactions = [makeTransaction(source: "X")]
        let spaces = [makeSpace(name: "Y")]

        let result = SearchCalculations.search(
            query: "",
            items: items,
            protoItems: protoItems,
            transactions: transactions,
            spaces: spaces,
            categories: []
        )
        #expect(result.items.count == 2)
        #expect(result.protoItems.count == 1)
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
        let protoItems = [makeProtoItem(name: "Lamp Draft"), makeProtoItem(name: "Sofa Draft")]
        let transactions = [makeTransaction(source: "Lamp Store"), makeTransaction(source: "IKEA")]
        let spaces = [makeSpace(name: "Lamp Room"), makeSpace(name: "Kitchen")]

        let result = SearchCalculations.search(
            query: "lamp",
            items: items,
            protoItems: protoItems,
            transactions: transactions,
            spaces: spaces,
            categories: []
        )
        #expect(result.items.count == 1)
        #expect(result.items[0].name == "Table Lamp")
        #expect(result.protoItems.count == 1)
        #expect(result.protoItems[0].name == "Lamp Draft")
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

    @Test("Canonical inventory sale with businessToProject → Purchase from Inventory")
    func canonicalBusinessToProject() {
        let tx = makeTransaction(
            isCanonicalInventorySale: true,
            inventorySaleDirection: .businessToProject
        )
        #expect(SearchCalculations.transactionDisplayName(for: tx) == "Purchase from Inventory")
    }

    @Test("Canonical inventory sale with projectToBusiness → Sale to Inventory")
    func canonicalProjectToBusiness() {
        let tx = makeTransaction(
            isCanonicalInventorySale: true,
            inventorySaleDirection: .projectToBusiness
        )
        #expect(SearchCalculations.transactionDisplayName(for: tx) == "Sale to Inventory")
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

    @Test("Search matches Sale to Inventory label")
    func searchMatchesSaleToInventory() {
        let tx = makeTransaction(
            isCanonicalInventorySale: true,
            inventorySaleDirection: .projectToBusiness
        )
        let result = SearchCalculations.transactionMatches(transaction: tx, query: "sale to", categories: [])
        #expect(result == true)
    }

    @Test("Search matches ID prefix when no source")
    func searchMatchesIdPrefix() {
        let tx = makeTransaction(id: "abc123def456")
        let result = SearchCalculations.transactionMatches(transaction: tx, query: "abc123", categories: [])
        #expect(result == true)
    }

    @Test("Transaction picker search matches source")
    func transactionPickerSearchMatchesSource() {
        let tx = makeTransaction(source: "Home Depot", amountCents: 5000)
        let result = SearchCalculations.transactionPickerMatches(transaction: tx, query: "depot")
        #expect(result == true)
    }

    @Test("Transaction picker search matches amount")
    func transactionPickerSearchMatchesAmount() {
        let tx = makeTransaction(source: "Home Depot", amountCents: 167143)
        let result = SearchCalculations.transactionPickerMatches(transaction: tx, query: "$1,671")
        #expect(result == true)
    }

    @Test("Transaction picker search matches transaction ID")
    func transactionPickerSearchMatchesTransactionID() {
        let tx = makeTransaction(id: "abc123def456", transactionType: .purchase, notes: "sofa", amountCents: 5000)
        let result = SearchCalculations.transactionPickerMatches(transaction: tx, query: "123def")
        #expect(result == true)
    }

    @Test("Matching transaction ID returns visible card context")
    func matchingTransactionIDReturnsID() {
        let tx = makeTransaction(id: "abc123def456")
        #expect(SearchCalculations.matchingTransactionID(transaction: tx, query: "123DEF") == "abc123def456")
        #expect(SearchCalculations.matchingTransactionID(transaction: tx, query: "unrelated") == nil)
        #expect(SearchCalculations.matchingTransactionID(transaction: tx, query: "  ") == nil)
    }

    @Test("Transaction picker search ignores unrelated fields")
    func transactionPickerSearchIgnoresUnrelatedFields() {
        let tx = makeTransaction(id: "abc123def456", transactionType: .purchase, notes: "sofa", amountCents: 5000)
        let result = SearchCalculations.transactionPickerMatches(transaction: tx, query: "sofa")
        #expect(result == false)
    }
}

// MARK: - Centralized Search Path Tests

@Suite("Centralized Search via List Calculations")
struct CentralizedSearchTests {

    @Test("TransactionFilterSortCalculations.applySearch matches amount query")
    func transactionListAmountSearch() {
        let tx = makeTransaction(amountCents: 167143)
        let results = TransactionFilterSortCalculations.applySearch([tx], query: "1671")
        #expect(results.count == 1)
    }

    @Test("TransactionFilterSortCalculations.applySearch matches transactionType")
    func transactionListTypeSearch() {
        let tx = makeTransaction(transactionType: .purchase)
        let results = TransactionFilterSortCalculations.applySearch([tx], query: "purchase")
        #expect(results.count == 1)
    }

    @Test("TransactionFilterSortCalculations.applySearch matches dollar amount with symbol")
    func transactionListDollarSearch() {
        let tx = makeTransaction(amountCents: 167143)
        let results = TransactionFilterSortCalculations.applySearch([tx], query: "$1,671")
        #expect(results.count == 1)
    }

    @Test("TransactionFilterSortCalculations.applySearch excludes non-matching")
    func transactionListNoMatch() {
        let tx = makeTransaction(source: "Home Depot", amountCents: 5000)
        let results = TransactionFilterSortCalculations.applySearch([tx], query: "9999")
        #expect(results.isEmpty)
    }

    @Test("TransactionFilterSortCalculations.applySearch treats whitespace and newlines as empty")
    func transactionListWhitespaceSearch() {
        let transactions = [makeTransaction(id: "one"), makeTransaction(id: "two")]
        let results = TransactionFilterSortCalculations.applySearch(transactions, query: " \n ")
        #expect(results.count == 2)
    }

    @Test("ListFilterSortCalculations.applySearch matches item amount")
    func itemListAmountSearch() {
        let item = makeItem(purchasePriceCents: 5099)
        let results = ListFilterSortCalculations.applySearch([item], query: "$50")
        #expect(results.count == 1)
    }

    @Test("ListFilterSortCalculations.applySearch matches normalized SKU")
    func itemListNormalizedSKU() {
        let item = makeItem(sku: "ABC-123")
        let results = ListFilterSortCalculations.applySearch([item], query: "abc123")
        #expect(results.count == 1)
    }

    @Test("ListFilterSortCalculations.applySearch empty query returns all")
    func itemListEmptyQuery() {
        let items = [makeItem(name: "A"), makeItem(name: "B")]
        let results = ListFilterSortCalculations.applySearch(items, query: "  ")
        #expect(results.count == 2)
    }

    @Test("Default categories parameter works without explicit []")
    func defaultCategoriesParam() {
        let tx = makeTransaction(source: "Amazon")
        let result = SearchCalculations.transactionMatches(transaction: tx, query: "amazon")
        #expect(result == true)
    }
}

@Suite("Inventory Transaction Grouping")
struct InventoryTransactionGroupingTests {

    @Test("Active search renders matching inventory movements as individual rows")
    func searchUngroupsInventoryMovements() {
        var purchase = makeTransaction(
            id: "purchase-1",
            source: "Wayfair",
            transactionType: .purchase,
            amountCents: 12000
        )
        purchase.projectId = nil

        let rows = TransactionFilterSortCalculations.rows(
            for: [purchase],
            scope: .inventory,
            search: "purchase-1"
        )

        guard case .transaction(let transaction) = rows.first else {
            Issue.record("Expected search results to render as individual transaction rows")
            return
        }
        #expect(transaction.id == "purchase-1")
    }

    @Test("Active search renders project inventory movements as individual rows")
    func searchUngroupsProjectInventoryMovements() {
        var purchase = makeTransaction(
            id: "project-purchase-1",
            source: "1584 Design Inventory",
            transactionType: .purchase,
            budgetCategoryId: "furnishings",
            amountCents: 12000
        )
        purchase.projectId = "project-1"

        let rows = TransactionFilterSortCalculations.rows(
            for: [purchase],
            scope: .project,
            search: "project-purchase-1"
        )

        guard case .transaction(let transaction) = rows.first else {
            Issue.record("Expected project search results to render as individual transaction rows")
            return
        }
        #expect(transaction.id == "project-purchase-1")
    }

    @Test("Whitespace-only search preserves inventory grouping")
    func whitespaceSearchPreservesGrouping() {
        var purchase = makeTransaction(
            id: "purchase-1",
            source: "Wayfair",
            transactionType: .purchase,
            amountCents: 12000
        )
        purchase.projectId = nil

        let rows = TransactionFilterSortCalculations.rows(
            for: [purchase],
            scope: .inventory,
            search: " \n "
        )

        guard case .inventoryGroup = rows.first else {
            Issue.record("Expected whitespace-only search to preserve grouping")
            return
        }
    }

    @Test("Inventory purchases group only in inventory scope")
    func inventoryPurchasesGroupOnlyInInventoryScope() {
        var purchase = makeTransaction(
            id: "purchase-1",
            source: "Wayfair",
            transactionType: .purchase,
            amountCents: 12000
        )
        purchase.transactionDate = "2026-05-09"
        purchase.projectId = nil
        purchase.itemIds = ["item-1"]

        let inventoryRows = TransactionFilterSortCalculations.groupedRows(
            for: [purchase],
            scope: .inventory
        )
        let projectRows = TransactionFilterSortCalculations.groupedRows(
            for: [purchase],
            scope: .project
        )

        guard case .inventoryGroup(let group) = inventoryRows.first else {
            Issue.record("Expected inventory purchase to render as an inventory group")
            return
        }
        #expect(group.title == "Added to Business Inventory")
        #expect(group.amountCents == 12000)
        #expect(group.itemCount == 1)

        guard case .transaction = projectRows.first else {
            Issue.record("Project scope should not group a normal purchase")
            return
        }
    }

    @Test("Inventory sale groups by category and does not merge returns")
    func saleGroupsDoNotMergeWithReturns() {
        var sale = makeTransaction(
            id: "sale-1",
            source: "1584 Design Inventory",
            transactionType: .sale,
            budgetCategoryId: "furnishings",
            amountCents: 8000
        )
        sale.transactionDate = "2026-05-09"
        sale.projectId = "project-1"
        sale.itemIds = ["item-1"]

        var returnTx = makeTransaction(
            id: "return-1",
            source: "1584 Design Inventory",
            transactionType: .return,
            amountCents: 8000
        )
        returnTx.transactionDate = "2026-05-09"
        returnTx.projectId = "project-1"
        returnTx.itemIds = ["item-1"]

        let rows = TransactionFilterSortCalculations.groupedRows(
            for: [sale, returnTx],
            scope: .project
        )

        #expect(rows.count == 2)
        let titles = rows.compactMap { row -> String? in
            if case .inventoryGroup(let group) = row { return group.title }
            return nil
        }
        #expect(titles.contains("Sold to 1584 Design Inventory"))
        #expect(titles.contains("Returned to 1584 Design Inventory"))
    }

    @Test("Inventory purchases merge across different dates")
    func inventoryPurchasesMergeAcrossDates() {
        var older = makeTransaction(
            id: "purchase-old",
            source: "1584 Design Inventory",
            transactionType: .purchase,
            budgetCategoryId: "furnishings",
            amountCents: 3000
        )
        older.transactionDate = "2026-03-27"
        older.projectId = "project-1"
        older.itemIds = ["item-a"]

        var newer = makeTransaction(
            id: "purchase-new",
            source: "1584 Design Inventory",
            transactionType: .purchase,
            budgetCategoryId: "furnishings",
            amountCents: 5000
        )
        newer.transactionDate = "2026-06-21"
        newer.projectId = "project-1"
        newer.itemIds = ["item-b", "item-c"]

        let rows = TransactionFilterSortCalculations.groupedRows(
            for: [older, newer],
            scope: .project
        )

        #expect(rows.count == 1)
        guard case .inventoryGroup(let group) = rows.first else {
            Issue.record("Expected a single merged inventory group across dates")
            return
        }
        #expect(group.title == "From 1584 Design Inventory")
        #expect(group.amountCents == 8000)
        #expect(group.itemCount == 3)
        #expect(group.dateString == "2026-06-21")
    }

    @Test("Vendor returns remain ungrouped")
    func vendorReturnsRemainUngrouped() {
        var vendorReturn = makeTransaction(
            id: "return-1",
            source: "Wayfair",
            transactionType: .return,
            amountCents: 3000
        )
        vendorReturn.transactionDate = "2026-05-09"
        vendorReturn.projectId = "project-1"

        let rows = TransactionFilterSortCalculations.groupedRows(
            for: [vendorReturn],
            scope: .project
        )

        guard case .transaction(let tx) = rows.first else {
            Issue.record("Vendor return should stay as a normal transaction row")
            return
        }
        #expect(tx.id == "return-1")
    }
}

@Suite("Transaction Needs Review Filter")
struct TransactionNeedsReviewFilterTests {

    @Test("Needs review filter excludes canceled transactions")
    func canceledTransactionsExcluded() {
        let incomplete = makeTransaction(source: "Incomplete")
        let canceled = makeTransaction(source: "Canceled", status: .canceled)
        let results = TransactionFilterSortCalculations.applyFilter(
            [incomplete, canceled], filter: .needsReview
        )
        #expect(results.count == 1)
        #expect(results.first?.source == "Incomplete")
    }

    @Test("Needs review filter includes incomplete non-canceled transactions")
    func incompleteNonCanceledIncluded() {
        let tx = makeTransaction(source: "Pending", isComplete: false)
        let results = TransactionFilterSortCalculations.applyFilter([tx], filter: .needsReview)
        #expect(results.count == 1)
    }

    @Test("Needs review filter excludes completed transactions")
    func completedExcluded() {
        let tx = makeTransaction(source: "Done", isComplete: true)
        let results = TransactionFilterSortCalculations.applyFilter([tx], filter: .needsReview)
        #expect(results.isEmpty)
    }
}
