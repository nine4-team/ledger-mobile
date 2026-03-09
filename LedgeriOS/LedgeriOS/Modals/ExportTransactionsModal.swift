import SwiftUI

/// Column selector sheet for CSV export. Lets users pick which fields to include.
struct ExportTransactionsModal: View {
    let transactions: [Transaction]
    let categories: [BudgetCategory]
    let items: [Item]
    let projectId: String?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedFieldIds: Set<String> = ExportFields.defaultSelectedIds
    @State private var errorMessage: String?

    private var allFields: [ExportFieldConfig] { ExportFields.all }
    private var isAllSelected: Bool { selectedFieldIds.count == allFields.count }

    var body: some View {
        FormSheet(
            title: "Export Transactions",
            description: "\(transactions.count) transaction\(transactions.count == 1 ? "" : "s") will be exported",
            primaryAction: FormSheetAction(
                title: "Export",
                isDisabled: selectedFieldIds.isEmpty,
                action: { exportCSV() }
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
                            selectedFieldIds = ExportFields.defaultSelectedIds
                        } else {
                            selectedFieldIds = Set(allFields.map(\.id))
                        }
                    }
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.primary)
                }

                // Field checkboxes
                VStack(spacing: Spacing.sm) {
                    ForEach(allFields) { field in
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

    private func exportCSV() {
        let selectedFields = allFields.filter { selectedFieldIds.contains($0.id) }
        let csv = TransactionExportCalculations.exportTransactionsCSV(
            transactions: transactions,
            categories: categories,
            items: items,
            selectedFields: selectedFields
        )

        let dateStamp = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let fileName = "project-\(projectId ?? "export")-\(dateStamp).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "Failed to export transactions."
            return
        }

        #if canImport(UIKit)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = scene.windows.first?.rootViewController else { return }

        // Dismiss the modal first, then present share sheet
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
            rootVC.present(activityVC, animated: true)
        }
        #elseif canImport(AppKit)
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = fileName
        savePanel.begin { response in
            guard response == .OK, let destinationURL = savePanel.url else { return }
            try? FileManager.default.copyItem(at: tempURL, to: destinationURL)
        }
        dismiss()
        #endif
    }
}
