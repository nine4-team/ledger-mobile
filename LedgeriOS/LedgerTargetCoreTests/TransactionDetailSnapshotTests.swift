import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Canonical Transaction display evidence")
struct TransactionDetailSnapshotTests {
    static func fixture() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
            root.appendingPathComponent("LedgerTargetMCP/tests/fixtures/transaction-detail.json"))) as? [String: Any])
    }
    static func decode(_ wire: [String: Any]) throws -> TransactionDetailSnapshot {
        try JSONDecoder().decode(TransactionDetailSnapshot.self, from: JSONSerialization.data(withJSONObject: wire))
    }

    @Test func exactMetadataAndScope() throws {
        let value = try Self.decode(Self.fixture())
        #expect(value.amount.minorUnits == 9_007_199_254_740_993)
        #expect(value.classification.type == .return)
        #expect(value.classification.scope.ownerKind == .businessInventory)
        #expect(value.classification.scope.projectId == nil)
        #expect(value.source == "Café vendor")
        #expect(value.transactionDate == "2024-02-29")
        #expect(value.createdAtMilliseconds == 1_709_251_200_123)
        #expect(value.notes == "First line\nSecond line")
        #expect(value.paymentMethod == "Company card")
        #expect(value.hasEmailReceipt == false)
        try value.validate(scope: value.classification.scope, principalId: value.principalId, transactionId: value.transactionId)
        #expect(throws: TransactionDetailSnapshot.Failure.scopeMismatch) {
            try value.validate(scope: .businessInventory(accountId: AccountID(validating: "other")),
                principalId: value.principalId, transactionId: value.transactionId)
        }
        #expect(throws: TransactionDetailSnapshot.Failure.scopeMismatch) {
            try value.validate(scope: value.classification.scope, principalId: PrincipalID(validating: "other"),
                transactionId: value.transactionId)
        }
        #expect(throws: TransactionDetailSnapshot.Failure.scopeMismatch) {
            try value.validate(scope: value.classification.scope, principalId: value.principalId,
                transactionId: TransactionID(validating: "other"))
        }
    }

    @Test func legacyAmountsAreExactOptionalAndNotReceiptInputs() throws {
        var wire = try Self.fixture()
        wire["legacySubtotalMinorUnits"] = "9007199254740993"
        wire["legacyTaxRatePct"] = "8.1234567890123456789012345678901234567890"
        let row = try Self.decode(wire)
        #expect(row.legacySubtotal?.minorUnits == 9_007_199_254_740_993)
        #expect(row.legacySubtotal?.currency == row.amount.currency)
        #expect(row.legacyTaxRatePct == wire["legacyTaxRatePct"] as? String)
        #expect(row.receipt == nil)
        #expect(try JSONDecoder().decode(TransactionDetailSnapshot.self, from: JSONEncoder().encode(row)) == row)
        for invalid in ["NaN", "Infinity", "1e2", " 8", "8\n", "8.", ".5", "01", "", "-", "8.5.2"] {
            wire["legacyTaxRatePct"] = invalid
            #expect(throws: TransactionDetailSnapshot.Failure.invalidEvidence) { try Self.decode(wire) }
        }
        wire["legacyTaxRatePct"] = "0.0000"; wire["legacySubtotalMinorUnits"] = "0"
        let zero = try Self.decode(wire)
        #expect(zero.legacyTaxRatePct == "0.0000" && zero.legacySubtotal?.minorUnits == 0)
        wire["legacySubtotalMinorUnits"] = "9223372036854775808"
        #expect(throws: TransactionDetailSnapshot.Failure.invalidEvidence) { try Self.decode(wire) }
    }

    @Test func clientPaymentItemCountUsesRetainedMembershipNotCurrentCategories() throws {
        var wire = try Self.fixture()
        wire["scopeKind"] = "project"; wire["projectId"] = "project"; wire["clientId"] = "client"
        wire["origin"] = "firebase_client_payment"; wire["category"] = NSNull(); wire["type"] = "purchase"
        #expect(try Self.decode(wire).linkedItemCount == nil)
        wire["currentItemCategories"] = [] as [String]
        #expect(try Self.decode(wire).linkedItemCount == nil)
        var contents: [String: Any] = ["accountId": wire["accountId"]!, "principalId": wire["principalId"]!,
            "transactionId": wire["transactionId"]!, "projectId":"project", "clientId":"client", "connections": [] as [String]]
        wire["paymentContents"] = contents
        #expect(try Self.decode(wire).linkedItemCount == 0)
        wire["currentItemCategories"] = [["itemId": "item", "placementId": "placement", "categoryId": NSNull()]]
        contents["connections"] = [["id":"closed-link","itemId":"item","placementId":"placement","endedAt":"2026-09-01"]]
        wire["paymentContents"] = contents
        let linked = try Self.decode(wire)
        #expect(linked.linkedItemCount == 1 && linked.receipt == nil)
        var departed = wire; departed["currentItemCategories"] = [] as [String]
        #expect(try Self.decode(departed).linkedItemCount == 1)
        // Missing category blocks category export, not proof of the Item link.
        #expect(throws: TransactionExportValues.Failure.incompleteField("itemCategories")) {
            try TransactionExportValues.cell(fieldID: "itemCategories", row: linked)
        }
    }

    @Test func unknownIsNotDefaulted() throws {
        var wire = try Self.fixture()
        for field in ["source", "transactionDate", "createdAtMilliseconds", "notes", "paymentMethod", "hasEmailReceipt"] {
            wire[field] = NSNull()
        }
        let value = try Self.decode(wire)
        #expect(value.source == nil && value.transactionDate == nil && value.createdAtMilliseconds == nil)
        #expect(value.notes == nil && value.paymentMethod == nil && value.hasEmailReceipt == nil)
        #expect(value.receipt == nil && value.linkedItemCount == nil)
        #expect(value.legacySubtotal == nil && value.legacyTaxRatePct == nil)
    }

    @Test func receiptUsesSameIdentityAmountsCategoryAndHistoricalEvidence() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let receipt = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
            root.appendingPathComponent("LedgerTargetMCP/tests/fixtures/transaction-receipt.json"))) as? [String: Any])
        var wire = try Self.fixture()
        for field in ["accountId", "principalId", "transactionId", "scopeKind", "projectId", "clientId", "type", "amountMinorUnits", "currency", "category"] {
            wire[field] = receipt[field]
        }
        wire["receipt"] = receipt
        let row = try Self.decode(wire)
        #expect(row.linkedItemCount == 1 && row.receipt?.items.count == 2)
        #expect(row.receipt?.auditStatus == .balanced && row.receipt?.reconstruction?.physicalItemTotal.minorUnits == 3000)
        for (field, value) in [("accountId", "foreign"), ("principalId", "foreign"), ("transactionId", "foreign"),
            ("projectId", "foreign"), ("clientId", "foreign"), ("amountMinorUnits", "3051"), ("currency", "EUR")] {
            var invalid = receipt; invalid[field] = value; wire["receipt"] = invalid
            #expect(throws: TransactionDetailSnapshot.Failure.invalidEvidence) { try Self.decode(wire) }
        }
        var invalid = receipt
        var category = try #require(receipt["category"] as? [String: Any]); category["revision"] = "2"
        invalid["category"] = category; wire["receipt"] = invalid
        #expect(throws: TransactionDetailSnapshot.Failure.invalidEvidence) { try Self.decode(wire) }
    }

    @Test(arguments: ["2023-02-29", "1900-02-29", "2024-04-31", "2024-13-01", "0000-01-01", "2024-1-01", "infinity", "2024-01-01T00:00:00Z"])
    func rejectsInvalidCalendarDate(_ date: String) throws {
        var wire = try Self.fixture(); wire["transactionDate"] = date
        #expect(throws: TransactionDetailSnapshot.Failure.invalidEvidence) { try Self.decode(wire) }
    }

    @Test(arguments: ["0", "-1", "01", "1.5", "9223372036854775808"])
    func rejectsInvalidMoney(_ amount: String) throws {
        var wire = try Self.fixture(); wire["amountMinorUnits"] = amount
        #expect(throws: TransactionDetailSnapshot.Failure.invalidEvidence) { try Self.decode(wire) }
    }

    @Test func importedPaymentIsNotVendorReceipt() throws {
        var wire = try Self.fixture()
        wire["origin"] = "firebase_client_payment"
        #expect(throws: TransactionDetailSnapshot.Failure.invalidEvidence) { try Self.decode(wire) }
        wire["category"] = NSNull(); wire["scopeKind"] = "project"; wire["type"] = "purchase"
        wire["projectId"] = "project-one"; wire["clientId"] = "client-one"
        let value = try Self.decode(wire)
        #expect(value.origin == .importedClientPayment && value.category == nil)
        #expect(value.classification.scope.clientId?.rawValue == "client-one")
        wire["type"] = "transfer"
        #expect(throws: TransactionDetailSnapshot.Failure.invalidEvidence) { try Self.decode(wire) }
    }
}
