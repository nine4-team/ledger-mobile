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
    item.spaceId = spaceId
    item.status = status
    return item
}

private func makeService(batch: RecordingBatch) -> InventoryOperationsService {
    InventoryOperationsService(makeBatch: { batch })
}

// MARK: - sellToBusiness

@Suite("InventoryOperationsService.sellToBusiness — execution")
struct SellToBusinessExecutionTests {

    @Test("empty items returns immediately without committing")
    func emptyItems() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        try await service.sellToBusiness(items: [], accountId: acct)
        #expect(!batch.commitCalled)
        #expect(batch.sets.isEmpty)
        #expect(batch.updates.isEmpty)
        #expect(batch.autoIdSets.isEmpty)
    }

    @Test("single item happy path — canonical sale, item update, source removal, lineage edge")
    func singleItemHappyPath() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(
            id: "i1", projectId: "proj1", budgetCategoryId: "cat1",
            purchasePriceCents: 5000, transactionId: "oldTx"
        )

        try await service.sellToBusiness(items: [item], accountId: acct)

        #expect(batch.commitCalled)

        // Canonical sale transaction
        let saleId = "SALE_proj1_project_to_business_cat1"
        let saleSets = batch.setsForPath("accounts/\(acct)/transactions/\(saleId)")
        #expect(saleSets.count == 1)
        let saleFields = saleSets[0].fields
        #expect(saleFields["projectId"] as? String == "proj1")
        #expect(saleFields["type"] as? String == "sale")
        #expect(saleFields["isCanonicalInventorySale"] as? Bool == true)
        #expect(saleFields["inventorySaleDirection"] as? String == "project_to_business")
        #expect(saleFields["budgetCategoryId"] as? String == "cat1")
        #expect(saleFields.keys.contains("itemIds"))
        #expect(saleFields.keys.contains("amountCents"))
        #expect(saleFields.keys.contains("createdAt"))
        #expect(saleFields.keys.contains("updatedAt"))
        #expect(saleSets[0].merge == true)

        // Item update
        let itemUpdates = batch.updatesForPath("accounts/\(acct)/items/i1")
        #expect(itemUpdates.count == 1)
        let itemFields = itemUpdates[0].fields
        #expect(itemFields["projectId"] is NSNull)
        #expect(itemFields["spaceId"] is NSNull)
        #expect(itemFields["status"] as? String == "purchased")
        #expect(itemFields["transactionId"] as? String == saleId)
        #expect(itemFields.keys.contains("updatedAt"))

        // Source transaction removal
        let srcTxUpdates = batch.updatesForPath("accounts/\(acct)/transactions/oldTx")
        #expect(srcTxUpdates.count == 1)
        #expect(srcTxUpdates[0].fields.keys.contains("itemIds"))

        // Lineage edge
        let edges = batch.lineageEdges(accountId: acct, itemId: "i1")
        #expect(edges.count == 1)
        let edgeFields = edges[0].fields
        #expect(edgeFields["accountId"] as? String == acct)
        #expect(edgeFields["fromProjectId"] as? String == "proj1")
        #expect(edgeFields["toTransactionId"] as? String == saleId)
        #expect(edgeFields["movementKind"] as? String == "sold")
        #expect(edgeFields["source"] as? String == "app")
        #expect(edgeFields["fromTransactionId"] as? String == "oldTx")
        #expect(edgeFields.keys.contains("createdAt"))
    }

    @Test("item without transactionId — no source removal, edge omits fromTransactionId")
    func itemWithoutTransactionId() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "proj1", budgetCategoryId: "cat1", transactionId: nil)

        try await service.sellToBusiness(items: [item], accountId: acct)

        // No source transaction update (only item update exists)
        let allUpdatePaths = batch.updates.map(\.path)
        #expect(!allUpdatePaths.contains(where: { $0.contains("/transactions/") }))

        // Edge omits fromTransactionId
        let edges = batch.lineageEdges(accountId: acct, itemId: "i1")
        #expect(edges.count == 1)
        #expect(edges[0].fields["fromTransactionId"] == nil)
    }

    @Test("item without projectId — skipped entirely")
    func itemWithoutProjectId() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: nil, budgetCategoryId: "cat1")

        try await service.sellToBusiness(items: [item], accountId: acct)

        // groupForSale skips items without projectId → no canonical sale
        #expect(batch.sets.isEmpty)
        // per-item loop guard fails → no item update or edge
        #expect(batch.updates.isEmpty)
        #expect(batch.autoIdSets.isEmpty)
        // Still commits (guard !items.isEmpty passed)
        #expect(batch.commitCalled)
    }

    @Test("item without id — per-item loop skipped")
    func itemWithoutId() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: nil, projectId: "proj1", budgetCategoryId: "cat1")

        try await service.sellToBusiness(items: [item], accountId: acct)

        // groupForSale still includes the item (compactMap(\.id) yields empty)
        // but per-item guard fails → no updateData or edge
        #expect(batch.updates.isEmpty)
        #expect(batch.autoIdSets.isEmpty)
        #expect(batch.commitCalled)
    }

    @Test("multiple items same category — single canonical sale, multiple item updates")
    func multipleItemsSameCategory() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let items = [
            makeItem(id: "i1", projectId: "proj1", budgetCategoryId: "cat1", purchasePriceCents: 1000),
            makeItem(id: "i2", projectId: "proj1", budgetCategoryId: "cat1", purchasePriceCents: 2000),
        ]

        try await service.sellToBusiness(items: items, accountId: acct)

        // One canonical sale
        let saleId = "SALE_proj1_project_to_business_cat1"
        let saleSets = batch.setsForPath("accounts/\(acct)/transactions/\(saleId)")
        #expect(saleSets.count == 1)

        // Two item updates
        let i1Updates = batch.updatesForPath("accounts/\(acct)/items/i1")
        let i2Updates = batch.updatesForPath("accounts/\(acct)/items/i2")
        #expect(i1Updates.count == 1)
        #expect(i2Updates.count == 1)

        // Two lineage edges
        #expect(batch.lineageEdges(accountId: acct).count == 2)
    }

    @Test("multiple items different categories — multiple canonical sales")
    func multipleItemsDifferentCategories() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let items = [
            makeItem(id: "i1", projectId: "proj1", budgetCategoryId: "cat1"),
            makeItem(id: "i2", projectId: "proj1", budgetCategoryId: "cat2"),
        ]

        try await service.sellToBusiness(items: items, accountId: acct)

        let sale1Sets = batch.setsForPath("accounts/\(acct)/transactions/SALE_proj1_project_to_business_cat1")
        let sale2Sets = batch.setsForPath("accounts/\(acct)/transactions/SALE_proj1_project_to_business_cat2")
        #expect(sale1Sets.count == 1)
        #expect(sale2Sets.count == 1)
    }

    @Test("budget category override — items without category use overrideCategoryId")
    func budgetCategoryOverride() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "proj1", budgetCategoryId: nil)

        try await service.sellToBusiness(items: [item], accountId: acct, overrideCategoryId: "catOverride")

        let saleId = "SALE_proj1_project_to_business_catOverride"
        let saleSets = batch.setsForPath("accounts/\(acct)/transactions/\(saleId)")
        #expect(saleSets.count == 1)

        let itemUpdates = batch.updatesForPath("accounts/\(acct)/items/i1")
        #expect(itemUpdates[0].fields["transactionId"] as? String == saleId)
    }

    @Test("fallback to 'uncategorized' when no budgetCategoryId and no override")
    func fallbackToUncategorized() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "proj1", budgetCategoryId: nil)

        try await service.sellToBusiness(items: [item], accountId: acct)

        let saleId = "SALE_proj1_project_to_business_uncategorized"
        #expect(batch.setsForPath("accounts/\(acct)/transactions/\(saleId)").count == 1)
    }

    @Test("userId present — included in lineage edge as createdBy")
    func userIdPresent() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "proj1", budgetCategoryId: "cat1")

        try await service.sellToBusiness(items: [item], accountId: acct, userId: "user1")

        let edges = batch.lineageEdges(accountId: acct, itemId: "i1")
        #expect(edges[0].fields["createdBy"] as? String == "user1")
    }

    @Test("userId nil — omitted from lineage edge")
    func userIdNil() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "proj1", budgetCategoryId: "cat1")

        try await service.sellToBusiness(items: [item], accountId: acct, userId: nil)

        let edges = batch.lineageEdges(accountId: acct, itemId: "i1")
        #expect(edges[0].fields["createdBy"] == nil)
    }

    @Test("item's own budgetCategoryId takes priority over override")
    func ownCategoryPriority() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "proj1", budgetCategoryId: "ownCat")

        try await service.sellToBusiness(items: [item], accountId: acct, overrideCategoryId: "override")

        let ownSets = batch.setsForPath("accounts/\(acct)/transactions/SALE_proj1_project_to_business_ownCat")
        let overrideSets = batch.setsForPath("accounts/\(acct)/transactions/SALE_proj1_project_to_business_override")
        #expect(ownSets.count == 1)
        #expect(overrideSets.isEmpty)
    }

    @Test("multiple items from different projects — separate canonical sales")
    func multipleProjects() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let items = [
            makeItem(id: "i1", projectId: "proj1", budgetCategoryId: "cat1"),
            makeItem(id: "i2", projectId: "proj2", budgetCategoryId: "cat1"),
        ]

        try await service.sellToBusiness(items: items, accountId: acct)

        let proj1Sales = batch.setsForPath("accounts/\(acct)/transactions/SALE_proj1_project_to_business_cat1")
        let proj2Sales = batch.setsForPath("accounts/\(acct)/transactions/SALE_proj2_project_to_business_cat1")
        #expect(proj1Sales.count == 1)
        #expect(proj2Sales.count == 1)
    }
}

