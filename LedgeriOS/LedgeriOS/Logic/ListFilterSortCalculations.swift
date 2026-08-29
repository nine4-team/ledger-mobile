import Foundation

/// Pure functions for filtering, sorting, searching, and grouping item lists.
/// Used by SharedItemsList views and testable without SwiftUI.
enum ListFilterSortCalculations {

    // MARK: - Grouped Facet Filters

    /// Applies AND logic across facets. A facet's selection applies OR logic
    /// among the values it includes.
    static func applyGroupedFilters(
        _ items: [Item],
        filters: ItemFilterState,
        photoMarkedItemIDs: Set<String> = []
    ) -> [Item] {
        guard filters.isActive else { return items }

        return items.filter { item in
            filters.status.includes(ItemFilterValues.status(for: item))
                && filters.space.includes(ItemFilterValues.space(for: item))
                && filters.source.includes(ItemFilterValues.source(for: item))
                && filters.budgetCategory.includes(ItemFilterValues.budgetCategory(for: item))
                && filters.purchasedBy.includes(ItemFilterValues.purchasedBy(for: item))
                && filters.transaction.includes(ItemFilterValues.transaction(for: item))
                && filters.bookmark.includes(ItemFilterValues.bookmark(for: item))
                && filters.image.includes(ItemFilterValues.image(for: item))
                && filters.sku.includes(ItemFilterValues.sku(for: item))
                && filters.name.includes(ItemFilterValues.name(for: item))
                && filters.projectPrice.includes(ItemFilterValues.projectPrice(for: item))
                && filters.photoMark.includes(
                    ItemFilterValues.photoMark(for: item, markedItemIDs: photoMarkedItemIDs)
                )
        }
    }

    // MARK: - Filter Predicates

    /// Returns a predicate for the given filter option.
    static func filterPredicate(for option: ItemFilterOption) -> (Item) -> Bool {
        switch option {
        case .all:
            return { _ in true }
        case .bookmarked:
            return { $0.bookmark == true }
        case .fromInventory:
            return { item in
                let currentSource = item.currentSource?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let originalSource = item.source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !currentSource.isEmpty else { return false }
                return currentSource.localizedCaseInsensitiveContains("inventory")
                    && currentSource.caseInsensitiveCompare(originalSource) != .orderedSame
            }
        case .toReturn:
            return { $0.status == .toReturn }
        case .returned:
            return { $0.status == .returned }
        case .noSku:
            return { $0.sku == nil || $0.sku?.trimmingCharacters(in: .whitespaces).isEmpty == true }
        case .noName:
            return { $0.displayName.trimmingCharacters(in: .whitespaces).isEmpty }
        case .noProjectPrice:
            return { !hasMeaningfulProjectPrice($0) }
        case .noImage:
            return { $0.images == nil || $0.images?.isEmpty == true }
        case .noSpace:
            return { $0.spaceId == nil || $0.spaceId?.trimmingCharacters(in: .whitespaces).isEmpty == true }
        case .noTransaction:
            return { $0.transactionId == nil }
        case .hasTransaction:
            return { $0.transactionId != nil }
        case .uncategorized:
            return { $0.budgetCategoryId == nil || $0.budgetCategoryId?.trimmingCharacters(in: .whitespaces).isEmpty == true }
        }
    }

    /// Filters items by the given filter option.
    static func applyFilter(_ items: [Item], filter: ItemFilterOption) -> [Item] {
        items.filter(filterPredicate(for: filter))
    }

    // MARK: - Sort Comparators

