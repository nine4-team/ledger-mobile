import Foundation

/// Shared field-selector metadata; no backend models are needed for a checkbox.
struct ExportFieldConfig: Identifiable, Sendable {
    let id: String
    let label: String
    let defaultSelected: Bool
}

/// All available export fields, ordered to match the web app.
enum ExportFields {

    static let all: [ExportFieldConfig] = [
        .init(id: "transactionId", label: "Transaction ID", defaultSelected: false),
        .init(id: "transactionDate", label: "Transaction Date", defaultSelected: true),
        .init(id: "source", label: "Source", defaultSelected: true),
        .init(id: "transactionType", label: "Transaction Type", defaultSelected: true),
        .init(id: "paymentMethod", label: "Payment Method", defaultSelected: true),
        .init(id: "amount", label: "Amount", defaultSelected: true),
        .init(id: "budgetCategory", label: "Budget Category", defaultSelected: true),
        .init(id: "categoryId", label: "Category ID", defaultSelected: false),
        .init(id: "notes", label: "Notes", defaultSelected: true),
        .init(id: "reimbursementType", label: "Payable", defaultSelected: false),
        .init(id: "status", label: "Status", defaultSelected: false),
        .init(id: "receiptEmailed", label: "Receipt Emailed", defaultSelected: false),
        .init(id: "taxRatePct", label: "Tax Rate Pct", defaultSelected: false),
        .init(id: "subtotal", label: "Subtotal", defaultSelected: false),
        .init(id: "createdAt", label: "Created At", defaultSelected: false),
        .init(id: "projectId", label: "Project ID", defaultSelected: false),
        .init(id: "receiptImages", label: "Receipt Images", defaultSelected: true),
        // Mobile-only fields (not in web app, non-default)
        .init(id: "purchasedBy", label: "Purchased By", defaultSelected: false),
        .init(id: "inventorySaleDirection", label: "Inventory Sale Direction", defaultSelected: false),
        .init(id: "itemCategories", label: "Item Categories", defaultSelected: false),
    ]

    static let defaultSelectedIds: Set<String> = Set(all.filter(\.defaultSelected).map(\.id))
}

#if canImport(FirebaseFirestore)
// Original-model compatibility only, excluded from the target. Existing callers
// retain their values; target field extraction uses TransactionExportValues.
extension ExportFieldConfig {
    func getValue(_ tx: Transaction, _ categories: [BudgetCategory], _ items: [Item]) -> String {
        switch id {
        case "transactionId": return tx.id ?? ""
        case "transactionDate": return tx.transactionDate ?? ""
        case "source": return tx.source ?? ""
        case "transactionType": return tx.transactionType?.displayLabel ?? ""
        case "paymentMethod": return tx.paymentMethod ?? ""
        case "amount": return TransactionExportCalculations.formatAmount(tx.amountCents)
        case "budgetCategory": return categories.first(where: { $0.id == tx.budgetCategoryId })?.name ?? ""
        case "categoryId": return tx.budgetCategoryId ?? ""
        case "notes": return tx.notes ?? ""
        case "reimbursementType": return tx.reimbursementType ?? ""
        case "status": return tx.status?.displayLabel ?? ""
        case "receiptEmailed": return tx.hasEmailReceipt == true ? "true" : "false"
        case "taxRatePct": return tx.taxRatePct.map { String($0) } ?? ""
        case "subtotal": return TransactionExportCalculations.formatAmount(tx.subtotalCents)
        case "createdAt": return tx.createdAt.map { iso8601Formatter.string(from: $0) } ?? ""
        case "projectId": return tx.projectId ?? ""
        case "receiptImages": return (tx.receiptImages ?? []).map(\.url).joined(separator: "; ")
        case "purchasedBy": return tx.purchasedBy ?? ""
        case "inventorySaleDirection": return tx.inventorySaleDirection?.rawValue ?? ""
        case "itemCategories": return items.filter { $0.transactionId == tx.id }.compactMap(\.budgetCategoryId).joined(separator: "|")
        default: return ""
        }
    }
}

/// Shared ISO 8601 formatter — created once, not per-row.
private nonisolated(unsafe) let iso8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()
#endif
