import Foundation
import Testing
import FirebaseFirestore
@testable import LedgeriOS

/// Round-trip tests for all Firestore models.
///
/// @DocumentID and @ServerTimestamp require a real Firestore document context
/// for decoding. For unit tests, we use Firestore.Encoder to produce a dict,
/// then verify the dict contains the expected keys and values. This tests
/// that all properties are correctly included in Codable synthesis.
///
/// Shared types without Firebase wrappers (AttachmentRef, enums) use standard
/// JSONEncoder/JSONDecoder for full round-trip testing.
@Suite("Model Codable Round-Trip Tests")
struct ModelCodableTests {

    // MARK: - Helper

    /// Encodes a Codable to [String: Any] via Firestore.Encoder,
    /// then verifies specific field values.
    private func encodeToDict<T: Encodable>(_ value: T) throws -> [String: Any] {
        try Firestore.Encoder().encode(value)
    }

    // MARK: - Item

    @Test("Item encodes all fields correctly")
    func itemEncoding() throws {
        var item = Item()
        item.name = "Test Chair"
        item.purchasePriceCents = 15000
        item.status = "purchased"
        item.source = "Amazon"
        item.bookmark = true
        item.images = [AttachmentRef(url: "https://example.com/img.jpg")]
        item.createdBy = "user123"

        let dict = try encodeToDict(item)

        #expect(dict["name"] as? String == "Test Chair")
        #expect(dict["purchasePriceCents"] as? Int == 15000)
        #expect(dict["status"] as? String == "purchased")
        #expect(dict["source"] as? String == "Amazon")
        #expect(dict["bookmark"] as? Bool == true)
        #expect(dict["createdBy"] as? String == "user123")

        let images = dict["images"] as? [[String: Any]]
        #expect(images?.count == 1)
        #expect(images?.first?["url"] as? String == "https://example.com/img.jpg")
    }

    @Test("Item with nil optionals omits those keys")
    func itemMinimal() throws {
        let item = Item()
        let dict = try encodeToDict(item)

        #expect(dict["name"] as? String == "")
        #expect(dict["purchasePriceCents"] == nil)
        #expect(dict["images"] == nil)
    }

    // MARK: - Transaction

    @Test("Transaction encodes all fields correctly")
    func transactionEncoding() throws {
        var tx = Transaction()
        tx.projectId = "proj1"
        tx.amountCents = 5000
        tx.source = "Home Depot"
        tx.transactionType = "purchase"
        tx.isCanceled = false
        tx.budgetCategoryId = "cat1"
        tx.itemIds = ["item1", "item2"]
        tx.taxRatePct = 8.25
        tx.subtotalCents = 4620
        tx.isCanonicalInventory = false
        tx.inventorySaleDirection = .businessToProject

        let dict = try encodeToDict(tx)

        #expect(dict["projectId"] as? String == "proj1")
        #expect(dict["amountCents"] as? Int == 5000)
        #expect(dict["source"] as? String == "Home Depot")
        #expect(dict["transactionType"] as? String == "purchase")
        #expect(dict["isCanceled"] as? Bool == false)
        #expect(dict["budgetCategoryId"] as? String == "cat1")
        #expect(dict["itemIds"] as? [String] == ["item1", "item2"])
        #expect(dict["taxRatePct"] as? Double == 8.25)
        #expect(dict["subtotalCents"] as? Int == 4620)
        #expect(dict["inventorySaleDirection"] as? String == "business_to_project")
    }

    @Test("Transaction with empty optionals")
    func transactionMinimal() throws {
        let tx = Transaction()
        let dict = try encodeToDict(tx)
        #expect(dict["amountCents"] == nil)
        #expect(dict["itemIds"] == nil)
    }

    // MARK: - Project

    @Test("Project with budget summary encodes correctly")
    func projectEncoding() throws {
        var project = Project()
        project.name = "Kitchen Remodel"
        project.clientName = "Jane Doe"
        project.description = "Full kitchen renovation"
        project.isArchived = false
        project.budgetSummary = ProjectBudgetSummary(
            totalBudgetCents: 500000,
            categories: [
                BudgetSummaryCategory(budgetCategoryId: "cat1", budgetCents: 200000),
                BudgetSummaryCategory(budgetCategoryId: "cat2", budgetCents: 300000)
            ]
        )

        let dict = try encodeToDict(project)

        #expect(dict["name"] as? String == "Kitchen Remodel")
        #expect(dict["clientName"] as? String == "Jane Doe")
        #expect(dict["description"] as? String == "Full kitchen renovation")

        let summary = dict["budgetSummary"] as? [String: Any]
        #expect(summary?["totalBudgetCents"] as? Int == 500000)

        let cats = summary?["categories"] as? [[String: Any]]
        #expect(cats?.count == 2)
        #expect(cats?.first?["budgetCents"] as? Int == 200000)
    }

    // MARK: - Space

