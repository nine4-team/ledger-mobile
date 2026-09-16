import LedgerTargetCore
import SwiftUI

/// Backend orchestration for MoveToInventoryModal's existing FormSheet controls.
/// Only the uninvoiced Inventory-origin story is available through this command.
struct UninvoicedReturnForm: View {
    let accountId: AccountID
    let projectId: ProjectID
    let itemIds: [ItemID]
    let service: any UninvoicedReturnWorkflowServing
    @Environment(\.dismiss) private var dismiss
    @State private var review: UninvoicedReturnReview?
    @State private var draft: Draft?
    @State private var requestId: UUID?
    @State private var saving = false
    @State private var error: String?
    @State private var operationId: OperationID?
    @State private var status: OperationSnapshot?
    private struct Draft {
        let payload: ReturnUninvoicedItemsPayload
        let id: UUID
        let capturedAt: Date
    }

    var body: some View {
        FormSheet(title: "Return to Inventory",
            description: "These uninvoiced Items will return to Inventory. Their unpaid charges will be removed. No payment or refund is recorded.",
            primaryAction: FormSheetAction(title: "Confirm Return", isLoading: saving,
                isDisabled: review == nil || operationId != nil, action: confirm),
            secondaryAction: FormSheetAction(title: operationId == nil ? "Cancel" : "Done") { dismiss() },
            error: error) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("\(itemIds.count) item\(itemIds.count == 1 ? "" : "s") → Return to inventory")
                        .font(Typography.body).foregroundStyle(BrandColors.textSecondary)
                    Text(message).font(Typography.small).foregroundStyle(BrandColors.textSecondary)
                        .accessibilityIdentifier("target-return-status")
                }
            }
            .accessibilityIdentifier("target-return-form")
            .task {
                do {
                    for try await value in service.watchUninvoicedReturnReview(projectId: projectId, itemIds: itemIds) {
                        guard !Task.isCancelled else { return }
                        guard let value, value.accountId == accountId, value.projectId == projectId,
                              Set(value.items.map(\.itemId)) == Set(itemIds) else { review = nil; continue }
                        review = value
                    }
                } catch is CancellationError { }
                catch { review = nil; self.error = "Return eligibility is unavailable. Download this Project before trying again." }
            }
            .task(id: requestId) {
                guard requestId != nil, let draft else { return }
                defer { saving = false }
                do {
                    let receipt = try await service.returnUninvoicedItems(draft.payload,
                        operationUUID: draft.id, capturedAt: draft.capturedAt)
                    operationId = receipt.operationId
                } catch is CancellationError { }
                catch { self.error = "Could not confirm this return. Your saved request, if accepted, is retained. Retry uses the same request." }
            }
            .task(id: operationId) {
                guard let operationId else { return }
                do {
                    for try await value in service.watchUninvoicedReturn(operationId) {
                        guard !Task.isCancelled else { return }
                        status = value
                    }
                } catch is CancellationError { }
                catch { self.error = "Return status is unavailable. Your saved work is retained." }
            }
    }

    private func confirm() {
        guard !saving, operationId == nil, let review else { return }
        do {
            if draft == nil { draft = try .init(payload: review.makePayload(), id: UUID(), capturedAt: Date()) }
            error = nil; saving = true; requestId = UUID()
        } catch { self.error = "The selection changed. Close this form and review the Items again." }
    }

    private var message: String {
        guard operationId != nil else {
            return review == nil ? "Waiting for a complete eligible selection. Invoiced or paid Items cannot use this action."
                : "Ready to return. Item identity and history will be preserved."
        }
        switch status?.state.phase {
        case .applied: return "Return applied. Downloaded Item locations will update when sync completes."
        case .rejected: return "Return was not applied. The selection changed or is no longer eligible. Your saved request is retained."
        default: return "Return saved on this device. It will upload when connected."
        }
    }
}
