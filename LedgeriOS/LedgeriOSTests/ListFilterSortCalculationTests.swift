import Foundation
import Testing
@testable import LedgeriOS

// Helper to create test items without Firebase dependencies
private func makeItem(
    id: String? = nil,
    name: String = "",
    sku: String? = nil,
    notes: String? = nil,
    bookmark: Bool? = nil,
    status: String? = nil,
    source: String? = nil,
    projectId: String? = nil,
    projectPriceCents: Int? = nil,
    purchasePriceCents: Int? = nil,
    images: [AttachmentRef]? = nil,
    transactionId: String? = nil,
    createdAt: Date? = nil
) -> Item {
    var item = Item()
    item.id = id
    item.name = name
    item.sku = sku
    item.notes = notes
    item.bookmark = bookmark
    item.status = status
    item.source = source
    item.projectId = projectId
    item.projectPriceCents = projectPriceCents
    item.purchasePriceCents = purchasePriceCents
    item.images = images
    item.transactionId = transactionId
    item.createdAt = createdAt
    return item
}

@Suite("List Filter/Sort Calculation Tests")
struct ListFilterSortCalculationTests {

    // MARK: - Filter: .all

    @Test("All filter returns every item")
    func allFilterReturnsAll() {
        let items = [
            makeItem(name: "A"),
            makeItem(name: "B"),
            makeItem(name: "C"),
        ]
        let result = ListFilterSortCalculations.applyFilter(items, filter: .all)
        #expect(result.count == 3)
    }

    // MARK: - Filter: .bookmarked

    @Test("Bookmarked filter returns only bookmarked items")
    func bookmarkedFilter() {
        let items = [
            makeItem(name: "Bookmarked", bookmark: true),
            makeItem(name: "Not bookmarked", bookmark: false),
            makeItem(name: "Nil bookmark"),
        ]
        let result = ListFilterSortCalculations.applyFilter(items, filter: .bookmarked)
        #expect(result.count == 1)
        #expect(result[0].name == "Bookmarked")
    }

    // MARK: - Filter: .fromInventory

    @Test("From inventory filter returns items without a projectId")
    func fromInventoryFilter() {
        let items = [
            makeItem(name: "Inventory item", projectId: nil),
            makeItem(name: "Project item", projectId: "proj-1"),
            makeItem(name: "Empty projectId", projectId: ""),
        ]
        let result = ListFilterSortCalculations.applyFilter(items, filter: .fromInventory)
        #expect(result.count == 2)
        #expect(result.map(\.name).contains("Inventory item"))
        #expect(result.map(\.name).contains("Empty projectId"))
    }

    // MARK: - Filter: .toReturn

    @Test("To return filter returns items with 'to return' status")
    func toReturnFilter() {
        let items = [
            makeItem(name: "To return", status: "to return"),
            makeItem(name: "Returned", status: "returned"),
            makeItem(name: "No status"),
        ]
        let result = ListFilterSortCalculations.applyFilter(items, filter: .toReturn)
        #expect(result.count == 1)
        #expect(result[0].name == "To return")
    }

    // MARK: - Filter: .returned

    @Test("Returned filter returns items with 'returned' status")
    func returnedFilter() {
        let items = [
            makeItem(name: "Returned", status: "returned"),
            makeItem(name: "To return", status: "to return"),
            makeItem(name: "No status"),
        ]
        let result = ListFilterSortCalculations.applyFilter(items, filter: .returned)
        #expect(result.count == 1)
        #expect(result[0].name == "Returned")
    }

    // MARK: - Filter: .noSku

    @Test("No SKU filter returns items with nil or empty SKU")
    func noSkuFilter() {
        let items = [
            makeItem(name: "No SKU nil"),
            makeItem(name: "No SKU empty", sku: ""),
            makeItem(name: "No SKU whitespace", sku: "  "),
            makeItem(name: "Has SKU", sku: "ABC-123"),
        ]
        let result = ListFilterSortCalculations.applyFilter(items, filter: .noSku)
        #expect(result.count == 3)
        #expect(!result.map(\.name).contains("Has SKU"))
    }

