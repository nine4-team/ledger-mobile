import LedgerTargetAppModel
import LedgerTargetCore
import SwiftUI

struct ClientBrowsingStagingExerciseView: View {
    @Bindable var model: ClientBrowsingStagingExercise

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
    }

    @ViewBuilder
    private func clientRows(
        _ rows: [ClientDirectoryCoreRow],
        segment: ClientDirectorySegment
    ) -> some View {
        ForEach(rows, id: \.clientId) { row in
            Button {
                Task {
                    await model.select(clientId: row.clientId, segment: segment)
                }
            } label: {
                Text(row.displayName.rawValue)
            }
            .accessibilityIdentifier(
                "target-client-row-\(segment.rawValue)-\(row.clientId.rawValue)"
            )
        }
    }
}
