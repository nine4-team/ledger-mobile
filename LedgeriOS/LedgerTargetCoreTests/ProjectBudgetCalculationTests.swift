import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Project budget source composition")
struct ProjectBudgetCalculationTests {
    let scope = try! TransactionScope.project(accountId: .init(validating: "account"), projectId: .init(validating: "project"), clientId: .init(validating: "client"))
    let currency = try! CurrencyCode(validating: "USD")
    let category = try! BudgetCategoryDefinitionSnapshot(id: .init(validating: "category"), accountId: .init(validating: "account"),
        name: .init(validating: "Budget category"), kind: .itemized, lifecycle: .active, isSystem: false,
        excludesFromOverallBudget: false, presentationOrder: 0, revision: 1)
    func money(_ amount: Int64) -> Money { .init(minorUnits: amount, currency: currency) }
    func line(_ source: LiveInvoiceSource, _ amount: Int64) throws -> LiveInvoiceContents.Line {
        try .init(selection: .init(source: source, expectedRevision: 1, reviewedAmount: money(amount)),
            categoryId: category.id, description: "Source")
    }
    func payment(_ id: String, amount: Int64, collected: Bool = false, refund: Bool = false) throws -> TransactionDetailSnapshot {
        var value: [String: Any] = ["accountId":"account", "principalId":"principal", "transactionId":id,
            "scopeKind":"project", "projectId":"project", "clientId":"client", "role":"standalone",
            "type":refund ? "return" : "purchase", "origin":collected ? TransactionDetailSnapshot.Origin.importedClientPayment.rawValue : TransactionDetailSnapshot.Origin.vendorPayment.rawValue,
            "amountMinorUnits":String(amount), "currency":"USD"]
        if !collected { value["category"] = ["id":"category", "name":"Category", "kind":"itemized", "revision":"1"] }
        return try JSONDecoder().decode(TransactionDetailSnapshot.self, from: JSONSerialization.data(withJSONObject: value))
    }
    func item(_ id: String = "item-charge", amount: Int64 = 100, paid: Bool = false, credit: Bool = false) throws -> ProjectInvoicingItem {
        try .init(occurrence: .init(id: .init(validating: id), accountId: scope.accountId,
            projectId: scope.projectId!, itemId: .init(validating: "chair"), polarity: credit ? .credit : .charge,
            phase: paid ? .frozenPaid(invoiceId: .init(validating: "invoice")) : .availableToInvoice),
            amount: money(amount), availability: paid ? .paid : .available, title: "Chair", categoryId: category.id)
    }
    func invoice() throws -> FrozenInvoiceContents {
        try .init(invoiceId: .init(validating: "invoice"), invoiceRevision: 1, scope: scope,
            purchaseId: .init(validating: "payment"), lines: [
                .init(id: .init(validating: "item-line"), scope: scope,
                    source: .item(itemId: .init(validating: "chair"), occurrenceId: .init(validating: "item-charge"),
                        price: .init(basis: .importedInvoiceAmount, amount: money(100))),
                    sourceRevision: 1, categoryId: category.id, signedAmount: money(100), description: "Chair"),
                .init(id: .init(validating: "expense-line"), scope: scope, source: .expense(expenseId: .init(validating: "expense")),
                    sourceRevision: 1, categoryId: category.id, signedAmount: money(50), description: "Expense"),
                .init(id: .init(validating: "fee-line"), scope: scope, source: .feeInstallment(installmentId: .init(validating: "fee")),
                    sourceRevision: 1, categoryId: category.id, signedAmount: money(25), description: "Fee")], total: money(175))
    }
    func calculate(_ candidates: [LiveInvoiceContents.Line] = [], paid: [FrozenInvoiceContents] = [],
                   live: [LiveInvoiceContents] = [], items: [ProjectInvoicingItem] = [],
                   payments: [TransactionDetailSnapshot] = []) throws -> ProjectBudgetCategorySegment {
        try #require(ProjectBudgetCalculation.calculate(categories: [category], currency: currency,
            review: .init(scope: scope, candidates: candidates), live: live, paid: paid,
            itemRows: .init(accountId: scope.accountId, projectId: scope.projectId!, rows: items),
            transactions: payments).first)
    }
    @Test func mixedSourcesCollectionReturnAndResale() throws {
        let sources = try [line(.itemOccurrence(.init(validating: "item-charge")), 100),
            line(.expense(.init(validating: "expense")), 50), line(.feeInstallment(.init(validating: "fee")), 25)]
        let direct = try [payment("direct", amount: 20), payment("refund", amount: 5, refund: true)]
        let before = try calculate(sources, items: [item()], payments: direct)
        #expect(before.clientPaid.minorUnits == 15 && before.invoicingUnpaid.minorUnits == 175)
        let live = try LiveInvoiceContents(invoiceId: .init(validating: "invoice"), revision: 1, status: .sent,
            name: "Invoice", notes: "", scope: scope, lines: sources, reportedTotal: money(175))
        #expect(try calculate(live: [live], items: [item()], payments: direct).recognized == before.recognized)
        let payments = try direct + [payment("payment", amount: 175, collected: true)]
        let collected = try calculate(paid: [invoice()], live: [live], items: [item(paid: true)], payments: payments)
        #expect(collected.recognized == before.recognized && collected.clientPaid.minorUnits == 190)
        #expect(collected.invoicingUnpaid.minorUnits == 0)
        let returned = try calculate(paid: [invoice()], items: [item(paid: true), item("credit", amount: -100, credit: true)], payments: payments)
        #expect(returned.clientPaid.minorUnits == 190 && returned.invoicingUnpaid.minorUnits == -100)
        #expect(returned.recognized.minorUnits == 90)
        let resale = try calculate([line(.itemOccurrence(.init(validating: "resale")), 125)], paid: [invoice()],
            items: [item(paid: true), item("credit", amount: -100, credit: true), item("resale", amount: 125)], payments: payments)
        #expect(resale.recognized.minorUnits == 215)
    }
    @Test func missingOrDuplicateEvidenceCannotProduceACompleteTotal() throws {
        let expense = try line(.expense(.init(validating: "expense")), 50)
        #expect(throws: ProjectBudgetCalculation.Failure.duplicateSource) { try calculate([expense, expense]) }
        #expect(throws: ProjectBudgetCalculation.Failure.duplicateSource) { try calculate(paid: [invoice(), invoice()]) }
        #expect(throws: ProjectBudgetCalculation.Failure.missingEvidence) { try calculate(items: [item(paid: true)]) }
        #expect(throws: ProjectBudgetCalculation.Failure.missingEvidence) { try calculate(payments: [payment("missing", amount: 175, collected: true)]) }
        #expect(throws: ProjectBudgetCalculation.Failure.missingEvidence) { try calculate(paid: [invoice()], payments: [payment("payment", amount: 176, collected: true)]) }
    }

    @Test func currencyAndOverflowDoNotProduceTotals() throws {
        let foreign = try LiveInvoiceContents.Line(selection: .init(source: .expense(.init(validating: "expense")),
            expectedRevision: 1, reviewedAmount: .init(minorUnits: 1, currency: .init(validating: "EUR"))),
            categoryId: category.id, description: "Other currency")
        #expect(throws: ProjectBudgetSegmentFailure.currencyMismatch) { try calculate([foreign]) }
        #expect(throws: DomainPrimitiveFailure.arithmeticOverflow(.addition)) {
            try calculate(payments: [payment("one", amount: Int64.max), payment("two", amount: 1)])
        }
        #expect(throws: ProjectBudgetSegmentFailure.arithmeticOverflow) {
            try calculate([line(.expense(.init(validating: "expense")), 1)], payments: [payment("one", amount: Int64.max)])
        }
    }

    @Test func budgetReadCannotMislabelDuplicateOrUnexplainedAllocations() throws {
        let segment = try calculate()
        let allocation = try NullableCategoryAllocation(categoryId: category.id, allocation: nil)
        let read = try ProjectBudgetRead(scope: scope, currency: currency,
            segments: [segment], allocations: [allocation], localOperations: [])
        #expect(!read.isCompleteForProjectBudget)
        #expect(read.allocations[0].allocation == nil)
        #expect(throws: ProjectBudgetCalculation.Failure.duplicateSource) {
            try ProjectBudgetRead(scope: scope, currency: currency,
                segments: [segment, segment], allocations: [], localOperations: [])
        }
        #expect(throws: ProjectBudgetCalculation.Failure.duplicateSource) {
            try ProjectBudgetRead(scope: scope, currency: currency,
                segments: [segment], allocations: [allocation, allocation], localOperations: [])
        }
        #expect(throws: ProjectBudgetCalculation.Failure.missingEvidence) {
            try ProjectBudgetRead(scope: scope, currency: currency,
                segments: [], allocations: [allocation], localOperations: [])
        }
    }

    @Test func overallExcludesNonAdditiveCategoriesAndCountsEnabledAllocations() throws {
        let excluded = try BudgetCategoryDefinitionSnapshot(id: .init(validating: "overlay"), accountId: scope.accountId,
            name: .init(validating: "Excluded category"), kind: .general, lifecycle: .active, isSystem: false,
            excludesFromOverallBudget: true, presentationOrder: 1, revision: 1)
        let read = try ProjectBudgetRead(scope: scope, currency: currency, segments: [
            .init(category: category, clientPaid: money(100), invoicingUnpaid: money(50)),
            .init(category: excluded, clientPaid: money(900), invoicingUnpaid: money(80))], allocations: [
                .init(categoryId: category.id, allocation: money(500)),
                .init(categoryId: excluded.id, allocation: money(999))], localOperations: [])
        #expect(read.overallPaid == money(100) && read.overallUnpaid == money(50))
        #expect(read.overallRecognized == money(150) && read.overallBudget == money(500))
    }

    @Test func mixedTransferConservesClientValueAndDoesNotDuplicateOpenCharge() throws {
        let destination = try TransactionScope.project(accountId: scope.accountId,
            projectId: .init(validating: "destination"), clientId: scope.clientId!)
        let third = try TransactionScope.project(accountId: scope.accountId,
            projectId: .init(validating: "third"), clientId: scope.clientId!)
        let paidLine = try invoice().lines[0]
        let open = try line(.itemOccurrence(.init(validating: "open-charge")), 40)
        func transfer(_ id: String, from: TransactionScope, to: TransactionScope,
                      items: [ProjectBudgetTransfer.Item]) throws -> ProjectBudgetTransfer {
            try .init(pair: .init(operationId: .init(validating: id),
                route: .init(source: from, destination: to, destinationLifecycle: .active),
                sourceTransactionId: .init(validating: "\(id)-source"),
                destinationTransactionId: .init(validating: "\(id)-destination")), items: items)
        }
        let paidItem = ProjectBudgetTransfer.Item(itemId: try .init(validating: "chair"), basis: .paidLine(paidLine))
        let move = try transfer("move", from: scope, to: destination, items: [paidItem,
            .init(itemId: .init(validating: "other-chair"), basis: .openCharge(open))])
        func budget(_ target: TransactionScope, paid: [FrozenInvoiceContents] = [],
                    candidates: [LiveInvoiceContents.Line] = [], transfers: [ProjectBudgetTransfer]) throws -> ProjectBudgetCategorySegment {
            try #require(ProjectBudgetCalculation.calculate(categories: [category], currency: currency,
                review: .init(scope: target, candidates: candidates), live: [], paid: paid,
                itemRows: .init(accountId: target.accountId, projectId: target.projectId!, rows: []),
                transactions: [], transfers: transfers).first)
        }
        let source = try budget(scope, paid: [invoice()], transfers: [move])
        let received = try budget(destination, candidates: [open], transfers: [move])
        #expect(source.clientPaid.minorUnits == 75 && source.invoicingUnpaid.minorUnits == 0)
        #expect(received.clientPaid.minorUnits == 100 && received.invoicingUnpaid.minorUnits == 40)
        #expect(try source.recognized.adding(received.recognized) == money(215))

        // Re-transfer preserves the original paid line, not the previous
        // Transfer's amount as another purchase. Intermediate attribution is zero.
        let next = try transfer("next", from: destination, to: third, items: [paidItem])
        let intermediate = try budget(destination, candidates: [open], transfers: [move, next])
        let last = try budget(third, transfers: [next])
        #expect(intermediate.clientPaid.minorUnits == 0 && last.clientPaid.minorUnits == 100)
        #expect(try source.recognized.adding(intermediate.recognized).adding(last.recognized) == money(215))
        #expect(throws: ProjectBudgetCalculation.Failure.duplicateSource) {
            try budget(scope, paid: [invoice()], transfers: [move, move])
        }
        #expect(throws: ProjectBudgetCalculation.Failure.scopeMismatch) {
            try budget(third, transfers: [move])
        }
        #expect(throws: ProjectBudgetCalculation.Failure.missingEvidence) {
            try transfer("bad", from: scope, to: destination,
                items: [.init(itemId: .init(validating: "wrong-item"), basis: .paidLine(paidLine))])
        }
    }
}