    // MARK: - Filter: .noName

    @Test("No name filter returns items with empty name")
    func noNameFilter() {
        let items = [
            makeItem(name: ""),
            makeItem(name: "  "),
            makeItem(name: "Has Name"),
        ]
        let result = ListFilterSortCalculations.applyFilter(items, filter: .noName)
        #expect(result.count == 2)
        #expect(!result.map(\.name).contains("Has Name"))
    }

    // MARK: - Filter: .noProjectPrice

    @Test("No project price filter returns items without meaningful project price")
    func noProjectPriceFilter() {
        let items = [
            makeItem(name: "No price"),
            makeItem(name: "Same as purchase", projectPriceCents: 1000, purchasePriceCents: 1000),
            makeItem(name: "Has price", projectPriceCents: 2000, purchasePriceCents: 1000),
            makeItem(name: "Price no purchase", projectPriceCents: 500),
        ]
        let result = ListFilterSortCalculations.applyFilter(items, filter: .noProjectPrice)
        #expect(result.count == 2)
        #expect(result.map(\.name).contains("No price"))
        #expect(result.map(\.name).contains("Same as purchase"))
    }

    // MARK: - Filter: .noImage

    @Test("No image filter returns items with no images")
    func noImageFilter() {
        let items = [
            makeItem(name: "No images nil"),
            makeItem(name: "No images empty", images: []),
            makeItem(name: "Has images", images: [AttachmentRef(url: "https://example.com/img.jpg")]),
        ]
        let result = ListFilterSortCalculations.applyFilter(items, filter: .noImage)
        #expect(result.count == 2)
        #expect(!result.map(\.name).contains("Has images"))
    }

    // MARK: - Filter: .noTransaction

    @Test("No transaction filter returns items without transactionId")
    func noTransactionFilter() {
        let items = [
            makeItem(name: "No transaction"),
            makeItem(name: "Has transaction", transactionId: "tx-1"),
        ]
        let result = ListFilterSortCalculations.applyFilter(items, filter: .noTransaction)
        #expect(result.count == 1)
        #expect(result[0].name == "No transaction")
    }

    // MARK: - Filter: empty input

    @Test("Filter on empty array returns empty")
    func filterEmptyInput() {
        let result = ListFilterSortCalculations.applyFilter([], filter: .bookmarked)
        #expect(result.isEmpty)
    }

    // MARK: - Sort: .createdDesc

    @Test("Created desc sorts newest first")
    func sortCreatedDesc() {
        let old = Date(timeIntervalSince1970: 1000)
        let mid = Date(timeIntervalSince1970: 2000)
        let recent = Date(timeIntervalSince1970: 3000)
        let items = [
            makeItem(name: "Old", createdAt: old),
            makeItem(name: "Recent", createdAt: recent),
            makeItem(name: "Mid", createdAt: mid),
        ]
        let result = ListFilterSortCalculations.applySort(items, sort: .createdDesc)
        #expect(result.map(\.name) == ["Recent", "Mid", "Old"])
    }

    // MARK: - Sort: .createdAsc

    @Test("Created asc sorts oldest first")
    func sortCreatedAsc() {
        let old = Date(timeIntervalSince1970: 1000)
        let mid = Date(timeIntervalSince1970: 2000)
        let recent = Date(timeIntervalSince1970: 3000)
        let items = [
            makeItem(name: "Recent", createdAt: recent),
            makeItem(name: "Old", createdAt: old),
            makeItem(name: "Mid", createdAt: mid),
        ]
        let result = ListFilterSortCalculations.applySort(items, sort: .createdAsc)
        #expect(result.map(\.name) == ["Old", "Mid", "Recent"])
    }

    // MARK: - Sort: .alphabeticalAsc

