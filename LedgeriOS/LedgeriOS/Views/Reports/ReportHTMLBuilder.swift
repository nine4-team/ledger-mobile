import Foundation

/// Generates HTML strings for PDF report rendering via WKWebView.
/// Styles ported from `src/utils/reportHtml.ts` — keep in sync.
enum ReportHTMLBuilder {

    // MARK: - Client Summary

    static func clientSummary(
        data: ClientSummaryData,
        projectName: String,
        clientName: String?,
        businessName: String?,
        logoBase64: String?,
        resolvedReceiptURLs: [String: URL]
    ) -> String {
        var body = ""

        body += headerHTML(
            businessName: businessName,
            reportTitle: "Client Summary",
            projectName: projectName,
            clientName: clientName,
            logoBase64: logoBase64
        )

        // Overview cards
        body += """
        <div class="overview-grid">
          <div class="card">
            <div class="card-label">Total Spent</div>
            <div class="card-value">\(formatCents(data.totalSpentCents))</div>
          </div>
          <div class="card">
            <div class="card-label">Market Value</div>
            <div class="card-value">\(formatCents(data.totalMarketValueCents))</div>
          </div>
          <div class="card">
            <div class="card-label">Total Saved</div>
            <div class="card-value">\(formatCents(data.totalSavedCents))</div>
          </div>
        </div>
        """

        // Category breakdown
        if !data.categoryBreakdowns.isEmpty {
            let rows = data.categoryBreakdowns.map { b in
                """
                <tr>
                  <td>\(esc(b.categoryName))</td>
                  <td class="right">\(formatCents(b.spentCents))</td>
                </tr>
                """
            }.joined()

            body += """
            <h2>Category Breakdown</h2>
            <table>
              <thead><tr>
                <th>Category</th>
                <th class="right" style="width:120px">Total</th>
              </tr></thead>
              <tbody>\(rows)</tbody>
            </table>
            """
        }

        // Items
        if !data.items.isEmpty {
            let rows = data.items.map { ci in
                let priceCents = ReportAggregationCalculations.clientPriceCents(for: ci.item)
                let badge = receiptBadgeHTML(ci.receiptLink, resolvedURLs: resolvedReceiptURLs)
                return """
                <tr>
                  <td>\(esc(ci.item.displayName))\(badge)</td>
                  <td>\(esc(ci.item.currentSource ?? ci.item.source ?? ""))</td>
                  <td>\(esc(ci.spaceName ?? ""))</td>
                  <td class="right">\(formatCents(priceCents))</td>
                </tr>
                """
            }.joined()

            body += """
            <h2>Items (\(data.items.count))</h2>
            <table>
              <thead><tr>
                <th>Item</th>
                <th style="width:120px">Source</th>
                <th style="width:120px">Space</th>
                <th class="right" style="width:110px">Project Price</th>
              </tr></thead>
              <tbody>\(rows)</tbody>
            </table>
            """

            // Totals
            body += """
            <table class="totals-table">
              <tbody>
                <tr>
                  <td class="total-label">Total Spent</td>
                  <td class="total-value">\(formatCents(data.totalSpentCents))</td>
                </tr>
                <tr>
                  <td class="total-label">Market Value</td>
                  <td class="total-value">\(formatCents(data.totalMarketValueCents))</td>
                </tr>
                <tr class="net-row">
                  <td class="total-label">Total Saved</td>
                  <td class="total-value">\(formatCents(data.totalSavedCents))</td>
                </tr>
              </tbody>
            </table>
            """
        }

        return wrapHTML(title: "Client Summary", body: body)
    }

    // MARK: - Invoice

    static func invoice(
        data: InvoiceReportData,
        projectName: String,
        clientName: String,
        businessName: String?,
        logoBase64: String?,
        invoiceName: String? = nil,
        invoiceStatusLabel: String? = nil,
        invoiceDate: Date? = nil,
        notes: String? = nil
    ) -> String {
        var body = ""

        let title: String = {
            if let invoiceName, !invoiceName.isEmpty { return "Invoice — \(invoiceName)" }
            return "Invoice"
        }()

        body += headerHTML(
            businessName: businessName,
            reportTitle: title,
            projectName: projectName,
            clientName: clientName.isEmpty ? nil : clientName,
            logoBase64: logoBase64
        )

        // Optional invoice meta (date / status)
        var metaExtras: [String] = []
        if let invoiceDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            metaExtras.append("<strong>Date:</strong> \(esc(formatter.string(from: invoiceDate)))")
        }
        if let invoiceStatusLabel, !invoiceStatusLabel.isEmpty {
            metaExtras.append("<strong>Status:</strong> \(esc(invoiceStatusLabel))")
        }
        if !metaExtras.isEmpty {
            body += #"<div class="meta">\#(metaExtras.joined(separator: "<br/>"))</div>"#
        }

        // Charges
        if !data.chargeLines.isEmpty {
            body += invoiceSectionHTML(title: "Charges", lines: data.chargeLines)
        }

