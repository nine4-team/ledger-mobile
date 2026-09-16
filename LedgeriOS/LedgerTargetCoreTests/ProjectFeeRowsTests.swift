import Testing
@testable import LedgerTargetCore

@Suite("Fee presentation preserves canonical membership")
struct ProjectFeeRowsTests {
    @Test func categorySummaryKeepsAllSourcesAndExactMoney() throws {
        let category = try BudgetCategoryID(validating: "design"), currency = try CurrencyCode(validating: "USD")
        func row(_ id: String, _ amount: Int64, _ state: InvoicingAvailability) throws -> ProjectFeeRow {
            try .init(id: .init(validating: id), title: id, amount: .init(minorUnits: amount, currency: currency),
                categoryId: category, categoryName: "Design", availability: state, invoiceId: nil, invoiceName: nil)
        }
        let rows = try [row("available", 100, .available), row("sent", 200, .sent), row("paid", 300, .paid)]
        let group = try ProjectFeeGroup(category: .init(id: category, name: "Design", configuredTotal: nil), rows: rows, currency: currency)
        #expect(group.total.minorUnits == 600)
        #expect(group.invoiced.minorUnits == 500 && group.received.minorUnits == 300)
        #expect(group.remainingToInvoice.minorUnits == 100)
        let ordered = try ProjectFeeGroup(category: .init(id: category, name: "Design", configuredTotal: nil),
            rows: rows, currency: currency, sortOrders: [rows[1].id: -1, rows[0].id: 1])
        #expect(ordered.rows.map(\.id.rawValue) == ["sent", "paid", "available"])
        #expect(group.rows.map(\.id.rawValue) == ["available", "paid", "sent"])
        #expect(ordered.rows.filter { $0.matches(search: "paid", availability: .paid) }.count == 1)
        #expect(ordered.total == group.total && ordered.received == group.received)
        let zero = try ProjectFeeGroup(category: .init(id: category, name: "Design", configuredTotal: .zero(currency: currency)), rows: rows, currency: currency)
        #expect(zero.total.minorUnits == 0 && zero.invoiced.minorUnits == 500 && zero.remainingToInvoice.minorUnits == 0)
        #expect(throws: (any Error).self) {
            try ProjectFeeGroup(category: .init(id: category, name: "Design", configuredTotal: nil),
                rows: [row("max", .max, .available), row("extra", 1, .paid)], currency: currency)
        }
        #expect(throws: (any Error).self) {
            try ProjectFeeGroup(category: .init(id: category, name: "Design", configuredTotal: nil), rows: rows + rows, currency: currency)
        }
    }
    @Test func frozenPaidFactsWinOverStaleLiveAndAvailableSnapshots() throws {
        let scope = try TransactionScope.project(accountId: .init(validating: "account"), projectId: .init(validating: "project"), clientId: .init(validating: "client"))
        let id = try FeeInstallmentID(validating: "fee"), category = try BudgetCategoryID(validating: "category")
        let amount = try Money(minorUnits: 100, currency: .init(validating: "USD"))
        let changed = try Money(minorUnits: 200, currency: amount.currency)
        let line = try LiveInvoiceContents.Line(selection: .init(source: .feeInstallment(id), expectedRevision: 2,
            reviewedAmount: changed), categoryId: category, description: "Changed label")
        let review = InvoiceCreationReview(scope: scope, candidates: [line], categoryNames: [category:"Renamed category"])
        let live = try LiveInvoiceContents(invoiceId: .init(validating: "invoice"), revision: 1, status: .sent,
            name: "Phase 1", notes: "", scope: scope, lines: [line], reportedTotal: changed)
        let frozen = try FrozenInvoiceContents(invoiceId: live.invoiceId, invoiceRevision: 1, scope: scope,
            purchaseId: .init(validating: "purchase"), lines: [.init(id: .init(validating: "line"), scope: scope,
                source: .feeInstallment(installmentId: id), sourceRevision: 1, categoryId: category,
                signedAmount: amount, description: "Original label")], total: amount)
        let available = try ProjectFeeRow.compose(review: review, live: [], paid: [])
        #expect(available.count == 1 && available[0].availability == .available)
        let sent = try ProjectFeeRow.compose(review: review, live: [live], paid: [])
        #expect(sent.count == 1 && sent[0].availability == .sent && sent[0].amount == changed)
        #expect(sent[0].matches(search: "Phase", availability: .sent))
        #expect(!sent[0].matches(search: "Phase", availability: .available))
        let paid = try ProjectFeeRow.compose(review: review, live: [live], paid: [frozen])
        #expect(paid.count == 1 && paid[0].availability == .paid && paid[0].amount == amount)
        #expect(paid[0].title == "Original label" && paid[0].categoryName == nil)
        #expect(throws: ProjectFeeRow.Failure.conflictingMembership) {
            try ProjectFeeRow.compose(review: review, live: [live, live], paid: [])
        }
        let foreign = try TransactionScope.project(accountId: .init(validating: "other"), projectId: .init(validating: "project"), clientId: .init(validating: "client"))
        #expect(throws: ProjectFeeRow.Failure.scopeMismatch) {
            try ProjectFeeRow.compose(review: .init(scope: foreign, candidates: []), live: [live], paid: [])
        }
    }
}
