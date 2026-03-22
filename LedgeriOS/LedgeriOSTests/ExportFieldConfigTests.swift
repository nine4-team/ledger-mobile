import Foundation
import Testing
@testable import LedgeriOS

@Suite("Export Field Config Tests")
struct ExportFieldConfigTests {

    // MARK: - Test Helpers

    private func makeTransaction(
        id: String? = "tx1",
        transactionDate: String? = "2024-01-15",
        source: String? = "HomeGoods",
        amountCents: Int? = 15099,
        budgetCategoryId: String? = "cat1",
        transactionType: TransactionType? = .purchase,
        paymentMethod: String? = "credit_card",
        notes: String? = "Test notes",
        reimbursementType: String? = nil,
        status: TransactionStatus? = .completed,
        hasEmailReceipt: Bool? = false,
        taxRatePct: Double? = 8.25,
        subtotalCents: Int? = 13950,
        createdAt: Date? = nil,
        projectId: String? = "proj1",
        purchasedBy: String? = "John",
        inventorySaleDirection: InventorySaleDirection? = nil
    ) -> Transaction {
        var tx = Transaction()
        tx.id = id
        tx.transactionDate = transactionDate
        tx.source = source
        tx.amountCents = amountCents
        tx.budgetCategoryId = budgetCategoryId
        tx.transactionType = transactionType
        tx.paymentMethod = paymentMethod
        tx.notes = notes
        tx.reimbursementType = reimbursementType
        tx.status = status
        tx.hasEmailReceipt = hasEmailReceipt
        tx.taxRatePct = taxRatePct
        tx.subtotalCents = subtotalCents
        tx.createdAt = createdAt
        tx.projectId = projectId
        tx.purchasedBy = purchasedBy
        tx.inventorySaleDirection = inventorySaleDirection
        return tx
    }

    private func makeCategory(id: String = "cat1", name: String = "Furniture") -> BudgetCategory {
        var cat = BudgetCategory()
        cat.id = id
        cat.name = name
        return cat
    }

    private func makeItem(
        id: String? = "item1",
        transactionId: String? = "tx1",
        budgetCategoryId: String? = "cat2"
    ) -> Item {
        var item = Item()
        item.id = id
        item.transactionId = transactionId
        item.budgetCategoryId = budgetCategoryId
        return item
    }

    // MARK: - Field Count & Defaults

    @Test("All fields has expected count")
    func allFieldsCount() {
        #expect(ExportFields.all.count == 20)
    }

    @Test("Default selected fields match expected set")
    func defaultSelectedFields() {
        let expected: Set<String> = [
            "transactionDate", "source", "transactionType", "paymentMethod",
            "amount", "budgetCategory", "notes", "receiptImages"
        ]
        #expect(ExportFields.defaultSelectedIds == expected)
    }

    @Test("Default selected count is 8")
    func defaultSelectedCount() {
        #expect(ExportFields.defaultSelectedIds.count == 8)
    }

    // MARK: - Field Value Extraction

    @Test("transactionId field extracts id")
    func transactionIdField() {
        let field = ExportFields.all.first { $0.id == "transactionId" }!
        let tx = makeTransaction(id: "abc123")
        #expect(field.getValue(tx, [], []) == "abc123")
    }

    @Test("transactionDate field extracts date")
    func transactionDateField() {
        let field = ExportFields.all.first { $0.id == "transactionDate" }!
        let tx = makeTransaction(transactionDate: "2024-03-15")
        #expect(field.getValue(tx, [], []) == "2024-03-15")
    }

    @Test("source field extracts source")
    func sourceField() {
        let field = ExportFields.all.first { $0.id == "source" }!
        let tx = makeTransaction(source: "Target")
        #expect(field.getValue(tx, [], []) == "Target")
    }

    @Test("transactionType field extracts type")
    func transactionTypeField() {
        let field = ExportFields.all.first { $0.id == "transactionType" }!
        let tx = makeTransaction(transactionType: .purchase)
        #expect(field.getValue(tx, [], []) == "Purchase")
    }