        // Credits
        if !data.creditLines.isEmpty {
            body += invoiceSectionHTML(title: "Credits", lines: data.creditLines)
        }

        // Totals
        body += """
        <table class="totals-table">
          <tbody>
            <tr>
              <td class="total-label">Charges Total</td>
              <td class="total-value">\(formatCents(data.chargesSubtotalCents))</td>
            </tr>
            <tr>
              <td class="total-label">Credits Total</td>
              <td class="total-value">(\(formatCents(data.creditsSubtotalCents)))</td>
            </tr>
            <tr class="net-row">
              <td class="total-label">Net Amount Due</td>
              <td class="total-value">\(formatCents(data.netDueCents))</td>
            </tr>
          </tbody>
        </table>
        """

        if let notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body += #"<div class="meta"><strong>Notes:</strong><br/>\#(esc(notes))</div>"#
        }

        return wrapHTML(title: "Invoice", body: body)
    }

    // MARK: - Property Management

    static func propertyManagement(
        data: PropertyManagementData,
        projectName: String,
        clientName: String?,
        businessName: String?,
        logoBase64: String?
    ) -> String {
        var body = ""

        body += headerHTML(
            businessName: businessName,
            reportTitle: "Property Management Summary",
            projectName: projectName,
            clientName: clientName,
            logoBase64: logoBase64
        )

        // Overview cards
        body += """
        <div class="overview-grid">
          <div class="card">
            <div class="card-label">Total Items</div>
            <div class="card-value">\(data.totalItemCount)</div>
          </div>
          <div class="card">
            <div class="card-label">Total Market Value</div>
            <div class="card-value">\(formatCents(data.totalMarketValueCents))</div>
          </div>
        </div>
        """

        // Per-space groups
        for group in data.spaceGroups {
            body += propertySpaceSectionHTML(
                title: group.space.name,
                items: group.items,
                marketValueCents: group.marketValueCents
            )
        }

        // No space
        if !data.noSpaceItems.isEmpty {
            let noSpaceValue = data.noSpaceItems.reduce(0) {
                $0 + ReportAggregationCalculations.propertyValueCents(for: $1)
            }
            body += propertySpaceSectionHTML(
                title: "No Space",
                items: data.noSpaceItems,
                marketValueCents: noSpaceValue
            )
        }

        return wrapHTML(title: "Property Management Summary", body: body)
    }

    // MARK: - Private Helpers

    private static func receiptBadgeHTML(
        _ link: ReceiptLink,
        resolvedURLs: [String: URL]
    ) -> String {
        switch link {
        case .invoice:
            return #" <span class="receipt-badge">Invoice</span>"#
        case .receiptURL(let urlString):
            if let url = resolvedURLs[urlString] {
                return #" <a href="\#(esc(url.absoluteString))" class="receipt-badge receipt-link">Receipt ↗</a>"#
            }
            return #" <span class="receipt-badge">Receipt</span>"#
        case .none:
            return ""
        }
    }

    private static func invoiceSectionHTML(title: String, lines: [InvoiceLineEntry]) -> String {
        let rows = lines.map { line in
            let priceClass = line.isMissingPrice ? #" class="missing-price""# : ""
            return """
            <tr>
              <td>\(esc(line.name))</td>
              <td class="right"\(priceClass)>\(formatCents(line.priceCents))</td>
            </tr>
            """
        }.joined()

        return """
        <h2>\(esc(title))</h2>
        <table>
          <thead><tr>
            <th>Item</th>
            <th class="right" style="width:120px">Amount</th>
          </tr></thead>
          <tbody>\(rows)</tbody>
        </table>
        """
    }

    private static func propertySpaceSectionHTML(
        title: String,
        items: [Item],
        marketValueCents: Int
    ) -> String {
        let rows = items.map { item in
            let valueCents = ReportAggregationCalculations.propertyValueCents(for: item)
            let valueStr = valueCents == 0
                ? #"<span class="missing-price">No value</span>"#
                : formatCents(valueCents)
            return """
            <tr>
              <td>\(esc(item.displayName))</td>
              <td>\(esc(item.currentSource ?? item.source ?? ""))</td>
              <td class="right">\(valueStr)</td>
            </tr>
            """
        }.joined()

        return """
        <div class="space-header">
          <span>\(esc(title))</span>
          <span>\(formatCents(marketValueCents))</span>
        </div>
        <table>
          <thead><tr>
            <th>Item</th>
            <th style="width:110px">Source</th>
            <th class="right" style="width:110px">Market Value</th>
          </tr></thead>
          <tbody>\(rows)</tbody>
        </table>
        """
    }

    private static func headerHTML(
        businessName: String?,
        reportTitle: String,
        projectName: String,
        clientName: String?,
        logoBase64: String?
    ) -> String {
        let logoHTML: String
        if let base64 = logoBase64 {
            logoHTML = #"<img class="report-logo" src="data:image/png;base64,\#(base64)" alt="Logo" />"#
        } else {
            logoHTML = ""
        }

        var metaLines = "<strong>Project:</strong> \(esc(projectName))"
        if let clientName, !clientName.isEmpty {
            metaLines += "<br/><strong>Client:</strong> \(esc(clientName))"
        }

        return """
        <div class="report-header">
          \(logoHTML)
          <div class="report-header-info">
            <h1>\(esc(businessName ?? ""))</h1>
            <div class="report-title">\(esc(reportTitle))</div>
            <div class="meta">\(metaLines)</div>
          </div>
        </div>
        """
    }

    private static func wrapHTML(title: String, body: String) -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <title>\(esc(title))</title>
          <style>\(reportStyles)</style>
        </head>
        <body>
          \(body)
        </body>
        </html>
        """
    }

    private static func esc(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#039;")
    }

    private static func formatCents(_ cents: Int) -> String {
        CurrencyFormatting.formatCentsWithDecimals(cents)
    }

    // MARK: - CSS (from reportHtml.ts getReportStyles)

    private static let reportStyles = """
    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }
    body {
      font-family: -apple-system, 'Helvetica Neue', Helvetica, Arial, sans-serif;
      font-size: 13px;
      line-height: 1.5;
      color: #1a1a1a;
      padding: 40px;
      max-width: 800px;
      margin: 0 auto;
    }
    @media print {
      body { padding: 20px; }
    }
    .report-header {
      display: flex;
      align-items: flex-start;
      gap: 16px;
      margin-bottom: 32px;
      padding-bottom: 20px;
      border-bottom: 2px solid #987e55;
    }
    .report-logo {
      width: 80px;
      height: 80px;
      object-fit: contain;
      border-radius: 8px;
    }
    .report-header-info { flex: 1; }
    .report-header-info h1 {
      font-size: 22px;
      font-weight: 700;
      color: #987e55;
      margin-bottom: 4px;
    }
    .report-header-info .report-title {
      font-size: 16px;
      font-weight: 600;
      color: #333;
      margin-bottom: 8px;
    }
    .report-header-info .meta {
      font-size: 12px;
      color: #666;
      line-height: 1.6;
    }
    h2 {
      font-size: 16px;
      font-weight: 600;
      color: #987e55;
      margin-top: 28px;
      margin-bottom: 12px;
      padding-bottom: 6px;
      border-bottom: 1px solid #e0d5c5;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      margin-bottom: 16px;
      page-break-inside: auto;
    }
    thead { background-color: #f7f3ee; }
    th {
      font-size: 11px;
      font-weight: 600;
      text-transform: uppercase;
      color: #666;
      text-align: left;
      padding: 8px 10px;
      border-bottom: 1px solid #e0d5c5;
    }
    th.right, td.right { text-align: right; }
    td {
      padding: 8px 10px;
      border-bottom: 1px solid #f0ebe4;
      vertical-align: top;
    }
    tr:nth-child(even) td { background-color: #faf8f5; }
    tr { page-break-inside: avoid; }
    .totals-table {
      width: auto;
      margin-left: auto;
      margin-top: 12px;
      margin-bottom: 24px;
    }
    .totals-table td {
      padding: 6px 12px;
      border-bottom: none;
      background-color: transparent !important;
    }
    .totals-table .total-label {
      font-weight: 600;
      color: #333;
      text-align: right;
    }
    .totals-table .total-value {
      font-weight: 600;
      text-align: right;
      min-width: 100px;
    }
    .totals-table .net-row td {
      border-top: 2px solid #987e55;
      font-size: 15px;
      font-weight: 700;
      color: #987e55;
      padding-top: 10px;
    }
    .missing-price {
      font-style: italic;
      color: #c0392b;
      font-size: 11px;
    }
    .card {
      background: #faf8f5;
      border: 1px solid #e0d5c5;
      border-radius: 8px;
      padding: 16px;
      margin-bottom: 12px;
    }
    .card-label {
      font-size: 11px;
      font-weight: 600;
      text-transform: uppercase;
      color: #666;
      margin-bottom: 4px;
    }
    .card-value {
      font-size: 20px;
      font-weight: 700;
      color: #1a1a1a;
    }
    .overview-grid {
      display: flex;
      gap: 12px;
      margin-bottom: 20px;
    }
    .overview-grid .card { flex: 1; }
    .receipt-badge {
      display: inline-block;
      font-size: 10px;
      font-weight: 600;
      color: #987e55;
      background: #f7f3ee;
      border-radius: 4px;
      padding: 2px 6px;
      margin-left: 6px;
      text-decoration: none;
    }
    .receipt-link:hover {
      text-decoration: underline;
    }
    .space-header {
      display: flex;
      justify-content: space-between;
      align-items: baseline;
      font-size: 16px;
      font-weight: 600;
      color: #987e55;
      margin-top: 28px;
      margin-bottom: 12px;
      padding-bottom: 6px;
      border-bottom: 1px solid #e0d5c5;
    }
    .space-header span:last-child {
      font-size: 13px;
      font-weight: 600;
      color: #333;
    }
    """
}
