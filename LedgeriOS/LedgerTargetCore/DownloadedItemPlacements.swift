import Foundation

public enum DownloadedItemPlacementsFailure: Error, Equatable, Sendable {
    case invalidRevision, invalidTimestamp, invalidImageCount, duplicateItem, duplicateSpace, scopeMismatch
}

/// Read-only physical facts. Item revision is not a placement mutation token.
public struct PhysicalItemPlacement: Equatable, Sendable {
    public let itemId: ItemID
    public let description: String
    public let name: String?
    public let sku: String?
    public let source: String?
    public let currentSource: String?
    public var displaySource: String? { currentSource ?? source }
    public var sourceFacetValue: String { normalizedItemGroupingValue(displaySource) }
    public let createdAt: Date?
    public let workflowStatusRaw: String?
    public let isBookmarked: Bool?
    /// Nil means image metadata has not downloaded; only explicit zero proves No Image.
    public let imageCount: Int64?
    public var imageFacetValue: String {
        guard let imageCount else { return "unavailable" }
        return imageCount == 0 ? "missing" : "has"
    }
    public var workflowStatus: ItemWorkflowStatus { .init(sourceValue: workflowStatusRaw) }
    public var displayName: String { name ?? description }
    public let itemRevision: Int64
    public let placementId: EntityID
    public let scope: ItemPlacementScope
    public let spaceId: SpaceID?

    public init(itemId: ItemID, description: String, itemRevision: Int64,
                placementId: EntityID, scope: ItemPlacementScope, spaceId: SpaceID?,
                name: String? = nil, sku: String? = nil, createdAt: Date? = nil,
                workflowStatusRaw: String? = nil, isBookmarked: Bool? = nil,
                source: String? = nil, currentSource: String? = nil, imageCount: Int64? = nil) throws {
        guard itemRevision > 0 else { throw DownloadedItemPlacementsFailure.invalidRevision }
        guard createdAt?.timeIntervalSinceReferenceDate.isFinite != false else {
            throw DownloadedItemPlacementsFailure.invalidTimestamp
        }
        guard imageCount.map({ $0 >= 0 }) ?? true else { throw DownloadedItemPlacementsFailure.invalidImageCount }
        self.itemId = itemId; self.description = description; self.itemRevision = itemRevision
        self.placementId = placementId; self.scope = scope; self.spaceId = spaceId
        self.name = name; self.sku = sku; self.createdAt = createdAt
        self.workflowStatusRaw = workflowStatusRaw; self.isBookmarked = isBookmarked
        self.source = source; self.currentSource = currentSource
        self.imageCount = imageCount
    }
}

/// Descriptive workflow only: never evidence of purchase, sale, refund or payment.
/// Preserve the source value on the Item; aliases share a display/filter meaning.
public enum ItemWorkflowStatus: Equatable, Sendable {
    case toPurchase, purchased, toReturn, returned, notSet, unrecognized(String)

    public init(sourceValue: String?) {
        guard let sourceValue else { self = .notSet; return }
        switch sourceValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "": self = .notSet
        case "to-purchase", "to purchase": self = .toPurchase
        case "purchased": self = .purchased
        case "to return": self = .toReturn
        case "returned": self = .returned
        default: self = .unrecognized(sourceValue)
        }
    }

    public var displayLabel: String {
        switch self {
        case .toPurchase: "To Purchase"
        case .purchased: "Purchased"
        case .toReturn: "To Return"
        case .returned: "Returned"
        case .notSet: "Not Set"
        case .unrecognized(let raw): "Legacy status: \(raw)"
        }
    }

    public var facetValue: String {
        switch self {
        case .toPurchase: "to purchase"
        case .purchased: "purchased"
        case .toReturn: "to return"
        case .returned: "returned"
        case .notSet: "not set"
        case .unrecognized: "legacy"
        }
    }
}

public enum DownloadedItemOrder: String, CaseIterable, Sendable {
    case newest = "Newest first", oldest = "Oldest first"
    case nameAscending = "Name A–Z", nameDescending = "Name Z–A"
}

/// Selection owns stable physical identities, never rows or financial authority.
/// Callers supply their current scoped, filtered eligible IDs on every action.
public struct DownloadedItemSelection: Equatable, Sendable {
    public private(set) var ids: Set<ItemID> = []

    public init() {}

