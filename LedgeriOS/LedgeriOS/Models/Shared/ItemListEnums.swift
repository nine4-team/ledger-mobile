import Foundation

enum ItemFilterOption: String, CaseIterable {
    case all
    case bookmarked
    case fromInventory = "from-inventory"
    case toReturn = "to-return"
    case returned
    case noSku = "no-sku"
    case noName = "no-name"
    case noProjectPrice = "no-project-price"
    case noImage = "no-image"
    case noSpace = "no-space"
    case noTransaction = "no-transaction"
    case hasTransaction = "has-transaction"
    case uncategorized
}

/// Selection semantics for a single grouped item-filter facet.
///
/// `.allExcept` is intentionally distinct from `.only`: source and space option
/// lists are data-driven, and users need both "everything except this" and
/// "only these values" without enumerating every value in persistent state.
enum ItemFacetSelection: Equatable {
    case all
    case only(Set<String>)
    case allExcept(Set<String>)

    var isActive: Bool {
        self != .all
    }

    func includes(_ value: String) -> Bool {
        switch self {
        case .all:
            return true
        case .only(let selected):
            return selected.contains(value)
        case .allExcept(let excluded):
            return !excluded.contains(value)
        }
    }

    mutating func selectAll() {
        self = .all
    }

    mutating func selectNone() {
        self = .only([])
    }

    mutating func toggle(_ value: String, availableValues: Set<String>) {
        switch self {
        case .all:
            self = .allExcept([value])

        case .allExcept(var excluded):
            if excluded.contains(value) {
                excluded.remove(value)
            } else {
                excluded.insert(value)
            }

            if excluded.isEmpty {
                self = .all
            } else if !availableValues.isEmpty, excluded.isSuperset(of: availableValues) {
                self = .only([])
            } else {
                self = .allExcept(excluded)
            }

        case .only(var selected):
            if selected.contains(value) {
                selected.remove(value)
            } else {
                selected.insert(value)
            }

            if !availableValues.isEmpty, selected.isSuperset(of: availableValues) {
                self = .all
            } else {
                self = .only(selected)
            }
        }
    }
}

struct ItemFilterState: Equatable {
    var status: ItemFacetSelection = .all
    var space: ItemFacetSelection = .all
    var source: ItemFacetSelection = .all
    var budgetCategory: ItemFacetSelection = .all
    var purchasedBy: ItemFacetSelection = .all
    var transaction: ItemFacetSelection = .all
    var bookmark: ItemFacetSelection = .all
    var image: ItemFacetSelection = .all
    var sku: ItemFacetSelection = .all
    var name: ItemFacetSelection = .all
    var projectPrice: ItemFacetSelection = .all

    var isActive: Bool {
        ItemFilterGroup.allCases.contains { selection(for: $0).isActive }
    }

    mutating func reset() {
        self = ItemFilterState()
    }

    func selection(for group: ItemFilterGroup) -> ItemFacetSelection {
        switch group {
        case .status: return status
        case .space: return space
        case .source: return source
        case .budgetCategory: return budgetCategory
        case .purchasedBy: return purchasedBy
        case .transaction: return transaction
        case .bookmark: return bookmark
        case .image: return image
        case .sku: return sku
        case .name: return name
        case .projectPrice: return projectPrice
        }
    }

    mutating func selectAll(group: ItemFilterGroup) {
        update(group: group) { $0.selectAll() }
    }

    mutating func selectNone(group: ItemFilterGroup) {
        update(group: group) { $0.selectNone() }
    }

    mutating func toggle(group: ItemFilterGroup, value: String, availableValues: Set<String>) {
        update(group: group) { $0.toggle(value, availableValues: availableValues) }
    }

    private mutating func update(
        group: ItemFilterGroup,
        mutation: (inout ItemFacetSelection) -> Void
    ) {
        switch group {
        case .status: mutation(&status)
        case .space: mutation(&space)
        case .source: mutation(&source)
        case .budgetCategory: mutation(&budgetCategory)
        case .purchasedBy: mutation(&purchasedBy)
        case .transaction: mutation(&transaction)
        case .bookmark: mutation(&bookmark)
        case .image: mutation(&image)
        case .sku: mutation(&sku)
        case .name: mutation(&name)
        case .projectPrice: mutation(&projectPrice)
        }
    }
}

enum ItemFilterGroup: CaseIterable {
    case status
    case space
    case source
    case budgetCategory
    case purchasedBy
    case transaction
    case bookmark
    case image
    case sku
    case name
    case projectPrice
}

enum ItemFilterValues {
    static let missing = "__missing__"
    static let yes = "yes"
    static let no = "no"
    static let yesNoValues: Set<String> = [yes, no]

    static var allStatusValues: Set<String> {
        Set(ItemStatus.allCases.map(\.rawValue) + [missing])
    }

    static func status(_ status: ItemStatus) -> String {
        status.rawValue
    }

    static func normalizedText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func status(for item: Item) -> String {
        item.status?.rawValue ?? missing
    }

    static func space(for item: Item) -> String {
        normalizedOptionalText(item.spaceId)
    }

    static func source(for item: Item) -> String {
        normalizedOptionalText(item.currentSource ?? item.source)
    }

    static func budgetCategory(for item: Item) -> String {
        normalizedOptionalText(item.budgetCategoryId, normalizeCase: false)
    }

    static func purchasedBy(for item: Item) -> String {
        let normalized = normalizedOptionalText(item.purchasedBy)
        guard normalized != missing else { return missing }
        if normalized.contains("client") { return "client-card" }
        if normalized.contains("design") || normalized.contains("business") { return "design-business" }
        return normalized
    }

    static func transaction(for item: Item) -> String {
        normalizedOptionalText(item.transactionId, normalizeCase: false) == missing ? no : yes
    }

    static func bookmark(for item: Item) -> String {
        item.bookmark == true ? yes : no
    }

    static func image(for item: Item) -> String {
        (item.images?.isEmpty == false) ? yes : no
    }

    static func sku(for item: Item) -> String {
        normalizedOptionalText(item.sku) == missing ? no : yes
    }

    static func name(for item: Item) -> String {
        normalizedText(item.displayName).isEmpty ? no : yes
    }

    static func projectPrice(for item: Item) -> String {
        (item.normalizedProjectPriceCents ?? 0) > 0 ? yes : no
    }

    private static func normalizedOptionalText(
        _ value: String?,
        normalizeCase: Bool = true
    ) -> String {
        guard let value else { return missing }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return missing }
        return normalizeCase ? trimmed.lowercased() : trimmed
    }
}

enum ItemSortOption: String, CaseIterable {
    case createdDesc = "created-desc"
    case createdAsc = "created-asc"
    case alphabeticalAsc = "alphabetical-asc"
    case alphabeticalDesc = "alphabetical-desc"
}
