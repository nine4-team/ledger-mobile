import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetMigrationCore

@Suite("Vendor purchase import parameters")
struct FirebaseVendorPurchaseImportParametersTests {
    private func plan() throws -> FirebaseAcquisitionConversion.Plan {
        let account = try AccountID(validating: "account")
        let source = FirebaseSourceDocument(accountScopeID: "source",
            documentPathSegments: ["accounts", "source", "transactions", "purchase"],
            entityCode: "transactions", evidenceKind: .record,
            fields: .map([.init(key: "amountCents", value: .integer("9007199254740993"))]), sourceRecordID: "purchase")
        return .init(source: source,
            classification: try .init(type: .purchase, scope: .businessInventory(accountId: account), role: .standalone),
            amountCents: 9007199254740993, sourceItemIDs: ["current"], historicalItemIDs: ["historical"],
            sourceProjectScope: .project(accountId: account, projectId: try .init(validating: "project"), clientId: try .init(validating: "client")),
            sourceCategory: source, categoryKind: .itemized)
    }
    private func items() throws -> [FirebaseVendorPurchaseItemMapping] {
        [.init(sourceItemID: "current", relationshipID: "link-current", targetItemID: try .init(validating: "item-current"),
            amountMinorUnits: 9007199254740993, membership: .linked),
         .init(sourceItemID: "historical", relationshipID: "link-history", targetItemID: try .init(validating: "item-history"),
            amountMinorUnits: nil, membership: .sold)]
    }
    private func make(_ items: [FirebaseVendorPurchaseItemMapping]) throws -> FirebaseVendorPurchaseImportParameters {
        try .make(plan: plan(), targetID: .init(validating: "target-purchase"),
            targetCategoryID: .init(validating: "target-category"), currency: .init(validating: "USD"), items: items, lines: [])
    }
    @Test func preservesHistoryExactAmountsAndExplicitNulls() throws {
        let p = try make(items())
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
        #expect(json["p_scope_kind"] as? String == "business_inventory")
        #expect(json["p_project_id"] is NSNull)
        #expect(json["p_client_id"] is NSNull)
        #expect(json["p_amount"] as? String == "9007199254740993")
        let rows = try #require(json["p_items"] as? [[String: Any]])
        #expect(rows[0]["amountMinorUnits"] as? String == "9007199254740993")
        #expect(rows[1]["amountMinorUnits"] is NSNull)
        #expect(rows[1]["membershipKind"] as? String == "sold")
        #expect(p.p_source_bytes == "\\x" + (try plan().source.canonicalEvidenceData()).map { String(format: "%02x", $0) }.joined())
    }
    @Test func rejectsMissingHistoricalAndDuplicateMappings() throws {
        let rows = try items()
        #expect(throws: FirebaseVendorPurchaseImportFailure.self) { try make([rows[0]]) }
        #expect(throws: FirebaseVendorPurchaseImportFailure.self) { try make(rows + [rows[1]]) }
        let invalid = FirebaseVendorPurchaseItemMapping(sourceItemID: "historical", relationshipID: "link-history",
            targetItemID: try .init(validating: "item-current"), amountMinorUnits: nil, membership: .sold)
        #expect(throws: FirebaseVendorPurchaseImportFailure.self) { try make([rows[0], invalid]) }
    }
}
