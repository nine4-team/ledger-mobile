import Foundation
import Testing
@testable import LedgeriOS

private let acct = "acc1"

private func makeItem(
    id: String? = "item1",
    transactionId: String? = nil
) -> Item {
    var item = Item()
    item.id = id
    item.transactionId = transactionId
    return item
}

private func makeService(batch: RecordingBatch) -> ItemsService {
    ItemsService(makeBatch: { batch })
}

@Suite("ItemsService — transaction membership batch operations")
struct ItemDeletionTests {

    @Test("create items for transaction — creates item docs and links transaction itemIds")
    func createItemsForTransaction() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        var item1 = makeItem(id: nil)
        item1.projectId = "project1"
        item1.name = "Lamp"
        item1.budgetCategoryId = "cat1"
        var item2 = makeItem(id: nil)
        item2.projectId = "project1"
        item2.name = "Chair"
        item2.budgetCategoryId = "cat1"

        let ids = try await service.createItemsForTransaction(
            accountId: acct,
            transactionId: "tx1",
            items: [item1, item2]
        )

        #expect(ids.count == 2)
        #expect(Set(ids).count == 2)
        #expect(batch.commitCalled)

        #expect(batch.sets.count == 2)
        for id in ids {
            let itemSets = batch.setsForPath("accounts/\(acct)/items/\(id)")
            #expect(itemSets.count == 1)
            #expect(itemSets[0].fields["accountId"] as? String == acct)
            #expect(itemSets[0].fields["transactionId"] as? String == "tx1")
        }

        let txUpdates = batch.updatesForPath("accounts/\(acct)/transactions/tx1")
        #expect(txUpdates.count == 1)
        #expect(txUpdates[0].fields.keys.contains("itemIds"))
        #expect(txUpdates[0].fields.keys.contains("updatedAt"))
    }

    @Test("create empty item array — does not commit")
    func createItemsForTransactionEmptyArray() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)

        let ids = try await service.createItemsForTransaction(
            accountId: acct,
            transactionId: "tx1",
            items: []
        )

        #expect(ids.isEmpty)
        #expect(!batch.commitCalled)
        #expect(batch.sets.isEmpty)
        #expect(batch.updates.isEmpty)
    }

    @Test("delete item with transactionId — deletes doc and removes from transaction itemIds")
    func deleteWithTransactionId() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", transactionId: "tx1")

        try await service.deleteItem(accountId: acct, item: item)

        #expect(batch.commitCalled)

        // Item doc deleted
        let itemDeletes = batch.deletesForPath("accounts/\(acct)/items/i1")
        #expect(itemDeletes.count == 1)

        // Transaction itemIds updated with arrayRemove
        let txUpdates = batch.updatesForPath("accounts/\(acct)/transactions/tx1")
        #expect(txUpdates.count == 1)
        #expect(txUpdates[0].fields.keys.contains("itemIds"))
        #expect(txUpdates[0].fields.keys.contains("updatedAt"))
    }

    @Test("delete item without transactionId — only deletes item doc")
    func deleteWithoutTransactionId() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", transactionId: nil)

        try await service.deleteItem(accountId: acct, item: item)

        #expect(batch.commitCalled)

        // Item doc deleted
        let itemDeletes = batch.deletesForPath("accounts/\(acct)/items/i1")
        #expect(itemDeletes.count == 1)

        // No transaction updates
        #expect(batch.updates.isEmpty)
    }

    @Test("delete multiple items — batch contains all deletes and transaction updates")
    func bulkDeleteMixedTransactions() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let items = [
            makeItem(id: "i1", transactionId: "tx1"),
            makeItem(id: "i2", transactionId: "tx1"),
            makeItem(id: "i3", transactionId: nil),
        ]

        try await service.deleteItems(accountId: acct, items: items)

        #expect(batch.commitCalled)

        // All 3 item docs deleted
        #expect(batch.deletes.count == 3)
        #expect(batch.deletesForPath("accounts/\(acct)/items/i1").count == 1)
        #expect(batch.deletesForPath("accounts/\(acct)/items/i2").count == 1)
        #expect(batch.deletesForPath("accounts/\(acct)/items/i3").count == 1)

        // 2 transaction updates (both for tx1)
        let txUpdates = batch.updatesForPath("accounts/\(acct)/transactions/tx1")
        #expect(txUpdates.count == 2)

        // No other transaction updates
        #expect(batch.updates.count == 2)
    }

    @Test("delete empty array — does not commit")
    func emptyArray() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)

        try await service.deleteItems(accountId: acct, items: [])

        #expect(!batch.commitCalled)
        #expect(batch.deletes.isEmpty)
        #expect(batch.updates.isEmpty)
    }
}
