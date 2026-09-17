import Foundation
import LedgerTargetCore
import Observation

@MainActor @Observable
public final class TransactionReceiptLinesEditSession {
    public var draft: TransactionReceiptLinesEditDraft
    public private(set) var saving = false
    public private(set) var loading = false
    public private(set) var isReady = false
    public private(set) var receipt: OperationReceipt?
    public private(set) var status: OperationSnapshot?
    public private(set) var error: String?
    public var fieldsLocked: Bool { !isReady || attempt != nil || receipt != nil }
    private let service: any TransactionReceiptLinesEditing
    private var attempt: Attempt?
    private struct Attempt {
        let payload: EditTransactionReceiptLinesCommand.Payload
        let uuid: UUID
        let capturedAt: Date
    }

    public init(original: TransactionDetailSnapshot, service: any TransactionReceiptLinesEditing) throws {
        draft = try .init(original: original); self.service = service
    }

    public func loadPending() async {
        guard !isReady, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            if let saved = try await service.pendingTransactionReceiptLinesEdit(
                scope: draft.original.classification.scope, transactionId: draft.original.transactionId) {
                guard saved.payload.scope == draft.original.classification.scope,
                      saved.payload.transactionId == draft.original.transactionId,
                      saved.payload.currency == draft.original.amount.currency else {
                    throw EditTransactionReceiptLinesCommand.Failure.invalidEnvelope
                }
                draft.entries = saved.payload.lines.map { ReceiptLineEntry(line: $0) }
                receipt = saved.receipt
            }
            isReady = true; error = nil
        } catch is CancellationError {} catch {
            self.error = "Saved receipt edits could not be checked. Save Changes retries the check."
        }
    }

    /// Only an unchanged draft closes without a write. An uncertain save retains
    /// the exact payload and identity, even if a caller later changes a binding.
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
            receipt = try await service.editTransactionReceiptLines(attempt.payload,
                operationUUID: attempt.uuid, capturedAt: attempt.capturedAt)
            error = nil
        } catch is CancellationError {
            error = "Save was interrupted. Retry confirms the same receipt edit."
        } catch {
            self.error = attempt == nil
                ? "Check each line's description, positive amount and optional whole-number quantity. Your edits are retained."
                : "The receipt edit could not be confirmed. Retry saves the same edit without duplicating it."
        }
        return false
    }

    public func observeStatus() async {
        guard let receipt else { return }
        do {
            for try await value in service.watchTransactionReceiptLinesEdit(receipt.operationId) {
                try Task.checkCancellation()
                status = value
            }
        } catch is CancellationError {} catch {
            self.error = "Receipt edit status is unavailable. Your saved edit is retained."
        }
    }

    public var hint: String? {
        guard receipt != nil else { return nil }
        switch status?.state.localState ?? receipt?.localState {
        case .applied: return "Receipt lines saved to the server. Updated details appear when they sync."
        case .rejected: return "The edit was not applied. Your saved receipt lines are retained for review."
        default: return "Saved on this device. Waiting to sync."
        }
    }
}
