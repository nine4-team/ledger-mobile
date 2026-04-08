import Testing
@testable import LedgeriOS

@Suite("InvoiceReportAggregation (per-invoice)")
struct InvoiceReportAggregationTests {

    @Test("Resolves referenced items + non-itemized tx into charge lines")
    func resolvesReferences() {
        let item1 = makeItem(id: "i1", name: "Chair", purchasePriceCents: 10_000, projectPriceCents: 15_000)
        let item2 = makeItem(id: "i2", name: "Table", purchasePriceCents: 20_000, projectPriceCents: 25_000)
        let tx = makeTransaction(id: "t1", amountCents: 5_000, source: "Install crew", itemIds: [])

        var invoice = Invoice()
        invoice.id = "inv1"
        invoice.itemIds = ["i1", "i2"]
        invoice.transactionIds = ["t1"]

        let result = ReportAggregationCalculations.computeInvoiceReport(
            for: invoice,
            items: [item1, item2],
            transactions: [tx]
        )

        #expect(result.chargeLines.count == 3)
        #expect(result.creditLines.isEmpty)
        #expect(result.chargesSubtotalCents == 15_000 + 25_000 + 5_000)
        #expect(result.hasFallbackPrices == false)
    }

    @Test("Item without projectPrice falls back to purchasePrice and flags missing")
    func fallbackPrice() {
        let item = makeItem(id: "i1", name: "Lamp", purchasePriceCents: 8_000, projectPriceCents: nil)
        var invoice = Invoice()
        invoice.id = "inv1"
        invoice.itemIds = ["i1"]

        let result = ReportAggregationCalculations.computeInvoiceReport(
            for: invoice,
            items: [item],
            transactions: []
        )

        #expect(result.chargeLines.count == 1)
        #expect(result.chargeLines[0].priceCents == 8_000)
        #expect(result.chargeLines[0].isMissingPrice == true)
        #expect(result.hasFallbackPrices == true)
    }

    @Test("Unknown ids are silently skipped")
    func unknownIdsSkipped() {
        let item = makeItem(id: "i1", name: "Chair", purchasePriceCents: 10_000, projectPriceCents: 10_000)
        var invoice = Invoice()
        invoice.id = "inv1"
        invoice.itemIds = ["i1", "missing-item"]
        invoice.transactionIds = ["missing-tx"]

        let result = ReportAggregationCalculations.computeInvoiceReport(
            for: invoice,
            items: [item],
            transactions: []
        )

        #expect(result.chargeLines.count == 1)
        #expect(result.chargesSubtotalCents == 10_000)
    }
}
