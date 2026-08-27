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

@Suite("ItemsService — bulk metadata updates")
struct ItemsServiceBulkUpdateTests {
    @Test("status update commits all items in one batch without transaction reads")
    func statusUpdateUsesOneBatch() async throws {
        let batch = RecordingBatch()
        let service = ItemsService(
            makeBatch: { batch },
            loadTransaction: { _, _ in
                Issue.record("Bulk metadata update unexpectedly loaded a transaction")
                return nil
            }
        )
        var first = makeItem(id: "i1", transactionId: "tx1")
        first.projectId = "project1"
        first.budgetCategoryId = "cat1"
        var second = first
        second.id = "i2"

        try await service.updateItems(
            accountId: acct,
            items: [first, second],
            fields: ["status": ItemStatus.purchased.rawValue]
        )

        #expect(batch.commitCalled)
        #expect(batch.updates.count == 2)
        for itemId in ["i1", "i2"] {
            let update = try #require(batch.updatesForPath("accounts/\(acct)/items/\(itemId)").first)
            #expect(update.fields["status"] as? String == ItemStatus.purchased.rawValue)
            #expect(update.fields.count == 1)
        }
    }

    @Test("space clear preserves null and deduplicates item IDs")
    func clearSpaceDeduplicatesItems() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1")

        try await service.updateItems(
            accountId: acct,
            items: [item, item],
            fields: ["spaceId": NSNull()]
        )

        #expect(batch.commitCalled)
        #expect(batch.updates.count == 1)
        let update = try #require(batch.updates.first)
        #expect(update.fields["spaceId"] is NSNull)
    }

    @Test("unsupported association field fails before creating a batch")
    func associationFieldRejected() async {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)

        await #expect(throws: ItemAssociationError.self) {
            try await service.updateItems(
                accountId: acct,
                items: [makeItem(id: "i1")],
                fields: ["projectId": "project2"]
            )
        }

        #expect(!batch.commitCalled)
        #expect(batch.updates.isEmpty)
    }

    @Test("missing item ID fails before creating a batch")
    func missingItemIdRejected() async {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)

        await #expect(throws: ItemAssociationError.self) {
            try await service.updateItems(
                accountId: acct,
                items: [makeItem(id: nil)],
                fields: ["status": ItemStatus.toPurchase.rawValue]
            )
        }

        #expect(!batch.commitCalled)
        #expect(batch.updates.isEmpty)
    }

    @Test("legacy category state does not block an unrelated metadata update")
    func legacyCategoryStateIsNotRewritten() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        var item = makeItem(id: "i1")
        item.projectId = "project1"
        item.budgetCategoryId = nil

        try await service.updateItems(
            accountId: acct,
            items: [item],
            fields: ["spaceId": "space1"]
        )

        #expect(batch.commitCalled)
        let update = try #require(batch.updates.first)
        #expect(update.fields["spaceId"] as? String == "space1")
        #expect(update.fields.count == 1)
    }

    @Test("more than 500 updates are committed in Firestore-safe chunks")
    func largeSelectionUsesMultipleBatches() async throws {
        let factory = RecordingBatchFactory()
        let service = ItemsService(makeBatch: { factory.makeBatch() })
        let items = (1...501).map { makeItem(id: "i\($0)") }

        try await service.updateItems(
            accountId: acct,
            items: items,
            fields: ["status": ItemStatus.toPurchase.rawValue]
        )

        let batches = factory.batches
        #expect(batches.count == 2)
        #expect(batches[0].commitCalled)
        #expect(batches[0].updates.count == 500)
        #expect(batches[1].commitCalled)
        #expect(batches[1].updates.count == 1)
    }

    @Test("batch commit errors propagate to the caller")
    func commitErrorPropagates() async {
        enum ExpectedError: Error { case commit }
        let batch = RecordingBatch()
        batch.commitError = ExpectedError.commit
        let service = makeService(batch: batch)

        await #expect(throws: ExpectedError.self) {
            try await service.updateItems(
                accountId: acct,
                items: [makeItem(id: "i1")],
                fields: ["status": ItemStatus.returned.rawValue]
            )
        }
        #expect(batch.commitCalled)
    }

    @Test("empty update does not create a batch")
    func emptyUpdateReturnsImmediately() async throws {
        let factory = RecordingBatchFactory()
        let service = ItemsService(makeBatch: { factory.makeBatch() })

        try await service.updateItems(accountId: acct, items: [], fields: ["status": "purchased"])
        try await service.updateItems(accountId: acct, items: [makeItem(id: "i1")], fields: [:])

        #expect(factory.batches.isEmpty)
    }
}

private final class RecordingBatchFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var storedBatches: [RecordingBatch] = []

    var batches: [RecordingBatch] {
        lock.withLock { storedBatches }
    }

    func makeBatch() -> RecordingBatch {
        lock.withLock {
            let batch = RecordingBatch()
            storedBatches.append(batch)
            return batch
        }
    }
}

private func makeService(batch: RecordingBatch) -> ItemsService {
    ItemsService(makeBatch: { batch })
}