    public mutating func reconcile(visible: [ItemID]) {
        ids.formIntersection(visible)
    }

    public mutating func toggle(itemId: ItemID, visible: [ItemID]) {
        let eligible = Set(visible)
        ids.formIntersection(eligible)
        guard eligible.contains(itemId) else { return }
        if !ids.insert(itemId).inserted { ids.remove(itemId) }
    }

    public mutating func toggleAll(visible: [ItemID]) {
        let eligible = Set(visible)
        ids.formIntersection(eligible)
        if ids == eligible { ids.removeAll() }
        else { ids = eligible }
    }

    public mutating func toggleGroup(itemIds: [ItemID], visible: [ItemID]) {
        let eligible = Set(visible)
        ids.formIntersection(eligible)
        let group = Set(itemIds).intersection(eligible)
        guard !group.isEmpty else { return }
        if group.isSubset(of: ids) { ids.subtract(group) }
        else { ids.formUnion(group) }
    }

    public mutating func clear() { ids.removeAll() }

    public func isAllSelected(visible: [ItemID]) -> Bool {
        let eligible = Set(visible)
        return !eligible.isEmpty && eligible.isSubset(of: ids)
    }
}

/// Same All/None-then-toggle interaction as the shared Item facets. Keep Only
/// distinct from All-except so selection intent survives changing option sets.
public enum DownloadedItemFacetSelection: Equatable, Sendable {
    case all, only(Set<String>), allExcept(Set<String>)

    public func includes(_ value: String) -> Bool {
        switch self {
        case .all: true
        case .only(let values): values.contains(value)
        case .allExcept(let values): !values.contains(value)
        }
    }

    public mutating func toggle(_ value: String) {
        switch self {
        case .all: self = .allExcept([value])
        case .only(var values):
            if !values.insert(value).inserted { values.remove(value) }
            self = .only(values)
        case .allExcept(var values):
            if !values.insert(value).inserted { values.remove(value) }
            self = values.isEmpty ? .all : .allExcept(values)
        }
    }
}

public struct DownloadedItemFilters: Equatable, Sendable {
    public var name: DownloadedItemFacetSelection = .all
    public var sku: DownloadedItemFacetSelection = .all
    public var space: DownloadedItemFacetSelection = .all
    public var workflowStatus: DownloadedItemFacetSelection = .all
    public var bookmark: DownloadedItemFacetSelection = .all
    public var source: DownloadedItemFacetSelection = .all
    public var image: DownloadedItemFacetSelection = .all
    public init() {}
    public var isActive: Bool {
        name != .all || sku != .all || space != .all || workflowStatus != .all || bookmark != .all || source != .all || image != .all
    }

