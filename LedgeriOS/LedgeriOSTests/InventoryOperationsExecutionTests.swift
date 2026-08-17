import Foundation
import Testing
@testable import LedgeriOS

// MARK: - Shared Helpers

private let acct = "acc1"

private func makeItem(
    id: String? = "item1",
    projectId: String? = "proj1",
    budgetCategoryId: String? = nil,
    purchasePriceCents: Int? = nil,
    transactionId: String? = nil,
    projectPriceCents: Int? = nil,
    taxRatePct: Double? = nil,
    spaceId: String? = nil,
    status: ItemStatus? = nil,
    source: String? = nil,
    currentSource: String? = nil
) -> Item {
    var item = Item()
    item.id = id
    item.projectId = projectId
    item.budgetCategoryId = budgetCategoryId
    item.purchasePriceCents = purchasePriceCents
    item.transactionId = transactionId
    item.projectPriceCents = projectPriceCents
    item.taxRatePct = taxRatePct
    item.spaceId = spaceId
    item.status = status
    item.source = source
    item.currentSource = currentSource
    return item
}

private func makeService(batch: RecordingBatch) -> InventoryOperationsService {
    InventoryOperationsService(makeBatch: { batch })
}

// MARK: - sellToProject (I1, I2, I5, I6)

@Suite("InventoryOperationsService.sellToProject — per-batch")
struct SellToProjectExecutionTests {

    private let dstProj = "dstProj"
    private let catId = "cat_furnishings"

    // I1: sellToProject with 5 items
    @Test("5 items — 1 Purchase tx, correct amountCents, item fields, 5 lineage edges")
    func fiveItemsHappyPath() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let items = (1...5).map { i in
            makeItem(
                id: "i\(i)", projectId: nil,
                purchasePriceCents: 1000 * i,
                transactionId: "oldTx\(i)",
                projectPriceCents: 1200 * i
            )
        }

        try await service.sellToProject(
            items: items, destinationProjectId: dstProj,
            budgetCategoryId: catId, accountId: acct, userId: "user1"
        )

        #expect(batch.commitCalled)

        // Exactly 1 Purchase transaction (via setData, not setDataAutoId)
        let purchaseSets = batch.sets.filter {
            ($0.fields["type"] as? String) == "Purchase"
        }
        #expect(purchaseSets.count == 1)
        let purchase = purchaseSets[0].fields

        // Shape fields
        #expect(purchase["type"] as? String == "Purchase")
        #expect(purchase["source"] as? String == "Business Inventory")
        #expect(purchase["projectId"] as? String == dstProj)
        #expect(purchase["budgetCategoryId"] as? String == catId)
        #expect(purchase["status"] as? String == nil)
        #expect(purchase["isComplete"] as? Bool == true)

        // amountCents = sum of projectPriceCents (no tax)
        // 1200 + 2400 + 3600 + 4800 + 6000 = 18000
        #expect(purchase["amountCents"] as? Int == 18000)
        #expect(purchase["subtotalCents"] as? Int == 18000)

        // itemIds
        let itemIds = purchase["itemIds"] as? [String] ?? []
        #expect(itemIds.count == 5)
        #expect(Set(itemIds) == Set(["i1", "i2", "i3", "i4", "i5"]))

        // Purchase doc path contains the auto-generated UUID (not a SALE_ prefix)
        let purchasePath = purchaseSets[0].path
        #expect(!purchasePath.contains("SALE_"))

        // 5 item updates
        for i in 1...5 {
            let updates = batch.updatesForPath("accounts/\(acct)/items/i\(i)")
            #expect(updates.count == 1)
            let f = updates[0].fields
            #expect(f["projectId"] as? String == dstProj)
            #expect(f["budgetCategoryId"] as? String == catId)
            #expect(f["status"] as? String == "purchased")
            #expect(f["spaceId"] is NSNull)
            // transactionId is the UUID from the purchase doc
            let txId = f["transactionId"] as? String
            #expect(txId != nil && !txId!.contains("SALE_"))
        }

        // 5 source transaction removals
        for i in 1...5 {
            let txUpdates = batch.updatesForPath("accounts/\(acct)/transactions/oldTx\(i)")
            #expect(txUpdates.count == 1)
        }

