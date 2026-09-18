import Foundation
import LedgerTargetCore
import LedgerTargetAppModel
import Testing

@Suite("Exact Transaction audit presentation")
struct TransactionReceiptAuditPresentationTests {
    @Test func validLiveAuditIgnoresOverflowingLegacyAcquisitionSum() throws {
        let value = try receipt { json in
            json["amountMinorUnits"] = "2"; json["requiresLiveAdjustments"] = true
            json["nonItemReceiptLines"] = []
            json["items"] = ["a","b"].map { ["itemId":$0,"amountMinorUnits":"9223372036854775807","membershipKind":"linked"] }
            json["liveAdjustments"] = ["totalMinorUnits":"2","adjustmentsMinorUnits":"0",
                "differenceNumerator":"0","differenceDenominator":"1","isBalanced":true,"isProvisional":false,
                "items":["a","b"].map { ["itemId":$0,"numerator":"1","denominator":"1",
                    "unadjustedMinorUnits":"1","adjustmentsMinorUnits":"0","projectPriceMinorUnits":"1"] }]
        }
        #expect(value.reconstruction == nil)
        #expect(value.items.allSatisfy { $0.amount?.minorUnits == .max })
        let model = try TransactionReceiptAuditPresentation(receipt:value)
        #expect(model.isComplete && model.statusLabel == "Balanced")
    }
    @Test func liveAuditUsesOriginalFractionAndDoesNotCallSubcentDifferenceBalanced() throws {
        let value = try receipt { json in
            json["amountMinorUnits"] = "3"; json["requiresLiveAdjustments"] = true
            json["nonItemReceiptLines"] = [["id":"shipping","description":"Shipping","amountMinorUnits":"1","effect":"increase"]]
            json["items"] = [["itemId":"a","amountMinorUnits":"99","membershipKind":"linked"]]
            json["liveAdjustments"] = ["totalMinorUnits":"3","adjustmentsMinorUnits":"1",
                "differenceNumerator":"1","differenceDenominator":"3","isBalanced":false,"isProvisional":true,
                "items":[["itemId":"a","numerator":"5","denominator":"3",
                    "unadjustedMinorUnits":"2","adjustmentsMinorUnits":"1","projectPriceMinorUnits":"3"]]]
        }
        let model = try TransactionReceiptAuditPresentation(receipt: value, locale: Locale(identifier:"en_US"))
        #expect(!model.isComplete)
        #expect(model.statusLabel.contains("exactly 1/3 cents"))
        #expect(model.details.contains("Items subtotal: $0.02"))
        #expect(model.details.contains("Adjustments: $0.01"))
        #expect(model.details.contains("Allocations are provisional while the receipt is unbalanced."))
    }
    private func receipt(_ edit: (inout [String: Any]) -> Void = { _ in }) throws -> TransactionReceiptSnapshot {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
            root.appendingPathComponent("LedgerTargetMCP/tests/fixtures/transaction-receipt.json"))) as? [String: Any])
        edit(&json)
        return try JSONDecoder().decode(TransactionReceiptSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
    }
    @Test func exactTotalsAndOneCentMismatch() throws {
        for difference in [-1, 0, 1] {
            let value = try receipt { $0["amountMinorUnits"] = String(3050 - difference) }
            let model = try TransactionReceiptAuditPresentation(receipt: value, locale: Locale(identifier: "en_US"))
            #expect(model.isApplicable && model.isComplete == (difference == 0))
            #expect(model.details.contains("Physical Item total: $30.00"))
            #expect(model.details.contains("Sold items (1): $20.00"))
            #expect(model.details.contains("Other receipt lines — increases: $1.00"))
            #expect(model.details.contains("Other receipt lines — decreases: $0.50"))
            #expect(model.details.contains("Other receipt lines — net: $0.50"))
            #expect(model.details.contains("Reconstructed total: $30.50"))
            #expect(model.statusLabel == (difference == 0 ? "Balanced" : "Difference: \(difference < 0 ? "-" : "")$0.01"))
            #expect(!model.details.joined().lowercased().contains("subtotal"))
        }
    }
    @Test func unknownPriceIsNotZeroAndCurrentCategoryControlsApplicability() throws {
        for kind in ["itemized", "general", "fee"] {
            let value = try receipt { json in
                var items = json["items"] as! [[String: Any]]
                items[1]["amountMinorUnits"] = NSNull(); json["items"] = items
                var category = json["category"] as! [String: Any]
                category["kind"] = kind; json["category"] = category
            }
            let model = try TransactionReceiptAuditPresentation(receipt: value, locale: Locale(identifier: "en_US"))
            #expect(model.isApplicable == (kind == "itemized"))
            #expect(!model.isComplete && model.progressPercentage == nil)
            #expect(model.missingItemIds.map(\.rawValue) == ["b"])
            #expect(model.missingItems.first?.name == "Historical chair")
            #expect(model.missingItems.first?.sku == "CHAIR-2")
            #expect(model.details.contains("Sold items (1): Unknown"))
            #expect(model.details.contains("Physical Item total: Unknown"))
            #expect(model.details.contains("Difference: Unknown"))
            #expect(model.details.contains("Other receipt lines — net: $0.50"))
        }
    }
    @Test func displayedMoneyDoesNotRoundThroughDouble() throws {
        let value = try receipt { json in
            json["amountMinorUnits"] = "9007199254740993"
            json["items"] = [["itemId": "large", "amountMinorUnits": "9007199254740993", "membershipKind": "linked"]]
            json["nonItemReceiptLines"] = []
        }
        let model = try TransactionReceiptAuditPresentation(receipt: value, locale: Locale(identifier: "en_US"))
        #expect(model.isComplete)
        #expect(model.details.contains("Transaction total: $90,071,992,547,409.93"))
        #expect(model.details.contains("Reconstructed total: $90,071,992,547,409.93"))
    }

    @Test func missingLabelUsesIdentityWithoutInventingPrice() throws {
        let value = try receipt { json in
            json["items"] = [["itemId": "unknown", "amountMinorUnits": NSNull(), "membershipKind": "returned"]]
        }
        let model = try TransactionReceiptAuditPresentation(receipt: value)
        #expect(model.missingItems.first?.name == "Item unknown")
        #expect(model.missingItems.first?.sku == nil)
        #expect(!model.isComplete && model.progressPercentage == nil)
    }
}
