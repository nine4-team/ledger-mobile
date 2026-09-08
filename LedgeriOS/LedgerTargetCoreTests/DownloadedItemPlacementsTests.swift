import LedgerTargetCore
import Testing

@Suite("Downloaded physical Item contract")
struct DownloadedItemPlacementsTests {
    @Test("Item revision must be positive", arguments: [Int64.min, -1, 0])
    func revision(_ revision: Int64) throws {
        #expect(throws: DownloadedItemPlacementsFailure.invalidRevision) {
            try row(revision: revision)
        }
    }

    @Test("One physical Item cannot have competing current placements")
    func duplicate() throws {
        let first = try row()
        let competing = try row(placement: "placement-other")
        #expect(throws: DownloadedItemPlacementsFailure.duplicateItem) {
            try DownloadedItemPlacements(accountId: AccountID(validating: "account"),
                scope: .businessInventory, rows: [first, competing])
        }
    }

    @Test("A Project row cannot enter the Inventory projection")
    func scope() throws {
        let projectRow = try row(scope: .project(ProjectID(validating: "project")))
        #expect(throws: DownloadedItemPlacementsFailure.scopeMismatch) {
            try DownloadedItemPlacements(accountId: AccountID(validating: "account"),
                scope: .businessInventory, rows: [projectRow])
        }
    }

    @Test("Physical identity, placement identity and revision remain distinct")
    func identities() throws {
        let item = try row(revision: Int64.max)
        let snapshot = try DownloadedItemPlacements(accountId: AccountID(validating: "account"),
            scope: .businessInventory, rows: [item])
        #expect(snapshot.rows.first?.itemId.rawValue == "chair")
        #expect(snapshot.rows.first?.placementId.rawValue == "placement")
        #expect(snapshot.rows.first?.itemRevision == Int64.max)
    }

    private func row(revision: Int64 = 1, placement: String = "placement",
                     scope: ItemPlacementScope = .businessInventory) throws -> PhysicalItemPlacement {
        try PhysicalItemPlacement(itemId: ItemID(validating: "chair"), description: "Chair",
            itemRevision: revision, placementId: EntityID(validating: placement), scope: scope, spaceId: nil)
    }
}
