import Foundation
import Testing
@testable import LedgeriOS

@Suite("Incomplete Return Detection Tests")
struct IncompleteReturnDetectionTests {

    // MARK: - Helpers

    private func makeEdge(itemId: String = "item-1", movementKind: String = "association") -> LineageEdge {
        var edge = LineageEdge()
        edge.itemId = itemId
        edge.movementKind = movementKind
        return edge
    }

    // MARK: - isIncompleteReturn

    @Test("Returns true when status is returned, purchase tx, and no returned edges")
    func incompleteReturn_basic() {
        let result = IncompleteReturnDetection.isIncompleteReturn(
            itemId: "item-1",
            itemStatus: .returned,
            transactionType: .purchase,
            edgesFromTransaction: []
        )
        #expect(result == true)
    }

    @Test("Returns false when status is not returned")
    func notReturned() {
        let result = IncompleteReturnDetection.isIncompleteReturn(
            itemId: "item-1",
            itemStatus: .purchased,
            transactionType: .purchase,
            edgesFromTransaction: []
        )
        #expect(result == false)
    }

    @Test("Returns false when item is in a return transaction")
    func returnTransaction() {
        let result = IncompleteReturnDetection.isIncompleteReturn(
            itemId: "item-1",
            itemStatus: .returned,
            transactionType: .return,
            edgesFromTransaction: []
        )
        #expect(result == false)
    }

    @Test("Returns false when a returned edge exists for this item")
    func hasReturnedEdge() {
        let result = IncompleteReturnDetection.isIncompleteReturn(
            itemId: "item-1",
            itemStatus: .returned,
            transactionType: .purchase,
            edgesFromTransaction: [makeEdge(itemId: "item-1", movementKind: "returned")]
        )
        #expect(result == false)
    }

    @Test("Returns true when only association edges exist (no returned edge)")
    func onlyAssociationEdges() {
        let result = IncompleteReturnDetection.isIncompleteReturn(
            itemId: "item-1",
            itemStatus: .returned,
            transactionType: .purchase,
            edgesFromTransaction: [makeEdge(itemId: "item-1", movementKind: "association")]
        )
        #expect(result == true)
    }

    @Test("Returns false when transaction type is nil")
    func nilTransaction() {
        let result = IncompleteReturnDetection.isIncompleteReturn(
            itemId: "item-1",
            itemStatus: .returned,
            transactionType: nil,
            edgesFromTransaction: []
        )
        #expect(result == false)
    }

    @Test("Returns false when status is nil")
    func nilStatus() {
        let result = IncompleteReturnDetection.isIncompleteReturn(
            itemId: "item-1",
            itemStatus: nil,
            transactionType: .purchase,
            edgesFromTransaction: []
        )
        #expect(result == false)
    }

    // MARK: - findIncompleteReturns

    @Test("Returns empty array when items list is empty")
    func emptyItems() {
        let result = IncompleteReturnDetection.findIncompleteReturns(
            items: [],
            transactionType: .purchase,
            edgesFromTransaction: []
        )
        #expect(result.isEmpty)
    }

    @Test("Returns only IDs of items with incomplete returns")
    func mixedItems() {
        let items: [(id: String, status: ItemStatus?)] = [
            (id: "item-1", status: .returned),
            (id: "item-2", status: .purchased),
            (id: "item-3", status: .returned),
        ]
        let edges = [makeEdge(itemId: "item-3", movementKind: "returned")]

        let result = IncompleteReturnDetection.findIncompleteReturns(
            items: items,
            transactionType: .purchase,
            edgesFromTransaction: edges
        )
        #expect(result == ["item-1"])
    }

    @Test("Returns empty array when all items have complete returns")
    func allComplete() {
        let items: [(id: String, status: ItemStatus?)] = [
            (id: "item-1", status: .returned),
            (id: "item-2", status: .returned),
        ]
        let edges = [
            makeEdge(itemId: "item-1", movementKind: "returned"),
            makeEdge(itemId: "item-2", movementKind: "returned"),
        ]

        let result = IncompleteReturnDetection.findIncompleteReturns(
            items: items,
            transactionType: .purchase,
            edgesFromTransaction: edges
        )
        #expect(result.isEmpty)
    }

    @Test("Returns all IDs when multiple items have incomplete returns")
    func allIncomplete() {
        let items: [(id: String, status: ItemStatus?)] = [
            (id: "item-1", status: .returned),
            (id: "item-2", status: .returned),
            (id: "item-3", status: .returned),
        ]

        let result = IncompleteReturnDetection.findIncompleteReturns(
            items: items,
            transactionType: .purchase,
            edgesFromTransaction: []
        )
        #expect(result == ["item-1", "item-2", "item-3"])
    }
}
