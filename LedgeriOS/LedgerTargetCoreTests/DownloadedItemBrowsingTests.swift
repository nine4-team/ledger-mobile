import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Downloaded Item browsing")
struct DownloadedItemBrowsingTests {
    @Test("Workflow status aliases share meaning without rewriting legacy evidence")
    func workflowStatusEvidence() throws {
        for raw in ["to-purchase", "to purchase", " TO PURCHASE "] {
            #expect(ItemWorkflowStatus(sourceValue: raw) == .toPurchase)
        }
        #expect(ItemWorkflowStatus(sourceValue: "purchased") == .purchased)
        #expect(ItemWorkflowStatus(sourceValue: "to return") == .toReturn)
        #expect(ItemWorkflowStatus(sourceValue: "returned") == .returned)
        #expect(ItemWorkflowStatus(sourceValue: nil) == .notSet)
        #expect(ItemWorkflowStatus(sourceValue: "  ") == .notSet)
        for raw in ["sold", "custom-status", " RETURNED-LEGACY "] {
            let status = ItemWorkflowStatus(sourceValue: raw)
            #expect(status == .unrecognized(raw))
            #expect(status.displayLabel == "Legacy status: \(raw)")
            #expect(status.facetValue == "legacy")
        }
    }

    @Test("Status and bookmark facets preserve OR/AND, nullable bookmarks and selection pruning")
    func workflowAndBookmarkFilters() throws {
        let data: [(String?, Bool?)] = [("to-purchase", true), ("to purchase", false),
            ("returned", true), (nil, nil), ("sold", false)]
        let rows = try data.enumerated().map { index, value in
            try PhysicalItemPlacement(itemId: .init(validating: "i\(index)"), description: "Item \(index)",
                itemRevision: 1, placementId: .init(validating: "p\(index)"), scope: .businessInventory,
                spaceId: nil, workflowStatusRaw: value.0, isBookmarked: value.1)
        }
        let snapshot = try DownloadedItemPlacements(accountId: .init(validating: "account"),
            scope: .businessInventory, rows: rows)
        #expect(rows[0].workflowStatusRaw == "to-purchase")
        #expect(rows[3].isBookmarked == nil)
        var filters = DownloadedItemFilters()
        func ids() -> [String] {
            snapshot.rows(in: nil, matching: "", order: .newest, filters: filters).map(\.itemId.rawValue)
        }
        filters.workflowStatus = .only(["to purchase", "returned"])
        #expect(ids() == ["i0", "i1", "i2"])
        filters.bookmark = .only(["bookmarked"])
        #expect(ids() == ["i0", "i2"])
        filters.workflowStatus = .allExcept(["returned"])
        #expect(ids() == ["i0"])
        filters.bookmark = .only(["not bookmarked"])
        #expect(ids() == ["i1", "i3", "i4"])
        filters.workflowStatus = .only(["not set"])
        #expect(ids() == ["i3"])
        filters.workflowStatus = .only(["legacy"])
        #expect(ids() == ["i4"])
        #expect(filters.isActive)
        var selected = DownloadedItemSelection()
        selected.toggleAll(visible: rows.map(\.itemId))
        selected.reconcile(visible: snapshot.rows(in: nil, matching: "", order: .newest, filters: filters).map(\.itemId))
        #expect(selected.ids.map(\.rawValue) == ["i4"])
        filters = .init()
        #expect(!filters.isActive)
        #expect(ids().count == 5)
        selected.reconcile(visible: rows.map(\.itemId))
        #expect(selected.ids.map(\.rawValue) == ["i4"])
    }

