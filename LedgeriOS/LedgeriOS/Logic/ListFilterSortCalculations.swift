import Foundation

/// Pure functions for filtering, sorting, searching, and grouping item lists.
/// Used by SharedItemsList views and testable without SwiftUI.
enum ListFilterSortCalculations {

    // MARK: - Filter Predicates

    /// Returns a predicate for the given filter option.
    static func filterPredicate(for option: ItemFilterOption) -> (Item) -> Bool {
        switch option {
        case .all:
            return { _ in true }
        case .bookmarked:
            return { $0.bookmark == true }
        case .fromInventory:
            return { $0.projectId == nil || $0.projectId?.isEmpty == true }
        case .toReturn:
            return { $0.status == "to return" }
        case .returned:
            return { $0.status == "returned" }
        case .noSku:
            return { $0.sku == nil || $0.sku?.trimmingCharacters(in: .whitespaces).isEmpty == true }
        case .noName:
            return { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        case .noProjectPrice:
            return { !hasMeaningfulProjectPrice($0) }
        case .noImage:
            return { $0.images == nil || $0.images?.isEmpty == true }
        case .noTransaction:
            return { $0.transactionId == nil }
        }
    }

    /// Filters items by the given filter option.
    static func applyFilter(_ items: [Item], filter: ItemFilterOption) -> [Item] {
        items.filter(filterPredicate(for: filter))
    }

    // MARK: - Sort Comparators

    /// Returns a comparator for the given sort option.
    static func sortComparator(for option: ItemSortOption) -> (Item, Item) -> Bool {
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
                let nameA = a.name.lowercased()
                let nameB = b.name.lowercased()
                if !nameA.isEmpty && !nameB.isEmpty {
                    return nameA.localizedCompare(nameB) == .orderedAscending
                }
                if !nameA.isEmpty { return true }
                if !nameB.isEmpty { return false }
                return (a.id ?? "") < (b.id ?? "")
            }
        case .alphabeticalDesc:
            return { a, b in
                let nameA = a.name.lowercased()
                let nameB = b.name.lowercased()
                if !nameA.isEmpty && !nameB.isEmpty {
                    return nameA.localizedCompare(nameB) == .orderedDescending
                }
                if !nameA.isEmpty { return true }
                if !nameB.isEmpty { return false }
                return (a.id ?? "") > (b.id ?? "")
            }
        }
    }

    /// Sorts items by the given sort option.
    static func applySort(_ items: [Item], sort: ItemSortOption) -> [Item] {
        items.sorted(by: sortComparator(for: sort))
    }

    // MARK: - Search

    /// Filters items by a search query against name, SKU, notes, and source.
    /// Returns all items when query is empty or whitespace-only.
    static func applySearch(_ items: [Item], query: String) -> [Item] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }
        let needle = trimmed.lowercased()
        return items.filter { item in
            let haystack = [
                item.name,
                item.sku ?? "",
                item.notes ?? "",
                item.source ?? "",
            ].joined(separator: " ").lowercased()
            return haystack.contains(needle)
        }
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

    // MARK: - Grouping

    /// Groups items by normalized name + SKU + source key.
    /// Items with same name, SKU, and source form a single group.
    /// Single items become groups of 1 for uniform list handling.
    static func groupItems(_ items: [Item]) -> [ItemGroup] {
        guard !items.isEmpty else { return [] }

        var groupMap: [String: (name: String, sku: String?, source: String?, items: [Item])] = [:]
        var keyOrder: [String] = []

        for item in items {
            let key = groupKey(for: item)
            if groupMap[key] != nil {
                groupMap[key]?.items.append(item)
            } else {
                groupMap[key] = (name: item.name, sku: item.sku, source: item.source, items: [item])
                keyOrder.append(key)
            }
        }

        return keyOrder.compactMap { key in
            guard let group = groupMap[key] else { return nil }
            return ItemGroup(
                id: key,
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

    // MARK: - Private Helpers

    /// Checks if an item has a meaningful project price.
    /// A price is meaningful if it's set and differs from the purchase price.
    private static func hasMeaningfulProjectPrice(_ item: Item) -> Bool {
        guard let projectPrice = item.projectPriceCents else { return false }
        if let purchasePrice = item.purchasePriceCents, projectPrice == purchasePrice {
            return false
        }
        return true
    }

    /// Generates a grouping key from name + SKU + source, normalized to lowercase.
    private static func groupKey(for item: Item) -> String {
        let name = item.name.trimmingCharacters(in: .whitespaces).lowercased()
        let sku = (item.sku ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        let source = (item.source ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return "\(name)::\(sku)::\(source)"
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
    var totalCents: Int { items.compactMap(\.projectPriceCents).reduce(0, +) }
}
