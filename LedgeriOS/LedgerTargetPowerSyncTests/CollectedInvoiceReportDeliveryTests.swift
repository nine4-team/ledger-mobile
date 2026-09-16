import Darwin
import Foundation
import LedgerTargetCore
import LedgerTargetPowerSync
import Testing

@Suite("Collected Invoice authorized PDF delivery") @MainActor
struct CollectedInvoiceReportDeliveryTests {
    enum Failure: Error { case denied, unused, handoff }
    struct LiveReader: ProjectLiveInvoiceReading {
        let invoices: [LiveInvoiceContents]?
        func readLiveInvoices(accountId: AccountID, projectId: ProjectID) async throws -> [LiveInvoiceContents] {
            guard let invoices else { throw Failure.denied }
            return invoices
        }
        func watchLiveInvoices(accountId: AccountID, projectId: ProjectID) -> AsyncThrowingStream<[LiveInvoiceContents]?, Error> {
            .init { $0.finish() }
        }
    }
    @Test func liveSourceChangeWithoutHeaderRevisionCannotExport() async throws {
        func invoice(amount: Int64, name: String = "Live", notes: String = "",
                     description: String = "Expense", sourceId: String = "expense",
                     accountId: String = "account") throws -> LiveInvoiceContents {
            let money = try Money(minorUnits: amount, currency: .init(validating: "USD"))
            return try .init(invoiceId: .init(validating: "live"), revision: 1, status: .created, name: name, notes: notes,
                scope: .project(accountId: .init(validating: accountId), projectId: .init(validating: "project"), clientId: .init(validating: "client")),
                lines: [.init(selection: .init(source: .expense(.init(validating: sourceId)), expectedRevision: 1,
                    reviewedAmount: money), categoryId: .init(validating: "category"), description: description)], reportedTotal: money)
        }
        let rendered = try invoice(amount: 100), changed = try invoice(amount: 101)
        let unavailable: [[LiveInvoiceContents]?] = try [
            [changed], [invoice(amount: 100, name: "Renamed")],
            [invoice(amount: 100, notes: "Changed terms")],
            [invoice(amount: 100, description: "Changed vendor")],
            [invoice(amount: 100, sourceId: "replacement-expense")],
            [invoice(amount: 100, accountId: "other-account")], [], nil,
        ]
        for available in unavailable {
            // The native save callback invokes this same validator after its
            // destination is chosen, not only before presenting the dialog.
            await #expect(throws: (any Error).self) {
                try await CollectedInvoiceReportDelivery.revalidate(rendered, reader: LiveReader(invoices: available))
            }
            await #expect(throws: (any Error).self) {
                try await CollectedInvoiceReportDelivery.deliver(data: Data("%PDF-live".utf8), invoice: rendered,
                    reader: LiveReader(invoices: available)) { _ in Issue.record("Stale or unauthorized live export") }
            }
        }
        var delivered: URL?
        try await CollectedInvoiceReportDelivery.deliver(data: Data("%PDF-live".utf8), invoice: rendered,
            reader: LiveReader(invoices: [rendered])) { url in
                delivered = url
                let actual = try Data(contentsOf: url)
                #expect(actual == Data("%PDF-live".utf8))
            }
        #expect(!FileManager.default.fileExists(atPath: try #require(delivered).path))
    }
    struct Reader: ProjectInvoicingReading {
        var invoices: [FrozenInvoiceContents]?
        var read: (@Sendable () async throws -> [FrozenInvoiceContents])? = nil
        var reportRead: (@Sendable (ProtectedArtifactEpochMilliseconds) async throws -> CollectedInvoiceReportSnapshot)? = nil
        func readCollectedInvoiceReport(accountId: AccountID, projectId: ProjectID, invoiceId: InvoiceID,
            asOf: ProtectedArtifactEpochMilliseconds) async throws -> CollectedInvoiceReportSnapshot {
            if let reportRead { return try await reportRead(asOf) }
            guard let invoice = try await readCollectedInvoices(accountId: accountId, projectId: projectId)
                .first(where: { $0.invoiceId == invoiceId }) else {
                throw CollectedInvoiceReportDeliveryFailure.snapshotChanged
            }
            return try .init(invoice: invoice, provenance: .init(accountId: accountId, projectId: projectId,
                principalId: .init(validating: "test-principal"), visibilityScopeID: .make(bytes: Data("test-scope".utf8)),
                source: .authoritative, authorityVersion: .init(validating: "test-authority"),
                asOf: asOf, readiness: .ready))
        }
        func readCollectedInvoices(accountId: AccountID, projectId: ProjectID) async throws -> [FrozenInvoiceContents] {
            if let read { return try await read() }
            guard let invoices else { throw Failure.denied }
            return invoices
        }
        func watchCollectedInvoices(accountId: AccountID, projectId: ProjectID, invoiceId: InvoiceID? = nil) -> AsyncThrowingStream<[FrozenInvoiceContents]?, Error> { .init { $0.finish() } }
        func readExpenses(accountId: AccountID, projectId: ProjectID) async throws -> ProjectExpenses { throw Failure.unused }
        func watchExpenses(accountId: AccountID, projectId: ProjectID) -> AsyncThrowingStream<ProjectExpenses?, Error> { .init { $0.finish() } }
        func loadExpenseReceipt(projectId: ProjectID, expenseId: ExpenseID, attachmentId: AttachmentID, allowDownload: Bool) async throws -> Data? { throw Failure.unused }
        func readInvoicingCharges(accountId: AccountID, projectId: ProjectID) async throws -> ProjectInvoicingItems { throw Failure.unused }
        func watchInvoicingCharges(accountId: AccountID, projectId: ProjectID) -> AsyncThrowingStream<ProjectInvoicingItems?, Error> { .init { $0.finish() } }
    }

    @Test(arguments: [false, true])
    func cleanupAfterHandoff(fails: Bool) async throws {
        let invoice = try fixture(), bytes = Data("%PDF-invoice-test".utf8)
        var artifact: URL?
        do {
            try await CollectedInvoiceReportDelivery.deliver(data: bytes, invoice: invoice, reader: Reader(invoices: [invoice])) { url in
                artifact = url
                #expect(try Data(contentsOf: url) == bytes)
                if fails { throw Failure.handoff }
            }
            #expect(!fails)
        } catch Failure.handoff { #expect(fails) }
        let url = try #require(artifact)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test(arguments: [false, true])
    func removedOrDeniedCannotExport(denied: Bool) async throws {
        let invoice = try fixture()
        await #expect(throws: (any Error).self) {
            try await CollectedInvoiceReportDelivery.deliver(data: Data("%PDF-test".utf8), invoice: invoice,
                reader: Reader(invoices: denied ? nil : [])) { _ in Issue.record("Unauthorized handoff") }
        }
    }

    @Test
    func cancellationDuringHandoffRetainsBytesUntilCompletion() async throws {
        let invoice = try fixture(), bytes = Data("%PDF-handoff-lifetime".utf8)
        let task = Task { @MainActor () throws -> URL in
            var handedOffURL: URL?
            try await CollectedInvoiceReportDelivery.deliver(data: bytes, invoice: invoice,
                reader: Reader(invoices: [invoice])) { url in
                    handedOffURL = url
                    withUnsafeCurrentTask { $0?.cancel() }
                    await Task.yield()
                    let retainedBytes = try Data(contentsOf: url)
                    #expect(retainedBytes == bytes)
                    // Native completion, not task cancellation, releases bytes.
                }
            return try #require(handedOffURL)
        }
        let url = try await task.value
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test
    func changedSnapshotCannotExportAndCleansScratch() async throws {
        let path = try #require(realpath(FileManager.default.temporaryDirectory.path, nil))
        defer { free(path) }
        let parent = URL(fileURLWithPath: String(cString: path)).appendingPathComponent("invoice-stale-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent(ReportScratchStore.directoryName)
        let rendered = try fixture(), current = try fixture(revision: 2)
        await #expect(throws: CollectedInvoiceReportDeliveryFailure.snapshotChanged) {
            try await CollectedInvoiceReportDelivery.deliver(data: Data("%PDF-test".utf8), invoice: rendered,
                reader: Reader(invoices: [current]), scratchRoot: root) { _ in
                    Issue.record("Stale Invoice handed to external destination")
                }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    private func fixture(revision: Int64 = 1) throws -> FrozenInvoiceContents {
        let scope = try TransactionScope.project(accountId: .init(validating: "account"), projectId: .init(validating: "project"), clientId: .init(validating: "client"))
        let amount = Money(minorUnits: 100, currency: try .init(validating: "USD"))
        let line = try FrozenInvoiceLine(id: .init(validating: "line"), scope: scope,
            source: .expense(expenseId: .init(validating: "expense")), sourceRevision: 1,
            categoryId: .init(validating: "category"), signedAmount: amount, description: "Frozen expense")
        return try .init(invoiceId: .init(validating: "invoice"), invoiceRevision: revision, scope: scope,
            purchaseId: .init(validating: "payment"), lines: [line], total: amount)
    }
}
