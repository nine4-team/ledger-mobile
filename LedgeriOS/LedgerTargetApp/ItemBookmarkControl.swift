import LedgerTargetCore
import SwiftUI

/// Existing bookmark presentation with durable target-command submission.
struct ItemBookmarkControl: View {
    let itemId: ItemID
    let details: DownloadedItemDescriptiveDetails
    let service: any ItemDetailsEditing
    @State private var attempt: Attempt?
    @State private var request: UUID?
    @State private var operationId: OperationID?
    @State private var phase: OperationPhase?
    @State private var saving = false
    @State private var error: String?

    private struct Attempt {
        let payload: EditItemDetailsCommand.Payload
        let id = UUID()
        let date = Date()
    }

    var body: some View {
        VStack(alignment: .leading) {
            CardBookmarkButton(isBookmarked: details.isBookmarked ?? false, action: submit)
                .disabled(saving || operationId != nil || details.itemRevision == nil)
                .accessibilityIdentifier("target-item-detail-bookmark-toggle")
            if let error {
                Text(error).font(.caption)
                if operationId == nil {
                    Button("Retry bookmark change", action: submit).disabled(saving)
                }
            } else if operationId != nil {
                Text(phase == .rejected ? "Bookmark change was not applied. Saved work is retained for review."
                     : "Bookmark change saved on this device. Waiting to sync.")
                    .font(.caption).accessibilityIdentifier("target-item-bookmark-pending")
            }
        }
        .task(id: request) {
            guard request != nil, let attempt else { return }
            do {
                let receipt = try await service.editItemDetails(attempt.payload,
                    operationUUID: attempt.id, capturedAt: attempt.date)
                operationId = receipt.operationId; error = nil
            } catch is CancellationError {} catch {
                self.error = "Bookmark change could not be confirmed. Retry uses the same edit."
            }
            saving = false
        }
        .task(id: operationId) {
            guard let operationId else { return }
            do {
                for try await snapshot in service.watchItemDetailsEdit(operationId) {
                    phase = snapshot?.state.phase
                    finishIfReadBack()
                }
            } catch is CancellationError {} catch {
                self.error = "Bookmark status is unavailable. Saved work is retained."
            }
        }
        .onChange(of: details.itemRevision) { _, _ in finishIfReadBack() }
    }

    private func submit() {
        guard !saving, operationId == nil else { return }
        if attempt == nil {
            do {
                var draft = ItemDetailsEditDraft(itemId: itemId, original: details)
                draft.bookmark.toggle()
                guard let payload = try draft.payload() else { return }
                attempt = Attempt(payload: payload)
            } catch {
                self.error = "Refresh this Item before changing its bookmark."
                return
            }
        }
        saving = true; error = nil; request = UUID()
    }

    private func finishIfReadBack() {
        guard phase == .applied, let attempt,
              let revision = details.itemRevision,
              revision > attempt.payload.items[0].expectedRevision else { return }
        self.attempt = nil; operationId = nil; phase = nil; error = nil
    }
}