    @Test("Alphabetical asc sorts A before Z")
    func sortAlphabeticalAsc() {
        let items = [
            makeItem(name: "Zebra"),
            makeItem(name: "Apple"),
            makeItem(name: "Mango"),
        ]
        let result = ListFilterSortCalculations.applySort(items, sort: .alphabeticalAsc)
        #expect(result.map(\.name) == ["Apple", "Mango", "Zebra"])
    }

    // MARK: - Sort: .alphabeticalDesc

    @Test("Alphabetical desc sorts Z before A")
    func sortAlphabeticalDesc() {
        let items = [
            makeItem(name: "Apple"),
            makeItem(name: "Zebra"),
            makeItem(name: "Mango"),
        ]
        let result = ListFilterSortCalculations.applySort(items, sort: .alphabeticalDesc)
        #expect(result.map(\.name) == ["Zebra", "Mango", "Apple"])
    }

    @Test("Sort handles nil dates by treating them as distant past")
    func sortHandlesNilDates() {
        let recent = Date(timeIntervalSince1970: 3000)
        let items = [
            makeItem(name: "No date"),
            makeItem(name: "Has date", createdAt: recent),
        ]
        let result = ListFilterSortCalculations.applySort(items, sort: .createdDesc)
        #expect(result.map(\.name) == ["Has date", "No date"])
    }

    @Test("Alphabetical sort puts empty names last")
    func sortEmptyNamesLast() {
        let items = [
            makeItem(name: ""),
            makeItem(name: "Has Name"),
        ]
        let result = ListFilterSortCalculations.applySort(items, sort: .alphabeticalAsc)
        #expect(result.map(\.name) == ["Has Name", ""])
    }

    // MARK: - Search

    @Test("Search matches item name")
    func searchMatchesName() {
        let items = [
            makeItem(name: "Red Chair"),
            makeItem(name: "Blue Table"),
        ]
        let result = ListFilterSortCalculations.applySearch(items, query: "chair")
        #expect(result.count == 1)
        #expect(result[0].name == "Red Chair")
    }

    @Test("Search matches SKU")
    func searchMatchesSku() {
        let items = [
            makeItem(name: "Chair", sku: "CHAIR-001"),
            makeItem(name: "Table", sku: "TABLE-002"),
        ]
        let result = ListFilterSortCalculations.applySearch(items, query: "TABLE")
        #expect(result.count == 1)
        #expect(result[0].name == "Table")
    }

    @Test("Search matches notes")
    func searchMatchesNotes() {
        let items = [
            makeItem(name: "Chair", notes: "needs reupholstering"),
            makeItem(name: "Table", notes: "good condition"),
        ]
        let result = ListFilterSortCalculations.applySearch(items, query: "reupholstering")
        #expect(result.count == 1)
        #expect(result[0].name == "Chair")
    }

    @Test("Search is case insensitive")
    func searchCaseInsensitive() {
        let items = [
            makeItem(name: "Red Chair"),
        ]
        let result = ListFilterSortCalculations.applySearch(items, query: "RED CHAIR")
        #expect(result.count == 1)
    }

    @Test("Search with no match returns empty")
    func searchNoMatch() {
        let items = [
            makeItem(name: "Red Chair", sku: "CH-1", notes: "vintage"),
        ]
        let result = ListFilterSortCalculations.applySearch(items, query: "sofa")
        #expect(result.isEmpty)
    }

    @Test("Empty search query returns all items")
    func searchEmptyQueryReturnsAll() {
        let items = [
            makeItem(name: "A"),
            makeItem(name: "B"),
        ]
        let result = ListFilterSortCalculations.applySearch(items, query: "")
        #expect(result.count == 2)
    }

    @Test("Whitespace-only search query returns all items")
    func searchWhitespaceReturnsAll() {
        let items = [
            makeItem(name: "A"),
            makeItem(name: "B"),
        ]
        let result = ListFilterSortCalculations.applySearch(items, query: "   ")
        #expect(result.count == 2)
    }

    // MARK: - Grouping