private func makeTransaction(
    id: String,
    projectId: String,
    budgetCategoryId: String? = nil,
    itemIds: [String] = []
) -> Transaction {
    var transaction = Transaction()
    transaction.id = id
    transaction.projectId = projectId
    transaction.budgetCategoryId = budgetCategoryId
    transaction.itemIds = itemIds
    return transaction
}

@Suite("ItemsService — transaction membership batch operations")
struct ItemDeletionTests {

    @Test("generic create rejects a pre-linked item")
    func genericCreateRejectsLinkedItem() throws {
        let service = makeService(batch: RecordingBatch())
        let item = makeItem(id: nil, transactionId: "tx1")

        #expect(throws: ItemAssociationError.self) {
            _ = try service.createItem(accountId: acct, item: item)
        }
    }

    @Test("inventory item creation rejects a budget category")
    func inventoryCreateRejectsCategory() throws {
        let service = makeService(batch: RecordingBatch())
        var item = makeItem(id: nil)
        item.budgetCategoryId = "cat1"

        #expect(throws: ItemAssociationError.self) {
            _ = try service.createItem(accountId: acct, item: item)
        }
    }

    @Test("generic transaction update rejects direct itemIds replacement")
    func genericTransactionUpdateRejectsItemIds() async throws {
        let batch = RecordingBatch()
        let service = TransactionsService(makeBatch: { batch })

        await #expect(throws: ItemAssociationError.self) {
            try await service.updateTransaction(
                accountId: acct,
                transactionId: "tx1",
                fields: ["itemIds": ["i1"]]
            )
        }
        #expect(!batch.commitCalled)
    }

    @Test("set transaction — inherits category and moves canonical membership atomically")
    func setTransactionInheritsCategory() async throws {
        let batch = RecordingBatch()
        let service = ItemsService(
            makeBatch: { batch },
            loadTransaction: { _, _ in
                makeTransaction(id: "tx2", projectId: "project1", budgetCategoryId: "cat2")
            }
        )
        var item = makeItem(id: "i1", transactionId: "tx1")
        item.projectId = "project1"
        item.budgetCategoryId = "cat1"

        try await service.setTransaction(accountId: acct, items: [item], transactionId: "tx2")

        #expect(batch.commitCalled)
        let itemUpdate = try #require(batch.updatesForPath("accounts/\(acct)/items/i1").first)
        #expect(itemUpdate.fields["transactionId"] as? String == "tx2")
        #expect(itemUpdate.fields["budgetCategoryId"] as? String == "cat2")
        #expect(batch.updatesForPath("accounts/\(acct)/transactions/tx1").count == 1)
        #expect(batch.updatesForPath("accounts/\(acct)/transactions/tx2").count == 1)
        #expect(batch.lineageEdges(accountId: acct, itemId: "i1").count == 1)
    }

    @Test("clear transaction — preserves category and removes canonical membership")
    func clearTransactionPreservesCategory() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        var item = makeItem(id: "i1", transactionId: "tx1")
        item.projectId = "project1"
        item.budgetCategoryId = "cat1"

        try await service.clearTransaction(accountId: acct, items: [item])

        let itemUpdate = try #require(batch.updatesForPath("accounts/\(acct)/items/i1").first)
        #expect(itemUpdate.fields["transactionId"] is NSNull)
        #expect(!itemUpdate.fields.keys.contains("budgetCategoryId"))
        #expect(batch.updatesForPath("accounts/\(acct)/transactions/tx1").count == 1)
        let edge = try #require(batch.lineageEdges(accountId: acct, itemId: "i1").first)
        #expect(edge.fields["note"] as? String == "Cleared transaction association")
    }

    @Test("set transaction — rejects a project transaction without a real category")
    func setTransactionRejectsMissingCategory() async throws {
        let batch = RecordingBatch()
        let service = ItemsService(
            makeBatch: { batch },
            loadTransaction: { _, _ in
                makeTransaction(id: "tx2", projectId: "project1")
            }
        )
        var item = makeItem(id: "i1")
        item.projectId = "project1"
        item.budgetCategoryId = "cat1"

        await #expect(throws: ItemAssociationError.self) {
            try await service.setTransaction(accountId: acct, items: [item], transactionId: "tx2")
        }
        #expect(!batch.commitCalled)
    }

    @Test("transaction category edit — cascades to canonically owned items")
    func transactionCategoryEditCascades() async throws {
        let batch = RecordingBatch()
        let service = TransactionsService(
            makeBatch: { batch },
            loadTransaction: { _, _ in
                makeTransaction(
                    id: "tx1",
                    projectId: "project1",
                    budgetCategoryId: "cat1",
                    itemIds: ["i1", "i2"]
                )
            }
        )

        try await service.updateTransaction(
            accountId: acct,
            transactionId: "tx1",
            fields: ["budgetCategoryId": "cat2"]
        )

        #expect(batch.commitCalled)
        #expect(batch.updatesForPath("accounts/\(acct)/transactions/tx1").count == 1)
        for itemId in ["i1", "i2"] {
            let update = try #require(batch.updatesForPath("accounts/\(acct)/items/\(itemId)").first)
            #expect(update.fields["budgetCategoryId"] as? String == "cat2")
        }
    }

    @Test("transaction inventory correction — detaches linked items into No Transaction state")
    func transactionInventoryCorrectionDetachesItems() async throws {
        let batch = RecordingBatch()
        let service = TransactionsService(
            makeBatch: { batch },
            loadTransaction: { _, _ in
                makeTransaction(
                    id: "tx1",
                    projectId: "project1",
                    budgetCategoryId: "cat1",
                    itemIds: ["i1"]
                )
            }
        )

        try await service.updateTransaction(
            accountId: acct,
            transactionId: "tx1",
            fields: TransactionsService.moveToInventoryCorrectionFields()
        )

        let itemUpdate = try #require(batch.updatesForPath("accounts/\(acct)/items/i1").first)
        #expect(itemUpdate.fields["transactionId"] is NSNull)
        #expect(!itemUpdate.fields.keys.contains("budgetCategoryId"))
        #expect(batch.lineageEdges(accountId: acct, itemId: "i1").count == 1)
    }

    @Test("transaction project correction — moves owned items and clears stale spaces")
    func transactionProjectCorrectionMovesItems() async throws {
        let batch = RecordingBatch()
        let service = TransactionsService(
            makeBatch: { batch },
            loadTransaction: { _, _ in
                makeTransaction(
                    id: "tx1",
                    projectId: "project1",
                    budgetCategoryId: "cat1",
                    itemIds: ["i1"]
                )
            }
        )

        try await service.updateTransaction(
            accountId: acct,
            transactionId: "tx1",
            fields: ["projectId": "project2", "budgetCategoryId": "cat2"]
        )

        let update = try #require(batch.updatesForPath("accounts/\(acct)/items/i1").first)
        #expect(update.fields["projectId"] as? String == "project2")
        #expect(update.fields["budgetCategoryId"] as? String == "cat2")
        #expect(update.fields["spaceId"] is NSNull)
        #expect(batch.lineageEdges(accountId: acct, itemId: "i1").count == 1)
    }

    @Test("create items for transaction — creates item docs and links transaction itemIds")
    func createItemsForTransaction() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        var item1 = makeItem(id: nil)
        item1.projectId = "project1"
        item1.spaceId = "space1"
        item1.name = "Lamp"
        item1.budgetCategoryId = "cat1"
        var item2 = makeItem(id: nil)
        item2.projectId = "project1"
        item2.name = "Chair"
        item2.budgetCategoryId = "cat1"

        let createdItems = try service.createItemsForTransaction(
            accountId: acct,
            transactionId: "tx1",
            budgetCategoryId: "cat1",
            items: [item1, item2],
            onCommitError: { _, _ in }
        )
        let ids = createdItems.compactMap(\.id)

        #expect(ids.count == 2)
        #expect(Set(ids).count == 2)
        #expect(createdItems.allSatisfy { $0.accountId == acct })
        #expect(createdItems.allSatisfy { $0.transactionId == "tx1" })
        #expect(createdItems[0].spaceId == "space1")
        #expect(batch.commitCalled)

        #expect(batch.sets.count == 2)
        for id in ids {
            let itemSets = batch.setsForPath("accounts/\(acct)/items/\(id)")
            #expect(itemSets.count == 1)
            #expect(itemSets[0].fields["accountId"] as? String == acct)
            #expect(itemSets[0].fields["transactionId"] as? String == "tx1")
            if id == createdItems[0].id {
                #expect(itemSets[0].fields["spaceId"] as? String == "space1")
            }
        }

        let txUpdates = batch.updatesForPath("accounts/\(acct)/transactions/tx1")
        #expect(txUpdates.count == 1)
        #expect(txUpdates[0].fields.keys.contains("itemIds"))
        #expect(txUpdates[0].fields.keys.contains("updatedAt"))
    }

    @Test("create inventory item for transaction — preserves inventory scope")
    func createInventoryItemForTransaction() throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        var item = makeItem(id: nil)
        item.name = "Lamp"

        let createdItems = try service.createItemsForTransaction(
            accountId: acct,
            transactionId: "inventory-tx",
            budgetCategoryId: nil,
            items: [item],
            onCommitError: { _, _ in }
        )

        let created = try #require(createdItems.first)
        let itemId = try #require(created.id)
        let itemSet = try #require(
            batch.setsForPath("accounts/\(acct)/items/\(itemId)").first
        )

        #expect(created.projectId == nil)
        #expect(created.budgetCategoryId == nil)
        #expect(created.transactionId == "inventory-tx")
        #expect(itemSet.fields["projectId"] is NSNull)
        #expect(itemSet.fields["budgetCategoryId"] is NSNull)
        #expect(batch.commitCalled)
    }

    @Test("create empty item array — does not commit")
    func createItemsForTransactionEmptyArray() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)

        let createdItems = try service.createItemsForTransaction(
            accountId: acct,
            transactionId: "tx1",
            budgetCategoryId: "cat1",
            items: [],
            onCommitError: { _, _ in }
        )

        #expect(createdItems.isEmpty)
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