// MARK: - sellToProject

@Suite("InventoryOperationsService.sellToProject — execution")
struct SellToProjectExecutionTests {

    private let dstProj = "dstProj"

    @Test("empty items returns immediately without committing")
    func emptyItems() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        try await service.sellToProject(items: [], destinationProjectId: dstProj, accountId: acct)
        #expect(!batch.commitCalled)
    }

    @Test("single item with projectId — two-hop canonical sales")
    func twoHopHappyPath() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(
            id: "i1", projectId: "srcProj", budgetCategoryId: "cat1",
            purchasePriceCents: 3000, transactionId: "oldTx"
        )

        try await service.sellToProject(
            items: [item], destinationProjectId: dstProj, accountId: acct
        )

        #expect(batch.commitCalled)

        // Hop 1: source → business
        let hop1Id = "SALE_srcProj_project_to_business_cat1"
        let hop1Sets = batch.setsForPath("accounts/\(acct)/transactions/\(hop1Id)")
        #expect(hop1Sets.count == 1)
        #expect(hop1Sets[0].fields["projectId"] as? String == "srcProj")
        #expect(hop1Sets[0].fields["inventorySaleDirection"] as? String == "project_to_business")
        #expect(hop1Sets[0].merge == true)

        // Hop 2: business → destination
        let hop2Id = "SALE_\(dstProj)_business_to_project_cat1"
        let hop2Sets = batch.setsForPath("accounts/\(acct)/transactions/\(hop2Id)")
        #expect(hop2Sets.count == 1)
        #expect(hop2Sets[0].fields["projectId"] as? String == dstProj)
        #expect(hop2Sets[0].fields["inventorySaleDirection"] as? String == "business_to_project")

        // Item update
        let itemUpdates = batch.updatesForPath("accounts/\(acct)/items/i1")
        #expect(itemUpdates.count == 1)
        #expect(itemUpdates[0].fields["projectId"] as? String == dstProj)
        #expect(itemUpdates[0].fields["spaceId"] is NSNull)
        #expect(itemUpdates[0].fields["transactionId"] as? String == hop2Id)

        // Source transaction removal
        let srcTxUpdates = batch.updatesForPath("accounts/\(acct)/transactions/oldTx")
        #expect(srcTxUpdates.count == 1)

        // Lineage edge
        let edges = batch.lineageEdges(accountId: acct, itemId: "i1")
        #expect(edges.count == 1)
        #expect(edges[0].fields["movementKind"] as? String == "sold")
        #expect(edges[0].fields["fromProjectId"] as? String == "srcProj")
        #expect(edges[0].fields["toProjectId"] as? String == dstProj)
        #expect(edges[0].fields["fromTransactionId"] as? String == "oldTx")
    }

    @Test("item without projectId — no hop 1, edge omits fromProjectId")
    func noHop1WhenNoProjectId() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: nil, budgetCategoryId: "cat1")

        try await service.sellToProject(
            items: [item], destinationProjectId: dstProj, accountId: acct
        )

        // No hop 1 (project_to_business)
        let hop1Sets = batch.sets.filter {
            ($0.fields["inventorySaleDirection"] as? String) == "project_to_business"
        }
        #expect(hop1Sets.isEmpty)

        // Hop 2 still created
        let hop2Id = "SALE_\(dstProj)_business_to_project_cat1"
        #expect(batch.setsForPath("accounts/\(acct)/transactions/\(hop2Id)").count == 1)

        // Edge omits fromProjectId
        let edges = batch.lineageEdges(accountId: acct, itemId: "i1")
        #expect(edges[0].fields["fromProjectId"] == nil)
    }

    @Test("item without id — skipped entirely")
    func itemWithoutId() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: nil, projectId: "srcProj")

        try await service.sellToProject(
            items: [item], destinationProjectId: dstProj, accountId: acct
        )

        #expect(batch.sets.isEmpty)
        #expect(batch.updates.isEmpty)
        #expect(batch.autoIdSets.isEmpty)
        #expect(batch.commitCalled)
    }

    @Test("source and destination category overrides used for items without budgetCategoryId")
    func categoryOverrides() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "srcProj", budgetCategoryId: nil)

        try await service.sellToProject(
            items: [item], destinationProjectId: dstProj, accountId: acct,
            sourceCategoryId: "srcCat", destinationCategoryId: "dstCat"
        )

        // Hop 1 uses sourceCategoryId
        let hop1Id = "SALE_srcProj_project_to_business_srcCat"
        #expect(batch.setsForPath("accounts/\(acct)/transactions/\(hop1Id)").count == 1)

        // Hop 2 uses destinationCategoryId
        let hop2Id = "SALE_\(dstProj)_business_to_project_dstCat"
        #expect(batch.setsForPath("accounts/\(acct)/transactions/\(hop2Id)").count == 1)
    }

    @Test("item's own budgetCategoryId takes priority over both overrides")
    func ownCategoryPriority() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "srcProj", budgetCategoryId: "ownCat")

        try await service.sellToProject(
            items: [item], destinationProjectId: dstProj, accountId: acct,
            sourceCategoryId: "srcCat", destinationCategoryId: "dstCat"
        )

        let hop1Id = "SALE_srcProj_project_to_business_ownCat"
        let hop2Id = "SALE_\(dstProj)_business_to_project_ownCat"
        #expect(batch.setsForPath("accounts/\(acct)/transactions/\(hop1Id)").count == 1)
        #expect(batch.setsForPath("accounts/\(acct)/transactions/\(hop2Id)").count == 1)
    }

    @Test("fallback to 'uncategorized' when no category and no overrides")
    func fallbackUncategorized() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "srcProj", budgetCategoryId: nil)

        try await service.sellToProject(
            items: [item], destinationProjectId: dstProj, accountId: acct
        )

        let hop1Id = "SALE_srcProj_project_to_business_uncategorized"
        let hop2Id = "SALE_\(dstProj)_business_to_project_uncategorized"
        #expect(batch.setsForPath("accounts/\(acct)/transactions/\(hop1Id)").count == 1)
        #expect(batch.setsForPath("accounts/\(acct)/transactions/\(hop2Id)").count == 1)
    }

    @Test("projectPriceCents backfill — nil projectPriceCents with purchasePriceCents")
    func projectPriceBackfill() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(
            id: "i1", projectId: "srcProj", budgetCategoryId: "cat1",
            purchasePriceCents: 5000, projectPriceCents: nil
        )

        try await service.sellToProject(
            items: [item], destinationProjectId: dstProj, accountId: acct
        )

        let itemUpdates = batch.updatesForPath("accounts/\(acct)/items/i1")
        #expect(itemUpdates[0].fields["projectPriceCents"] as? Int == 5000)
    }

    @Test("projectPriceCents NOT backfilled when already set")
    func projectPriceNotBackfilledWhenSet() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(
            id: "i1", projectId: "srcProj", budgetCategoryId: "cat1",
            purchasePriceCents: 5000, projectPriceCents: 3000
        )

        try await service.sellToProject(
            items: [item], destinationProjectId: dstProj, accountId: acct
        )

        let itemUpdates = batch.updatesForPath("accounts/\(acct)/items/i1")
        #expect(itemUpdates[0].fields["projectPriceCents"] == nil)
    }

    @Test("source transaction removal when transactionId present")
    func sourceTransactionRemoval() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "srcProj", budgetCategoryId: "cat1", transactionId: "oldTx")

        try await service.sellToProject(
            items: [item], destinationProjectId: dstProj, accountId: acct
        )

        let srcUpdates = batch.updatesForPath("accounts/\(acct)/transactions/oldTx")
        #expect(srcUpdates.count == 1)
        #expect(srcUpdates[0].fields.keys.contains("itemIds"))
    }

    @Test("no source transaction removal when transactionId nil")
    func noSourceTransactionRemovalWhenNil() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "srcProj", budgetCategoryId: "cat1", transactionId: nil)

        try await service.sellToProject(
            items: [item], destinationProjectId: dstProj, accountId: acct
        )

        // Only item update, no source transaction update
        let txUpdates = batch.updates.filter { $0.path.contains("/transactions/") }
        #expect(txUpdates.isEmpty)
    }

    @Test("auto-enable budget categories at destination")
    func autoEnableBudgetCategories() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let items = [
            makeItem(id: "i1", projectId: "srcProj", budgetCategoryId: "cat1"),
            makeItem(id: "i2", projectId: "srcProj", budgetCategoryId: "cat2"),
        ]

        try await service.sellToProject(
            items: items, destinationProjectId: dstProj, accountId: acct
        )

        let cat1Sets = batch.setsForPath("accounts/\(acct)/projects/\(dstProj)/budgetCategories/cat1")
        let cat2Sets = batch.setsForPath("accounts/\(acct)/projects/\(dstProj)/budgetCategories/cat2")
        #expect(cat1Sets.count == 1)
        #expect(cat2Sets.count == 1)
        #expect(cat1Sets[0].merge == true)
    }

    @Test("auto-enable skips 'uncategorized'")
    func autoEnableSkipsUncategorized() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "srcProj", budgetCategoryId: nil)

        try await service.sellToProject(
            items: [item], destinationProjectId: dstProj, accountId: acct
        )

        let uncatSets = batch.setsForPath("accounts/\(acct)/projects/\(dstProj)/budgetCategories/uncategorized")
        #expect(uncatSets.isEmpty)
    }

    @Test("auto-enable deduplicates categories across items")
    func autoEnableDeduplicates() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let items = [
            makeItem(id: "i1", projectId: "srcProj", budgetCategoryId: "cat1"),
            makeItem(id: "i2", projectId: "srcProj", budgetCategoryId: "cat1"),
        ]

        try await service.sellToProject(
            items: items, destinationProjectId: dstProj, accountId: acct
        )

        let catSets = batch.setsForPath("accounts/\(acct)/projects/\(dstProj)/budgetCategories/cat1")
        #expect(catSets.count == 1)
    }

    @Test("auto-enable includes userId when present")
    func autoEnableWithUserId() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "srcProj", budgetCategoryId: "cat1")

        try await service.sellToProject(
            items: [item], destinationProjectId: dstProj, accountId: acct, userId: "user1"
        )

        let catSets = batch.setsForPath("accounts/\(acct)/projects/\(dstProj)/budgetCategories/cat1")
        #expect(catSets[0].fields["updatedBy"] as? String == "user1")
    }

    @Test("auto-enable omits userId when nil")
    func autoEnableWithoutUserId() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "srcProj", budgetCategoryId: "cat1")

        try await service.sellToProject(
            items: [item], destinationProjectId: dstProj, accountId: acct, userId: nil
        )

        let catSets = batch.setsForPath("accounts/\(acct)/projects/\(dstProj)/budgetCategories/cat1")
        #expect(catSets[0].fields["updatedBy"] == nil)
    }

    @Test("lineage edge includes fromTransactionId when present")
    func edgeWithFromTransactionId() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "srcProj", budgetCategoryId: "cat1", transactionId: "oldTx")

        try await service.sellToProject(
            items: [item], destinationProjectId: dstProj, accountId: acct
        )

        let edges = batch.lineageEdges(accountId: acct, itemId: "i1")
        #expect(edges[0].fields["fromTransactionId"] as? String == "oldTx")
    }

    @Test("lineage edge omits fromTransactionId when nil")
    func edgeWithoutFromTransactionId() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "srcProj", budgetCategoryId: "cat1", transactionId: nil)

        try await service.sellToProject(
            items: [item], destinationProjectId: dstProj, accountId: acct
        )

        let edges = batch.lineageEdges(accountId: acct, itemId: "i1")
        #expect(edges[0].fields["fromTransactionId"] == nil)
    }

    @Test("userId included in lineage edge when present")
    func edgeWithUserId() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "srcProj", budgetCategoryId: "cat1")

        try await service.sellToProject(
            items: [item], destinationProjectId: dstProj, accountId: acct, userId: "user1"
        )

        let edges = batch.lineageEdges(accountId: acct, itemId: "i1")
        #expect(edges[0].fields["createdBy"] as? String == "user1")
    }
}

