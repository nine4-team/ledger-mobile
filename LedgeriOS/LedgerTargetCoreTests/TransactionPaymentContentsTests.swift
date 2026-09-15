import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Client payment contents preserve historical membership")
struct TransactionPaymentContentsTests {
    private func fixture() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: root
            .appendingPathComponent("LedgerTargetMCP/tests/fixtures/payment-contents.json"))) as? [String: Any])
    }
    private func decode(_ wire: [String: Any]) throws -> TransactionPaymentContents {
        try JSONDecoder().decode(TransactionPaymentContents.self, from: JSONSerialization.data(withJSONObject: wire))
    }

    @Test func closedConnectionsAndFrozenInvoiceShareOnePhysicalIdentityWithoutLosingFacts() throws {
        let value = try decode(fixture())
        #expect(value.connections.count == 2)
        #expect(value.connections[0].endedAt == "2026-09-01")
        #expect(value.itemIDs.map(\.rawValue) == ["direct-item", "invoiced-item"])
        #expect(value.invoice?.lines.first?.description == "Frozen description")
        #expect(value.invoice?.lines.first?.categoryId.rawValue == "old-category")
        #expect(value.invoice?.total.minorUnits == 125)
        #expect(value.items?.map(\.id) == value.itemIDs)
        #expect(value.items?.first?.name == "Current lamp" && value.items?.first?.imageCount == 1)
        #expect(value.items?.first?.currentSpaceName == "Other Project room")
        #expect(try JSONDecoder().decode(TransactionPaymentContents.self,
            from: JSONEncoder().encode(value)) == value)
    }

    @Test func standalonePaymentIsKnownEmptyButNeverAnInventedInvoice() throws {
        var wire = try fixture(); wire["invoice"] = NSNull(); wire["connections"] = [] as [String]; wire["items"] = [] as [String]
        let value = try decode(wire)
        #expect(value.itemIDs.isEmpty && value.invoice == nil)
    }

    @Test func embeddedFrozenAmountsRemainExactAcrossNativeAndMCP() throws {
        for (literal, amount) in [("125.0", Int64(125)), ("1.25e2", Int64(125)),
            ("9007199254740993", Int64(9_007_199_254_740_993)), ("9223372036854775807", Int64.max)] {
            var wire = try fixture(), invoice = try #require(wire["invoice"] as? [String: Any])
            var lines = try #require(invoice["lines"] as? [[String: Any]])
            let source = try #require(lines[0]["source_snapshot_json"] as? String)
            lines[0]["source_snapshot_json"] = source.replacingOccurrences(of: "\"minorUnits\":125",
                with: "\"minorUnits\":\(literal)")
            lines[0]["signed_amount_minor_units"] = String(amount)
            invoice["lines"] = lines; invoice["total_minor_units"] = String(amount); wire["invoice"] = invoice
            #expect(try decode(wire).invoice?.total.minorUnits == amount)
            lines[0]["signed_amount_minor_units"] = String(amount - 1)
            invoice["lines"] = lines; invoice["total_minor_units"] = String(amount - 1); wire["invoice"] = invoice
            #expect(throws: FrozenInvoiceContentsFailure.invalidPriceSnapshot) { try decode(wire) }
        }
    }

    @Test func detailBindsPaymentHistoryToExactPrincipalTransactionScopeAndCurrency() throws {
        var wire = try TransactionDetailSnapshotTests.fixture()
        wire["origin"] = "firebase_client_payment"; wire["category"] = NSNull(); wire["type"] = "purchase"
        wire["scopeKind"] = "project"; wire["projectId"] = "project"; wire["clientId"] = "client"
        wire["accountId"] = "account"; wire["principalId"] = "principal"; wire["transactionId"] = "payment"
        wire["paymentContents"] = try fixture()
        let detail = try TransactionDetailSnapshotTests.decode(wire)
        #expect(detail.receipt == nil && detail.paymentContents?.itemIDs.count == 2)
        #expect(try JSONDecoder().decode(TransactionDetailSnapshot.self, from: JSONEncoder().encode(detail)) == detail)
        for (key, value) in [("principalId", "other"), ("transactionId", "other"), ("currency", "EUR")] {
            var invalid = wire; invalid[key] = value
            #expect(throws: TransactionPaymentContents.Failure.scopeMismatch) { try TransactionDetailSnapshotTests.decode(invalid) }
        }
        wire["origin"] = "vendor_payment"
        wire["category"] = ["id": "category", "name": "Items", "kind": "itemized", "revision": "1"]
        #expect(throws: TransactionDetailSnapshot.Failure.invalidEvidence) { try TransactionDetailSnapshotTests.decode(wire) }
    }

    @Test func rejectsWrongInvoiceScopeDuplicateLinksAndInvalidFrozenMoney() throws {
        for change in ["foreign", "missing", "duplicate", "negative-image-count"] {
            var wire = try fixture(), items = try #require(wire["items"] as? [[String: Any]])
            switch change {
            case "foreign": items[0]["itemId"] = "foreign"
            case "missing": items.removeLast()
            case "duplicate": items.append(items[0])
            default: items[0]["imageCount"] = "-1"
            }
            wire["items"] = items
            #expect(throws: TransactionPaymentContents.Failure.invalidEvidence) { try decode(wire) }
        }
        for key in ["account_id", "project_id", "client_id", "purchase_id"] {
            var wire = try fixture(), invoice = try #require(wire["invoice"] as? [String: Any])
            invoice[key] = "other"; wire["invoice"] = invoice
            #expect(throws: (any Error).self) { try decode(wire) }
        }
        var wire = try fixture(), links = try #require(wire["connections"] as? [[String: Any]])
        links.append(links[0]); wire["connections"] = links
        #expect(throws: TransactionPaymentContents.Failure.invalidEvidence) { try decode(wire) }
        wire = try fixture()
        var invoice = try #require(wire["invoice"] as? [String: Any])
        invoice["total_minor_units"] = "126"; wire["invoice"] = invoice
        #expect(throws: FrozenInvoiceContentsFailure.totalMismatch) { try decode(wire) }
        let value = try decode(fixture())
        #expect(throws: TransactionPaymentContents.Failure.scopeMismatch) {
            try value.validate(scope: .project(accountId: AccountID(validating: "account"),
                projectId: ProjectID(validating: "project"), clientId: ClientID(validating: "client")),
                principalId: PrincipalID(validating: "other"), transactionId: TransactionID(validating: "payment"),
                currency: CurrencyCode(validating: "USD"))
        }
    }
}
