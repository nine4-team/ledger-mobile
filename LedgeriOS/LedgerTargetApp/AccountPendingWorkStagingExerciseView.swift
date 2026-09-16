import LedgerTargetAppModel
import LedgerTargetCore
import SwiftUI

struct AccountPendingWorkStagingExerciseView: View {
    @Bindable var model: AccountPendingWorkStagingExercise
    var endSession: ((SessionEndRequest) async throws -> Void)? = nil
    @State private var confirmedSummary: PendingLocalWorkSummary?
    @State private var confirmingDiscard = false
    @State private var endingTask: Task<Void, Never>?
    @State private var ending = false
    @State private var endFailure: String?

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
            LabeledContent("Unfinished Expense forms", value: model.unfinishedEntryCountLabel)
                .accessibilityIdentifier("target-pending-work-unfinished-count")

            if let diagnosticCode = model.diagnosticCode {
                Text(diagnosticCode)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("target-pending-work-diagnostic")
            }
            if endSession != nil {
                Button("Sync Then Sign Out") {
                    guard let summary = model.presentation.summary, !ending else { return }
                    ending = true
                    endFailure = nil
                    endingTask = Task {
                        defer { ending = false; endingTask = nil }
                        do {
                            let request = try SessionEndRequest(disposition: .synchronizeThenLogout,
                                expectedSummary: summary, requestedAt: Date())
                            while !Task.isCancelled {
                                await model.refresh()
                                guard let current = model.presentation.summary else {
                                    throw SessionEndingFailure.summaryChanged
                                }
                                if !current.hasBlockingWork {
                                    try Task.checkCancellation()
                                    try await endSession?(request)
                                    return
                                }
                                try await Task.sleep(for: .seconds(1))
                            }
                        } catch is CancellationError { }
                        catch { endFailure = "Sign-out did not complete. Check pending work in every downloaded Account and retry." }
                    }
                }.disabled(ending || model.presentation.summary == nil)
                .accessibilityIdentifier("target-pending-sync-sign-out")
                if ending {
                    Text("Waiting for pending work to sync. Keep Ledger open and connected.")
                    Button("Cancel Sign Out") { endingTask?.cancel() }
                }
                Button("Discard This Account’s Pending Work and Sign Out", role: .destructive) {
                    confirmedSummary = model.presentation.summary
                    confirmingDiscard = confirmedSummary != nil
                }.disabled(ending || model.presentation.summary == nil)
                .accessibilityIdentifier("target-pending-discard-sign-out")
                if let endFailure { Text(endFailure).foregroundStyle(.red) }
            }
        }
        .alert("Discard pending work from this device?", isPresented: $confirmingDiscard) {
            Button("Keep My Work", role: .cancel) { confirmedSummary = nil }
            Button("Discard and Sign Out", role: .destructive) {
                guard let summary = confirmedSummary else { return }
                confirmedSummary = nil
                ending = true
                endingTask = Task {
                    defer { ending = false; endingTask = nil }
                    do {
                        guard let request = try SessionEndPolicy.makeRequest(
                            choice: .removeFromDeviceDiscardingPendingWork(confirmedAt: Date()),
                            summary: summary, requestedAt: Date()) else { return }
                        try Task.checkCancellation()
                        try await endSession?(request)
                    } catch is CancellationError { }
                    catch { endFailure = "Work changed or sign-out could not finish. Refresh and review before trying again." }
                }
            }
        } message: {
            if let summary = confirmedSummary {
                Text("This Account: \(summary.queuedOperationCount) queued operations, \(summary.applyingOperationCount) applying operations, \(summary.unresolvedRejectedOperationCount) rejected operations, \(summary.unverifiedAttachmentCount) unverified attachments, and \(summary.unfinishedEntryCount) unfinished forms. These will be lost, not uploaded. Other Accounts must have no pending work.")
            }
        }
        .onDisappear { endingTask?.cancel(); confirmedSummary = nil }
    }
}
