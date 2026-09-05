import LedgerTargetAppModel
import SwiftUI

struct SpaceAssignmentDestinationStagingExerciseView: View {
    @Bindable var model: SpaceAssignmentDestinationStagingExercise

    var body: some View {
        Section("Local Space Destination Picker") {
            LabeledContent("Destination data", value: model.status)
                .accessibilityIdentifier("target-space-destination-status")
            ForEach(model.rows, id: \.id) { row in
                Button(row.displayName.rawValue) {
                    model.select(spaceId: row.id)
                }
                .accessibilityIdentifier("target-space-destination-\(row.id.rawValue)")
            }
            if let selected = model.selectedSpaceId {
                LabeledContent("Selected Space ID", value: selected.rawValue)
                    .accessibilityIdentifier("target-space-destination-selection")
            }
            if let diagnostic = model.diagnostic {
                Text(diagnostic)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("target-space-destination-diagnostic")
            }
        }
    }
}
