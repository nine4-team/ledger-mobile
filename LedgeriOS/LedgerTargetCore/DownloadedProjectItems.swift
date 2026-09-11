/// Physical placements and accounting evidence captured from one local read.
/// Nil accounting means unavailable, never that the Items are Unaccounted.
public struct DownloadedProjectItems: Equatable, Sendable {
    public let placements: DownloadedItemPlacements
    public let accounting: ProjectItemAccountingSectionsSnapshot?

    public init(placements: DownloadedItemPlacements,
                accounting: ProjectItemAccountingSectionsSnapshot?) throws {
        guard case .project(let projectId) = placements.scope else {
            throw DownloadedItemPlacementsFailure.scopeMismatch
        }
        if let accounting {
            let spaces = Dictionary(uniqueKeysWithValues: placements.rows.map { ($0.itemId, $0.spaceId) })
            guard accounting.accountId == placements.accountId, accounting.projectId == projectId,
                  accounting.rows.count == placements.rows.count,
                  accounting.rows.allSatisfy({ row in
                      guard let space = spaces[row.evidence.itemId] else { return false }
                      return space == row.evidence.spaceId
                  }) else { throw DownloadedItemPlacementsFailure.scopeMismatch }
        }
        self.placements = placements
        self.accounting = accounting
    }
}

public protocol DownloadedProjectItemsReading: Sendable {
    func watchDownloadedProjectItems(accountId: AccountID, projectId: ProjectID)
        -> AsyncThrowingStream<DownloadedProjectItems, Error>
}
