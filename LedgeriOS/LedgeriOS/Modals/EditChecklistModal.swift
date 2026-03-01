import SwiftUI

/// Bottom sheet modal for full checklist management —
/// add/remove checklists, add/remove/reorder/check items within each checklist.
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
        VStack(spacing: 0) {
            // Header
            Text("Edit Checklists")
                .font(Typography.h2)
                .foregroundStyle(BrandColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.screenPadding)
                .padding(.bottom, Spacing.sm)

            // List with reorder support
            List {
                ForEach(localChecklists.indices, id: \.self) { checklistIndex in
                    Section {
                        ForEach(localChecklists[checklistIndex].items.indices, id: \.self) { itemIndex in
                            checklistItemRow(
                                checklistIndex: checklistIndex,
                                itemIndex: itemIndex
                            )
                        }
                        .onMove { indices, destination in
                            localChecklists[checklistIndex].items.move(fromOffsets: indices, toOffset: destination)
                        }
                        .onDelete { indices in
                            localChecklists[checklistIndex].items.remove(atOffsets: indices)
                        }

                        // Add Item
                        Button {
                            localChecklists[checklistIndex].items.append(ChecklistItem())
                        } label: {
                            Label("Add Item", systemImage: "plus")
                                .font(Typography.small)
                                .foregroundStyle(BrandColors.textSecondary)
                        }
                    } header: {
                        checklistHeader(checklistIndex: checklistIndex)
                    }
                }

                // Add Checklist
                Section {
                    Button {
                        localChecklists.append(Checklist(name: "New Checklist"))
                    } label: {
                        Label("Add Checklist", systemImage: "plus.circle.fill")
                            .font(Typography.label)
                            .foregroundStyle(BrandColors.primary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))

            // Actions
            VStack(spacing: Spacing.sm) {
                AppButton(title: "Save") {
                    onSave(localChecklists)
                    dismiss()
                }

                AppButton(title: "Cancel", variant: .secondary) {
                    dismiss()
                }
            }
            .padding(Spacing.screenPadding)
        }
    }

    // MARK: - Checklist Header

    @ViewBuilder
    private func checklistHeader(checklistIndex: Int) -> some View {
        HStack(spacing: Spacing.sm) {
            TextField("Checklist Name", text: $localChecklists[checklistIndex].name)
                .font(Typography.h3)
                .foregroundStyle(BrandColors.textPrimary)
                .textCase(nil)

            Spacer()

            Button {
                localChecklists.remove(at: checklistIndex)
            } label: {
                Image(systemName: "trash")
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.destructive)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Checklist Item Row

    @ViewBuilder
    private func checklistItemRow(checklistIndex: Int, itemIndex: Int) -> some View {
        HStack(spacing: Spacing.sm) {
            // Checkbox
            Button {
                localChecklists[checklistIndex].items[itemIndex].isChecked.toggle()
            } label: {
                Image(systemName: localChecklists[checklistIndex].items[itemIndex].isChecked
                    ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(
                        localChecklists[checklistIndex].items[itemIndex].isChecked
                            ? BrandColors.primary : BrandColors.textTertiary
                    )
                    .font(Typography.body)
            }
            .buttonStyle(.plain)

            // Item text
            TextField("Item text", text: $localChecklists[checklistIndex].items[itemIndex].text)
                .font(Typography.body)
                .foregroundStyle(BrandColors.textPrimary)
        }
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
