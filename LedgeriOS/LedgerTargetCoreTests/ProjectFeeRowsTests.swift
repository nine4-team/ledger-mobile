import Testing
@testable import LedgerTargetCore

@Suite("Fee presentation preserves canonical membership")
struct ProjectFeeRowsTests {
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
