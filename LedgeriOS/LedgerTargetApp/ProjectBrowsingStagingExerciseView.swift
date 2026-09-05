import LedgerTargetAppModel
import LedgerTargetCore
import SwiftUI

struct ProjectBrowsingStagingExerciseView: View {
    @Bindable var model: ProjectBrowsingStagingExercise
    @Bindable var archive: ProjectArchiveBrowserStagingExercise

    var body: some View {
        Section("Local Project Browser") {
            LabeledContent("Project data", value: model.directoryStatus)
                .accessibilityIdentifier("target-project-directory-status")

            LabeledContent("Active Projects", value: model.activeProjectCountLabel)
                .accessibilityIdentifier("target-project-active-count")
            projectRows(model.activeProjects, segment: .active)

            LabeledContent("Archived Projects", value: model.archivedProjectCountLabel)
                .accessibilityIdentifier("target-project-archived-count")
            projectRows(model.archivedProjects, segment: .archived)

            if let selectedProjectName = model.selectedProjectName {
                LabeledContent("Selected Project", value: selectedProjectName)
                    .accessibilityIdentifier("target-selected-project-name")
            }
            if let selectedClientName = model.selectedClientName {
                LabeledContent("Selected Client", value: selectedClientName)
                    .accessibilityIdentifier("target-selected-client-name")
            }

            LabeledContent("Detail state", value: model.detailStateLabel)
                .accessibilityIdentifier("target-project-detail-state")
            LabeledContent("Detail readiness", value: model.detailReadiness)
                .accessibilityIdentifier("target-project-detail-readiness")

            Button("Archive Project") {
                archive.requestArchiveConfirmation()
            }
            .disabled(!archive.canRequestArchive)
            .accessibilityIdentifier("target-project-archive-action")

            LabeledContent("Archive state", value: archive.operationStateLabel)
                .accessibilityIdentifier("target-project-archive-state")

            if archive.canRetryAmbiguousAcceptance {
                Button("Retry local acceptance") {
                    Task { await archive.retryAmbiguousAcceptance() }
                }
                .accessibilityIdentifier("target-project-archive-retry")
            } else if archive.canRetryRejectedArchive {
                Button("Retry archive") {
                    archive.requestRejectedRetryConfirmation()
                }
                .accessibilityIdentifier("target-project-archive-retry")
            }

            if let archiveDiagnostic = archive.diagnostic {
                Text(archiveDiagnostic)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("target-project-archive-diagnostic")
            }

            if let directoryDiagnostic = model.directoryDiagnostic {
                Text(directoryDiagnostic)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("target-project-directory-diagnostic")
            }
            if let detailDiagnostic = model.detailDiagnostic {
                Text(detailDiagnostic)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("target-project-detail-diagnostic")
            }
        }
        .onChange(of: model.selectedProjectArchiveEvidence) {
            Task { await archive.selectionDidSettle() }
        }
        .alert(
            "Archive this Project?",
            isPresented: Binding(
                get: { archive.isConfirmationPresented },
                set: { presented in
                    if !presented { archive.cancelConfirmation() }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                archive.cancelConfirmation()
            }
            .accessibilityIdentifier("target-project-archive-cancel")
            Button("Archive", role: .destructive) {
                Task { await archive.confirmArchive() }
            }
            .accessibilityIdentifier("target-project-archive-confirm")
        }
    }

    @ViewBuilder
    private func projectRows(
        _ rows: [ProjectDirectoryCoreRow],
        segment: ProjectDirectorySegment
    ) -> some View {
        ForEach(rows, id: \.projectId) { row in
            Button {
                Task {
                    await archive.selectionDidChange()
                    await model.select(projectId: row.projectId, segment: segment)
                }
            } label: {
                VStack(alignment: .leading) {
                    Text(row.projectDisplayName.rawValue)
                    Text(row.clientDisplayName.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(archive.isSubmitting)
            .accessibilityIdentifier(
                "target-project-row-\(segment.rawValue)-\(row.projectId.rawValue)"
            )
        }
    }
}
