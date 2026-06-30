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

    private func makeCategory(id: String, supportedTypes: [TransactionType]) -> BudgetCategory {
        var category = BudgetCategory()
        category.id = id
        category.name = id
        category.supportedTypes = supportedTypes
        return category
    }

    @Test("Membership across draft/sent/paid/voided produces correct totals")
    func mixedStatuses() {
        let projectId = "p1"

        // Items — unbilled, on draft, on sent (invoiced-only), on paid.
        let unbilledItem = makeItem(id: "i-unbilled", projectId: projectId, purchasePriceCents: 1000)
        let draftItem = makeItem(id: "i-draft", projectId: projectId, purchasePriceCents: 2000)
        let sentItem = makeItem(id: "i-sent", projectId: projectId, purchasePriceCents: 3000)
        let paidItem = makeItem(id: "i-paid", projectId: projectId, purchasePriceCents: 4000)
        let items = [unbilledItem, draftItem, sentItem, paidItem]

        // Transactions — non-itemized variants + one itemized (excluded).
        let unbilledTx = makeTransaction(id: "t-unbilled", projectId: projectId, amountCents: 500, itemIds: nil)
        let sentTx = makeTransaction(id: "t-sent", projectId: projectId, amountCents: 700, itemIds: [])
        let paidTx = makeTransaction(id: "t-paid", projectId: projectId, amountCents: 900, itemIds: [])
        let itemizedTx = makeTransaction(id: "t-itemized", projectId: projectId, amountCents: 9999, itemIds: ["a", "b"])
        let transactions = [unbilledTx, sentTx, paidTx, itemizedTx]

        let invoices: [Invoice] = [
            makeInvoice(id: "inv-draft", projectId: projectId, status: .draft, itemIds: ["i-draft"]),
            makeInvoice(id: "inv-sent", projectId: projectId, status: .sent, itemIds: ["i-sent"], transactionIds: ["t-sent"]),
            makeInvoice(id: "inv-paid", projectId: projectId, status: .paid, itemIds: ["i-paid"], transactionIds: ["t-paid"]),
            makeInvoice(id: "inv-voided", projectId: projectId, status: .voided, itemIds: ["i-unbilled"]),
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
            budgetCategories: ["items": makeCategory(id: "items", supportedTypes: [.purchase, .return])]
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
            budgetCategories: ["items": makeCategory(id: "items", supportedTypes: [.purchase, .return])]
        )
        #expect(summary.totalSpentCents == 0)
        #expect(BillingSummaryCalculations.isNonItemized(
            tx,
            budgetCategories: ["items": makeCategory(id: "items", supportedTypes: [.purchase, .return])]
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
            budgetCategories: ["services": makeCategory(id: "services", supportedTypes: [.expense])]
        )
        #expect(summary.totalSpentCents == 12_345)
        #expect(BillingSummaryCalculations.isNonItemized(
            tx,
            budgetCategories: ["services": makeCategory(id: "services", supportedTypes: [.expense])]
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
                "items": makeCategory(id: "items", supportedTypes: [.purchase, .return]),
                "services": makeCategory(id: "services", supportedTypes: [.expense]),
            ]
        )

        #expect(!membership.toInvoiceTransactionIds.contains("t-itemized-missing-items"))
        #expect(membership.toInvoiceTransactionIds.contains("t-service"))
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

    @Test("Voided invoice membership doesn't count")
    func voidedDoesNotCount() {
        let item = makeItem(id: "i", projectId: "p1", purchasePriceCents: 5000)
        let inv = makeInvoice(id: "inv", projectId: "p1", status: .voided, itemIds: ["i"])
        let summary = BillingSummaryCalculations.summarize(
            projectId: "p1", items: [item], transactions: [], invoices: [inv]
        )
        #expect(summary.totalSpentCents == 5000)
        #expect(summary.invoicedCents == 0)
        #expect(summary.collectedCents == 0)
        #expect(summary.outstandingCents == 0)
    }
}
