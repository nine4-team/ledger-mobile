import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Transaction export field values")
struct TransactionExportValuesTests {
    @Test func existingFieldsUseRecordedEvidence() throws {
        var wire = try TransactionDetailSnapshotTests.fixture()
        wire["source"] = "=untrusted"; wire["notes"] = "Comma, quote\"\nnext"
        wire["createdAtMilliseconds"] = "1800000000123"
        let row = try TransactionDetailSnapshotTests.decode(wire)
        #expect(try cell("amount", row) == .money(row.amount))
        #expect(row.amount.minorUnits == 9_007_199_254_740_993)
        #expect(try cell("source", row) == .text("=untrusted")) // Serializer owns escaping.
        #expect(try cell("notes", row) == .text("Comma, quote\"\nnext"))
        #expect(try cell("receiptEmailed", row) == .boolean(false))
        #expect(try cell("createdAt", row) == .text("2027-01-15T08:00:00.123Z"))
        #expect(try cell("projectId", row) == .unknown)
        for type in ["purchase", "return"] {
            wire["type"] = type
            let typed = try TransactionDetailSnapshotTests.decode(wire)
            #expect(try cell("transactionType", typed) == .text(type == "purchase" ? "Purchase" : "Return"))
            #expect(try cell("amount", typed) == .money(row.amount)) // No sign inversion.
        }
        wire["hasEmailReceipt"] = NSNull(); wire["source"] = NSNull()
        let unknown = try TransactionDetailSnapshotTests.decode(wire)
        #expect(try cell("receiptEmailed", unknown) == .unknown)
        #expect(try cell("source", unknown) == .unknown)
    }

    @Test func purchaseOwnerFollowsCanonicalScopeForPurchasesAndReturns() throws {
        try TransactionExportValues.validate(fieldID: "purchasedBy")
        for scope in ["project", "business_inventory"] {
            for type in ["purchase", "return"] {
                var wire = try TransactionDetailSnapshotTests.fixture()
                wire["scopeKind"] = scope; wire["type"] = type
                wire["projectId"] = scope == "project" ? "project" : NSNull()
                wire["clientId"] = scope == "project" ? "client" : NSNull()
                let row = try TransactionDetailSnapshotTests.decode(wire)
                #expect(try cell("purchasedBy", row) == .text(scope == "project" ? "Client" : "1584"))
                #expect(try cell("amount", row) == .money(row.amount))
            }
        }
        var wire = try TransactionDetailSnapshotTests.fixture()
        wire["origin"] = "firebase_client_payment"; wire["category"] = NSNull()
        wire["scopeKind"] = "project"; wire["projectId"] = "project"; wire["clientId"] = "client"
        wire["type"] = "purchase"
        let imported = try TransactionDetailSnapshotTests.decode(wire)
        #expect(imported.origin == .importedClientPayment)
        #expect(try cell("purchasedBy", imported) == .text("Client"))
    }

    @Test func orderedLinesRetainIdentityWordingSignAndExactQuantity() throws {
        var wire = try TransactionReceiptSnapshotTests.fixture()
        var lines = try #require(wire["nonItemReceiptLines"] as? [[String: Any]])
        lines[0]["quantity"] = String(Int64.max)
        lines[0]["description"] = "=original, \"wording\"\nnext"
        wire["nonItemReceiptLines"] = lines
        let row = try detail(wire)
        guard case .text(let json) = try cell("receiptLinesJSON", row),
              case .text(let readable) = try cell("receiptLines", row) else {
            Issue.record("Receipt lines must be exported in both forms"); return
        }
        let restored = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        #expect(restored.compactMap { $0["id"] as? String } == ["tax", "discount"])
        #expect(restored[0]["description"] as? String == lines[0]["description"] as? String)
        #expect(restored[0]["quantity"] as? String == String(Int64.max))
        #expect(restored[1]["effect"] as? String == "decrease")
        #expect(restored[1]["amountMinorUnits"] as? String == "50")
        #expect(readable.contains("quantity=9223372036854775807"))
        #expect(readable.contains("discount:") && readable.contains("decrease; 50 USD minor units"))
        #expect(try cell("receiptItemTotal", row) == .money(row.receipt!.reconstruction!.physicalItemTotal))
        #expect(try cell("receiptVariance", row) == .money(row.receipt!.reconstruction!.variance))
        #expect(try cell("receiptAuditStatus", row) == .text("balanced"))
    }

