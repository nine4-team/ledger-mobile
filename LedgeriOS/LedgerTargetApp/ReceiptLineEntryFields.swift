import LedgerTargetCore
import SwiftUI

/// The existing Expense line controls, shared with Transaction receipt editing.
struct ReceiptLineEntryFields: View {
    @Binding var lines: [ReceiptLineEntry]
    let accessibilityPrefix: String

    var body: some View {
        ForEach($lines) { $line in
            VStack(alignment: .leading, spacing: Spacing.sm) {
                FormField(label: "Description", text: $line.description, placeholder: "Receipt wording")
                FormField(label: "Line total", text: $line.amountText, placeholder: "Line amount")
                Picker("Effect", selection: $line.effect) {
                    Text("Increase").tag(NonItemReceiptLineEffect.increase)
                    Text("Decrease").tag(NonItemReceiptLineEffect.decrease)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("\(accessibilityPrefix)-line-effect-\(line.id.uuidString.lowercased())")
                FormField(label: "Quantity (optional)", text: $line.quantityText, placeholder: "Quantity")
                Button("Remove line") {
                    let id = line.id
                    lines.removeAll { $0.id == id }
                }
            }
        }
        Button("Add receipt line") { lines.append(.init()) }
    }
}
