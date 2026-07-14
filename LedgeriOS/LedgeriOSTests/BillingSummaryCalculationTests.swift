import Foundation
import Testing
@testable import LedgeriOS

@Suite("Billing Summary Calculation Tests")
struct BillingSummaryCalculationTests {

    private func makeInvoice(
        id: String,
        projectId: String,
        status: InvoiceStatus,
        itemIds: [String] = [],
        transactionIds: [String] = [],
        lines: [InvoiceLine]? = nil
    ) -> Invoice {
        var inv = Invoice()
        inv.id = id
        inv.projectId = projectId
        inv.status = status
        inv.itemIds = itemIds
        inv.transactionIds = transactionIds
        inv.lines = lines
        return inv
    }

    private func makeCategory(id: String, categoryType: BudgetCategoryType) -> BudgetCategory {
        var category = BudgetCategory()
        category.id = id
        category.name = id
        category.metadata = BudgetCategoryMetadata(categoryType: categoryType, excludeFromOverallBudget: false)
        return category
    }

    @Test("Membership across created/sent/paid/canceled produces correct totals")
    func mixedStatuses() {
        let projectId = "p1"

        // Items — unbilled, on created, on sent (invoiced-only), on paid.
        let unbilledItem = makeItem(id: "i-unbilled", projectId: projectId, purchasePriceCents: 1000)
        let createdItem = makeItem(id: "i-created", projectId: projectId, purchasePriceCents: 2000)
        let sentItem = makeItem(id: "i-sent", projectId: projectId, purchasePriceCents: 3000)
        let paidItem = makeItem(id: "i-paid", projectId: projectId, purchasePriceCents: 4000)
        let items = [unbilledItem, createdItem, sentItem, paidItem]

        // Transactions — non-itemized variants + one itemized (excluded).
        let unbilledTx = makeTransaction(id: "t-unbilled", projectId: projectId, amountCents: 500, itemIds: nil)
        let sentTx = makeTransaction(id: "t-sent", projectId: projectId, amountCents: 700, itemIds: [])
        let paidTx = makeTransaction(id: "t-paid", projectId: projectId, amountCents: 900, itemIds: [])
        let itemizedTx = makeTransaction(id: "t-itemized", projectId: projectId, amountCents: 9999, itemIds: ["a", "b"])
        let transactions = [unbilledTx, sentTx, paidTx, itemizedTx]

        let invoices: [Invoice] = [
            makeInvoice(id: "inv-created", projectId: projectId, status: .created, itemIds: ["i-created"]),
            makeInvoice(id: "inv-sent", projectId: projectId, status: .sent, itemIds: ["i-sent"], transactionIds: ["t-sent"]),
            makeInvoice(id: "inv-paid", projectId: projectId, status: .paid, itemIds: ["i-paid"], transactionIds: ["t-paid"]),
            makeInvoice(id: "inv-canceled", projectId: projectId, status: .canceled, itemIds: ["i-unbilled"]),
        ]

        let summary = BillingSummaryCalculations.summarize(
            projectId: projectId,
            items: items,
            transactions: transactions,
            invoices: invoices
        )

        // Items: 1000+2000+3000+4000 = 10000, Tx non-itemized: 500+700+900 = 2100
        #expect(summary.totalSpentCents == 12100)
        // Invoiced demand (sent+paid only): items 3000+4000 + tx 700+900 = 8600
        #expect(summary.invoicedCents == 8600)
        // Collected falls back to paid invoice demand when no settlement transaction exists.
        #expect(summary.collectedCents == 4900)
        // Outstanding = sent invoice demand.
        #expect(summary.outstandingCents == 3700)
    }