    @Test("Groups items with same name and SKU together")
    func groupBySameNameAndSku() {
        let items = [
            makeItem(name: "Chair", sku: "CH-1"),
            makeItem(name: "Chair", sku: "CH-1"),
            makeItem(name: "Table", sku: "TB-1"),
        ]
        let groups = ListFilterSortCalculations.groupItems(items)
        #expect(groups.count == 2)
        let chairGroup = groups.first { $0.name == "Chair" }
        #expect(chairGroup?.count == 2)
        let tableGroup = groups.first { $0.name == "Table" }
        #expect(tableGroup?.count == 1)
    }

    @Test("All unique items produce groups of 1")
    func groupAllUnique() {
        let items = [
            makeItem(name: "Chair", sku: "CH-1"),
            makeItem(name: "Table", sku: "TB-1"),
            makeItem(name: "Lamp", sku: "LM-1"),
        ]
        let groups = ListFilterSortCalculations.groupItems(items)
        #expect(groups.count == 3)
        #expect(groups.allSatisfy { $0.count == 1 })
    }

    @Test("Empty items produce empty groups")
    func groupEmpty() {
        let groups = ListFilterSortCalculations.groupItems([])
        #expect(groups.isEmpty)
    }

    @Test("Group totalCents sums projectPriceCents")
    func groupTotalCents() {
        let items = [
            makeItem(name: "Chair", sku: "CH-1", projectPriceCents: 1000),
            makeItem(name: "Chair", sku: "CH-1", projectPriceCents: 2000),
            makeItem(name: "Chair", sku: "CH-1"),
        ]
        let groups = ListFilterSortCalculations.groupItems(items)
        #expect(groups.count == 1)
        #expect(groups[0].totalCents == 3000)
    }

    @Test("shouldShowGrouped returns true when any group has count > 1")
    func shouldShowGroupedTrue() {
        let items = [
            makeItem(name: "Chair", sku: "CH-1"),
            makeItem(name: "Chair", sku: "CH-1"),
            makeItem(name: "Table"),
        ]
        let groups = ListFilterSortCalculations.groupItems(items)
        #expect(ListFilterSortCalculations.shouldShowGrouped(groups) == true)
    }

    @Test("shouldShowGrouped returns false when all groups have count 1")
    func shouldShowGroupedFalse() {
        let items = [
            makeItem(name: "Chair"),
            makeItem(name: "Table"),
        ]
        let groups = ListFilterSortCalculations.groupItems(items)
        #expect(ListFilterSortCalculations.shouldShowGrouped(groups) == false)
    }

    @Test("Grouping is case-insensitive and trims whitespace")
    func groupCaseInsensitiveAndTrimmed() {
        let items = [
            makeItem(name: "Chair", sku: "CH-1"),
            makeItem(name: "  chair  ", sku: "ch-1"),
        ]
        let groups = ListFilterSortCalculations.groupItems(items)
        #expect(groups.count == 1)
        #expect(groups[0].count == 2)
    }

    // MARK: - Combined Pipeline

    @Test("Combined pipeline applies filter, search, and sort")
    func combinedPipeline() {
        let old = Date(timeIntervalSince1970: 1000)
        let recent = Date(timeIntervalSince1970: 3000)
        let items = [
            makeItem(name: "Blue Chair", bookmark: true, createdAt: old),
            makeItem(name: "Red Chair", bookmark: true, createdAt: recent),
            makeItem(name: "Green Table", bookmark: false),
        ]
        let result = ListFilterSortCalculations.applyAllFilters(
            items,
            filter: .bookmarked,
            sort: .createdDesc,
            search: "chair"
        )
        #expect(result.count == 2)
        #expect(result[0].name == "Red Chair")
        #expect(result[1].name == "Blue Chair")
    }

    // MARK: - Available Filters

    @Test("Project scope returns all 10 filter options")
    func availableFiltersProjectScope() {
        let filters = ListFilterSortCalculations.availableFilters(for: .project("proj-1"))
        #expect(filters.count == 10)
        #expect(filters == ItemFilterOption.allCases)
    }

