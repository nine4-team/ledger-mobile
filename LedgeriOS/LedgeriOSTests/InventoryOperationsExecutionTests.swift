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
    status: ItemStatus? = nil
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
    @Test("5 items — 1 Sale tx, correct amountCents, item fields, 5 lineage edges")
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

        // Exactly 1 Sale transaction (via setData, not setDataAutoId)
        let saleSets = batch.sets.filter {
            ($0.fields["type"] as? String) == "Sale"
        }
        #expect(saleSets.count == 1)
        let sale = saleSets[0].fields

        // Shape fields
        #expect(sale["type"] as? String == "Sale")
        #expect(sale["source"] as? String == "Business Inventory")
        #expect(sale["projectId"] as? String == dstProj)
        #expect(sale["budgetCategoryId"] as? String == catId)
        #expect(sale["status"] as? String == "completed")
        #expect(sale["isComplete"] as? Bool == true)

        // amountCents = sum of projectPriceCents (no tax)
        // 1200 + 2400 + 3600 + 4800 + 6000 = 18000
        #expect(sale["amountCents"] as? Int == 18000)
        #expect(sale["subtotalCents"] as? Int == 18000)

        // itemIds
        let itemIds = sale["itemIds"] as? [String] ?? []
        #expect(itemIds.count == 5)
        #expect(Set(itemIds) == Set(["i1", "i2", "i3", "i4", "i5"]))

        // Sale doc path contains the auto-generated UUID (not a SALE_ prefix)
        let salePath = saleSets[0].path
        #expect(!salePath.contains("SALE_"))

        // 5 item updates
        for i in 1...5 {
            let updates = batch.updatesForPath("accounts/\(acct)/items/i\(i)")
            #expect(updates.count == 1)
            let f = updates[0].fields
            #expect(f["projectId"] as? String == dstProj)
            #expect(f["budgetCategoryId"] as? String == catId)
            #expect(f["status"] as? String == "purchased")
            #expect(f["spaceId"] is NSNull)
            // transactionId is the UUID from the sale doc
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

        // Each batch has exactly 1 sale transaction
        let sale1 = batch1.sets.filter { ($0.fields["type"] as? String) == "Sale" }
        let sale2 = batch2.sets.filter { ($0.fields["type"] as? String) == "Sale" }
        #expect(sale1.count == 1)
        #expect(sale2.count == 1)

        // Different doc paths (different UUIDs)
        #expect(sale1[0].path != sale2[0].path)

        // First sale unchanged by second
        #expect(sale1[0].fields["amountCents"] as? Int == 1200)
        #expect(sale2[0].fields["amountCents"] as? Int == 2400)
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

        let sale = batch.sets.first { ($0.fields["type"] as? String) == "Sale" }!.fields
        // i1 contributes 0, i2 contributes 6000
        #expect(sale["amountCents"] as? Int == 6000)
        #expect(sale["subtotalCents"] as? Int == 6000)

        // Both items still in itemIds
        let itemIds = sale["itemIds"] as? [String] ?? []
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

    @Test("item without id — skipped in batch but sale still created")
    func itemWithoutId() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let items = [
            makeItem(id: nil, projectId: nil),
            makeItem(id: "i2", projectId: nil, purchasePriceCents: 3000, projectPriceCents: 3600),
        ]

        try await service.sellToProject(
            items: items, destinationProjectId: dstProj,
            budgetCategoryId: catId, accountId: acct
        )

        // Sale still created (nil-id item contributes to itemIds via compactMap)
        let sale = batch.sets.first { ($0.fields["type"] as? String) == "Sale" }!.fields
        let itemIds = sale["itemIds"] as? [String] ?? []
        #expect(itemIds == ["i2"]) // nil-id item excluded

        // Only i2 gets item update
        #expect(batch.updatesForPath("accounts/\(acct)/items/i2").count == 1)
        #expect(batch.lineageEdges(accountId: acct).count == 1)
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

    @Test("projectPriceCents backfill — nil projectPriceCents with purchasePriceCents")
    func projectPriceBackfill() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: nil, purchasePriceCents: 5000, projectPriceCents: nil)

        try await service.sellToProject(
            items: [item], destinationProjectId: dstProj,
            budgetCategoryId: catId, accountId: acct
        )

        let itemUpdates = batch.updatesForPath("accounts/\(acct)/items/i1")
        #expect(itemUpdates[0].fields["projectPriceCents"] as? Int == 5000)
    }

    @Test("projectPriceCents NOT backfilled when already set")
    func projectPriceNotBackfilled() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: nil, purchasePriceCents: 5000, projectPriceCents: 3000)

        try await service.sellToProject(
            items: [item], destinationProjectId: dstProj,
            budgetCategoryId: catId, accountId: acct
        )

        let itemUpdates = batch.updatesForPath("accounts/\(acct)/items/i1")
        #expect(itemUpdates[0].fields["projectPriceCents"] == nil)
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

        let sale = batch.sets.first { ($0.fields["type"] as? String) == "Sale" }!.fields
        #expect(sale["isCanonicalInventorySale"] == nil)
        #expect(sale["inventorySaleDirection"] == nil)
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
                budgetCategoryId: "cat\(i)",
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
        let items = (1...101).map { makeItem(id: "i\($0)", projectId: "proj1") }

        await #expect(throws: InventoryOperationError.self) {
            try await service.returnToInventory(items: items, accountId: acct)
        }
        #expect(!batch.commitCalled)
    }

    @Test("source transaction removal when transactionId present")
    func sourceTransactionRemoval() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "proj1", transactionId: "oldTx")

        try await service.returnToInventory(items: [item], accountId: acct)

        let srcUpdates = batch.updatesForPath("accounts/\(acct)/transactions/oldTx")
        #expect(srcUpdates.count == 1)
        #expect(srcUpdates[0].fields.keys.contains("itemIds"))
    }

    @Test("no source transaction removal when transactionId nil")
    func noSourceRemovalWhenNil() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "proj1", transactionId: nil)

        try await service.returnToInventory(items: [item], accountId: acct)

        let txUpdates = batch.updates.filter { $0.path.contains("/transactions/") }
        #expect(txUpdates.isEmpty)
    }

    @Test("userId included in lineage edge when present")
    func userIdPresent() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "proj1")

        try await service.returnToInventory(items: [item], accountId: acct, userId: "user1")

        let edges = batch.lineageEdges(accountId: acct, itemId: "i1")
        #expect(edges[0].fields["createdBy"] as? String == "user1")
    }

    @Test("userId nil — omitted from lineage edge")
    func userIdNil() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "proj1")

        try await service.returnToInventory(items: [item], accountId: acct, userId: nil)

        let edges = batch.lineageEdges(accountId: acct, itemId: "i1")
        #expect(edges[0].fields["createdBy"] == nil)
    }
}