    @Test("Empty inputs produce zero summary")
    func emptyInputs() {
        let summary = BillingSummaryCalculations.summarize(
            projectId: "p1", items: [], transactions: [], invoices: []
        )
        #expect(summary == BillingSummaryCalculations.Summary(
            totalSpentCents: 0, invoicedCents: 0, collectedCents: 0, outstandingCents: 0
        ))
    }

    @Test("Itemized transactions are excluded")
    func itemizedExcluded() {
        let tx = makeTransaction(
            id: "t",
            projectId: "p1",
            amountCents: 10_000,
            itemIds: ["x"],
            budgetCategoryId: "items"
        )
        let inv = makeInvoice(id: "inv", projectId: "p1", status: .paid, transactionIds: ["t"])
        let summary = BillingSummaryCalculations.summarize(
            projectId: "p1",
            items: [],
            transactions: [tx],
            invoices: [inv],
            budgetCategories: ["items": makeCategory(id: "items", categoryType: .itemized)]
        )
        #expect(summary.totalSpentCents == 0)
        #expect(summary.collectedCents == 0)
    }

    @Test("Itemized-category transaction with missing itemIds is not treated as non-itemized")
    func itemizedCategoryWithMissingItemsExcluded() {
        let tx = makeTransaction(
            id: "t",
            projectId: "p1",
            amountCents: 10_000,
            itemIds: [],
            budgetCategoryId: "items"
        )
        let summary = BillingSummaryCalculations.summarize(
            projectId: "p1",
            items: [],
            transactions: [tx],
            invoices: [],
            budgetCategories: ["items": makeCategory(id: "items", categoryType: .itemized)]
        )
        #expect(summary.totalSpentCents == 0)
        #expect(BillingSummaryCalculations.isNonItemized(
            tx,
            budgetCategories: ["items": makeCategory(id: "items", categoryType: .itemized)]
        ) == false)
    }

    @Test("Non-itemized purchase category remains directly billable")
    func nonItemizedPurchaseCategoryIncluded() {
        let tx = makeTransaction(
            id: "t",
            projectId: "p1",
            amountCents: 12_345,
            itemIds: [],
            transactionType: .purchase,
            budgetCategoryId: "services"
        )
        let summary = BillingSummaryCalculations.summarize(
            projectId: "p1",
            items: [],
            transactions: [tx],
            invoices: [],
            budgetCategories: ["services": makeCategory(id: "services", categoryType: .general)]
        )
        #expect(summary.totalSpentCents == 12_345)
        #expect(BillingSummaryCalculations.isNonItemized(
            tx,
            budgetCategories: ["services": makeCategory(id: "services", categoryType: .general)]
        ) == true)
    }

    @Test("Billable membership uses category itemization instead of empty itemIds")
    func billableMembershipUsesCategoryItemization() {
        let itemized = makeTransaction(
            id: "t-itemized-missing-items",
            projectId: "p1",
            amountCents: 10_000,
            itemIds: [],
            reimbursementType: "owed-to-company",
            transactionType: .purchase,
            budgetCategoryId: "items"
        )
        let service = makeTransaction(
            id: "t-service",
            projectId: "p1",
            amountCents: 2_500,
            itemIds: [],
            reimbursementType: "owed-to-company",
            transactionType: .purchase,
            budgetCategoryId: "services"
        )

        let membership = InvoiceLineCalculations.billableMembership(
            projectId: "p1",
            items: [],
            transactions: [itemized, service],
            invoices: [],
            budgetCategories: [
                "items": makeCategory(id: "items", categoryType: .itemized),
                "services": makeCategory(id: "services", categoryType: .general),
            ]
        )

        #expect(!membership.toInvoiceTransactionIds.contains("t-itemized-missing-items"))
        #expect(membership.toInvoiceTransactionIds.contains("t-service"))
    }

    @Test("Item invoiceability uses current transaction shape for pricing")
    func itemInvoiceabilityUsesCurrentTransactionShape() {
        let projectId = "p1"
        var soldItem = makeItem(id: "sold", projectId: projectId, purchasePriceCents: 1_000, projectPriceCents: 1_500)
        soldItem.transactionId = "tx-inventory"
        soldItem.currentSource = "Business Inventory"

        var reimbursableItem = makeItem(id: "reimbursable", projectId: projectId, purchasePriceCents: 2_000, projectPriceCents: 2_500)
        reimbursableItem.transactionId = "tx-vendor"
        reimbursableItem.currentSource = "Vendor"

        var clientPaidItem = makeItem(id: "client-paid", projectId: projectId, purchasePriceCents: 3_000, projectPriceCents: 3_500)
        clientPaidItem.transactionId = "tx-client"
        clientPaidItem.currentSource = "Vendor"

        var inventoryTx = makeTransaction(
            id: "tx-inventory",
            projectId: projectId,
            amountCents: 1_000,
            itemIds: ["sold"],
            transactionType: .purchase
        )
        inventoryTx.source = "Business Inventory"
        var vendorTx = makeTransaction(
            id: "tx-vendor",
            projectId: projectId,
            amountCents: 2_000,
            itemIds: ["reimbursable"],
            reimbursementType: "owed-to-company",
            transactionType: .purchase
        )
        vendorTx.source = "Vendor"
        var clientTx = makeTransaction(
            id: "tx-client",
            projectId: projectId,
            amountCents: 3_000,
            itemIds: ["client-paid"],
            transactionType: .purchase
        )
        clientTx.source = "Vendor"

        let transactions = [inventoryTx, vendorTx, clientTx]

        #expect(InvoiceLineCalculations.invoiceability(
            for: soldItem,
            projectId: projectId,
            transactions: transactions
        ) == .billable(.projectPrice))
        #expect(InvoiceLineCalculations.amountCents(
            for: soldItem,
            projectId: projectId,
            transactions: transactions
        ) == 1_500)
        #expect(InvoiceLineCalculations.invoiceability(
            for: reimbursableItem,
            projectId: projectId,
            transactions: transactions
        ) == .billable(.purchasePrice))
        #expect(InvoiceLineCalculations.amountCents(
            for: reimbursableItem,
            projectId: projectId,
            transactions: transactions
        ) == 2_000)
        #expect(InvoiceLineCalculations.invoiceability(
            for: clientPaidItem,
            projectId: projectId,
            transactions: transactions
        ) == .notBillable)

        let membership = InvoiceLineCalculations.billableMembership(
            projectId: projectId,
            items: [soldItem, reimbursableItem, clientPaidItem],
            transactions: transactions,
            invoices: []
        )
        #expect(membership.toInvoiceItemIds == ["sold", "reimbursable"])
    }

    @Test("Item invoiceability uses sold lineage as fallback")
    func itemInvoiceabilityUsesSoldLineageFallback() {
        let projectId = "p1"
        let item = makeItem(id: "legacy-sold", projectId: projectId, purchasePriceCents: 1_000, projectPriceCents: 1_400)
        var edge = LineageEdge()
        edge.itemId = "legacy-sold"
        edge.movementKind = "sold"
        edge.toProjectId = projectId

        #expect(InvoiceLineCalculations.invoiceability(
            for: item,
            projectId: projectId,
            transactions: [],
            lineageEdges: [edge]
        ) == .billable(.projectPrice))
        #expect(InvoiceLineCalculations.amountCents(
            for: item,
            projectId: projectId,
            transactions: [],
            lineageEdges: [edge]
        ) == 1_400)
    }

    @Test("Manual invoice lines count as demand and settlement transactions count as collected")
    func manualLineDemandAndSettlementCollection() {
        let projectId = "p1"
        let manualLine = InvoiceLine(
            id: "line-manual",
            sourceType: .manual,
            amountCents: 123,
            sign: .charge,
            snapshotName: "Design Fee"
        )
        let sentInvoice = makeInvoice(
            id: "inv-sent",
            projectId: projectId,
            status: .sent,
            lines: [manualLine]
        )

        let sentSummary = BillingSummaryCalculations.summarize(
            projectId: projectId,
            items: [],
            transactions: [],
            invoices: [sentInvoice]
        )
        #expect(sentSummary.totalSpentCents == 0)
        #expect(sentSummary.invoicedCents == 123)
        #expect(sentSummary.collectedCents == 0)
        #expect(sentSummary.outstandingCents == 123)

        var paidInvoice = sentInvoice
        paidInvoice.status = .paid
        let settlement = makeTransaction(
            id: "settlement",
            projectId: projectId,
            amountCents: 123,
            itemIds: nil
        )
        var linkedSettlement = settlement
        linkedSettlement.settlementInvoiceId = "inv-sent"

        let paidSummary = BillingSummaryCalculations.summarize(
            projectId: projectId,
            items: [],
            transactions: [linkedSettlement],
            invoices: [paidInvoice]
        )
        #expect(paidSummary.totalSpentCents == 0)
        #expect(paidSummary.invoicedCents == 123)
        #expect(paidSummary.collectedCents == 123)
        #expect(paidSummary.outstandingCents == 0)
    }

    @Test("Canceled settlement transactions do not count as collected")
    func canceledSettlementDoesNotCountAsCollected() {
        let projectId = "p1"
        let line = InvoiceLine(
            id: "line-manual",
            sourceType: .manual,
            amountCents: 123,
            sign: .charge,
            snapshotName: "Design Fee"
        )
        let paidInvoice = makeInvoice(
            id: "inv-paid",
            projectId: projectId,
            status: .paid,
            lines: [line]
        )
        var activeSettlement = makeTransaction(
            id: "settlement-active",
            projectId: projectId,
            amountCents: 123,
            itemIds: nil
        )
        activeSettlement.settlementInvoiceId = "inv-paid"
        var canceledSettlement = makeTransaction(
            id: "settlement-canceled",
            projectId: projectId,
            amountCents: 999,
            itemIds: nil
        )
        canceledSettlement.settlementInvoiceId = "inv-paid"
        canceledSettlement.status = .canceled

        let summary = BillingSummaryCalculations.summarize(
            projectId: projectId,
            items: [],
            transactions: [activeSettlement, canceledSettlement],
            invoices: [paidInvoice]
        )

        #expect(summary.invoicedCents == 123)
        #expect(summary.collectedCents == 123)
        #expect(summary.outstandingCents == 0)
    }

    @Test("Canceled settlement transactions do not reduce sent invoice outstanding")
    func canceledSettlementDoesNotReduceOutstanding() {
        let projectId = "p1"
        let line = InvoiceLine(
            id: "line-manual",
            sourceType: .manual,
            amountCents: 123,
            sign: .charge,
            snapshotName: "Design Fee"
        )
        let sentInvoice = makeInvoice(
            id: "inv-sent",
            projectId: projectId,
            status: .sent,
            lines: [line]
        )
        var canceledSettlement = makeTransaction(
            id: "settlement-canceled",
            projectId: projectId,
            amountCents: 123,
            itemIds: nil
        )
        canceledSettlement.settlementInvoiceId = "inv-sent"
        canceledSettlement.status = .canceled

        let summary = BillingSummaryCalculations.summarize(
            projectId: projectId,
            items: [],
            transactions: [canceledSettlement],
            invoices: [sentInvoice]
        )

        #expect(summary.invoicedCents == 123)
        #expect(summary.collectedCents == 0)
        #expect(summary.outstandingCents == 123)
    }

    @Test("Canceled settlement transactions do not reduce payable balance")
    func canceledSettlementDoesNotReducePayableBalance() {
        let projectId = "p1"
        let line = InvoiceLine(
            id: "line-manual",
            sourceType: .manual,
            amountCents: 500,
            sign: .charge,
            snapshotName: "Design Fee"
        )
        let sentInvoice = makeInvoice(
            id: "inv-sent",
            projectId: projectId,
            status: .sent,
            lines: [line]
        )
        var canceledSettlement = makeTransaction(
            id: "settlement",
            projectId: projectId,
            amountCents: 500,
            itemIds: nil
        )
        canceledSettlement.settlementInvoiceId = "inv-sent"
        canceledSettlement.status = .canceled

        let balance = InvoiceLineCalculations.payableBalance(
            projectId: projectId,
            items: [],
            transactions: [canceledSettlement],
            invoices: [sentInvoice]
        )

        #expect(balance.toBusinessCents == 500)
        #expect(balance.toClientCents == 0)
    }

    @Test("Voided invoice membership doesn't count")
    func voidedDoesNotCount() {
        let item = makeItem(id: "i", projectId: "p1", purchasePriceCents: 5000)
        let inv = makeInvoice(id: "inv", projectId: "p1", status: .canceled, itemIds: ["i"])
        let summary = BillingSummaryCalculations.summarize(
            projectId: "p1", items: [item], transactions: [], invoices: [inv]
        )
        #expect(summary.totalSpentCents == 5000)
        #expect(summary.invoicedCents == 0)
        #expect(summary.collectedCents == 0)
        #expect(summary.outstandingCents == 0)
    }
}
