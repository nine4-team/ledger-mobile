import Foundation
import Testing
@testable import LedgeriOS

/// Tests for the v2 billing model's draft-is-live-preview behavior: `markSent`
/// is the moment an invoice freezes into a stored `lines` + `totalCents` snapshot.
@Suite("InvoiceService — draft/markSent snapshotting")
struct InvoiceServiceTests {

    private let acct = "acc1"
    private let invoiceId = "inv1"

    private func makeService(batch: RecordingBatch) -> InvoiceService {
        InvoiceService(makeBatch: { batch })
    }

    private var invoicePath: String { "accounts/\(acct)/invoices/\(invoiceId)" }

    // MARK: - createInvoice

    @Test("createInvoice — writes only membership on a draft, no lines/total")
    func createInvoiceOmitsLinesAndTotal() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)

        _ = try await service.createInvoice(
            accountId: acct,
            projectId: "proj1",
            itemIds: ["i1", "i2"],
            transactionIds: ["t1"],
            invoiceNumber: "INV-1",
            notes: nil,
            userId: "user1"
        )

        #expect(batch.commitCalled)
        #expect(batch.sets.count == 1)
        let set = batch.sets[0]
        let fields = set.fields
        #expect(fields["status"] as? String == "draft")
        #expect(fields["itemIds"] as? [String] == ["i1", "i2"])
        #expect(fields["transactionIds"] as? [String] == ["t1"])
        #expect(fields["lines"] == nil)
        #expect(fields["totalCents"] == nil)
        #expect(fields["invoiceNumber"] as? String == "INV-1")
        #expect(fields["createdBy"] as? String == "user1")
    }

    // MARK: - updateSelections

    @Test("updateSelections — clears stale lines/totalCents on edited drafts")
    func updateSelectionsClearsSnapshot() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        var stub = Invoice()
        stub.id = invoiceId

        try await service.updateSelections(
            invoice: stub,
            accountId: acct,
            newItemIds: ["i3"],
            newTransactionIds: [],
            invoiceNumber: nil,
            notes: "hello",
            userId: "user1"
        )

        #expect(batch.commitCalled)
        #expect(batch.updates.count == 1)
        let fields = batch.updates[0].fields
        #expect(batch.updates[0].path == invoicePath)
        #expect(fields["itemIds"] as? [String] == ["i3"])
        #expect(fields["transactionIds"] as? [String] == [])
        // Stale snapshot fields must be explicitly deleted so readers fall
        // through to live derivation.
        #expect(fields["lines"] != nil) // FieldValue.delete() sentinel present
        #expect(fields["totalCents"] != nil)
        #expect(fields["notes"] as? String == "hello")
    }

    // MARK: - markSent

    @Test("markSent — writes status, dateSent, lines, totalCents, and rederived membership atomically")
    func markSentMaterializesSnapshot() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)

        let lines: [InvoiceLine] = [
            InvoiceLine(id: "line-i1", sourceType: .item, sourceId: "i1", amountCents: 5_000, sign: .charge, snapshotName: "Sofa"),
            InvoiceLine(id: "line-t1", sourceType: .transaction, sourceId: "t1", amountCents: 1_000, sign: .credit, snapshotName: "Refund"),
            InvoiceLine(id: "line-i2", sourceType: .item, sourceId: "i2", amountCents: 3_000, sign: .charge, snapshotName: nil),
            InvoiceLine(id: "line-manual", sourceType: .manual, amountCents: 2_500, sign: .charge, snapshotName: "Design Fee"),
        ]
        let total = InvoiceLineCalculations.netTotalCents(lines: lines) // 5000 - 1000 + 3000 + 2500 = 9500

        try await service.markSent(
            invoiceId: invoiceId,
            accountId: acct,
            lines: lines,
            totalCents: total,
            userId: "user1"
        )

        #expect(batch.commitCalled)
        #expect(batch.updates.count == 1)
        let update = batch.updates[0]
        #expect(update.path == invoicePath)

        let fields = update.fields
        #expect(fields["status"] as? String == "sent")
        #expect(fields["totalCents"] as? Int == 9_500)
        #expect(fields["itemIds"] as? [String] == ["i1", "i2"])
        #expect(fields["transactionIds"] as? [String] == ["t1"])
        #expect(fields["updatedBy"] as? String == "user1")

        // `dateSent` is a serverTimestamp sentinel — just verify the field was
        // written; the exact value is opaque.
        #expect(fields["dateSent"] != nil)

        // Lines encoded as untyped dicts
        let encoded = try #require(fields["lines"] as? [[String: Any]])
        #expect(encoded.count == 4)
        #expect(encoded[0]["id"] as? String == "line-i1")
        #expect(encoded[0]["sourceId"] as? String == "i1")
        #expect(encoded[0]["sign"] as? Int == 1)
        #expect(encoded[1]["sign"] as? Int == -1)
        #expect(encoded[1]["snapshotName"] as? String == "Refund")
        // Third line has no snapshotName — key should be absent rather than NSNull
        #expect(encoded[2]["snapshotName"] == nil)
        // Manual line has no sourceId but does preserve its label and amount.
        #expect(encoded[3]["sourceType"] as? String == "manual")
        #expect(encoded[3]["sourceId"] == nil)
        #expect(encoded[3]["snapshotName"] as? String == "Design Fee")
    }

    @Test("markSent — deduplicates membership when the same source appears twice")
    func markSentDedupesMembership() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let lines: [InvoiceLine] = [
            InvoiceLine(sourceType: .item, sourceId: "i1", amountCents: 100, sign: .charge, snapshotName: nil),
            InvoiceLine(sourceType: .item, sourceId: "i1", amountCents: 200, sign: .charge, snapshotName: nil),
        ]

        try await service.markSent(
            invoiceId: invoiceId,
            accountId: acct,
            lines: lines,
            totalCents: 300,
            userId: nil
        )

        let fields = batch.updates[0].fields
        #expect(fields["itemIds"] as? [String] == ["i1"])
    }

    // MARK: - markCollected

    @Test("markCollected — creates settlement transaction and marks invoice paid")
    func markCollectedCreatesSettlementTransaction() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        var invoice = Invoice()
        invoice.id = invoiceId

        let txId = try await service.markCollected(
            invoice: invoice,
            accountId: acct,
            projectId: "proj1",
            amountCents: 2_800_00,
            source: "Collected INV-1",
            budgetCategoryId: "fee-cat",
            settlementInvoiceLineIds: ["line1", "line2"],
            userId: "user1"
        )

        #expect(!txId.isEmpty)
        #expect(batch.commitCalled)
        #expect(batch.sets.count == 1)
        #expect(batch.updates.count == 1)

        let set = batch.sets[0]
        #expect(set.path == "accounts/\(acct)/transactions/\(txId)")
        #expect(set.fields["projectId"] as? String == "proj1")
        #expect(set.fields["amountCents"] as? Int == 2_800_00)
        #expect(set.fields["type"] as? String == "fee")
        #expect(set.fields["source"] as? String == "Collected INV-1")
        #expect(set.fields["budgetCategoryId"] as? String == "fee-cat")
        #expect(set.fields["settlementInvoiceId"] as? String == invoiceId)
        #expect(set.fields["settlementInvoiceLineIds"] as? [String] == ["line1", "line2"])
        #expect(set.fields["isComplete"] as? Bool == true)
        #expect(set.fields["transactionDate"] != nil)

        let update = batch.updates[0]
        #expect(update.path == invoicePath)
        #expect(update.fields["status"] as? String == "paid")
        #expect(update.fields["updatedBy"] as? String == "user1")
        #expect(update.fields["datePaid"] != nil)
    }
}