// MARK: - moveBetweenProjects (I4)

@Suite("InventoryOperationsService.moveBetweenProjects — per-batch")
struct MoveBetweenProjectsExecutionTests {

    // I4: moveBetweenProjects — 1 Return + 1 Sale, lineage edges cross-linked
    @Test("1 Return + 1 Sale in one batch, budget math nets, lineage edges")
    func happyPath() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let items = [
            makeItem(id: "i1", projectId: "srcProj", purchasePriceCents: 2000, transactionId: "oldTx", projectPriceCents: 2500),
            makeItem(id: "i2", projectId: "srcProj", purchasePriceCents: 3000, transactionId: "oldTx", projectPriceCents: 3500),
        ]

        try await service.moveBetweenProjects(
            items: items, destinationProjectId: "dstProj",
            destinationCategoryId: "cat1", accountId: acct, userId: "user1"
        )

        #expect(batch.commitCalled)

        // 1 Return transaction
        let returnSets = batch.sets.filter { ($0.fields["type"] as? String) == "Return" }
        #expect(returnSets.count == 1)
        let ret = returnSets[0].fields
        #expect(ret["projectId"] as? String == "srcProj")
        #expect(ret["amountCents"] as? Int == 5000) // sum of purchasePriceCents

        // 1 Sale transaction
        let saleSets = batch.sets.filter { ($0.fields["type"] as? String) == "Sale" }
        #expect(saleSets.count == 1)
        let sale = saleSets[0].fields
        #expect(sale["projectId"] as? String == "dstProj")
        #expect(sale["budgetCategoryId"] as? String == "cat1")
        #expect(sale["amountCents"] as? Int == 6000) // sum of projectPriceCents (no tax)
        #expect(sale["subtotalCents"] as? Int == 6000)

