import SwiftUI

/// Shared bottom sheet for editing free-text notes.
/// Reusable for transactions, items, spaces — takes a closure for saving.
struct EditNotesModal: View {
    let notes: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentText: String

    init(notes: String, onSave: @escaping (String) -> Void) {
        self.notes = notes
        self.onSave = onSave
        self._currentText = State(initialValue: notes)
    }

    var body: some View {
        FormSheet(
            title: "Edit Notes",
            primaryAction: FormSheetAction(title: "Save") {
                onSave(currentText)
                dismiss()
            },
            secondaryAction: FormSheetAction(title: "Cancel") {
                dismiss()
            }
        ) {
            TextEditor(text: $currentText)
                .font(Typography.body)
                .foregroundStyle(BrandColors.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(Spacing.md)
                .frame(minHeight: 200)
                .background(BrandColors.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                        .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
                )
        }
    }
}

#Preview {
    EditNotesModal(
        notes: "Sample notes for this transaction",
        onSave: { _ in }
    )
}
