import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetAppModel

@MainActor struct TransactionDetailsEditSessionTests {
    @Test func unchangedAndCancelledDraftDoNotWrite() async throws {
        let service = Editor()
        let row = try TransactionBrowserSessionTests.row("transaction", ["detailsRevision": "7"])
        let session = TransactionDetailsEditSession(original: row, service: service)
        #expect(await session.save())
        #expect(await service.count == 0)
        let cancelled = TransactionDetailsEditSession(original: row, service: service)
        cancelled.draft.notes = "Unsaved"
        #expect(await service.count == 0)
        #expect(session.receipt == nil && !session.fieldsLocked)
    }

    @Test func uncertainSaveRetainsExactAttemptAndAcceptedSaveCannotDuplicate() async throws {
        let service = Editor(failFirst: true)
        let row = try TransactionBrowserSessionTests.row("transaction", ["detailsRevision": "7"])
        let session = TransactionDetailsEditSession(original: row, service: service)
        session.draft.notes = "Exact edit"
        #expect(!(await session.save()))
        #expect(session.error != nil && !session.saving && session.fieldsLocked && session.receipt == nil)
        // Even if a caller changes a binding, retry is the original immutable attempt.
        session.draft.notes = "Not part of retry"
        #expect(!(await session.save()))
        #expect(await service.sameAttempts)
        #expect(session.receipt?.localState == .queued && session.error == nil)
        #expect(session.hint == "Saved on this device. Waiting to sync.")
        #expect(!(await session.save()))
        #expect(await service.count == 2)
    }

    @Test func validationFailureKeepsDraftWithoutCallingProvider() async throws {
        let service = Editor()
        let session = TransactionDetailsEditSession(original:
            try TransactionBrowserSessionTests.row("transaction", ["detailsRevision": NSNull()]), service: service)
        session.draft.notes = "Retain this"
        #expect(!(await session.save()))
        #expect(session.error != nil && session.draft.notes == "Retain this" && !session.fieldsLocked)
        #expect(await service.count == 0)
    }

    @Test func recoveredTerminalReceiptIsNotShownAsPending() async throws {
        for state: LocalOperationState in [.applied, .rejected] {
            let service = Editor(acceptedState: state)
            let session = TransactionDetailsEditSession(original:
                try TransactionBrowserSessionTests.row("transaction", ["detailsRevision": "7"]), service: service)
            session.draft.notes = "Changed"
            #expect(!(await session.save()))
            #expect(session.hint == (state == .applied
                ? "Transaction updated. Other devices will receive it when they sync."
                : "The edit was not applied. Your saved operation is retained for review."))
        }
    }

    @Test func reopeningRestoresPendingValuesAndCannotCreateAnotherEdit() async throws {
        let row = try TransactionBrowserSessionTests.row("transaction", ["detailsRevision": "7"])
        let pending = PendingTransactionDetailsEdit(payload: try .init(transactionId: row.transactionId,
            scope: row.classification.scope, expectedRevision: 7,
            changes: .init(notes: .set("Saved notes"), paymentMethod: .clear, hasEmailReceipt: false)),
            receipt: .init(operationId: try .init(validating: "saved-edit"), localState: .rejected))
        let service = Editor(pending: pending)
        let session = TransactionDetailsEditSession(original: row, service: service)
        #expect(session.fieldsLocked)
        await session.loadPending()
        #expect(session.draft.notes == "Saved notes" && session.draft.paymentMethod == "" && session.draft.hasEmailReceipt == false)
        #expect(session.fieldsLocked && session.receipt == pending.receipt)
        #expect(!(await session.save()))
        #expect(await service.count == 0)
    }

    private actor Editor: TransactionDetailsEditing {
        struct Attempt: Equatable { let payload: EditTransactionDetailsCommand.Payload; let id: UUID; let date: Date }
        enum Failure: Error { case uncertain }
        var attempts: [Attempt] = []
        let failFirst: Bool
        let acceptedState: LocalOperationState
        let pending: PendingTransactionDetailsEdit?
        init(failFirst: Bool = false, acceptedState: LocalOperationState = .queued, pending: PendingTransactionDetailsEdit? = nil) {
            self.failFirst = failFirst; self.acceptedState = acceptedState
            self.pending = pending
        }
        var count: Int { attempts.count }
        var sameAttempts: Bool { attempts.count == 2 && attempts[0] == attempts[1] }
        func editTransactionDetails(_ payload: EditTransactionDetailsCommand.Payload, operationUUID: UUID,
                                    capturedAt: Date) async throws -> OperationReceipt {
            attempts.append(.init(payload: payload, id: operationUUID, date: capturedAt))
            if failFirst && attempts.count == 1 { throw Failure.uncertain }
            return .init(operationId: try .init(validating: "edit-test"), localState: acceptedState)
        }
        func transactionDetailsEditStatus(_ operationId: OperationID) async throws -> OperationSnapshot? { nil }
        func pendingTransactionDetailsEdit(scope: TransactionScope, transactionId: TransactionID) async throws -> PendingTransactionDetailsEdit? { pending }
        nonisolated func watchTransactionDetailsEdit(_ operationId: OperationID) -> AsyncThrowingStream<OperationSnapshot?, Error> {
            AsyncThrowingStream { $0.finish() }
        }
    }
}
