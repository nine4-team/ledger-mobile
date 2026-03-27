import Foundation
import FirebaseFirestore
import Testing
@testable import LedgeriOS

@Suite("Item CRUD — Emulator Integration", .tags(.integration))
struct ItemCRUDIntegrationTests {
    let accountId = FirestoreTestHelper.testAccountId
    var itemsPath: String { FirestoreTestHelper.itemsPath(accountId: accountId) }

    // MARK: - Create & Read Back

    @Test("Create item with all common fields — every field survives round-trip")
    func createFullItem() async throws {
        try await FirestoreTestHelper.signIn()
        let id = UUID().uuidString
        let item = makeItem(
            id: id,
            accountId: accountId,
            projectId: "proj1",
            spaceId: "space1",
            name: "Velvet Sofa",
            description: "Mid-century modern",
            notes: "Client loves green",
            status: .purchased,
            source: "Arhaus",
            sku: "ARH-9901",
            transactionId: "tx1",
            purchasePriceCents: 250000,
            projectPriceCents: 275000,
            marketValueCents: 300000,
            purchasedBy: "user1",
            bookmark: true,
            budgetCategoryId: "catFurnishings",
            quantity: 2,
            taxRatePct: 8.25,
            taxAmountPurchasePriceCents: 20625,
            taxAmountProjectPriceCents: 22688,
            images: [
                AttachmentRef(url: "https://example.com/sofa.jpg", kind: .image, isPrimary: true),
                AttachmentRef(url: "https://example.com/receipt.pdf", kind: .pdf, fileName: "receipt.pdf")
            ],
            createdBy: "user1",
            updatedBy: "user2"
        )

        try FirestoreTestHelper.write(item, toCollection: itemsPath, id: id)
        let readBack: Item? = try await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: id)
        let result = try #require(readBack)

        #expect(result.id == id)
        #expect(result.accountId == accountId)
        #expect(result.projectId == "proj1")
        #expect(result.spaceId == "space1")
        #expect(result.name == "Velvet Sofa")
        #expect(result.description == "Mid-century modern")
        #expect(result.notes == "Client loves green")
        #expect(result.status == .purchased)
        #expect(result.source == "Arhaus")
        #expect(result.sku == "ARH-9901")
        #expect(result.transactionId == "tx1")
        #expect(result.purchasePriceCents == 250000)
        #expect(result.projectPriceCents == 275000)
        #expect(result.marketValueCents == 300000)
        #expect(result.purchasedBy == "user1")
        #expect(result.bookmark == true)
        #expect(result.budgetCategoryId == "catFurnishings")
        #expect(result.quantity == 2)
        #expect(result.taxRatePct == 8.25)
        #expect(result.taxAmountPurchasePriceCents == 20625)
        #expect(result.taxAmountProjectPriceCents == 22688)
        #expect(result.createdBy == "user1")
        #expect(result.updatedBy == "user2")