    /// Returns a comparator for the given sort option.
    static func sortComparator(
        for option: ItemSortOption,
        photoMarkedItemIDs: Set<String> = []
    ) -> (Item, Item) -> Bool {
        switch option {
        case .createdDesc:
            return { a, b in
                let dateA = a.createdAt ?? .distantPast
                let dateB = b.createdAt ?? .distantPast
                if dateA != dateB { return dateA > dateB }
                return (a.id ?? "") > (b.id ?? "")
            }
        case .createdAsc:
            return { a, b in
                let dateA = a.createdAt ?? .distantPast
                let dateB = b.createdAt ?? .distantPast
                if dateA != dateB { return dateA < dateB }
                return (a.id ?? "") < (b.id ?? "")
            }
        case .alphabeticalAsc:
            return { a, b in
                let nameA = a.displayName.lowercased()
                let nameB = b.displayName.lowercased()
                if !nameA.isEmpty && !nameB.isEmpty {
                    return nameA.localizedCompare(nameB) == .orderedAscending
                }
                if !nameA.isEmpty { return true }
                if !nameB.isEmpty { return false }
                return (a.id ?? "") < (b.id ?? "")
            }
        case .alphabeticalDesc:
            return { a, b in
                let nameA = a.displayName.lowercased()
                let nameB = b.displayName.lowercased()
                if !nameA.isEmpty && !nameB.isEmpty {
                    return nameA.localizedCompare(nameB) == .orderedDescending
                }
                if !nameA.isEmpty { return true }
                if !nameB.isEmpty { return false }
                return (a.id ?? "") > (b.id ?? "")
            }
        case .photoUncheckedFirst, .photoCheckedFirst:
            let checkedFirst = option == .photoCheckedFirst
            let createdDescending = sortComparator(for: .createdDesc)
            return { a, b in
                let aIsMarked = a.id.map(photoMarkedItemIDs.contains) ?? false
                let bIsMarked = b.id.map(photoMarkedItemIDs.contains) ?? false
                if aIsMarked != bIsMarked {
                    return checkedFirst ? aIsMarked : !aIsMarked
                }
                return createdDescending(a, b)
            }
        }
    }

    /// Sorts items by the given sort option.
    static func applySort(
        _ items: [Item],
        sort: ItemSortOption,
        photoMarkedItemIDs: Set<String> = []
    ) -> [Item] {
        items.sorted(by: sortComparator(for: sort, photoMarkedItemIDs: photoMarkedItemIDs))
    }

    // MARK: - Search

