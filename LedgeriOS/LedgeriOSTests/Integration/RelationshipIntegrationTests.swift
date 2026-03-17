import Foundation
import FirebaseFirestore
import Testing
@testable import LedgeriOS

@Suite("Item ↔ Transaction/Space Relationships — Emulator Integration", .tags(.integration))
struct RelationshipIntegrationTests {
    let accountId = FirestoreTestHelper.testAccountId
    var itemsPath: String { FirestoreTestHelper.itemsPath(accountId: accountId) }
    var txPath: String { FirestoreTestHelper.transactionsPath(accountId: accountId) }

    // MARK: - Item ↔ Transaction Linking

    @Test("Create items and transaction linked via itemIds and transactionId — bidirectional consistency")
    func bidirectionalLinking() async throws {
        try await FirestoreTestHelper.signIn()
        let itemId1 = UUID().uuidString
        let itemId2 = UUID().uuidString
        let itemId3 = UUID().uuidString
        let txId = UUID().uuidString

        // Create transaction with itemIds
        let tx = makeTransaction(id: txId, itemIds: [itemId1, itemId2, itemId3])
        try FirestoreTestHelper.write(tx, toCollection: txPath, id: txId)

        // Create items pointing back at the transaction
        for itemId in [itemId1, itemId2, itemId3] {
            let item = makeItem(id: itemId, transactionId: txId)
            try FirestoreTestHelper.write(item, toCollection: itemsPath, id: itemId)
        }

        // Verify transaction has all 3 item IDs
        let readTx: LedgeriOS.Transaction = try #require(await FirestoreTestHelper.read(LedgeriOS.Transaction.self, fromCollection: txPath, id: txId))
        #expect(readTx.itemIds?.count == 3)
        #expect(readTx.itemIds?.contains(itemId1) == true)
        #expect(readTx.itemIds?.contains(itemId2) == true)
        #expect(readTx.itemIds?.contains(itemId3) == true)

        // Verify each item points to the transaction
        for itemId in [itemId1, itemId2, itemId3] {
            let readItem: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: itemId))
            #expect(readItem.transactionId == txId)
        }
    }

    @Test("Add item to existing transaction via arrayUnion")
    func addItemToTransaction() async throws {
        try await FirestoreTestHelper.signIn()
        let txId = UUID().uuidString
        let existingItemId = UUID().uuidString
        let newItemId = UUID().uuidString

        let tx = makeTransaction(id: txId, itemIds: [existingItemId])
        try FirestoreTestHelper.write(tx, toCollection: txPath, id: txId)

        // Add new item
        try await FirestoreTestHelper.update(
            documentPath: "\(txPath)/\(txId)",
            fields: ["itemIds": FieldValue.arrayUnion([newItemId])]
        )

        let result: LedgeriOS.Transaction = try #require(await FirestoreTestHelper.read(LedgeriOS.Transaction.self, fromCollection: txPath, id: txId))
        #expect(result.itemIds?.count == 2)
        #expect(result.itemIds?.contains(existingItemId) == true)
        #expect(result.itemIds?.contains(newItemId) == true)
    }

    @Test("Remove item from transaction via arrayRemove")
    func removeItemFromTransaction() async throws {
        try await FirestoreTestHelper.signIn()
        let txId = UUID().uuidString
        let keepId = UUID().uuidString
        let removeId = UUID().uuidString

        let tx = makeTransaction(id: txId, itemIds: [keepId, removeId])
        try FirestoreTestHelper.write(tx, toCollection: txPath, id: txId)

        try await FirestoreTestHelper.update(
            documentPath: "\(txPath)/\(txId)",
            fields: ["itemIds": FieldValue.arrayRemove([removeId])]
        )

        let result: LedgeriOS.Transaction = try #require(await FirestoreTestHelper.read(LedgeriOS.Transaction.self, fromCollection: txPath, id: txId))
        #expect(result.itemIds == [keepId])
    }

    @Test("Move item between transactions — remove from A, add to B, update item")
    func moveItemBetweenTransactions() async throws {
        try await FirestoreTestHelper.signIn()
        let itemId = UUID().uuidString
        let txAId = UUID().uuidString
        let txBId = UUID().uuidString

        // Setup: item in transaction A
        let txA = makeTransaction(id: txAId, itemIds: [itemId])
        let txB = makeTransaction(id: txBId, itemIds: [])
        let item = makeItem(id: itemId, transactionId: txAId)

        try FirestoreTestHelper.write(txA, toCollection: txPath, id: txAId)
        try FirestoreTestHelper.write(txB, toCollection: txPath, id: txBId)
        try FirestoreTestHelper.write(item, toCollection: itemsPath, id: itemId)

        // Move: remove from A, add to B, update item
        try await FirestoreTestHelper.update(
            documentPath: "\(txPath)/\(txAId)",
            fields: ["itemIds": FieldValue.arrayRemove([itemId])]
        )
        try await FirestoreTestHelper.update(
            documentPath: "\(txPath)/\(txBId)",
            fields: ["itemIds": FieldValue.arrayUnion([itemId])]
        )
        try await FirestoreTestHelper.update(
            documentPath: "\(itemsPath)/\(itemId)",
            fields: ["transactionId": txBId]
        )

        // Verify all three documents
        let resultA: LedgeriOS.Transaction = try #require(await FirestoreTestHelper.read(LedgeriOS.Transaction.self, fromCollection: txPath, id: txAId))
        let resultB: LedgeriOS.Transaction = try #require(await FirestoreTestHelper.read(LedgeriOS.Transaction.self, fromCollection: txPath, id: txBId))
        let resultItem: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: itemId))

        #expect(resultA.itemIds?.contains(itemId) != true) // removed from A
        #expect(resultB.itemIds?.contains(itemId) == true)  // added to B
        #expect(resultItem.transactionId == txBId)           // item points to B
    }

    // MARK: - Item ↔ Space/Project Assignment

    @Test("Assign item to space, then clear")
    func assignAndClearSpace() async throws {
        try await FirestoreTestHelper.signIn()
        let itemId = UUID().uuidString
        let item = makeItem(id: itemId)

        try FirestoreTestHelper.write(item, toCollection: itemsPath, id: itemId)

        // Assign to space
        try await FirestoreTestHelper.update(
            documentPath: "\(itemsPath)/\(itemId)",
            fields: ["spaceId": "space-kitchen"]
        )
        let withSpace: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: itemId))
        #expect(withSpace.spaceId == "space-kitchen")

        // Clear space
        try await FirestoreTestHelper.update(
            documentPath: "\(itemsPath)/\(itemId)",
            fields: ["spaceId": NSNull()]
        )
        let cleared: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: itemId))
        #expect(cleared.spaceId == nil)
    }

    @Test("Assign item to project, then clear")
    func assignAndClearProject() async throws {
        try await FirestoreTestHelper.signIn()
        let itemId = UUID().uuidString
        let item = makeItem(id: itemId)

        try FirestoreTestHelper.write(item, toCollection: itemsPath, id: itemId)

        // Assign to project
        try await FirestoreTestHelper.update(
            documentPath: "\(itemsPath)/\(itemId)",
            fields: ["projectId": "proj-main"]
        )
        let withProject: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: itemId))
        #expect(withProject.projectId == "proj-main")

        // Clear project
        try await FirestoreTestHelper.update(
            documentPath: "\(itemsPath)/\(itemId)",
            fields: ["projectId": NSNull()]
        )
        let cleared: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: itemId))
        #expect(cleared.projectId == nil)
    }
}
