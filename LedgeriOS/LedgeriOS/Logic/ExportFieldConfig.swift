import Foundation

/// Configuration for a single CSV export column.
struct ExportFieldConfig: Identifiable, Sendable {
    let id: String
    let label: String
    let defaultSelected: Bool
    let getValue: @Sendable (Transaction, [BudgetCategory], [Item]) -> String
}

/// All available export fields, ordered to match the web app.
enum ExportFields {

    static let all: [ExportFieldConfig] = [
        ExportFieldConfig(id: "transactionId", label: "Transaction ID", defaultSelected: false) { tx, _, _ in
            tx.id ?? ""
        },
        ExportFieldConfig(id: "transactionDate", label: "Transaction Date", defaultSelected: true) { tx, _, _ in
            tx.transactionDate ?? ""
        },
        ExportFieldConfig(id: "source", label: "Source", defaultSelected: true) { tx, _, _ in
            tx.source ?? ""
        },
        ExportFieldConfig(id: "transactionType", label: "Transaction Type", defaultSelected: true) { tx, _, _ in
            tx.transactionType?.displayLabel ?? ""
        },
        ExportFieldConfig(id: "paymentMethod", label: "Payment Method", defaultSelected: true) { tx, _, _ in
            tx.paymentMethod ?? ""
        },
        ExportFieldConfig(id: "amount", label: "Amount", defaultSelected: true) { tx, _, _ in
            TransactionExportCalculations.formatAmount(tx.amountCents)
        },
        ExportFieldConfig(id: "budgetCategory", label: "Budget Category", defaultSelected: true) { tx, cats, _ in
            cats.first(where: { $0.id == tx.budgetCategoryId })?.name ?? ""
        },
        ExportFieldConfig(id: "categoryId", label: "Category ID", defaultSelected: false) { tx, _, _ in
            tx.budgetCategoryId ?? ""
        },
        ExportFieldConfig(id: "notes", label: "Notes", defaultSelected: true) { tx, _, _ in
            tx.notes ?? ""
        },
        ExportFieldConfig(id: "reimbursementType", label: "Payable", defaultSelected: false) { tx, _, _ in
            tx.reimbursementType ?? ""
        },
        ExportFieldConfig(id: "status", label: "Status", defaultSelected: false) { tx, _, _ in
            tx.status?.displayLabel ?? ""
        },
        ExportFieldConfig(id: "receiptEmailed", label: "Receipt Emailed", defaultSelected: false) { tx, _, _ in
            tx.hasEmailReceipt == true ? "true" : "false"
        },
        ExportFieldConfig(id: "taxRatePct", label: "Tax Rate Pct", defaultSelected: false) { tx, _, _ in
            tx.taxRatePct.map { String($0) } ?? ""
        },
        ExportFieldConfig(id: "subtotal", label: "Subtotal", defaultSelected: false) { tx, _, _ in
            TransactionExportCalculations.formatAmount(tx.subtotalCents)
        },
        ExportFieldConfig(id: "createdAt", label: "Created At", defaultSelected: false) { tx, _, _ in
            tx.createdAt.map { iso8601Formatter.string(from: $0) } ?? ""
        },
        ExportFieldConfig(id: "projectId", label: "Project ID", defaultSelected: false) { tx, _, _ in
            tx.projectId ?? ""
        },
        ExportFieldConfig(id: "receiptImages", label: "Receipt Images", defaultSelected: true) { tx, _, _ in
            (tx.receiptImages ?? []).map(\.url).joined(separator: "; ")
        },
        // Mobile-only fields (not in web app, non-default)
        ExportFieldConfig(id: "purchasedBy", label: "Purchased By", defaultSelected: false) { tx, _, _ in
            tx.purchasedBy ?? ""
        },
        ExportFieldConfig(id: "inventorySaleDirection", label: "Inventory Sale Direction", defaultSelected: false) { tx, _, _ in
            tx.inventorySaleDirection?.rawValue ?? ""
        },
        ExportFieldConfig(id: "itemCategories", label: "Item Categories", defaultSelected: false) { tx, _, items in
            let linked = items.filter { $0.transactionId == tx.id }
            return linked.compactMap(\.budgetCategoryId).joined(separator: "|")
        },
    ]

    static let defaultSelectedIds: Set<String> = Set(all.filter(\.defaultSelected).map(\.id))
}

/// Shared ISO 8601 formatter — created once, not per-row.
private nonisolated(unsafe) let iso8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()
