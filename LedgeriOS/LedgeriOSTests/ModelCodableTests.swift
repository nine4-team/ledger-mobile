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
        item.status = .purchased
        item.source = "Amazon"
        item.currentSource = "1584 Design Inventory"
        item.inventoryEntryTransactionId = "return-1"
        item.inventoryEntryProjectId = "project-1"
        item.inventoryEntryBudgetCategoryId = "furnishings"
        item.inventoryEntryPriceCents = 10_000
        item.inventoryEntryAmountCents = 10_825
        item.bookmark = true
        item.images = [AttachmentRef(url: "https://example.com/img.jpg")]
        item.createdBy = "user123"
        item.createdAt = Date(timeIntervalSince1970: 1_000)
        item.updatedAt = Date(timeIntervalSince1970: 2_000)

        let dict = try encodeToDict(item)

        #expect(dict["name"] as? String == "Test Chair")
        #expect(dict["purchasePriceCents"] as? Int == 15000)
        #expect(dict["status"] as? String == "purchased")
        #expect(dict["source"] as? String == "Amazon")
        #expect(dict["currentSource"] as? String == "1584 Design Inventory")
        #expect(dict["inventoryEntryTransactionId"] as? String == "return-1")
        #expect(dict["inventoryEntryProjectId"] as? String == "project-1")
        #expect(dict["inventoryEntryBudgetCategoryId"] as? String == "furnishings")
        #expect(dict["inventoryEntryPriceCents"] as? Int == 10_000)
        #expect(dict["inventoryEntryAmountCents"] as? Int == 10_825)
        #expect(dict["bookmark"] as? Bool == true)
        #expect(dict["createdBy"] as? String == "user123")
        #expect(dict["createdAt"] != nil)
        #expect(dict["updatedAt"] != nil)

        let images = dict["images"] as? [[String: Any]]
        #expect(images?.count == 1)
        #expect(images?.first?["url"] as? String == "https://example.com/img.jpg")
    }

    @Test("Item with nil optionals omits those keys")
    func itemMinimal() throws {
        let item = Item()
        let dict = try encodeToDict(item)

        #expect(dict["name"] == nil) // name is String?, defaults to nil
        #expect(dict["purchasePriceCents"] == nil)
        #expect(dict["images"] == nil)
    }

    // MARK: - ProtoItem

    @Test("ProtoItem encodes capture fields correctly")
    func protoItemEncoding() throws {
        var protoItem = ProtoItem()
        protoItem.projectId = "project1"
        protoItem.spaceId = "space1"
        protoItem.captureContext = .project
        protoItem.status = .open
        protoItem.assignmentHint = .fromInventory
        protoItem.isFromInventory = true
        protoItem.quantity = 1
        protoItem.notes = "Blue fish with tag"
        protoItem.photos = [
            AttachmentRef(url: "offline://upload-1", isUploading: true),
            AttachmentRef(url: "https://example.com/tag.jpg")
        ]
        protoItem.extracted = ProtoItemExtraction(
            rawText: "SKU 12345",
            skuCandidates: ["12345"],
            confidence: 0.92,
            extractedAt: Date(timeIntervalSince1970: 100)
        )

        let dict = try encodeToDict(protoItem)

        #expect(dict["projectId"] as? String == "project1")
        #expect(dict["spaceId"] as? String == "space1")
        #expect(dict["captureContext"] as? String == "project")
        #expect(dict["status"] as? String == "open")
        #expect(dict["assignmentHint"] as? String == "from_inventory")
        #expect(dict["isFromInventory"] as? Bool == true)
        #expect(dict["sourceHint"] == nil)
        #expect(dict["quantity"] as? Int == 1)
        #expect(dict["notes"] as? String == "Blue fish with tag")

        let photos = dict["photos"] as? [[String: Any]]
        #expect(photos?.count == 2)
        #expect(photos?.first?["url"] as? String == "offline://upload-1")
        #expect(photos?.first?["isUploading"] as? Bool == true)

        let extracted = dict["extracted"] as? [String: Any]
        #expect(extracted?["rawText"] as? String == "SKU 12345")
        #expect(extracted?["skuCandidates"] as? [String] == ["12345"])
    }

    @Test("ProtoItem extraction encodes structured SKU provenance")
    func protoItemExtractionProvenanceEncoding() throws {
        var protoItem = ProtoItem()
        protoItem.extracted = ProtoItemExtraction(
            rawText: "STYLE 220251",
            skuCandidates: ["220251"],
            confidence: 0.99,
            extractedAt: Date(timeIntervalSince1970: 100),
            rawTextByEngine: ["vision": "STYLE 220251"],
            skuEvidence: [ProtoItemSkuEvidence(value: "220251", sourceEngine: "vision", sourceImage: "02.jpg", extractionMethod: "barcodeDerived", confidence: 0.99, department: "35", priceCents: 3999, rejectionReason: nil)],
            rejectedSkuEvidence: [],
            reviewFlags: [],
            engineEvents: ["tag-focused-retry:completed"]
        )

        let dict = try encodeToDict(protoItem)
        let extracted = dict["extracted"] as? [String: Any]
        let evidence = (extracted?["skuEvidence"] as? [[String: Any]])?.first
        #expect(evidence?["sourceImage"] as? String == "02.jpg")
        #expect(evidence?["department"] as? String == "35")
        #expect(extracted?["rawTextByEngine"] as? [String: String] == ["vision": "STYLE 220251"])
    }

    // MARK: - Transaction

    @Test("Transaction encodes all fields correctly")
    func transactionEncoding() throws {
        var tx = Transaction()
        tx.projectId = "proj1"
        tx.amountCents = 5000
        tx.source = "Home Depot"
        tx.transactionType = .purchase
        tx.budgetCategoryId = "cat1"
        tx.itemIds = ["item1", "item2"]
        tx.taxRatePct = 8.25
        tx.subtotalCents = 4620
        tx.discount = Discount(amountCents: 500)
        tx.isCanonicalInventory = false
        tx.inventorySaleDirection = .businessToProject
        tx.purchaseHandling = .inventoryResale
        tx.intendedProjectId = "proj2"
        tx.intendedBudgetCategoryId = "cat2"
        tx.inventoryIntentResolvedAt = Date(timeIntervalSince1970: 3_000)
        tx.settlementInvoiceId = "inv1"
        tx.settlementInvoiceLineIds = ["line1", "line2"]

        let dict = try encodeToDict(tx)

        #expect(dict["projectId"] as? String == "proj1")
        #expect(dict["amountCents"] as? Int == 5000)
        #expect(dict["source"] as? String == "Home Depot")
        #expect(dict["type"] as? String == "purchase") // CodingKey maps transactionType → "type"
        #expect(dict["budgetCategoryId"] as? String == "cat1")
        #expect(dict["itemIds"] as? [String] == ["item1", "item2"])
        #expect(dict["taxRatePct"] as? Double == 8.25)
        #expect(dict["subtotalCents"] as? Int == 4620)
        let discount = dict["discount"] as? [String: Any]
        #expect(discount?["amountCents"] as? Int == 500)
        #expect(dict["inventorySaleDirection"] as? String == "business_to_project")
        #expect(dict["purchaseHandling"] as? String == "inventory_resale")
        #expect(dict["intendedProjectId"] as? String == "proj2")
        #expect(dict["intendedBudgetCategoryId"] as? String == "cat2")
        #expect(dict["inventoryIntentResolvedAt"] != nil)
        #expect(dict["settlementInvoiceId"] as? String == "inv1")
        #expect(dict["settlementInvoiceLineIds"] as? [String] == ["line1", "line2"])
    }

    @Test("Transaction with empty optionals")
    func transactionMinimal() throws {
        let tx = Transaction()
        let dict = try encodeToDict(tx)
        #expect(dict["amountCents"] == nil)
        #expect(dict["itemIds"] == nil)
    }

    @Test("Transaction isComplete: true encodes to dict")
    func transactionIsCompleteEncoding() throws {
        var tx = Transaction()
        tx.isComplete = true
        tx.source = "Amazon"

        let dict = try encodeToDict(tx)
        #expect(dict["isComplete"] as? Bool == true)
    }

    // MARK: - Invoice

    @Test("InvoiceLine encodes manual line fields")
    func invoiceLineManualEncoding() throws {
        let line = InvoiceLine(
            id: "line1",
            sourceType: .manual,
            amountCents: 2_500_00,
            sign: .charge,
            snapshotName: "Design Fee 1 of 3",
            settlementTransactionIds: ["tx1"]
        )

        let dict = try encodeToDict(line)

        #expect(dict["id"] as? String == "line1")
        #expect(dict["sourceType"] as? String == "manual")
        #expect(dict["sourceId"] == nil)
        #expect(dict["amountCents"] as? Int == 2_500_00)
        #expect(dict["sign"] as? Int == 1)
        #expect(dict["snapshotName"] as? String == "Design Fee 1 of 3")
        #expect(dict["settlementTransactionIds"] as? [String] == ["tx1"])
    }

    @Test("InvoiceLine decodes legacy line without id")
    func invoiceLineLegacyDecode() throws {
        let json = """
        {
          "sourceType": "item",
          "sourceId": "item1",
          "amountCents": 1000,
          "sign": 1,
          "snapshotName": "Lamp"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(InvoiceLine.self, from: json)

        #expect(!decoded.id.isEmpty)
        #expect(decoded.sourceType == .item)
        #expect(decoded.sourceId == "item1")
        #expect(decoded.amountCents == 1000)
        #expect(decoded.sign == .charge)
        #expect(decoded.snapshotName == "Lamp")
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
                "cat1": BudgetSummaryCategory(budgetCents: 200000, name: "Furniture"),
                "cat2": BudgetSummaryCategory(budgetCents: 300000, name: "Labor")
            ]
        )

        let dict = try encodeToDict(project)

        #expect(dict["name"] as? String == "Kitchen Remodel")
        #expect(dict["clientName"] as? String == "Jane Doe")
        #expect(dict["description"] as? String == "Full kitchen renovation")

        let summary = dict["budgetSummary"] as? [String: Any]
        #expect(summary?["totalBudgetCents"] as? Int == 500000)

        let cats = summary?["categories"] as? [String: Any]
        #expect(cats?.count == 2)
        #expect((cats?["cat1"] as? [String: Any])?["budgetCents"] as? Int == 200000)
    }

    // MARK: - Space

    @Test("Space with checklists encodes correctly")
    func spaceEncoding() throws {
        var space = Space()
        space.name = "Living Room"
        space.notes = "Main living area"
        space.isComplete = true
        space.images = [AttachmentRef(
            url: "https://example.com/room.jpg",
            checkmarks: [ImageCheckmark(id: "mark1", x: 0.25, y: 0.75, itemId: "item1")]
        )]
        space.checklists = [
            Checklist(id: "cl1", name: "Furniture", items: [
                ChecklistItem(id: "cli1", text: "Sofa", isChecked: true),
                ChecklistItem(id: "cli2", text: "Coffee table", isChecked: false)
            ])
        ]

        let dict = try encodeToDict(space)

        #expect(dict["name"] as? String == "Living Room")
        #expect(dict["isComplete"] as? Bool == true)

        let images = dict["images"] as? [[String: Any]]
        let marks = images?.first?["checkmarks"] as? [[String: Any]]
        #expect(marks?.first?["id"] as? String == "mark1")
        #expect(marks?.first?["itemId"] as? String == "item1")
        #expect(marks?.first?["x"] as? Double == 0.25)
        #expect(marks?.first?["y"] as? Double == 0.75)

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

    @Test("BudgetCategory categoryType resolves itemized behavior")
    func budgetCategoryTypeResolvesItemizedBehavior() {
        var cat = BudgetCategory()
        cat.metadata = BudgetCategoryMetadata(categoryType: .itemized, excludeFromOverallBudget: false)

        #expect(cat.resolvedCategoryType == .itemized)
        #expect(cat.isItemsCategory)
    }

    @Test("BudgetCategory defaults to general when categoryType is missing")
    func budgetCategoryDefaultsToGeneralWhenCategoryTypeMissing() {
        var cat = BudgetCategory()

        #expect(cat.resolvedCategoryType == .general)
        #expect(cat.isItemsCategory == false)
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

    @Test("AttachmentRef checkmark overlays round-trip")
    func attachmentRefCheckmarks() throws {
        let ref = AttachmentRef(
            url: "https://example.com/room.jpg",
            checkmarks: [ImageCheckmark(id: "mark1", x: 0.2, y: 0.8, itemId: "item1")]
        )
        let data = try JSONEncoder().encode(ref)
        let decoded = try JSONDecoder().decode(AttachmentRef.self, from: data)

        #expect(decoded.checkmarks == [ImageCheckmark(id: "mark1", x: 0.2, y: 0.8, itemId: "item1")])
    }

    @Test("AttachmentRef multi-item checkmarks round-trip with a legacy item ID")
    func attachmentRefMultiItemCheckmarks() throws {
        let mark = ImageCheckmark(
            id: "bouquet",
            x: 0.2,
            y: 0.8,
            itemId: "stem1",
            itemIds: ["stem1", "stem2", "stem3"]
        )
        let ref = AttachmentRef(url: "https://example.com/room.jpg", checkmarks: [mark])
        let data = try JSONEncoder().encode(ref)
        let decoded = try JSONDecoder().decode(AttachmentRef.self, from: data)

        #expect(decoded.checkmarks?.first?.linkedItemIds == ["stem1", "stem2", "stem3"])
        let dictionary = ref.firestoreDictionary
        let marks = dictionary["checkmarks"] as? [[String: Any]]
        #expect(marks?.first?["itemId"] as? String == "stem1")
        #expect(marks?.first?["itemIds"] as? [String] == ["stem1", "stem2", "stem3"])
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