    public func includes(_ row: PhysicalItemPlacement) -> Bool {
        name.includes(row.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "missing" : "has")
            && sku.includes((row.sku ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "missing" : "has")
            && space.includes(row.spaceId?.rawValue ?? "")
            && workflowStatus.includes(row.workflowStatus.facetValue)
            && bookmark.includes(row.isBookmarked == true ? "bookmarked" : "not bookmarked")
            && source.includes(row.sourceFacetValue)
            && image.includes(row.imageFacetValue)
    }
}

private func normalizedItemGroupingValue(_ value: String?) -> String {
    (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

/// A presentation group never replaces its permanent physical Item identities.
/// Structured keys avoid collisions when vendor names/SKUs contain separators.
public struct DownloadedItemGroup: Equatable, Sendable, Identifiable {
    public enum ID: Hashable, Sendable {
        case sku(source: String, sku: String)
        case name(source: String, name: String)
    }
    public let id: ID
    public let representative: PhysicalItemPlacement
    public let rows: [PhysicalItemPlacement]
}

/// Current-scope local Space evidence for Item filtering, not an authoritative
/// directory. Empty string is reserved for the No Space facet; SpaceID forbids it.
public struct DownloadedItemSpace: Equatable, Sendable {
    public let id: SpaceID
    public let accountId: AccountID
    public let scope: ItemPlacementScope
    public let displayName: String?
    public let isArchived: Bool
    public init(id: SpaceID, accountId: AccountID, scope: ItemPlacementScope,
                displayName: String?, isArchived: Bool = false) {
        self.id = id; self.accountId = accountId; self.scope = scope
        self.displayName = displayName; self.isArchived = isArchived
    }
}

/// This query reports downloaded rows, never authoritative inventory totals or
/// accounting completeness. A missing row may simply not have downloaded yet.
public struct DownloadedItemPlacements: Equatable, Sendable {
    public let accountId: AccountID
    public let scope: ItemPlacementScope
    public let rows: [PhysicalItemPlacement]
    public let spaces: [DownloadedItemSpace]

    public init(accountId: AccountID, scope: ItemPlacementScope, rows: [PhysicalItemPlacement],
                spaces: [DownloadedItemSpace] = []) throws {
        var identities = Set<ItemID>()
        for row in rows {
            guard row.scope == scope else { throw DownloadedItemPlacementsFailure.scopeMismatch }
            guard identities.insert(row.itemId).inserted else { throw DownloadedItemPlacementsFailure.duplicateItem }
        }
        var spaceIds = Set<SpaceID>()
        let referencedSpaces = Set(rows.compactMap(\.spaceId))
        for space in spaces {
            guard space.accountId == accountId, space.scope == scope,
                  !space.isArchived || referencedSpaces.contains(space.id) else {
                throw DownloadedItemPlacementsFailure.scopeMismatch
            }
            guard spaceIds.insert(space.id).inserted else { throw DownloadedItemPlacementsFailure.duplicateSpace }
        }
        self.accountId = accountId; self.scope = scope; self.rows = rows; self.spaces = spaces
    }

    /// Keep referenced identities selectable when their labels have not arrived.
    /// Never infer an exhaustive directory from a partial local download.
    public var spaceChoices: [DownloadedItemSpace] {
        var values = Dictionary(uniqueKeysWithValues: spaces.map { ($0.id, $0) })
        for id in rows.compactMap(\.spaceId) where values[id] == nil {
            values[id] = .init(id: id, accountId: accountId, scope: scope, displayName: nil)
        }
        return values.values.sorted { left, right in
            let comparison = (left.displayName ?? "").localizedCaseInsensitiveCompare(right.displayName ?? "")
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return left.id.rawValue.utf8.lexicographicallyPrecedes(right.id.rawValue.utf8)
        }
    }

    /// Options reflect downloaded immediate-source labels, not original vendors
    /// hidden by the Inventory-origin label. An explicit blank stays blank.
    public func sourceChoices(in spaceId: SpaceID? = nil) -> [String] {
        var labels: [String: String] = [:]
        for row in rows(in: spaceId).sorted(by: { $0.itemId.rawValue < $1.itemId.rawValue }) {
            let key = row.sourceFacetValue
            guard !key.isEmpty, labels[key] == nil else { continue }
            labels[key] = row.displaySource?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return labels.keys.sorted().compactMap { labels[$0] }
    }

    /// Resolve SKU-less copies against the whole scoped download, not just the
    /// filtered rows: hiding a competing SKU must not silently merge identities.
    /// Only this snapshot's exact Items can enter a group; caller order is kept.
    public func groups(for itemIds: [ItemID], in spaceId: SpaceID? = nil) -> [DownloadedItemGroup] {
        let context = rows(in: spaceId)
        var candidates: [DownloadedItemGroup.ID: Set<DownloadedItemGroup.ID>] = [:]
        for row in context {
            let source = normalizedItemGroupingValue(row.source)
            let name = normalizedItemGroupingValue(row.displayName)
            let sku = normalizedItemGroupingValue(row.sku)
            if !name.isEmpty, !sku.isEmpty {
                candidates[.name(source: source, name: name), default: []].insert(.sku(source: source, sku: sku))
            }
        }
        let byId = Dictionary(uniqueKeysWithValues: context.map { ($0.itemId, $0) })
        var seen = Set<ItemID>()
        var order: [DownloadedItemGroup.ID] = []
        var grouped: [DownloadedItemGroup.ID: [PhysicalItemPlacement]] = [:]
        for itemId in itemIds {
            guard seen.insert(itemId).inserted, let row = byId[itemId] else { continue }
            let source = normalizedItemGroupingValue(row.source)
            let sku = normalizedItemGroupingValue(row.sku)
            let nameKey = DownloadedItemGroup.ID.name(source: source, name: normalizedItemGroupingValue(row.displayName))
            let key: DownloadedItemGroup.ID
            if !sku.isEmpty { key = .sku(source: source, sku: sku) }
            else if let matches = candidates[nameKey], matches.count == 1, let match = matches.first { key = match }
            else { key = nameKey }
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(row)
        }
        return order.compactMap { key in
            guard let members = grouped[key], let first = members.first else { return nil }
            let representative = members.first { !normalizedItemGroupingValue($0.sku).isEmpty } ?? first
            return .init(id: key, representative: representative, rows: members)
        }
    }

    /// A Space filter narrows an already Account/scope-bound download; it does
    /// not turn missing local rows into an authoritative zero count.
    public func rows(in spaceId: SpaceID?) -> [PhysicalItemPlacement] {
        guard let spaceId else { return rows }
        return rows.filter { row in
            row.spaceId.map { $0.rawValue.utf8.elementsEqual(spaceId.rawValue.utf8) } ?? false
        }
    }

    /// Search only downloaded descriptive fields. Unknown creation dates sort
    /// last in both directions; missing evidence is never a fabricated date.
    public func rows(in spaceId: SpaceID?, matching query: String, order: DownloadedItemOrder,
                     filters: DownloadedItemFilters = .init()) -> [PhysicalItemPlacement] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return rows(in: spaceId).filter { row in
            filters.includes(row) && (term.isEmpty || [row.displayName, row.description, row.sku ?? "", row.source ?? "", row.currentSource ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(term) })
        }.sorted { lhs, rhs in
            switch order {
            case .newest, .oldest:
                if let left = lhs.createdAt, let right = rhs.createdAt, left != right {
                    return order == .newest ? left > right : left < right
                }
                if (lhs.createdAt == nil) != (rhs.createdAt == nil) { return lhs.createdAt != nil }
            case .nameAscending, .nameDescending:
                let comparison = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                if comparison != .orderedSame {
                    return order == .nameAscending ? comparison == .orderedAscending : comparison == .orderedDescending
                }
            }
            return lhs.itemId.rawValue.utf8.lexicographicallyPrecedes(rhs.itemId.rawValue.utf8)
        }
    }
}

public protocol DownloadedItemPlacementReading: Sendable {
    func readDownloadedItemPlacements(accountId: AccountID, scope: ItemPlacementScope) async throws -> DownloadedItemPlacements
    func watchDownloadedItemPlacements(accountId: AccountID, scope: ItemPlacementScope) -> AsyncThrowingStream<DownloadedItemPlacements, Error>
}

/// Physical intervals only, not sales, refunds or financial history. Timestamps
/// retain their downloaded representation; absent labels do not erase IDs.
public struct PhysicalItemPlacementHistoryInterval: Equatable, Sendable {
    public let placementId: EntityID
    public let scope: ItemPlacementScope
    public let spaceId: SpaceID?
    public let projectDisplayName: String?
    public let spaceDisplayName: String?
    public let startedAt: String
    public let endedAt: String?

    public init(placementId: EntityID, scope: ItemPlacementScope, spaceId: SpaceID?,
                projectDisplayName: String? = nil, spaceDisplayName: String? = nil,
                startedAt: String, endedAt: String?) {
        self.placementId = placementId; self.scope = scope; self.spaceId = spaceId
        self.projectDisplayName = projectDisplayName; self.spaceDisplayName = spaceDisplayName
        self.startedAt = startedAt; self.endedAt = endedAt
    }
}

/// Newest intervals first. Never asserts complete history: older placements or
/// labels may not be downloaded, and financial provenance is not included.
public struct DownloadedItemPlacementHistory: Equatable, Sendable {
    public let accountId: AccountID
    public let itemId: ItemID
    public let description: String
    public let intervals: [PhysicalItemPlacementHistoryInterval]
    public var isPartial: Bool { true }

    public init(accountId: AccountID, itemId: ItemID, description: String,
                intervals: [PhysicalItemPlacementHistoryInterval]) throws {
        guard Set(intervals.map(\.placementId)).count == intervals.count else {
            throw DownloadedItemPlacementsFailure.duplicateItem
        }
        self.accountId = accountId; self.itemId = itemId; self.description = description
        self.intervals = intervals
    }
}

public protocol DownloadedItemPlacementHistoryReading: Sendable {
    func readDownloadedItemPlacementHistory(accountId: AccountID, itemId: ItemID) async throws -> DownloadedItemPlacementHistory
    func watchDownloadedItemPlacementHistory(accountId: AccountID, itemId: ItemID) -> AsyncThrowingStream<DownloadedItemPlacementHistory, Error>
}
