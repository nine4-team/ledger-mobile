import LedgerTargetAppModel
import SwiftUI

struct AccountPendingWorkStagingExerciseView: View {
    @Bindable var model: AccountPendingWorkStagingExercise

    var body: some View {
        Section("Pending Local Work") {
            LabeledContent("Local status", value: model.statusLabel)
                .accessibilityIdentifier("target-pending-work-status")

            Button("Refresh") {
                Task { await model.refresh() }
            }
            .disabled(!model.canRefresh)
            .accessibilityIdentifier("target-pending-work-refresh")

            LabeledContent(
                "Queued operations",
                value: model.queuedOperationCountLabel
            )
            .accessibilityIdentifier("target-pending-work-queued-count")

            LabeledContent(
                "Applying operations",
                value: model.applyingOperationCountLabel
            )
            .accessibilityIdentifier("target-pending-work-applying-count")

            LabeledContent(
                "Unresolved rejected operations",
                value: model.unresolvedRejectedOperationCountLabel
            )
            .accessibilityIdentifier("target-pending-work-rejected-count")

            LabeledContent(
                "Unverified attachments",
                value: model.unverifiedAttachmentCountLabel
            )
            .accessibilityIdentifier("target-pending-work-attachment-count")

            if let diagnosticCode = model.diagnosticCode {
                Text(diagnosticCode)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("target-pending-work-diagnostic")
            }
        }
    }
}
