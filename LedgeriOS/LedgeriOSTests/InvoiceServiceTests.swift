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
            InvoiceLine(sourceType: .item, sourceId: "i1", amountCents: 5_000, sign: .charge, snapshotName: "Sofa"),
            InvoiceLine(sourceType: .transaction, sourceId: "t1", amountCents: 1_000, sign: .credit, snapshotName: "Refund"),
            InvoiceLine(sourceType: .item, sourceId: "i2", amountCents: 3_000, sign: .charge, snapshotName: nil),
        ]
        let total = InvoiceLineCalculations.netTotalCents(lines: lines) // 5000 - 1000 + 3000 = 7000

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
        #expect(fields["totalCents"] as? Int == 7_000)
        #expect(fields["itemIds"] as? [String] == ["i1", "i2"])
        #expect(fields["transactionIds"] as? [String] == ["t1"])
        #expect(fields["updatedBy"] as? String == "user1")

        // `dateSent` is a serverTimestamp sentinel — just verify the field was
        // written; the exact value is opaque.
        #expect(fields["dateSent"] != nil)

        // Lines encoded as untyped dicts
        let encoded = try #require(fields["lines"] as? [[String: Any]])
        #expect(encoded.count == 3)
        #expect(encoded[0]["sourceId"] as? String == "i1")
        #expect(encoded[0]["sign"] as? Int == 1)
        #expect(encoded[1]["sign"] as? Int == -1)
        #expect(encoded[1]["snapshotName"] as? String == "Refund")
        // Third line has no snapshotName — key should be absent rather than NSNull
        #expect(encoded[2]["snapshotName"] == nil)
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
}
