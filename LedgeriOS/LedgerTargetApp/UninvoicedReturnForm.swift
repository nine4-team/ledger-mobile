import LedgerTargetCore
import SwiftUI

/// Backend orchestration for MoveToInventoryModal's existing FormSheet controls.
/// Paid and uninvoiced Inventory-origin returns share the existing controls.
struct UninvoicedReturnForm: View {
    let accountId: AccountID
    let projectId: ProjectID
    let itemIds: [ItemID]
    let service: any UninvoicedReturnWorkflowServing
    @Environment(\.dismiss) private var dismiss
    @State private var review: UninvoicedReturnReview?
    @State private var paidReview: PaidReturnReview?
    @State private var draft: Draft?
    @State private var requestId: UUID?
    @State private var saving = false
    @State private var error: String?
    @State private var operationId: OperationID?
    @State private var status: OperationSnapshot?
    private struct Draft {
        enum Payload {
            case uninvoiced(ReturnUninvoicedItemsPayload)
            case paid(ReturnPaidItemsPayload)
        }
        let payload: Payload
        let id: UUID
        let capturedAt: Date
    }

    var body: some View {
        FormSheet(title: "Return to Inventory",
            description: paidReview == nil
                ? "Eligible Items will return to Inventory. Unpaid charges are removed; paid Items receive a credit. No payment or cash refund is recorded."
                : "These paid Items will return to Inventory and receive credits based on their original Invoice lines. The paid Invoice and payment history stay unchanged. No cash refund is recorded.",
            primaryAction: FormSheetAction(title: "Confirm Return", isLoading: saving,
                isDisabled: (review == nil && paidReview == nil) || operationId != nil, action: confirm),
            secondaryAction: FormSheetAction(title: operationId == nil ? "Cancel" : "Done") { dismiss() },
            error: error) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("\(itemIds.count) item\(itemIds.count == 1 ? "" : "s") → Return to inventory")
                        .font(Typography.body).foregroundStyle(BrandColors.textSecondary)
                    Text(message).font(Typography.small).foregroundStyle(BrandColors.textSecondary)
                        .accessibilityIdentifier("target-return-status")
                    if let paidReview {
                        ForEach(paidReview.items, id: \.itemId) { item in
                            Text("Credit: \((Decimal(-item.paidAmount.minorUnits) / 100).formatted(.currency(code: item.paidAmount.currency.rawValue)))")
                                .font(Typography.body)
                                .accessibilityIdentifier("target-return-credit-\(item.itemId.rawValue)")
                        }
                    }
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
            .task {
                guard let paidService = service as? any PaidReturnWorkflowServing else { return }
                do {
                    for try await value in paidService.watchPaidReturnReview(projectId: projectId, itemIds: itemIds) {
                        guard !Task.isCancelled else { return }
                        guard let value, value.accountId == accountId, value.projectId == projectId,
                              Set(value.items.map(\.itemId)) == Set(itemIds) else { paidReview = nil; continue }
                        paidReview = value
                    }
                } catch is CancellationError { }
                catch { paidReview = nil }
            }
            .task(id: requestId) {
                guard requestId != nil, let draft else { return }
                defer { saving = false }
                do {
                    let receipt: OperationReceipt
                    switch draft.payload {
                    case .uninvoiced(let payload):
                        receipt = try await service.returnUninvoicedItems(payload,
                            operationUUID: draft.id, capturedAt: draft.capturedAt)
                    case .paid(let payload):
                        guard let paidService = service as? any PaidReturnWorkflowServing else { return }
                        receipt = try await paidService.returnPaidItems(payload,
                            operationUUID: draft.id, capturedAt: draft.capturedAt)
                    }
                    operationId = receipt.operationId
                } catch is CancellationError { }
                catch { self.error = "Could not confirm this return. Your saved request, if accepted, is retained. Retry uses the same request." }
            }
            .task(id: operationId) {
                guard let operationId else { return }
                do {
                    let stream: AsyncThrowingStream<OperationSnapshot?, Error>
                    if case .paid = draft?.payload, let paidService = service as? any PaidReturnWorkflowServing {
                        stream = paidService.watchPaidReturn(operationId)
                    } else { stream = service.watchUninvoicedReturn(operationId) }
                    for try await value in stream {
                        guard !Task.isCancelled else { return }
                        status = value
                    }
                } catch is CancellationError { }
                catch { self.error = "Return status is unavailable. Your saved work is retained." }
            }
    }

    private func confirm() {
        guard !saving, operationId == nil, review != nil || paidReview != nil else { return }
        do {
            if draft == nil {
                if let paidReview {
                    draft = try .init(payload: .paid(paidReview.makePayload()), id: UUID(), capturedAt: Date())
                } else if let review {
                    draft = try .init(payload: .uninvoiced(review.makePayload()), id: UUID(), capturedAt: Date())
                }
            }
            error = nil; saving = true; requestId = UUID()
        } catch { self.error = "The selection changed. Close this form and review the Items again." }
    }

    private var message: String {
        guard operationId != nil else {
            return review == nil && paidReview == nil ? "Waiting for a complete eligible selection. Select uninvoiced or paid Items separately; Items on an unpaid Invoice must be removed from that Invoice first."
                : "Ready to return. Item identity and history will be preserved."
        }
        switch status?.state.phase {
        case .applied: return "Return applied. Downloaded Item locations will update when sync completes."
        case .rejected: return "Return was not applied. The selection changed or is no longer eligible. Your saved request is retained."
        default: return "Return saved on this device. It will upload when connected."
        }
    }
}
