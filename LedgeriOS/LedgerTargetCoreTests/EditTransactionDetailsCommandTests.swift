import Foundation
import Testing
@testable import LedgerTargetCore

struct EditTransactionDetailsCommandTests {
    private func snapshot(revision: String? = "1") throws -> TransactionDetailSnapshot {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("LedgerTargetMCP/tests/fixtures/transaction-detail.json"))
        var wire = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        wire["detailsRevision"] = revision
        return try JSONDecoder().decode(TransactionDetailSnapshot.self, from: JSONSerialization.data(withJSONObject: wire))
    }
    private func command(_ changes: EditTransactionDetailsCommand.Changes,
                         revision: Int64 = 1) throws -> EditTransactionDetailsCommand {
        let row = try snapshot()
        return try .init(operationId: .init(validating: "edit-details"), actorPrincipalId: row.principalId,
            capturedAt: Date(timeIntervalSince1970: 100), payload: .init(transactionId: row.transactionId,
                scope: row.classification.scope, expectedRevision: revision, changes: changes))
    }

    @Test func omittedClearFalseAndVerbatimTextRoundTrip() throws {
        let value = try command(.init(source: .clear, notes: .set("  Exact\n🪑  "), hasEmailReceipt: false))
        let bytes = try OperationContractCodec.encode(value)
        let restored = try OperationContractCodec.decode(EditTransactionDetailsCommand.self, from: bytes)
        #expect(restored.envelope.payload == value.envelope.payload)
        #expect(restored.envelope.payload.changes.paymentMethod == nil)
        #expect(restored.envelope.payload.changes.source == .clear)
        #expect(restored.envelope.payload.changes.hasEmailReceipt == false)
        #expect(try OperationContractCodec.encode(restored) == bytes)
    }

    @Test func unchangedDraftDoesNotWriteOrNormalizeEvidence() throws {
        let row = try snapshot()
        var draft = TransactionDetailsEditDraft(original: row)
        #expect(try draft.payload() == nil)
        draft.notes = "  New notes\n  "
        let changes = try #require(try draft.payload()).changes
        #expect(changes.notes == .set("  New notes\n  "))
        #expect(changes.source == nil && changes.paymentMethod == nil && changes.hasEmailReceipt == nil)
        #expect(draft.original == row)
    }

    @Test func invalidIntentAndDecodedRevisionAreRejected() throws {
        #expect(throws: EditTransactionDetailsCommand.Failure.emptyChanges) { try command(.init()) }
        #expect(throws: EditTransactionDetailsCommand.Failure.unrepresentableText) {
            try command(.init(notes: .set("bad\0text")))
        }
        for revision: Int64 in [0, -1, Int64.max] {
            #expect(throws: EditTransactionDetailsCommand.Failure.invalidRevision) {
                try command(.init(notes: .clear), revision: revision)
            }
        }
        let bytes = try OperationContractCodec.encode(command(.init(notes: .clear)))
        let invalid = String(decoding: bytes, as: UTF8.self)
            .replacingOccurrences(of: "\"expectedRevision\":1", with: "\"expectedRevision\":0")
        #expect(throws: EditTransactionDetailsCommand.Failure.invalidRevision) {
            try OperationContractCodec.decode(EditTransactionDetailsCommand.self, from: Data(invalid.utf8))
        }
    }

    @Test func clearingTextDoesNotClearUnchangedFields() throws {
        var draft = TransactionDetailsEditDraft(original: try snapshot())
        draft.source = ""; draft.paymentMethod = ""
        let changes = try #require(try draft.payload()).changes
        #expect(changes.source == .clear && changes.paymentMethod == .clear)
        #expect(changes.notes == nil && changes.hasEmailReceipt == nil)
        draft.hasEmailReceipt = nil
        #expect(try draft.payload()?.changes.hasEmailReceipt == nil)
    }

    @Test func saveUsesDownloadedRevisionAndCannotInventOne() throws {
        var missing = TransactionDetailsEditDraft(original: try snapshot(revision: nil))
        #expect(try missing.payload() == nil)
        missing.notes = "Changed"
        #expect(throws: EditTransactionDetailsCommand.Failure.invalidRevision) { try missing.payload() }
        var known = TransactionDetailsEditDraft(original: try snapshot(revision: "9007199254740993"))
        known.notes = "Changed"
        #expect(try known.payload()?.expectedRevision == 9_007_199_254_740_993)
    }

    @Test func importedPaymentDraftCannotBypassExistingHistoryLock() throws {
        var wire = try TransactionDetailSnapshotTests.fixture()
        wire["origin"] = "firebase_client_payment"; wire["type"] = "purchase"
        wire["scopeKind"] = "project"; wire["projectId"] = "project"; wire["clientId"] = "client"
        wire["category"] = NSNull(); wire["detailsRevision"] = "1"
        var draft = TransactionDetailsEditDraft(original: try TransactionDetailSnapshotTests.decode(wire))
        #expect(try draft.payload() == nil)
        draft.notes = "Changed"
        #expect(throws: EditTransactionDetailsCommand.Failure.immutableTransaction) { try draft.payload() }
    }

    @Test func decodedAccountAndContractCannotChangeIntent() throws {
        let bytes = try OperationContractCodec.encode(command(.init(notes: .clear)))
        let object = try #require(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let envelope = try #require(object["envelope"] as? [String: Any])
        for (field, value) in [("accountId", "other-account"), ("contractVersion", "other-command-v1")] {
            var changed = envelope; changed[field] = value
            let tampered = try JSONSerialization.data(withJSONObject: ["envelope": changed])
            #expect(throws: EditTransactionDetailsCommand.Failure.invalidEnvelope) {
                try OperationContractCodec.decode(EditTransactionDetailsCommand.self, from: tampered)
            }
        }
    }
}
