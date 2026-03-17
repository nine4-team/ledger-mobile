import Foundation
import FirebaseFirestore
import Testing
@testable import LedgeriOS

@Suite("Transaction CRUD — Emulator Integration", .tags(.integration))
struct TransactionCRUDIntegrationTests {
    let accountId = FirestoreTestHelper.testAccountId
    var txPath: String { FirestoreTestHelper.transactionsPath(accountId: accountId) }

    // MARK: - CodingKey Remap Verification (CRITICAL)

    @Test("transactionType stored as 'type' in Firestore (CodingKey remap)")
    func transactionTypeFieldName() async throws {
        try await FirestoreTestHelper.signIn()
        let id = UUID().uuidString
        let tx = makeTransaction(id: id, transactionType: "purchase")

        try FirestoreTestHelper.write(tx, toCollection: txPath, id: id)
        let raw = try #require(await FirestoreTestHelper.readRaw(documentPath: "\(txPath)/\(id)"))

        // Must be stored as "type", not "transactionType"
        #expect(raw["type"] as? String == "purchase")
        #expect(raw["transactionType"] == nil) // this key must NOT exist
    }

    @Test("hasEmailReceipt stored as 'receiptEmailed' in Firestore (CodingKey remap)")
    func hasEmailReceiptFieldName() async throws {
        try await FirestoreTestHelper.signIn()
        let id = UUID().uuidString
        let tx = makeTransaction(id: id, hasEmailReceipt: true)

        try FirestoreTestHelper.write(tx, toCollection: txPath, id: id)
        let raw = try #require(await FirestoreTestHelper.readRaw(documentPath: "\(txPath)/\(id)"))

        // Must be stored as "receiptEmailed", not "hasEmailReceipt"
        #expect(raw["receiptEmailed"] as? Bool == true)
        #expect(raw["hasEmailReceipt"] == nil) // this key must NOT exist
    }

    @Test("CodingKey remaps decode correctly — read document with Firestore field names")
    func codingKeyDecodeFromRawFields() async throws {
        try await FirestoreTestHelper.signIn()
        let id = UUID().uuidString
        // Write raw fields using Firestore names (as the backend would)
        try await FirestoreTestHelper.writeFields([
            "type": "sale",
            "receiptEmailed": false,
            "amountCents": 5000,
            "source": "Amazon"
        ], toDocument: "\(txPath)/\(id)")

        let result: LedgeriOS.Transaction = try #require(await FirestoreTestHelper.read(LedgeriOS.Transaction.self, fromCollection: txPath, id: id))

        #expect(result.transactionType == "sale")
        #expect(result.hasEmailReceipt == false)
        #expect(result.amountCents == 5000)
    }

    // MARK: - Full Round-Trip

    @Test("Create transaction with all fields — every field survives round-trip")
    func createFullTransaction() async throws {
        try await FirestoreTestHelper.signIn()
        let id = UUID().uuidString
        let tx = makeTransaction(
            id: id,
            projectId: "proj1",
            transactionDate: "2026-01-15",
            amountCents: 85000,
            source: "Pottery Barn",
            isCanonicalInventory: false,
            canonicalKind: nil,
            isCanonicalInventorySale: true,
            inventorySaleDirection: .businessToProject,
            itemIds: ["item1", "item2", "item3"],
            status: "complete",
            purchasedBy: "user1",
            reimbursementType: "owed_to_client",
            notes: "Living room furniture",
            transactionType: "purchase",
            isCanceled: false,
            budgetCategoryId: "catFurnishings",
            paymentMethod: "credit_card",
            hasEmailReceipt: true,
            needsReview: false,
            taxRatePct: 8.25,
            subtotalCents: 78500,
            triggerEvent: "manual"
        )

        try FirestoreTestHelper.write(tx, toCollection: txPath, id: id)
        let result: LedgeriOS.Transaction = try #require(await FirestoreTestHelper.read(LedgeriOS.Transaction.self, fromCollection: txPath, id: id))

        #expect(result.id == id)
        #expect(result.projectId == "proj1")
        #expect(result.transactionDate == "2026-01-15")
        #expect(result.amountCents == 85000)
        #expect(result.source == "Pottery Barn")
        #expect(result.isCanonicalInventory == false)
        #expect(result.isCanonicalInventorySale == true)
        #expect(result.inventorySaleDirection == .businessToProject)
        #expect(result.itemIds == ["item1", "item2", "item3"])
        #expect(result.status == "complete")
        #expect(result.purchasedBy == "user1")
        #expect(result.reimbursementType == "owed_to_client")
        #expect(result.notes == "Living room furniture")
        #expect(result.transactionType == "purchase")
        #expect(result.isCanceled == false)
        #expect(result.budgetCategoryId == "catFurnishings")
        #expect(result.paymentMethod == "credit_card")
        #expect(result.hasEmailReceipt == true)
        #expect(result.needsReview == false)
        #expect(result.taxRatePct == 8.25)
        #expect(result.subtotalCents == 78500)
        #expect(result.triggerEvent == "manual")
    }

