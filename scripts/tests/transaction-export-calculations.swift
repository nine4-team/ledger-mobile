import Foundation

/// Compile with the original shared source, without any Firebase dependency.
@main struct TransactionExportCalculationChecks {
    static func main() {
        precondition(ExportFields.all.map(\.id) == ["transactionId", "transactionDate", "source",
            "transactionType", "paymentMethod", "amount", "budgetCategory", "categoryId", "notes",
            "reimbursementType", "status", "receiptEmailed", "taxRatePct", "subtotal", "createdAt",
            "projectId", "receiptImages", "purchasedBy", "inventorySaleDirection", "itemCategories"])
        precondition(ExportFields.defaultSelectedIds == Set(["transactionDate", "source", "transactionType",
            "paymentMethod", "amount", "budgetCategory", "notes", "receiptImages"]))
        precondition(ExportFields.all.map(\.label) == ["Transaction ID", "Transaction Date", "Source",
            "Transaction Type", "Payment Method", "Amount", "Budget Category", "Category ID", "Notes",
            "Payable", "Status", "Receipt Emailed", "Tax Rate Pct", "Subtotal", "Created At", "Project ID",
            "Receipt Images", "Purchased By", "Inventory Sale Direction", "Item Categories"])
        let money: [(Int64, String)] = [
            (0, "0.00"), (1, "0.01"), (-1, "-0.01"), (15099, "150.99"),
            (9_007_199_254_740_993, "90071992547409.93"),
            (.max, "92233720368547758.07"), (.min, "-92233720368547758.08")
        ]
        for (value, expected) in money {
            precondition(TransactionExportCalculations.formatMinorUnits(value) == expected)
        }
        precondition(TransactionExportCalculations.formatAmount(nil) == "0.00") // Legacy overload only.
        let rows = [["second", "=SUM(A1:A2)", "He said \"hi\"\rnext"], ["first", "", "a,b"]]
        let csv = TransactionExportCalculations.exportCSV(rows: rows, headers: ["ID", "Source", "Notes"]) {
            TransactionExportCalculations.spreadsheetText($0[$1])
        }
        precondition(csv == "ID,Source,Notes\nsecond,'=SUM(A1:A2),\"He said \"\"hi\"\"\rnext\"\nfirst,,\"a,b\"")
        precondition(TransactionExportCalculations.exportCSV(rows: rows, headers: []) { $0[$1] }.isEmpty)
        precondition(TransactionExportCalculations.exportCSV(rows: [[String]](), headers: ["ID"]) { $0[$1] } == "ID")
        for text in ["=1", "+1", "-1", "@formula", "  =1", "\tdata", "\rdata"] {
            precondition(TransactionExportCalculations.spreadsheetText(text) == "'" + text)
        }
        precondition(TransactionExportCalculations.spreadsheetText("Plain text") == "Plain text")
        print("PASS: shared CSV row/column order, quoting, missing cells, formula-safe text and exact Int64 money")
    }
}