        // 5 lineage edges with movementKind "sold"
        let edges = batch.lineageEdges(accountId: acct)
        #expect(edges.count == 5)
        for edge in edges {
            #expect(edge.fields["movementKind"] as? String == "sold")
            #expect(edge.fields["toProjectId"] as? String == dstProj)
            #expect(edge.fields["createdBy"] as? String == "user1")
        }
    }

    // I2: sellToProject twice — two independent transactions
    @Test("two separate sells create two independent transactions")
    func twoSellsIndependent() async throws {
        let batch1 = RecordingBatch()
        let service1 = makeService(batch: batch1)
        let item1 = makeItem(id: "i1", projectId: nil, purchasePriceCents: 1000, projectPriceCents: 1200)

        try await service1.sellToProject(
            items: [item1], destinationProjectId: dstProj,
            budgetCategoryId: catId, accountId: acct
        )

        let batch2 = RecordingBatch()
        let service2 = makeService(batch: batch2)
        let item2 = makeItem(id: "i2", projectId: nil, purchasePriceCents: 2000, projectPriceCents: 2400)

        try await service2.sellToProject(
            items: [item2], destinationProjectId: dstProj,
            budgetCategoryId: catId, accountId: acct
        )

        // Each batch has exactly 1 purchase transaction
        let purchase1 = batch1.sets.filter { ($0.fields["type"] as? String) == "Purchase" }
        let purchase2 = batch2.sets.filter { ($0.fields["type"] as? String) == "Purchase" }
        #expect(purchase1.count == 1)
        #expect(purchase2.count == 1)

        // Different doc paths (different UUIDs)
        #expect(purchase1[0].path != purchase2[0].path)

        // First purchase unchanged by second
        #expect(purchase1[0].fields["amountCents"] as? Int == 1200)
        #expect(purchase2[0].fields["amountCents"] as? Int == 2400)
    }

    // I5: sellToProject with 101 items — batch size error
    @Test("101 items throws batch size error, no writes")
    func batchSizeExceeded() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let items = (1...101).map { makeItem(id: "i\($0)", projectId: nil) }

        await #expect(throws: InventoryOperationError.self) {
            try await service.sellToProject(
                items: items, destinationProjectId: dstProj,
                budgetCategoryId: catId, accountId: acct
            )
        }

        #expect(!batch.commitCalled)
        #expect(batch.sets.isEmpty)
        #expect(batch.updates.isEmpty)
    }

    // I6: sellToProject with item missing projectPriceCents
    @Test("item missing projectPriceCents contributes 0 to amount, still in itemIds")
    func missingProjectPriceCents() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let items = [
            makeItem(id: "i1", projectId: nil, purchasePriceCents: nil, projectPriceCents: nil),
            makeItem(id: "i2", projectId: nil, purchasePriceCents: 5000, projectPriceCents: 6000),
        ]

        try await service.sellToProject(
            items: items, destinationProjectId: dstProj,
            budgetCategoryId: catId, accountId: acct
        )

        let purchase = batch.sets.first { ($0.fields["type"] as? String) == "Purchase" }!.fields
        // i1 contributes 0, i2 contributes 6000
        #expect(purchase["amountCents"] as? Int == 6000)
        #expect(purchase["subtotalCents"] as? Int == 6000)

        // Both items still in itemIds
        let itemIds = purchase["itemIds"] as? [String] ?? []
        #expect(itemIds.count == 2)
        #expect(Set(itemIds) == Set(["i1", "i2"]))
    }

    @Test("empty items returns immediately without committing")
    func emptyItems() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        try await service.sellToProject(
            items: [], destinationProjectId: dstProj,
            budgetCategoryId: catId, accountId: acct
        )
        #expect(!batch.commitCalled)
    }

    @Test("item without document ID throws before creating Purchase transaction")
    func itemWithoutId() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let items = [
            makeItem(id: nil, projectId: nil),
            makeItem(id: "i2", projectId: nil, purchasePriceCents: 3000, projectPriceCents: 3600),
        ]

        await #expect(throws: InventoryOperationError.self) {
            try await service.sellToProject(
                items: items, destinationProjectId: dstProj,
                budgetCategoryId: catId, accountId: acct
            )
        }

        #expect(batch.sets.isEmpty)
        #expect(batch.updates.isEmpty)
        #expect(batch.autoIdSets.isEmpty)
        #expect(!batch.commitCalled)
    }

    @Test("no source transaction removal when transactionId nil")
    func noSourceRemovalWhenNil() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: nil, purchasePriceCents: 1000, transactionId: nil, projectPriceCents: 1200)

        try await service.sellToProject(
            items: [item], destinationProjectId: dstProj,
            budgetCategoryId: catId, accountId: acct
        )

        // No transaction updates for source removal (only item update)
        let txUpdates = batch.updates.filter { $0.path.contains("/transactions/") }
        #expect(txUpdates.isEmpty)
    }

    @Test("auto-enable budget category at destination")
    func autoEnableBudgetCategory() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: nil, purchasePriceCents: 1000, projectPriceCents: 1200)

        try await service.sellToProject(
            items: [item], destinationProjectId: dstProj,
            budgetCategoryId: catId, accountId: acct, userId: "user1"
        )

        let catSets = batch.setsForPath("accounts/\(acct)/projects/\(dstProj)/budgetCategories/\(catId)")
        #expect(catSets.count == 1)
        #expect(catSets[0].merge == true)
        #expect(catSets[0].fields["updatedBy"] as? String == "user1")
    }

    @Test("projectPriceCents missing — not backfilled from purchasePriceCents")
    func projectPriceNotBackfilledFromPurchasePrice() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: nil, purchasePriceCents: 5000, projectPriceCents: nil)

        try await service.sellToProject(
            items: [item], destinationProjectId: dstProj,
            budgetCategoryId: catId, accountId: acct
        )

        let itemUpdates = batch.updatesForPath("accounts/\(acct)/items/i1")
        #expect(itemUpdates[0].fields["projectPriceCents"] == nil)
    }

    @Test("projectPriceCents written when provided")
    func projectPriceWrittenWhenProvided() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: nil, purchasePriceCents: 5000, projectPriceCents: 3000)

        try await service.sellToProject(
            items: [item], destinationProjectId: dstProj,
            budgetCategoryId: catId, accountId: acct
        )

        let itemUpdates = batch.updatesForPath("accounts/\(acct)/items/i1")
        #expect(itemUpdates[0].fields["projectPriceCents"] as? Int == 3000)
    }

    @Test("no isCanonicalInventorySale or inventorySaleDirection fields")
    func noCanonicalFields() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: nil, purchasePriceCents: 1000, projectPriceCents: 1200)

        try await service.sellToProject(
            items: [item], destinationProjectId: dstProj,
            budgetCategoryId: catId, accountId: acct
        )

        let purchase = batch.sets.first { ($0.fields["type"] as? String) == "Purchase" }!.fields
        #expect(purchase["isCanonicalInventorySale"] == nil)
        #expect(purchase["inventorySaleDirection"] == nil)
    }

    @Test("resolving a planned acquisition is committed in the sale batch")
    func resolvesInventoryIntentInSaleBatch() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(
            id: "i1", projectId: nil, purchasePriceCents: 1000,
            transactionId: "acquisitionTx", projectPriceCents: 1200
        )

        try await service.sellToProject(
            items: [item], destinationProjectId: dstProj,
            budgetCategoryId: catId, accountId: acct, userId: "user1",
            resolveInventoryIntentTransactionId: "acquisitionTx"
        )

        let acquisitionUpdates = batch.updatesForPath(
            "accounts/\(acct)/transactions/acquisitionTx"
        )
        #expect(acquisitionUpdates.count == 2)
        let resolution = acquisitionUpdates.first {
            $0.fields["inventoryIntentResolvedAt"] != nil
        }
        #expect(resolution != nil)
        #expect(resolution?.fields["updatedBy"] as? String == "user1")
        #expect(batch.commitCalled)
    }

    @Test("sale batch failure propagates without a separate intent-resolution write")
    func intentResolutionCommitFailurePropagates() async {
        enum ExpectedFailure: Error { case commit }

        let batch = RecordingBatch()
        batch.commitError = ExpectedFailure.commit
        let service = makeService(batch: batch)
        let item = makeItem(
            id: "i1", projectId: nil, purchasePriceCents: 1000,
            transactionId: "acquisitionTx", projectPriceCents: 1200
        )

        await #expect(throws: ExpectedFailure.self) {
            try await service.sellToProject(
                items: [item], destinationProjectId: dstProj,
                budgetCategoryId: catId, accountId: acct,
                resolveInventoryIntentTransactionId: "acquisitionTx"
            )
        }

        #expect(batch.commitCalled)
        #expect(batch.updatesForPath(
            "accounts/\(acct)/transactions/acquisitionTx"
        ).contains { $0.fields["inventoryIntentResolvedAt"] != nil })
    }
}