    @Test("Create transaction with minimal fields — all others nil")
    func createMinimalTransaction() async throws {
        try await FirestoreTestHelper.signIn()
        let id = UUID().uuidString
        let tx = makeTransaction(id: id, source: "Amazon")

        try FirestoreTestHelper.write(tx, toCollection: txPath, id: id)
        let result: LedgeriOS.Transaction = try #require(await FirestoreTestHelper.read(LedgeriOS.Transaction.self, fromCollection: txPath, id: id))

        #expect(result.source == "Amazon")
        #expect(result.amountCents == nil)
        #expect(result.itemIds == nil)
        #expect(result.transactionType == nil)
        #expect(result.isCanceled == nil)
        #expect(result.hasEmailReceipt == nil)
        #expect(result.inventorySaleDirection == nil)
    }

    // MARK: - Bool Optional Distinction

    @Test("isCanceled: false preserved as false, not nil")
    func falseVsNilCanceled() async throws {
        try await FirestoreTestHelper.signIn()
        let id = UUID().uuidString
        let tx = makeTransaction(id: id, isCanceled: false)

        try FirestoreTestHelper.write(tx, toCollection: txPath, id: id)
        let result: LedgeriOS.Transaction = try #require(await FirestoreTestHelper.read(LedgeriOS.Transaction.self, fromCollection: txPath, id: id))

        #expect(result.isCanceled == false)
    }

    // MARK: - itemIds Array Operations

    @Test("arrayUnion adds to itemIds")
    func arrayUnionItemIds() async throws {
        try await FirestoreTestHelper.signIn()
        let id = UUID().uuidString
        let tx = makeTransaction(id: id, itemIds: ["item1", "item2"])

        try FirestoreTestHelper.write(tx, toCollection: txPath, id: id)
        try await FirestoreTestHelper.update(
            documentPath: "\(txPath)/\(id)",
            fields: ["itemIds": FieldValue.arrayUnion(["item3"])]
        )

        let result: LedgeriOS.Transaction = try #require(await FirestoreTestHelper.read(LedgeriOS.Transaction.self, fromCollection: txPath, id: id))
        #expect(result.itemIds == ["item1", "item2", "item3"])
    }

    @Test("arrayRemove removes from itemIds")
    func arrayRemoveItemIds() async throws {
        try await FirestoreTestHelper.signIn()
        let id = UUID().uuidString
        let tx = makeTransaction(id: id, itemIds: ["item1", "item2", "item3"])

        try FirestoreTestHelper.write(tx, toCollection: txPath, id: id)
        try await FirestoreTestHelper.update(
            documentPath: "\(txPath)/\(id)",
            fields: ["itemIds": FieldValue.arrayRemove(["item2"])]
        )

        let result: LedgeriOS.Transaction = try #require(await FirestoreTestHelper.read(LedgeriOS.Transaction.self, fromCollection: txPath, id: id))
        #expect(result.itemIds == ["item1", "item3"])
    }

    // MARK: - Enum Round-Trip

    @Test("InventorySaleDirection enum round-trips through Firestore")
    func saleDirectionRoundTrip() async throws {
        try await FirestoreTestHelper.signIn()
        let id1 = UUID().uuidString
        let id2 = UUID().uuidString

        let tx1 = makeTransaction(id: id1, inventorySaleDirection: .businessToProject)
        let tx2 = makeTransaction(id: id2, inventorySaleDirection: .projectToBusiness)

        try FirestoreTestHelper.write(tx1, toCollection: txPath, id: id1)
        try FirestoreTestHelper.write(tx2, toCollection: txPath, id: id2)

        let result1: LedgeriOS.Transaction = try #require(await FirestoreTestHelper.read(LedgeriOS.Transaction.self, fromCollection: txPath, id: id1))
        let result2: LedgeriOS.Transaction = try #require(await FirestoreTestHelper.read(LedgeriOS.Transaction.self, fromCollection: txPath, id: id2))

        #expect(result1.inventorySaleDirection == .businessToProject)
        #expect(result2.inventorySaleDirection == .projectToBusiness)

        // Verify raw values use snake_case
        let raw1 = try #require(await FirestoreTestHelper.readRaw(documentPath: "\(txPath)/\(id1)"))
        #expect(raw1["inventorySaleDirection"] as? String == "business_to_project")
    }
}
