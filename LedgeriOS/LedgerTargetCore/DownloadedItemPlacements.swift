public enum DownloadedItemPlacementsFailure: Error, Equatable, Sendable {
    case invalidRevision, duplicateItem, scopeMismatch
}

/// Read-only physical facts. Item revision is not a placement mutation token.
public struct PhysicalItemPlacement: Equatable, Sendable {
    public let itemId: ItemID
    public let description: String
    public let itemRevision: Int64
    public let placementId: EntityID
    public let scope: ItemPlacementScope
    public let spaceId: SpaceID?

    public init(itemId: ItemID, description: String, itemRevision: Int64,
                placementId: EntityID, scope: ItemPlacementScope, spaceId: SpaceID?) throws {
        guard itemRevision > 0 else { throw DownloadedItemPlacementsFailure.invalidRevision }
        self.itemId = itemId; self.description = description; self.itemRevision = itemRevision
        self.placementId = placementId; self.scope = scope; self.spaceId = spaceId
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
