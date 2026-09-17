import Testing
@testable import LedgerTargetCore

@Suite("Canonical Invoicing Item rows")
struct ProjectInvoicingItemsTests {
    private func row(_ id: String = "charge", amount: Int64 = 100,
                     polarity: BillableItemOccurrencePolarity = .charge,
                     phase: BillableItemOccurrencePhase = .availableToInvoice,
                     availability: InvoicingAvailability = .available,
                     category: String? = "category") throws -> ProjectInvoicingItem {
        try .init(occurrence: .init(id: .init(validating: id), accountId: .init(validating: "account"),
            projectId: .init(validating: "project"), itemId: .init(validating: "same-chair"),
            polarity: polarity, phase: phase), amount: .init(minorUnits: amount, currency: .init(validating: "USD")),
            availability: availability, title: "Oak Chair", invoiceDescription: "Window seating",
            categoryName: "Furnishings", vendorName: "Original Vendor",
            categoryId: category.map { try .init(validating: $0) })
    }

    @Test func exactSignedAmountsAndMembership() throws {
        #expect(try row(amount: Int64.max).amount.minorUnits == Int64.max)
        #expect(try row(amount: Int64.min, polarity: .credit).amount.minorUnits == Int64.min)
        for value: Int64 in [0, -1] {
            #expect(throws: ProjectInvoicingItemsFailure.invalidAmount) { try row(amount: value) }
        }
        #expect(throws: ProjectInvoicingItemsFailure.invalidAmount) { try row(amount: 1, polarity: .credit) }
        #expect(throws: ProjectInvoicingItemsFailure.invalidMembership) { try row(availability: .paid) }
        let invoice = try InvoiceID(validating: "invoice")
        #expect(try row(phase: .frozenPaid(invoiceId: invoice), availability: .paid).occurrence.phase.invoiceId == invoice)
        #expect(try row(phase: .onLiveInvoice(invoiceId: invoice), availability: .sent).availability == .sent)
    }

    @Test func repeatedPhysicalItemKeepsDistinctCyclesAndScopes() throws {
        let first = try row(), second = try row("resale")
        let snapshot = try ProjectInvoicingItems(accountId: first.occurrence.accountId,
            projectId: first.occurrence.projectId, rows: [first, second])
        #expect(snapshot.rows.count == 2)
        #expect(throws: ProjectInvoicingItemsFailure.duplicateOccurrence) {
            try ProjectInvoicingItems(accountId: snapshot.accountId, projectId: snapshot.projectId, rows: [first, first])
        }
        #expect(throws: ProjectInvoicingItemsFailure.scopeMismatch) {
            try ProjectInvoicingItems(accountId: .init(validating: "other"), projectId: snapshot.projectId, rows: [first])
        }
    }

    @Test func searchAndStatusUseExistingLabelsWithoutChangingAmounts() throws {
        let value = try row()
        for query in ["", "  oak  ", "WINDOW", "furnishings", "original vendor"] { #expect(value.matches(search: query)) }
        #expect(!value.matches(search: "missing"))
        #expect(!value.matches(search: "oak", availability: .paid))
        #expect(value.matches(search: "oak", availability: .available))
        #expect(value.amount.minorUnits == 100)
    }

    @Test func chargeAndCreditWithSameRawIDRemainDistinct() throws {
        let charge = try row("same"), credit = try row("same", amount: -100, polarity: .credit)
        #expect(charge.id != credit.id)
        let value = try ProjectInvoicingItems(accountId: charge.occurrence.accountId,
            projectId: charge.occurrence.projectId, rows: [charge, credit])
        #expect(value.rows.count == 2)
        #expect(throws: ProjectInvoicingItemsFailure.duplicateOccurrence) {
            try ProjectInvoicingItems(accountId: charge.occurrence.accountId,
                projectId: charge.occurrence.projectId, rows: [credit, credit])
        }
    }

    @Test func collectionReturnAndResalePreserveExactItemBudgetContributions() throws {
        let category = try BudgetCategoryDefinitionSnapshot(id: .init(validating: "category"),
            accountId: .init(validating: "account"), name: .init(validating: "Furnishings"), kind: .itemized,
            lifecycle: .active, isSystem: false, excludesFromOverallBudget: false, presentationOrder: 0, revision: 1)
        let currency = try CurrencyCode(validating: "USD")
        func total(_ rows: [ProjectInvoicingItem]) throws -> ProjectBudgetCategorySegment {
            let snapshot = try ProjectInvoicingItems(accountId: category.accountId,
                projectId: .init(validating: "project"), rows: rows)
            return try #require(snapshot.budgetContributions(categories: [category], currency: currency).first)
        }
        let open = try row(), paid = try row(phase: .frozenPaid(invoiceId: .init(validating: "invoice")), availability: .paid)
        let credit = try row(amount: -100, polarity: .credit), resale = try row("resale", amount: 125)
        #expect(try total([open]).clientPaid.minorUnits == 0)
        #expect(try total([open]).invoicingUnpaid.minorUnits == 100)
        #expect(try total([paid]).recognized == total([open]).recognized)
        let returned = try total([paid, credit])
        #expect(returned.clientPaid.minorUnits == 100 && returned.invoicingUnpaid.minorUnits == -100)
        #expect(returned.recognized.minorUnits == 0)
        #expect(try total([paid, credit, resale]).recognized.minorUnits == 125)
        #expect(throws: ProjectInvoicingItemsFailure.missingBudgetCategory) { try total([row(category: nil)]) }
        #expect(throws: ProjectInvoicingItemsFailure.missingBudgetCategory) { try total([row(category: "missing")]) }
        #expect(throws: (any Error).self) { try total([row(amount: Int64.max), row("overflow", amount: 1)]) }
    }
}
