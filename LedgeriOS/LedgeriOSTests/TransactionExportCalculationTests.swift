import Foundation
import Testing
@testable import LedgeriOS

@Suite("Transaction Export Calculation Tests")
struct TransactionExportCalculationTests {

    // MARK: - Test Helpers

    private func makeTransaction(
        id: String? = "tx1",
        transactionDate: String? = "2024-01-15",
        source: String? = "HomeGoods",
        amountCents: Int? = 15099,
        budgetCategoryId: String? = "cat1",
        inventorySaleDirection: InventorySaleDirection? = nil
    ) -> Transaction {
        var tx = Transaction()
        tx.id = id
        tx.transactionDate = transactionDate
        tx.source = source
        tx.amountCents = amountCents
        tx.budgetCategoryId = budgetCategoryId
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

    // MARK: - CSV Export Tests

    @Test("CSV header row has correct columns")
    func csvHeaderRow() {
        let csv = TransactionExportCalculations.exportTransactionsCSV(
            transactions: [],
            categories: [],
            items: []
        )
        let header = csv.components(separatedBy: "\n").first
        #expect(header == "id,date,source,amount,categoryName,budgetCategoryId,inventorySaleDirection,itemCategories")
    }

    @Test("CSV includes transaction data in correct columns")
    func csvTransactionData() {
        let transactions = [makeTransaction()]
        let categories = [makeCategory()]

        let csv = TransactionExportCalculations.exportTransactionsCSV(
            transactions: transactions,
            categories: categories,
            items: []
        )

        let lines = csv.components(separatedBy: "\n")
        #expect(lines.count == 2)

        let dataLine = lines[1]
        let fields = dataLine.components(separatedBy: ",")
        #expect(fields[0] == "tx1")           // id
        #expect(fields[1] == "2024-01-15")    // date
        #expect(fields[2] == "HomeGoods")     // source
        #expect(fields[3] == "150.99")        // amount (cents to dollars)
        #expect(fields[4] == "Furniture")     // categoryName
        #expect(fields[5] == "cat1")          // budgetCategoryId
        #expect(fields[6] == "")              // inventorySaleDirection (nil)
        #expect(fields[7] == "")              // itemCategories (no linked items)
    }

    @Test("CSV formats amount from cents to dollars")
    func amountFormatting() {
        #expect(TransactionExportCalculations.formatAmount(15099) == "150.99")
        #expect(TransactionExportCalculations.formatAmount(0) == "0.00")
        #expect(TransactionExportCalculations.formatAmount(100) == "1.00")
        #expect(TransactionExportCalculations.formatAmount(nil) == "0.00")
        #expect(TransactionExportCalculations.formatAmount(50) == "0.50")
    }

    @Test("CSV escapes commas in field values")
    func escapeCommas() {
        let result = TransactionExportCalculations.escapeCSV("Hello, World")
        #expect(result == "\"Hello, World\"")
    }

    @Test("CSV escapes double quotes in field values")
    func escapeDoubleQuotes() {
        let result = TransactionExportCalculations.escapeCSV("He said \"hi\"")
        #expect(result == "\"He said \"\"hi\"\"\"")
    }

    @Test("CSV does not escape clean values")
    func noEscapeCleanValues() {
        let result = TransactionExportCalculations.escapeCSV("HomeGoods")
        #expect(result == "HomeGoods")
    }

    @Test("CSV includes inventory sale direction when present")
    func inventorySaleDirection() {
        let tx = makeTransaction(inventorySaleDirection: .businessToProject)
        let csv = TransactionExportCalculations.exportTransactionsCSV(
            transactions: [tx],
            categories: [makeCategory()],
            items: []
        )

        let dataLine = csv.components(separatedBy: "\n")[1]
        let fields = dataLine.components(separatedBy: ",")
        #expect(fields[6] == "business_to_project")
    }

    @Test("CSV includes pipe-separated item categories")
    func itemCategories() {
        let items = [
            makeItem(id: "item1", transactionId: "tx1", budgetCategoryId: "cat2"),
            makeItem(id: "item2", transactionId: "tx1", budgetCategoryId: "cat3"),
        ]
        let csv = TransactionExportCalculations.exportTransactionsCSV(
            transactions: [makeTransaction()],
            categories: [makeCategory()],
            items: items
        )

        let dataLine = csv.components(separatedBy: "\n")[1]
        let fields = dataLine.components(separatedBy: ",")
        #expect(fields[7] == "cat2|cat3")
    }

    @Test("CSV handles multiple transactions")
    func multipleTransactions() {
        let transactions = [
            makeTransaction(id: "tx1"),
            makeTransaction(id: "tx2", source: "Target", amountCents: 5000),
        ]
        let csv = TransactionExportCalculations.exportTransactionsCSV(
            transactions: transactions,
            categories: [makeCategory()],
            items: []
        )

        let lines = csv.components(separatedBy: "\n")
        #expect(lines.count == 3) // header + 2 data rows
    }

    @Test("CSV handles missing category name gracefully")
    func missingCategoryName() {
        let tx = makeTransaction(budgetCategoryId: "unknown-cat")
        let csv = TransactionExportCalculations.exportTransactionsCSV(
            transactions: [tx],
            categories: [makeCategory()], // cat1, not unknown-cat
            items: []
        )

        let dataLine = csv.components(separatedBy: "\n")[1]
        let fields = dataLine.components(separatedBy: ",")
        #expect(fields[4] == "") // no category name found
    }

    @Test("CSV handles nil fields gracefully")
    func nilFields() {
        var tx = Transaction()
        tx.id = nil
        tx.transactionDate = nil
        tx.source = nil
        tx.amountCents = nil
        tx.budgetCategoryId = nil

        let csv = TransactionExportCalculations.exportTransactionsCSV(
            transactions: [tx],
            categories: [],
            items: []
        )

        let dataLine = csv.components(separatedBy: "\n")[1]
        let fields = dataLine.components(separatedBy: ",")
        #expect(fields[0] == "")     // id
        #expect(fields[1] == "")     // date
        #expect(fields[2] == "")     // source
        #expect(fields[3] == "0.00") // amount
        #expect(fields[4] == "")     // categoryName
        #expect(fields[5] == "")     // budgetCategoryId
    }
}
