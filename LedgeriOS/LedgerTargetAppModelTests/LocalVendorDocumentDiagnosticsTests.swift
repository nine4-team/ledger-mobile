import Foundation
import Testing
import LedgerTargetAppModel

@Suite("Local document diagnostic disclosure")
struct LocalVendorDocumentDiagnosticsTests {
    @Test("Known secret lines and links are removed without modifying ordinary text")
    func redaction() {
        let text = "Order 123\naccess_token=private-value\nAuthorization: Bearer private-value\nSee https://private.example/object?signature=private-value\nChair 12.00"
        let safe = LocalVendorDocumentDiagnostics.redactedText(text)
        #expect(!safe.contains("private-value"))
        #expect(!safe.contains("private.example"))
        #expect(safe.contains("Order 123") && safe.contains("Chair 12.00"))
    }

    @Test("JSON retains explicit missing amounts and sanitizes nested source fields")
    func safeJSON() throws {
        let document = LocalVendorDocument(vendor: .wayfair,
            fields: ["Order": "123", "Comment": "password=private-value"],
            rows: [.init(id: 0, description: "Chair", quantity: 2, unitPrice: nil, total: "24.00",
                         attributes: ["https://private.example/asset"], details: ["Shipping": "0.00"])],
            warnings: ["apiKey: private-value"], rawText: "refresh_token=private-value", pageCount: 1)
        let json = try LocalVendorDocumentDiagnostics.json(document)
        #expect(!json.contains("private-value") && !json.contains("private.example"))
        let value = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let rows = try #require(value["rows"] as? [[String: Any]])
        #expect(rows[0]["unitPrice"] is NSNull)
        #expect(document.rawText == "refresh_token=private-value")
    }
}
