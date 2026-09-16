import Foundation
import Testing
import LedgerTargetCore
@testable import LedgerTargetMigrationCore

@Suite("Source Invoice settlement coverage")
struct FirebaseInvoiceSettlementReviewTests {
    @Test func invoiceDisplayFieldsPreserveOriginalValuesAndUnknowns() throws {
        let source = Self.document("invoices", "display", ["invoiceNumber": .string("  INV-001  "),
            "notes": .string("First\nSecond"), "datePaid": .timestamp(seconds: "-1", nanoseconds: 999_999_999)])
        let before = try source.canonicalEvidenceData()
        let decoded = try FirebaseInvoiceDisplayMetadata.read(source)
        let display = try #require(decoded)
        #expect(display.invoiceNumber == "  INV-001  ")
        #expect(display.notes == "First\nSecond")
        #expect(display.paidAtMilliseconds == "-1")
        #expect(display.issuedAtMilliseconds == nil)
        #expect(try source.canonicalEvidenceData() == before)
        #expect(try FirebaseInvoiceDisplayMetadata.read(Self.document("invoices", "none", [:])) == nil)
        #expect(throws: InvoiceDisplayMetadata.Failure.invalid) {
            try FirebaseInvoiceDisplayMetadata.read(Self.document("invoices", "bad", ["datePaid": .string("2024-01-01")]))
        }
    }
    private static func map(_ fields: [String: FirebaseSourceValue]) -> FirebaseSourceValue {
        .map(fields.keys.sorted().map { .init(key: $0, value: fields[$0]!) })
    }
    private static func document(_ collection: String, _ id: String, _ fields: [String: FirebaseSourceValue]) -> FirebaseSourceDocument {
        .init(accountScopeID: "source-account", documentPathSegments: ["accounts", "source-account", collection, id],
            entityCode: collection, evidenceKind: .record, fields: map(fields), sourceRecordID: id)
    }
    private static func line(_ id: String = "line", amount: String = "100", sign: String = "1",
                             reverse: [String] = []) -> FirebaseSourceValue {
        map(["id": .string(id), "amountCents": .integer(amount), "sign": .integer(sign),
             "sourceType": .string("item"), "sourceId": .string("physical-item"),
             "settlementTransactionIds": .array(reverse.map { .string($0) })])
    }
    private static func invoice(lines: [FirebaseSourceValue]? = nil, total: String = "100", status: String = "paid") -> FirebaseSourceDocument {
        document("invoices", "invoice", ["projectId": .string("source-project"), "status": .string(status),
            "totalCents": .integer(total), "lines": .array(lines ?? [line()]), "unknown": .string("preserved")])
    }
    private static func payment(_ id: String = "payment", lines: [String] = ["line"], amount: String = "100",
                                status: String? = nil, project: String = "source-project") -> FirebaseSourceDocument {
        var fields: [String: FirebaseSourceValue] = ["type": .string("paymentToBusiness"), "amountCents": .integer(amount),
            "projectId": .string(project), "settlementInvoiceId": .string("invoice"),
            "settlementInvoiceLineIds": .array(lines.map { .string($0) })]
        if let status { fields["status"] = .string(status) }
        return document("transactions", id, fields)
    }
    private static func review(_ invoice: FirebaseSourceDocument, _ payments: [FirebaseSourceDocument]) throws -> FirebaseInvoiceSettlementReview {
        .review(invoice: invoice, payments: payments, sourceAccountID: "source-account",
            targetScope: .project(accountId: try AccountID(validating: "target-account"),
                projectId: try ProjectID(validating: "target-project"), clientId: try ClientID(validating: "target-client")))
    }

    @Test("Paid Fee field mapping preserves source evidence without creating new demand")
    func feeFieldMapping() throws {
        let line = Self.map(["id": .string("line"), "amountCents": .integer("9007199254740993"),
            "sign": .integer("1"), "sourceType": .string("feeInstallment"), "sourceId": .string("fee")])
        let source = FirebaseSourceDocument(accountScopeID: "source-account",
            documentPathSegments: ["accounts", "source-account", "projects", "source-project", "feeInstallments", "fee"],
            entityCode: "feeInstallments", evidenceKind: .record,
            fields: Self.map(["budgetCategoryId": .string("category"), "label": .string("Original fee"),
                "amountCents": .integer("9007199254740993"), "sortOrder": .integer("2"), "unknown": .string("retain")]),
            sourceRecordID: "fee")
        let review = try Self.review(Self.invoice(lines: [line], total: "9007199254740993"),
            [Self.payment(amount: "9007199254740993")]).resolveSources(in: [source])
        let scope = TransactionScope.project(accountId: try .init(validating: "target-account"),
            projectId: try .init(validating: "target-project"), clientId: try .init(validating: "target-client"))
        let category = try BudgetCategoryID(validating: "target-category")
        func map(_ value: FirebaseInvoiceSourcesReview, categories: [String: BudgetCategoryID]) throws -> FeeInstallmentDraft {
            try value.mapFee(lineID: "line", targetScope: scope, installmentID: .init(validating: "target-fee"),
                categories: categories, currency: .init(validating: "USD")).draft
        }
        let mapped = try review.mapFee(lineID: "line", targetScope: scope, installmentID: .init(validating: "target-fee"),
            categories: ["category": category], currency: .init(validating: "USD"))
        #expect(mapped.draft.amount.minorUnits == 9007199254740993)
        #expect(mapped.draft.label == "Original fee" && mapped.draft.sortOrder == 2)
        #expect(mapped.evidence.source == source && mapped.evidence.line == line)
        #expect(throws: (any Error).self) { try map(review, categories: [:]) }
        let missing = try Self.review(Self.invoice(lines: [line], total: "9007199254740993"),
            [Self.payment(amount: "9007199254740993")]).resolveSources(in: [])
        #expect(throws: (any Error).self) { try map(missing, categories: ["category": category]) }
        let foreignScope = TransactionScope.project(accountId: try .init(validating: "foreign-account"),
            projectId: scope.projectId!, clientId: scope.clientId!)
        #expect(throws: (any Error).self) {
            try review.mapFee(lineID: "line", targetScope: foreignScope,
                installmentID: .init(validating: "target-fee"), categories: ["category": category], currency: .init(validating: "USD"))
        }
        for change: [String: FirebaseSourceValue] in [
            ["amountCents": .integer("9007199254740992")], ["label": .string(" ")],
            ["sortOrder": .string("2")], ["sortOrder": .integer("2147483648")],
            ["projectId": .string("foreign-project")], ["accountId": .string("foreign-account")]
        ] {
            guard case .map(let fields) = source.fields else { Issue.record("Invalid fixture"); return }
            var values = Dictionary(uniqueKeysWithValues: fields.map { ($0.key, $0.value) })
            values.merge(change) { _, new in new }
            let changed = FirebaseSourceDocument(accountScopeID: source.accountScopeID,
                documentPathSegments: source.documentPathSegments, entityCode: source.entityCode,
                evidenceKind: .record, fields: Self.map(values), sourceRecordID: source.sourceRecordID)
            let rejected = review.settlement.resolveSources(in: [changed])
            #expect(throws: (any Error).self) { try map(rejected, categories: ["category": category]) }
        }
        let duplicated = review.settlement.resolveSources(in: [source, source])
        #expect(throws: (any Error).self) { try map(duplicated, categories: ["category": category]) }
    }

    @Test("Exact signed lines and one explicit payment establish only source line coverage")
    func exactCoverage() throws {
        let source = Self.invoice(lines: [Self.line("charge", amount: "120"), Self.line("credit", amount: "20", sign: "-1")])
        let payments = [Self.payment(lines: ["credit", "charge"])]
        let result = try Self.review(source, payments)
        #expect(result.hasSinglePaymentLineCoverage)
        #expect(result.invoice == source)
        #expect(result.suppliedPayments == payments)
    }

    @Test("Canceled and recollected history is retained, never resurrected by surviving links")
    func canceledHistory() throws {
        let source = Self.invoice(lines: [Self.line(reverse: ["old", "new"])])
        let payments = [Self.payment("old", status: "CANCELLED"), Self.payment("new")]
        let result = try Self.review(source, payments)
        #expect(result.issues.contains(.canceledPaymentHistory))
        #expect(!result.hasSinglePaymentLineCoverage)
        #expect(result.suppliedPayments == payments)
        let canceledOnly = try Self.review(Self.invoice(status: "sent"), [payments[0]])
        #expect(canceledOnly.issues.contains(.noActivePayment))
        #expect(canceledOnly.issues.contains(.invoiceNotPaid))
    }

    @Test("Category-grouped, partial and status-only collection are not silently consolidated")
    func ambiguousSettlements() throws {
        let source = Self.invoice(lines: [Self.line("a", amount: "40"), Self.line("b", amount: "60")])
        #expect(try Self.review(source, [Self.payment("a", lines: ["a"], amount: "40"),
            Self.payment("b", lines: ["b"], amount: "60")]).issues.contains(.multipleActivePayments))
        let partial = try Self.review(source, [Self.payment(lines: ["a"], amount: "40")])
        #expect(partial.issues.contains(.paymentLineCoverageMismatch))
        #expect(partial.issues.contains(.paymentAmountMismatch))
        #expect(try Self.review(source, []).issues.contains(.noActivePayment))
    }

    @Test("Missing legacy line identity, duplicate IDs, foreign scope and dangling history block mapping")
    func identityAndScope() throws {
        let noID = Self.map(["amountCents": .integer("100"), "sign": .integer("1"), "sourceType": .string("manual")])
        #expect(try Self.review(Self.invoice(lines: [noID]), [Self.payment()]).issues.contains(.missingOrInvalidLines))
        #expect(try Self.review(Self.invoice(lines: [Self.line(), Self.line()], total: "200"), [Self.payment()]).issues.contains(.duplicateLineID))
        #expect(try Self.review(Self.invoice(), [Self.payment(project: "foreign")]).issues.contains(.paymentScopeOrShape))
        #expect(try Self.review(Self.invoice(), [Self.payment(), Self.payment()]).issues.contains(.duplicatePayment))
        #expect(try Self.review(Self.invoice(lines: [Self.line(reverse: ["missing"])]), [Self.payment()]).issues.contains(.paymentScopeOrShape))
        #expect(try Self.review(Self.invoice(), [Self.payment(lines: ["line", "line"])]).issues.contains(.paymentLineCoverageMismatch))
    }

    @Test("Integer overflow and mismatched invoice totals never become plausible balances")
    func moneyIntegrity() throws {
        #expect(try Self.review(Self.invoice(total: "99"), [Self.payment()]).issues.contains(.lineTotalMismatch))
        let overflow = Self.invoice(lines: [Self.line("a", amount: "9223372036854775807"), Self.line("b", amount: "1")])
        #expect(try Self.review(overflow, [Self.payment()]).issues.contains(.lineTotalMismatch))
        let exact = Self.invoice(lines: [Self.line(amount: "9007199254740993")], total: "9007199254740993")
        #expect(try Self.review(exact, [Self.payment(amount: "9007199254740993")]).hasSinglePaymentLineCoverage)
    }

    @Test("Conflicting payment copies cannot hide behind a different or missing Invoice link")
    func conflictingLinkedIdentity() throws {
        for link: FirebaseSourceValue? in [.string("another-invoice"), .null, nil] {
            var fields: [String: FirebaseSourceValue] = ["type": .string("paymentToBusiness"),
                "projectId": .string("source-project"), "amountCents": .integer("100")]
            if let link { fields["settlementInvoiceId"] = link }
            let conflicting = Self.document("transactions", "payment", fields)
            let records = [Self.payment(), conflicting]
            let result = try Self.review(Self.invoice(), records)
            #expect(result.issues.contains(.duplicatePayment))
            #expect(!result.hasSinglePaymentLineCoverage)
            #expect(result.suppliedPayments == records)
        }
    }

    @Test("Byte-distinct line identities are not merged by Unicode normalization")
    func exactIdentityBytes() throws {
        let composed = "\u{00e9}", decomposed = "e\u{0301}"
        let source = Self.invoice(lines: [Self.line(composed, amount: "40"), Self.line(decomposed, amount: "60")])
        #expect(try Self.review(source, [Self.payment(lines: [composed, decomposed])]).hasSinglePaymentLineCoverage)
        #expect(try Self.review(source, [Self.payment(lines: [composed, composed])]).issues.contains(.paymentLineCoverageMismatch))
    }

    @Test("Historical Item identity resolves even after relocation, without inventing an occurrence")
    func historicalItemSource() throws {
        let item = Self.document("items", "physical-item", ["projectId": .string("later-project"), "unknown": .string("retained")])
        let reviewed = try Self.review(Self.invoice(), [Self.payment()]).resolveSources(in: [item])
        #expect(reviewed.lines.count == 1)
        #expect(reviewed.lines[0].source == item)
        #expect(reviewed.lines[0].issues == [.itemOccurrenceNotMapped])
        #expect(reviewed.suppliedDocuments == [item])
        let duplicate = try Self.review(Self.invoice(), [Self.payment()]).resolveSources(in: [item, item])
        #expect(duplicate.lines[0].source == nil)
        #expect(duplicate.lines[0].issues == [.duplicateSource])
        #expect(duplicate.suppliedDocuments.count == 2)
    }

    @Test("Source semantic labels do not replace actual document paths or payment fields")
    func semanticEntityLabels() throws {
        let originalInvoice = Self.invoice(), originalPayment = Self.payment()
        let invoice = FirebaseSourceDocument(accountScopeID: originalInvoice.accountScopeID,
            documentPathSegments: originalInvoice.documentPathSegments, entityCode: "legacy_invoices",
            evidenceKind: .record, fields: originalInvoice.fields, sourceRecordID: originalInvoice.sourceRecordID)
        let payment = FirebaseSourceDocument(accountScopeID: originalPayment.accountScopeID,
            documentPathSegments: originalPayment.documentPathSegments, entityCode: "client_payments",
            evidenceKind: .record, fields: originalPayment.fields, sourceRecordID: originalPayment.sourceRecordID)
        let result = try Self.review(invoice, [payment])
        #expect(result.hasSinglePaymentLineCoverage)
        #expect(result.invoice.entityCode == "legacy_invoices")
        #expect(result.suppliedPayments[0].entityCode == "client_payments")
    }

    @Test("Fee identity uses the real nested Project path, not matching IDs elsewhere")
    func nestedFeeIdentity() throws {
        let line = Self.map(["id": .string("line"), "amountCents": .integer("100"), "sign": .integer("1"),
            "sourceType": .string("feeInstallment"), "sourceId": .string("fee")])
        let invoice = Self.invoice(lines: [line])
        let wrong = FirebaseSourceDocument(accountScopeID: "source-account",
            documentPathSegments: ["accounts", "source-account", "projects", "other-project", "feeInstallments", "fee"],
            entityCode: "feeInstallments", evidenceKind: .record, fields: .map([]), sourceRecordID: "wrong")
        let correct = FirebaseSourceDocument(accountScopeID: "source-account",
            documentPathSegments: ["accounts", "source-account", "projects", "source-project", "feeInstallments", "fee"],
            entityCode: "feeInstallments", evidenceKind: .record, fields: .map([]), sourceRecordID: "correct")
        let review = try Self.review(invoice, [Self.payment()])
        #expect(review.resolveSources(in: [wrong]).lines[0].issues == [.missingSource])
        let result = review.resolveSources(in: [wrong, correct])
        #expect(result.lines[0].source == correct)
        #expect(result.lines[0].issues == [.feeNotMapped])
        #expect(result.suppliedDocuments == [wrong, correct])
    }

    @Test("Expense scope, missing source and manual adjustments remain explicit")
    func unresolvedSourceMeaning() throws {
        let expenseLine = Self.map(["id": .string("line"), "amountCents": .integer("100"), "sign": .integer("1"),
            "sourceType": .string("transaction"), "sourceId": .string("expense")])
        let invoice = Self.invoice(lines: [expenseLine])
        let review = try Self.review(invoice, [Self.payment()])
        #expect(review.resolveSources(in: []).lines[0].issues == [.missingSource])
        let foreign = Self.document("transactions", "expense", ["projectId": .string("other-project")])
        #expect(review.resolveSources(in: [foreign]).lines[0].issues == [.projectMismatch])
        let exact = Self.document("transactions", "expense", ["projectId": .string("source-project")])
        #expect(review.resolveSources(in: [exact]).lines[0].issues == [.transactionMeaningNotMapped])
        let manual = Self.map(["id": .string("line"), "amountCents": .integer("100"), "sign": .integer("1"), "sourceType": .string("manual")])
        #expect(try Self.review(Self.invoice(lines: [manual]), [Self.payment()]).resolveSources(in: []).lines[0].issues == [.manualAdjustmentNotMapped])
    }

    @Test("Expense field mapping retains the exact paid Invoice line and requires proven settlement")
    func mapsExpenseSourceWithoutRebilling() throws {
        let line = Self.map(["id": .string("line"), "amountCents": .integer("100"), "sign": .integer("1"),
            "sourceType": .string("transaction"), "sourceId": .string("expense"), "snapshotName": .string("Historical vendor"),
            "budgetCategoryId": .string("historical-category")])
        let invoice = Self.invoice(lines: [line])
        let category = FirebaseSourceDocument(accountScopeID: "source-account",
            documentPathSegments: ["accounts", "source-account", "presets", "default", "budgetCategories", "category"],
            entityCode: "budgetCategories", evidenceKind: .record,
            fields: Self.map(["metadata": Self.map(["categoryType": .string("general")])]), sourceRecordID: "category")
        func source(_ amount: String = "100", created: FirebaseSourceValue = .null) -> FirebaseSourceDocument {
            Self.document("transactions", "expense", ["projectId": .string("source-project"), "type": .string("purchase"),
                "purchasedBy": .string("design-business"), "budgetCategoryId": .string("category"),
                "amountCents": .integer(amount), "transactionDate": .string("2024-02-29"),
                "source": .string("Current vendor"), "itemIds": .array([]), "createdAt": created])
        }
        func convert(_ payments: [FirebaseSourceDocument], amount: String = "100") throws -> FirebaseExpenseConversion.Result {
            let review = try Self.review(invoice, payments).resolveSources(in: [source(amount), category])
            return try FirebaseExpenseConversion.convertInvoiceSource(review, lineID: "line",
                targetScope: .project(accountId: .init(validating: "target-account"), projectId: .init(validating: "target-project"),
                    clientId: .init(validating: "target-client")), expenseID: .init(validating: "target-expense"),
                categoryID: .init(validating: "target-category"), currency: .init(validating: "USD"), lineage: [])
        }
        guard case .invoiceSourceMapped(let draft, let original, let keptInvoice, let keptLine) = try convert([Self.payment()]) else {
            Issue.record("Expected mapped source with paid evidence retained"); return
        }
        #expect(draft.vendor == "Current vendor" && draft.finalAmount.minorUnits == 100)
        #expect(original == source() && keptInvoice == invoice && keptLine == line)
        let reviewed = try Self.review(invoice, [Self.payment()]).resolveSources(in: [source(), category])
        let targetScope = try TransactionScope.project(accountId: .init(validating: "target-account"),
            projectId: .init(validating: "target-project"), clientId: .init(validating: "target-client"))
        func paymentParameters(source: FirebaseSourceDocument = Self.payment(), account: String = "target-account",
                               amount: String = "100") throws -> FirebaseClientPaymentImportParameters {
            .init(p_id: "target-payment", p_account_id: account, p_project_id: "target-project",
                p_client_id: "target-client", p_amount: amount, p_currency: "USD",
                p_source_account: "source-account", p_source_document: source.documentPathSegments.last!,
                p_source_bytes: "\\x" + (try source.canonicalEvidenceData()).map { String(format: "%02x", $0) }.joined())
        }
        func frozen(_ mappings: [FirebaseExpenseConversion.Result], categories: [String: BudgetCategoryID],
                    payment: FirebaseClientPaymentImportParameters? = nil, invoiceID: String = "target-invoice") throws -> FrozenInvoiceContents {
            try FirebaseExpenseConversion.frozenInvoice(reviewed, mappedSources: mappings, targetScope: targetScope,
                invoiceID: .init(validating: invoiceID), payment: payment ?? paymentParameters(),
                invoiceRevision: 1, sourceRevision: 1, historicalCategories: categories,
                currency: .init(validating: "USD")).restored()
        }
        let mapped = try convert([Self.payment()])
        let historicalCategories = ["historical-category": try BudgetCategoryID(validating: "historical-target-category")]
        let frozenRecord = try frozen([mapped], categories: historicalCategories)
        #expect(frozenRecord.total.minorUnits == 100 && frozenRecord.lines.count == 1)
        #expect(frozenRecord.lines[0].description == "Historical vendor")
        #expect(frozenRecord.lines[0].categoryId.rawValue == "historical-target-category")
        #expect(frozenRecord.lines[0].source == .expense(expenseId: draft.expenseId))
        #expect(frozenRecord.purchaseId.rawValue == "target-payment")
        #expect(frozenRecord.lines[0].id.rawValue.hasPrefix("import-line-"))
        #expect(try frozen([mapped], categories: historicalCategories).lines[0].id == frozenRecord.lines[0].id)
        #expect(try frozen([mapped], categories: historicalCategories, invoiceID: "other-invoice").lines[0].id != frozenRecord.lines[0].id)
        let parameters = try FirebaseExpenseInvoiceImportParameters.make(review: reviewed, mappedSources: [mapped],
            targetScope: targetScope, invoiceID: .init(validating: "target-invoice"), payment: paymentParameters(),
            invoiceRevision: 1, sourceRevision: 1, historicalCategories: historicalCategories, currency: .init(validating: "USD"))
        #expect(parameters.p_expenses.count == 1)
        #expect(parameters.p_expenses[0].record.final_amount_minor_units == "100")
        #expect(parameters.p_expenses[0].record.created_at == nil)
        #expect(parameters.p_expenses[0].record.created_by_principal_id == nil)
        #expect(parameters.p_expenses[0].source_document_id == "expense")
        #expect(parameters.p_invoice_bytes == "\\x" + (try invoice.canonicalEvidenceData()).map { String(format: "%02x", $0) }.joined())
        func timestampParameters(_ created: FirebaseSourceValue) throws -> FirebaseExpenseInvoiceImportParameters {
            let original = source(created: created)
            let evidence = try Self.review(invoice, [Self.payment()]).resolveSources(in: [original, category])
            let mapped = try FirebaseExpenseConversion.convertInvoiceSource(evidence, lineID: "line", targetScope: targetScope,
                expenseID: .init(validating: "target-expense"), categoryID: .init(validating: "target-category"),
                currency: .init(validating: "USD"), lineage: [])
            return try .make(review: evidence, mappedSources: [mapped], targetScope: targetScope,
                invoiceID: .init(validating: "target-invoice"), payment: paymentParameters(),
                invoiceRevision: 1, sourceRevision: 1, historicalCategories: historicalCategories, currency: .init(validating: "USD"))
        }
        let timestamp = FirebaseSourceValue.timestamp(seconds: "-1", nanoseconds: 999_999_999)
        let timestamped = try timestampParameters(timestamp)
        #expect(timestamped.p_expenses[0].record.created_at == "1969-12-31T23:59:59.999999Z")
        #expect(timestamped.p_expenses[0].source_bytes == "\\x" + (try source(created: timestamp).canonicalEvidenceData())
            .map { String(format: "%02x", $0) }.joined())
        #expect(throws: FirebaseExpenseConversion.MappingFailure.self) {
            try timestampParameters(.string("yesterday"))
        }
        #expect(throws: FirebaseExpenseConversion.MappingFailure.self) {
            try frozen([mapped], categories: historicalCategories, payment: paymentParameters(source: Self.payment("other-payment")))
        }
        #expect(throws: FirebaseExpenseConversion.MappingFailure.self) {
            try frozen([mapped], categories: historicalCategories, payment: paymentParameters(account: "other-account"))
        }
        #expect(throws: FirebaseExpenseConversion.MappingFailure.self) {
            try frozen([mapped], categories: historicalCategories, payment: paymentParameters(amount: "101"))
        }
        #expect(throws: FirebaseExpenseConversion.MappingFailure.self) { try frozen([], categories: historicalCategories) }
        #expect(throws: FirebaseExpenseConversion.MappingFailure.self) { try frozen([mapped], categories: [:]) }
        guard case .unresolved(.settlementUnresolved) = try convert([]) else { Issue.record("Status-only paid evidence mapped"); return }
        guard case .unresolved(.invoiceAmountRequiresMapping) = try convert([Self.payment()], amount: "200") else {
            Issue.record("Changed source amount overwrote paid line amount"); return
        }
    }
}