    @Test("paymentMethod field extracts payment method")
    func paymentMethodField() {
        let field = ExportFields.all.first { $0.id == "paymentMethod" }!
        let tx = makeTransaction(paymentMethod: "credit_card")
        #expect(field.getValue(tx, [], []) == "credit_card")
    }

    @Test("amount field formats cents to dollars")
    func amountField() {
        let field = ExportFields.all.first { $0.id == "amount" }!
        let tx = makeTransaction(amountCents: 15099)
        #expect(field.getValue(tx, [], []) == "150.99")
    }

    @Test("budgetCategory field looks up category name")
    func budgetCategoryField() {
        let field = ExportFields.all.first { $0.id == "budgetCategory" }!
        let tx = makeTransaction(budgetCategoryId: "cat1")
        let cats = [makeCategory(id: "cat1", name: "Furniture")]
        #expect(field.getValue(tx, cats, []) == "Furniture")
    }

    @Test("budgetCategory field returns empty for unknown category")
    func budgetCategoryFieldUnknown() {
        let field = ExportFields.all.first { $0.id == "budgetCategory" }!
        let tx = makeTransaction(budgetCategoryId: "unknown")
        #expect(field.getValue(tx, [], []) == "")
    }

    @Test("categoryId field extracts raw category ID")
    func categoryIdField() {
        let field = ExportFields.all.first { $0.id == "categoryId" }!
        let tx = makeTransaction(budgetCategoryId: "cat1")
        #expect(field.getValue(tx, [], []) == "cat1")
    }

    @Test("notes field extracts notes")
    func notesField() {
        let field = ExportFields.all.first { $0.id == "notes" }!
        let tx = makeTransaction(notes: "Some notes here")
        #expect(field.getValue(tx, [], []) == "Some notes here")
    }

    @Test("reimbursementType field extracts value")
    func reimbursementTypeField() {
        let field = ExportFields.all.first { $0.id == "reimbursementType" }!
        let tx = makeTransaction(reimbursementType: "full")
        #expect(field.getValue(tx, [], []) == "full")
    }

    @Test("status field extracts status")
    func statusField() {
        let field = ExportFields.all.first { $0.id == "status" }!
        let tx = makeTransaction(status: .completed)
        #expect(field.getValue(tx, [], []) == "Completed")
    }

    @Test("status field returns Canceled for canceled status")
    func statusFieldCanceled() {
        let field = ExportFields.all.first { $0.id == "status" }!
        let tx = makeTransaction(status: .canceled)
        #expect(field.getValue(tx, [], []) == "Canceled")
    }

    @Test("receiptEmailed field returns true/false string")
    func receiptEmailedField() {
        let field = ExportFields.all.first { $0.id == "receiptEmailed" }!
        let txTrue = makeTransaction(hasEmailReceipt: true)
        let txFalse = makeTransaction(hasEmailReceipt: false)
        #expect(field.getValue(txTrue, [], []) == "true")
        #expect(field.getValue(txFalse, [], []) == "false")
    }

    @Test("taxRatePct field extracts tax rate")
    func taxRatePctField() {
        let field = ExportFields.all.first { $0.id == "taxRatePct" }!
        let tx = makeTransaction(taxRatePct: 8.25)
        #expect(field.getValue(tx, [], []) == "8.25")
    }

    @Test("taxRatePct field returns empty for nil")
    func taxRatePctFieldNil() {
        let field = ExportFields.all.first { $0.id == "taxRatePct" }!
        let tx = makeTransaction(taxRatePct: nil)
        #expect(field.getValue(tx, [], []) == "")
    }

    @Test("subtotal field formats cents to dollars")
    func subtotalField() {
        let field = ExportFields.all.first { $0.id == "subtotal" }!
        let tx = makeTransaction(subtotalCents: 13950)
        #expect(field.getValue(tx, [], []) == "139.50")
    }

    @Test("projectId field extracts project ID")
    func projectIdField() {
        let field = ExportFields.all.first { $0.id == "projectId" }!
        let tx = makeTransaction(projectId: "proj1")
        #expect(field.getValue(tx, [], []) == "proj1")
    }

