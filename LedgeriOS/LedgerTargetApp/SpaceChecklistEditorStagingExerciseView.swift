import LedgerTargetAppModel
import LedgerTargetCore
import SwiftUI

struct SpaceChecklistEditorStagingExerciseView: View {
    @Bindable var model: SpaceChecklistEditorStagingExercise

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.checklists.isEmpty {
                    ContentUnavailableView(
                        "No Checklists",
                        systemImage: "checklist",
                        description: Text("Add a checklist or cancel without changing the Space.")
                    )
                    .accessibilityIdentifier("target-space-checklist-editor-empty")
                } else {
                    List {
                        ForEach(model.checklists) { checklist in
                            Section {
                                ForEach(checklist.items) { item in
                                    SpaceChecklistEditorItemRow(
                                        model: model,
                                        checklistId: checklist.id,
                                        itemId: item.id
                                    )
                                }
                                .onDelete { offsets in
                                    for index in offsets.sorted(by: >) {
                                        guard checklist.items.indices.contains(index) else {
                                            continue
                                        }
                                        model.deleteItem(
                                            checklistId: checklist.id,
                                            itemId: checklist.items[index].id
                                        )
                                    }
                                }
                                .onMove { offsets, destination in
                                    var ids = checklist.items.map(\.id)
                                    ids.move(fromOffsets: offsets, toOffset: destination)
                                    model.reorderItems(
                                        checklistId: checklist.id,
                                        itemIds: ids
                                    )
                                }
                                .deleteDisabled(!model.canMutateDraft)
                                .moveDisabled(!model.canMutateDraft)

                                Button("Add Item", systemImage: "plus") {
                                    model.addItem(to: checklist.id)
                                }
                                .disabled(!model.canMutateDraft)
                                .accessibilityIdentifier(
                                    "target-space-checklist-editor-add-item-\(checklist.id.rawValue)"
                                )
                            } header: {
                                let checklistDeleteLabel = checklist.name.isEmpty
                                    ? "Delete untitled checklist"
                                    : "Delete \(checklist.name)"
                                HStack {
                                    TextField(
                                        "Checklist Name",
                                        text: Binding(
                                            get: { currentChecklist(checklist.id)?.name ?? "" },
                                            set: { model.renameChecklist(
                                                id: checklist.id,
                                                name: $0
                                            ) }
                                        )
                                    )
                                    .disabled(!model.canMutateDraft)
                                    .accessibilityIdentifier(
                                        "target-space-checklist-editor-name-\(checklist.id.rawValue)"
                                    )

                                    Spacer()

                                    Text(
                                        "\(checklist.completedItemCount) / \(checklist.items.count)"
                                    )
                                    .accessibilityLabel("Checklist progress")
                                    .accessibilityValue(
                                        "\(checklist.completedItemCount) of \(checklist.items.count) complete"
                                    )

                                    Button(role: .destructive) {
                                        model.deleteChecklist(id: checklist.id)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!model.canMutateDraft)
                                    .accessibilityIdentifier(
                                        "target-space-checklist-editor-delete-checklist-\(checklist.id.rawValue)"
                                    )
                                    .accessibilityLabel(checklistDeleteLabel)
                                }
                            }
                        }
                    }
#if canImport(UIKit)
                    .environment(\.editMode, .constant(.active))
#endif
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("Add Checklist", systemImage: "plus.circle.fill") {
                            model.addChecklist()
                        }
                        .disabled(!model.canMutateDraft)
                        .accessibilityIdentifier("target-space-checklist-editor-add-checklist")

                        Spacer()

                        Text("\(model.completedItemCount) / \(model.totalItemCount) complete")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier(
                                "target-space-checklist-editor-total-progress"
                            )
                    }

                    if let message = model.validationMessage {
                        Text(message)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier(
                                "target-space-checklist-editor-validation"
                            )
                    }
                    if let diagnostic = model.diagnostic {
                        Text(diagnostic)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier(
                                "target-space-checklist-editor-diagnostic"
                            )
                    }
                    if model.canRetryAmbiguousAcceptance {
                        Button("Retry local acceptance") {
                            Task { await model.retryAmbiguousAcceptance() }
                        }
                        .accessibilityIdentifier(
                            "target-space-checklist-editor-retry-acceptance"
                        )
                    }

                    HStack {
                        Button("Cancel") { model.cancel() }
                            .disabled(!model.canCancel)
                            .accessibilityIdentifier("target-space-checklist-editor-cancel")

                        Spacer()

                        Button("Save") {
                            Task { await model.save() }
                        }
                        .disabled(!model.canSave)
                        .accessibilityIdentifier("target-space-checklist-editor-save")
                    }
                }
                .padding()
            }
            .navigationTitle("Edit Checklists")
        }
        .interactiveDismissDisabled(model.isPresented && !model.canCancel)
#if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
#endif
    }

    private func currentChecklist(
        _ id: SpaceChecklistID
    ) -> SpaceChecklistEditorChecklist? {
        model.checklists.first(where: { $0.id == id })
    }
}

private struct SpaceChecklistEditorItemRow: View {
    @Bindable var model: SpaceChecklistEditorStagingExercise
    let checklistId: SpaceChecklistID
    let itemId: SpaceChecklistItemID

    private var item: SpaceChecklistEditorItem? {
        model.checklists
            .first(where: { $0.id == checklistId })?
            .items.first(where: { $0.id == itemId })
    }

    private var controlSuffix: String {
        "\(checklistId.rawValue)-\(itemId.rawValue)"
    }

    var body: some View {
        HStack {
            Button {
                model.setItemChecked(
                    checklistId: checklistId,
                    itemId: itemId,
                    isChecked: !(item?.isChecked ?? false)
                )
            } label: {
                Image(systemName: item?.isChecked == true
                    ? "checkmark.circle.fill"
                    : "circle")
            }
            .buttonStyle(.plain)
            .disabled(!model.canMutateDraft)
            .accessibilityIdentifier("target-space-checklist-editor-check-\(controlSuffix)")
            .accessibilityLabel(item?.text.isEmpty == false
                ? item?.text ?? "Untitled checklist item"
                : "Untitled checklist item")
            .accessibilityValue(item?.isChecked == true ? "Checked" : "Not checked")

            TextField(
                "Item text",
                text: Binding(
                    get: { item?.text ?? "" },
                    set: {
                        model.editItemText(
                            checklistId: checklistId,
                            itemId: itemId,
                            text: $0
                        )
                    }
                )
            )
            .disabled(!model.canMutateDraft)
            .accessibilityIdentifier(
                "target-space-checklist-editor-item-text-\(controlSuffix)"
            )

            Button(role: .destructive) {
                model.deleteItem(checklistId: checklistId, itemId: itemId)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .disabled(!model.canMutateDraft)
            .accessibilityIdentifier(
                "target-space-checklist-editor-delete-item-\(controlSuffix)"
            )
            .accessibilityLabel(item?.text.isEmpty == false
                ? "Delete \(item?.text ?? "checklist item")"
                : "Delete untitled checklist item")
        }
    }
}
