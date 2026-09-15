import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Transaction receipt read contract")
struct TransactionReceiptSnapshotTests {
    static func fixture() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
            root.appendingPathComponent("LedgerTargetMCP/tests/fixtures/transaction-receipt.json"))) as? [String: Any])
    }
    static func decode(_ wire: [String: Any]) throws -> TransactionReceiptSnapshot {
        try JSONDecoder().decode(TransactionReceiptSnapshot.self, from: JSONSerialization.data(withJSONObject: wire))
    }

    @Test func sharedMCPFixturePreservesExactAuditAndCurrentCategory() throws {
        for type in ["purchase", "return"] {
            for difference in [-1, 0, 1] {
                var wire = try Self.fixture()
                wire["type"] = type
                wire["amountMinorUnits"] = String(3050 - difference)
                let receipt = try Self.decode(wire)
                #expect(receipt.auditStatus == (difference == 0 ? .balanced : .mismatch))
                #expect(receipt.reconstruction?.variance.minorUnits == Int64(difference))
                #expect(receipt.reconstruction?.physicalItemTotal.minorUnits == 3000)
                #expect(receipt.reconstruction?.lineNet.minorUnits == 50)
                #expect(receipt.lines.first?.quantity == 10)
                #expect(receipt.items.last?.membership == .sold)
                #expect(receipt.items.last?.name == "Historical chair" && receipt.items.last?.sku == "CHAIR-2")
                #expect(receipt.items.last?.source == "Original vendor" && receipt.items.last?.currentSource == "Display vendor")
                #expect(try JSONDecoder().decode(TransactionReceiptSnapshot.self, from: JSONEncoder().encode(receipt)) == receipt)
                for kind in ["general", "fee"] {
                    var category = try #require(wire["category"] as? [String: Any])
                    category["kind"] = kind
                    wire["category"] = category
                    #expect(try Self.decode(wire).auditStatus == .notApplicable)
                }
            }
        }
    }

    @Test func groupingPreservesIdentitiesMembershipSourceAndExactReceiptAmounts() throws {
        var wire = try Self.fixture()
        func item(_ id: String, _ sku: String?, source: String = "Vendor", membership: String = "linked", amount: String? = "100") -> [String: Any] {
            ["itemId": id, "name": "Lamp", "sku": sku as Any? ?? NSNull(), "source": source,
             "currentSource": "Same display override", "membershipKind": membership,
             "amountMinorUnits": amount as Any? ?? NSNull()]
        }
        wire["items"] = [item("a", nil), item("b", "SKU"), item("c", " sku "),
            item("d", "SKU", source: "Other"), item("e", "SKU", membership: "sold")]
        let receipt = try Self.decode(wire), groups = receipt.itemGroups(membership: .linked)
        #expect(groups.count == 2)
        #expect(groups[0].rows.map(\.id.rawValue) == ["a", "b", "c"])
        #expect(groups[0].representative.id.rawValue == "b")
        #expect(groups[0].receiptTotal?.minorUnits == 300)
        #expect(groups[1].rows.map(\.id.rawValue) == ["d"])
        #expect(receipt.itemGroups(membership: .sold).first?.rows.map(\.id.rawValue) == ["e"])
        #expect(receipt.itemGroups(membership: .returned).isEmpty)

        var metadataItems = try #require(wire["items"] as? [[String: Any]])
        metadataItems[0]["imageCount"] = "0"
        metadataItems[1]["imageCount"] = "0"
        metadataItems[2]["imageCount"] = "2"
        metadataItems[0]["currentSpaceName"] = "Kitchen"
        metadataItems[1]["currentSpaceName"] = "Kitchen"
        wire["items"] = metadataItems
        var metadataGroup = try #require(Self.decode(wire).itemGroups(membership: .linked).first)
        #expect(metadataGroup.thumbnailItem.id.rawValue == "c")
        #expect(metadataGroup.spaceName == "Kitchen")
        #expect(metadataGroup.receiptTotal?.minorUnits == 300)
        metadataItems[2]["currentSpaceName"] = "Office"
        wire["items"] = metadataItems
        metadataGroup = try #require(Self.decode(wire).itemGroups(membership: .linked).first)
        #expect(metadataGroup.spaceName == "Multiple spaces")
        for count in ["-1", "01", "NaN", "9223372036854775808"] {
            metadataItems[0]["imageCount"] = count; wire["items"] = metadataItems
            #expect(throws: (any Error).self) { try Self.decode(wire) }
        }

        wire["items"] = [item("a", nil), item("b", "SKU"), item("c", "different SKU")]
        #expect(try Self.decode(wire).itemGroups(membership: .linked).count == 3)
        wire["items"] = [item("a", "SKU", amount: nil), item("b", "SKU")]
        #expect(try Self.decode(wire).itemGroups(membership: .linked).first?.receiptTotal == nil)
        wire["items"] = [item("a", "SKU", amount: "0"), item("b", "SKU", amount: "0")]
        #expect(try Self.decode(wire).itemGroups(membership: .linked).first?.receiptTotal?.minorUnits == 0)
    }

    @Test func unknownPricesAndInventoryScopeAreExplicit() throws {
        var wire = try Self.fixture()
        wire["scopeKind"] = "business_inventory"
        wire["projectId"] = NSNull(); wire["clientId"] = NSNull()
        var items = try #require(wire["items"] as? [[String: Any]])
        items[0]["amountMinorUnits"] = NSNull(); wire["items"] = items
        let receipt = try Self.decode(wire)
        #expect(receipt.auditStatus == .incompleteEvidence)
        #expect(receipt.reconstruction == nil)
        #expect(receipt.items.count == 2)
        #expect(receipt.classification.scope.ownerKind == .businessInventory)
        var category = try #require(wire["category"] as? [String: Any])
        category["kind"] = "general"; wire["category"] = category
        #expect(try Self.decode(wire).auditStatus == .notApplicable)
    }

    @Test func rejectsMalformedAndMismatchedEvidence() throws {
        let receipt = try Self.decode(Self.fixture())
        for (account, principal, transaction) in [("other", "principal", "transaction"),
            ("account", "other", "transaction"), ("account", "principal", "other")] {
            #expect(throws: TransactionReceiptSnapshot.Failure.scopeMismatch) {
                try receipt.validate(accountId: AccountID(validating: account),
                    principalId: PrincipalID(validating: principal), transactionId: TransactionID(validating: transaction))
            }
        }
        for amount in ["-1", "01", "9223372036854775808", "9223372036854775807"] {
            var wire = try Self.fixture()
            var items = try #require(wire["items"] as? [[String: Any]])
            items[0]["amountMinorUnits"] = amount; wire["items"] = items
            #expect(throws: (any Error).self) { try Self.decode(wire) }
        }
        var wire = try Self.fixture()
        var items = try #require(wire["items"] as? [[String: Any]])
        items.append(items[0]); wire["items"] = items
        #expect(throws: TransactionReceiptSnapshot.Failure.invalidEvidence) { try Self.decode(wire) }
        wire = try Self.fixture(); wire["scopeKind"] = "business_inventory"
        #expect(throws: TransactionTaxonomyFailure.invalidTransactionScope) { try Self.decode(wire) }
    }
}