// MARK: - returnToInventory (I3)

@Suite("InventoryOperationsService.returnToInventory — per-batch")
struct ReturnToInventoryExecutionTests {

    // I3: returnToInventory with 3 items
    @Test("3 items — 1 Return tx, budgetCategoryId wiped, projectId null")
    func threeItemsHappyPath() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let items = (1...3).map { i in
            makeItem(
                id: "i\(i)", projectId: "srcProj",
                budgetCategoryId: "cat1",
                purchasePriceCents: 1000 * i,
                transactionId: "oldTx"
            )
        }

        try await service.returnToInventory(items: items, accountId: acct, userId: "user1")

        #expect(batch.commitCalled)

        // 1 Return transaction
        let returnSets = batch.sets.filter { ($0.fields["type"] as? String) == "Return" }
        #expect(returnSets.count == 1)
        let ret = returnSets[0].fields
        #expect(ret["type"] as? String == "Return")
        #expect(ret["source"] as? String == "Business Inventory")
        #expect(ret["projectId"] as? String == "srcProj")
        #expect(ret["budgetCategoryId"] as? String == "cat1")
        #expect(ret["status"] as? String == "completed")
        // amountCents = sum of purchasePriceCents: 1000 + 2000 + 3000 = 6000
        #expect(ret["amountCents"] as? Int == 6000)

        let itemIds = ret["itemIds"] as? [String] ?? []
        #expect(Set(itemIds) == Set(["i1", "i2", "i3"]))

        // 3 item updates — projectId and budgetCategoryId wiped
        for i in 1...3 {
            let updates = batch.updatesForPath("accounts/\(acct)/items/i\(i)")
            #expect(updates.count == 1)
            let f = updates[0].fields
            #expect(f["projectId"] is NSNull)
            #expect(f["budgetCategoryId"] is NSNull)
            #expect(f["spaceId"] is NSNull)
            #expect(f["status"] as? String == "purchased")
        }

        // 3 lineage edges with movementKind "returned"
        let edges = batch.lineageEdges(accountId: acct)
        #expect(edges.count == 3)
        for edge in edges {
            #expect(edge.fields["movementKind"] as? String == "returned")
            #expect(edge.fields["fromProjectId"] as? String == "srcProj")
            #expect(edge.fields["createdBy"] as? String == "user1")
        }
    }

    @Test("empty items returns immediately")
    func emptyItems() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        try await service.returnToInventory(items: [], accountId: acct)
        #expect(!batch.commitCalled)
    }

    @Test("101 items throws batch size error")
    func batchSizeExceeded() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let items = (1...101).map { makeItem(id: "i\($0)", projectId: "proj1", budgetCategoryId: "cat1") }

        await #expect(throws: InventoryOperationError.self) {
            try await service.returnToInventory(items: items, accountId: acct)
        }
        #expect(!batch.commitCalled)
    }

    @Test("item without document ID throws before creating empty Return transaction")
    func missingItemIdThrowsBeforeCreatingReturn() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: nil, projectId: "proj1", budgetCategoryId: "cat1", transactionId: "oldTx")

        await #expect(throws: InventoryOperationError.self) {
            try await service.returnToInventory(items: [item], accountId: acct)
        }

        #expect(batch.sets.isEmpty)
        #expect(batch.updates.isEmpty)
        #expect(batch.autoIdSets.isEmpty)
        #expect(!batch.commitCalled)
    }

    @Test("source transaction removal when transactionId present")
    func sourceTransactionRemoval() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "proj1", budgetCategoryId: "cat1", transactionId: "oldTx")

        try await service.returnToInventory(items: [item], accountId: acct)

        let srcUpdates = batch.updatesForPath("accounts/\(acct)/transactions/oldTx")
        #expect(srcUpdates.count == 1)
        #expect(srcUpdates[0].fields.keys.contains("itemIds"))
    }

    @Test("no source transaction removal when transactionId nil")
    func noSourceRemovalWhenNil() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "proj1", budgetCategoryId: "cat1", transactionId: nil)

        try await service.returnToInventory(items: [item], accountId: acct)

        let txUpdates = batch.updates.filter { $0.path.contains("/transactions/") }
        #expect(txUpdates.isEmpty)
    }

    @Test("userId included in lineage edge when present")
    func userIdPresent() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "proj1", budgetCategoryId: "cat1")

        try await service.returnToInventory(items: [item], accountId: acct, userId: "user1")

        let edges = batch.lineageEdges(accountId: acct, itemId: "i1")
        #expect(edges[0].fields["createdBy"] as? String == "user1")
    }

    @Test("userId nil — omitted from lineage edge")
    func userIdNil() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "proj1", budgetCategoryId: "cat1")

        try await service.returnToInventory(items: [item], accountId: acct, userId: nil)

        let edges = batch.lineageEdges(accountId: acct, itemId: "i1")
        #expect(edges[0].fields["createdBy"] == nil)
    }
}

