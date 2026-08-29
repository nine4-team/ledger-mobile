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
    status: ItemStatus? = nil,
    source: String? = nil,
    currentSource: String? = nil,
    projectId: String? = nil,
    spaceId: String? = nil,
    purchasedBy: String? = nil,
    budgetCategoryId: String? = nil,
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
    item.currentSource = currentSource
    item.projectId = projectId
    item.spaceId = spaceId
    item.purchasedBy = purchasedBy
    item.budgetCategoryId = budgetCategoryId
    item.projectPriceCents = projectPriceCents
    item.purchasePriceCents = purchasePriceCents
    item.images = images
    item.transactionId = transactionId
    item.createdAt = createdAt
    return item
}

@Suite("List Filter/Sort Calculation Tests")
struct ListFilterSortCalculationTests {

    // MARK: - Grouped Facet Selection

    @Test("Toggling a value from All excludes only that value")
    func facetSelectionExcludesFromAll() {
        var selection = ItemFacetSelection.all

        selection.toggle("purchased", availableValues: ["purchased", "returned", "sold"])

        #expect(selection.includes("returned"))
        #expect(selection.includes("sold"))
        #expect(!selection.includes("purchased"))
        #expect(selection.isActive)
    }

    @Test("Select None followed by a value creates an only selection")
    func facetSelectionBuildsOnlySelection() {
        var selection = ItemFacetSelection.all
        selection.selectNone()

        selection.toggle("space-1", availableValues: ["space-1", "space-2"])

        #expect(selection.includes("space-1"))
        #expect(!selection.includes("space-2"))
    }

    @Test("Status can show everything except purchased")
    func groupedStatusExcludesPurchased() {
        var filters = ItemFilterState()
        filters.status.toggle(
            ItemFilterValues.status(.purchased),
            availableValues: ItemFilterValues.allStatusValues
        )
        let items = [
            makeItem(name: "To buy", status: .toPurchase),
            makeItem(name: "Bought", status: .purchased),
            makeItem(name: "Returning", status: .toReturn),
            makeItem(name: "No status"),
        ]

        let result = ListFilterSortCalculations.applyGroupedFilters(items, filters: filters)

        #expect(result.map(\.name) == ["To buy", "Returning", "No status"])
    }

    @Test("Source exclusion uses current source and includes missing sources")
    func groupedSourceExcludesDisplayedInventorySource() {
        let inventorySource = ItemFilterValues.normalizedText("1584 Design Inventory")
        var filters = ItemFilterState()
        filters.source.toggle(
            inventorySource,
            availableValues: [inventorySource, ItemFilterValues.normalizedText("Wayfair"), ItemFilterValues.missing]
        )
        let items = [
            makeItem(name: "Inventory", source: "Wayfair", currentSource: "1584 DESIGN INVENTORY"),
            makeItem(name: "Direct", source: "Wayfair", currentSource: "Wayfair"),
            makeItem(name: "Missing"),
        ]

        let result = ListFilterSortCalculations.applyGroupedFilters(items, filters: filters)

        #expect(result.map(\.name) == ["Direct", "Missing"])
    }

    @Test("Grouped filters OR within a facet and AND across facets")
    func groupedFiltersCombineFacets() {
        var filters = ItemFilterState()
        filters.space.selectNone()
        let availableSpaces: Set<String> = ["living", "bedroom", "kitchen"]
        filters.space.toggle("living", availableValues: availableSpaces)
        filters.space.toggle("bedroom", availableValues: availableSpaces)
        filters.image.selectNone()
        filters.image.toggle(ItemFilterValues.no, availableValues: ItemFilterValues.yesNoValues)
        let items = [
            makeItem(name: "Living missing image", spaceId: "living"),
            makeItem(name: "Bedroom missing image", spaceId: "bedroom"),
            makeItem(name: "Living with image", spaceId: "living", images: [AttachmentRef(url: "image")]),
            makeItem(name: "Kitchen missing image", spaceId: "kitchen"),
        ]

        let result = ListFilterSortCalculations.applyGroupedFilters(items, filters: filters)

        #expect(result.map(\.name) == ["Living missing image", "Bedroom missing image"])
    }

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

    @Test("From inventory filter returns project items whose current source is inventory")
    func fromInventoryFilter() {
        let items = [
            makeItem(name: "From business inventory", source: "Wayfair", currentSource: "Business Inventory", projectId: "proj-1"),
            makeItem(name: "From account inventory", source: "Homegoods", currentSource: "1584 Design Inventory", projectId: "proj-1"),
            makeItem(name: "Currently in inventory", source: "Business Inventory", currentSource: "Business Inventory", projectId: nil),
            makeItem(name: "Direct project item", source: "Wayfair", currentSource: "Wayfair", projectId: "proj-1"),
            makeItem(name: "Legacy missing current source", source: "Wayfair", projectId: "proj-1"),
        ]
        let result = ListFilterSortCalculations.applyFilter(items, filter: .fromInventory)
        #expect(result.count == 2)
        #expect(result.map(\.name).contains("From business inventory"))
        #expect(result.map(\.name).contains("From account inventory"))
    }