    @Test("Space facets use exact IDs, retain empty active choices and hide unrelated archives")
    func spaceChoicesAndFiltering() throws {
        let base = try snapshot()
        let room = try SpaceID(validating: "room"), empty = try SpaceID(validating: "empty")
        let value = try DownloadedItemPlacements(accountId: base.accountId, scope: base.scope, rows: base.rows,
            spaces: [
                .init(id: room, accountId: base.accountId, scope: base.scope, displayName: "Same name", isArchived: true),
                .init(id: empty, accountId: base.accountId, scope: base.scope, displayName: "Same name")
            ])
        #expect(value.spaceChoices.map(\.id) == [empty, room])
        #expect(value.spaceChoices.last?.isArchived == true)
        var filters = DownloadedItemFilters()
        filters.space = .only([room.rawValue])
        #expect(value.rows(in: nil, matching: "", order: .newest, filters: filters).map(\.itemId.rawValue) == ["a"])
        filters.space = .only([empty.rawValue])
        #expect(value.rows(in: nil, matching: "", order: .newest, filters: filters).isEmpty)
        filters.space = .only([""])
        #expect(value.rows(in: nil, matching: "", order: .newest, filters: filters).map(\.itemId.rawValue) == ["b", "c"])
        filters.sku = .only(["has"])
        #expect(value.rows(in: nil, matching: "", order: .newest, filters: filters).map(\.itemId.rawValue) == ["b"])
        filters.space = .allExcept([""])
        #expect(value.rows(in: nil, matching: "", order: .newest, filters: filters).isEmpty)
        #expect(base.spaceChoices.map(\.id) == [room])
        #expect(base.spaceChoices.first?.displayName == nil)
        #expect(throws: DownloadedItemPlacementsFailure.scopeMismatch) {
            try DownloadedItemPlacements(accountId: base.accountId, scope: base.scope, rows: base.rows,
                spaces: [.init(id: empty, accountId: base.accountId, scope: base.scope, displayName: "Archive", isArchived: true)])
        }
        #expect(throws: DownloadedItemPlacementsFailure.scopeMismatch) {
            try DownloadedItemPlacements(accountId: base.accountId, scope: base.scope, rows: base.rows,
                spaces: [.init(id: room, accountId: .init(validating: "foreign"), scope: base.scope, displayName: "Secret")])
        }
        #expect(throws: DownloadedItemPlacementsFailure.duplicateSpace) {
            try DownloadedItemPlacements(accountId: value.accountId, scope: value.scope, rows: value.rows,
                spaces: [value.spaces[0], value.spaces[0]])
        }
        #expect(throws: DownloadedItemPlacementsFailure.scopeMismatch) {
            try DownloadedItemPlacements(accountId: base.accountId, scope: base.scope, rows: base.rows,
                spaces: [.init(id: room, accountId: base.accountId, scope: .project(.init(validating: "other-project")), displayName: "Wrong scope")])
        }
    }

    @Test("Row selection prunes removed IDs and cannot select an ineligible Item")
    func selectionEligibility() throws {
        let a = try ItemID(validating: "a"), b = try ItemID(validating: "b")
        let outside = try ItemID(validating: "outside")
        var selection = DownloadedItemSelection()
        selection.toggle(itemId: a, visible: [a, b])
        #expect(selection.ids == [a])
        selection.toggle(itemId: outside, visible: [b])
        #expect(selection.ids.isEmpty)
        selection.toggle(itemId: b, visible: [b])
        #expect(selection.ids == [b])
        selection.toggle(itemId: b, visible: [b])
        #expect(selection.ids.isEmpty)
    }

    @Test("Select all fills partial selection, deselects all and never selects an empty list")
    func selectionAllAndEmpty() throws {
        let a = try ItemID(validating: "a"), b = try ItemID(validating: "b")
        var selection = DownloadedItemSelection()
        #expect(!selection.isAllSelected(visible: []))
        selection.toggle(itemId: a, visible: [a, b])
        #expect(!selection.isAllSelected(visible: [a, b]))
        selection.toggleAll(visible: [a, b, b])
        #expect(selection.ids == [a, b])
        #expect(selection.isAllSelected(visible: [b, a]))
        selection.toggleAll(visible: [b, a])
        #expect(selection.ids.isEmpty)
        selection.toggleAll(visible: [a])
        selection.toggleAll(visible: [])
        #expect(selection.ids.isEmpty)
        #expect(!selection.isAllSelected(visible: []))
        selection.toggleAll(visible: [a, b])
        selection.clear()
        #expect(selection == DownloadedItemSelection())
    }

    @Test("Clearing a filter or reordering does not restore removed selection")
    func selectionReconciliation() throws {
        let a = try ItemID(validating: "a"), b = try ItemID(validating: "b")
        var selection = DownloadedItemSelection()
        selection.toggleAll(visible: [a, b])
        selection.reconcile(visible: [b, a])
        #expect(selection.ids == [a, b])
        selection.reconcile(visible: [b])
        #expect(selection.ids == [b])
        selection.reconcile(visible: [a, b])
        #expect(selection.ids == [b])
        selection.toggleAll(visible: [a])
        #expect(selection.ids == [a])
        selection.reconcile(visible: [])
        #expect(selection.ids.isEmpty)
    }

    @Test("All-except and Only preserve intent when values appear later")
    func facetModes() {
        var selection = DownloadedItemFacetSelection.all
        selection.toggle("has")
        #expect(selection == .allExcept(["has"]))
        #expect(selection.includes("missing"))
        #expect(selection.includes("later"))
        selection.toggle("has")
        #expect(selection == .all)
        selection = .only([])
        #expect(!selection.includes("has"))
        selection.toggle("has")
        #expect(selection.includes("has"))
        #expect(!selection.includes("missing"))
        #expect(!selection.includes("later"))
        selection.toggle("has")
        #expect(selection == .only([]))
    }

    @Test("Facets use OR within and AND across, intersecting search and Space")
    func descriptiveFilters() throws {
        let value = try snapshot()
        var filters = DownloadedItemFilters()
        filters.name = .only(["has"])
        filters.sku = .only(["has"])
        #expect(value.rows(in: nil, matching: "", order: .newest, filters: filters).map(\.itemId.rawValue) == ["b"])
        #expect(value.rows(in: try SpaceID(validating: "room"), matching: "", order: .newest, filters: filters).isEmpty)
        #expect(value.rows(in: nil, matching: "chair", order: .newest, filters: filters).isEmpty)
        filters.sku = .all
        #expect(value.rows(in: nil, matching: "", order: .newest, filters: filters).count == 2)
        filters.name = .only(["has", "missing"])
        #expect(value.rows(in: nil, matching: "", order: .newest, filters: filters).count == 3)
        filters.name = .allExcept(["has"])
        #expect(value.rows(in: nil, matching: "", order: .newest, filters: filters).map(\.itemId.rawValue) == ["c"])
        #expect(filters.isActive)
        filters = .init()
        #expect(!filters.isActive)
        #expect(value.rows(in: nil, matching: "", order: .newest, filters: filters).count == 3)
    }

    @Test("Canonical name wins, including empty name; legacy description remains searchable")
    func namesAndSearch() throws {
        let value = try snapshot()
        #expect(value.rows[0].displayName == "Chair")
        #expect(value.rows[2].displayName == "")
        #expect(value.rows(in: nil, matching: " legacy ", order: .newest).map(\.itemId.rawValue) == ["a", "c"])
        #expect(value.rows(in: nil, matching: "sku-2", order: .newest).map(\.itemId.rawValue) == ["b"])
        #expect(value.rows(in: nil, matching: "CHAIR", order: .newest).map(\.itemId.rawValue) == ["a"])
        #expect(value.rows(in: nil, matching: "no match", order: .newest).isEmpty)
        #expect(value.rows(in: nil, matching: "  ", order: .newest).count == 3)
    }

    @Test("Date orders keep missing evidence last and alphabetical orders use display names")
    func ordering() throws {
        let value = try snapshot()
        #expect(value.rows(in: nil, matching: "", order: .newest).map(\.itemId.rawValue) == ["b", "a", "c"])
        #expect(value.rows(in: nil, matching: "", order: .oldest).map(\.itemId.rawValue) == ["a", "b", "c"])
        #expect(value.rows(in: nil, matching: "", order: .nameAscending).map(\.itemId.rawValue) == ["c", "a", "b"])
        #expect(value.rows(in: nil, matching: "", order: .nameDescending).map(\.itemId.rawValue) == ["b", "a", "c"])
    }

    @Test("Search stays inside Space scope and ties use stable physical IDs")
    func spaceAndTies() throws {
        let value = try snapshot()
        #expect(value.rows(in: try SpaceID(validating: "room"), matching: "legacy", order: .newest).map(\.itemId.rawValue) == ["a"])
        let rows = try ["z", "a"].map { id in
            try PhysicalItemPlacement(itemId: .init(validating: id), description: "Same", itemRevision: 1,
                placementId: .init(validating: "placement-\(id)"), scope: .businessInventory, spaceId: nil)
        }
        let ties = try DownloadedItemPlacements(accountId: .init(validating: "account"), scope: .businessInventory, rows: rows)
        for order in DownloadedItemOrder.allCases {
            #expect(ties.rows(in: nil, matching: "", order: order).map(\.itemId.rawValue) == ["a", "z"])
        }
    }

    private func snapshot() throws -> DownloadedItemPlacements {
        let rows = try [
            PhysicalItemPlacement(itemId: .init(validating: "a"), description: "Legacy chair", itemRevision: 1,
                placementId: .init(validating: "p-a"), scope: .businessInventory, spaceId: .init(validating: "room"),
                name: "Chair", createdAt: Date(timeIntervalSince1970: 1)),
            PhysicalItemPlacement(itemId: .init(validating: "b"), description: "Table", itemRevision: 1,
                placementId: .init(validating: "p-b"), scope: .businessInventory, spaceId: nil,
                sku: "SKU-2", createdAt: Date(timeIntervalSince1970: 2)),
            PhysicalItemPlacement(itemId: .init(validating: "c"), description: "Legacy unnamed", itemRevision: 1,
                placementId: .init(validating: "p-c"), scope: .businessInventory, spaceId: nil, name: "")
        ]
        return try .init(accountId: .init(validating: "account"), scope: .businessInventory, rows: rows)
    }
}