    @Test("Space with checklists encodes correctly")
    func spaceEncoding() throws {
        var space = Space()
        space.name = "Living Room"
        space.notes = "Main living area"
        space.checklists = [
            Checklist(id: "cl1", name: "Furniture", items: [
                ChecklistItem(id: "cli1", text: "Sofa", isChecked: true),
                ChecklistItem(id: "cli2", text: "Coffee table", isChecked: false)
            ])
        ]

        let dict = try encodeToDict(space)

        #expect(dict["name"] as? String == "Living Room")

        let checklists = dict["checklists"] as? [[String: Any]]
        #expect(checklists?.count == 1)

        let items = checklists?.first?["items"] as? [[String: Any]]
        #expect(items?.count == 2)
        #expect(items?.first?["text"] as? String == "Sofa")
        #expect(items?.first?["isChecked"] as? Bool == true)
    }

    // MARK: - BudgetCategory

    @Test("BudgetCategory with metadata encodes correctly")
    func budgetCategoryEncoding() throws {
        var cat = BudgetCategory()
        cat.name = "Furniture"
        cat.slug = "furniture"
        cat.order = 1
        cat.metadata = BudgetCategoryMetadata(
            categoryType: .itemized,
            excludeFromOverallBudget: false
        )

        let dict = try encodeToDict(cat)

        #expect(dict["name"] as? String == "Furniture")
        #expect(dict["slug"] as? String == "furniture")
        #expect(dict["order"] as? Int == 1)

        let meta = dict["metadata"] as? [String: Any]
        #expect(meta?["categoryType"] as? String == "itemized")
        #expect(meta?["excludeFromOverallBudget"] as? Bool == false)
    }

    // MARK: - AttachmentRef (JSON round-trip — no Firebase wrappers)

    @Test("AttachmentRef defaults to image kind")
    func attachmentRefDefault() throws {
        let ref = AttachmentRef(url: "https://example.com/photo.jpg")
        let data = try JSONEncoder().encode(ref)
        let decoded = try JSONDecoder().decode(AttachmentRef.self, from: data)

        #expect(decoded.kind == .image)
        #expect(decoded.url == "https://example.com/photo.jpg")
    }

    @Test("AttachmentRef with PDF kind round-trips")
    func attachmentRefPdf() throws {
        let ref = AttachmentRef(
            url: "https://example.com/receipt.pdf",
            kind: .pdf,
            fileName: "receipt.pdf",
            contentType: "application/pdf"
        )
        let data = try JSONEncoder().encode(ref)
        let decoded = try JSONDecoder().decode(AttachmentRef.self, from: data)

        #expect(decoded.kind == .pdf)
        #expect(decoded.fileName == "receipt.pdf")
    }

    // MARK: - Enums (JSON round-trip — no Firebase wrappers)

    @Test("InventorySaleDirection uses snake_case raw values")
    func inventorySaleDirectionEncoding() throws {
        let direction = InventorySaleDirection.businessToProject
        let data = try JSONEncoder().encode(direction)
        let json = String(data: data, encoding: .utf8)

        #expect(json == "\"business_to_project\"")
    }

    @Test("BudgetCategoryType round-trips all cases")
    func budgetCategoryTypeRoundTrip() throws {
        for caseValue in [BudgetCategoryType.general, .itemized, .fee] {
            let data = try JSONEncoder().encode(caseValue)
            let decoded = try JSONDecoder().decode(BudgetCategoryType.self, from: data)
            #expect(decoded == caseValue)
        }
    }

    @Test("MemberRole round-trips all cases")
    func memberRoleRoundTrip() throws {
        for caseValue in [MemberRole.owner, .admin, .user] {
            let data = try JSONEncoder().encode(caseValue)
            let decoded = try JSONDecoder().decode(MemberRole.self, from: data)
            #expect(decoded == caseValue)
        }
    }

    // MARK: - Account

    @Test("Account encodes correctly")
    func accountEncoding() throws {
        var account = Account()
        account.name = "My Business"
        account.ownerUid = "uid123"

        let dict = try encodeToDict(account)

        #expect(dict["name"] as? String == "My Business")
        #expect(dict["ownerUid"] as? String == "uid123")
    }

    // MARK: - AccountMember

    @Test("AccountMember encodes correctly")
    func accountMemberEncoding() throws {
        var member = AccountMember()
        member.uid = "uid123"
        member.role = .admin
        member.email = "test@example.com"
        member.name = "Test User"

        let dict = try encodeToDict(member)

        #expect(dict["role"] as? String == "admin")
        #expect(dict["email"] as? String == "test@example.com")
        #expect(dict["name"] as? String == "Test User")
    }

    // MARK: - ProjectBudgetCategory

    @Test("ProjectBudgetCategory encodes correctly")
    func projectBudgetCategoryEncoding() throws {
        var pbc = ProjectBudgetCategory()
        pbc.budgetCents = 100000
        pbc.createdBy = "user1"
        pbc.updatedBy = "user2"

        let dict = try encodeToDict(pbc)

        #expect(dict["budgetCents"] as? Int == 100000)
        #expect(dict["createdBy"] as? String == "user1")
        #expect(dict["updatedBy"] as? String == "user2")
    }
}
