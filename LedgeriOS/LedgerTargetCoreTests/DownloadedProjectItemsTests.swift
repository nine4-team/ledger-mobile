import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Atomic Project Item snapshot scope")
struct DownloadedProjectItemsContractTests {
    @Test("Nil accounting keeps physical data available; matching evidence is accepted")
    func matchingAndUnavailable() throws {
        let physical = try placements()
        #expect(try DownloadedProjectItems(placements: physical, accounting: nil).placements == physical)
        #expect(try DownloadedProjectItems(placements: physical, accounting: snapshot()).accounting != nil)
    }

    @Test("Mismatched Account, Project, Item, count, or Space cannot join separate snapshots")
    func mismatches() throws {
        for accounting in [
            try snapshot(account: "other"), try snapshot(project: "other"),
            try snapshot(item: "other"), try snapshot(space: "other"),
            try snapshot(space: nil), try snapshot(empty: true)
        ] {
            #expect(throws: DownloadedItemPlacementsFailure.scopeMismatch) {
                try DownloadedProjectItems(placements: placements(), accounting: accounting)
            }
        }
        let inventory = try DownloadedItemPlacements(accountId: AccountID(validating: "account"),
            scope: .businessInventory, rows: [])
        #expect(throws: DownloadedItemPlacementsFailure.scopeMismatch) {
            try DownloadedProjectItems(placements: inventory, accounting: nil)
        }
    }

    @Test("An unassigned physical Item matches unassigned accounting evidence")
    func unassignedSpace() throws {
        #expect(try DownloadedProjectItems(placements: placements(space: nil),
            accounting: snapshot(space: nil)).accounting != nil)
    }

    private func placements(space: String? = "space") throws -> DownloadedItemPlacements {
        let scope = ItemPlacementScope.project(try ProjectID(validating: "project"))
        return try .init(accountId: AccountID(validating: "account"), scope: scope, rows: [
            .init(itemId: ItemID(validating: "item"), description: "Chair", itemRevision: 1,
                placementId: EntityID(validating: "placement"), scope: scope,
                spaceId: space.map { try SpaceID(validating: $0) })
        ])
    }

    private func snapshot(account: String = "account", project: String = "project",
                          item: String = "item", space: String? = "space", empty: Bool = false) throws
        -> ProjectItemAccountingSectionsSnapshot {
        let accountId = try AccountID(validating: account), projectId = try ProjectID(validating: project)
        let clientId = try ClientID(validating: "client")
        return try .init(accountId: accountId, projectId: projectId, clientId: clientId,
            items: empty ? [] : [.init(accountId: accountId, projectId: projectId, clientId: clientId,
                itemId: ItemID(validating: item), spaceId: space.map { try SpaceID(validating: $0) })],
            isCompleteForAccounting: false, quality: .ready,
            localDataVersion: .init(validating: "test-version"), asOf: Date(timeIntervalSince1970: 100))
    }
}
