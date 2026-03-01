import Foundation

/// Pure functions for generating CSV exports of transaction data.
enum TransactionExportCalculations {

    /// Generates a CSV string from transactions with the specified column order.
    ///
    /// Columns: id, date, source, amount, categoryName, budgetCategoryId,
    /// inventorySaleDirection, itemCategories
    static func exportTransactionsCSV(
        transactions: [Transaction],
        categories: [BudgetCategory],
        items: [Item]
    ) -> String {
        let categoryNameById = Dictionary(
            uniqueKeysWithValues: categories.compactMap { cat in
                cat.id.map { ($0, cat.name) }
            }
        )

        let itemsByTransaction = buildItemsByTransaction(items: items)

        var lines: [String] = []
        lines.append("id,date,source,amount,categoryName,budgetCategoryId,inventorySaleDirection,itemCategories")

        for transaction in transactions {
            let id = escapeCSV(transaction.id ?? "")
            let date = escapeCSV(transaction.transactionDate ?? "")
            let source = escapeCSV(transaction.source ?? "")
            let amount = formatAmount(transaction.amountCents)
            let categoryName = escapeCSV(
                categoryNameById[transaction.budgetCategoryId ?? ""] ?? ""
            )
            let budgetCategoryId = escapeCSV(transaction.budgetCategoryId ?? "")
            let saleDirection = escapeCSV(transaction.inventorySaleDirection?.rawValue ?? "")
            let itemCategories = escapeCSV(
                buildItemCategories(
                    transactionId: transaction.id ?? "",
                    itemsByTransaction: itemsByTransaction
                )
            )

            lines.append("\(id),\(date),\(source),\(amount),\(categoryName),\(budgetCategoryId),\(saleDirection),\(itemCategories)")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    /// Formats amount in cents as a decimal dollar string (e.g., 15099 → "150.99").
    static func formatAmount(_ cents: Int?) -> String {
        guard let cents else { return "0.00" }
        let dollars = Double(cents) / 100.0
        return String(format: "%.2f", dollars)
    }

    /// Escapes a CSV field value. Wraps in double quotes if the value contains
    /// a comma, double quote, or newline. Internal double quotes are doubled.
    static func escapeCSV(_ value: String) -> String {
        let needsQuoting = value.contains(",") || value.contains("\"") || value.contains("\n")
        if needsQuoting {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    /// Builds a lookup of transaction ID → items linked to that transaction.
    private static func buildItemsByTransaction(items: [Item]) -> [String: [Item]] {
        var result: [String: [Item]] = [:]
        for item in items {
            if let transactionId = item.transactionId, !transactionId.isEmpty {
                result[transactionId, default: []].append(item)
            }
        }
        return result
    }

    /// Returns pipe-separated list of budget category IDs from items linked to a transaction.
    private static func buildItemCategories(
        transactionId: String,
        itemsByTransaction: [String: [Item]]
    ) -> String {
        guard let linkedItems = itemsByTransaction[transactionId] else { return "" }
        let categoryIds = linkedItems.compactMap { $0.budgetCategoryId }
        return categoryIds.joined(separator: "|")
    }
}
