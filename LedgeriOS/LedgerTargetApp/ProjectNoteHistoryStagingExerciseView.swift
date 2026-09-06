import LedgerTargetAppModel
import SwiftUI

struct ProjectNoteHistoryStagingExerciseView: View {
    @Bindable var model: ProjectNoteHistoryStagingExercise

    var body: some View {
        Group {
            LabeledContent("Note history", value: model.status)
                .accessibilityIdentifier("target-project-note-history-status")

            if model.isAuthoritativelyEmpty {
                Text("No notes")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("target-project-note-history-empty")
            }

            ForEach(model.rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.body)
                        .foregroundStyle(row.isTombstone ? .secondary : .primary)
                    HStack {
                        if let creator = row.creatorDisplayName {
                            Text(creator)
                        }
                        Text(row.createdAt, style: .date)
                        if row.lastEditedAt != nil { Text("Edited") }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("target-project-note-row")
            }

            HStack {
                Button("Older") {
                    Task { await model.loadOlderNotes() }
                }
                .disabled(!model.hasOlderNotes)
                .accessibilityIdentifier("target-project-note-older")

                Button("Newest") {
                    Task { await model.showNewestNotes() }
                }
                .disabled(model.isShowingNewestPage)
                .accessibilityIdentifier("target-project-note-newest")
            }

            if let diagnostic = model.diagnostic {
                Text(diagnostic)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("target-project-note-history-diagnostic")
            }
        }
    }
}