// MARK: - sellItemsFromProjectToProject (I4)

@Suite("InventoryOperationsService.sellItemsFromProjectToProject — per-batch")
struct SellItemsFromProjectToProjectExecutionTests {

    // I4: sellItemsFromProjectToProject with from-inventory items — Return-leg first hop
    @Test("From-inventory items: 1 Return + 1 destination Purchase, lineage edges cross-linked")
    func happyPathFromInventory() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        // currentSource != source ⇒ items previously passed through inventory
        let items = [
            makeItem(id: "i1", projectId: "srcProj", budgetCategoryId: "cat_src", purchasePriceCents: 2000, transactionId: "oldTx",
                     projectPriceCents: 2500, source: "Wayfair", currentSource: "Business Inventory"),
            makeItem(id: "i2", projectId: "srcProj", budgetCategoryId: "cat_src", purchasePriceCents: 3000, transactionId: "oldTx",
                     projectPriceCents: 3500, source: "Wayfair", currentSource: "Business Inventory"),
        ]

        try await service.sellItemsFromProjectToProject(
            items: items, destinationProjectId: "dstProj",
            destinationCategoryId: "cat1", accountId: acct, userId: "user1"
        )

        #expect(batch.commitCalled)

        let returnSets = batch.sets.filter { ($0.fields["type"] as? String) == "Return" }
        #expect(returnSets.count == 1)
        let ret = returnSets[0].fields
        #expect(ret["projectId"] as? String == "srcProj")
        #expect(ret["budgetCategoryId"] as? String == "cat_src")
        #expect(ret["amountCents"] as? Int == 5000)

        let purchaseSets = batch.sets.filter { ($0.fields["type"] as? String) == "Purchase" }
        #expect(purchaseSets.count == 1)
        let purchase = purchaseSets[0].fields
        #expect(purchase["projectId"] as? String == "dstProj")
        #expect(purchase["budgetCategoryId"] as? String == "cat1")
        #expect(purchase["amountCents"] as? Int == 6000)
        #expect(purchase["subtotalCents"] as? Int == 6000)

        for itemId in ["i1", "i2"] {
            let updates = batch.updatesForPath("accounts/\(acct)/items/\(itemId)")
            #expect(updates.count == 1)
            let f = updates[0].fields
            #expect(f["projectId"] as? String == "dstProj")
            #expect(f["budgetCategoryId"] as? String == "cat1")
            #expect(f["status"] as? String == "purchased")
        }

        let edges = batch.lineageEdges(accountId: acct)
        #expect(edges.count == 4)
        let returned = edges.filter { ($0.fields["movementKind"] as? String) == "returned" }
        let sold = edges.filter { ($0.fields["movementKind"] as? String) == "sold" }
        #expect(returned.count == 2)
        #expect(sold.count == 2)

        for edge in returned {
            #expect(edge.fields["fromProjectId"] as? String == "srcProj")
        }
        for edge in sold {
            #expect(edge.fields["toProjectId"] as? String == "dstProj")
        }

