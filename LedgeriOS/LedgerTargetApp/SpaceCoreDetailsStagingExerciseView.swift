import LedgerTargetAppModel
import LedgerTargetCore
import SwiftUI

struct SpaceCoreDetailsStagingExerciseView: View {
    @Bindable var model: SpaceCoreDetailsStagingExercise
    @Bindable var checklistToggle: SpaceChecklistItemToggleStagingExercise
    @Bindable var checklistEditor: SpaceChecklistEditorStagingExercise
    @State private var isChecklistsExpanded = true

    var body: some View {
        Section("Space Core Details") {
            LabeledContent("Local status", value: model.status)
                .accessibilityIdentifier("target-space-core-details-status")

            if model.isAuthoritativelyEmpty {
                Text("No Space exists for this exact local selection.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("target-space-core-details-empty")
            }

            if let row = model.row {
                LabeledContent("Name", value: row.displayName.rawValue)
                LabeledContent("Scope", value: scope(row))
                LabeledContent("Lifecycle", value: row.lifecycle.rawValue)
                LabeledContent("Revision", value: String(row.revision))
                LabeledContent("Created", value: row.createdAt.formatted())
                LabeledContent("Updated", value: row.updatedAt.formatted())
                if let notes = row.notes.value {
                    Text(notes)
                        .accessibilityIdentifier("target-space-core-details-notes")
                }
                if checklistToggle.isProgressOptimistic {
                    LabeledContent(
                        "Pending checklist progress",
                        value: "\(checklistToggle.completedItemCount) / \(checklistToggle.totalItemCount)"
                    )
                    .accessibilityIdentifier("target-space-core-details-progress")
                } else if checklistToggle.admission == .ready
                            || checklistToggle.admission == .archived {
                    LabeledContent(
                        checklistToggle.admission == .archived
                            ? "Archived checklist progress"
                            : "Checklist progress",
                        value: "\(checklistToggle.completedItemCount) / \(checklistToggle.totalItemCount)"
                    )
                    .accessibilityIdentifier("target-space-core-details-progress")
                } else if checklistToggle.admission == .retryableStale {
                    LabeledContent(
                        "Cached checklist progress",
                        value: "\(checklistToggle.completedItemCount) / \(checklistToggle.totalItemCount)"
                    )
                    .accessibilityIdentifier("target-space-core-details-progress")
                } else {
                    Text("Checklist progress is incomplete local evidence.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(
                            "target-space-core-details-progress-incomplete"
                        )
                }

                DisclosureGroup(isExpanded: $isChecklistsExpanded) {
                    HStack {
                        Button("Edit") {
                            checklistEditor.open()
                        }
                        .disabled(!checklistEditor.canOpen)
                        .accessibilityIdentifier("target-space-checklist-editor-open")

                        if checklistEditor.canReviewPreservedConflict {
                            Button("Review Rejected Draft") {
                                checklistEditor.reviewPreservedConflict()
                            }
                            .accessibilityIdentifier(
                                "target-space-checklist-editor-review-conflict"
                            )
                        }
                    }

                    if let collection = checklistToggle.displayedCollection {
                        if collection.checklists.isEmpty,
                           checklistToggle.admission.permitsToggle
                            || checklistToggle.isProgressOptimistic {
                            Text("No checklists.")
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("target-space-checklists-empty")
                        } else {
                            ForEach(collection.checklists, id: \.id.rawValue) { checklist in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(checklist.name.rawValue).font(.headline)
                                        Spacer()
                                        Text(
                                            "\(checklist.completedItemCount) / \(checklist.totalItemCount)"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel(
                                            "\(checklist.name.rawValue) progress"
                                        )
                                        .accessibilityValue(
                                            "\(checklist.completedItemCount) of \(checklist.totalItemCount) complete"
                                        )
                                    }

                                    ForEach(checklist.items, id: \.id.rawValue) { item in
                                        Button {
                                            Task {
                                                await checklistToggle.toggle(
                                                    checklistId: checklist.id,
                                                    itemId: item.id
                                                )
                                            }
                                        } label: {
                                            Label(
                                                item.text.rawValue,
                                                systemImage: item.isChecked
                                                    ? "checkmark.circle.fill"
                                                    : "circle"
                                            )
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(!checklistToggle.canToggle(
                                            checklistId: checklist.id,
                                            itemId: item.id
                                        ))
                                        .accessibilityIdentifier(
                                            "target-space-checklist-item-\(checklist.id.rawValue)-\(item.id.rawValue)"
                                        )
                                        .accessibilityLabel(item.text.rawValue)
                                        .accessibilityValue(
                                            item.isChecked ? "Checked" : "Not checked"
                                        )
                                        .accessibilityHint(
                                            item.isChecked
                                                ? "Marks this checklist item incomplete"
                                                : "Marks this checklist item complete"
                                        )
                                    }
                                }
                                .accessibilityIdentifier(
                                    "target-space-checklist-\(checklist.id.rawValue)"
                                )
                            }
                        }
                    } else {
                        Text(checklistToggle.admission.explanation)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("target-space-checklists-unavailable")
                    }
                } label: {
                    HStack {
                        Text("Checklists")
                        Spacer()
                        Text(
                            "\(checklistToggle.completedItemCount) / \(checklistToggle.totalItemCount)"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("target-space-checklists-section")
                .accessibilityValue(isChecklistsExpanded ? "Expanded" : "Collapsed")

                LabeledContent(
                    "Checklist synchronization",
                    value: checklistToggle.operationStatus
                )
                .accessibilityIdentifier("target-space-checklist-operation-status")

                if !checklistToggle.admission.permitsToggle {
                    Text(checklistToggle.admission.explanation)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("target-space-checklist-admission")
                }

                if checklistToggle.canRetryAmbiguousAcceptance {
                    Button("Retry local acceptance") {
                        Task { await checklistToggle.retryAmbiguousAcceptance() }
                    }
                    .accessibilityIdentifier("target-space-checklist-retry-acceptance")
                }
            }

            if let diagnostic = model.diagnostic {
                Text(diagnostic)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("target-space-core-details-diagnostic")
            }

            if let diagnostic = checklistToggle.diagnostic {
                Text(diagnostic)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("target-space-checklist-diagnostic")
            }
        }
        .task(id: model.evidenceSequence) {
            await checklistToggle.receiveDetailUpdate(
                model.currentUpdate,
                selectedSpaceId: model.selectedSpaceId
            )
            await checklistEditor.receiveDetailUpdate(
                model.currentUpdate,
                selectedSpaceId: model.selectedSpaceId
            )
        }
        .sheet(isPresented: Binding(
            get: { checklistEditor.isPresented },
            set: { if !$0 { checklistEditor.cancel() } }
        )) {
            SpaceChecklistEditorStagingExerciseView(model: checklistEditor)
        }
    }

    private func scope(_ row: SpaceCoreDetailsSnapshot) -> String {
        switch row.scope {
        case .project:
            "Project"
        case .businessInventory:
            "Business Inventory"
        }
    }
}
