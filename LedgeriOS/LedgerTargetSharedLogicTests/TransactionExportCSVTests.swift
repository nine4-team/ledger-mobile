import Foundation
import LedgerTargetCore
import Testing

@Suite("Original CSV serializer with target snapshots")
struct TransactionExportCSVTests {
    @Test func defaultSelectionExportsWithoutRemovingLegacyOptions() throws {
        let defaults = TransactionExportCalculations.targetDefaultSelectedIds
        #expect(defaults == ExportFields.defaultSelectedIds.subtracting(["receiptImages"]))
        #expect(ExportFields.defaultSelectedIds.contains("receiptImages"))
        let selected = ExportFields.all.filter { defaults.contains($0.id) }
        for rows in [[], [try row("default")]] {
            let csv = try TransactionExportCalculations.exportTransactionsCSV(
                snapshot: snapshot(rows), selectedFields: selected)
            #expect(try manifest(csv, selectedCount: selected.count)["selectedFieldIds"] as? [String] == selected.map(\.id))
        }
    }

    @Test func selectedOrderExactMoneyEscapingAndManifest() throws {
        let a = try row("a", source: "=formula", emailed: false)
        let b = try row("b", source: "Quote\", comma\nnext", emailed: nil)
        let snapshot = try snapshot([a, b], selection: [b.transactionId, a.transactionId])
        let fields = try fields(["source", "amount", "receiptEmailed"])
        let csv = try TransactionExportCalculations.exportTransactionsCSV(snapshot: snapshot, selectedFields: fields)
        #expect(csv.hasPrefix("Record Type,Stable Transaction ID,Currency,Source,Amount,Receipt Emailed,Export Manifest JSON\n"))
        #expect(csv.contains("\ntransaction,b,USD,\"Quote\"\", comma\nnext\",90071992547409.93,,"))
        #expect(csv.hasSuffix("\ntransaction,a,USD,'=formula,90071992547409.93,false,"))
        let manifest = try manifest(csv, selectedCount: fields.count)
        #expect(manifest["snapshotHash"] as? String == snapshot.reference.snapshotHash.rawValue)
        #expect(manifest["sourceVersion"] as? String == snapshot.sourceVersion.rawValue)
        #expect(manifest["asOfEpochMilliseconds"] as? String == "1800000000000")
        #expect(manifest["selectedFieldIds"] as? [String] == ["source", "amount", "receiptEmailed"])
        #expect(manifest["orderedTransactionIds"] as? [String] == ["b", "a"])
        #expect(try TransactionExportCalculations.exportTransactionsCSV(snapshot: snapshot, selectedFields: fields) == csv)
    }

    @Test func itemCategoriesUseTheExistingSelectableColumn() throws {
        var wire = base("categories")
        wire["currentItemCategories"] = [
            ["itemId": "a", "placementId": "p-a", "categoryId": "category-a"],
            ["itemId": "b", "placementId": "p-b", "categoryId": "category-a"]]
        let row = try JSONDecoder().decode(TransactionDetailSnapshot.self, from: JSONSerialization.data(withJSONObject: wire))
        let csv = try TransactionExportCalculations.exportTransactionsCSV(snapshot: snapshot([row]), selectedFields: fields(["itemCategories"]))
        #expect(csv.hasPrefix("Record Type,Stable Transaction ID,Currency,Item Categories,Export Manifest JSON\n"))
        #expect(csv.hasSuffix("\ntransaction,categories,USD,category-a|category-a,"))
    }

    @Test func purchasedByUsesTheExistingSelectableColumn() throws {
        let selected = try fields(["purchasedBy"])
        let csv = try TransactionExportCalculations.exportTransactionsCSV(
            snapshot: snapshot([row("payment")]), selectedFields: selected)
        #expect(csv.hasPrefix("Record Type,Stable Transaction ID,Currency,Purchased By,Export Manifest JSON\n"))
        #expect(csv.hasSuffix("\ntransaction,payment,USD,Client,"))
        #expect(try manifest(csv, selectedCount: 1)["selectedFieldIds"] as? [String] == ["purchasedBy"])
        let empty = try TransactionExportCalculations.exportTransactionsCSV(
            snapshot: snapshot([]), selectedFields: selected)
        #expect(empty.components(separatedBy: "\n").count == 2)
    }

    @Test func legacyMetadataExportsWithoutFloatingPointOrInference() throws {
        var wire = base("legacy")
        wire["legacySubtotalMinorUnits"] = "9007199254740993"
        wire["legacyTaxRatePct"] = "8.12345678901234567890"
        let value = try JSONDecoder().decode(TransactionDetailSnapshot.self, from: JSONSerialization.data(withJSONObject: wire))
        let selected = try fields(["subtotal", "taxRatePct"])
        let csv = try TransactionExportCalculations.exportTransactionsCSV(snapshot: snapshot([value]), selectedFields: selected)
        #expect(csv.hasSuffix("\ntransaction,legacy,USD,90071992547409.93,8.12345678901234567890,"))
        let unknown = try TransactionExportCalculations.exportTransactionsCSV(snapshot: snapshot([row("unknown")]), selectedFields: selected)
        #expect(unknown.hasSuffix("\ntransaction,unknown,USD,,,"))
    }

