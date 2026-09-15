import LedgerTargetCore
import Testing
@testable import LedgerTargetMigrationCore

@Suite("Acquisition money-owner mapping")
struct FirebaseAcquisitionConversionTests {
    @Test func expenseFieldsPreserveEvidenceWithoutCreatingPaymentOrUnpaidStatus() throws {
        func expense(_ changes: [String: FirebaseSourceValue] = [:]) -> FirebaseSourceDocument {
            let original = source(payer: "design-business")
            guard case .map(let fields) = original.fields else { fatalError("fixture") }
            var values = Dictionary(uniqueKeysWithValues: fields.map { ($0.key, $0.value) })
            values["source"] = .string("Original vendor")
            values["notes"] = .string("Exact notes")
            values["transactionDate"] = .string("2024-02-29")
            values["unknownEvidence"] = .string("retained")
            values["amountCents"] = .integer("9007199254740993")
            values.merge(changes) { _, new in new }
            return .init(accountScopeID: original.accountScopeID, documentPathSegments: original.documentPathSegments,
                entityCode: original.entityCode, evidenceKind: .record,
                fields: .map(values.keys.sorted().map { .init(key: $0, value: values[$0]!) }), sourceRecordID: original.sourceRecordID)
        }
        func convert(_ value: FirebaseSourceDocument, mappings: [FirebaseExpenseConversion.ReceiptMapping] = []) throws -> FirebaseExpenseConversion.Result {
            try FirebaseExpenseConversion.convert(value, sourceAccountID: "source", sourceProjectID: "project",
                targetScope: scope(), expenseID: .init(validating: "target-expense"),
                categoryID: .init(validating: "target-category"), currency: .init(validating: "USD"),
                documents: [category()], lineage: [], receiptMappings: mappings)
        }
        let original = expense()
        guard case .sourceMapped(let draft, let retained) = try convert(original) else {
            Issue.record("Expected source-field mapping"); return
        }
        #expect(retained == original)
        #expect(draft.vendor == "Original vendor" && draft.notes == "Exact notes")
        #expect(draft.date == "2024-02-29" && draft.finalAmount.minorUnits == 9007199254740993)
        #expect(draft.projectId.rawValue == "target-project" && draft.accountId.rawValue == "target-account")
        #expect(draft.receiptAttachmentIds.isEmpty && draft.receiptLines.isEmpty)
        let reference = FirebaseSourceValue.map([.init(key: "fileName", value: .string("Original.pdf")),
            .init(key: "kind", value: .string("pdf")),
            .init(key: "url", value: .string("https://source.invalid/original.pdf"))])
        func object(account: String = "target-account") throws -> DownloadedMediaObjectReference {
            let hash = String(repeating: "a", count: 64)
            return try .init(accountId: .init(validating: account), attachmentId: "target-receipt", sha256: hash,
                byteCount: "12", mediaType: "application/pdf",
                storagePath: "accounts/\(account)/attachments/target-receipt/\(hash)", kind: .pdf)
        }
        let withReceipt = expense(["receiptImages": .array([reference])])
        let mapping = try FirebaseExpenseConversion.ReceiptMapping(sourceReference: reference, object: object())
        guard case .sourceMapped(let receiptDraft, let evidence) = try convert(withReceipt, mappings: [mapping]) else {
            Issue.record("Complete receipt mapping did not retain source"); return
        }
        #expect(receiptDraft.receiptAttachmentIds.map(\.rawValue) == ["target-receipt"])
        #expect(evidence == withReceipt)
        for bad in [[], [mapping,mapping],
                    [try .init(sourceReference: .string("different source"), object: object())],
                    [try .init(sourceReference: reference, object: object(account: "foreign-account"))]] {
            guard case .unresolved(.attachmentMappingRequired) = try convert(withReceipt, mappings: bad) else {
                Issue.record("Incomplete/foreign/substituted media mapping accepted"); continue
            }
        }
        for key in ["receiptImages", "otherImages", "transactionImages"] {
            guard case .unresolved(.attachmentMappingRequired) = try convert(expense([key: .array([.string("unmapped")])])) else {
                Issue.record("Media evidence silently dropped"); continue
            }
        }
        for change: [String: FirebaseSourceValue] in [
            ["transactionDate": .string("2023-02-29")], ["transactionDate": .null], ["notes": .integer("1")]
        ] {
            guard case .unresolved(.invalidSourceFields) = try convert(expense(change)) else {
                Issue.record("Malformed fields mapped"); continue
            }
        }
        guard case .unresolved(.sourceMeaningUnresolved) = try convert(expense(["purchasedBy": .string("client-card")])) else {
            Issue.record("Client payment became Expense"); return
        }
    }

