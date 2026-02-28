import SwiftUI

/// Bottom sheet modal for full checklist management —
/// add/remove checklists, add/remove/check items within each checklist.
struct EditChecklistModal: View {
    let space: Space
    let onSave: ([Checklist]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var localChecklists: [Checklist]

    init(space: Space, onSave: @escaping ([Checklist]) -> Void) {
        self.space = space
        self.onSave = onSave
        self._localChecklists = State(initialValue: space.checklists ?? [])
    }

    var body: some View {
        FormSheet(
            title: "Edit Checklists",
            primaryAction: FormSheetAction(title: "Save") {
                onSave(localChecklists)
                dismiss()
            },
            secondaryAction: FormSheetAction(title: "Cancel") {
                dismiss()
            }
        ) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                ForEach($localChecklists) { $checklist in
                    checklistSection(checklist: $checklist)
                }

                Button {
                    localChecklists.append(Checklist(name: "New Checklist"))
                } label: {
                    Label("Add Checklist", systemImage: "plus.circle.fill")
                        .font(Typography.label)
                        .foregroundStyle(BrandColors.primary)
                }
            }
        }
    }

    // MARK: - Checklist Section

    @ViewBuilder
    private func checklistSection(checklist: Binding<Checklist>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Checklist title row
            HStack(spacing: Spacing.sm) {
                TextField("Checklist Name", text: checklist.name)
                    .font(Typography.h3)
                    .foregroundStyle(BrandColors.textPrimary)

                Spacer()

                Button {
                    localChecklists.removeAll { $0.id == checklist.wrappedValue.id }
                } label: {
                    Image(systemName: "trash")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.destructive)
                }
                .buttonStyle(.plain)
            }

            // Items
            ForEach(checklist.items) { $item in
                HStack(spacing: Spacing.sm) {
                    // Checkbox
                    Button {
                        item.isChecked.toggle()
                    } label: {
                        Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(
                                item.isChecked ? BrandColors.primary : BrandColors.textTertiary
                            )
                            .font(Typography.body)
                    }
                    .buttonStyle(.plain)

                    // Item text
                    TextField("Item text", text: $item.text)
                        .font(Typography.body)
                        .foregroundStyle(BrandColors.textPrimary)

                    // Delete item
                    Button {
                        checklist.wrappedValue.items.removeAll { $0.id == item.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(BrandColors.destructive)
                            .font(Typography.small)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Add Item
            Button {
                checklist.wrappedValue.items.append(ChecklistItem())
            } label: {
                Label("Add Item", systemImage: "plus")
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textSecondary)
            }

            Divider()
                .overlay(BrandColors.border)
        }
        .padding(Spacing.md)
        .background(BrandColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Dimensions.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Dimensions.cardRadius)
                .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
        )
    }
}

#Preview("Empty") {
    EditChecklistModal(
        space: Space(name: "Test Space"),
        onSave: { _ in }
    )
}

#Preview("With Checklists") {
    EditChecklistModal(
        space: Space(
            name: "Test Space",
            checklists: [
                Checklist(name: "Prep Work", items: [
                    ChecklistItem(text: "Sand walls", isChecked: true),
                    ChecklistItem(text: "Prime surfaces", isChecked: false),
                ]),
                Checklist(name: "Final Touches", items: [
                    ChecklistItem(text: "Touch up paint", isChecked: false),
                ]),
            ]
        ),
        onSave: { _ in }
    )
}
