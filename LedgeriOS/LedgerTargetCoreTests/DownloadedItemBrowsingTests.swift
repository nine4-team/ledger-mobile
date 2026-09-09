import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Downloaded Item browsing")
struct DownloadedItemBrowsingTests {
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
