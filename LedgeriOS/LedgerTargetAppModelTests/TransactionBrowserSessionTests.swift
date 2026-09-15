import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetAppModel

@MainActor @Suite("Transaction browser behavior")
struct TransactionBrowserSessionTests {
    static func row(_ id: String, _ overrides: [String: Any] = [:]) throws -> TransactionDetailSnapshot {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        var wire = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
            root.appendingPathComponent("LedgerTargetMCP/tests/fixtures/transaction-detail.json"))) as? [String: Any])
        wire["transactionId"] = id
        for (key, value) in overrides { wire[key] = value }
        return try JSONDecoder().decode(TransactionDetailSnapshot.self, from: JSONSerialization.data(withJSONObject: wire))
    }
    static func session(_ rows: [TransactionDetailSnapshot]) throws -> TransactionBrowserSession {
        let scope = try #require(rows.first).classification.scope
        let model = TransactionBrowserSession(scope: scope, watch: { AsyncThrowingStream { $0.finish() } })
        try model.receive(.partial(rows))
        return model
    }

    @Test func allEightSortsUseStableIdentityAndUnknownLast() throws {
        let a = try Self.row("a", ["source": "A", "transactionDate": "2024-01-01", "createdAtMilliseconds": "1", "amountMinorUnits": "100"])
        let b = try Self.row("b", ["source": "Z", "transactionDate": "2024-02-01", "createdAtMilliseconds": "2", "amountMinorUnits": "200"])
        let c = try Self.row("c", ["source": NSNull(), "transactionDate": NSNull(), "createdAtMilliseconds": NSNull(), "amountMinorUnits": "300"])
        let session = try Self.session([b, c, a])
        for sort in TransactionBrowserSession.Sort.allCases {
            session.sort = sort
            let expected: [String]
            switch sort {
            case .dateAsc, .createdAsc, .sourceAsc, .amountAsc: expected = ["a", "b", "c"]
            case .dateDesc, .createdDesc, .sourceDesc: expected = ["b", "a", "c"]
            case .amountDesc: expected = ["c", "b", "a"]
            }
            #expect(session.processed.map(\.transactionId.rawValue) == expected)
        }
        let fallback = try Self.row("fallback", ["transactionDate": NSNull(), "createdAtMilliseconds": "1709251200123"])
        try session.receive(.partial([a, fallback]))
        session.sort = .dateDesc
        #expect(session.processed.first?.transactionId.rawValue == "fallback")
        #expect(fallback.transactionDate == nil) // Sort fallback must not invent a displayed Transaction date.
    }

    @Test func groupedFiltersAreOrWithinAndAcrossWithUnknownReceiptDistinct() throws {
        let yes = try Self.row("yes", ["hasEmailReceipt": true, "source": "A"])
        let no = try Self.row("no", ["hasEmailReceipt": false, "source": "B"])
        let unknown = try Self.row("unknown", ["hasEmailReceipt": NSNull(), "source": "A"])
        let session = try Self.session([yes, no, unknown])
        session.toggleFilter(.emailReceipt, value: "yes")
        session.toggleFilter(.emailReceipt, value: "no")
        #expect(Set(session.processed.map(\.transactionId.rawValue)) == ["yes", "no"])
        session.toggleFilter(.source, value: "A")
        #expect(session.processed.map(\.transactionId.rawValue) == ["yes"])
        session.toggleFilter(.emailReceipt, value: nil)
        #expect(Set(session.processed.map(\.transactionId.rawValue)) == ["yes", "unknown"])
        session.resetFilters()
        session.search = "unknown"
        #expect(session.processed.map(\.transactionId.rawValue) == ["unknown"])
        session.search = "NO MATCH"
        #expect(session.processed.isEmpty && session.rows.count == 3 && session.state == .partial)
    }

    @Test func detailNavigationRestoresOnlyCurrentlyVisibleSelection() throws {
        let retained = try Self.row("retained"), removed = try Self.row("removed")
        let session = try Self.session([retained, removed])
        session.toggleSelection(retained.transactionId)
        session.toggleSelection(removed.transactionId)
        session.suspendForDetailNavigation()
        #expect(session.rows.isEmpty && session.selectedIds.isEmpty)
        try session.receive(.ready([retained]))
        #expect(session.selectedIds == [retained.transactionId])
        session.suspendForDetailNavigation()
        session.invalidate()
        try session.receive(.ready([retained]))
        #expect(session.selectedIds.isEmpty)
    }

    @Test func selectionAndExactSignedTotalFollowProcessedRows() throws {
        let buy = try Self.row("buy", ["type": "purchase", "amountMinorUnits": "100"])
        let refund = try Self.row("refund", ["amountMinorUnits": "200"])
        let session = try Self.session([buy, refund])
        session.selectAllVisible()
        #expect(session.selectedIds.isEmpty) // Inventory must not gain Project-only select-all.
        session.toggleSelection(buy.transactionId); session.toggleSelection(refund.transactionId)
        #expect(try session.selectedTotal()?.minorUnits == -100)
        session.search = "refund"
        #expect(session.selectedIDText == "refund")
        #expect(try session.selectedTotal()?.minorUnits == -200)
        session.clearSelection()
        #expect(try session.selectedTotal() == nil)
        let project = try Self.row("project", ["scopeKind": "project", "projectId": "p", "clientId": "c"])
        let projectSession = try Self.session([project])
        projectSession.selectAllVisible()
        #expect(projectSession.selectedIDText == "project")
        projectSession.selectAllVisible()
        #expect(projectSession.selectedIds.isEmpty)
    }

    @Test func receiptAuditFiltersUseExactSharedEvidenceAndPruneSelection() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
            root.appendingPathComponent("LedgerTargetMCP/tests/fixtures/transaction-receipt.json"))) as? [String: Any])
        func row(_ id: String, amount: String = "3050", missing: Bool = false, kind: String = "itemized", downloaded: Bool = true) throws -> TransactionDetailSnapshot {
            var receipt = fixture; receipt["transactionId"] = id; receipt["amountMinorUnits"] = amount
            var category = receipt["category"] as! [String: Any]; category["kind"] = kind; receipt["category"] = category
            if missing {
                var items = receipt["items"] as! [[String: Any]]; items[1]["amountMinorUnits"] = NSNull(); receipt["items"] = items
            }
            var fields = receipt; fields["receipt"] = downloaded ? receipt : NSNull()
            return try Self.row(id, fields)
        }
        let balanced = try row("balanced"), mismatch = try row("mismatch", amount: "3051"),
            missing = try row("missing", missing: true), general = try row("general", kind: "general"),
            unknown = try row("unknown", downloaded: false)
        let model = try Self.session([balanced, mismatch, missing, general, unknown])
        for (value, id) in [("balanced", "balanced"), ("mismatch", "mismatch"), ("incompleteEvidence", "missing"),
            ("notApplicable", "general"), ("unknown", "unknown")] {
            model.resetFilters(); model.toggleFilter(.audit, value: value)
            #expect(model.processed.map(\.transactionId.rawValue) == [id])
        }
        model.toggleFilter(.audit, value: "incompleteEvidence")
        #expect(Set(model.processed.map(\.transactionId.rawValue)) == ["unknown", "missing"])
        model.resetFilters(); model.toggleFilter(.audit, value: "balanced"); model.selectAllVisible()
        #expect(model.selectedIDText == "balanced")
        try model.receive(.partial([row("balanced", kind: "general")]))
        #expect(model.processed.isEmpty && model.selectedIds.isEmpty)
    }

    @Test func failedIncompleteAndWithdrawnReadsRemoveVisibleAndSelectedData() throws {
        let row = try Self.row("a")
        let session = try Self.session([row])
        session.toggleSelection(row.transactionId)
        try session.receive(.incomplete)
        #expect(session.rows.isEmpty && session.selectedIds.isEmpty && session.state == .incomplete)
        try session.receive(.partial([row]))
        try session.receive(.unavailable)
        #expect(session.rows.isEmpty && session.state == .unavailable)
        #expect(throws: TransactionDetailSnapshot.Failure.scopeMismatch) {
            try session.receive(.partial([Self.row("foreign", ["accountId": "other"])]))
        }
        #expect(session.rows.isEmpty && session.state == .failed)
        #expect(throws: TransactionDetailSnapshot.Failure.scopeMismatch) { try session.receive(.partial([row, row])) }
        try session.receive(.partial([]))
        #expect(session.state == .partial) // Empty vendor subset is not a complete empty Transaction list.
    }

    @Test func streamTerminationDoesNotLeaveStaleFinancialContent() async throws {
        let row = try Self.row("a")
        let session = TransactionBrowserSession(scope: row.classification.scope, watch: {
            AsyncThrowingStream { $0.yield(.partial([row])); $0.finish() }
        })
        await session.observe()
        #expect(session.rows.isEmpty && session.state == .unavailable)
    }
}