    private func source(payer: String) -> FirebaseSourceDocument {
        .init(accountScopeID: "source", documentPathSegments: ["accounts", "source", "transactions", "receipt"],
            entityCode: "transactions", evidenceKind: .record, fields: .map([
                .init(key: "projectId", value: .string("project")), .init(key: "type", value: .string("purchase")), .init(key: "budgetCategoryId", value: .string("category")),
                .init(key: "purchasedBy", value: .string(payer)), .init(key: "amountCents", value: .integer("12345")),
                .init(key: "itemIds", value: .array([]))].sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }), sourceRecordID: "receipt")
    }
    private func scope() throws -> TransactionScope {
        .project(accountId: try .init(validating: "target-account"), projectId: try .init(validating: "target-project"), clientId: try .init(validating: "target-client"))
    }
    private func category(_ kind: String = "general") -> FirebaseSourceDocument {
        .init(accountScopeID: "source", documentPathSegments: ["accounts", "source", "presets", "default", "budgetCategories", "category"],
            entityCode: "budgetCategories", evidenceKind: .record,
            fields: .map([.init(key: "metadata", value: .map([.init(key: "categoryType", value: .string(kind))]))]), sourceRecordID: "category")
    }
    @Test func moneyFollowsPayerNotPhysicalProject() throws {
        let scope = try scope()
        let cases: [(String, TransactionScopeOwnerKind)] = [("client-card", .project), ("design-business", .businessInventory)]
        for (payer, expected) in cases {
            let source = source(payer: payer)
            let result = FirebaseAcquisitionConversion.convert(source, sourceAccountID: "source", sourceProjectID: "project", targetProjectScope: scope, documents: [category("itemized")], lineage: [])
            guard case .planned(let plan) = result else { Issue.record("Expected explicit payer mapping"); continue }
            #expect(plan.classification.scope.ownerKind == expected)
            #expect(plan.classification.type == .purchase)
            #expect(plan.amountCents == 12345)
            #expect(plan.source == source)
            #expect(plan.sourceProjectScope == scope)
            #expect(plan.categoryKind == .itemized)
            #expect(plan.sourceCategory == category("itemized"))
        }
    }
    @Test func businessGeneralCostsCannotBecomeInventoryPurchases() throws {
        let business = FirebaseAcquisitionConversion.convert(source(payer: "design-business"), sourceAccountID: "source",
            sourceProjectID: "project", targetProjectScope: try scope(), documents: [category()], lineage: [])
        guard case .unresolved(.businessExpenseRequiresMapping) = business else {
            Issue.record("Business-paid General cost must await Expense/history mapping, not become a Purchase"); return
        }
        let client = FirebaseAcquisitionConversion.convert(source(payer: "client-card"), sourceAccountID: "source",
            sourceProjectID: "project", targetProjectScope: try scope(), documents: [category()], lineage: [])
        guard case .planned(let plan) = client else { Issue.record("Client-paid cost lost its payment mapping"); return }
        #expect(plan.classification.scope.ownerKind == .project)
        #expect(plan.classification.type == .purchase)
        #expect(plan.categoryKind == .general)
    }
    @Test func unknownPayerAndWrongProjectNeverMap() throws {
        let scope = try scope()
        if case .planned = FirebaseAcquisitionConversion.convert(source(payer: "unknown"), sourceAccountID: "source", sourceProjectID: "project", targetProjectScope: scope, documents: [], lineage: []) { Issue.record("Unknown payer mapped") }
        if case .planned = FirebaseAcquisitionConversion.convert(source(payer: "client-card"), sourceAccountID: "source", sourceProjectID: "wrong", targetProjectScope: scope, documents: [], lineage: []) { Issue.record("Wrong project mapped") }
    }
    @Test func categoryMeaningMustBeExplicitAndUnique() throws {
        for categories in [[], [category("unknown")], [category(), category()]] {
            if case .planned = FirebaseAcquisitionConversion.convert(source(payer: "client-card"), sourceAccountID: "source", sourceProjectID: "project", targetProjectScope: try scope(), documents: categories, lineage: []) {
                Issue.record("Missing, unknown or duplicate category mapped")
            }
        }
    }
}
