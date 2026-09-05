import LedgerTargetAppModel
import SwiftUI

struct TransferDestinationSelectionStagingExerciseView: View {
    @Bindable var model: TransferDestinationSelectionStagingExercise

    var body: some View {
        Section("Local Transfer Destination Picker") {
            LabeledContent("Destination data", value: model.status)
                .accessibilityIdentifier("target-transfer-destination-status")
            ForEach(model.rows, id: \.destination.id) { candidate in
                Button(candidate.destination.displayName.rawValue) {
                    model.select(projectId: candidate.destination.id)
                }
                .accessibilityIdentifier(
                    "target-transfer-destination-\(candidate.destination.id.rawValue)"
                )
            }
            if let selected = model.selectedProjectId {
                LabeledContent("Selected Project ID", value: selected.rawValue)
                    .accessibilityIdentifier("target-transfer-destination-selection")
            }
            if let diagnostic = model.diagnostic {
                Text(diagnostic)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("target-transfer-destination-diagnostic")
            }
        }
    }
}