        let catSets = batch.setsForPath("accounts/\(acct)/projects/dstProj/budgetCategories/cat1")
        #expect(catSets.count == 1)
    }

    // Project-originated items take the Sale-to-Inventory path on hop 1
    @Test("Originated-here items: Sale-to-Inventory + destination Purchase, soldToInventory edges")
    func happyPathOriginatedHere() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        // currentSource == source ⇒ items originated in srcProj, never touched inventory
        let items = [
            makeItem(id: "i1", projectId: "srcProj", budgetCategoryId: "cat_src", purchasePriceCents: 2000, transactionId: "oldTx",
                     projectPriceCents: 2500, source: "Wayfair", currentSource: "Wayfair"),
            makeItem(id: "i2", projectId: "srcProj", budgetCategoryId: "cat_src", purchasePriceCents: 3000, transactionId: "oldTx",
                     projectPriceCents: 3500, source: "Wayfair", currentSource: "Wayfair"),
        ]

        try await service.sellItemsFromProjectToProject(
            items: items, destinationProjectId: "dstProj",
            destinationCategoryId: "cat1", accountId: acct, userId: "user1"
        )

        // No Return transaction — both items take the Sale-to-Inventory path
        let returnSets = batch.sets.filter { ($0.fields["type"] as? String) == "Return" }
        #expect(returnSets.isEmpty)

        // One Sale-to-Inventory plus one Purchase-from-Inventory destination transaction.
        let saleSets = batch.sets.filter { ($0.fields["type"] as? String) == "Sale" }
        let purchaseSets = batch.sets.filter { ($0.fields["type"] as? String) == "Purchase" }
        #expect(saleSets.count == 1)
        #expect(purchaseSets.count == 1)

        let toInventory = saleSets.first { ($0.fields["budgetCategoryId"] as? String) == "cat_src" }
        let toDest = purchaseSets.first { ($0.fields["budgetCategoryId"] as? String) == "cat1" }
        #expect(toInventory != nil)
        #expect(toDest != nil)
        #expect(toInventory?.fields["projectId"] as? String == "srcProj")
        #expect(toDest?.fields["projectId"] as? String == "dstProj")
        #expect(toInventory?.fields["amountCents"] as? Int == 5000)
        #expect(toDest?.fields["amountCents"] as? Int == 6000)

        // Lineage: 2 soldToInventory (hop 1) + 2 sold (hop 2)
        let edges = batch.lineageEdges(accountId: acct)
        let soldToInventory = edges.filter { ($0.fields["movementKind"] as? String) == "soldToInventory" }
        let purchased = edges.filter { ($0.fields["movementKind"] as? String) == "sold" }
        #expect(soldToInventory.count == 2)
        #expect(purchased.count == 2)
    }

    // Mixed origin: one Return + one Sale-to-Inventory + one destination Purchase
    @Test("Mixed origin items: Return + Sale-to-Inventory + destination Purchase")
    func mixedOriginHop1() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let items = [
            makeItem(id: "i1", projectId: "srcProj", budgetCategoryId: "cat_src", purchasePriceCents: 2000, transactionId: "oldTx",
                     projectPriceCents: 2500, source: "Wayfair", currentSource: "Business Inventory"),
            makeItem(id: "i2", projectId: "srcProj", budgetCategoryId: "cat_src", purchasePriceCents: 3000, transactionId: "oldTx",
                     projectPriceCents: 3500, source: "Wayfair", currentSource: "Wayfair"),
        ]

        try await service.sellItemsFromProjectToProject(
            items: items, destinationProjectId: "dstProj",
            destinationCategoryId: "cat1", accountId: acct, userId: "user1"
        )

        let returnSets = batch.sets.filter { ($0.fields["type"] as? String) == "Return" }
        let saleSets = batch.sets.filter { ($0.fields["type"] as? String) == "Sale" }
        let purchaseSets = batch.sets.filter { ($0.fields["type"] as? String) == "Purchase" }
        #expect(returnSets.count == 1)
        #expect(saleSets.count == 1)
        #expect(purchaseSets.count == 1)

        // Return covers only i1 (the from-inventory item)
        let returnItemIds = returnSets[0].fields["itemIds"] as? [String] ?? []
        #expect(returnItemIds == ["i1"])

        // Sale-to-Inventory covers only i2 and carries the source category
        let toInventory = saleSets.first { ($0.fields["budgetCategoryId"] as? String) == "cat_src" }!
        let toInventoryItemIds = toInventory.fields["itemIds"] as? [String] ?? []
        #expect(toInventoryItemIds == ["i2"])
        #expect(toInventory.fields["amountCents"] as? Int == 3000)
        #expect(returnSets[0].fields["amountCents"] as? Int == 2000)

        // Destination Purchase covers both items
        let toDest = purchaseSets.first { ($0.fields["budgetCategoryId"] as? String) == "cat1" }!
        let toDestItemIds = toDest.fields["itemIds"] as? [String] ?? []
        #expect(Set(toDestItemIds) == Set(["i1", "i2"]))
        #expect(toDest.fields["amountCents"] as? Int == 6000)
    }

    @Test("items in different source projects — throws mixedSourceProjects")
    func mixedSourceProjects() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let items = [
            makeItem(id: "i1", projectId: "proj1"),
            makeItem(id: "i2", projectId: "proj2"),
        ]

        await #expect(throws: InventoryOperationError.self) {
            try await service.sellItemsFromProjectToProject(
                items: items, destinationProjectId: "dstProj",
                destinationCategoryId: "cat1", accountId: acct
            )
        }
        #expect(!batch.commitCalled)
    }

    @Test("source == destination — throws sameSourceAndDestination")
    func sameSourceAndDest() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "proj1")

        await #expect(throws: InventoryOperationError.self) {
            try await service.sellItemsFromProjectToProject(
                items: [item], destinationProjectId: "proj1",
                destinationCategoryId: "cat1", accountId: acct
            )
        }
    }

    @Test("item not in any project — throws itemsNotInProject")
    func itemNotInProject() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: nil)

        await #expect(throws: InventoryOperationError.self) {
            try await service.sellItemsFromProjectToProject(
                items: [item], destinationProjectId: "dstProj",
                destinationCategoryId: "cat1", accountId: acct
            )
        }
    }

    @Test("101 items throws batch size error")
    func batchSizeExceeded() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let items = (1...101).map { makeItem(id: "i\($0)", projectId: "srcProj", budgetCategoryId: "cat1") }

        await #expect(throws: InventoryOperationError.self) {
            try await service.sellItemsFromProjectToProject(
                items: items, destinationProjectId: "dstProj",
                destinationCategoryId: "cat1", accountId: acct
            )
        }
    }

    @Test("empty items returns immediately")
    func emptyItems() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        try await service.sellItemsFromProjectToProject(
            items: [], destinationProjectId: "dstProj",
            destinationCategoryId: "cat1", accountId: acct
        )
        #expect(!batch.commitCalled)
    }
}

// MARK: - reassignToProject (unchanged)

@Suite("InventoryOperationsService.reassignToProject — execution")
struct ReassignToProjectExecutionTests {

    private let proj = "proj1"
    private let destTx = "newTx"

