import Foundation
import LedgerTargetCore

/// Source-field conversion only. A mapped source is not authority to insert a
/// billable Expense: Invoice/settlement mapping must be applied with it.
package enum FirebaseExpenseConversion {
    /// Supplied only after the existing media copier/verifier has established
    /// the protected target object. This mapping itself never downloads bytes.
    package struct ReceiptMapping: Sendable {
        package let sourceReference: FirebaseSourceValue
        package let object: DownloadedMediaObjectReference
        package init(sourceReference: FirebaseSourceValue, object: DownloadedMediaObjectReference) {
            self.sourceReference = sourceReference; self.object = object
        }
    }
    package enum Issue: String, Sendable {
        case sourceMeaningUnresolved, itemHistoryRequiresMapping, attachmentMappingRequired
        case invalidSourceFields
        case invoiceSourceUnresolved, settlementUnresolved, invoiceAmountRequiresMapping
    }

    /// Compose an Expense-only Invoice import record using the canonical frozen
    /// contract. Mixed Item/Fee/manual invoices must provide their own complete
    /// source mapping; this function never drops those lines to make a subtotal.
    package static func frozenInvoice(_ review: FirebaseInvoiceSourcesReview, mappedSources: [Result],
        targetScope: TransactionScope, invoiceID: InvoiceID, payment: FirebaseClientPaymentImportParameters,
        invoiceRevision: Int64, sourceRevision: Int64,
        historicalCategories: [String: BudgetCategoryID], currency: CurrencyCode) throws -> FrozenInvoiceStorageRecord {
        guard review.settlement.hasSinglePaymentLineCoverage,
              mappedSources.count == review.lines.count, !mappedSources.isEmpty else {
            throw MappingFailure.incompleteInvoiceMapping
        }
        func field(_ value: FirebaseSourceValue, _ key: String) -> FirebaseSourceValue? {
            guard case .map(let fields) = value else { return nil }
            return fields.first { $0.key.utf8.elementsEqual(key.utf8) }?.value
        }
        let lines: [FrozenInvoiceLine] = try zip(review.lines, mappedSources).map { reviewed, mapped in
            guard case .invoiceSourceMapped(let draft, let original, let invoice, let line) = mapped,
                  let reviewedSource = reviewed.source,
                  try invoice.canonicalEvidenceData() == review.settlement.invoice.canonicalEvidenceData(),
                  try FirebaseSourceFixtureCatalog.canonicalData(for: line) == FirebaseSourceFixtureCatalog.canonicalData(for: reviewed.line),
                  try original.canonicalEvidenceData() == reviewedSource.canonicalEvidenceData(),
                  draft.accountId == targetScope.accountId, draft.projectId == targetScope.projectId,
                  draft.finalAmount.currency == currency,
                  case .string(let lineID) = field(line, "id"),
                  case .string(let category) = field(line, "budgetCategoryId"),
                  let targetCategory = historicalCategories.first(where: { $0.key.utf8.elementsEqual(category.utf8) })?.value,
                  case .string(let description) = field(line, "snapshotName"),
                  case .integer("1") = field(line, "sign"),
                  case .integer(let amountText) = field(line, "amountCents"),
                  let amount = Int64(amountText), amount == draft.finalAmount.minorUnits else {
                throw MappingFailure.incompleteInvoiceMapping
            }
            // Source line IDs are scoped to their original Invoice. Target
            // storage uses a global key; retain the original in source evidence
            // while deterministically namespacing the target identity.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            let identity = try encoder.encode([targetScope.accountId.rawValue, invoiceID.rawValue, lineID])
            let targetLineID = "import-line-" + (try MigrationSHA256.make(bytes: identity)).rawValue
            return try FrozenInvoiceLine(id: .init(validating: targetLineID), scope: targetScope,
                source: .expense(expenseId: draft.expenseId), sourceRevision: sourceRevision, categoryId: targetCategory,
                signedAmount: .init(minorUnits: amount, currency: currency), description: description)
        }
        guard case .integer(let totalText) = field(review.settlement.invoice.fields, "totalCents"),
              let total = Int64(totalText) else { throw MappingFailure.incompleteInvoiceMapping }
        // A target ID alone cannot prove that this is the payment reviewed above.
        // Bind the frozen record to the exact import parameters, including the
        // complete original envelope; the database loader must check these again
        // against stored payment evidence before inserting any Expense.
        guard review.settlement.suppliedPayments.count == 1,
              let sourcePayment = review.settlement.suppliedPayments.first,
              let sourcePaymentID = sourcePayment.documentPathSegments.last,
              payment.p_account_id == targetScope.accountId.rawValue,
              payment.p_project_id == targetScope.projectId?.rawValue,
              payment.p_client_id == targetScope.clientId?.rawValue,
              payment.p_currency == currency.rawValue, payment.p_amount == String(total),
              payment.p_source_account.utf8.elementsEqual(sourcePayment.accountScopeID.utf8),
              payment.p_source_document.utf8.elementsEqual(sourcePaymentID.utf8),
              payment.p_source_bytes == "\\x" + (try sourcePayment.canonicalEvidenceData())
                .map({ String(format: "%02x", $0) }).joined() else {
            throw MappingFailure.incompleteInvoiceMapping
        }
        return try FrozenInvoiceStorageRecord.make(.init(invoiceId: invoiceID, invoiceRevision: invoiceRevision,
            scope: targetScope, purchaseId: .init(validating: payment.p_id), lines: lines,
            total: .init(minorUnits: total, currency: currency),
            displayMetadata: FirebaseInvoiceDisplayMetadata.read(review.settlement.invoice)))
    }

    package enum MappingFailure: Error { case incompleteInvoiceMapping }
    package enum Result: Sendable {
        case sourceMapped(BusinessPaidExpenseDraft, original: FirebaseSourceDocument)
        case invoiceSourceMapped(BusinessPaidExpenseDraft, original: FirebaseSourceDocument,
            invoice: FirebaseSourceDocument, line: FirebaseSourceValue)
        case unresolved(Issue)
    }

    /// Keeps a paid Invoice's original line attached to the mapped source.
    /// This does not produce a target collection command or a new unpaid charge.
    package static func convertInvoiceSource(_ review: FirebaseInvoiceSourcesReview, lineID: String,
        targetScope: TransactionScope, expenseID: ExpenseID, categoryID: BudgetCategoryID,
        currency: CurrencyCode, lineage: [ReconciledFirebaseLineageEvidence], receiptMappings: [ReceiptMapping] = []) -> Result {
        guard review.settlement.hasSinglePaymentLineCoverage else { return .unresolved(.settlementUnresolved) }
        func field(_ value: FirebaseSourceValue, _ key: String) -> FirebaseSourceValue? {
            guard case .map(let fields) = value else { return nil }
            return fields.first { $0.key.utf8.elementsEqual(key.utf8) }?.value
        }
        let matches = review.lines.filter {
            guard case .string(let id) = field($0.line, "id") else { return false }
            return id.utf8.elementsEqual(lineID.utf8)
        }
        guard matches.count == 1, let selected = matches.first,
              selected.issues == [.transactionMeaningNotMapped], let source = selected.source,
              case .string(let project) = field(review.settlement.invoice.fields, "projectId") else {
            return .unresolved(.invoiceSourceUnresolved)
        }
        let result = convert(source, sourceAccountID: review.settlement.invoice.accountScopeID,
            sourceProjectID: project, targetScope: targetScope, expenseID: expenseID,
            categoryID: categoryID, currency: currency, documents: review.suppliedDocuments, lineage: lineage, receiptMappings: receiptMappings)
        guard case .sourceMapped(let draft, let original) = result else { return result }
        guard case .integer("1") = field(selected.line, "sign"),
              case .integer(let text) = field(selected.line, "amountCents"),
              Int64(text) == draft.finalAmount.minorUnits else {
            return .unresolved(.invoiceAmountRequiresMapping)
        }
        return .invoiceSourceMapped(draft, original: original, invoice: review.settlement.invoice, line: selected.line)
    }

    package static func convert(_ source: FirebaseSourceDocument, sourceAccountID: String,
        sourceProjectID: String, targetScope: TransactionScope, expenseID: ExpenseID,
        categoryID: BudgetCategoryID, currency: CurrencyCode, documents: [FirebaseSourceDocument],
        lineage: [ReconciledFirebaseLineageEvidence], receiptMappings: [ReceiptMapping] = []) -> Result {
        // Reuse the existing payer/category/project and bidirectional Item
        // reconciliation. An empty current Item list cannot erase older links.
        guard case .unresolved(.businessExpenseRequiresMapping) = FirebaseAcquisitionConversion.convert(source,
            sourceAccountID: sourceAccountID, sourceProjectID: sourceProjectID, targetProjectScope: targetScope,
            documents: documents, lineage: lineage), case .map(let fields) = source.fields else {
            return .unresolved(.sourceMeaningUnresolved)
        }
        let purchase = FirebaseAcquisitionSourceReview.review(source, accountID: sourceAccountID)
        let links = FirebaseAcquisitionSourceReview.reconcileItems(purchase, documents: documents, lineage: lineage)
        guard links.currentItemIDs.isEmpty, links.historicalItemIDs.isEmpty else {
            return .unresolved(.itemHistoryRequiresMapping)
        }
        func field(_ key: String) -> FirebaseSourceValue? { fields.first { $0.key == key }?.value }
        // Do not silently drop legacy receipt/other media or manufacture target
        // object IDs. Retain source evidence until its byte mapping is supplied.
        for key in ["otherImages", "transactionImages"] {
            switch field(key) {
            case nil, .null: break
            case .array(let values) where values.isEmpty: break
            default: return .unresolved(.attachmentMappingRequired)
            }
        }
        let sourceReceipts: [FirebaseSourceValue]
        switch field("receiptImages") {
        case nil, .null: sourceReceipts = []
        case .array(let values): sourceReceipts = values
        default: return .unresolved(.attachmentMappingRequired)
        }
        guard sourceReceipts.count == receiptMappings.count else { return .unresolved(.attachmentMappingRequired) }
        for (reference, mapping) in zip(sourceReceipts, receiptMappings) {
            guard case .map(let fields) = reference,
                  case .string = fields.first(where: { $0.key == "url" })?.value,
                  case .string(let kind) = fields.first(where: { $0.key == "kind" })?.value,
                  kind == (mapping.object.mediaType == "application/pdf" ? "pdf" : "image"),
                  mapping.object.accountId == targetScope.accountId,
                  let sourceBytes = try? FirebaseSourceFixtureCatalog.canonicalData(for: reference),
                  let mappedBytes = try? FirebaseSourceFixtureCatalog.canonicalData(for: mapping.sourceReference),
                  sourceBytes == mappedBytes else { return .unresolved(.attachmentMappingRequired) }
        }
        func optionalText(_ key: String) -> String? {
            switch field(key) { case nil, .null: return ""; case .string(let text): return text; default: return nil }
        }
        guard let vendor = optionalText("source"), let notes = optionalText("notes"),
              case .string(let date) = field("transactionDate"), let amount = purchase.amountCents,
              let projectID = targetScope.projectId else { return .unresolved(.invalidSourceFields) }
        do {
            let draft = try BusinessPaidExpenseDraft(accountId: targetScope.accountId, projectId: projectID,
                expenseId: expenseID, vendor: vendor, date: date,
                finalAmount: .init(minorUnits: amount, currency: currency), categoryId: categoryID, notes: notes,
                receiptAttachmentIds: receiptMappings.map { $0.object.attachmentId })
            return .sourceMapped(draft, original: source)
        } catch { return .unresolved(.invalidSourceFields) }
    }
}
