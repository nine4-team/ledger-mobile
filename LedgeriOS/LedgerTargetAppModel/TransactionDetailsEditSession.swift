import Foundation
import LedgerTargetCore
import Observation

@MainActor @Observable
public final class TransactionDetailsEditSession {
    public var draft: TransactionDetailsEditDraft
    public private(set) var saving = false
    public private(set) var loading = false
    public private(set) var isReady = false
    public private(set) var receipt: OperationReceipt?
    public private(set) var status: OperationSnapshot?
    public private(set) var error: String?
    public var fieldsLocked: Bool { !isReady || attempt != nil || receipt != nil }
    private let service: any TransactionDetailsEditing
    private var attempt: Attempt?
    private struct Attempt {
        let payload: EditTransactionDetailsCommand.Payload
        let uuid: UUID
        let capturedAt: Date
    }

    public init(original: TransactionDetailSnapshot, service: any TransactionDetailsEditing) {
        draft = .init(original: original); self.service = service
    }

    public func loadPending() async {
        guard !isReady, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            if let saved = try await service.pendingTransactionDetailsEdit(scope: draft.original.classification.scope,
                                                                          transactionId: draft.original.transactionId) {
                guard saved.payload.scope == draft.original.classification.scope,
                      saved.payload.transactionId == draft.original.transactionId else {
                    throw EditTransactionDetailsCommand.Failure.invalidEnvelope
                }
                func restored(_ change: EditTransactionDetailsCommand.TextChange?, fallback: String) -> String {
                    switch change { case .set(let value): value; case .clear: ""; case nil: fallback }
                }
                draft.source = restored(saved.payload.changes.source, fallback: draft.source)
                draft.notes = restored(saved.payload.changes.notes, fallback: draft.notes)
                draft.paymentMethod = restored(saved.payload.changes.paymentMethod, fallback: draft.paymentMethod)
                if let email = saved.payload.changes.hasEmailReceipt { draft.hasEmailReceipt = email }
                receipt = saved.receipt
            }
            isReady = true; error = nil
        } catch is CancellationError {} catch {
            self.error = "Saved edits could not be checked. Save Changes retries the check before creating an edit."
        }
    }

    /// True only for unchanged Save, so the sheet can close without a write.
    /// An uncertain response retains the exact attempt; retry never changes its identity.
    public func save() async -> Bool {
        guard !saving, !loading, receipt == nil else { return false }
        await loadPending()
        guard isReady, receipt == nil else { return false }
        do {
            if attempt == nil {
                guard let payload = try draft.payload() else { return true }
                attempt = .init(payload: payload, uuid: UUID(), capturedAt: Date())
            }
            guard let attempt else { return false }
            saving = true
            defer { saving = false }
            receipt = try await service.editTransactionDetails(attempt.payload,
                operationUUID: attempt.uuid, capturedAt: attempt.capturedAt)
            error = nil
        } catch is CancellationError {
            error = "Save was interrupted. Retry confirms the same edit."
        } catch {
            self.error = "The edit could not be confirmed. Retry saves the same edit without duplicating it."
        }
        return false
    }

    public func observeStatus() async {
        guard let receipt else { return }
        do {
            for try await value in service.watchTransactionDetailsEdit(receipt.operationId) {
                try Task.checkCancellation()
                status = value
            }
        } catch is CancellationError {} catch {
            self.error = "Edit status is unavailable. Your saved edit is retained."
        }
    }

    public var hint: String? {
        guard receipt != nil else { return nil }
        switch status?.state.localState ?? receipt?.localState {
        case .applied: return "Transaction updated. Other devices will receive it when they sync."
        case .rejected: return "The edit was not applied. Your saved operation is retained for review."
        default: return "Saved on this device. Waiting to sync."
        }
    }
}
