import SwiftUI

/// Lightweight bottom sheet for renaming an item.
struct RenameItemModal: View {
    let currentName: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @FocusState private var fieldFocused: Bool

    init(currentName: String, onSave: @escaping (String) -> Void) {
        self.currentName = currentName
        self.onSave = onSave
        _name = State(initialValue: currentName)
    }

    private var nameIsEmpty: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        FormSheet(
            title: "Rename Item",
            primaryAction: FormSheetAction(
                title: "Save",
                isDisabled: nameIsEmpty
            ) {
                save()
            },
            secondaryAction: FormSheetAction(title: "Cancel") {
                dismiss()
            }
        ) {
            HStack(spacing: Spacing.sm) {
                TextField("Item name", text: $name)
                    .font(Typography.input)
                    .focused($fieldFocused)
                    .onSubmit { if !nameIsEmpty { save() } }
                    .autocorrectionDisabled()

                if !name.isEmpty {
                    Button {
                        name = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(Typography.body)
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear name")
                }
            }
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: 44)
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                    .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
            )
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                fieldFocused = true
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
        dismiss()
    }
}

#Preview {
    RenameItemModal(currentName: "Vintage Lamp", onSave: { _ in })
}
