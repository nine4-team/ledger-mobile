import SwiftUI

/// Shared original form shell. Backend adapters own validation and submission;
/// the shell never dismisses a failed or merely in-flight save.
struct ItemDetailsFormPresentation<Content: View>: View {
    var title = "Edit Details"
    var isSaving = false
    var isSaveDisabled = false
    var error: String? = nil
    var hint: String? = nil
    var closeTitle = "Cancel"
    let onSave: () -> Void
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FormSheet(title: title, showDismissButton: !isSaving,
            primaryAction: FormSheetAction(title: "Save Changes", isLoading: isSaving,
                isDisabled: isSaveDisabled || isSaving, action: onSave),
            secondaryAction: FormSheetAction(title: closeTitle, isDisabled: isSaving, action: { dismiss() }),
            actionHint: hint, error: error) {
                VStack(spacing: Spacing.md) { content }
            }
        .interactiveDismissDisabled(isSaving)
    }
}

struct ItemProjectPriceField: View {
    @Binding var text: String
    var isLocked = false
    var body: some View {
        FormField(label: "Project Price", text: $text, placeholder: "0.00")
            .platformKeyboardType(.decimalPad)
            .disabled(isLocked)
            .opacity(isLocked ? 0.55 : 1)
        if isLocked {
            Text("Project price is locked because this item is on a paid invoice.")
                .font(Typography.caption)
                .foregroundStyle(BrandColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#if canImport(FirebaseFirestore)
/// Bottom sheet for editing item fields.
/// Field order (FR-8.1): Name, Source, SKU, Purchase Price, Project Price, Market Value.
struct EditItemDetailsModal: View {
    let item: Item
    let isProjectPriceLocked: Bool
    let onSave: ([String: Any]) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var source: String
    @State private var showVendorPicker = false
    @State private var sku: String
    @State private var purchasePrice: String
    @State private var projectPrice: String
    @State private var marketValue: String

    init(
        item: Item,
        isProjectPriceLocked: Bool = false,
        onSave: @escaping ([String: Any]) -> Void
    ) {
        self.item = item
        self.isProjectPriceLocked = isProjectPriceLocked
        self.onSave = onSave
        _name = State(initialValue: item.displayName)
        _source = State(initialValue: item.source ?? "")
        _sku = State(initialValue: item.sku ?? "")
        _purchasePrice = State(initialValue: item.purchasePriceCents.map { Self.formatCents($0) } ?? "")
        _projectPrice = State(initialValue: item.normalizedProjectPriceCents.map { Self.formatCents($0) } ?? "")
        _marketValue = State(initialValue: item.marketValueCents.map { Self.formatCents($0) } ?? "")
    }

    var body: some View {
        ItemDetailsFormPresentation(onSave: saveChanges) {
                FormField(label: "Name", text: $name, placeholder: "Item name")
                VendorPickerField(value: $source, showPicker: $showVendorPicker)
                FormField(label: "SKU", text: $sku, placeholder: "Barcode or SKU number")
                FormField(label: "Purchase Price", text: $purchasePrice, placeholder: "0.00")
                    .platformKeyboardType(.decimalPad)
                ItemProjectPriceField(text: $projectPrice, isLocked: isProjectPriceLocked)
                FormField(label: "Market Value", text: $marketValue, placeholder: "0.00")
                    .platformKeyboardType(.decimalPad)
        }
        .adaptivePresentation(isPresented: $showVendorPicker, style: .picker) {
            VendorPickerModal(selectedValue: source, onSelect: { source = $0 })
        }
    }

    // MARK: - Actions

    private func saveChanges() {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        var fields: [String: Any] = [
            "name": name.trimmingCharacters(in: .whitespacesAndNewlines),
            "source": trimmedSource,
            "sku": sku.trimmingCharacters(in: .whitespacesAndNewlines),
        ]

        // If the item has never been moved (currentSource still tracks source),
        // cascade the edit to currentSource so search still shows the corrected
        // vendor. Once a scope move has shifted currentSource to an inventory
        // label, editing the original source must not stomp it.
        if item.currentSource == item.source {
            fields["currentSource"] = trimmedSource
        }

        if let cents = parseCents(purchasePrice) {
            fields["purchasePriceCents"] = cents
        } else if purchasePrice.isEmpty {
            fields["purchasePriceCents"] = NSNull()
        }

        if !isProjectPriceLocked {
            if let cents = parseCents(projectPrice) {
                fields["projectPriceCents"] = cents
            } else if projectPrice.isEmpty {
                fields["projectPriceCents"] = NSNull()
            }
        }

        if let cents = parseCents(marketValue) {
            fields["marketValueCents"] = cents
        } else if marketValue.isEmpty {
            fields["marketValueCents"] = NSNull()
        }

        onSave(fields)
        dismiss()
    }

    // MARK: - Helpers

    private static func formatCents(_ cents: Int) -> String {
        String(format: "%.2f", Double(cents) / 100.0)
    }

    private func parseCents(_ text: String) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard let value = Double(cleaned), value >= 0 else { return nil }
        return Int(round(value * 100))
    }
}

#Preview {
    EditItemDetailsModal(item: Item(name: "Test Item", source: "Ross", sku: "123456")) { _ in }
}
#endif
