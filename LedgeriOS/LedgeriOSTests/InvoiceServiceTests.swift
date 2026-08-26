import Foundation
import Testing
@testable import LedgeriOS

/// Tests for the v2 billing model's created-is-live-preview behavior: `markSent`
/// is the moment an invoice freezes into a stored `lines` + `totalCents` snapshot.
@Suite("InvoiceService — created/markSent snapshotting")
struct InvoiceServiceTests {

    private let acct = "acc1"
    private let invoiceId = "inv1"

    private func makeService(batch: RecordingBatch) -> InvoiceService {
        InvoiceService(makeBatch: { batch })
    }

    private var invoicePath: String { "accounts/\(acct)/invoices/\(invoiceId)" }

    // MARK: - createInvoice

    @Test("createInvoice — writes only membership on a created invoice, no lines/total")
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
        #expect(fields["status"] as? String == "created")
        #expect(fields["itemIds"] as? [String] == ["i1", "i2"])
        #expect(fields["transactionIds"] as? [String] == ["t1"])
        #expect(fields["lines"] == nil)
        #expect(fields["totalCents"] == nil)
        #expect(fields["invoiceNumber"] as? String == "INV-1")
        #expect(fields["createdBy"] as? String == "user1")
    }

    @Test("createInvoice — provisions the hidden category for a manual charge")
    func createInvoiceProvisionsSystemCategoryForManualCharge() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        let line = InvoiceLine(
            sourceType: .manual,
            amountCents: 25_000,
            sign: .charge,
            budgetCategoryId: SystemBudgetCategory.otherClientChargesAndCreditsId,
            snapshotName: "Additional project work"
        )

        _ = try await service.createInvoice(
            accountId: acct,
            projectId: "proj1",
            itemIds: [],
            transactionIds: [],
            lines: [line],
            invoiceNumber: nil,
            notes: nil,
            userId: "user1"
        )

        let categoryPath = "accounts/\(acct)/presets/default/budgetCategories/\(SystemBudgetCategory.otherClientChargesAndCreditsId)"
        let categorySet = try #require(batch.sets.first { $0.path == categoryPath })
        #expect(categorySet.merge)
        #expect(categorySet.fields["name"] as? String == "Other Client Charges & Credits")
        #expect(categorySet.fields["isSystem"] as? Bool == true)

        let invoiceSet = try #require(batch.sets.first { $0.path != categoryPath })
        let encodedLines = try #require(invoiceSet.fields["lines"] as? [[String: Any]])
        #expect(encodedLines.first?["budgetCategoryId"] as? String == SystemBudgetCategory.otherClientChargesAndCreditsId)
    }

    // MARK: - updateSelections

    @Test("updateSelections — clears stale lines/totalCents on edited created invoices")
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

    @Test("markCollected — creates categorized payment transactions and marks invoice paid")
    func markCollectedCreatesCategorizedPaymentTransactions() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        var invoice = Invoice()
        invoice.id = invoiceId
        invoice.lines = [
            InvoiceLine(id: "line1", sourceType: .manual, amountCents: 2_000_00, sign: .charge, budgetCategoryId: "cat-a", snapshotName: "Design Fee"),
            InvoiceLine(id: "line2", sourceType: .manual, amountCents: 800_00, sign: .charge, budgetCategoryId: "cat-b", snapshotName: "Install"),
        ]

        let txIds = try await service.markCollected(
            invoice: invoice,
            accountId: acct,
            projectId: "proj1",
            amountCents: 2_800_00,
            source: "Collected INV-1",
            settlementInvoiceLineIds: ["line1", "line2"],
            userId: "user1"
        )

        #expect(txIds.count == 2)
        #expect(batch.commitCalled)
        #expect(batch.sets.count == 2)
        #expect(batch.updates.count == 1)

        let first = batch.sets[0]
        #expect(first.fields["projectId"] as? String == "proj1")
        #expect(first.fields["amountCents"] as? Int == 2_000_00)
        #expect(first.fields["type"] as? String == "paymentToBusiness")
        #expect(first.fields["source"] as? String == "Collected INV-1")
        #expect(first.fields["budgetCategoryId"] as? String == "cat-a")
        #expect(first.fields["settlementInvoiceId"] as? String == invoiceId)
        #expect(first.fields["settlementInvoiceLineIds"] as? [String] == ["line1"])
        #expect(first.fields["isComplete"] as? Bool == true)
        #expect(first.fields["transactionDate"] != nil)

        let second = batch.sets[1]
        #expect(second.fields["amountCents"] as? Int == 800_00)
        #expect(second.fields["type"] as? String == "paymentToBusiness")
        #expect(second.fields["budgetCategoryId"] as? String == "cat-b")
        #expect(second.fields["settlementInvoiceLineIds"] as? [String] == ["line2"])

        let update = batch.updates[0]
        #expect(update.path == invoicePath)
        #expect(update.fields["status"] as? String == "paid")
        #expect(update.fields["updatedBy"] as? String == "user1")
        #expect(update.fields["datePaid"] != nil)
    }

    @Test("markCollected — partial collection retains all lines and leaves the invoice sent")
    func markCollectedPartiallyRetainsInvoice() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        var invoice = Invoice()
        invoice.id = invoiceId
        invoice.status = .sent
        invoice.lines = [
            InvoiceLine(id: "line1", sourceType: .manual, amountCents: 20_000, sign: .charge, budgetCategoryId: "cat-a", snapshotName: "First charge"),
            InvoiceLine(id: "line2", sourceType: .manual, amountCents: 8_000, sign: .charge, budgetCategoryId: "cat-b", snapshotName: "Second charge"),
        ]

        let transactionIds = try await service.markCollected(
            invoice: invoice,
            accountId: acct,
            projectId: "proj1",
            amountCents: 20_000,
            source: "Partial payment",
            settlementInvoiceLineIds: ["line1"],
            userId: "user1"
        )

        #expect(transactionIds.count == 1)
        let update = try #require(batch.updates.first)
        #expect(update.fields["status"] as? String == "sent")
        #expect(update.fields["datePaid"] == nil)
        #expect(update.fields["totalCents"] as? Int == 28_000)
        let lines = try #require(update.fields["lines"] as? [[String: Any]])
        #expect(lines.count == 2)
        #expect(lines[0]["settlementTransactionIds"] as? [String] == transactionIds)
        #expect(lines[1]["settlementTransactionIds"] == nil)
    }

    @Test("markCollected — blocks credit-only invoice from paymentToBusiness")
    func markCollectedBlocksCreditOnlyInvoice() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        var invoice = Invoice()
        invoice.id = invoiceId
        invoice.lines = [
            InvoiceLine(id: "credit1", sourceType: .manual, amountCents: 500_00, sign: .credit, budgetCategoryId: "cat-a", snapshotName: "Returned item credit"),
        ]

        do {
            _ = try await service.markCollected(
                invoice: invoice,
                accountId: acct,
                projectId: "proj1",
                amountCents: -500_00,
                source: "Collected INV-1",
                settlementInvoiceLineIds: nil,
                userId: "user1"
            )
            Issue.record("Expected markCollected to reject credit-only invoice")
        } catch InvoiceService.InvoiceServiceError.nonPositiveCollection {
            #expect(batch.sets.isEmpty)
            #expect(batch.updates.isEmpty)
            #expect(!batch.commitCalled)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - voidInvoicePayment

    @Test("voidInvoicePayment — cancels settlement transactions, restores sent, and writes event")
    func voidInvoicePaymentCancelsSettlementsAndRestoresSent() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        var invoice = Invoice()
        invoice.id = invoiceId
        invoice.projectId = "proj1"
        invoice.status = .paid

        try await service.voidInvoicePayment(
            invoice: invoice,
            accountId: acct,
            settlementTransactionIds: ["tx-a", "tx-b"],
            userId: "user1"
        )

        #expect(batch.commitCalled)
        #expect(batch.updates.count == 3)

        let firstTx = batch.updates[0]
        #expect(firstTx.path == "accounts/\(acct)/transactions/tx-a")
        #expect(firstTx.fields["status"] as? String == "canceled")
        #expect(firstTx.fields["updatedBy"] as? String == "user1")

        let secondTx = batch.updates[1]
        #expect(secondTx.path == "accounts/\(acct)/transactions/tx-b")
        #expect(secondTx.fields["status"] as? String == "canceled")

        let invoiceUpdate = batch.updates[2]
        #expect(invoiceUpdate.path == invoicePath)
        #expect(invoiceUpdate.fields["status"] as? String == "sent")
        #expect(invoiceUpdate.fields["datePaid"] != nil)
        #expect(invoiceUpdate.fields["updatedBy"] as? String == "user1")

        #expect(batch.autoIdSets.count == 1)
        let event = batch.autoIdSets[0]
        #expect(event.collectionPath == "accounts/\(acct)/invoiceEvents")
        #expect(event.fields["accountId"] as? String == acct)
        #expect(event.fields["projectId"] as? String == "proj1")
        #expect(event.fields["invoiceId"] as? String == invoiceId)
        #expect(event.fields["kind"] as? String == "paymentCanceled")
        #expect(event.fields["fromStatus"] as? String == "paid")
        #expect(event.fields["toStatus"] as? String == "sent")
        #expect(event.fields["settlementTransactionIds"] as? [String] == ["tx-a", "tx-b"])
        #expect(event.fields["source"] as? String == "app")
        #expect(event.fields["createdBy"] as? String == "user1")
        #expect(event.fields["createdAt"] != nil)
    }

    @Test("voidInvoicePayment — requires settlement transaction ids")
    func voidInvoicePaymentRequiresSettlementIds() async throws {
        let batch = RecordingBatch()
        let service = makeService(batch: batch)
        var invoice = Invoice()
        invoice.id = invoiceId

        do {
            try await service.voidInvoicePayment(
                invoice: invoice,
                accountId: acct,
                settlementTransactionIds: [],
                userId: "user1"
            )
            Issue.record("Expected voidInvoicePayment to reject an empty settlement id list")
        } catch InvoiceService.InvoiceServiceError.noSettlementTransactions {
            #expect(batch.updates.isEmpty)
            #expect(batch.autoIdSets.isEmpty)
            #expect(!batch.commitCalled)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("appendReturnedPaidItemCreditInvoices — writes ordinary created invoice with manual credit line")
    func appendReturnedPaidItemCreditInvoicesWritesCreatedInvoice() async throws {
        let batch = RecordingBatch()
        let credit = InvoiceLineCalculations.ReturnedPaidItemCreditContext(
            itemId: "item1",
            itemName: "Sofa",
            projectId: "proj1",
            amountCents: 1_200_00,
            budgetCategoryId: "cat-furnishings",
            paidInvoiceId: "paid-inv",
            paidInvoiceLineId: "paid-line",
            lineId: "returnCredit:paid-inv:paid-line:item1"
        )

        InvoiceService.appendReturnedPaidItemCreditInvoices(
            accountId: acct,
            credits: [credit],
            batch: batch,
            userId: "user1"
        )

        #expect(batch.sets.count == 1)
        let set = batch.sets[0]
        #expect(set.path.hasPrefix("accounts/\(acct)/invoices/"))
        #expect(set.fields["status"] as? String == "created")
        #expect(set.fields["projectId"] as? String == "proj1")
        #expect(set.fields["itemIds"] as? [String] == [])
        #expect(set.fields["transactionIds"] as? [String] == [])
        #expect(set.fields["createdBy"] as? String == "user1")

        let lines = try #require(set.fields["lines"] as? [[String: Any]])
        #expect(lines.count == 1)
        #expect(lines[0]["id"] as? String == "returnCredit:paid-inv:paid-line:item1")
        #expect(lines[0]["sourceType"] as? String == "manual")
        #expect(lines[0]["sourceId"] == nil)
        #expect(lines[0]["sign"] as? Int == -1)
        #expect(lines[0]["amountCents"] as? Int == 1_200_00)
        #expect(lines[0]["budgetCategoryId"] as? String == "cat-furnishings")
        #expect(lines[0]["snapshotName"] as? String == "Credit: returned Sofa")
    }
}

@Suite("InvoiceLineCalculations — returned paid item credits")
struct ReturnedPaidItemCreditContextTests {

    @Test("paid item invoice line creates deterministic credit context")
    func paidItemInvoiceLineCreatesCreditContext() throws {
        var item = Item()
        item.id = "item1"
        item.projectId = "proj1"
        item.name = "Sofa"

        var invoice = Invoice()
        invoice.id = "paid-inv"
        invoice.projectId = "proj1"
        invoice.status = .paid
        invoice.datePaid = Date(timeIntervalSince1970: 100)
        invoice.lines = [
            InvoiceLine(id: "paid-line", sourceType: .item, sourceId: "item1", amountCents: 2_500_00, sign: .charge, budgetCategoryId: "cat-furnishings", snapshotName: "Sofa"),
        ]

        let contexts = InvoiceLineCalculations.returnedPaidItemCreditContexts(
            for: [item],
            invoices: [invoice]
        )

        #expect(contexts.count == 1)
        #expect(contexts[0].itemId == "item1")
        #expect(contexts[0].itemName == "Sofa")
        #expect(contexts[0].projectId == "proj1")
        #expect(contexts[0].amountCents == 2_500_00)
        #expect(contexts[0].budgetCategoryId == "cat-furnishings")
        #expect(contexts[0].lineId == "returnCredit:paid-inv:paid-line:item1")
    }

    @Test("existing non-canceled deterministic credit line dedupes")
    func existingCreditLineDedupes() throws {
        var item = Item()
        item.id = "item1"
        item.projectId = "proj1"

        var paidInvoice = Invoice()
        paidInvoice.id = "paid-inv"
        paidInvoice.projectId = "proj1"
        paidInvoice.status = .paid
        paidInvoice.lines = [
            InvoiceLine(id: "paid-line", sourceType: .item, sourceId: "item1", amountCents: 1_000, sign: .charge, budgetCategoryId: "cat1"),
        ]

        var creditInvoice = Invoice()
        creditInvoice.id = "credit-inv"
        creditInvoice.projectId = "proj1"
        creditInvoice.status = .created
        creditInvoice.lines = [
            InvoiceLine(id: "returnCredit:paid-inv:paid-line:item1", sourceType: .manual, amountCents: 1_000, sign: .credit, budgetCategoryId: "cat1"),
        ]

        let contexts = InvoiceLineCalculations.returnedPaidItemCreditContexts(
            for: [item],
            invoices: [paidInvoice, creditInvoice]
        )

        #expect(contexts.isEmpty)
    }
}

@Suite("InvoiceLineCalculations — project price locking")
struct ProjectPriceLockingTests {

    @Test("paid invoice membership locks an item's project price")
    func paidInvoiceLocksProjectPrice() {
        var invoice = Invoice()
        invoice.status = .paid
        invoice.projectId = "project1"
        invoice.itemIds = ["item1"]

        #expect(InvoiceLineCalculations.isProjectPriceLocked(
            itemId: "item1",
            projectId: "project1",
            invoices: [invoice]
        ))
    }

    @Test("created, sent, and canceled invoices leave project price editable")
    func openInvoicesLeaveProjectPriceEditable() {
        let invoices = [InvoiceStatus.created, .sent, .canceled].map { status in
            var invoice = Invoice()
            invoice.status = status
            invoice.projectId = "project1"
            invoice.itemIds = ["item1"]
            return invoice
        }

        #expect(!InvoiceLineCalculations.isProjectPriceLocked(
            itemId: "item1",
            projectId: "project1",
            invoices: invoices
        ))
    }

    @Test("paid legacy line locks even when flat membership is missing")
    func paidLineLocksWithoutMembershipIndex() {
        var invoice = Invoice()
        invoice.status = .paid
        invoice.projectId = "project1"
        invoice.lines = [
            InvoiceLine(sourceType: .item, sourceId: "item1", amountCents: 10_000, sign: .charge),
        ]

        #expect(InvoiceLineCalculations.isProjectPriceLocked(
            itemId: "item1",
            projectId: "project1",
            invoices: [invoice]
        ))
    }

    @Test("paid invoice from a prior project does not lock the current sale")
    func priorProjectPaidInvoiceDoesNotLockCurrentProjectPrice() {
        var invoice = Invoice()
        invoice.status = .paid
        invoice.projectId = "oldProject"
        invoice.itemIds = ["item1"]

        #expect(!InvoiceLineCalculations.isProjectPriceLocked(
            itemId: "item1",
            projectId: "newProject",
            invoices: [invoice]
        ))
    }
}
