import Foundation
import Testing
@testable import LedgeriOS

@Suite("Billing Summary Calculation Tests")
struct BillingSummaryCalculationTests {

    @Test("Mixed billing statuses produce correct totals")
    func mixedStatuses() {
        let items: [Item] = [
            makeItem(purchasePriceCents: 1000, billingStatus: nil),         // unbilled (nil)
            makeItem(purchasePriceCents: 2000, billingStatus: .unbilled),   // unbilled
            makeItem(purchasePriceCents: 3000, billingStatus: .invoiced),   // invoiced
            makeItem(purchasePriceCents: 4000, billingStatus: .paid),       // paid
        ]
        let transactions: [Transaction] = [
            // Non-itemized (no itemIds) — count
            makeTransaction(amountCents: 500, itemIds: nil, billingStatus: nil),
            makeTransaction(amountCents: 700, itemIds: [], billingStatus: .invoiced),
            makeTransaction(amountCents: 900, itemIds: [], billingStatus: .paid),
            // Itemized — excluded (children carry the value)
            makeTransaction(amountCents: 9999, itemIds: ["a", "b"], billingStatus: nil),
        ]

        let summary = BillingSummaryCalculations.summarize(items: items, transactions: transactions)

        // Items: 1000+2000+3000+4000 = 10000, Tx (non-itemized only): 500+700+900 = 2100
        #expect(summary.totalSpentCents == 12100)
        // Invoiced (invoiced + paid): items 3000+4000 + tx 700+900 = 8600
        #expect(summary.invoicedCents == 8600)
        // Collected (paid only): items 4000 + tx 900 = 4900
        #expect(summary.collectedCents == 4900)
        // Outstanding = total - collected = 12100 - 4900 = 7200
        #expect(summary.outstandingCents == 7200)
    }

    @Test("Empty inputs produce zero summary")
    func emptyInputs() {
        let summary = BillingSummaryCalculations.summarize(items: [], transactions: [])
        #expect(summary == BillingSummaryCalculations.Summary(
            totalSpentCents: 0, invoicedCents: 0, collectedCents: 0, outstandingCents: 0
        ))
    }

    @Test("Itemized transactions are excluded")
    func itemizedExcluded() {
        let txs: [Transaction] = [
            makeTransaction(amountCents: 10_000, itemIds: ["x"], billingStatus: .paid),
        ]
        let summary = BillingSummaryCalculations.summarize(items: [], transactions: txs)
        #expect(summary.totalSpentCents == 0)
        #expect(summary.collectedCents == 0)
    }
}