    // MARK: - Filter: .toReturn

    @Test("To return filter returns items with 'to return' status")
    func toReturnFilter() {
        let items = [
            makeItem(name: "To return", status: .toReturn),
            makeItem(name: "Returned", status: .returned),
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
            makeItem(name: "Returned", status: .returned),
            makeItem(name: "To return", status: .toReturn),
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

    @Test("No project price filter returns only items without a normalized positive price")
    func noProjectPriceFilter() {
        let items = [
            makeItem(name: "No price"),
            makeItem(name: "Same as purchase", projectPriceCents: 1000, purchasePriceCents: 1000),
            makeItem(name: "Has price", projectPriceCents: 2000, purchasePriceCents: 1000),
            makeItem(name: "Price no purchase", projectPriceCents: 500),
        ]
        let result = ListFilterSortCalculations.applyFilter(items, filter: .noProjectPrice)
        #expect(result.count == 1)
        #expect(result.map(\.name).contains("No price"))
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

    // MARK: - Filter: .noSpace

    @Test("No space filter returns items without a spaceId")
    func noSpaceFilter() {
        let items = [
            makeItem(name: "No space nil"),
            makeItem(name: "No space empty", spaceId: ""),
            makeItem(name: "No space whitespace", spaceId: "  "),
            makeItem(name: "Has space", spaceId: "space-1"),
        ]
        let result = ListFilterSortCalculations.applyFilter(items, filter: .noSpace)
        #expect(result.count == 3)
        #expect(!result.map(\.name).contains("Has space"))
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

    @Test("Photo checkmark filter can show only unchecked space items")
    func photoCheckmarkFilterShowsUncheckedItems() {
        var filters = ItemFilterState()
        filters.selectOnly(group: .photoMark, value: ItemFilterValues.no)
        let items = [
            makeItem(id: "unchecked-1", name: "Lamp"),
            makeItem(id: "checked", name: "Chair"),
            makeItem(id: "unchecked-2", name: "Table"),
        ]

        let result = ListFilterSortCalculations.applyGroupedFilters(
            items,
            filters: filters,
            photoMarkedItemIDs: ["checked"]
        )

        #expect(result.compactMap(\.id) == ["unchecked-1", "unchecked-2"])
    }

    @Test("Photo checkmark filter can show only checked space items")
    func photoCheckmarkFilterShowsCheckedItems() {
        var filters = ItemFilterState()
        filters.selectOnly(group: .photoMark, value: ItemFilterValues.yes)
        let items = [
            makeItem(id: "unchecked", name: "Lamp"),
            makeItem(id: "checked-1", name: "Chair"),
            makeItem(id: "checked-2", name: "Table"),
        ]

        let result = ListFilterSortCalculations.applyGroupedFilters(
            items,
            filters: filters,
            photoMarkedItemIDs: ["checked-1", "checked-2"]
        )

        #expect(result.compactMap(\.id) == ["checked-1", "checked-2"])
    }

    @Test("Unchecked-first photo sort partitions items and preserves newest-first order")
    func photoCheckmarkSortShowsUncheckedFirst() {
        let items = [
            makeItem(id: "checked-new", name: "Checked New", createdAt: Date(timeIntervalSince1970: 4000)),
            makeItem(id: "unchecked-old", name: "Unchecked Old", createdAt: Date(timeIntervalSince1970: 1000)),
            makeItem(id: "checked-old", name: "Checked Old", createdAt: Date(timeIntervalSince1970: 2000)),
            makeItem(id: "unchecked-new", name: "Unchecked New", createdAt: Date(timeIntervalSince1970: 3000)),
        ]

        let result = ListFilterSortCalculations.applySort(
            items,
            sort: .photoUncheckedFirst,
            photoMarkedItemIDs: ["checked-new", "checked-old"]
        )

        #expect(result.compactMap(\.id) == [
            "unchecked-new",
            "unchecked-old",
            "checked-new",
            "checked-old",
        ])
    }

    @Test("Collapsed group is complete only when every item has a photo checkmark")
    func groupedPhotoCheckmarkRequiresEveryItem() {
        let group = ItemGroup(
            id: "pillows",
            name: "Pillow",
            sku: nil,
            source: nil,
            items: [
                makeItem(id: "pillow-1", name: "Pillow"),
                makeItem(id: "pillow-2", name: "Pillow"),
            ]
        )

        #expect(!ListFilterSortCalculations.isGroupFullyMarkedInPhoto(
            group,
            markedItemIDs: ["pillow-1"]
        ))
        #expect(ListFilterSortCalculations.isGroupFullyMarkedInPhoto(
            group,
            markedItemIDs: ["pillow-1", "pillow-2"]
        ))
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

    @Test("Groups matching SKUs even when names differ")
    func groupBySkuIgnoringName() {
        let items = [
            makeItem(name: "Chair", sku: "CH-1"),
            makeItem(name: "Blue upholstered chair", sku: "ch-1"),
            makeItem(name: "Table", sku: "TB-1"),
        ]
        let groups = ListFilterSortCalculations.groupItems(items)
        #expect(groups.count == 2)
        let chairGroup = groups.first { $0.name == "Chair" }
        #expect(chairGroup?.count == 2)
        let tableGroup = groups.first { $0.name == "Table" }
        #expect(tableGroup?.count == 1)
    }

    @Test("Groups SKU-less items by matching name")
    func groupWithoutSkuByName() {
        let items = [
            makeItem(name: "Chair"),
            makeItem(name: "  chair  ", sku: "  "),
            makeItem(name: "Table"),
        ]

        let groups = ListFilterSortCalculations.groupItems(items)

        #expect(groups.count == 2)
        #expect(groups.first { $0.name == "Chair" }?.count == 2)
    }

    @Test("Joins SKU-less name matches to an unambiguous SKU group")
    func groupWithoutSkuIntoUnambiguousSkuGroup() {
        let items = [
            makeItem(name: "Chair"),
            makeItem(name: "Chair", sku: "CH-1"),
            makeItem(name: "Different catalog name", sku: "CH-1"),
        ]

        let groups = ListFilterSortCalculations.groupItems(items)

        #expect(groups.count == 1)
        #expect(groups[0].count == 3)
        #expect(groups[0].sku == "CH-1")
    }

    @Test("Keeps SKU-less name matches separate when the name has multiple SKUs")
    func groupWithoutSkuStaysSeparateFromAmbiguousSkuGroups() {
        let items = [
            makeItem(name: "Dining Chair", sku: "CH-1"),
            makeItem(name: "Dining Chair"),
            makeItem(name: "Dining Chair", sku: "CH-2"),
        ]

        let groups = ListFilterSortCalculations.groupItems(items)

        #expect(groups.count == 3)
        #expect(groups.allSatisfy { $0.count == 1 })
        #expect(groups.filter { $0.sku == nil }.count == 1)
    }

    @Test("Uses the full resolution context when a filtered list hides an ambiguous SKU")
    func groupFilteredItemsUsingFullResolutionContext() {
        let skuOne = makeItem(name: "Dining Chair", sku: "CH-1")
        let unresolved = makeItem(name: "Dining Chair")
        let skuTwo = makeItem(name: "Dining Chair", sku: "CH-2")

        let groups = ListFilterSortCalculations.groupItems(
            [skuOne, unresolved],
            resolutionContext: [skuOne, unresolved, skuTwo]
        )

        #expect(groups.count == 2)
        #expect(groups.allSatisfy { $0.count == 1 })
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

    @Test("Project scope returns all filter options")
    func availableFiltersProjectScope() {
        let filters = ListFilterSortCalculations.availableFilters(for: .project("proj-1"))
        #expect(filters == ItemFilterOption.allCases)
    }

    @Test("Inventory scope excludes project-specific filters")
    func availableFiltersInventoryScope() {
        let filters = ListFilterSortCalculations.availableFilters(for: .inventory)
        #expect(!filters.contains(.fromInventory))
        #expect(!filters.contains(.toReturn))
        #expect(!filters.contains(.returned))
    }

    @Test("All scope returns all filter options")
    func availableFiltersAllScope() {
        let filters = ListFilterSortCalculations.availableFilters(for: .all)
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

    @Test("Group expansion toggles all visible multi-item groups without changing hidden groups")
    func groupExpansionTogglesVisibleGroups() {
        let groups = ListFilterSortCalculations.groupItems([
            makeItem(id: "chair-1", name: "Chair"),
            makeItem(id: "chair-2", name: "Chair"),
            makeItem(id: "table-1", name: "Table"),
            makeItem(id: "table-2", name: "Table"),
            makeItem(id: "lamp-1", name: "Lamp"),
        ])
        let visibleGroupIDs = ListFilterSortCalculations.expandableGroupIDs(in: groups)
        let hiddenExpandedID = "hidden-group"

        #expect(visibleGroupIDs.count == 2)

        let expanded = ListFilterSortCalculations.toggledExpandedGroupIDs(
            expandedGroupIDs: [hiddenExpandedID],
            visibleGroupIDs: visibleGroupIDs
        )
        #expect(visibleGroupIDs.isSubset(of: expanded))
        #expect(expanded.contains(hiddenExpandedID))

        let collapsed = ListFilterSortCalculations.toggledExpandedGroupIDs(
            expandedGroupIDs: expanded,
            visibleGroupIDs: visibleGroupIDs
        )
        #expect(collapsed == [hiddenExpandedID])
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