        // Nested AttachmentRef array
        let images = try #require(result.images)
        #expect(images.count == 2)
        #expect(images[0].url == "https://example.com/sofa.jpg")
        #expect(images[0].kind == .image)
        #expect(images[0].isPrimary == true)
        #expect(images[1].url == "https://example.com/receipt.pdf")
        #expect(images[1].kind == .pdf)
        #expect(images[1].fileName == "receipt.pdf")
    }

    @Test("Create item with only name — all other fields are nil")
    func createMinimalItem() async throws {
        try await FirestoreTestHelper.signIn()
        let id = UUID().uuidString
        let item = makeItem(id: id, name: "Bare Item")

        try FirestoreTestHelper.write(item, toCollection: itemsPath, id: id)
        let result: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: id))

        #expect(result.name == "Bare Item")
        #expect(result.projectId == nil)
        #expect(result.spaceId == nil)
        #expect(result.purchasePriceCents == nil)
        #expect(result.projectPriceCents == nil)
        #expect(result.marketValueCents == nil)
        #expect(result.status == nil)
        #expect(result.bookmark == nil)
        #expect(result.images == nil)
        #expect(result.budgetCategoryId == nil)
        #expect(result.quantity == nil)
        #expect(result.taxRatePct == nil)
    }

    // MARK: - Zero vs Nil Distinction

    @Test("purchasePriceCents: 0 is preserved as 0, not nil")
    func zeroVsNilPrice() async throws {
        try await FirestoreTestHelper.signIn()
        let id = UUID().uuidString
        let item = makeItem(id: id, purchasePriceCents: 0)

        try FirestoreTestHelper.write(item, toCollection: itemsPath, id: id)
        let result: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: id))

        #expect(result.purchasePriceCents == 0)
    }

    @Test("quantity: 0 is preserved as 0, not nil")
    func zeroVsNilQuantity() async throws {
        try await FirestoreTestHelper.signIn()
        let id = UUID().uuidString
        let item = makeItem(id: id, quantity: 0)

        try FirestoreTestHelper.write(item, toCollection: itemsPath, id: id)
        let result: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: id))

        #expect(result.quantity == 0)
    }

    @Test("bookmark: false is preserved as false, not nil")
    func falseVsNilBookmark() async throws {
        try await FirestoreTestHelper.signIn()
        let id = UUID().uuidString
        let item = makeItem(id: id, bookmark: false)

        try FirestoreTestHelper.write(item, toCollection: itemsPath, id: id)
        let result: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: id))

        #expect(result.bookmark == false)
    }

    // MARK: - Update

    @Test("Update single field — untouched fields unchanged")
    func updateSingleField() async throws {
        try await FirestoreTestHelper.signIn()
        let id = UUID().uuidString
        let item = makeItem(id: id, name: "Original", status: .purchased, purchasePriceCents: 10000)

        try FirestoreTestHelper.write(item, toCollection: itemsPath, id: id)

        let docPath = "\(itemsPath)/\(id)"
        try await FirestoreTestHelper.update(documentPath: docPath, fields: ["name": "Updated"])

        let result: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: id))

        #expect(result.name == "Updated")
        #expect(result.purchasePriceCents == 10000) // unchanged
        #expect(result.status == .purchased)        // unchanged
    }

    @Test("Update with NSNull clears field to nil")
    func updateWithNSNull() async throws {
        try await FirestoreTestHelper.signIn()
        let id = UUID().uuidString
        let item = makeItem(id: id, projectId: "proj1", spaceId: "space1")

        try FirestoreTestHelper.write(item, toCollection: itemsPath, id: id)

        let docPath = "\(itemsPath)/\(id)"
        try await FirestoreTestHelper.update(documentPath: docPath, fields: [
            "projectId": NSNull(),
            "spaceId": NSNull()
        ])

        let result: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: id))

        #expect(result.projectId == nil)
        #expect(result.spaceId == nil)
    }

    // MARK: - Delete

    @Test("Delete item — get returns nil")
    func deleteItem() async throws {
        try await FirestoreTestHelper.signIn()
        let id = UUID().uuidString
        let item = makeItem(id: id, name: "To Delete")

        try FirestoreTestHelper.write(item, toCollection: itemsPath, id: id)

        // Verify exists
        let before: Item? = try await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: id)
        #expect(before != nil)

        // Delete
        try await FirestoreTestHelper.delete(documentPath: "\(itemsPath)/\(id)")

        // Verify gone
        let after: Item? = try await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: id)
        #expect(after == nil)
    }

    // MARK: - Tax Fields

    @Test("All tax fields survive round-trip")
    func taxFieldsRoundTrip() async throws {
        try await FirestoreTestHelper.signIn()
        let id = UUID().uuidString
        let item = makeItem(
            id: id,
            purchasePriceCents: 50000,
            taxRatePct: 9.5,
            taxAmountPurchasePriceCents: 4750,
            taxAmountProjectPriceCents: 5225
        )

        try FirestoreTestHelper.write(item, toCollection: itemsPath, id: id)
        let result: Item = try #require(await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: id))

        #expect(result.taxRatePct == 9.5)
        #expect(result.taxAmountPurchasePriceCents == 4750)
        #expect(result.taxAmountProjectPriceCents == 5225)
    }

    // MARK: - Raw Field Verification

    @Test("Firestore document uses correct field names (no CodingKey surprises)")
    func rawFieldNames() async throws {
        try await FirestoreTestHelper.signIn()
        let id = UUID().uuidString
        let item = makeItem(
            id: id,
            name: "Check Fields",
            purchasePriceCents: 100,
            bookmark: true,
            budgetCategoryId: "cat1"
        )

        try FirestoreTestHelper.write(item, toCollection: itemsPath, id: id)
        let raw = try #require(await FirestoreTestHelper.readRaw(documentPath: "\(itemsPath)/\(id)"))

        // Item has no CodingKey remaps — field names should match property names
        #expect(raw["name"] as? String == "Check Fields")
        #expect(raw["purchasePriceCents"] as? Int == 100)
        #expect(raw["bookmark"] as? Bool == true)
        #expect(raw["budgetCategoryId"] as? String == "cat1")
    }

    // MARK: - Atomic Delete (transaction cleanup)

    @Test("Delete item removes its ID from the parent transaction's itemIds")
    func deleteItemRemovesFromTransactionItemIds() async throws {
        try await FirestoreTestHelper.signIn()
        let itemId = UUID().uuidString
        let txId = UUID().uuidString
        let txPath = FirestoreTestHelper.transactionsPath(accountId: accountId)

        // Seed a transaction with the item in its itemIds
        let tx = makeTransaction(id: txId, itemIds: [itemId, "other-item"])
        try FirestoreTestHelper.write(tx, toCollection: txPath, id: txId)

        // Seed the item linked to that transaction
        let item = makeItem(id: itemId, transactionId: txId)
        try FirestoreTestHelper.write(item, toCollection: itemsPath, id: itemId)

        // Delete via ItemsService (atomic batch)
        let service = ItemsService()
        try await service.deleteItem(accountId: accountId, item: item)

        // Item doc is gone
        let deletedItem: Item? = try await FirestoreTestHelper.read(Item.self, fromCollection: itemsPath, id: itemId)
        #expect(deletedItem == nil)

        // Transaction's itemIds no longer contains the deleted item
        let updatedTx: Transaction = try #require(await FirestoreTestHelper.read(Transaction.self, fromCollection: txPath, id: txId))
        #expect(updatedTx.itemIds?.contains(itemId) != true)
        #expect(updatedTx.itemIds?.contains("other-item") == true)
    }
}
