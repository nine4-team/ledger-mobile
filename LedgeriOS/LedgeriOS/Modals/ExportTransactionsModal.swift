import SwiftUI

#if canImport(FirebaseFirestore)
/// Column selector sheet for CSV export. Lets users pick which fields to include.
struct ExportTransactionsModal: View {
    let transactions: [Transaction]
    let categories: [BudgetCategory]
    let items: [Item]
    let projectId: String?
    var onExport: ((URL) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedFieldIds: Set<String> = ExportFields.defaultSelectedIds
    @State private var errorMessage: String?

    private var allFields: [ExportFieldConfig] { ExportFields.all }
    var body: some View {
        ExportTransactionFieldsForm(transactionCount: transactions.count, fields: allFields,
            defaultSelectedIds: ExportFields.defaultSelectedIds, selectedFieldIds: $selectedFieldIds,
            errorMessage: errorMessage, canExport: true, onExport: exportCSV)
    }

    private func exportCSV() {
        let selectedFields = allFields.filter { selectedFieldIds.contains($0.id) }
        let csv = TransactionExportCalculations.exportTransactionsCSV(
            transactions: transactions, categories: categories, items: items, selectedFields: selectedFields)
        let dateStamp = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let fileName = "project-\(projectId ?? "export")-\(dateStamp).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do { try csv.write(to: tempURL, atomically: true, encoding: .utf8) }
        catch { errorMessage = "Failed to export transactions."; return }
        onExport?(tempURL)
        dismiss()
    }
}
#endif

/// The original sheet body, with backend-bound rows and file delivery removed.
/// Both callers keep the same selection controls, defaults and form layout.
struct ExportTransactionFieldsForm: View {
    let transactionCount: Int?
    let fields: [ExportFieldConfig]
    let defaultSelectedIds: Set<String>
    @Binding var selectedFieldIds: Set<String>
    let errorMessage: String?
    let canExport: Bool
    let onExport: () -> Void
    @Environment(\.dismiss) private var dismiss
    private var isAllSelected: Bool { selectedFieldIds == Set(fields.map(\.id)) }

    var body: some View {
        FormSheet(
            title: "Export Transactions",
            description: transactionCount.map { "\($0) transaction\($0 == 1 ? "" : "s") will be exported" }
                ?? "Transaction data is not ready to export.",
            primaryAction: FormSheetAction(
                title: "Export",
                isDisabled: selectedFieldIds.isEmpty || !canExport,
                action: onExport
            ),
            secondaryAction: FormSheetAction(
                title: "Cancel",
                action: { dismiss() }
            ),
            error: errorMessage
        ) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Select All / Reset to Default toggle
                HStack {
                    Text("Select Fields")
                        .font(Typography.label)
                        .foregroundStyle(BrandColors.textSecondary)
                    Spacer()
                    Button(isAllSelected ? "Reset to Default" : "Select All") {
                        if isAllSelected {
                            selectedFieldIds = defaultSelectedIds
                        } else {
                            selectedFieldIds = Set(fields.map(\.id))
                        }
                    }
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.primary)
                }

                // Field checkboxes
                VStack(spacing: Spacing.sm) {
                    ForEach(fields) { field in
                        Button {
                            toggleField(field.id)
                        } label: {
                            HStack(spacing: Spacing.md) {
                                Image(systemName: selectedFieldIds.contains(field.id)
                                    ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(selectedFieldIds.contains(field.id)
                                        ? BrandColors.primary : BrandColors.textTertiary)
                                Text(field.label)
                                    .font(Typography.body)
                                    .foregroundStyle(BrandColors.textPrimary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("transaction-export-field-\(field.id)")
                        .accessibilityValue(selectedFieldIds.contains(field.id) ? "Selected" : "Not selected")
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func toggleField(_ id: String) {
        if selectedFieldIds.contains(id) {
            selectedFieldIds.remove(id)
        } else {
            selectedFieldIds.insert(id)
        }
    }

}