    @Test("Inventory scope returns 7 filter options excluding project-specific ones")
    func availableFiltersInventoryScope() {
        let filters = ListFilterSortCalculations.availableFilters(for: .inventory)
        #expect(filters.count == 7)
        #expect(!filters.contains(.fromInventory))
        #expect(!filters.contains(.toReturn))
        #expect(!filters.contains(.returned))
    }

    @Test("All scope returns all 10 filter options")
    func availableFiltersAllScope() {
        let filters = ListFilterSortCalculations.availableFilters(for: .all)
        #expect(filters.count == 10)
        #expect(filters == ItemFilterOption.allCases)
    }

    // MARK: - Multi-Filter

    @Test("Empty modes set returns all items")
    func multiFilterEmptyModesReturnsAll() {
        let items = [
            makeItem(name: "A", bookmark: true),
            makeItem(name: "B"),
            makeItem(name: "C", sku: "SKU-1"),
        ]
        let result = ListFilterSortCalculations.applyMultipleFilters(items, modes: [])
        #expect(result.count == 3)
    }

    @Test("Modes containing .all returns all items")
    func multiFilterAllModeReturnsAll() {
        let items = [
            makeItem(name: "A", bookmark: true),
            makeItem(name: "B"),
        ]
        let result = ListFilterSortCalculations.applyMultipleFilters(items, modes: [.all, .bookmarked])
        #expect(result.count == 2)
    }

    @Test("Single mode works same as single filter")
    func multiFilterSingleMode() {
        let items = [
            makeItem(name: "Bookmarked", bookmark: true),
            makeItem(name: "Not bookmarked", bookmark: false),
            makeItem(name: "Nil bookmark"),
        ]
        let multiResult = ListFilterSortCalculations.applyMultipleFilters(items, modes: [.bookmarked])
        let singleResult = ListFilterSortCalculations.applyFilter(items, filter: .bookmarked)
        #expect(multiResult.count == singleResult.count)
        #expect(multiResult.map(\.name) == singleResult.map(\.name))
    }

    @Test("Two modes uses OR logic — bookmarked + noSku returns items matching either")
    func multiFilterTwoModesOrLogic() {
        let items = [
            makeItem(name: "Bookmarked with SKU", sku: "ABC", bookmark: true),
            makeItem(name: "Not bookmarked no SKU"),
            makeItem(name: "Not bookmarked with SKU", sku: "DEF"),
        ]
        let result = ListFilterSortCalculations.applyMultipleFilters(items, modes: [.bookmarked, .noSku])
        #expect(result.count == 2)
        #expect(result.map(\.name).contains("Bookmarked with SKU"))
        #expect(result.map(\.name).contains("Not bookmarked no SKU"))
    }

    @Test("Item matching both modes appears once — no duplicates")
    func multiFilterNoDuplicates() {
        let items = [
            makeItem(name: "Bookmarked and no SKU", bookmark: true),
        ]
        let result = ListFilterSortCalculations.applyMultipleFilters(items, modes: [.bookmarked, .noSku])
        #expect(result.count == 1)
    }

    // MARK: - Search: source field

    @Test("Search matches source field")
    func searchMatchesSource() {
        let items = [
            makeItem(name: "Chair", source: "Restoration Hardware"),
            makeItem(name: "Table", source: "IKEA"),
        ]
        let result = ListFilterSortCalculations.applySearch(items, query: "restoration")
        #expect(result.count == 1)
        #expect(result[0].name == "Chair")
    }

    // MARK: - Grouping: source in key

    @Test("Items with same name and SKU but different source are separate groups")
    func groupDifferentSourceSeparateGroups() {
        let items = [
            makeItem(name: "Chair", sku: "CH-1", source: "Store A"),
            makeItem(name: "Chair", sku: "CH-1", source: "Store B"),
        ]
        let groups = ListFilterSortCalculations.groupItems(items)
        #expect(groups.count == 2)
        #expect(groups.allSatisfy { $0.count == 1 })
    }

