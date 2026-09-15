import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetPowerSync

@Suite("Transaction export authorization and scratch handoff", .serialized, .timeLimit(.minutes(1)))
@MainActor struct TransactionExportDeliveryTests {
    enum Failure: Error { case denied, system }
    struct Reader: TransactionExportReading {
        let snapshot: TransactionExportSnapshot
        var denied = false
        func readTransactionExport(scope: TransactionScope, orderedTransactionIDs: [TransactionID]?,
                                   asOf: ProtectedArtifactEpochMilliseconds) async throws -> TransactionExportSnapshot {
            if denied { throw Failure.denied }
            #expect(scope == snapshot.scope && asOf == snapshot.asOf)
            #expect(orderedTransactionIDs == nil)
            return snapshot
        }
    }

    @Test(arguments: ["source", "principal", "visibility", "selection", "denied"])
    func rejectsChangedOrDeniedReadback(_ change: String) async throws {
        let original = try fixture()
        let current = try fixture(notes: change == "source" ? "Changed" : "Original",
            principal: change == "principal" ? "replacement" : "principal",
            visibility: change == "visibility" ? "restricted" : "full", emptySelection: change == "selection")
        do {
            try await TransactionExportDelivery.deliver(data: Data("ID,Amount\ntransaction,10.00".utf8),
                snapshot: original, reader: Reader(snapshot: current, denied: change == "denied")) { _ in
                Issue.record("Changed or unauthorized export reached system handoff")
            }
            Issue.record("Expected rejection")
        } catch TransactionExportDeliveryFailure.snapshotChanged { #expect(change != "denied") }
        catch Failure.denied { #expect(change == "denied") }
    }

    @Test(arguments: [false, true])
    func retainsBytesUntilSystemCompletion(fails: Bool) async throws {
        let snapshot = try fixture(), bytes = Data("ID,Amount\ntransaction,10.00".utf8)
        let entered = AsyncStream<URL>.makeStream(), finish = AsyncStream<Void>.makeStream()
        let task = Task {
            try await TransactionExportDelivery.deliver(data: bytes, snapshot: snapshot, reader: Reader(snapshot: snapshot)) { url in
                entered.continuation.yield(url)
                await Task.detached { for await _ in finish.stream { break } }.value
                #expect(FileManager.default.fileExists(atPath: url.path))
                if fails { throw Failure.system }
            }
        }
        var iterator = entered.stream.makeAsyncIterator()
        let url = try #require(await iterator.next())
        #expect(url.pathExtension == "csv")
        #expect(try Data(contentsOf: url) == bytes)
        task.cancel()
        #expect(FileManager.default.fileExists(atPath: url.path))
        finish.continuation.yield(()); finish.continuation.finish()
        do { try await task.value; #expect(!fails) }
        catch Failure.system { #expect(fails) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
        entered.continuation.finish()
    }

    private func fixture(notes: String = "Original", principal: String = "principal", visibility: String = "full",
                         emptySelection: Bool = false) throws -> TransactionExportSnapshot {
        let wire: [String: Any] = ["accountId": "account", "principalId": principal, "transactionId": "transaction",
            "scopeKind": "project", "projectId": "project", "clientId": "client", "type": "purchase", "role": "standalone",
            "origin": "firebase_client_payment", "category": NSNull(), "amountMinorUnits": "1000", "currency": "USD", "notes": notes]
        let row = try JSONDecoder().decode(TransactionDetailSnapshot.self, from: JSONSerialization.data(withJSONObject: wire))
        return try .init(scope: row.classification.scope, principalId: row.principalId, update: .ready([row]),
            orderedTransactionIDs: emptySelection ? [] : nil, asOf: .init(validating: 1_800_000_000_000),
            sourceVersion: .init(validating: "export-1"), visibilityScopeID: .make(bytes: Data(visibility.utf8)),
            authorityVersion: .init(validating: "transaction-export-v1"))
    }
}

@Suite("Transaction PDF protected delivery", .serialized, .timeLimit(.minutes(1)))
@MainActor struct TransactionAttachmentPDFDeliveryTests {
    struct Reader: DownloadedTransactionAttachmentReading {
        let current: DownloadedTransactionAttachments
        var denied = false
        func watchDownloadedTransactionAttachments(scope: TransactionScope, transactionId: TransactionID,
            section: TransactionAttachmentSection) -> AsyncThrowingStream<DownloadedTransactionAttachments?, Error> {
            AsyncThrowingStream { $0.finish() }
        }
        func readDownloadedTransactionAttachments(scope: TransactionScope, transactionId: TransactionID,
            section: TransactionAttachmentSection) async throws -> DownloadedTransactionAttachments {
            if denied { throw DownloadedTransactionAttachments.Failure.unavailable }
            return current
        }
        func loadDownloadedTransactionAttachment(catalog: DownloadedTransactionAttachments,
            attachment: DownloadedTransactionAttachment, allowDownload: Bool) async throws -> Data? { nil }
    }

    @Test(arguments: ["revision", "transaction", "section", "reference", "denied", "bytes"])
    func rejectsChangedEvidence(change: String) async throws {
        let (catalog, bytes) = try fixture()
        let current = try DownloadedTransactionAttachments(scope: catalog.scope,
            transactionId: .init(validating: change == "transaction" ? "other" : "transaction"),
            section: change == "section" ? .other : .receipts, revision: change == "revision" ? 2 : 1,
            isComplete: true, attachments: change == "reference" ? [] : catalog.attachments)
        await #expect(throws: (any Error).self) {
            try await TransactionAttachmentPDFDelivery.deliver(data: change == "bytes" ? Data("wrong".utf8) : bytes,
                catalog: catalog, attachment: catalog.attachments[0], reader: Reader(current: current, denied: change == "denied")) { _ in
                Issue.record("Changed or denied PDF reached the destination")
            }
        }
    }

    @Test(arguments: [false, true])
    func ownsPDFUntilDestinationCompletion(fails: Bool) async throws {
        let (catalog, bytes) = try fixture()
        let entered = AsyncStream<URL>.makeStream(), finish = AsyncStream<Void>.makeStream()
        let task = Task {
            try await TransactionAttachmentPDFDelivery.deliver(data: bytes, catalog: catalog,
                attachment: catalog.attachments[0], reader: Reader(current: catalog)) { url in
                entered.continuation.yield(url)
                await Task.detached { for await _ in finish.stream { break } }.value
                #expect(try Data(contentsOf: url) == bytes)
                if fails { throw TransactionExportDeliveryTests.Failure.system }
            }
        }
        var iterator = entered.stream.makeAsyncIterator()
        let url = try #require(await iterator.next())
        #expect(url.pathExtension == "pdf")
        #expect(try Data(contentsOf: url) == bytes)
        task.cancel()
        #expect(FileManager.default.fileExists(atPath: url.path))
        finish.continuation.yield(()); finish.continuation.finish()
        do { try await task.value; #expect(!fails) }
        catch TransactionExportDeliveryTests.Failure.system { #expect(fails) }
        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
        entered.continuation.finish()
    }

    private func fixture() throws -> (DownloadedTransactionAttachments, Data) {
        let account = try AccountID(validating: "account"), bytes = Data("%PDF-1.7\nfixture".utf8)
        let hash = try ProtectedArtifactSHA256.make(bytes: bytes).rawValue
        let object = try DownloadedMediaObjectReference(accountId: account, attachmentId: "pdf", sha256: hash,
            byteCount: String(bytes.count), mediaType: "application/pdf",
            storagePath: "accounts/account/attachments/pdf/\(hash)", kind: .pdf)
        let attachment = try DownloadedTransactionAttachment(id: .init(validating: "reference"), object: object,
            position: 0, isPrimary: true, fileName: "Receipt.pdf")
        return (try .init(scope: .businessInventory(accountId: account), transactionId: .init(validating: "transaction"),
            section: .receipts, revision: 1, isComplete: true, attachments: [attachment]), bytes)
    }
}