    @Test func unknownPricesDoNotInventAuditTotalsAndNoReceiptIsNotEmptyReceipt() throws {
        var wire = try TransactionReceiptSnapshotTests.fixture()
        var items = try #require(wire["items"] as? [[String: Any]])
        items[0]["amountMinorUnits"] = NSNull(); wire["items"] = items
        let unknown = try detail(wire)
        #expect(try cell("receiptAuditStatus", unknown) == .text("incompleteEvidence"))
        for field in ["receiptItemTotal", "receiptReconstructedTotal", "receiptVariance"] {
            #expect(try cell(field, unknown) == .unknown)
        }
        let noReceipt = try TransactionDetailSnapshotTests.decode(TransactionDetailSnapshotTests.fixture())
        #expect(try cell("receiptLinesJSON", noReceipt) == .unknown)
        wire["nonItemReceiptLines"] = [[String: Any]]()
        #expect(try cell("receiptLinesJSON", detail(wire)) == .text("[]"))
    }

    @Test func legacyColumnsNeverBackSolveSubtotalOrTax() throws {
        let absent = try TransactionExportSnapshotTests.row()
        #expect(try cell("subtotal", absent) == .unknown)
        #expect(try cell("taxRatePct", absent) == .unknown)
        var receipt = try TransactionReceiptSnapshotTests.fixture()
        receipt["legacySubtotalMinorUnits"] = "9007199254740993"
        receipt["legacyTaxRatePct"] = "8.12345678901234567890"
        let row = try detail(receipt)
        #expect(try cell("subtotal", row) == .money(row.legacySubtotal!))
        #expect(try cell("taxRatePct", row) == .text("8.12345678901234567890"))
        #expect(row.receipt?.reconstruction == absent.receipt?.reconstruction)
    }

    @Test func unavailableLegacyFieldsCannotSilentlyDisappear() throws {
        let row = try TransactionExportSnapshotTests.row()
        for id in ["reimbursementType", "status", "receiptImages",
                   "inventorySaleDirection"] {
            #expect(throws: TransactionExportValues.Failure.unavailableField(id)) { try cell(id, row) }
        }
        #expect(throws: TransactionExportValues.Failure.unknownField("typo")) { try cell("typo", row) }
    }

    @Test func itemCategoriesUseExplicitCurrentAttributionAndKeepUnknownDistinct() throws {
        var wire = try TransactionDetailSnapshotTests.fixture()
        #expect(throws: TransactionExportValues.Failure.incompleteField("itemCategories")) {
            try cell("itemCategories", TransactionDetailSnapshotTests.decode(wire))
        }
        wire["scopeKind"] = "project"; wire["projectId"] = "project"; wire["clientId"] = "client"
        wire["currentItemCategories"] = [
            ["itemId": "b", "placementId": "p-b", "categoryId": "category-other"],
            ["itemId": "a", "placementId": "p-a", "categoryId": "category-other"]]
        let row = try TransactionDetailSnapshotTests.decode(wire)
        try TransactionExportValues.validate(fieldID: "itemCategories")
        #expect(try cell("itemCategories", row) == .text("category-other|category-other"))
        #expect(try JSONDecoder().decode(TransactionDetailSnapshot.self, from: JSONEncoder().encode(row)) == row)
        #expect(row.currentItemCategories?.map(\.itemId.rawValue) == ["a", "b"])
        wire["currentItemCategories"] = [["itemId": "a", "placementId": "p-a", "categoryId": NSNull()]]
        #expect(throws: TransactionExportValues.Failure.incompleteField("itemCategories")) {
            try cell("itemCategories", TransactionDetailSnapshotTests.decode(wire))
        }
        wire["currentItemCategories"] = [] as [String]
        #expect(try cell("itemCategories", TransactionDetailSnapshotTests.decode(wire)) == .text(""))
        let duplicate = ["itemId": "a", "placementId": "p-a", "categoryId": "category-other"]
        wire["currentItemCategories"] = [duplicate, duplicate]
        #expect(throws: TransactionDetailSnapshot.Failure.invalidEvidence) { try TransactionDetailSnapshotTests.decode(wire) }
        wire["currentItemCategories"] = [duplicate]
        wire["scopeKind"] = "business_inventory"; wire["projectId"] = NSNull(); wire["clientId"] = NSNull()
        #expect(throws: TransactionDetailSnapshot.Failure.invalidEvidence) { try TransactionDetailSnapshotTests.decode(wire) }
    }

    private func cell(_ field: String, _ row: TransactionDetailSnapshot) throws -> TransactionExportValues.Cell {
        try TransactionExportValues.cell(fieldID: field, row: row)
    }
    private func detail(_ receipt: [String: Any]) throws -> TransactionDetailSnapshot {
        var wire = receipt; wire["role"] = "standalone"; wire["origin"] = "vendor_payment"
        wire["receipt"] = receipt
        return try TransactionDetailSnapshotTests.decode(wire)
    }
}
