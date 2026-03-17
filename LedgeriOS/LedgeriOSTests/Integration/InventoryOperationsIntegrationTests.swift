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

    // MARK: - sellToBusiness

    @Test("sellToBusiness — item cleared, canonical sale created, source tx updated, lineage edge created")
    func sellToBusinessSingleItem() async throws {
        try await FirestoreTestHelper.signIn()
        let itemId = UUID().uuidString
        let sourceTxId = UUID().uuidString
        let projectId = "proj-\(UUID().uuidString)"
        let categoryId = "catFurnishings"

        // Seed: item in a project with a source transaction
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

        // Execute
        try await service.sellToBusiness(
            items: [item],
            accountId: accountId
        )

        // Verify: item cleared from project
        let resultItem: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: itemId))
        #expect(resultItem.projectId == nil)
        #expect(resultItem.spaceId == nil)
        #expect(resultItem.status == "purchased")

        // Verify: item linked to canonical sale
        let expectedSaleId = "SALE_\(projectId)_project_to_business_\(categoryId)"
        #expect(resultItem.transactionId == expectedSaleId)

        // Verify: canonical sale transaction exists with correct fields
        let sale: LedgeriOS.Transaction? = try await FirestoreTestHelper.read(LedgeriOS.Transaction.self, fromCollection: txPath, id: expectedSaleId)
        let resultSale = try #require(sale)
        #expect(resultSale.isCanonicalInventorySale == true)

        // Verify raw field to check the "type" CodingKey
        let rawSale = try #require(await FirestoreTestHelper.readRaw(documentPath: "\(txPath)/\(expectedSaleId)"))
        #expect(rawSale["inventorySaleDirection"] as? String == "project_to_business")
        #expect(rawSale["isCanonicalInventorySale"] as? Bool == true)
        #expect(rawSale["type"] as? String == "Sale")

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
        #expect(edgeData?["movementKind"] as? String == "sold")
        #expect(edgeData?["fromProjectId"] as? String == projectId)
    }

    @Test("sellToBusiness — multiple items in different categories create separate canonical sales")
    func sellToBusinessMultipleCategories() async throws {
        try await FirestoreTestHelper.signIn()
        let projectId = "proj-\(UUID().uuidString)"

        let item1 = makeItem(
            id: UUID().uuidString,
            projectId: projectId,
            purchasePriceCents: 10000,
            budgetCategoryId: "catA"
        )
        let item2 = makeItem(
            id: UUID().uuidString,
            projectId: projectId,
            purchasePriceCents: 20000,
            budgetCategoryId: "catB"
        )

        try FirestoreTestHelper.write(item1, toCollection: itemsPath, id: item1.id!)
        try FirestoreTestHelper.write(item2, toCollection: itemsPath, id: item2.id!)

        try await service.sellToBusiness(items: [item1, item2], accountId: accountId)

        // Two separate canonical sales should exist
        let saleA: LedgeriOS.Transaction? = try await FirestoreTestHelper.read(
            LedgeriOS.Transaction.self, fromCollection: txPath,
            id: "SALE_\(projectId)_project_to_business_catA"
        )
        let saleB: LedgeriOS.Transaction? = try await FirestoreTestHelper.read(
            LedgeriOS.Transaction.self, fromCollection: txPath,
            id: "SALE_\(projectId)_project_to_business_catB"
        )

        #expect(saleA != nil)
        #expect(saleB != nil)
    }

    // MARK: - sellToProject

    @Test("sellToProject — item moves to destination, two canonical sales created")
    func sellToProjectTwoHop() async throws {
        try await FirestoreTestHelper.signIn()
        let itemId = UUID().uuidString
        let sourceTxId = UUID().uuidString
        let sourceProjectId = "projA-\(UUID().uuidString)"
        let destProjectId = "projB-\(UUID().uuidString)"
        let categoryId = "catFurnishings"

        let item = makeItem(
            id: itemId,
            projectId: sourceProjectId,
            transactionId: sourceTxId,
            purchasePriceCents: 25000,
            budgetCategoryId: categoryId
        )
        let sourceTx = makeTransaction(id: sourceTxId, itemIds: [itemId])

        try FirestoreTestHelper.write(item, toCollection: itemsPath, id: itemId)
        try FirestoreTestHelper.write(sourceTx, toCollection: txPath, id: sourceTxId)

        try await service.sellToProject(
            items: [item],
            destinationProjectId: destProjectId,
            accountId: accountId
        )

        // Verify: item moved to destination project
        let resultItem: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: itemId))
        #expect(resultItem.projectId == destProjectId)
        #expect(resultItem.spaceId == nil)

        // Verify: hop 1 canonical sale (source project → business)
        let hop1Id = "SALE_\(sourceProjectId)_project_to_business_\(categoryId)"
        let hop1: LedgeriOS.Transaction? = try await FirestoreTestHelper.read(LedgeriOS.Transaction.self, fromCollection: txPath, id: hop1Id)
        #expect(hop1 != nil)

        // Verify: hop 2 canonical sale (business → destination project)
        let hop2Id = "SALE_\(destProjectId)_business_to_project_\(categoryId)"
        let hop2: LedgeriOS.Transaction? = try await FirestoreTestHelper.read(LedgeriOS.Transaction.self, fromCollection: txPath, id: hop2Id)
        #expect(hop2 != nil)

        // Verify: item linked to destination canonical sale
        #expect(resultItem.transactionId == hop2Id)

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

    // MARK: - reassignToInventory

    @Test("reassignToInventory — item cleared from project, source tx updated, lineage edge created")
    func reassignToInventory() async throws {
        try await FirestoreTestHelper.signIn()
        let itemId = UUID().uuidString
        let sourceTxId = UUID().uuidString
        let projectId = "proj-\(UUID().uuidString)"

        let item = makeItem(id: itemId, projectId: projectId, transactionId: sourceTxId)
        let sourceTx = makeTransaction(id: sourceTxId, itemIds: [itemId])

        try FirestoreTestHelper.write(item, toCollection: itemsPath, id: itemId)
        try FirestoreTestHelper.write(sourceTx, toCollection: txPath, id: sourceTxId)

        try await service.reassignToInventory(
            items: [item],
            accountId: accountId
        )

        // Verify: item's projectId cleared
        let resultItem: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: itemId))
        #expect(resultItem.projectId == nil)

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
        #expect(edgeData?["movementKind"] as? String == "correction")
        #expect(edgeData?["fromProjectId"] as? String == projectId)
    }
}