    @Test func emptyExportStillHasManifestAndUnsupportedFieldsFail() throws {
        let empty = try snapshot([])
        let csv = try TransactionExportCalculations.exportTransactionsCSV(snapshot: empty, selectedFields: fields(["amount"]))
        #expect(csv.components(separatedBy: "\n").count == 2)
        #expect(try manifest(csv, selectedCount: 1)["snapshotId"] as? String == empty.reference.snapshotID.rawValue)
        let noMatches = try snapshot([row("a")], selection: [])
        let processed = try TransactionExportCalculations.exportTransactionsCSV(snapshot: noMatches, selectedFields: fields(["amount"]))
        #expect(try manifest(processed, selectedCount: 1)["orderedTransactionIds"] as? [String] == [])
        #expect(processed != csv)
        for id in ["receiptImages", "status"] {
            #expect(throws: TransactionExportValues.Failure.unavailableField(id)) {
                try TransactionExportCalculations.exportTransactionsCSV(snapshot: empty, selectedFields: fields([id]))
            }
        }
        let amount = try fields(["amount"])
        for invalid in [[], amount + amount] {
            #expect(throws: TransactionExportCalculations.TargetFailure.invalidFields) {
                try TransactionExportCalculations.exportTransactionsCSV(snapshot: empty, selectedFields: invalid)
            }
        }
        #expect(throws: TransactionExportValues.Failure.unknownField("typo")) {
            try TransactionExportCalculations.exportTransactionsCSV(snapshot: empty,
                selectedFields: [.init(id: "typo", label: "Typo", defaultSelected: false)])
        }
    }

    @Test func receiptColumnsPreserveReadableAndStructuredEvidence() throws {
        var wire = base("receipt")
        wire["origin"] = "vendor_payment"; wire["amountMinorUnits"] = "100"
        wire["category"] = ["id": "items", "name": "Items", "kind": "itemized", "revision": "1"]
        var receipt = wire
        receipt["items"] = [[String: Any]]()
        receipt["nonItemReceiptLines"] = [["id": "tax", "description": "Sales Tax", "amountMinorUnits": "100",
            "effect": "increase", "quantity": "9223372036854775807"]]
        wire["receipt"] = receipt
        let row = try JSONDecoder().decode(TransactionDetailSnapshot.self, from: JSONSerialization.data(withJSONObject: wire))
        let selected: [ExportFieldConfig] = [
            .init(id: "receiptLines", label: "Receipt Lines", defaultSelected: true),
            .init(id: "receiptLinesJSON", label: "Receipt Lines JSON", defaultSelected: true),
            .init(id: "receiptVariance", label: "Receipt Variance", defaultSelected: true)]
        let csv = try TransactionExportCalculations.exportTransactionsCSV(snapshot: snapshot([row]), selectedFields: selected)
        #expect(csv.contains("tax: Sales Tax [increase; 100 USD minor units; quantity=9223372036854775807]"))
        #expect(csv.contains("\"\"quantity\"\":\"\"9223372036854775807\"\""))
        #expect(csv.contains("\"\"amountMinorUnits\"\":\"\"100\"\""))
        #expect(csv.hasSuffix(",0.00,"))
    }

    private func base(_ id: String) -> [String: Any] {
        ["accountId": "account", "principalId": "principal", "transactionId": id,
         "scopeKind": "project", "projectId": "project", "clientId": "client", "type": "purchase",
         "role": "standalone", "origin": "firebase_client_payment", "currency": "USD",
         "amountMinorUnits": "9007199254740993"]
    }
    private func row(_ id: String, source: String = "Client", emailed: Bool? = nil) throws -> TransactionDetailSnapshot {
        var wire = base(id); wire["source"] = source; wire["hasEmailReceipt"] = emailed
        return try JSONDecoder().decode(TransactionDetailSnapshot.self, from: JSONSerialization.data(withJSONObject: wire))
    }
    private func snapshot(_ rows: [TransactionDetailSnapshot], selection: [TransactionID]? = nil) throws -> TransactionExportSnapshot {
        try .init(scope: .project(accountId: AccountID(validating: "account"), projectId: ProjectID(validating: "project"),
            clientId: ClientID(validating: "client")), principalId: PrincipalID(validating: "principal"), update: .ready(rows),
            orderedTransactionIDs: selection, asOf: .init(validating: 1_800_000_000_000),
            sourceVersion: .init(validating: "source-1"), visibilityScopeID: .make(bytes: Data("scope".utf8)),
            authorityVersion: .init(validating: "transaction-export-v1"))
    }
    private func fields(_ ids: [String]) throws -> [ExportFieldConfig] {
        try ids.map { id in try #require(ExportFields.all.first { $0.id == id }) }
    }
    private func manifest(_ csv: String, selectedCount: Int) throws -> [String: Any] {
        let line = try #require(csv.components(separatedBy: "\n").dropFirst().first)
        let prefix = "manifest," + String(repeating: ",", count: selectedCount + 2)
        #expect(line.hasPrefix(prefix))
        let quoted = String(line.dropFirst(prefix.count))
        #expect(quoted.first == "\"" && quoted.last == "\"")
        let json = quoted.dropFirst().dropLast().replacingOccurrences(of: "\"\"", with: "\"")
        return try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }
}