    @Test("empty items returns immediately without committing")
    func emptyItems() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        try await service.reassignToProject(
            items: [], destinationTransactionId: destTx,
            destinationProjectId: proj, accountId: acct
        )
        #expect(!batch.commitCalled)
    }

    @Test("cross-project correction relinks item without sale transactions")
    func crossProjectCorrection() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "otherProj", transactionId: "oldTx", spaceId: "oldSpace")

        try await service.reassignToProject(
            items: [item], destinationTransactionId: destTx,
            destinationProjectId: proj, destinationBudgetCategoryId: "cat1", accountId: acct
        )

        #expect(batch.commitCalled)

        let itemUpdates = batch.updatesForPath("accounts/\(acct)/items/i1")
        #expect(itemUpdates.count == 1)
        #expect(itemUpdates[0].fields["projectId"] as? String == proj)
        #expect(itemUpdates[0].fields["transactionId"] as? String == destTx)
        #expect(itemUpdates[0].fields["budgetCategoryId"] as? String == "cat1")
        #expect(itemUpdates[0].fields["spaceId"] is NSNull)

        let edges = batch.lineageEdges(accountId: acct, itemId: "i1")
        #expect(edges.count == 1)
        let ef = edges[0].fields
        #expect(ef["movementKind"] as? String == "correction")
        #expect(ef["fromProjectId"] as? String == "otherProj")
        #expect(ef["toProjectId"] as? String == proj)

        let financialSets = batch.sets.filter {
            let type = $0.fields["type"] as? String
            return type == "Purchase" || type == "Sale" || type == "Return"
        }
        #expect(financialSets.isEmpty)
    }

    @Test("single item happy path — within-scope reassign")
    func singleItemHappyPath() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: proj, transactionId: "oldTx")

        try await service.reassignToProject(
            items: [item], destinationTransactionId: destTx,
            destinationProjectId: proj, accountId: acct
        )

        #expect(batch.commitCalled)

        // Item update — transactionId changed and destination project is set
        let itemUpdates = batch.updatesForPath("accounts/\(acct)/items/i1")
        #expect(itemUpdates.count == 1)
        #expect(itemUpdates[0].fields["transactionId"] as? String == destTx)
        #expect(itemUpdates[0].fields["projectId"] as? String == proj)

        // Source transaction — remove item
        let srcUpdates = batch.updatesForPath("accounts/\(acct)/transactions/oldTx")
        #expect(srcUpdates.count == 1)

        // Destination transaction — add item
        let dstUpdates = batch.updatesForPath("accounts/\(acct)/transactions/\(destTx)")
        #expect(dstUpdates.count == 1)

        // Lineage edge
        let edges = batch.lineageEdges(accountId: acct, itemId: "i1")
        #expect(edges.count == 1)
        let ef = edges[0].fields
        #expect(ef["movementKind"] as? String == "correction")
        #expect(ef["note"] as? String == "Reassigned to project transaction")
        #expect(ef["fromTransactionId"] as? String == "oldTx")
        #expect(ef["toTransactionId"] as? String == destTx)

        // No sale/return transactions created
        #expect(batch.sets.isEmpty)
    }
}

// MARK: - computeBatchTotals (I9 shape parity)

@Suite("InventoryOperationsService.computeBatchTotals — shape parity")
struct ComputeBatchTotalsTests {

    // I9: Shape parity — matches mcp-server/test/fixtures/sale-transaction.golden.json
    @Test("matches golden fixture: amountCents includes tax, subtotalCents excludes tax")
    func goldenFixtureParity() {
        let items = [
            makeItem(id: "item_a", purchasePriceCents: 10000, projectPriceCents: 12000, taxRatePct: 8.25),
            makeItem(id: "item_b", purchasePriceCents: 5000, projectPriceCents: 6000, taxRatePct: 8.25),
        ]

        let (subtotalCents, amountCents) = InventoryOperationsService.computeBatchTotals(items)

        // Golden fixture expects:
        //   subtotalCents = 12000 + 6000 = 18000
        //   amountCents = round(12000 * 1.0825) + round(6000 * 1.0825) = 12990 + 6495 = 19485
        #expect(subtotalCents == 18000)
        #expect(amountCents == 19485)
    }

    @Test("items without taxRatePct — amountCents equals subtotalCents")
    func noTaxRate() {
        let items = [
            makeItem(id: "i1", purchasePriceCents: 1000, projectPriceCents: 1200),
            makeItem(id: "i2", purchasePriceCents: 2000, projectPriceCents: 2400),
        ]

        let (subtotalCents, amountCents) = InventoryOperationsService.computeBatchTotals(items)

        #expect(subtotalCents == 3600)
        #expect(amountCents == 3600)
    }

    @Test("missing projectPriceCents contributes 0")
    func missingProjectPriceContributesZero() {
        let items = [
            makeItem(id: "i1", purchasePriceCents: 5000, projectPriceCents: nil),
        ]

        let (subtotalCents, amountCents) = InventoryOperationsService.computeBatchTotals(items)

        #expect(subtotalCents == 0)
        #expect(amountCents == 0)
    }

    @Test("both prices nil — contributes 0")
    func bothPricesNil() {
        let items = [makeItem(id: "i1", purchasePriceCents: nil, projectPriceCents: nil)]

        let (subtotalCents, amountCents) = InventoryOperationsService.computeBatchTotals(items)

        #expect(subtotalCents == 0)
        #expect(amountCents == 0)
    }
}

// MARK: - normalizeTransactionAmount (dual-read path)

@Suite("BudgetTabCalculations.normalizeTransactionAmount — dual-read")
struct NormalizeTransactionAmountTests {

    private func makeTx(
        type: TransactionType? = nil,
        status: TransactionStatus? = nil,
        amountCents: Int? = nil,
        isCanonicalInventorySale: Bool? = nil,
        inventorySaleDirection: InventorySaleDirection? = nil
    ) -> Transaction {
        var tx = Transaction()
        tx.transactionType = type
        tx.status = status
        tx.amountCents = amountCents
        tx.isCanonicalInventorySale = isCanonicalInventorySale
        tx.inventorySaleDirection = inventorySaleDirection
        return tx
    }

    @Test("canceled → 0")
    func canceled() {
        let tx = makeTx(type: .sale, status: .canceled, amountCents: 5000)
        #expect(BudgetTabCalculations.normalizeTransactionAmount(tx) == 0)
    }

    @Test("return type → -abs(amount)")
    func returnType() {
        let tx = makeTx(type: .return, amountCents: 3000)
        #expect(BudgetTabCalculations.normalizeTransactionAmount(tx) == -3000)
    }

    @Test("legacy canonical sale businessToProject → +abs(amount)")
    func legacyBusinessToProject() {
        let tx = makeTx(type: .sale, amountCents: 2000, isCanonicalInventorySale: true, inventorySaleDirection: .businessToProject)
        #expect(BudgetTabCalculations.normalizeTransactionAmount(tx) == 2000)
    }

    @Test("legacy canonical sale projectToBusiness → -abs(amount)")
    func legacyProjectToBusiness() {
        let tx = makeTx(type: .sale, amountCents: 2000, isCanonicalInventorySale: true, inventorySaleDirection: .projectToBusiness)
        #expect(BudgetTabCalculations.normalizeTransactionAmount(tx) == -2000)
    }

