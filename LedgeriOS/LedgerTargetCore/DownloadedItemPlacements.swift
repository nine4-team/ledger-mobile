import Foundation

public enum DownloadedItemPlacementsFailure: Error, Equatable, Sendable {
    case invalidRevision, invalidTimestamp, duplicateItem, scopeMismatch
}

/// Read-only physical facts. Item revision is not a placement mutation token.
public struct PhysicalItemPlacement: Equatable, Sendable {
    public let itemId: ItemID
    public let description: String
    public let name: String?
    public let sku: String?
    public let createdAt: Date?
    public var displayName: String { name ?? description }
    public let itemRevision: Int64
    public let placementId: EntityID
    public let scope: ItemPlacementScope
    public let spaceId: SpaceID?

    public init(itemId: ItemID, description: String, itemRevision: Int64,
                placementId: EntityID, scope: ItemPlacementScope, spaceId: SpaceID?,
                name: String? = nil, sku: String? = nil, createdAt: Date? = nil) throws {
        guard itemRevision > 0 else { throw DownloadedItemPlacementsFailure.invalidRevision }
        guard createdAt?.timeIntervalSinceReferenceDate.isFinite != false else {
            throw DownloadedItemPlacementsFailure.invalidTimestamp
        }
        self.itemId = itemId; self.description = description; self.itemRevision = itemRevision
        self.placementId = placementId; self.scope = scope; self.spaceId = spaceId
        self.name = name; self.sku = sku; self.createdAt = createdAt
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
    public init() {}
    public var isActive: Bool { name != .all || sku != .all }

    public func includes(_ row: PhysicalItemPlacement) -> Bool {
        name.includes(row.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "missing" : "has")
            && sku.includes((row.sku ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "missing" : "has")
    }
}

/// This query reports downloaded rows, never authoritative inventory totals or
/// accounting completeness. A missing row may simply not have downloaded yet.
public struct DownloadedItemPlacements: Equatable, Sendable {
    public let accountId: AccountID
    public let scope: ItemPlacementScope
    public let rows: [PhysicalItemPlacement]

    public init(accountId: AccountID, scope: ItemPlacementScope, rows: [PhysicalItemPlacement]) throws {
        var identities = Set<ItemID>()
        for row in rows {
            guard row.scope == scope else { throw DownloadedItemPlacementsFailure.scopeMismatch }
            guard identities.insert(row.itemId).inserted else { throw DownloadedItemPlacementsFailure.duplicateItem }
        }
        self.accountId = accountId; self.scope = scope; self.rows = rows
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
            filters.includes(row) && (term.isEmpty || [row.displayName, row.description, row.sku ?? ""]
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
