import LedgerTargetAppModel
import LedgerTargetCore
import SwiftUI

struct ClientBrowsingStagingExerciseView: View {
    @Bindable var model: ClientBrowsingStagingExercise
    @Bindable var archive: ClientArchiveBrowserStagingExercise

    var body: some View {
        Section("Local Client Browser") {
            LabeledContent("Client data", value: model.directoryStatus)
                .accessibilityIdentifier("target-client-directory-status")

            LabeledContent("Active Clients", value: model.activeClientCountLabel)
                .accessibilityIdentifier("target-client-active-count")
            clientRows(model.activeClients, segment: .active)

            LabeledContent("Archived Clients", value: model.archivedClientCountLabel)
                .accessibilityIdentifier("target-client-archived-count")
            clientRows(model.archivedClients, segment: .archived)

            if let selectedClientName = model.selectedClientName {
                LabeledContent("Selected Client", value: selectedClientName)
                    .accessibilityIdentifier("target-client-browser-selected-name")
            }

            LabeledContent("Detail state", value: model.detailStateLabel)
                .accessibilityIdentifier("target-client-detail-state")
            LabeledContent("Detail readiness", value: model.detailReadiness)
                .accessibilityIdentifier("target-client-detail-readiness")

            Button("Archive Client") {
                archive.requestArchiveConfirmation()
            }
            .disabled(!archive.canRequestArchive)
            .accessibilityIdentifier("target-client-archive-action")

            LabeledContent("Archive state", value: archive.operationStateLabel)
                .accessibilityIdentifier("target-client-archive-state")

            if archive.canRetryAmbiguousAcceptance {
                Button("Retry local acceptance") {
                    Task { await archive.retryAmbiguousAcceptance() }
                }
                .accessibilityIdentifier("target-client-archive-retry")
            } else if archive.canRetryRejectedArchive {
                Button("Retry archive") {
                    archive.requestRejectedRetryConfirmation()
                }
                .accessibilityIdentifier("target-client-archive-retry")
            }

            if let archiveDiagnostic = archive.diagnostic {
                Text(archiveDiagnostic)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("target-client-archive-diagnostic")
            }

            if let directoryDiagnostic = model.directoryDiagnostic {
                Text(directoryDiagnostic)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("target-client-directory-diagnostic")
            }
            if let detailDiagnostic = model.detailDiagnostic {
                Text(detailDiagnostic)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("target-client-detail-diagnostic")
            }
        }
        .onChange(of: model.selectedClientArchiveEvidence) {
            Task { await archive.selectionDidSettle() }
        }
        .alert(
            "Archive this Client?",
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
            .accessibilityIdentifier("target-client-archive-cancel")
            Button("Archive", role: .destructive) {
                Task { await archive.confirmArchive() }
            }
            .accessibilityIdentifier("target-client-archive-confirm")
        }
    }

    @ViewBuilder
    private func clientRows(
        _ rows: [ClientDirectoryCoreRow],
        segment: ClientDirectorySegment
    ) -> some View {
        ForEach(rows, id: \.clientId) { row in
            Button {
                Task {
                    await archive.selectionDidChange()
                    await model.select(clientId: row.clientId, segment: segment)
                }
            } label: {
                Text(row.displayName.rawValue)
            }
            .disabled(archive.isSubmitting)
            .accessibilityIdentifier(
                "target-client-row-\(segment.rawValue)-\(row.clientId.rawValue)"
            )
        }
    }
}