    @Test("new per-batch sale → -abs(amount)")
    func newPerBatchSale() {
        let tx = makeTx(type: .sale, amountCents: 4000)
        #expect(BudgetTabCalculations.normalizeTransactionAmount(tx) == -4000)
    }

    @Test("purchase → amount as-stored")
    func purchaseAsStored() {
        let tx = makeTx(type: .purchase, amountCents: 1500)
        #expect(BudgetTabCalculations.normalizeTransactionAmount(tx) == 1500)
    }
}

// MARK: - Inventory Label Helper

@Suite("InventoryOperationsService.inventoryLabel(for:)")
struct InventoryLabelTests {

    @Test("nil account name → default 'Business Inventory'")
    func nilName() {
        #expect(InventoryOperationsService.inventoryLabel(for: nil) == "Business Inventory")
    }

    @Test("empty account name → default 'Business Inventory'")
    func emptyName() {
        #expect(InventoryOperationsService.inventoryLabel(for: "") == "Business Inventory")
    }

    @Test("whitespace-only account name → default 'Business Inventory'")
    func whitespaceName() {
        #expect(InventoryOperationsService.inventoryLabel(for: "   \n\t") == "Business Inventory")
    }

    @Test("named account → '[Name] Inventory' with whitespace trimmed")
    func namedAccount() {
        #expect(InventoryOperationsService.inventoryLabel(for: "1584 Design") == "1584 Design Inventory")
        #expect(InventoryOperationsService.inventoryLabel(for: "  1584 Design  ") == "1584 Design Inventory")
    }
}

// MARK: - Custom inventoryLabel passthrough

@Suite("sellToProject / returnToInventory / sellItemsFromProjectToProject — custom inventoryLabel")
struct InventoryLabelPassthroughTests {

    @Test("sellToProject writes custom source label on the Purchase transaction")
    func sellToProjectCustomLabel() async throws {
        let batch = RecordingBatch()
        let service = InventoryOperationsService(makeBatch: { batch })
        let items = [makeItem(id: "i1", projectId: nil, purchasePriceCents: 1000)]

        try await service.sellToProject(
            items: items,
            destinationProjectId: "dstProj",
            budgetCategoryId: "cat1",
            accountId: acct,
            inventoryLabel: "1584 Design Inventory"
        )

        let purchase = batch.sets.first { ($0.fields["type"] as? String) == "Purchase" }?.fields
        #expect(purchase?["source"] as? String == "1584 Design Inventory")
    }

    @Test("sellToProject defaults to 'Business Inventory' when label not provided")
    func sellToProjectDefaultLabel() async throws {
        let batch = RecordingBatch()
        let service = InventoryOperationsService(makeBatch: { batch })
        let items = [makeItem(id: "i1", projectId: nil, purchasePriceCents: 1000)]

        try await service.sellToProject(
            items: items,
            destinationProjectId: "dstProj",
            budgetCategoryId: "cat1",
            accountId: acct
        )

        let purchase = batch.sets.first { ($0.fields["type"] as? String) == "Purchase" }?.fields
        #expect(purchase?["source"] as? String == "Business Inventory")
    }

    @Test("returnToInventory writes custom source label on the Return transaction")
    func returnToInventoryCustomLabel() async throws {
        let batch = RecordingBatch()
        let service = InventoryOperationsService(makeBatch: { batch })
        let items = [makeItem(id: "i1", projectId: "proj1", budgetCategoryId: "cat1", purchasePriceCents: 1000)]

        try await service.returnToInventory(
            items: items,
            accountId: acct,
            inventoryLabel: "1584 Design Inventory"
        )

        let ret = batch.sets.first { ($0.fields["type"] as? String) == "Return" }?.fields
        #expect(ret?["source"] as? String == "1584 Design Inventory")
    }

    @Test("returnToInventory writes paid item credit as created invoice, not transaction")
    func returnToInventoryWritesPaidCreditCreatedInvoice() async throws {
        let batch = RecordingBatch()
        let service = InventoryOperationsService(makeBatch: { batch })
        let items = [
            makeItem(
                id: "i1",
                projectId: "proj1",
                budgetCategoryId: "cat1",
                purchasePriceCents: 1000,
                transactionId: "oldTx",
                projectPriceCents: 1500
            ),
        ]
        let credit = InvoiceLineCalculations.ReturnedPaidItemCreditContext(
            itemId: "i1",
            itemName: "item",
            projectId: "proj1",
            amountCents: 1500,
            budgetCategoryId: "cat1",
            paidInvoiceId: "paidInv",
            paidInvoiceLineId: "paidLine",
            lineId: "returnCredit:paidInv:paidLine:i1"
        )

        try await service.returnToInventory(
            items: items,
            accountId: acct,
            returnedPaidItemCredits: [credit]
        )

        let txSets = batch.sets.filter { $0.path.contains("/transactions/") }
        #expect(txSets.count == 1)
        #expect(txSets[0].fields["type"] as? String == "Return")
        #expect(batch.autoIdSetsInCollection("accounts/\(acct)/transactions").isEmpty)

        let invoiceSets = batch.sets.filter { $0.path.contains("/invoices/") }
        #expect(invoiceSets.count == 1)
        let invoice = invoiceSets[0].fields
        #expect(invoice["status"] as? String == "created")
        #expect(invoice["projectId"] as? String == "proj1")
        #expect(invoice["itemIds"] as? [String] == [])
        #expect(invoice["transactionIds"] as? [String] == [])
        let lines = try #require(invoice["lines"] as? [[String: Any]])
        #expect(lines.count == 1)
        #expect(lines[0]["id"] as? String == "returnCredit:paidInv:paidLine:i1")
        #expect(lines[0]["sourceType"] as? String == "manual")
        #expect(lines[0]["sign"] as? Int == -1)
        #expect(lines[0]["budgetCategoryId"] as? String == "cat1")
    }