// MARK: - reassignToProject

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

    @Test("cross-scope throws — one matching + one mismatched")
    func crossScopeThrowsOneMismatch() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let items = [
            makeItem(id: "i1", projectId: proj),
            makeItem(id: "i2", projectId: "otherProj"),
        ]

        await #expect(throws: InventoryOperationError.self) {
            try await service.reassignToProject(
                items: items, destinationTransactionId: destTx,
                destinationProjectId: proj, accountId: acct
            )
        }
    }

    @Test("cross-scope throws — nil projectId vs non-nil destination")
    func crossScopeThrowsNilProjectId() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: nil)

        await #expect(throws: InventoryOperationError.self) {
            try await service.reassignToProject(
                items: [item], destinationTransactionId: destTx,
                destinationProjectId: proj, accountId: acct
            )
        }
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
        #expect(itemUpdates[0].fields.keys.contains("updatedAt"))

        // Source transaction — remove item
        let srcUpdates = batch.updatesForPath("accounts/\(acct)/transactions/oldTx")
        #expect(srcUpdates.count == 1)
        #expect(srcUpdates[0].fields.keys.contains("itemIds"))

        // Destination transaction — add item
        let dstUpdates = batch.updatesForPath("accounts/\(acct)/transactions/\(destTx)")
        #expect(dstUpdates.count == 1)
        #expect(dstUpdates[0].fields.keys.contains("itemIds"))

        // Lineage edge
        let edges = batch.lineageEdges(accountId: acct, itemId: "i1")
        #expect(edges.count == 1)
        let ef = edges[0].fields
        #expect(ef["movementKind"] as? String == "correction")
        #expect(ef["note"] as? String == "Reassigned to transaction")
        #expect(ef["fromTransactionId"] as? String == "oldTx")
        #expect(ef["toTransactionId"] as? String == destTx)
        #expect(ef["fromProjectId"] as? String == proj)
        #expect(ef["toProjectId"] as? String == proj)
        #expect(ef["source"] as? String == "app")

        // No canonical sales created (correction, not financial)
        #expect(batch.sets.isEmpty)
    }

    @Test("item without transactionId — no source removal, dest add still happens")
    func itemWithoutTransactionId() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: proj, transactionId: nil)

        try await service.reassignToProject(
            items: [item], destinationTransactionId: destTx,
            destinationProjectId: proj, accountId: acct
        )

        // Destination add still happens
        let dstUpdates = batch.updatesForPath("accounts/\(acct)/transactions/\(destTx)")
        #expect(dstUpdates.count == 1)

        // No source transaction update (only item + dest)
        let allTxUpdates = batch.updates.filter { $0.path.contains("/transactions/") }
        #expect(allTxUpdates.count == 1) // Only the destination

        // Edge omits fromTransactionId
        let edges = batch.lineageEdges(accountId: acct, itemId: "i1")
        #expect(edges[0].fields["fromTransactionId"] == nil)
    }

    @Test("item without id — skipped")
    func itemWithoutId() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: nil, projectId: proj)

        try await service.reassignToProject(
            items: [item], destinationTransactionId: destTx,
            destinationProjectId: proj, accountId: acct
        )

        #expect(batch.updates.isEmpty)
        #expect(batch.autoIdSets.isEmpty)
        #expect(batch.commitCalled)
    }

    @Test("projectPriceCents backfill when nil with purchasePriceCents")
    func projectPriceBackfill() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(
            id: "i1", projectId: proj, purchasePriceCents: 5000,
            transactionId: "oldTx", projectPriceCents: nil
        )

        try await service.reassignToProject(
            items: [item], destinationTransactionId: destTx,
            destinationProjectId: proj, accountId: acct
        )

        let itemUpdates = batch.updatesForPath("accounts/\(acct)/items/i1")
        #expect(itemUpdates[0].fields["projectPriceCents"] as? Int == 5000)
    }

    @Test("projectPriceCents NOT backfilled when already set")
    func projectPriceNotBackfilled() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(
            id: "i1", projectId: proj, purchasePriceCents: 5000,
            transactionId: "oldTx", projectPriceCents: 3000
        )

        try await service.reassignToProject(
            items: [item], destinationTransactionId: destTx,
            destinationProjectId: proj, accountId: acct
        )

        let itemUpdates = batch.updatesForPath("accounts/\(acct)/items/i1")
        #expect(itemUpdates[0].fields["projectPriceCents"] == nil)
    }

    @Test("userId present — included in lineage edge")
    func userIdPresent() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: proj)

        try await service.reassignToProject(
            items: [item], destinationTransactionId: destTx,
            destinationProjectId: proj, accountId: acct, userId: "user1"
        )

        let edges = batch.lineageEdges(accountId: acct, itemId: "i1")
        #expect(edges[0].fields["createdBy"] as? String == "user1")
    }

    @Test("userId nil — omitted from lineage edge")
    func userIdNil() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: proj)

        try await service.reassignToProject(
            items: [item], destinationTransactionId: destTx,
            destinationProjectId: proj, accountId: acct, userId: nil
        )

        let edges = batch.lineageEdges(accountId: acct, itemId: "i1")
        #expect(edges[0].fields["createdBy"] == nil)
    }

    @Test("multiple items all within scope — all processed")
    func multipleItemsWithinScope() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let items = [
            makeItem(id: "i1", projectId: proj, transactionId: "tx1"),
            makeItem(id: "i2", projectId: proj, transactionId: "tx2"),
            makeItem(id: "i3", projectId: proj, transactionId: "tx3"),
        ]

        try await service.reassignToProject(
            items: items, destinationTransactionId: destTx,
            destinationProjectId: proj, accountId: acct
        )

        // 3 item updates + 3 source removals + 3 dest adds = 9 updates
        #expect(batch.updatesForPath("accounts/\(acct)/items/i1").count == 1)
        #expect(batch.updatesForPath("accounts/\(acct)/items/i2").count == 1)
        #expect(batch.updatesForPath("accounts/\(acct)/items/i3").count == 1)
        #expect(batch.lineageEdges(accountId: acct).count == 3)
    }
}

