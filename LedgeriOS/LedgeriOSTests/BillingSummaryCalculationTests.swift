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
        transactionIds: [String] = []
    ) -> Invoice {
        var inv = Invoice()
        inv.id = id
        inv.projectId = projectId
        inv.status = status
        inv.itemIds = itemIds
        inv.transactionIds = transactionIds
        return inv
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
        // Invoiced (any non-voided: draft+sent+paid): items 2000+3000+4000 + tx 700+900 = 10600
        #expect(summary.invoicedCents == 10600)
        // Collected (paid only): items 4000 + tx 900 = 4900
        #expect(summary.collectedCents == 4900)
        // Outstanding = total - collected
        #expect(summary.outstandingCents == 7200)
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
        let tx = makeTransaction(id: "t", projectId: "p1", amountCents: 10_000, itemIds: ["x"])
        let inv = makeInvoice(id: "inv", projectId: "p1", status: .paid, transactionIds: ["t"])
        let summary = BillingSummaryCalculations.summarize(
            projectId: "p1", items: [], transactions: [tx], invoices: [inv]
        )
        #expect(summary.totalSpentCents == 0)
        #expect(summary.collectedCents == 0)
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
        #expect(summary.outstandingCents == 5000)
    }
}