    @Test("receiptImages field joins URLs with semicolon")
    func receiptImagesField() {
        let field = ExportFields.all.first { $0.id == "receiptImages" }!
        var tx = makeTransaction()
        tx.receiptImages = [
            AttachmentRef(url: "https://example.com/img1.jpg"),
            AttachmentRef(url: "https://example.com/img2.jpg"),
        ]
        #expect(field.getValue(tx, [], []) == "https://example.com/img1.jpg; https://example.com/img2.jpg")
    }

    @Test("receiptImages field returns empty for nil")
    func receiptImagesFieldNil() {
        let field = ExportFields.all.first { $0.id == "receiptImages" }!
        let tx = makeTransaction()
        #expect(field.getValue(tx, [], []) == "")
    }

    @Test("purchasedBy field extracts value")
    func purchasedByField() {
        let field = ExportFields.all.first { $0.id == "purchasedBy" }!
        let tx = makeTransaction(purchasedBy: "John")
        #expect(field.getValue(tx, [], []) == "John")
    }

    @Test("inventorySaleDirection field extracts raw value")
    func inventorySaleDirectionField() {
        let field = ExportFields.all.first { $0.id == "inventorySaleDirection" }!
        let tx = makeTransaction(inventorySaleDirection: .businessToProject)
        #expect(field.getValue(tx, [], []) == "business_to_project")
    }

    @Test("itemCategories field returns pipe-separated category IDs from linked items")
    func itemCategoriesField() {
        let field = ExportFields.all.first { $0.id == "itemCategories" }!
        let tx = makeTransaction(id: "tx1")
        let items = [
            makeItem(id: "item1", transactionId: "tx1", budgetCategoryId: "cat2"),
            makeItem(id: "item2", transactionId: "tx1", budgetCategoryId: "cat3"),
        ]
        #expect(field.getValue(tx, [], items) == "cat2|cat3")
    }

    @Test("itemCategories field returns empty when no linked items")
    func itemCategoriesFieldEmpty() {
        let field = ExportFields.all.first { $0.id == "itemCategories" }!
        let tx = makeTransaction(id: "tx1")
        #expect(field.getValue(tx, [], []) == "")
    }

    // MARK: - Nil Field Handling

    @Test("All fields handle nil transaction values gracefully")
    func nilFieldHandling() {
        var tx = Transaction()
        tx.id = nil
        for field in ExportFields.all {
            // Should not crash — all fields return empty string for nil values
            let value = field.getValue(tx, [], [])
            #expect(value is String)
        }
    }

    // MARK: - Configurable CSV Export

    @Test("Configurable export with subset of fields")
    func configurableExportSubset() {
        let fields = ExportFields.all.filter { ["source", "amount"].contains($0.id) }
        let tx = makeTransaction(source: "Target", amountCents: 5000)

        let csv = TransactionExportCalculations.exportTransactionsCSV(
            transactions: [tx],
            categories: [],
            items: [],
            selectedFields: fields
        )

        let lines = csv.components(separatedBy: "\n")
        #expect(lines.count == 2)
        #expect(lines[0] == "Source,Amount")
        #expect(lines[1] == "Target,50.00")
    }

    @Test("Configurable export with empty fields returns empty string")
    func configurableExportEmpty() {
        let csv = TransactionExportCalculations.exportTransactionsCSV(
            transactions: [makeTransaction()],
            categories: [],
            items: [],
            selectedFields: []
        )
        #expect(csv == "")
    }

    @Test("Configurable export escapes CSV values")
    func configurableExportEscaping() {
        let fields = ExportFields.all.filter { $0.id == "notes" }
        let tx = makeTransaction(notes: "Has a comma, in it")

        let csv = TransactionExportCalculations.exportTransactionsCSV(
            transactions: [tx],
            categories: [],
            items: [],
            selectedFields: fields
        )

        let lines = csv.components(separatedBy: "\n")
        #expect(lines[1] == "\"Has a comma, in it\"")
    }
}
