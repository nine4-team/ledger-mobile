import Foundation

@main struct InvoiceReportHTMLChecks {
    static func main() {
        let lines = (0..<90).map {
            InvoiceLineEntry(name: "Invoice row \(String(format: "%03d", $0)) <original>",
                exactPriceCents: Decimal(9_007_199_254_740_993 as Int64), isMissingPrice: false)
        }
        let data = InvoiceReportData(chargeLines: lines,
            creditLines: [.init(name: "Returned Item", priceCents: 101, isMissingPrice: false)])
        let html = ReportHTMLBuilder.invoice(data: data, projectName: "Project & name",
            clientName: "Client", businessName: "Design studio", logoBase64: nil,
            invoiceName: "INV-TEST", invoiceStatusLabel: "Paid", notes: "<script>never execute</script>",
            currencyCode: "USD", totalLabel: "Invoice Total", provenance: "Invoice revision 3")
        precondition(html.contains("Invoice Total") && !html.contains("Net Amount Due"))
        precondition(html.contains("&lt;original&gt;") && !html.contains("<script>"))
        precondition(html.contains("90,071,992,547,409.93"))
        precondition(!html.contains("<strong>Date:</strong>"))
        for index in 0..<90 { precondition(html.contains("Invoice row \(String(format: "%03d", index))")) }
        precondition(html.contains("Returned Item") && html.contains("Invoice revision 3"))
        precondition(data.chargesSubtotalCents == Decimal(9_007_199_254_740_993 as Int64) * 90)
        precondition(data.netDueCents == data.chargesSubtotalCents - 101)
        precondition(html.contains("default-src 'none'"))
        let groupedLines = [
            InvoiceLineEntry(name: "first", exactPriceCents: 101, isMissingPrice: false, categoryId: "a", categoryName: "Same name"),
            InvoiceLineEntry(name: "second", exactPriceCents: 202, isMissingPrice: false, categoryId: "b", categoryName: "Same name"),
            InvoiceLineEntry(name: "third", exactPriceCents: 303, isMissingPrice: false, categoryId: "a", categoryName: "Same name"),
            InvoiceLineEntry(name: "unknown", exactPriceCents: 0, isMissingPrice: false, categoryId: "missing")
        ]
        let groups = InvoiceReportData.groups(groupedLines)
        precondition(groups.count == 3 && groups[0].lines.map(\.name) == ["first", "third"])
        precondition(groups.map(\.subtotalCents) == [404, 202, 0])
        let unicodeGroups = InvoiceReportData.groups([
            .init(name: "one", exactPriceCents: 1, isMissingPrice: false, categoryId: "é"),
            .init(name: "two", exactPriceCents: 2, isMissingPrice: false, categoryId: "e\u{301}")
        ])
        precondition(unicodeGroups.count == 2)
        let groupedHTML = ReportHTMLBuilder.invoice(data: .init(chargeLines: groupedLines, creditLines: []),
            projectName: "Project", clientName: "Client", businessName: nil, logoBase64: nil)
        precondition(groupedHTML.contains("Category name unavailable") && groupedHTML.contains("Category Total"))
        precondition(groupedHTML.contains("$4.04") && groupedHTML.contains("$2.02") && groupedHTML.contains("$6.06"))
        precondition(InvoiceReportData.groups(lines).count == 1)
        print("PASS: shared Invoice HTML escaping, exact cents, all90 rows, provenance and no invented date")
    }
}
