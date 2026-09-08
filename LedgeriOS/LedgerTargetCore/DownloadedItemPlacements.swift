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
