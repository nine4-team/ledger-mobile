import Foundation
import Testing
import LedgerTargetCore
@testable import LedgerTargetMigrationCore

@Suite("Frozen Invoice private storage transport")
struct FrozenInvoiceStorageRecordTests {
    @Test("Actual Postgres frozen contents restore the same typed Invoice",
          .enabled(if: ProcessInfo.processInfo.environment["LEDGER_REPORT_PARITY_INPUT"] != nil
                    || ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
                   "Requires the same-commit database parity artifact"))
    func actualDatabaseRoundTrip() throws {
        let environment = ProcessInfo.processInfo.environment
        let path = try #require(environment["LEDGER_REPORT_PARITY_INPUT"]
            ?? environment["RUNNER_TEMP"].map { "\($0)/ledger-property-report-parity.json" })
        struct DatabaseEvidence: Decodable { let frozenInvoice: FrozenInvoiceStorageRecord }
        let evidence = try JSONDecoder().decode(DatabaseEvidence.self,
            from: Data(contentsOf: URL(fileURLWithPath: path)))
        let actual = try evidence.frozenInvoice.restored()
        let expected = try fixture()
        #expect(actual == expected)
        #expect(actual.lines.map(\.id.rawValue) == ["z-sale", "a-credit", "expense-line", "fee-line"])
        for (actualLine, expectedLine) in zip(actual.lines, expected.lines) {
            #expect(actualLine.description.utf8.elementsEqual(expectedLine.description.utf8))
        }
        #expect(try actual.categoryTotals() == expected.categoryTotals())
    }

    @Test("Mixed signed contents round-trip exact cents, provenance and original line order")
    func exactRoundTrip() throws {
        let original = try fixture()
        let record = try FrozenInvoiceStorageRecord.make(original)
        #expect(record.total_minor_units == "9007199254740978")
        #expect(record.lines[0].signed_amount_minor_units == "9007199254740993")
        #expect(record.lines.map(\.line_position) == [0, 1, 2, 3])
        let decoded = try JSONDecoder().decode(FrozenInvoiceStorageRecord.self, from: JSONEncoder().encode(record))
        let restored = try decoded.restored()
        #expect(restored == original)
        #expect(restored.lines.map(\.id.rawValue) == ["z-sale", "a-credit", "expense-line", "fee-line"])
        #expect(restored.lines[0].description.utf8.elementsEqual(original.lines[0].description.utf8))
        #expect(try restored.categoryTotals() == original.categoryTotals())
    }

    @Test("Database result order is reconstructed only from explicit contiguous positions")
    func resultOrder() throws {
        let original = try fixture()
        var json = try object(original)
        let rows = try #require(json["lines"] as? [[String: Any]])
        json["lines"] = Array(rows.reversed())
        #expect(try decode(json).restored() == original)
        var bad = rows
        bad[1]["line_position"] = 0
        json["lines"] = bad
        #expect(throws: (any Error).self) { try decode(json).restored() }
        bad[1]["line_position"] = 8
        json["lines"] = bad
        #expect(throws: (any Error).self) { try decode(json).restored() }
    }

    @Test("Postgres-style source JSON formatting and explicit null Item links preserve typed facts")
    func normalizedDatabaseJSON() throws {
        let original = try fixture()
        var json = try object(original)
        var rows = try #require(json["lines"] as? [[String: Any]])
        for index in rows.indices {
            let source = try #require(rows[index]["source_snapshot_json"] as? String)
            let parsed = try JSONSerialization.jsonObject(with: Data(source.utf8))
            let formatted = try JSONSerialization.data(withJSONObject: parsed, options: [.prettyPrinted, .sortedKeys])
            rows[index]["source_snapshot_json"] = String(decoding: formatted, as: UTF8.self)
            if rows[index]["item_id"] == nil { rows[index]["item_id"] = NSNull() }
        }
        json["lines"] = rows
        #expect(try decode(json).restored() == original)
        // This exercises the transport representation, not a running database.
        // Actual SQL-to-Swift round-trip evidence is still required.
    }

    @Test("Mismatched indexed source identities and malformed integer totals fail closed")
    func corruptedProjection() throws {
        for key in ["source_id", "source_kind", "item_id"] {
            var json = try object(fixture())
            var rows = try #require(json["lines"] as? [[String: Any]])
            rows[0][key] = "other"
            json["lines"] = rows
            #expect(throws: (any Error).self) { try decode(json).restored() }
        }
        for amount in ["09007199254740978", "9223372036854775808", "1", "1.0"] {
            var json = try object(fixture())
            json["total_minor_units"] = amount
            #expect(throws: (any Error).self) { try decode(json).restored() }
        }
    }

    @Test("Canonically equivalent Unicode cannot substitute a different stored identity")
    func byteExactSourceIdentity() throws {
        let original = try fixture(itemID: "\u{212B}", saleID: "\u{212B}")
        #expect(try FrozenInvoiceStorageRecord.make(original).restored() == original)
        for key in ["source_id", "item_id"] {
            var json = try object(original)
            var rows = try #require(json["lines"] as? [[String: Any]])
            rows[0][key] = "\u{00C5}"
            json["lines"] = rows
            #expect(throws: FrozenInvoiceStorageFailure.malformedRecord) { try decode(json).restored() }
        }
    }

    private func object(_ value: FrozenInvoiceContents) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(FrozenInvoiceStorageRecord.make(value))) as? [String: Any])
    }
    private func decode(_ value: [String: Any]) throws -> FrozenInvoiceStorageRecord {
        try JSONDecoder().decode(FrozenInvoiceStorageRecord.self, from: JSONSerialization.data(withJSONObject: value))
    }
    private func fixture(itemID: String = "frozen-item", saleID: String = "sale") throws -> FrozenInvoiceContents {
        let currency = try CurrencyCode(validating: "USD")
        let scope = TransactionScope.project(accountId: try AccountID(validating: "account-primary"),
            projectId: try ProjectID(validating: "frozen-project"), clientId: try ClientID(validating: "client-existing"))
        func money(_ value: Int64) -> Money { Money(minorUnits: value, currency: currency) }
        func line(_ id: String, _ amount: Int64, _ source: FrozenInvoiceLineSource) throws -> FrozenInvoiceLine {
            try FrozenInvoiceLine(id: InvoiceLineID(validating: id), scope: scope, source: source,
                sourceRevision: 2, categoryId: BudgetCategoryID(validating: "furnishings"),
                signedAmount: money(amount), description: "  e\u{0301}\r\nOriginal description  ")
        }
        let item = try ItemID(validating: itemID)
        return try FrozenInvoiceContents(invoiceId: InvoiceID(validating: "frozen-invoice"), invoiceRevision: 3,
            scope: scope, purchaseId: TransactionID(validating: "frozen-purchase"), lines: [
                line("z-sale", 9_007_199_254_740_993, .item(itemId: item,
                    occurrenceId: BillableItemOccurrenceID(validating: saleID),
                    price: FrozenItemPriceSnapshot(basis: .projectPrice, amount: money(9_007_199_254_740_993)))),
                line("a-credit", -20, .item(itemId: item,
                    occurrenceId: BillableItemOccurrenceID(validating: "return"),
                    price: FrozenItemPriceSnapshot(basis: .paidInvoiceLine(invoiceId: InvoiceID(validating: "prior-invoice"),
                        lineId: InvoiceLineID(validating: "prior-line")), amount: money(20)))),
                line("expense-line", 3, .expense(expenseId: ExpenseID(validating: "expense"))),
                line("fee-line", 2, .feeInstallment(installmentId: FeeInstallmentID(validating: "installment")))
            ], total: money(9_007_199_254_740_978))
    }
}
