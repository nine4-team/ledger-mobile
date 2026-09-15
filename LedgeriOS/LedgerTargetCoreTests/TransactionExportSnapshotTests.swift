import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Complete authorized Transaction export snapshot")
struct TransactionExportSnapshotTests {
    static func row(_ id: String = "transaction", notes: String? = nil) throws -> TransactionDetailSnapshot {
        var wire = try TransactionReceiptSnapshotTests.fixture()
        wire["transactionId"] = id
        var detail = wire
        detail["role"] = "standalone"; detail["origin"] = "vendor_payment"
        detail["receipt"] = wire; detail["notes"] = notes
        return try TransactionDetailSnapshotTests.decode(detail)
    }
    static func snapshot(_ rows: [TransactionDetailSnapshot], selection: [TransactionID]? = nil,
                         version: String = "source-1", visibility: String = "allowed") throws -> TransactionExportSnapshot {
        try .init(scope: .project(accountId: AccountID(validating: "account"), projectId: ProjectID(validating: "project"),
            clientId: ClientID(validating: "client")), principalId: PrincipalID(validating: "principal"), update: .ready(rows),
            orderedTransactionIDs: selection, asOf: .init(validating: 1_800_000_000_000), sourceVersion: .init(validating: version),
            visibilityScopeID: .make(bytes: Data(visibility.utf8)), authorityVersion: .init(validating: "transaction-export-v1"))
    }

    @Test func exactWireRoundTrip() throws {
        let original = try TransactionDetailSnapshotTests.decode(TransactionDetailSnapshotTests.fixture())
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        #expect(try JSONDecoder().decode(TransactionDetailSnapshot.self, from: data) == original)
        let wire = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(wire["scopeKind"] as? String == "business_inventory")
        #expect(wire["amountMinorUnits"] as? String == "9007199254740993")
        #expect(wire["hasEmailReceipt"] as? Bool == false)
        let receipt = try Self.row()
        #expect(try JSONDecoder().decode(TransactionDetailSnapshot.self, from: encoder.encode(receipt)) == receipt)
        var unknown = try TransactionReceiptSnapshotTests.fixture()
        var items = try #require(unknown["items"] as? [[String: Any]])
        items[1]["amountMinorUnits"] = NSNull(); unknown["items"] = items
        var lines = try #require(unknown["nonItemReceiptLines"] as? [[String: Any]])
        lines[0]["quantity"] = String(Int64.max); unknown["nonItemReceiptLines"] = lines
        let value = try TransactionReceiptSnapshotTests.decode(unknown)
        let restored = try JSONDecoder().decode(TransactionReceiptSnapshot.self, from: encoder.encode(value))
        #expect(restored == value && restored.items[1].amount == nil)
        #expect(restored.lines.map(\.id.rawValue) == ["tax", "discount"])
        #expect(restored.lines.first?.quantity == .max && restored.lines.last?.effect == .decrease)
    }

    @Test func deterministicSourceAndExplicitProcessedOrder() throws {
        let a = try Self.row("a"), b = try Self.row("b")
        let all = try Self.snapshot([b, a]), again = try Self.snapshot([a, b])
        #expect(all == again)
        #expect(all.rows.map(\.transactionId.rawValue) == ["a", "b"])
        let processed = try Self.snapshot([a, b], selection: [b.transactionId, a.transactionId])
        #expect(processed.rows.map(\.transactionId.rawValue) == ["b", "a"])
        #expect(processed.sourceSetHash == all.sourceSetHash && processed.reference != all.reference)
        #expect(try processed.hasSameSourceRows([b, a]))
        #expect(try !processed.hasSameSourceRows([a]))
        #expect(try !processed.hasSameSourceRows([a, Self.row("b", notes: "Changed after filtering")]))
        #expect(try ProtectedArtifactSHA256.make(bytes: processed.canonicalContentData()) == processed.reference.snapshotHash)
        let noMatches = try Self.snapshot([a, b], selection: [])
        #expect(noMatches.rows.isEmpty && noMatches.sourceSetHash == all.sourceSetHash)
        #expect(try Self.snapshot([]).rows.isEmpty)
    }

    @Test func sourceVisibilityAndVersionChangesInvalidateReference() throws {
        let a = try Self.row("a"), b = try Self.row("b")
        let selected = try Self.snapshot([a, b], selection: [a.transactionId])
        #expect(try Self.snapshot([a, Self.row("b", notes: "Changed unselected row")], selection: [a.transactionId]).reference != selected.reference)
        #expect(try Self.snapshot([a, b], selection: [a.transactionId], version: "source-2").reference != selected.reference)
        #expect(try Self.snapshot([a, b], selection: [a.transactionId], visibility: "restricted").reference != selected.reference)
        var wire = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(b)) as? [String: Any])
        wire["legacySubtotalMinorUnits"] = "9007199254740993"
        wire["legacyTaxRatePct"] = "8.12345678901234567890"
        let changed = try TransactionDetailSnapshotTests.decode(wire)
        #expect(try Self.snapshot([a, changed], selection: [a.transactionId]).reference != selected.reference)
        #expect(try !selected.hasSameSourceRows([a, changed]))
    }

    @Test func rejectsIncompleteScopeAndSelection() throws {
        let row = try Self.row(), reference = try Self.snapshot([row])
        for update in [TransactionBrowserUpdate.partial([row]), .incomplete, .unavailable] {
            #expect(throws: TransactionExportSnapshot.Failure.incomplete) {
                try TransactionExportSnapshot(scope: reference.scope, principalId: reference.principalId, update: update,
                    asOf: reference.asOf, sourceVersion: reference.sourceVersion,
                    visibilityScopeID: reference.reference.visibilityScopeID, authorityVersion: reference.reference.authorityVersion)
            }
        }
        #expect(throws: TransactionExportSnapshot.Failure.wrongScope) { try Self.snapshot([row, row]) }
        #expect(throws: TransactionExportSnapshot.Failure.wrongScope) {
            try Self.snapshot([TransactionDetailSnapshotTests.decode(TransactionDetailSnapshotTests.fixture())])
        }
        for ids in [[row.transactionId, row.transactionId], [try TransactionID(validating: "absent")]] {
            #expect(throws: TransactionExportSnapshot.Failure.invalidSelection) { try Self.snapshot([row], selection: ids) }
        }
        var missing = try TransactionReceiptSnapshotTests.fixture()
        missing["role"] = "standalone"; missing["origin"] = "vendor_payment"
        #expect(throws: TransactionExportSnapshot.Failure.missingReceipt) {
            try Self.snapshot([TransactionDetailSnapshotTests.decode(missing)])
        }
    }
}
