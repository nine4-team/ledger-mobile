import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Frozen Invoice contents")
struct FrozenInvoiceContentsTests {
    private static func scope(_ project: String = "project", account: String = "account", client: String = "client") throws -> TransactionScope {
        .project(accountId: try AccountID(validating: account), projectId: try ProjectID(validating: project),
                 clientId: try ClientID(validating: client))
    }
    private static func money(_ cents: Int64, currency: String = "USD") throws -> Money {
        .init(minorUnits: cents, currency: try CurrencyCode(validating: currency))
    }
    private static func line(_ id: String, cents: Int64, category: String = "furniture",
                             source: FrozenInvoiceLineSource? = nil, scope: TransactionScope? = nil,
                             currency: String = "USD", revision: Int64 = 1) throws -> FrozenInvoiceLine {
        try .init(id: InvoiceLineID(validating: id), scope: scope ?? Self.scope(),
            source: source ?? .item(itemId: ItemID(validating: "physical-item"), occurrenceId: BillableItemOccurrenceID(validating: id),
                price: FrozenItemPriceSnapshot(basis: .projectPrice, amount: money(cents < 0 ? -cents : cents, currency: currency))),
            sourceRevision: revision, categoryId: BudgetCategoryID(validating: category),
            signedAmount: money(cents, currency: currency), description: "Original description")
    }
    private static func snapshot(_ lines: [FrozenInvoiceLine], total: Int64, scope: TransactionScope? = nil,
                                 invoiceId: String = "invoice") throws -> FrozenInvoiceContents {
        try .init(invoiceId: InvoiceID(validating: invoiceId), invoiceRevision: 2,
            scope: scope ?? Self.scope(), purchaseId: TransactionID(validating: "purchase-" + invoiceId), lines: lines, total: money(total))
    }

