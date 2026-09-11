import Foundation

/// Pure presentation of the validated report projection. No fetches, asset
/// resolution, eligibility decisions or recalculation of report totals.
public enum PropertyManagementReportHTML {
    public static func render(_ snapshot: PropertyManagementReportSnapshot) -> String {
        let date = ISO8601DateFormatter().string(from: Date(
            timeIntervalSince1970: Double(snapshot.provenance.asOf.rawValue) / 1_000))
        let body: String
        if snapshot.totals.itemCount == 0 {
            body = "<p>No data for this report</p>"
        } else {
            body = snapshot.groups.map { group in
                let rows = group.rows.map { item in
                    "<tr><td>\(escape(item.name))</td><td>\(escape(item.sku ?? "Not provided"))</td><td class=\"amount\">\(escape(value(item.marketValue)))</td></tr>"
                }.joined()
                return """
                <section><h2>\(escape(group.name))</h2>
                <table><thead><tr><th>Item</th><th>SKU</th><th>Market value</th></tr></thead>
                <tbody>\(rows)</tbody></table>\(totals(group.totals))</section>
                """
            }.joined()
        }
        return """
        <!doctype html><html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
        <title>Property Management — \(escape(snapshot.project.name))</title>
        <style>
        body{font:15px -apple-system,BlinkMacSystemFont,sans-serif;color:#161616;margin:28px}
        h1{font-size:25px}h2{font-size:19px;margin-top:28px}p{line-height:1.45}
        table{width:100%;border-collapse:collapse;table-layout:fixed}
        th,td{text-align:left;vertical-align:top;padding:8px;border-bottom:1px solid #ddd;overflow-wrap:anywhere}
        .amount{text-align:right}th:last-child{text-align:right}thead{display:table-header-group}
        tr{break-inside:avoid}h2{break-after:avoid}.totals{font-weight:600}footer{margin-top:28px;font-size:11px;overflow-wrap:anywhere}
        @media print{body{margin:0}@page{margin:18mm}}
        </style></head><body>
        <h1>Property Management</h1><h2>\(escape(snapshot.project.name))</h2>
        <p>\(escape(snapshot.project.address ?? "Property address not provided"))<br>As of \(escape(date))</p>
        \(body)
        <h2>Report totals</h2>\(totals(snapshot.totals))
        <footer>Snapshot: \(escape(snapshot.reference.snapshotID.rawValue))<br>
        Source: \(escape(snapshot.provenance.source.kind))<br>
        Data version: \(escape(snapshot.provenance.localDataVersion?.rawValue ?? snapshot.sourceSetHash.rawValue))<br>
        Authority: \(escape(snapshot.provenance.authorityVersion.rawValue))</footer>
        </body></html>
        """
    }

    /// Ledger's report v1 market values are cents, as specified by the source
    /// marketValueCents field. Keep integer precision, including Int64.min.
    public static func value(_ amount: Money?) -> String {
        guard let amount else { return "Unknown" }
        let magnitude = amount.minorUnits.magnitude
        let fraction = magnitude % 100
        return "\(amount.currency.rawValue) \(amount.minorUnits < 0 ? "-" : "")\(magnitude / 100).\(fraction < 10 ? "0" : "")\(fraction)"
    }

    private static func totals(_ totals: PropertyManagementReportTotals) -> String {
        if let complete = totals.totalMarketValue {
            return "<p class=\"totals\">Items: \(totals.itemCount) · Total market value: \(escape(value(complete)))</p>"
        }
        return "<p class=\"totals\">Items: \(totals.itemCount) · Known market value subtotal: \(escape(value(totals.knownMarketValueSubtotal))) · Unknown values: \(totals.unknownMarketValueCount)</p>"
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