    @Test("Items with same name, SKU, and source form one group")
    func groupSameSourceSameGroup() {
        let items = [
            makeItem(name: "Chair", sku: "CH-1", source: "Store A"),
            makeItem(name: "Chair", sku: "CH-1", source: "Store A"),
        ]
        let groups = ListFilterSortCalculations.groupItems(items)
        #expect(groups.count == 1)
        #expect(groups[0].count == 2)
    }

    @Test("ItemGroup.source property is populated from grouped items")
    func groupSourcePropertyPopulated() {
        let items = [
            makeItem(name: "Chair", sku: "CH-1", source: "Pottery Barn"),
            makeItem(name: "Chair", sku: "CH-1", source: "Pottery Barn"),
        ]
        let groups = ListFilterSortCalculations.groupItems(items)
        #expect(groups.count == 1)
        #expect(groups[0].source == "Pottery Barn")
    }

    @Test("Items with nil source group together")
    func groupNilSourceTogether() {
        let items = [
            makeItem(name: "Chair", sku: "CH-1"),
            makeItem(name: "Chair", sku: "CH-1"),
        ]
        let groups = ListFilterSortCalculations.groupItems(items)
        #expect(groups.count == 1)
        #expect(groups[0].count == 2)
        #expect(groups[0].source == nil)
    }

    @Test("Items with nil vs non-nil source are separate groups")
    func groupNilVsNonNilSourceSeparate() {
        let items = [
            makeItem(name: "Chair", sku: "CH-1"),
            makeItem(name: "Chair", sku: "CH-1", source: "Store A"),
        ]
        let groups = ListFilterSortCalculations.groupItems(items)
        #expect(groups.count == 2)
    }

    // MARK: - Combined Multi-Filter Pipeline

    @Test("applyAllMultiFilters applies multi-filter, search, and sort together")
    func combinedMultiFilterPipeline() {
        let old = Date(timeIntervalSince1970: 1000)
        let mid = Date(timeIntervalSince1970: 2000)
        let recent = Date(timeIntervalSince1970: 3000)
        let items = [
            makeItem(name: "Blue Chair", bookmark: true, createdAt: old),
            makeItem(name: "Red Chair", createdAt: recent),
            makeItem(name: "Green Table", bookmark: true, createdAt: mid),
            makeItem(name: "Yellow Lamp", sku: "HAS-SKU", createdAt: mid),
        ]
        // Filters: bookmarked OR noSku (union). Search: "chair" or "table".
        // bookmarked: Blue Chair, Green Table
        // noSku: Blue Chair, Red Chair, Green Table (all have nil SKU)
        // Union: Blue Chair, Red Chair, Green Table
        // Search "chair": Blue Chair, Red Chair
        // Sort createdDesc: Red Chair (recent), Blue Chair (old)
        let result = ListFilterSortCalculations.applyAllMultiFilters(
            items,
            filters: [.bookmarked, .noSku],
            sort: .createdDesc,
            search: "chair"
        )
        #expect(result.count == 2)
        #expect(result[0].name == "Red Chair")
        #expect(result[1].name == "Blue Chair")
    }

    @Test("applyAllMultiFilters with empty filters returns all items filtered by search and sort")
    func combinedMultiFilterEmptyFilters() {
        let old = Date(timeIntervalSince1970: 1000)
        let recent = Date(timeIntervalSince1970: 3000)
        let items = [
            makeItem(name: "Blue Chair", createdAt: old),
            makeItem(name: "Red Chair", createdAt: recent),
            makeItem(name: "Green Table", createdAt: old),
        ]
        let result = ListFilterSortCalculations.applyAllMultiFilters(
            items,
            filters: [],
            sort: .alphabeticalAsc,
            search: "chair"
        )
        #expect(result.count == 2)
        #expect(result[0].name == "Blue Chair")
        #expect(result[1].name == "Red Chair")
    }
}