// MARK: - reassignToInventory

@Suite("InventoryOperationsService.reassignToInventory — execution")
struct ReassignToInventoryExecutionTests {

    @Test("empty items returns immediately without committing")
    func emptyItems() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        try await service.reassignToInventory(items: [], accountId: acct)
        #expect(!batch.commitCalled)
    }

    @Test("single item happy path — projectId cleared, source updated, correction edge")
    func singleItemHappyPath() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "proj1", transactionId: "oldTx")

        try await service.reassignToInventory(items: [item], accountId: acct)

        #expect(batch.commitCalled)

        // Item update — projectId cleared
        let itemUpdates = batch.updatesForPath("accounts/\(acct)/items/i1")
        #expect(itemUpdates.count == 1)
        #expect(itemUpdates[0].fields["projectId"] is NSNull)
        #expect(itemUpdates[0].fields.keys.contains("updatedAt"))

        // Source transaction removal
        let srcUpdates = batch.updatesForPath("accounts/\(acct)/transactions/oldTx")
        #expect(srcUpdates.count == 1)
        #expect(srcUpdates[0].fields.keys.contains("itemIds"))

        // Lineage edge
        let edges = batch.lineageEdges(accountId: acct, itemId: "i1")
        #expect(edges.count == 1)
        let ef = edges[0].fields
        #expect(ef["movementKind"] as? String == "correction")
        #expect(ef["note"] as? String == "Reassigned to inventory")
        #expect(ef["fromTransactionId"] as? String == "oldTx")
        #expect(ef["fromProjectId"] as? String == "proj1")
        #expect(ef["source"] as? String == "app")

        // No canonical sales (correction, not financial)
        #expect(batch.sets.isEmpty)
    }

    @Test("item without transactionId — no source removal, edge omits fromTransactionId")
    func itemWithoutTransactionId() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "proj1", transactionId: nil)

        try await service.reassignToInventory(items: [item], accountId: acct)

        // No transaction updates
        let txUpdates = batch.updates.filter { $0.path.contains("/transactions/") }
        #expect(txUpdates.isEmpty)

        let edges = batch.lineageEdges(accountId: acct, itemId: "i1")
        #expect(edges[0].fields["fromTransactionId"] == nil)
    }

    @Test("item without projectId — update still happens, edge omits fromProjectId")
    func itemWithoutProjectId() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: nil, transactionId: "oldTx")

        try await service.reassignToInventory(items: [item], accountId: acct)

        // Item still gets updated (projectId set to NSNull)
        let itemUpdates = batch.updatesForPath("accounts/\(acct)/items/i1")
        #expect(itemUpdates.count == 1)
        #expect(itemUpdates[0].fields["projectId"] is NSNull)

        // Edge omits fromProjectId
        let edges = batch.lineageEdges(accountId: acct, itemId: "i1")
        #expect(edges[0].fields["fromProjectId"] == nil)
    }

    @Test("item without id — skipped")
    func itemWithoutId() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: nil, projectId: "proj1")

        try await service.reassignToInventory(items: [item], accountId: acct)

        #expect(batch.updates.isEmpty)
        #expect(batch.autoIdSets.isEmpty)
        #expect(batch.commitCalled)
    }

    @Test("userId present — included in lineage edge")
    func userIdPresent() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "proj1")

        try await service.reassignToInventory(items: [item], accountId: acct, userId: "user1")

        let edges = batch.lineageEdges(accountId: acct, itemId: "i1")
        #expect(edges[0].fields["createdBy"] as? String == "user1")
    }

    @Test("userId nil — omitted from lineage edge")
    func userIdNil() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "proj1")

        try await service.reassignToInventory(items: [item], accountId: acct, userId: nil)

        let edges = batch.lineageEdges(accountId: acct, itemId: "i1")
        #expect(edges[0].fields["createdBy"] == nil)
    }

    @Test("status is NOT changed — item update omits status")
    func statusNotChanged() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "proj1", status: .toPurchase)

        try await service.reassignToInventory(items: [item], accountId: acct)

        let itemUpdates = batch.updatesForPath("accounts/\(acct)/items/i1")
        #expect(itemUpdates[0].fields["status"] == nil)
    }

    @Test("spaceId is NOT cleared — item update omits spaceId")
    func spaceIdNotCleared() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "proj1", spaceId: "space1")

        try await service.reassignToInventory(items: [item], accountId: acct)

        let itemUpdates = batch.updatesForPath("accounts/\(acct)/items/i1")
        #expect(itemUpdates[0].fields["spaceId"] == nil)
    }

    @Test("transactionId is NOT cleared — item update omits transactionId")
    func transactionIdNotCleared() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "proj1", transactionId: "tx1")

        try await service.reassignToInventory(items: [item], accountId: acct)

        let itemUpdates = batch.updatesForPath("accounts/\(acct)/items/i1")
        #expect(itemUpdates[0].fields["transactionId"] == nil)
    }

    @Test("multiple items — all processed with individual edges")
    func multipleItems() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let items = [
            makeItem(id: "i1", projectId: "proj1", transactionId: "tx1"),
            makeItem(id: "i2", projectId: "proj2", transactionId: "tx2"),
            makeItem(id: "i3", projectId: "proj1", transactionId: nil),
        ]

        try await service.reassignToInventory(items: items, accountId: acct)

        #expect(batch.updatesForPath("accounts/\(acct)/items/i1").count == 1)
        #expect(batch.updatesForPath("accounts/\(acct)/items/i2").count == 1)
        #expect(batch.updatesForPath("accounts/\(acct)/items/i3").count == 1)
        #expect(batch.lineageEdges(accountId: acct).count == 3)
        // Only 2 source transaction removals (i3 has no transactionId)
        let txUpdates = batch.updates.filter { $0.path.contains("/transactions/") }
        #expect(txUpdates.count == 2)
    }
}