        // Item updates — items land in destination project
        for itemId in ["i1", "i2"] {
            let updates = batch.updatesForPath("accounts/\(acct)/items/\(itemId)")
            #expect(updates.count == 1)
            let f = updates[0].fields
            #expect(f["projectId"] as? String == "dstProj")
            #expect(f["budgetCategoryId"] as? String == "cat1")
            #expect(f["status"] as? String == "purchased")
        }

        // 4 lineage edges total — 2 returned + 2 sold
        let edges = batch.lineageEdges(accountId: acct)
        #expect(edges.count == 4)
        let returned = edges.filter { ($0.fields["movementKind"] as? String) == "returned" }
        let sold = edges.filter { ($0.fields["movementKind"] as? String) == "sold" }
        #expect(returned.count == 2)
        #expect(sold.count == 2)

        // Returned edges point from srcProj
        for edge in returned {
            #expect(edge.fields["fromProjectId"] as? String == "srcProj")
        }
        // Sold edges point to dstProj
        for edge in sold {
            #expect(edge.fields["toProjectId"] as? String == "dstProj")
        }

        // Auto-enable budget category
        let catSets = batch.setsForPath("accounts/\(acct)/projects/dstProj/budgetCategories/cat1")
        #expect(catSets.count == 1)
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
            try await service.moveBetweenProjects(
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
            try await service.moveBetweenProjects(
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
            try await service.moveBetweenProjects(
                items: [item], destinationProjectId: "dstProj",
                destinationCategoryId: "cat1", accountId: acct
            )
        }
    }

    @Test("101 items throws batch size error")
    func batchSizeExceeded() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let items = (1...101).map { makeItem(id: "i\($0)", projectId: "srcProj") }

        await #expect(throws: InventoryOperationError.self) {
            try await service.moveBetweenProjects(
                items: items, destinationProjectId: "dstProj",
                destinationCategoryId: "cat1", accountId: acct
            )
        }
    }

    @Test("empty items returns immediately")
    func emptyItems() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        try await service.moveBetweenProjects(
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

    @Test("cross-scope throws — item projectId differs from destination")
    func crossScopeThrows() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "otherProj")

        await #expect(throws: InventoryOperationError.self) {
            try await service.reassignToProject(
                items: [item], destinationTransactionId: destTx,
                destinationProjectId: proj, accountId: acct
            )
        }

        #expect(!batch.commitCalled)
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

        // Item update — transactionId changed, projectId NOT changed
        let itemUpdates = batch.updatesForPath("accounts/\(acct)/items/i1")
        #expect(itemUpdates.count == 1)
        #expect(itemUpdates[0].fields["transactionId"] as? String == destTx)
        #expect(itemUpdates[0].fields["projectId"] == nil) // Not touched

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
        #expect(ef["note"] as? String == "Reassigned to transaction")
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

    @Test("falls back to purchasePriceCents when projectPriceCents nil")
    func fallbackToPurchasePrice() {
        let items = [
            makeItem(id: "i1", purchasePriceCents: 5000, projectPriceCents: nil),
        ]

        let (subtotalCents, amountCents) = InventoryOperationsService.computeBatchTotals(items)

        #expect(subtotalCents == 5000)
        #expect(amountCents == 5000)
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

    @Test("new per-batch sale → +abs(amount)")
    func newPerBatchSale() {
        let tx = makeTx(type: .sale, amountCents: 4000)
        #expect(BudgetTabCalculations.normalizeTransactionAmount(tx) == 4000)
    }

    @Test("purchase → amount as-stored")
    func purchaseAsStored() {
        let tx = makeTx(type: .purchase, amountCents: 1500)
        #expect(BudgetTabCalculations.normalizeTransactionAmount(tx) == 1500)
    }
}
