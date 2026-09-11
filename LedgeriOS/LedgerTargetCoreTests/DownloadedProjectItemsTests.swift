import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Atomic Project Item snapshot scope")
struct DownloadedProjectItemsContractTests {
    @Test("Accounting facet uses canonical evidence, composes with other filters and ignores Inventory")
    func accountingFacet() throws {
        let physical = try placements()
        for (complete, charge, expected) in [(false, false, ProjectItemAccountingResolution.relationshipEvidenceIncomplete),
                                             (true, false, .unaccountedFor), (false, true, .accountedFor)] {
            let evidence = try snapshot(complete: complete, charge: charge)
            var filters = DownloadedItemFilters()
            func visible() -> [PhysicalItemPlacement] {
                physical.rows(in: nil, matching: "", order: .newest, filters: filters, accounting: evidence)
            }
            #expect(visible().count == 1)
            filters.accounting = .only([])
            #expect(filters.isActive)
            #expect(visible().isEmpty)
            filters.accounting.toggle(expected.rawValue)
            #expect(visible().count == 1)
            filters.accounting = .allExcept([expected.rawValue])
            #expect(visible().isEmpty)
            filters.accounting = .only([expected.rawValue, "another value"])
            #expect(visible().count == 1)
            filters.sku = .only(["has"])
            #expect(visible().isEmpty)
            filters = .init()
            #expect(!filters.isActive)
            #expect(visible().count == 1)
            filters.accounting = .only([expected.rawValue])
            #expect(physical.rows(in: nil, matching: "absent", order: .newest, filters: filters, accounting: evidence).isEmpty)
            let otherSpace = try SpaceID(validating: "another-space")
            #expect(physical.rows(in: otherSpace, matching: "", order: .newest, filters: filters, accounting: evidence).isEmpty)
        }
        let inventoryRow = try PhysicalItemPlacement(itemId: .init(validating: "inventory-item"), description: "Chair",
            itemRevision: 1, placementId: .init(validating: "inventory-placement"), scope: .businessInventory, spaceId: nil)
        let inventory = try DownloadedItemPlacements(accountId: .init(validating: "account"), scope: .businessInventory, rows: [inventoryRow])
        var filters = DownloadedItemFilters()
        filters.accounting = .only([])
        #expect(inventory.rows(in: nil, matching: "", order: .newest, filters: filters).count == 1)
    }

    @Test("Absent or mismatched accounting cannot classify physical rows as known")
    func accountingFacetScope() throws {
        let physical = try placements()
        for evidence in [nil, try snapshot(account: "other", complete: true),
                         try snapshot(project: "other", complete: true), try snapshot(item: "other", complete: true),
                         try snapshot(space: "other", complete: true), try snapshot(empty: true, complete: true)] {
            var filters = DownloadedItemFilters()
            filters.accounting = .only([ProjectItemAccountingResolution.unaccountedFor.rawValue,
                                        ProjectItemAccountingResolution.accountedFor.rawValue])
            #expect(physical.rows(in: nil, matching: "", order: .newest, filters: filters, accounting: evidence).isEmpty)
            filters.accounting = .only([ProjectItemAccountingResolution.relationshipEvidenceIncomplete.rawValue])
            #expect(physical.rows(in: nil, matching: "", order: .newest, filters: filters, accounting: evidence).count == 1)
        }
    }

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
                          item: String = "item", space: String? = "space", empty: Bool = false,
                          complete: Bool = false, charge: Bool = false) throws
        -> ProjectItemAccountingSectionsSnapshot {
        let accountId = try AccountID(validating: account), projectId = try ProjectID(validating: project)
        let clientId = try ClientID(validating: "client")
        return try .init(accountId: accountId, projectId: projectId, clientId: clientId,
            items: empty ? [] : [.init(accountId: accountId, projectId: projectId, clientId: clientId,
                itemId: ItemID(validating: item), spaceId: space.map { try SpaceID(validating: $0) },
                billableOccurrences: charge ? [.init(id: .init(validating: "charge"), accountId: accountId,
                    projectId: projectId, itemId: .init(validating: item), polarity: .charge, phase: .availableToInvoice)] : [])],
            isCompleteForAccounting: complete, quality: .ready,
            localDataVersion: .init(validating: "test-version"), asOf: Date(timeIntervalSince1970: 100))
    }
}
