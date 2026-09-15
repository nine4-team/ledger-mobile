import Foundation
import LedgerTargetCore
import LedgerTargetAppModel
import Testing

@Suite("Transaction audit live read state")
@MainActor
struct TransactionReceiptAuditSessionTests {
    private func receipt(_ edit: (inout [String: Any]) -> Void = { _ in }) throws -> TransactionReceiptSnapshot {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
            root.appendingPathComponent("LedgerTargetMCP/tests/fixtures/transaction-receipt.json"))) as? [String: Any])
        edit(&json)
        return try JSONDecoder().decode(TransactionReceiptSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func session(_ value: TransactionReceiptSnapshot,
                         watch: @escaping @Sendable () -> AsyncThrowingStream<TransactionReceiptUpdate, Error> = {
                             AsyncThrowingStream { $0.finish() }
                         }) -> TransactionReceiptAuditSession {
        TransactionReceiptAuditSession(scope: value.classification.scope, principalId: value.principalId,
            transactionId: value.transactionId, locale: Locale(identifier: "en_US"), watch: watch)
    }

    @Test func currentCategoryAndIncompleteOrWithdrawnReadsReplacePriorValues() throws {
        let value = try receipt()
        let model = session(value)
        try model.receive(.ready(value))
        #expect(model.state == .ready && model.presentation?.isComplete == true)
        let general = try receipt { json in
            var category = json["category"] as! [String: Any]
            category["kind"] = "general"; json["category"] = category
        }
        try model.receive(.ready(general))
        #expect(model.presentation?.isApplicable == false)
        for update in [TransactionReceiptUpdate.incomplete, .unavailable] {
            try model.receive(.ready(value))
            try model.receive(update)
            #expect(model.receipt == nil && model.presentation == nil)
        }
        #expect(model.state == .unavailable)
        try model.receive(.ready(value))
        model.invalidate()
        #expect(model.state == .unavailable && model.receipt == nil && model.presentation == nil)
    }

    @Test func everyBoundIdentityMismatchClearsFinancialValues() throws {
        let value = try receipt()
        for key in ["accountId", "principalId", "transactionId", "projectId", "clientId"] {
            let model = session(value)
            try model.receive(.ready(value))
            let foreign = try receipt { $0[key] = "foreign" }
            #expect(throws: TransactionReceiptSnapshot.Failure.scopeMismatch) {
                try model.receive(.ready(foreign))
            }
            #expect(model.state == .failed && model.receipt == nil && model.presentation == nil)
        }
    }

    @Test func completionFailureAndCancellationClearLastSnapshot() async throws {
        let value = try receipt()
        for failed in [false, true] {
            let model = session(value) {
                AsyncThrowingStream { continuation in
                    continuation.yield(.ready(value))
                    if failed { continuation.finish(throwing: InjectedFailure()) }
                    else { continuation.finish() }
                }
            }
            await model.observe()
            #expect(model.state == (failed ? .failed : .unavailable))
            #expect(model.receipt == nil && model.presentation == nil)
        }
        let (stream, continuation) = AsyncThrowingStream<TransactionReceiptUpdate, Error>.makeStream()
        let model = session(value) { stream }
        let task = Task { await model.observe() }
        continuation.yield(.ready(value))
        try await waitFor { model.state == .ready }
        task.cancel()
        await task.value
        #expect(model.state == .unavailable && model.receipt == nil && model.presentation == nil)
    }

    @Test func invalidationRejectsBufferedOldUpdates() async throws {
        let value = try receipt()
        let (stream, continuation) = AsyncThrowingStream<TransactionReceiptUpdate, Error>.makeStream()
        let model = session(value) { stream }
        let task = Task { await model.observe() }
        defer { task.cancel(); continuation.finish() }
        continuation.yield(.ready(value))
        try await waitFor { model.state == .ready }
        model.invalidate()
        continuation.yield(.ready(value))
        continuation.finish()
        await task.value
        #expect(model.state == .unavailable && model.receipt == nil && model.presentation == nil)
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        try #require(condition(), "Expected local stream update did not arrive")
    }
}

private struct InjectedFailure: Error {}
