import Foundation
#if canImport(LedgerTargetCore)
import LedgerTargetCore
#endif

/// Pure functions for generating CSV exports of transaction data.
enum TransactionExportCalculations {
    #if canImport(LedgerTargetCore)
    enum TargetFailure: Error, Equatable { case invalidFields }

    // Keep the original choices, but do not default to a field the target
    // explicitly rejects. Unsupported options remain visible and fail honestly.
    static let targetDefaultSelectedIds = Set(ExportFields.all.filter {
        $0.defaultSelected && (try? TransactionExportValues.validate(fieldID: $0.id)) != nil
    }.map(\.id))

    /// Rectangular CSV: one explicitly tagged manifest row, then Transactions in
    /// the captured order. Even an empty/no-match export keeps its provenance.
    /// Field choices never remove the stable row identity or snapshot metadata.
    static func exportTransactionsCSV(snapshot: TransactionExportSnapshot,
                                      selectedFields: [ExportFieldConfig]) throws -> String {
        guard !selectedFields.isEmpty, Set(selectedFields.map(\.id)).count == selectedFields.count else {
            throw TargetFailure.invalidFields
        }
        // Validate all chosen fields even when there are no rows. An empty set
        // must not disguise an unsupported or misspelled field as implemented.
        for field in selectedFields { try TransactionExportValues.validate(fieldID: field.id) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let manifest = try encoder.encode(TargetManifest(snapshot: snapshot, fields: selectedFields.map(\.id)))
        let headers = ["Record Type", "Stable Transaction ID", "Currency"] + selectedFields.map(\.label) + ["Export Manifest JSON"]
        var rows = [["manifest", "", ""] + Array(repeating: "", count: selectedFields.count)
                    + [String(decoding: manifest, as: UTF8.self)]]
        for row in snapshot.rows {
            let cells = try selectedFields.map { field in
                switch try TransactionExportValues.cell(fieldID: field.id, row: row) {
                case .text(let value): return spreadsheetText(value)
                case .money(let value): return formatMinorUnits(value.minorUnits)
                case .boolean(let value): return value ? "true" : "false"
                case .unknown: return ""
                }
            }
            rows.append(["transaction", spreadsheetText(row.transactionId.rawValue), row.amount.currency.rawValue] + cells + [""])
        }
        return exportCSV(rows: rows, headers: headers.map(spreadsheetText)) { $0[$1] }
    }

    private struct TargetManifest: Encodable {
        let schemaVersion = "transaction-export-v1"
        let accountId, projectId, principalId, asOfEpochMilliseconds, sourceVersion, sourceSetHash: String
        let snapshotId, snapshotHash, visibilityScopeId, authorityVersion: String
        let selectedFieldIds: [String]
        let orderedTransactionIds: [String]?
        init(snapshot: TransactionExportSnapshot, fields: [String]) {
            accountId = snapshot.scope.accountId.rawValue; projectId = snapshot.scope.projectId!.rawValue
            principalId = snapshot.principalId.rawValue; asOfEpochMilliseconds = String(snapshot.asOf.rawValue)
            sourceVersion = snapshot.sourceVersion.rawValue; sourceSetHash = snapshot.sourceSetHash.rawValue
            snapshotId = snapshot.reference.snapshotID.rawValue; snapshotHash = snapshot.reference.snapshotHash.rawValue
            visibilityScopeId = snapshot.reference.visibilityScopeID.rawValue
            authorityVersion = snapshot.reference.authorityVersion.rawValue
            selectedFieldIds = fields; orderedTransactionIds = snapshot.orderedTransactionIDs?.map(\.rawValue)
        }
    }
    #endif

    /// Shared serialization for either backend's already-authorized rows.
    /// Column order belongs to the field selector; this function never fetches
    /// data, decides readiness, or changes the caller's row order.
    static func exportCSV<Row>(rows: [Row], headers: [String], value: (Row, Int) -> String) -> String {
        guard !headers.isEmpty else { return "" }
        return ([headers.map(escapeCSV).joined(separator: ",")] + rows.map { row in
            headers.indices.map { escapeCSV(value(row, $0)) }.joined(separator: ",")
        }).joined(separator: "\n")
    }

    /// Exact signed money. No Double conversion, even above 2^53 or at Int64.min.
    static func formatMinorUnits(_ cents: Int64) -> String {
        let magnitude = cents.magnitude
        let fraction = magnitude % 100
        return "\(cents < 0 ? "-" : "")\(magnitude / 100).\(fraction < 10 ? "0" : "")\(fraction)"
    }

    /// Apply only to untrusted text, not typed monetary values. CSV quoting
    /// alone does not prevent spreadsheet formula execution.
    static func spreadsheetText(_ value: String) -> String {
        let significant = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let formula = significant.first.map { "=+-@".contains($0) } ?? false
        let control = value.unicodeScalars.first.map { CharacterSet.controlCharacters.contains($0) } ?? false
        return formula || control ? "'" + value : value
    }

    #if canImport(FirebaseFirestore)

    /// Generates a CSV string using the selected field configuration.
    static func exportTransactionsCSV(
        transactions: [Transaction],
        categories: [BudgetCategory],
        items: [Item],
        selectedFields: [ExportFieldConfig]
    ) -> String {
        exportCSV(rows: transactions, headers: selectedFields.map(\.label)) { transaction, column in
            selectedFields[column].getValue(transaction, categories, items)
        }
    }

    /// Backward-compatible overload using the legacy hardcoded column order.
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

    #endif

    // MARK: - Helpers

    /// Formats amount in cents as a decimal dollar string (e.g., 15099 → "150.99").
    static func formatAmount(_ cents: Int?) -> String {
        guard let cents else { return "0.00" }
        return formatMinorUnits(Int64(cents))
    }

    /// Escapes a CSV field value. Wraps in double quotes if the value contains
    /// a comma, double quote, or newline. Internal double quotes are doubled.
    static func escapeCSV(_ value: String) -> String {
        let needsQuoting = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        if needsQuoting {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    #if canImport(FirebaseFirestore)
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
    #endif
}
