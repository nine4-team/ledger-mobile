import Foundation
import LedgerTargetCore

/// One atomic operator import request, not an app command or migration approval.
package struct FirebaseExpenseInvoiceImportParameters: Encodable, Sendable {
    package struct Expense: Encodable, Sendable {
        struct Record: Encodable, Sendable {
            let id, account_id, project_id, category_id, vendor, expense_date: String
            let final_amount_minor_units, currency, notes, revision: String
            let created_at: String?
            // The current source Transaction model has no author field.
            let created_by_principal_id: String? = nil
        }
        let record: Record
        let source_document_id, source_bytes: String
        let receipt_attachment_ids: [String]
    }
    package let p_invoice: FrozenInvoiceStorageRecord
    package let p_expenses: [Expense]
    package let p_payment: FirebaseClientPaymentImportParameters
    package let p_source_account, p_source_invoice, p_invoice_bytes: String

    package static func make(review: FirebaseInvoiceSourcesReview, mappedSources: [FirebaseExpenseConversion.Result],
        targetScope: TransactionScope, invoiceID: InvoiceID, payment: FirebaseClientPaymentImportParameters,
        invoiceRevision: Int64, sourceRevision: Int64, historicalCategories: [String: BudgetCategoryID],
        currency: CurrencyCode) throws -> Self {
        let invoice = try FirebaseExpenseConversion.frozenInvoice(review, mappedSources: mappedSources,
            targetScope: targetScope, invoiceID: invoiceID, payment: payment, invoiceRevision: invoiceRevision,
            sourceRevision: sourceRevision, historicalCategories: historicalCategories, currency: currency)
        let expenses = try mappedSources.map { mapped -> Expense in
            guard case .invoiceSourceMapped(let draft, let source, _, _) = mapped,
                  case .map(let fields) = source.fields,
                  let sourceID = source.documentPathSegments.last,
                  draft.receiptLines.isEmpty else {
                throw FirebaseExpenseConversion.MappingFailure.incompleteInvoiceMapping
            }
            let created: String?
            switch fields.first(where: { $0.key == "createdAt" })?.value {
            case nil, .null: created = nil
            case .timestamp(let seconds, let nanos):
                guard let value = Int64(seconds), (-62135596800...253402300799).contains(value),
                      (0..<1_000_000_000).contains(nanos) else {
                    throw FirebaseExpenseConversion.MappingFailure.incompleteInvoiceMapping
                }
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime]
                let base = formatter.string(from: Date(timeIntervalSince1970: Double(value)))
                // Postgres stores microseconds; submicrosecond evidence remains
                // byte-exact in source_bytes instead of being silently discarded.
                created = String(base.dropLast()) + String(format: ".%06dZ", nanos / 1000)
            default: throw FirebaseExpenseConversion.MappingFailure.incompleteInvoiceMapping
            }
            return Expense(record: .init(id: draft.expenseId.rawValue, account_id: draft.accountId.rawValue,
                project_id: draft.projectId.rawValue, category_id: draft.categoryId.rawValue,
                vendor: draft.vendor, expense_date: draft.date, final_amount_minor_units: String(draft.finalAmount.minorUnits),
                currency: currency.rawValue, notes: draft.notes, revision: String(sourceRevision), created_at: created),
                source_document_id: sourceID, source_bytes: bytes(try source.canonicalEvidenceData()),
                receipt_attachment_ids: draft.receiptAttachmentIds.map(\.rawValue))
        }
        return Self(p_invoice: invoice, p_expenses: expenses, p_payment: payment,
            p_source_account: review.settlement.invoice.accountScopeID,
            p_source_invoice: review.settlement.invoice.documentPathSegments.last!,
            p_invoice_bytes: bytes(try review.settlement.invoice.canonicalEvidenceData()))
    }

    private static func bytes(_ data: Data) -> String {
        "\\x" + data.map { String(format: "%02x", $0) }.joined()
    }
}
