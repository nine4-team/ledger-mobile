import Foundation

/// One downloaded Expense, not a queued proposal or an Invoice/payment report.
public struct ExpenseExportSnapshot: Equatable, Sendable {
    public let expense: ProjectExpenses.Expense
    public let values: [String]
    public let reference: ProtectedArtifactSnapshotReference
    public static let headers = ["Expense ID", "Account ID", "Project ID", "Revision", "Vendor", "Date",
        "Amount minor units", "Currency", "Budget category ID", "Notes", "Receipt lines", "Receipt lines JSON"]

    public init(expense: ProjectExpenses.Expense) throws {
        self.expense = expense
        let entry = expense.entry
        values = [entry.expenseId.rawValue, entry.accountId.rawValue, entry.projectId.rawValue,
            String(expense.revision), entry.vendor, entry.date, String(entry.finalAmount.minorUnits),
            entry.finalAmount.currency.rawValue, entry.categoryId.rawValue, entry.notes,
            ReceiptLineExport.readable(entry.receiptLines), try ReceiptLineExport.structured(entry.receiptLines)]
        let bytes = try JSONSerialization.data(withJSONObject: values)
        let hash = try ProtectedArtifactSHA256.make(bytes: bytes)
        reference = try .init(snapshotID: .init(validating: String(hash.rawValue.prefix(32))), snapshotHash: hash,
            visibilityScopeID: .make(bytes: JSONSerialization.data(withJSONObject: [entry.accountId.rawValue, entry.projectId.rawValue, entry.expenseId.rawValue])),
            profileVersion: .init(validating: "expense-export-v1"), authorityVersion: .init(validating: "expense-receipt-v1"))
    }
}
