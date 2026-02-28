import SwiftUI

/// Bottom sheet for editing a space's name and notes.
struct EditSpaceDetailsModal: View {
    let space: Space
    let onSave: (String, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var notes: String

    init(space: Space, onSave: @escaping (String, String?) -> Void) {
        self.space = space
        self.onSave = onSave
        _name = State(initialValue: space.name)
        _notes = State(initialValue: space.notes ?? "")
    }

    private var nameIsEmpty: Bool {
        name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        FormSheet(
            title: "Edit Space Details",
            primaryAction: FormSheetAction(
                title: "Save",
                isDisabled: nameIsEmpty
            ) {
                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                onSave(trimmedName, trimmedNotes.isEmpty ? nil : trimmedNotes)
                dismiss()
            },
            secondaryAction: FormSheetAction(title: "Cancel") {
                dismiss()
            }
        ) {
            VStack(spacing: Spacing.md) {
                FormField(
                    label: "Name",
                    text: $name,
                    placeholder: "Space name",
                    errorText: nameIsEmpty ? "Name is required" : nil
                )

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Notes")
                        .font(Typography.label)
                        .foregroundStyle(BrandColors.textSecondary)

                    TextEditor(text: $notes)
                        .font(Typography.body)
                        .foregroundStyle(BrandColors.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(Spacing.md)
                        .frame(minHeight: 120)
                        .background(BrandColors.inputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                                .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
                        )
                }
            }
        }
    }
}

#Preview {
    EditSpaceDetailsModal(
        space: Space(name: "Living Room", notes: "Main display area"),
        onSave: { _, _ in }
    )
}
