import LedgerTargetAppModel
import LedgerTargetCore
import SwiftUI

struct SpaceCoreDetailsStagingExerciseView: View {
    @Bindable var model: SpaceCoreDetailsStagingExercise

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
                if model.progressCountsAreAuthoritative {
                    LabeledContent(
                        "Checklist progress",
                        value: "\(model.completedItemCount) / \(model.totalItemCount)"
                    )
                    .accessibilityIdentifier("target-space-core-details-progress")
                } else {
                    Text("Checklist progress is incomplete local evidence.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(
                            "target-space-core-details-progress-incomplete"
                        )
                }

                ForEach(row.checklists.checklists, id: \.id.rawValue) { checklist in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(checklist.name.rawValue).font(.headline)
                        if model.progressCountsAreAuthoritative {
                            Text(
                                "\(checklist.completedItemCount) / \(checklist.totalItemCount)"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        ForEach(checklist.items, id: \.id.rawValue) { item in
                            Label(
                                item.text.rawValue,
                                systemImage: item.isChecked ? "checkmark.circle.fill" : "circle"
                            )
                        }
                    }
                    .accessibilityIdentifier("target-space-core-details-checklist")
                }
            }

            if let diagnostic = model.diagnostic {
                Text(diagnostic)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("target-space-core-details-diagnostic")
            }
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
