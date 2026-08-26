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
/// `.serialized` is required because the E6 test toggles the shared Firestore
/// network state (`disableNetwork()`/`enableNetwork()`). Running tests in parallel
/// would let E6 disable the network while other tests are mid-flight, hanging them.
@Suite("Inventory Operations — Emulator Integration", .tags(.integration), .serialized)
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
        #expect(rawReturn["budgetCategoryId"] as? String == categoryId)
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

    @Test("sellToProject — item moves to destination, per-batch Purchase created")
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

        // Verify: item linked to per-batch Purchase (auto-ID, not SALE_ prefix)
        let purchaseTxId = try #require(resultItem.transactionId)
        #expect(!purchaseTxId.hasPrefix("SALE_"))

        // Verify: Purchase transaction exists with correct shape
        let rawPurchase = try #require(await FirestoreTestHelper.readRaw(documentPath: "\(txPath)/\(purchaseTxId)"))
        #expect(rawPurchase["type"] as? String == "Purchase")
        #expect(rawPurchase["source"] as? String == "Business Inventory")
        #expect(rawPurchase["projectId"] as? String == destProjectId)
        #expect(rawPurchase["budgetCategoryId"] as? String == categoryId)
        #expect(rawPurchase["status"] as? String == nil)
        #expect(rawPurchase["isComplete"] as? Bool == true)
        // No canonical sale fields
        #expect(rawPurchase["isCanonicalInventorySale"] == nil)
        #expect(rawPurchase["inventorySaleDirection"] == nil)

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
            destinationBudgetCategoryId: "cat1",
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

    @Test("reassignToProject — cross-project correction relinks item without sale")
    func reassignCrossProjectCorrection() async throws {
        try await FirestoreTestHelper.signIn()
        let itemId = UUID().uuidString
        let oldTxId = UUID().uuidString
        let newTxId = UUID().uuidString
        let sourceProjectId = "projA-\(UUID().uuidString)"
        let destProjectId = "projB-\(UUID().uuidString)"
        let categoryId = "cat-\(UUID().uuidString)"

        let item = makeItem(id: itemId, projectId: sourceProjectId, transactionId: oldTxId, budgetCategoryId: "oldCat")
        let oldTx = makeTransaction(id: oldTxId, projectId: sourceProjectId, itemIds: [itemId])
        let newTx = makeTransaction(id: newTxId, projectId: destProjectId, itemIds: [], budgetCategoryId: categoryId)

        try FirestoreTestHelper.write(item, toCollection: itemsPath, id: itemId)
        try FirestoreTestHelper.write(oldTx, toCollection: txPath, id: oldTxId)
        try FirestoreTestHelper.write(newTx, toCollection: txPath, id: newTxId)

        try await service.reassignToProject(
            items: [item],
            destinationTransactionId: newTxId,
            destinationProjectId: destProjectId,
            destinationBudgetCategoryId: categoryId,
            accountId: accountId
        )

        let resultItem: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: itemId))
        #expect(resultItem.projectId == destProjectId)
        #expect(resultItem.transactionId == newTxId)
        #expect(resultItem.budgetCategoryId == categoryId)

        let resultOld: LedgeriOS.Transaction = try #require(await FirestoreTestHelper.read(LedgeriOS.Transaction.self, fromCollection: txPath, id: oldTxId))
        #expect(resultOld.itemIds?.contains(itemId) != true)

        let resultNew: LedgeriOS.Transaction = try #require(await FirestoreTestHelper.read(LedgeriOS.Transaction.self, fromCollection: txPath, id: newTxId))
        #expect(resultNew.itemIds?.contains(itemId) == true)

        let edges = try await Firestore.firestore()
            .collection(edgesPath)
            .whereField("itemId", isEqualTo: itemId)
            .getDocuments()
        let correction = edges.documents.map { $0.data() }.first { $0["movementKind"] as? String == "correction" }
        #expect(correction?["fromProjectId"] as? String == sourceProjectId)
        #expect(correction?["toProjectId"] as? String == destProjectId)
    }

    // MARK: - sellItemsFromProjectToProject

    @Test("sellItemsFromProjectToProject — from-inventory item returns at project price, then purchases at project price")
    func projectToProjectFromInventoryItem() async throws {
        try await FirestoreTestHelper.signIn()
        let itemId = UUID().uuidString
        let oldTxId = UUID().uuidString
        let sourceProjectId = "projA-\(UUID().uuidString)"
        let destProjectId = "projB-\(UUID().uuidString)"
        let categoryId = "catFurnishings"

        let item = makeItem(
            id: itemId,
            projectId: sourceProjectId,
            source: "Wayfair",
            currentSource: "Business Inventory",
            transactionId: oldTxId,
            purchasePriceCents: 20_000,
            projectPriceCents: 25_000,
            budgetCategoryId: "oldCat"
        )
        let oldTx = makeTransaction(id: oldTxId, projectId: sourceProjectId, itemIds: [itemId])

        try FirestoreTestHelper.write(item, toCollection: itemsPath, id: itemId)
        try FirestoreTestHelper.write(oldTx, toCollection: txPath, id: oldTxId)

        try await service.sellItemsFromProjectToProject(
            items: [item],
            destinationProjectId: destProjectId,
            destinationCategoryId: categoryId,
            accountId: accountId
        )

        let resultItem: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: itemId))
        #expect(resultItem.projectId == destProjectId)
        #expect(resultItem.budgetCategoryId == categoryId)
        #expect(resultItem.currentSource == "Business Inventory")

        let resultOld: LedgeriOS.Transaction = try #require(await FirestoreTestHelper.read(LedgeriOS.Transaction.self, fromCollection: txPath, id: oldTxId))
        #expect(resultOld.itemIds?.contains(itemId) != true)

        let txDocs = try await Firestore.firestore().collection(txPath)
            .whereField("itemIds", arrayContains: itemId)
            .getDocuments()
        let txs = txDocs.documents.map { $0.data() }
        let returnTx = txs.first { $0["type"] as? String == "Return" }
        let purchaseTx = txs.first {
            ($0["type"] as? String) == "Purchase" &&
            ($0["projectId"] as? String) == destProjectId
        }
        #expect(returnTx?["projectId"] as? String == sourceProjectId)
        #expect(returnTx?["amountCents"] as? Int == 25_000)
        #expect(returnTx?["budgetCategoryId"] as? String == "oldCat")
        #expect(purchaseTx?["budgetCategoryId"] as? String == categoryId)
        #expect(purchaseTx?["amountCents"] as? Int == 25_000)

        let edges = try await Firestore.firestore()
            .collection(edgesPath)
            .whereField("itemId", isEqualTo: itemId)
            .getDocuments()
        let edgeKinds = Set(edges.documents.compactMap { $0.data()["movementKind"] as? String })
        #expect(edgeKinds.contains("returned"))
        #expect(edgeKinds.contains("sold"))
    }

    @Test("sellItemsFromProjectToProject — project-originated item sells to inventory at purchase cost, then purchases at project price")
    func projectToProjectOriginatedHereItem() async throws {
        try await FirestoreTestHelper.signIn()
        let itemId = UUID().uuidString
        let oldTxId = UUID().uuidString
        let sourceProjectId = "projA-\(UUID().uuidString)"
        let destProjectId = "projB-\(UUID().uuidString)"
        let categoryId = "catInstall"

        let item = makeItem(
            id: itemId,
            projectId: sourceProjectId,
            source: "Project Vendor",
            currentSource: "Project Vendor",
            transactionId: oldTxId,
            purchasePriceCents: 30_000,
            projectPriceCents: 35_000,
            budgetCategoryId: "oldCat"
        )
        let oldTx = makeTransaction(id: oldTxId, projectId: sourceProjectId, itemIds: [itemId])

        try FirestoreTestHelper.write(item, toCollection: itemsPath, id: itemId)
        try FirestoreTestHelper.write(oldTx, toCollection: txPath, id: oldTxId)

        try await service.sellItemsFromProjectToProject(
            items: [item],
            destinationProjectId: destProjectId,
            destinationCategoryId: categoryId,
            accountId: accountId
        )

        let resultItem: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: itemId))
        #expect(resultItem.projectId == destProjectId)
        #expect(resultItem.budgetCategoryId == categoryId)
        #expect(resultItem.currentSource == "Business Inventory")

        let resultOld: LedgeriOS.Transaction = try #require(await FirestoreTestHelper.read(LedgeriOS.Transaction.self, fromCollection: txPath, id: oldTxId))
        #expect(resultOld.itemIds?.contains(itemId) != true)

        let txDocs = try await Firestore.firestore().collection(txPath)
            .whereField("itemIds", arrayContains: itemId)
            .getDocuments()
        let txs = txDocs.documents.map { $0.data() }
        let saleTx = txs.first {
            ($0["type"] as? String) == "Sale" &&
            ($0["projectId"] as? String) == sourceProjectId
        }
        let purchaseTx = txs.first {
            ($0["type"] as? String) == "Purchase" &&
            ($0["projectId"] as? String) == destProjectId
        }
        #expect(saleTx?["amountCents"] as? Int == 30_000)
        #expect(saleTx?["budgetCategoryId"] as? String == "oldCat")
        #expect(purchaseTx?["budgetCategoryId"] as? String == categoryId)
        #expect(purchaseTx?["amountCents"] as? Int == 35_000)

        let edges = try await Firestore.firestore()
            .collection(edgesPath)
            .whereField("itemId", isEqualTo: itemId)
            .getDocuments()
        let edgeKinds = Set(edges.documents.compactMap { $0.data()["movementKind"] as? String })
        #expect(edgeKinds.contains("soldToInventory"))
        #expect(edgeKinds.contains("sold"))
    }

    // MARK: - E4: Price change after sale

    /// E4: Updating a sold item's projectPriceCents adjusts the separate
    /// project-side Purchase-from-Inventory transaction. The vendor purchase is
    /// not the item's active transaction and is never targeted by this trigger.
    ///
    /// Requires the **Functions emulator** in addition to Firestore. Boot with:
    /// ```
    /// firebase emulators:start --config firebase.test.json
    /// ```
    @Test("E4: sold item project-price change updates project Purchase amountCents")
    func priceChangeUpdatesProjectPurchaseAmount() async throws {
        try await FirestoreTestHelper.signIn()
        let itemId = UUID().uuidString
        let destProjectId = "projE4-\(UUID().uuidString)"
        let categoryId = "catFurnishings"

        // Seed: item in inventory with known prices
        let item = makeItem(
            id: itemId,
            purchasePriceCents: 10000,
            projectPriceCents: 12000
        )
        try FirestoreTestHelper.write(item, toCollection: itemsPath, id: itemId)

        // E1 precondition: move the item to create a Purchase transaction
        try await service.sellToProject(
            items: [item],
            destinationProjectId: destProjectId,
            budgetCategoryId: categoryId,
            accountId: accountId
        )

        let itemAfterPurchase: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: itemId))
        let purchaseTxId = try #require(itemAfterPurchase.transactionId)
        let originalPurchase = try #require(await FirestoreTestHelper.readRaw(documentPath: "\(txPath)/\(purchaseTxId)"))
        let originalAmountCents = try #require(originalPurchase["amountCents"] as? Int)
        #expect(originalAmountCents == 12000)

        // E4 action: change the item's projectPriceCents (triggers onItemPriceChanged)
        try await Firestore.firestore()
            .document("\(itemsPath)/\(itemId)")
            .updateData(["projectPriceCents": 15000])

        // The full integration suite generates many emulator events in parallel.
        // Poll the server-backed document rather than relying on a fixed delay.
        var amountAfter = originalAmountCents
        for _ in 0..<20 where amountAfter != 15000 {
            try await Task.sleep(nanoseconds: 500_000_000)
            let purchaseAfter = try #require(
                await FirestoreTestHelper.readRaw(documentPath: "\(txPath)/\(purchaseTxId)")
            )
            amountAfter = try #require(purchaseAfter["amountCents"] as? Int)
        }

        // Verify: only the project-side Purchase amount follows the project price.
        #expect(amountAfter == 15000,
                "Purchase.amountCents should change from \(originalAmountCents) to 15000, got \(amountAfter)")
    }

    // MARK: - E6: Offline sell, reconnect

    /// E6: With the network disabled, a sell write queues in the Firestore SDK
    /// cache. After `enableNetwork()`, the write syncs and appears on the server.
    ///
    /// This does not require device airplane mode — `Firestore.disableNetwork()`
    /// exercises the same offline-queueing code path.
    @Test("E6: offline sell queues locally, syncs on reconnect")
    func offlineSellSyncsOnReconnect() async throws {
        try await FirestoreTestHelper.signIn()
        let itemId = UUID().uuidString
        let destProjectId = "projE6-\(UUID().uuidString)"
        let categoryId = "catFurnishings"

        // Seed: item in inventory (while online)
        let item = makeItem(
            id: itemId,
            purchasePriceCents: 5000,
            projectPriceCents: 6000
        )
        try FirestoreTestHelper.write(item, toCollection: itemsPath, id: itemId)

        defer {
            // Ensure network is re-enabled even on failure so later tests aren't affected.
            Task { try? await Firestore.firestore().enableNetwork() }
        }

        // Go offline
        try await Firestore.firestore().disableNetwork()

        // Kick off the sell in the background. While offline, `batch.commit()` does
        // not resolve its await until the network is back — Firestore queues writes
        // locally but the commit future stays pending. So we don't `await` the
        // service call here; we launch it as a Task and verify the queued state
        // via cache read.
        let sellTask = Task {
            try await service.sellToProject(
                items: [item],
                destinationProjectId: destProjectId,
                budgetCategoryId: categoryId,
                accountId: accountId
            )
        }

        // Give the SDK a moment to process the queued writes into the cache.
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s

        // Cache read — confirms queued state is visible locally while offline.
        let cachedSnap = try await Firestore.firestore()
            .document("\(itemsPath)/\(itemId)")
            .getDocument(source: .cache)
        #expect(cachedSnap.exists)
        let cachedItem = try cachedSnap.data(as: Item.self)
        #expect(cachedItem.projectId == destProjectId)
        #expect(cachedItem.budgetCategoryId == categoryId)
        let purchaseTxId = try #require(cachedItem.transactionId)

        // Reconnect — queued writes sync to the server, sellTask's await resolves.
        try await Firestore.firestore().enableNetwork()
        try await sellTask.value
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s for final sync

        // Server read: confirm the purchase actually landed on the emulator (not just cache).
        let serverSnap = try await Firestore.firestore()
            .document("\(txPath)/\(purchaseTxId)")
            .getDocument(source: .server)
        #expect(serverSnap.exists)
        let serverFields = try #require(serverSnap.data())
        #expect(serverFields["type"] as? String == "Purchase")
        #expect(serverFields["projectId"] as? String == destProjectId)
        #expect(serverFields["amountCents"] as? Int == 6000)
    }

    // MARK: - E1→E2→E3 Chained Flow

    @Test("E1→E2→E3: sell 3 to project A, return 2 to inventory, sell 1 to project B")
    func chainedSellReturnSell() async throws {
        try await FirestoreTestHelper.signIn()
        let projectA = "projA-\(UUID().uuidString)"
        let projectB = "projB-\(UUID().uuidString)"
        let catFurnishings = "catFurnishings"
        let catInstall = "catInstall"

        // Seed: 3 items in inventory (no projectId)
        let item1 = makeItem(id: UUID().uuidString, purchasePriceCents: 10000, projectPriceCents: 12000)
        let item2 = makeItem(id: UUID().uuidString, purchasePriceCents: 15000, projectPriceCents: 18000)
        let item3 = makeItem(id: UUID().uuidString, purchasePriceCents: 20000, projectPriceCents: 24000)

        for item in [item1, item2, item3] {
            try FirestoreTestHelper.write(item, toCollection: itemsPath, id: item.id!)
        }

        // ── E1: Sell 3 items from inventory to Project A under Furnishings ──

        try await service.sellToProject(
            items: [item1, item2, item3],
            destinationProjectId: projectA,
            budgetCategoryId: catFurnishings,
            accountId: accountId
        )

        // Verify: all 3 items in Project A with correct category
        for item in [item1, item2, item3] {
            let result: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: item.id!))
            #expect(result.projectId == projectA)
            #expect(result.budgetCategoryId == catFurnishings)
            #expect(result.status == .purchased)
        }

        // Verify: 1 Purchase tx exists for Project A
        let item1After: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: item1.id!))
        let purchaseTxId = try #require(item1After.transactionId)
        let rawPurchase = try #require(await FirestoreTestHelper.readRaw(documentPath: "\(txPath)/\(purchaseTxId)"))
        #expect(rawPurchase["type"] as? String == "Purchase")
        #expect(rawPurchase["source"] as? String == "Business Inventory")
        #expect(rawPurchase["projectId"] as? String == projectA)
        #expect(rawPurchase["budgetCategoryId"] as? String == catFurnishings)
        // amountCents = 12000 + 18000 + 24000 = 54000 (no tax)
        #expect(rawPurchase["amountCents"] as? Int == 54000)
        let purchaseItemIds = rawPurchase["itemIds"] as? [String] ?? []
        #expect(Set(purchaseItemIds) == Set([item1.id!, item2.id!, item3.id!]))
        // No canonical sale fields
        #expect(rawPurchase["isCanonicalInventorySale"] == nil)

        // ── E2: Return 2 items from Project A to inventory ──

        // Re-read items so transactionId is current
        let item1ForReturn: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: item1.id!))
        let item2ForReturn: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: item2.id!))

        try await service.returnToInventory(
            items: [item1ForReturn, item2ForReturn],
            accountId: accountId
        )

        // Verify: 2 items back in inventory, budgetCategoryId wiped
        for itemId in [item1.id!, item2.id!] {
            let result: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: itemId))
            #expect(result.projectId == nil)
            #expect(result.budgetCategoryId == nil)
            #expect(result.status == .purchased)
        }

        // Verify: item3 still in Project A (untouched)
        let item3Still: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: item3.id!))
        #expect(item3Still.projectId == projectA)
        #expect(item3Still.budgetCategoryId == catFurnishings)

        // Verify: Return tx exists
        let item1Returned: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: item1.id!))
        let returnTxId = try #require(item1Returned.transactionId)
        let rawReturn = try #require(await FirestoreTestHelper.readRaw(documentPath: "\(txPath)/\(returnTxId)"))
        #expect(rawReturn["type"] as? String == "Return")
        #expect(rawReturn["source"] as? String == "Business Inventory")
        #expect(rawReturn["budgetCategoryId"] as? String == catFurnishings)

        // ── E3: Sell one returned item to Project B under Install ──

        // Re-read item1 so transactionId is current
        let item1ForSell: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: item1.id!))

        try await service.sellToProject(
            items: [item1ForSell],
            destinationProjectId: projectB,
            budgetCategoryId: catInstall,
            accountId: accountId
        )

        // Verify: item1 now in Project B with Install category
        let item1Final: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: item1.id!))
        #expect(item1Final.projectId == projectB)
        #expect(item1Final.budgetCategoryId == catInstall)

        // Verify: second Purchase tx (independent from first)
        let secondPurchaseTxId = try #require(item1Final.transactionId)
        #expect(secondPurchaseTxId != purchaseTxId) // different transaction
        let rawPurchase2 = try #require(await FirestoreTestHelper.readRaw(documentPath: "\(txPath)/\(secondPurchaseTxId)"))
        #expect(rawPurchase2["type"] as? String == "Purchase")
        #expect(rawPurchase2["projectId"] as? String == projectB)
        #expect(rawPurchase2["budgetCategoryId"] as? String == catInstall)
        #expect(rawPurchase2["amountCents"] as? Int == 12000)

        // Verify: original Purchase tx unchanged (E1 purchase still has its original amountCents)
        let rawPurchaseRecheck = try #require(await FirestoreTestHelper.readRaw(documentPath: "\(txPath)/\(purchaseTxId)"))
        #expect(rawPurchaseRecheck["amountCents"] as? Int == 54000)

        // Verify: lineage edges — at least 6 total (3 purchased + 2 returned + 1 purchased)
        let allEdges = try await Firestore.firestore()
            .collection(edgesPath)
            .whereField("itemId", in: [item1.id!, item2.id!, item3.id!])
            .getDocuments()
        let soldEdges = allEdges.documents.filter { ($0.data()["movementKind"] as? String) == "sold" }
        let returnedEdges = allEdges.documents.filter { ($0.data()["movementKind"] as? String) == "returned" }
        #expect(soldEdges.count >= 4) // 3 from E1 + 1 from E3
        #expect(returnedEdges.count >= 2) // 2 from E2
    }
}
