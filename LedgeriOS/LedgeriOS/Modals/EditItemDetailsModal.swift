import SwiftUI

/// Bottom sheet for editing item fields.
/// Field order (FR-8.1): Name, Source, SKU, Purchase Price, Project Price, Market Value.
struct EditItemDetailsModal: View {
    let item: Item
    let onSave: ([String: Any]) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var source: String
    @State private var sku: String
    @State private var purchasePrice: String
    @State private var projectPrice: String
    @State private var marketValue: String

    init(item: Item, onSave: @escaping ([String: Any]) -> Void) {
        self.item = item
        self.onSave = onSave
        _name = State(initialValue: item.name)
        _source = State(initialValue: item.source ?? "")
        _sku = State(initialValue: item.sku ?? "")
        _purchasePrice = State(initialValue: item.purchasePriceCents.map { Self.formatCents($0) } ?? "")
        _projectPrice = State(initialValue: item.projectPriceCents.map { Self.formatCents($0) } ?? "")
        _marketValue = State(initialValue: item.marketValueCents.map { Self.formatCents($0) } ?? "")
    }

    var body: some View {
        FormSheet(
            title: "Edit Details",
            primaryAction: FormSheetAction(title: "Save Changes") {
                saveChanges()
            },
            secondaryAction: FormSheetAction(title: "Cancel") {
                dismiss()
            }
        ) {
            VStack(spacing: Spacing.md) {
                FormField(label: "Name", text: $name, placeholder: "Item name")
                VendorPickerField(value: $source)
                FormField(label: "SKU", text: $sku, placeholder: "Barcode or SKU number")
                FormField(label: "Purchase Price", text: $purchasePrice, placeholder: "0.00")
                    .keyboardType(.decimalPad)
                FormField(label: "Project Price", text: $projectPrice, placeholder: "0.00")
                    .keyboardType(.decimalPad)
                FormField(label: "Market Value", text: $marketValue, placeholder: "0.00")
                    .keyboardType(.decimalPad)
            }
        }
    }

    // MARK: - Actions

    private func saveChanges() {
        var fields: [String: Any] = [
            "name": name.trimmingCharacters(in: .whitespacesAndNewlines),
            "source": source.trimmingCharacters(in: .whitespacesAndNewlines),
            "sku": sku.trimmingCharacters(in: .whitespacesAndNewlines),
        ]

        if let cents = parseCents(purchasePrice) {
            fields["purchasePriceCents"] = cents
        } else if purchasePrice.isEmpty {
            fields["purchasePriceCents"] = NSNull()
        }

        if let cents = parseCents(projectPrice) {
            fields["projectPriceCents"] = cents
        } else if projectPrice.isEmpty {
            fields["projectPriceCents"] = NSNull()
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
        return Int(value * 100)
    }
}

#Preview {
    EditItemDetailsModal(item: Item(name: "Test Item", source: "Ross", sku: "123456")) { _ in }
}
