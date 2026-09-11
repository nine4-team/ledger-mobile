import Foundation

/// Explicit local disclosure of the selected document only. No workspace,
/// session, account directory, or stored-object metadata is accepted here.
public enum LocalVendorDocumentDiagnostics {
    public static func redactedText(_ text: String) -> String {
        text.components(separatedBy: .newlines).map { line in
            if line.range(of: #"(?i)\b(authorization|bearer|password|passwd|secret|cookie|token|(?:access|refresh|id)[_ -]?token|client[_ -]?secret|api[_ -]?key)\b"#,
                          options: .regularExpression) != nil {
                return "[Sensitive line omitted]"
            }
            return line.replacingOccurrences(of: #"(?i)\b[a-z][a-z0-9+.-]*://\S+"#,
                                             with: "[Link omitted]", options: .regularExpression)
        }.joined(separator: "\n")
    }

    public static func json(_ document: LocalVendorDocument) throws -> String {
        let fields = document.fields.mapValues(redactedText)
        let rows: [[String: Any]] = document.rows.map { row in
            var result: [String: Any] = ["sourceRow": row.id, "description": redactedText(row.description),
                "quantity": row.quantity, "total": redactedText(row.total),
                "attributes": row.attributes.map(redactedText), "details": row.details.mapValues(redactedText)]
            result["unitPrice"] = row.unitPrice.map { redactedText($0) as Any } ?? NSNull()
            result["sku"] = row.sku.map { redactedText($0) as Any } ?? NSNull()
            return result
        }
        let value: [String: Any] = ["vendor": document.vendor.rawValue, "pages": document.pageCount,
            "fields": fields, "rows": rows, "warnings": document.warnings.map(redactedText),
            "rawText": redactedText(document.rawText)]
        let bytes = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: bytes, as: UTF8.self)
    }
}
