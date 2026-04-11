import Foundation
@preconcurrency import FirebaseFirestore
import Testing
@testable import LedgeriOS

/// End-to-end tests for InventoryOperationsService against the Firestore emulator.
///
/// Requires emulators running with **test rules** (`firebase/firestore.test.rules`)
/// which open lineage edge writes for client-side batch operations.
///
/// Start emulators with:
/// ```
/// firebase emulators:start --import=./firebase-export --export-on-exit=./firebase-export \
///   --only auth,firestore,storage \
///   --config firebase.test.json
/// ```
@Suite("Inventory Operations — Emulator Integration", .tags(.integration))
struct InventoryOperationsIntegrationTests {
    let accountId = FirestoreTestHelper.testAccountId
    /// Uses real FirestoreBatchWriter — writes go to the emulator.
    let service = InventoryOperationsService()

    var itemsPath: String { FirestoreTestHelper.itemsPath(accountId: accountId) }
    var txPath: String { FirestoreTestHelper.transactionsPath(accountId: accountId) }
    var edgesPath: String { FirestoreTestHelper.lineageEdgesPath(accountId: accountId) }

    // MARK: - returnToInventory

    @Test("returnToInventory — item cleared, Return tx created, source tx updated, lineage edge created")
    func returnToInventorySingleItem() async throws {
        try await FirestoreTestHelper.signIn()
        let itemId = UUID().uuidString
        let sourceTxId = UUID().uuidString
        let projectId = "proj-\(UUID().uuidString)"
        let categoryId = "catFurnishings"

        let item = makeItem(
            id: itemId,
            projectId: projectId,
            transactionId: sourceTxId,
            purchasePriceCents: 15000,
            budgetCategoryId: categoryId
        )
        let sourceTx = makeTransaction(id: sourceTxId, itemIds: [itemId])

        try FirestoreTestHelper.write(item, toCollection: itemsPath, id: itemId)
        try FirestoreTestHelper.write(sourceTx, toCollection: txPath, id: sourceTxId)

        try await service.returnToInventory(
            items: [item],
            accountId: accountId
        )

        // Verify: item cleared from project, budgetCategoryId wiped
        let resultItem: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: itemId))
        #expect(resultItem.projectId == nil)
        #expect(resultItem.budgetCategoryId == nil)
        #expect(resultItem.spaceId == nil)
        #expect(resultItem.status == .purchased)

        // Verify: item linked to Return transaction (auto-ID, not SALE_ prefix)
        let returnTxId = try #require(resultItem.transactionId)
        #expect(!returnTxId.hasPrefix("SALE_"))

        // Verify: Return transaction exists with correct fields
        let returnTx = try #require(await FirestoreTestHelper.read(LedgeriOS.Transaction.self, fromCollection: txPath, id: returnTxId))
        #expect(returnTx.transactionType == .return)
        #expect(returnTx.source == "Business Inventory")

        // Verify raw field
        let rawReturn = try #require(await FirestoreTestHelper.readRaw(documentPath: "\(txPath)/\(returnTxId)"))
        #expect(rawReturn["type"] as? String == "Return")
        #expect(rawReturn["isCanonicalInventorySale"] == nil)
        #expect(rawReturn["inventorySaleDirection"] == nil)

        // Verify: source transaction no longer has this item
        let resultSourceTx: LedgeriOS.Transaction = try #require(await FirestoreTestHelper.read(LedgeriOS.Transaction.self, fromCollection: txPath, id: sourceTxId))
        #expect(resultSourceTx.itemIds?.contains(itemId) != true)

        // Verify: lineage edge exists
        let edges = try await Firestore.firestore()
            .collection(edgesPath)
            .whereField("itemId", isEqualTo: itemId)
            .getDocuments()
        #expect(edges.documents.count >= 1)
        let edgeData = edges.documents.first?.data()
        #expect(edgeData?["movementKind"] as? String == "returned")
        #expect(edgeData?["fromProjectId"] as? String == projectId)
    }

    // MARK: - sellToProject

    @Test("sellToProject — item moves to destination, per-batch Sale created")
    func sellToProjectPerBatch() async throws {
        try await FirestoreTestHelper.signIn()
        let itemId = UUID().uuidString
        let sourceTxId = UUID().uuidString
        let destProjectId = "projB-\(UUID().uuidString)"
        let categoryId = "catFurnishings"

        let item = makeItem(
            id: itemId,
            projectId: nil,
            transactionId: sourceTxId,
            purchasePriceCents: 25000,
            projectPriceCents: 30000,
            budgetCategoryId: nil
        )
        let sourceTx = makeTransaction(id: sourceTxId, itemIds: [itemId])

        try FirestoreTestHelper.write(item, toCollection: itemsPath, id: itemId)
        try FirestoreTestHelper.write(sourceTx, toCollection: txPath, id: sourceTxId)

        try await service.sellToProject(
            items: [item],
            destinationProjectId: destProjectId,
            budgetCategoryId: categoryId,
            accountId: accountId
        )

        // Verify: item moved to destination project
        let resultItem: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: itemId))
        #expect(resultItem.projectId == destProjectId)
        #expect(resultItem.budgetCategoryId == categoryId)
        #expect(resultItem.spaceId == nil)
        #expect(resultItem.status == .purchased)

        // Verify: item linked to per-batch Sale (auto-ID, not SALE_ prefix)
        let saleTxId = try #require(resultItem.transactionId)
        #expect(!saleTxId.hasPrefix("SALE_"))

        // Verify: Sale transaction exists with correct shape
        let rawSale = try #require(await FirestoreTestHelper.readRaw(documentPath: "\(txPath)/\(saleTxId)"))
        #expect(rawSale["type"] as? String == "Sale")
        #expect(rawSale["source"] as? String == "Business Inventory")
        #expect(rawSale["projectId"] as? String == destProjectId)
        #expect(rawSale["budgetCategoryId"] as? String == categoryId)
        #expect(rawSale["status"] as? String == "completed")
        #expect(rawSale["isComplete"] as? Bool == true)
        // No canonical sale fields
        #expect(rawSale["isCanonicalInventorySale"] == nil)
        #expect(rawSale["inventorySaleDirection"] == nil)

        // Verify: source transaction updated
        let resultSourceTx: LedgeriOS.Transaction = try #require(await FirestoreTestHelper.read(LedgeriOS.Transaction.self, fromCollection: txPath, id: sourceTxId))
        #expect(resultSourceTx.itemIds?.contains(itemId) != true)

        // Verify: lineage edge
        let edges = try await Firestore.firestore()
            .collection(edgesPath)
            .whereField("itemId", isEqualTo: itemId)
            .getDocuments()
        #expect(edges.documents.count >= 1)
        let edgeData = edges.documents.first?.data()
        #expect(edgeData?["movementKind"] as? String == "sold")
        #expect(edgeData?["toProjectId"] as? String == destProjectId)
    }

    // MARK: - reassignToProject

    @Test("reassignToProject — within-scope: item moved, tx arrays updated, lineage edge created")
    func reassignWithinScope() async throws {
        try await FirestoreTestHelper.signIn()
        let itemId = UUID().uuidString
        let oldTxId = UUID().uuidString
        let newTxId = UUID().uuidString
        let projectId = "proj-\(UUID().uuidString)"

        let item = makeItem(id: itemId, projectId: projectId, transactionId: oldTxId)
        let oldTx = makeTransaction(id: oldTxId, itemIds: [itemId])
        let newTx = makeTransaction(id: newTxId, itemIds: [])

        try FirestoreTestHelper.write(item, toCollection: itemsPath, id: itemId)
        try FirestoreTestHelper.write(oldTx, toCollection: txPath, id: oldTxId)
        try FirestoreTestHelper.write(newTx, toCollection: txPath, id: newTxId)

        try await service.reassignToProject(
            items: [item],
            destinationTransactionId: newTxId,
            destinationProjectId: projectId,
            accountId: accountId
        )

        // Verify: item points to new transaction
        let resultItem: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: itemId))
        #expect(resultItem.transactionId == newTxId)
        #expect(resultItem.projectId == projectId) // unchanged

        // Verify: old tx no longer has item
        let resultOld: LedgeriOS.Transaction = try #require(await FirestoreTestHelper.read(LedgeriOS.Transaction.self, fromCollection: txPath, id: oldTxId))
        #expect(resultOld.itemIds?.contains(itemId) != true)

        // Verify: new tx has item
        let resultNew: LedgeriOS.Transaction = try #require(await FirestoreTestHelper.read(LedgeriOS.Transaction.self, fromCollection: txPath, id: newTxId))
        #expect(resultNew.itemIds?.contains(itemId) == true)

        // Verify: lineage edge with "correction" kind
        let edges = try await Firestore.firestore()
            .collection(edgesPath)
            .whereField("itemId", isEqualTo: itemId)
            .getDocuments()
        #expect(edges.documents.count >= 1)
        let edgeData = edges.documents.first?.data()
        #expect(edgeData?["movementKind"] as? String == "correction")
    }

    @Test("reassignToProject — cross-scope throws crossScopeReassign error")
    func reassignCrossScopeThrows() async throws {
        try await FirestoreTestHelper.signIn()
        let item = makeItem(id: UUID().uuidString, projectId: "projA")

        await #expect(throws: InventoryOperationError.crossScopeReassign) {
            try await service.reassignToProject(
                items: [item],
                destinationTransactionId: "tx-dest",
                destinationProjectId: "projB", // different from item's projectId
                accountId: accountId
            )
        }
    }
}
