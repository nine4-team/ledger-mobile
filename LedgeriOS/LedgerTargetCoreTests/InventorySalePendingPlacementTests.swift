import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Inventory sale pending placement")
struct InventorySalePendingPlacementTests {
    private func pending(_ state: LocalOperationState) throws -> InventorySalePendingPlacement {
        let command = try InventorySaleCommand(operationId: .init(validating: "sale"),accountId: .init(validating: "account"),
            actorPrincipalId: .init(validating: "actor"),capturedAt: Date(timeIntervalSince1970: 1000),
            payload: .init(projectId: .init(validating: "project"),currency: .init(validating: "USD"),
                items: [.init(itemId: .init(validating: "item"),placementId: .init(validating: "old"),priceRevision: 0,
                    reviewedPriceMinorUnits: Int64.max,newPlacementId: .init(validating: "new"),occurrenceId: .init(validating: "charge"))]))
        return try .init(command: command,projectName: "Destination",itemId: .init(validating: "item"),state: state)
    }
    private func row(_ id: String = "old", scope: ItemPlacementScope = .businessInventory) throws -> PhysicalItemPlacement {
        try .init(itemId: .init(validating: "item"),description: "Original chair",itemRevision: 3,
            placementId: .init(validating: id),scope: scope,spaceId: .init(validating: "original-space"),
            sku: "CHAIR",source: "Vendor",imageCount: 2)
    }
    @Test func acceptedPhasesMovePresentationWithoutChangingSource() throws {
        for state in [LocalOperationState.queued,.applying,.applied] {
            let pending = try pending(state), source = try row()
            for current in [source, nil] {
                let moved = try #require(try pending.resolve(source: source,current: current))
                #expect(moved.scope == .project(pending.projectId) && moved.spaceId == nil)
                #expect(moved.pendingSale?.price.minorUnits == Int64.max)
                #expect(moved.sku == source.sku && moved.imageCount == 2 && moved.source == "Vendor")
                #expect(source.scope == .businessInventory && source.pendingSale == nil)
            }
        }
    }
    @Test func rejectionAndMatchingDownloadRemoveOverlay() throws {
        let source = try row()
        #expect(try pending(.rejected).resolve(source: source,current: source) == source)
        #expect(try pending(.rejected).resolve(source: source,current: nil) == nil)
        let downloaded = try row("new",scope: .project(.init(validating: "project")))
        #expect(try pending(.applied).resolve(source: source,current: downloaded) == downloaded)
        let later = try row("later-inventory")
        #expect(try pending(.applied).resolve(source: source,current: later) == later)
    }
    @Test func wrongDestinationDoesNotBecomeSuccess() throws {
        #expect(throws: InventorySaleCommandFailure.invalidSelection) {
            try pending(.applied).resolve(source: row(),current: row("new",scope: .project(.init(validating: "wrong"))))
        }
    }
}