    /// Filters items by a search query against name, SKU, notes, and source.
    /// Returns all items when query is empty or whitespace-only.
    static func applySearch(_ items: [Item], query: String) -> [Item] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }
        return items.filter { SearchCalculations.itemMatches(item: $0, query: trimmed) }
    }

    // MARK: - Available Filters

    /// Returns the filter options available for the given list scope.
    /// Inventory scope excludes project-specific filters (fromInventory, toReturn, returned).
    static func availableFilters(for scope: ListScope) -> [ItemFilterOption] {
        switch scope {
        case .inventory:
            return ItemFilterOption.allCases.filter { option in
                option != .fromInventory && option != .toReturn && option != .returned
            }
        case .project, .all:
            return ItemFilterOption.allCases
        }
    }

    // MARK: - Multi-Filter

    /// Filters items using UNION (OR) logic across multiple filter modes.
    /// An item is included if it matches ANY of the selected modes.
    /// Returns all items when modes is empty or contains `.all`.
    static func applyMultipleFilters(_ items: [Item], modes: Set<ItemFilterOption>) -> [Item] {
        if modes.isEmpty || modes.contains(.all) {
            return items
        }
        return items.filter { item in
            modes.contains { mode in
                filterPredicate(for: mode)(item)
            }
        }
    }

    // MARK: - Combined Pipeline

    /// Applies filter, search, and sort in sequence.
    static func applyAllFilters(
        _ items: [Item],
        filter: ItemFilterOption,
        sort: ItemSortOption,
        search: String
    ) -> [Item] {
        let filtered = applyFilter(items, filter: filter)
        let searched = applySearch(filtered, query: search)
        return applySort(searched, sort: sort)
    }

    /// Applies multi-filter, search, and sort in sequence.
    /// Uses UNION (OR) logic for the filter set.
    static func applyAllMultiFilters(
        _ items: [Item],
        filters: Set<ItemFilterOption>,
        sort: ItemSortOption,
        search: String
    ) -> [Item] {
        let filtered = applyMultipleFilters(items, modes: filters)
        let searched = applySearch(filtered, query: search)
        return applySort(searched, sort: sort)
    }

    /// Applies grouped facets, search, and sort in sequence.
    static func applyAllGroupedFilters(
        _ items: [Item],
        filters: ItemFilterState,
        sort: ItemSortOption,
        search: String,
        photoMarkedItemIDs: Set<String> = []
    ) -> [Item] {
        let filtered = applyGroupedFilters(
            items,
            filters: filters,
            photoMarkedItemIDs: photoMarkedItemIDs
        )
        let searched = applySearch(filtered, query: search)
        return applySort(searched, sort: sort, photoMarkedItemIDs: photoMarkedItemIDs)
    }

    // MARK: - Grouping

    /// Groups items by normalized SKU when available, falling back to name.
    /// SKU matches ignore name differences. SKU-less items join a matching
    /// name's SKU group only when that name identifies exactly one SKU group.
    /// Source remains a grouping boundary in both cases.
    /// Single items become groups of 1 for uniform list handling.
    static func groupItems(_ items: [Item], resolutionContext: [Item]? = nil) -> [ItemGroup] {
        guard !items.isEmpty else { return [] }

        typealias GroupAccumulator = (
            name: String,
            sku: String?,
            source: String?,
            hasSkuRepresentative: Bool,
            items: [Item]
        )

        // Discover all authoritative SKU groups before assigning SKU-less items.
        // This makes the result independent of whether resolved or unresolved
        // copies happen to appear first in the input.
        var skuGroupsByName: [NameGroupIdentity: Set<ItemGroupIdentity>] = [:]
        for item in resolutionContext ?? items {
            let sku = normalizedGroupingValue(item.sku)
            let name = normalizedGroupingValue(item.displayName)
            guard !sku.isEmpty, !name.isEmpty else { continue }

            let source = normalizedGroupingValue(item.source)
            let nameIdentity = NameGroupIdentity(source: source, name: name)
            skuGroupsByName[nameIdentity, default: []].insert(.sku(source: source, sku: sku))
        }

        var groupMap: [ItemGroupIdentity: GroupAccumulator] = [:]
        var keyOrder: [ItemGroupIdentity] = []

        for item in items {
            let identity = groupIdentity(for: item, skuGroupsByName: skuGroupsByName)
            let itemHasSku = !normalizedGroupingValue(item.sku).isEmpty

            if var group = groupMap[identity] {
                group.items.append(item)
                if itemHasSku, !group.hasSkuRepresentative {
                    group.name = item.displayName
                    group.sku = item.sku
                    group.source = item.source
                    group.hasSkuRepresentative = true
                }
                groupMap[identity] = group
            } else {
                groupMap[identity] = (
                    name: item.displayName,
                    sku: itemHasSku ? item.sku : nil,
                    source: item.source,
                    hasSkuRepresentative: itemHasSku,
                    items: [item]
                )
                keyOrder.append(identity)
            }
        }

        return keyOrder.compactMap { identity in
            guard let group = groupMap[identity] else { return nil }
            return ItemGroup(
                id: identity.id,
                name: group.name,
                sku: group.sku,
                source: group.source,
                items: group.items
            )
        }
    }

    /// Returns true if any group has more than one item.
    static func shouldShowGrouped(_ groups: [ItemGroup]) -> Bool {
        groups.contains { $0.count > 1 }
    }

    static func expandableGroupIDs(in groups: [ItemGroup]) -> Set<String> {
        Set(groups.lazy.filter { $0.count > 1 }.map(\.id))
    }

    static func toggledExpandedGroupIDs(
        expandedGroupIDs: Set<String>,
        visibleGroupIDs: Set<String>
    ) -> Set<String> {
        guard !visibleGroupIDs.isEmpty else { return expandedGroupIDs }
        if visibleGroupIDs.isSubset(of: expandedGroupIDs) {
            return expandedGroupIDs.subtracting(visibleGroupIDs)
        }
        return expandedGroupIDs.union(visibleGroupIDs)
    }

    static func isGroupFullyMarkedInPhoto(
        _ group: ItemGroup,
        markedItemIDs: Set<String>
    ) -> Bool {
        !group.items.isEmpty && group.items.allSatisfy { item in
            guard let itemID = item.id else { return false }
            return markedItemIDs.contains(itemID)
        }
    }

    // MARK: - Private Helpers

    /// Checks whether the normalized project price is positive.
    private static func hasMeaningfulProjectPrice(_ item: Item) -> Bool {
        (item.normalizedProjectPriceCents ?? 0) > 0
    }

    // MARK: - Labels

    /// Display label for a filter option.
    static func filterLabel(for option: ItemFilterOption) -> String {
        switch option {
        case .all: return "All"
        case .bookmarked: return "Bookmarked"
        case .fromInventory: return "From Inventory"
        case .toReturn: return "To Return"
        case .returned: return "Returned"
        case .noSku: return "No SKU"
        case .noName: return "No Name"
        case .noProjectPrice: return "No Project Price"
        case .noImage: return "No Image"
        case .noSpace: return "No Space"
        case .noTransaction: return "No Transaction"
        case .hasTransaction: return "Has Transaction"
        case .uncategorized: return "Uncategorized"
        }
    }

    /// Display label for a sort option.
    static func sortLabel(for option: ItemSortOption) -> String {
        switch option {
        case .createdDesc: return "Newest First"
        case .createdAsc: return "Oldest First"
        case .alphabeticalAsc: return "A to Z"
        case .alphabeticalDesc: return "Z to A"
        case .photoUncheckedFirst: return "Unchecked First"
        case .photoCheckedFirst: return "Checked First"
        }
    }

    /// Short label for active sort indicator.
    static func sortShortLabel(for option: ItemSortOption) -> String {
        switch option {
        case .createdDesc: return "Newest"
        case .createdAsc: return "Oldest"
        case .alphabeticalAsc: return "A-Z"
        case .alphabeticalDesc: return "Z-A"
        case .photoUncheckedFirst: return "Unchecked"
        case .photoCheckedFirst: return "Checked"
        }
    }

    private static func groupIdentity(
        for item: Item,
        skuGroupsByName: [NameGroupIdentity: Set<ItemGroupIdentity>]
    ) -> ItemGroupIdentity {
        let source = normalizedGroupingValue(item.source)
        let sku = normalizedGroupingValue(item.sku)
        if !sku.isEmpty {
            return .sku(source: source, sku: sku)
        }

        let name = normalizedGroupingValue(item.displayName)
        let nameIdentity = NameGroupIdentity(source: source, name: name)
        if !name.isEmpty,
           let candidates = skuGroupsByName[nameIdentity],
           candidates.count == 1,
           let onlyCandidate = candidates.first {
            return onlyCandidate
        }
        return .name(source: source, name: name)
    }

    private static func normalizedGroupingValue(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

private struct NameGroupIdentity: Hashable {
    let source: String
    let name: String
}

private enum ItemGroupIdentity: Hashable {
    case sku(source: String, sku: String)
    case name(source: String, name: String)

    var id: String {
        switch self {
        case let .sku(source, sku):
            return "sku::\(source)::\(sku)"
        case let .name(source, name):
            return "name::\(source)::\(name)"
        }
    }
}

// MARK: - ItemGroup

struct ItemGroup: Identifiable {
    let id: String
    let name: String
    let sku: String?
    let source: String?
    let items: [Item]

    var count: Int { items.count }
    var totalCents: Int { items.compactMap(\.normalizedProjectPriceCents).reduce(0, +) }
}