    @Test("Mixed Item, Expense, Fee and credit lines retain exact category allocation")
    func mixedContents() throws {
        let credit: FrozenInvoiceLineSource = try .item(itemId: ItemID(validating: "returned-item"),
            occurrenceId: BillableItemOccurrenceID(validating: "return-cycle"),
            price: FrozenItemPriceSnapshot(basis: .paidInvoiceLine(invoiceId: InvoiceID(validating: "prior-invoice"),
                lineId: InvoiceLineID(validating: "prior-line")), amount: Self.money(20)))
        let lines = try [Self.line("sale", cents: 100), Self.line("credit", cents: -20, source: credit),
            Self.line("expense", cents: 30, category: "shipping", source: .expense(expenseId: ExpenseID(validating: "expense"))),
            Self.line("fee", cents: 10, category: "fees", source: .feeInstallment(installmentId: FeeInstallmentID(validating: "installment")))]
        let snapshot = try Self.snapshot(lines, total: 120)
        #expect(snapshot.lines == lines)
        #expect(try snapshot.categoryTotals() == [BudgetCategoryID(validating: "furniture"): Self.money(80),
            BudgetCategoryID(validating: "shipping"): Self.money(30), BudgetCategoryID(validating: "fees"): Self.money(10)])
        #expect(try JSONDecoder().decode(FrozenInvoiceContents.self, from: JSONEncoder().encode(snapshot)) == snapshot)
    }

    @Test("One physical Item can have distinct billed cycles without rewriting earlier history")
    func resaleHistory() throws {
        let original = try Self.snapshot([Self.line("first-sale", cents: 100)], total: 100)
        let bytes = try JSONEncoder().encode(original)
        let laterScope = try Self.scope("later-project")
        let resale = try Self.snapshot([Self.line("resale", cents: 200, category: "new-category", scope: laterScope)],
            total: 200, scope: laterScope, invoiceId: "resale-invoice")
        let restored = try JSONDecoder().decode(FrozenInvoiceContents.self, from: bytes)
        #expect(restored == original)
        #expect(restored.scope != resale.scope)
        #expect(restored.lines[0].signedAmount.minorUnits == 100)
        #expect(restored.lines[0].categoryId.rawValue == "furniture")
        #expect(restored.lines[0].source != resale.lines[0].source)
    }

    @Test("Duplicate line identity and reuse of one Item occurrence reject")
    func duplicates() throws {
        let line = try Self.line("sale", cents: 100)
        #expect(throws: FrozenInvoiceContentsFailure.duplicateLine) { try Self.snapshot([line, line], total: 200) }
        let other = try Self.line("second-line", cents: 100, source: line.source)
        #expect(throws: FrozenInvoiceContentsFailure.duplicateItemOccurrence) { try Self.snapshot([line, other], total: 200) }
        let expense = FrozenInvoiceLineSource.expense(expenseId: try ExpenseID(validating: "expense"))
        #expect(throws: FrozenInvoiceContentsFailure.duplicateExpense) {
            try Self.snapshot([Self.line("a", cents: 100, source: expense), Self.line("b", cents: 100, source: expense)], total: 200)
        }
        let fee = FrozenInvoiceLineSource.feeInstallment(installmentId: try FeeInstallmentID(validating: "fee"))
        #expect(throws: FrozenInvoiceContentsFailure.duplicateFeeInstallment) {
            try Self.snapshot([Self.line("a", cents: 100, source: fee), Self.line("b", cents: 100, source: fee)], total: 200)
        }
    }

    @Test("Item price provenance is mandatory, exact and retained across decoding")
    func priceProvenance() throws {
        let bases: [FrozenItemPriceBasis] = try [.projectPrice,
            .purchaseCost(acquisitionId: TransactionID(validating: "acquisition")),
            .paidInvoiceLine(invoiceId: InvoiceID(validating: "prior-invoice"), lineId: InvoiceLineID(validating: "prior-line")),
            .inventoryEntry(entryId: InventoryEntryID(validating: "entry"))]
        for basis in bases {
            let source = try FrozenInvoiceLineSource.item(itemId: ItemID(validating: "item"),
                occurrenceId: BillableItemOccurrenceID(validating: "cycle"),
                price: FrozenItemPriceSnapshot(basis: basis, amount: Self.money(100)))
            let line = try Self.line("line", cents: -100, source: source)
            #expect(try JSONDecoder().decode(FrozenInvoiceLine.self, from: JSONEncoder().encode(line)) == line)
            #expect(throws: FrozenInvoiceContentsFailure.invalidPriceSnapshot) { try Self.line("line", cents: 99, source: source) }
            #expect(throws: FrozenInvoiceContentsFailure.invalidPriceSnapshot) { try Self.line("line", cents: 100, source: source, currency: "EUR") }
        }
        #expect(throws: FrozenInvoiceContentsFailure.invalidPriceSnapshot) {
            try FrozenItemPriceSnapshot(basis: .projectPrice, amount: Self.money(-1))
        }
        let line = try Self.line("line", cents: 100)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(line)) as? [String: Any])
        var source = try #require(json["source"] as? [String: Any])
        var item = try #require(source["item"] as? [String: Any])
        item.removeValue(forKey: "price"); source["item"] = item; json["source"] = source
        let missingPrice = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(FrozenInvoiceLine.self, from: missingPrice) }
    }

    @Test("Account, Project and Client mismatches cannot enter one snapshot")
    func scopes() throws {
        for scope in try [Self.scope("other"), Self.scope(account: "other"), Self.scope(client: "other")] {
            let line = try Self.line("sale", cents: 100, scope: scope)
            #expect(throws: FrozenInvoiceContentsFailure.scopeMismatch) { try Self.snapshot([line], total: 100) }
        }
        let inventory = TransactionScope.businessInventory(accountId: try AccountID(validating: "account"))
        #expect(throws: FrozenInvoiceContentsFailure.requiresProjectScope) { try Self.line("sale", cents: 100, scope: inventory) }
    }

    @Test("Exact totals, currency and revision validation apply to decoded values too")
    func validationAndDecode() throws {
        let line = try Self.line("sale", cents: 100)
        #expect(throws: FrozenInvoiceContentsFailure.totalMismatch) { try Self.snapshot([line], total: 99) }
        #expect(throws: FrozenInvoiceContentsFailure.emptyContents) { try Self.snapshot([], total: 100) }
        #expect(throws: FrozenInvoiceContentsFailure.requiresPositiveTotal) { try Self.snapshot([Self.line("zero", cents: 0)], total: 0) }
        #expect(throws: FrozenInvoiceContentsFailure.invalidRevision) { try Self.line("sale", cents: 100, revision: 0) }
        #expect(throws: DomainPrimitiveFailure.currencyMismatch) { try Self.snapshot([Self.line("sale", cents: 100, currency: "EUR")], total: 100) }
        let snapshot = try Self.snapshot([line], total: 100)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        json["invoiceRevision"] = -1
        let invalidRevision = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: FrozenInvoiceContentsFailure.invalidRevision) { try JSONDecoder().decode(FrozenInvoiceContents.self, from: invalidRevision) }
        json["invoiceRevision"] = 2
        json["lines"] = []
        let empty = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: FrozenInvoiceContentsFailure.emptyContents) { try JSONDecoder().decode(FrozenInvoiceContents.self, from: empty) }
    }

    @Test("Large exact integers round trip; total and per-category overflow reject")
    func integerBoundaries() throws {
        let exact: Int64 = 9_007_199_254_740_993
        let snapshot = try Self.snapshot([Self.line("large", cents: exact)], total: exact)
        #expect(try JSONDecoder().decode(FrozenInvoiceContents.self, from: JSONEncoder().encode(snapshot)).total.minorUnits == exact)
        #expect(throws: DomainPrimitiveFailure.arithmeticOverflow(.addition)) {
            try Self.snapshot([Self.line("max", cents: .max), Self.line("one", cents: 1)], total: .max)
        }
        // Overall sum fits, but category A cannot be represented in Int64.
        #expect(throws: DomainPrimitiveFailure.arithmeticOverflow(.addition)) {
            try Self.snapshot([Self.line("max", cents: .max), Self.line("offset", cents: -1, category: "other"),
                Self.line("one", cents: 1)], total: .max)
        }
    }
}
