import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetAppModel

@MainActor struct TransactionReceiptLinesEditSessionTests {
    private func original() throws -> TransactionDetailSnapshot {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let receipt = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
            root.appendingPathComponent("LedgerTargetMCP/tests/fixtures/transaction-receipt.json"))) as? [String: Any])
        var detail = receipt
        detail["origin"] = "vendor_payment"; detail["role"] = "standalone"; detail["receipt"] = receipt
        return try JSONDecoder().decode(TransactionDetailSnapshot.self, from: JSONSerialization.data(withJSONObject: detail))
    }

    @Test func unchangedAndInvalidDraftsDoNotWrite() async throws {
        let editor = Editor(), session = try TransactionReceiptLinesEditSession(original: original(), service: editor)
        #expect(await session.save())
        session.draft.entries[0].amountText = "0"
        #expect(!(await session.save()))
        #expect(session.error != nil && !session.fieldsLocked && session.draft.entries[0].amountText == "0")
        #expect(await editor.attempts.isEmpty)
    }

    @Test func mismatchSaveAndUncertainRetryKeepOneExactAttempt() async throws {
        let row = try original(), editor = Editor(failFirst: true)
        let session = try TransactionReceiptLinesEditSession(original: row, service: editor)
        session.draft.entries[0].amountText = "1.01"
        #expect(!(await session.save()))
        #expect(session.receipt == nil && session.fieldsLocked && session.error != nil)
        session.draft.entries.removeAll()
        #expect(!(await session.save()))
        let attempts = await editor.attempts
        #expect(attempts.count == 2 && attempts[0] == attempts[1])
        #expect(attempts[0].payload.lines[0].magnitude.minorUnits == 101)
        #expect(attempts[0].payload.expectedLines == row.receipt?.lines)
        #expect(session.receipt?.localState == .queued && session.error == nil)
        #expect(!(await session.save()))
        #expect(await editor.attempts.count == 2)
    }

    @Test func pendingClearIsRestoredAndRejectedWorkCannotBeOverwritten() async throws {
        let row = try original()
        let pending = PendingTransactionReceiptLinesEdit(payload: try .init(transactionId: row.transactionId,
            scope: row.classification.scope, currency: row.amount.currency,
            expectedLines: try #require(row.receipt).lines, lines: []),
            receipt: .init(operationId: try .init(validating: "saved"), localState: .rejected))
        let editor = Editor(pending: pending)
        let session = try TransactionReceiptLinesEditSession(original: row, service: editor)
        await session.loadPending()
        #expect(session.draft.entries.isEmpty && session.fieldsLocked && session.receipt == pending.receipt)
        #expect(session.hint?.contains("retained for review") == true)
        #expect(!(await session.save()))
        #expect(await editor.attempts.isEmpty)
    }

    @Test func failedPendingLookupDoesNotAdmitNewWorkAndRetries() async throws {
        let editor = Editor(failPendingFirst: true)
        let session = try TransactionReceiptLinesEditSession(original: original(), service: editor)
        session.draft.entries.removeAll()
        #expect(!(await session.save()))
        #expect(!session.isReady && session.fieldsLocked && session.error != nil)
        #expect(await editor.attempts.isEmpty)
        #expect(!(await session.save()))
        #expect(session.receipt?.localState == .queued)
        #expect(await editor.attempts.count == 1)
    }

    private actor Editor: TransactionReceiptLinesEditing {
        struct Attempt: Equatable { let payload: EditTransactionReceiptLinesCommand.Payload; let uuid: UUID; let date: Date }
        enum Failure: Error { case uncertain }
        var attempts: [Attempt] = []
        var pendingReads = 0
        let failFirst: Bool, failPendingFirst: Bool
        let pending: PendingTransactionReceiptLinesEdit?
        init(failFirst: Bool = false, failPendingFirst: Bool = false, pending: PendingTransactionReceiptLinesEdit? = nil) {
            self.failFirst = failFirst; self.failPendingFirst = failPendingFirst; self.pending = pending
        }
        func editTransactionReceiptLines(_ payload: EditTransactionReceiptLinesCommand.Payload,
            operationUUID: UUID, capturedAt: Date) async throws -> OperationReceipt {
            attempts.append(.init(payload: payload, uuid: operationUUID, date: capturedAt))
            if failFirst && attempts.count == 1 { throw Failure.uncertain }
            return .init(operationId: try .init(validating: "saved"), localState: .queued)
        }
        func pendingTransactionReceiptLinesEdit(scope: TransactionScope,
            transactionId: TransactionID) async throws -> PendingTransactionReceiptLinesEdit? {
            pendingReads += 1
            if failPendingFirst && pendingReads == 1 { throw Failure.uncertain }
            return pending
        }
        nonisolated func watchTransactionReceiptLinesEdit(_ operationId: OperationID) -> AsyncThrowingStream<OperationSnapshot?, Error> {
            AsyncThrowingStream { $0.finish() }
        }
    }
}