// MARK: - returnToTransaction

@Suite("InventoryOperationsService.returnToTransaction — execution")
struct ReturnToTransactionExecutionTests {

    private let destTx = "returnTx"

    @Test("empty items returns immediately without committing")
    func emptyItems() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        try await service.returnToTransaction(
            items: [], destinationTransactionId: destTx, accountId: acct
        )
        #expect(!batch.commitCalled)
    }

    @Test("single item happy path — transactionId updated, itemIds moved, returned edge")
    func singleItemHappyPath() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(
            id: "i1", projectId: "proj1",
            purchasePriceCents: 3000, transactionId: "purchaseTx"
        )

        try await service.returnToTransaction(
            items: [item], destinationTransactionId: destTx, accountId: acct
        )

        #expect(batch.commitCalled)

        // Item update — transactionId changed, status set to returned, projectId NOT changed
        let itemUpdates = batch.updatesForPath("accounts/\(acct)/items/i1")
        #expect(itemUpdates.count == 1)
        #expect(itemUpdates[0].fields["transactionId"] as? String == destTx)
        #expect(itemUpdates[0].fields["status"] as? String == "returned")
        #expect(itemUpdates[0].fields["projectId"] == nil) // Not touched
        #expect(itemUpdates[0].fields.keys.contains("updatedAt"))

        // Source transaction — remove item
        let srcUpdates = batch.updatesForPath("accounts/\(acct)/transactions/purchaseTx")
        #expect(srcUpdates.count == 1)
        #expect(srcUpdates[0].fields.keys.contains("itemIds"))

        // Destination transaction — add item
        let dstUpdates = batch.updatesForPath("accounts/\(acct)/transactions/\(destTx)")
        #expect(dstUpdates.count == 1)
        #expect(dstUpdates[0].fields.keys.contains("itemIds"))

        // Lineage edge — movementKind is "returned", not "correction"
        let edges = batch.lineageEdges(accountId: acct, itemId: "i1")
        #expect(edges.count == 1)
        let ef = edges[0].fields
        #expect(ef["movementKind"] as? String == "returned")
        #expect(ef["fromTransactionId"] as? String == "purchaseTx")
        #expect(ef["toTransactionId"] as? String == destTx)
        #expect(ef["fromProjectId"] as? String == "proj1")
        #expect(ef["toProjectId"] as? String == "proj1")
        #expect(ef["source"] as? String == "app")

        // No canonical sales created (return, not financial sale)
        #expect(batch.sets.isEmpty)
    }

    @Test("item without transactionId — no source removal, edge omits fromTransactionId")
    func itemWithoutTransactionId() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "proj1", transactionId: nil)

        try await service.returnToTransaction(
            items: [item], destinationTransactionId: destTx, accountId: acct
        )

        // No source transaction updates (no fromTxId)
        let txUpdates = batch.updates.filter {
            $0.path.contains("/transactions/") && !$0.path.contains(destTx)
        }
        #expect(txUpdates.isEmpty)

        // Destination still gets arrayUnion
        let dstUpdates = batch.updatesForPath("accounts/\(acct)/transactions/\(destTx)")
        #expect(dstUpdates.count == 1)

        // Edge omits fromTransactionId
        let edges = batch.lineageEdges(accountId: acct, itemId: "i1")
        #expect(edges[0].fields["fromTransactionId"] == nil)
        #expect(edges[0].fields["movementKind"] as? String == "returned")
    }

    @Test("item without projectId — edge omits project fields")
    func itemWithoutProjectId() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: nil, transactionId: "oldTx")

        try await service.returnToTransaction(
            items: [item], destinationTransactionId: destTx, accountId: acct
        )

        let edges = batch.lineageEdges(accountId: acct, itemId: "i1")
        #expect(edges[0].fields["fromProjectId"] == nil)
        #expect(edges[0].fields["toProjectId"] == nil)
        #expect(edges[0].fields["movementKind"] as? String == "returned")
    }

    @Test("projectPriceCents backfilled when nil")
    func projectPriceCentsBackfill() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(
            id: "i1", projectId: "proj1",
            purchasePriceCents: 4200, transactionId: "oldTx",
            projectPriceCents: nil
        )

        try await service.returnToTransaction(
            items: [item], destinationTransactionId: destTx, accountId: acct
        )

        let itemUpdates = batch.updatesForPath("accounts/\(acct)/items/i1")
        #expect(itemUpdates[0].fields["projectPriceCents"] as? Int == 4200)
        #expect(itemUpdates[0].fields["status"] as? String == "returned")
    }

    @Test("projectPriceCents NOT overwritten when already set")
    func projectPriceCentsPreserved() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(
            id: "i1", projectId: "proj1",
            purchasePriceCents: 4200, transactionId: "oldTx",
            projectPriceCents: 3500
        )

        try await service.returnToTransaction(
            items: [item], destinationTransactionId: destTx, accountId: acct
        )

        let itemUpdates = batch.updatesForPath("accounts/\(acct)/items/i1")
        #expect(itemUpdates[0].fields["projectPriceCents"] == nil) // Not touched
    }

    @Test("userId present — included in lineage edge")
    func userIdPresent() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: "i1", projectId: "proj1", transactionId: "oldTx")

        try await service.returnToTransaction(
            items: [item], destinationTransactionId: destTx,
            accountId: acct, userId: "user42"
        )

        let edges = batch.lineageEdges(accountId: acct, itemId: "i1")
        #expect(edges[0].fields["createdBy"] as? String == "user42")
    }

    @Test("multiple items — all get edges and itemIds updates")
    func multipleItems() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let items = [
            makeItem(id: "i1", projectId: "proj1", transactionId: "tx1"),
            makeItem(id: "i2", projectId: "proj1", transactionId: "tx2"),
            makeItem(id: "i3", projectId: "proj1", transactionId: nil),
        ]

        try await service.returnToTransaction(
            items: items, destinationTransactionId: destTx, accountId: acct
        )

        // 3 item updates, all with status "returned"
        for itemId in ["i1", "i2", "i3"] {
            let updates = batch.updatesForPath("accounts/\(acct)/items/\(itemId)")
            #expect(updates.count == 1)
            #expect(updates[0].fields["status"] as? String == "returned")
        }

        // 3 lineage edges, all "returned"
        let allEdges = batch.lineageEdges(accountId: acct)
        #expect(allEdges.count == 3)
        #expect(allEdges.allSatisfy { $0.fields["movementKind"] as? String == "returned" })

        // 2 source transaction removals (i3 has no transactionId) + 3 dest additions
        let txUpdates = batch.updates.filter { $0.path.contains("/transactions/") }
        #expect(txUpdates.count == 5)
    }

    @Test("item without id — skipped")
    func itemWithoutId() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let item = makeItem(id: nil, projectId: "proj1")

        try await service.returnToTransaction(
            items: [item], destinationTransactionId: destTx, accountId: acct
        )

        #expect(batch.updates.isEmpty)
        #expect(batch.autoIdSets.isEmpty)
        #expect(batch.commitCalled)
    }
}
