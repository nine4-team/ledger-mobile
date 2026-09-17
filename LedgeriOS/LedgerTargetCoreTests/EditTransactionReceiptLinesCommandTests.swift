import Foundation
import Testing
@testable import LedgerTargetCore

struct EditTransactionReceiptLinesCommandTests {
    private func snapshot() throws -> TransactionDetailSnapshot {
        let receipt = try TransactionReceiptSnapshotTests.fixture()
        var detail = receipt
        detail["role"] = "standalone"; detail["origin"] = "vendor_payment"
        detail["receipt"] = receipt
        return try TransactionDetailSnapshotTests.decode(detail)
    }

    @Test func unchangedClearAndMismatchPreserveReviewedEvidence() throws {
        let original = try snapshot()
        var draft = try TransactionReceiptLinesEditDraft(original: original)
        #expect(try draft.payload() == nil)
        draft.entries[0].amountText = "1.01"
        let changed = try #require(try draft.payload())
        #expect(changed.lines[0].magnitude.minorUnits == 101)
        #expect(changed.expectedLines == original.receipt?.lines)
        #expect(changed.lines.map(\.id) == original.receipt?.lines.map(\.id))
        #expect(original.receipt?.auditStatus == .balanced)
        // A one-cent mismatch is editable receipt evidence, not a save rejection.
        draft.entries = []
        #expect(try draft.payload()?.lines.isEmpty == true)
        #expect(draft.original == original)
    }

    @Test func commandRoundTripAndDuplicateIdentityDenial() throws {
        var draft = try TransactionReceiptLinesEditDraft(original: snapshot())
        draft.entries.reverse()
        let payload = try #require(try draft.payload())
        let command = try EditTransactionReceiptLinesCommand(operationId: .init(validating: "receipt-edit"),
            actorPrincipalId: draft.original.principalId, capturedAt: Date(timeIntervalSince1970: 100), payload: payload)
        let bytes = try OperationContractCodec.encode(command)
        let restored = try OperationContractCodec.decode(EditTransactionReceiptLinesCommand.self, from: bytes)
        #expect(restored.envelope.payload == payload)
        #expect(try OperationContractCodec.encode(restored) == bytes)
        draft.entries.append(draft.entries[0])
        #expect(throws: EditTransactionReceiptLinesCommand.Failure.duplicateLine) { try draft.payload() }
    }

    @Test func unknownReceiptIsNotAnEmptyEditableReceipt() throws {
        let row = try TransactionDetailSnapshotTests.decode(TransactionDetailSnapshotTests.fixture())
        #expect(throws: EditTransactionReceiptLinesCommand.Failure.incompleteEvidence) {
            try TransactionReceiptLinesEditDraft(original: row)
        }
    }
}
