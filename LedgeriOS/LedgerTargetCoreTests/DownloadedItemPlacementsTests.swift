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

    @Test("Exact Space filter excludes unassigned and other-Space Items in either owner scope", arguments: [false, true])
    func exactSpaceFilter(inventory: Bool) throws {
        let scope: ItemPlacementScope = inventory ? .businessInventory : .project(try ProjectID(validating: "project"))
        let selected = try SpaceID(validating: "\u{212B}")
        let other = try SpaceID(validating: "\u{00C5}")
        let rows = try [selected, other, nil].enumerated().map { index, space in
            try PhysicalItemPlacement(itemId: ItemID(validating: "item-\(index)"), description: "Item",
                itemRevision: 1, placementId: EntityID(validating: "placement-\(index)"), scope: scope, spaceId: space)
        }
        let snapshot = try DownloadedItemPlacements(accountId: AccountID(validating: "account"), scope: scope, rows: rows)
        #expect(snapshot.rows(in: selected).map(\.itemId.rawValue) == ["item-0"])
        #expect(snapshot.rows(in: other).map(\.itemId.rawValue) == ["item-1"])
        #expect(snapshot.rows(in: nil).count == 3)
        #expect(snapshot.rows(in: try SpaceID(validating: "missing")).isEmpty)
    }
}