    @Test("sellItemsFromProjectToProject writes custom source label on both Return and Sale")
    func sellItemsFromProjectToProjectCustomLabel() async throws {
        let batch = RecordingBatch()
        let service = InventoryOperationsService(makeBatch: { batch })
        // From-inventory item — triggers the Return-leg first hop
        let items = [
            makeItem(id: "i1", projectId: "srcProj", budgetCategoryId: "cat_src", purchasePriceCents: 1000,
                     transactionId: "oldTx", projectPriceCents: 1200, source: "Wayfair",
                     currentSource: "Business Inventory"),
        ]

        try await service.sellItemsFromProjectToProject(
            items: items,
            destinationProjectId: "dstProj",
            destinationCategoryId: "cat1",
            accountId: acct,
            inventoryLabel: "1584 Design Inventory"
        )

        let ret = batch.sets.first { ($0.fields["type"] as? String) == "Return" }?.fields
        let purchase = batch.sets.first { ($0.fields["type"] as? String) == "Purchase" }?.fields
        #expect(ret?["source"] as? String == "1584 Design Inventory")
        #expect(purchase?["source"] as? String == "1584 Design Inventory")
    }
}

// MARK: - currentSource denormalization

@Suite("sellToProject / returnToInventory / sellItemsFromProjectToProject — currentSource denormalization")
struct CurrentSourceDenormalizationTests {

    @Test("sellToProject writes currentSource=inventoryLabel on each item update")
    func sellToProjectWritesCurrentSource() async throws {
        let batch = RecordingBatch()
        let service = InventoryOperationsService(makeBatch: { batch })
        let items = [
            makeItem(id: "i1", projectId: nil, purchasePriceCents: 1000),
            makeItem(id: "i2", projectId: nil, purchasePriceCents: 2000),
        ]

        try await service.sellToProject(
            items: items,
            destinationProjectId: "dstProj",
            budgetCategoryId: "cat1",
            accountId: acct,
            inventoryLabel: "1584 Design Inventory"
        )

        for id in ["i1", "i2"] {
            let updates = batch.updatesForPath("accounts/\(acct)/items/\(id)")
            #expect(updates.count == 1)
            #expect(updates.first?.fields["currentSource"] as? String == "1584 Design Inventory")
            // Original `source` must NOT be in the update dict — preserved for returns.
            #expect(updates.first?.fields["source"] == nil)
        }
    }

    @Test("sellToProject defaults currentSource to 'Business Inventory' when label not provided")
    func sellToProjectDefaultsCurrentSource() async throws {
        let batch = RecordingBatch()
        let service = InventoryOperationsService(makeBatch: { batch })
        let items = [makeItem(id: "i1", projectId: nil, purchasePriceCents: 1000)]

        try await service.sellToProject(
            items: items,
            destinationProjectId: "dstProj",
            budgetCategoryId: "cat1",
            accountId: acct
        )

        let update = batch.updatesForPath("accounts/\(acct)/items/i1").first
        #expect(update?.fields["currentSource"] as? String == "Business Inventory")
    }

    @Test("returnToInventory writes currentSource=inventoryLabel on each item update")
    func returnToInventoryWritesCurrentSource() async throws {
        let batch = RecordingBatch()
        let service = InventoryOperationsService(makeBatch: { batch })
        let items = [makeItem(id: "i1", projectId: "proj1", budgetCategoryId: "cat1", purchasePriceCents: 1000)]

        try await service.returnToInventory(
            items: items,
            accountId: acct,
            inventoryLabel: "1584 Design Inventory"
        )

        let update = batch.updatesForPath("accounts/\(acct)/items/i1").first
        #expect(update?.fields["currentSource"] as? String == "1584 Design Inventory")
        #expect(update?.fields["source"] == nil)
    }

    @Test("sellItemsFromProjectToProject writes currentSource=inventoryLabel on each item update")
    func sellItemsFromProjectToProjectWritesCurrentSource() async throws {
        let batch = RecordingBatch()
        let service = InventoryOperationsService(makeBatch: { batch })
        let items = [
            makeItem(
                id: "i1", projectId: "srcProj",
                budgetCategoryId: "cat_src",
                purchasePriceCents: 1000,
                transactionId: "oldTx",
                projectPriceCents: 1200,
                source: "Business Inventory",
                currentSource: "Business Inventory"
            ),
        ]

        try await service.sellItemsFromProjectToProject(
            items: items,
            destinationProjectId: "dstProj",
            destinationCategoryId: "cat1",
            accountId: acct,
            inventoryLabel: "1584 Design Inventory"
        )

        let update = batch.updatesForPath("accounts/\(acct)/items/i1").first
        #expect(update?.fields["currentSource"] as? String == "1584 Design Inventory")
    }

    @Test("reassignToProject does NOT touch currentSource (within-project move)")
    func reassignToProjectLeavesCurrentSourceAlone() async throws {
        let batch = RecordingBatch()
        let service = InventoryOperationsService(makeBatch: { batch })
        let items = [
            makeItem(id: "i1", projectId: "proj1", budgetCategoryId: "cat1", transactionId: "oldTx"),
        ]

        try await service.reassignToProject(
            items: items,
            destinationTransactionId: "newTx",
            destinationProjectId: "proj1",
            accountId: acct
        )

        let update = batch.updatesForPath("accounts/\(acct)/items/i1").first
        #expect(update?.fields["currentSource"] == nil)
    }

    @Test("returnToTransaction does NOT touch currentSource (within-project move)")
    func returnToTransactionLeavesCurrentSourceAlone() async throws {
        let batch = RecordingBatch()
        let service = InventoryOperationsService(makeBatch: { batch })
        let items = [
            makeItem(id: "i1", projectId: "proj1", budgetCategoryId: "cat1", transactionId: "oldTx"),
        ]

        try await service.returnToTransaction(
            items: items,
            destinationTransactionId: "retTx",
            accountId: acct
        )

        let update = batch.updatesForPath("accounts/\(acct)/items/i1").first
        #expect(update?.fields["currentSource"] == nil)
    }
}
