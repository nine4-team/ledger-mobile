import LedgerTargetCore
import SwiftUI

/// Backend orchestration for MoveToInventoryModal's existing FormSheet controls.
/// Paid and uninvoiced Inventory-origin returns share the existing controls.
struct UninvoicedReturnForm: View {
    let accountId: AccountID
    let projectId: ProjectID
    let itemIds: [ItemID]
    let service: any UninvoicedReturnWorkflowServing
    var sourceService: (any InventorySourceReturnWorkflowServing)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var review: UninvoicedReturnReview?
    @State private var paidReview: PaidReturnReview?
    @State private var sourceReview: InventorySourceReturnReview?
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
            case source(ReturnInventoryItemsToSourcePayload)
        }
        let payload: Payload
        let id: UUID
        let capturedAt: Date
    }

    var body: some View {
        FormSheet(title: sourceService == nil ? "Return to Inventory" : "Return to Project",
            description: sourceService != nil
                ? "Restore each Item to its proven source Project at its saved inventory-entry amount and category. This adds unpaid charges, not a cash Transaction."
                : paidReview == nil
                ? "Eligible Items will return to Inventory. Unpaid charges are removed; paid Items receive a credit. No payment or cash refund is recorded."
                : "These paid Items will return to Inventory and receive credits based on their original Invoice lines. The paid Invoice and payment history stay unchanged. No cash refund is recorded.",
            primaryAction: FormSheetAction(title: "Confirm Return", isLoading: saving,
                isDisabled: (review == nil && paidReview == nil && sourceReview == nil) || operationId != nil, action: confirm),
            secondaryAction: FormSheetAction(title: operationId == nil ? "Cancel" : "Done") { dismiss() },
            error: error) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("\(itemIds.count) item\(itemIds.count == 1 ? "" : "s") → \(sourceService == nil ? "Return to inventory" : "Source Project")")
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
                    if let sourceReview {
                        Text("Source Project: \(sourceReview.projectDisplayName ?? sourceReview.projectId.rawValue)")
                            .accessibilityIdentifier("target-source-return-project")
                        ForEach(sourceReview.items, id: \.itemId) { item in
                            Text("\(item.itemId.rawValue) · \(item.categoryDisplayName ?? item.sourceCategoryId.rawValue) · \((Decimal(item.sourceAmount.minorUnits) / 100).formatted(.currency(code: item.sourceAmount.currency.rawValue)))")
                                .accessibilityIdentifier("target-source-return-basis-\(item.itemId.rawValue)")
                        }
                    }
                }
            }
            .accessibilityIdentifier("target-return-form")
            .task {
                guard sourceService == nil else { return }
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
                guard sourceService == nil, let paidService = service as? any PaidReturnWorkflowServing else { return }
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
            .task {
                guard let sourceService else { return }
                do {
                    for try await value in sourceService.watchInventorySourceReturnReview(itemIds: itemIds) {
                        guard !Task.isCancelled else { return }
                        guard let value, value.accountId == accountId, value.projectId == projectId,
                              Set(value.items.map(\.itemId)) == Set(itemIds) else { sourceReview = nil; continue }
                        sourceReview = value
                    }
                } catch is CancellationError { }
                catch { sourceReview = nil; self.error = "Source return evidence is unavailable. No destination or amount will be guessed." }
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
                    case .source(let payload):
                        guard let sourceService else { return }
                        receipt = try await sourceService.returnInventoryItemsToSource(payload,
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
                    if case .source = draft?.payload, let sourceService {
                        stream = sourceService.watchInventorySourceReturn(operationId)
                    } else if case .paid = draft?.payload, let paidService = service as? any PaidReturnWorkflowServing {
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
        guard !saving, operationId == nil, review != nil || paidReview != nil || sourceReview != nil else { return }
        do {
            if draft == nil {
                if let sourceReview {
                    draft = try .init(payload: .source(sourceReview.makePayload()), id: UUID(), capturedAt: Date())
                } else if let paidReview {
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
            if sourceService != nil {
                return sourceReview == nil ? "Waiting for complete, current source evidence. Sell remains an independent action."
                    : "Ready to restore the saved source, amount and category."
            }
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

/// Existing Item actions remain independent: unavailable Return never hides Sell.
struct InventorySourceReturnSelection: Identifiable {
    let id = UUID()
    let review: InventorySourceReturnReview
}

struct InventorySourceReturnAction: View {
    let review: InventorySourceReturnReview?
    var accessibilityID = "target-items-return-source"
    let present: (InventorySourceReturnReview) -> Void
    var body: some View {
        Button("Return to Project") {
            guard let review else { return }
            present(review)
        }
            .disabled(review == nil)
            .help(review == nil ? "Return requires one proven source Project and complete saved inventory-entry evidence. Sell is independent." : "Restore each saved amount and category")
            .accessibilityIdentifier(accessibilityID)
    }
}
