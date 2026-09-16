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
    package struct Fee: Encodable, Sendable {
        struct Record: Encodable, Sendable {
            let id, account_id, project_id, category_id, label: String
            let amount_minor_units, currency, revision: String
            let sort_order: Int64?
            let created_at, created_by_principal_id: String?
        }
        let record: Record
        let source_document_id, source_project_id, source_bytes: String
    }
    package let p_fees: [Fee]
    package struct Item: Encodable, Sendable {
        let source_document_id, source_line_id, source_bytes, line_source_bytes: String
    }
    package enum Source: Encodable, Sendable {
        case expense(Expense), fee(Fee), item(Item)
        package func encode(to encoder: Encoder) throws {
            switch self {
            case .expense(let value): try value.encode(to: encoder)
            case .fee(let value): try value.encode(to: encoder)
            case .item(let value): try value.encode(to: encoder)
            }
        }
    }
    package let p_sources: [Source]
    package let p_payment: FirebaseClientPaymentImportParameters
    package let p_source_account, p_source_invoice, p_invoice_bytes: String

    package static func make(review: FirebaseInvoiceSourcesReview, mappedSources: [FirebaseExpenseConversion.Result],
        targetScope: TransactionScope, invoiceID: InvoiceID, payment: FirebaseClientPaymentImportParameters,
        invoiceRevision: Int64, sourceRevision: Int64, historicalCategories: [String: BudgetCategoryID],
        currency: CurrencyCode, principalMappings: [String: PrincipalID] = [:]) throws -> Self {
        let invoice = try FirebaseExpenseConversion.frozenInvoice(review, mappedSources: mappedSources,
            targetScope: targetScope, invoiceID: invoiceID, payment: payment, invoiceRevision: invoiceRevision,
            sourceRevision: sourceRevision, historicalCategories: historicalCategories, currency: currency)
        func creationTime(_ fields: [FirebaseSourceMapEntry]) throws -> String? {
            switch fields.first(where: { $0.key == "createdAt" })?.value {
            case nil, .null: return nil
            case .timestamp(let seconds, let nanos):
                guard let value = Int64(seconds), (-62135596800...253402300799).contains(value),
                      (0..<1_000_000_000).contains(nanos) else {
                    throw FirebaseExpenseConversion.MappingFailure.incompleteInvoiceMapping
                }
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime]
                let base = formatter.string(from: Date(timeIntervalSince1970: Double(value)))
                return String(base.dropLast()) + String(format: ".%06dZ", nanos / 1000)
            default: throw FirebaseExpenseConversion.MappingFailure.incompleteInvoiceMapping
            }
        }
        let expenses = try mappedSources.compactMap { mapped -> Expense? in
            if case .feeSourceMapped = mapped { return nil }
            if case .paidItemSourceMapped = mapped { return nil }
            guard case .invoiceSourceMapped(let draft, let source, _, _) = mapped,
                  case .map(let fields) = source.fields,
                  let sourceID = source.documentPathSegments.last,
                  draft.receiptLines.isEmpty else {
                throw FirebaseExpenseConversion.MappingFailure.incompleteInvoiceMapping
            }
            let created = try creationTime(fields)
            return Expense(record: .init(id: draft.expenseId.rawValue, account_id: draft.accountId.rawValue,
                project_id: draft.projectId.rawValue, category_id: draft.categoryId.rawValue,
                vendor: draft.vendor, expense_date: draft.date, final_amount_minor_units: String(draft.finalAmount.minorUnits),
                currency: currency.rawValue, notes: draft.notes, revision: String(sourceRevision), created_at: created),
                source_document_id: sourceID, source_bytes: bytes(try source.canonicalEvidenceData()),
                receipt_attachment_ids: draft.receiptAttachmentIds.map(\.rawValue))
        }
        let fees = try mappedSources.compactMap { mapped -> Fee? in
            guard case .feeSourceMapped(let draft, let source, _, _) = mapped else { return nil }
            guard case .map(let fields) = source.fields, source.documentPathSegments.count == 6,
                  let sourceID = source.documentPathSegments.last else {
                throw FirebaseExpenseConversion.MappingFailure.incompleteInvoiceMapping
            }
            let creator: String?
            switch fields.first(where: { $0.key == "createdBy" })?.value {
            case nil, .null: creator = nil
            case .string(let original):
                guard let mapped = principalMappings.first(where: { $0.key.utf8.elementsEqual(original.utf8) })?.value else {
                    throw FirebaseExpenseConversion.MappingFailure.incompleteInvoiceMapping
                }
                creator = mapped.rawValue
            default: throw FirebaseExpenseConversion.MappingFailure.incompleteInvoiceMapping
            }
            return Fee(record: .init(id: draft.installmentId.rawValue, account_id: draft.accountId.rawValue,
                project_id: draft.projectId.rawValue, category_id: draft.categoryId.rawValue, label: draft.label,
                amount_minor_units: String(draft.amount.minorUnits), currency: currency.rawValue,
                revision: String(sourceRevision), sort_order: draft.sortOrder,
                created_at: try creationTime(fields), created_by_principal_id: creator),
                source_document_id: sourceID, source_project_id: source.documentPathSegments[3],
                source_bytes: bytes(try source.canonicalEvidenceData()))
        }
        var expenseIndex = 0, feeIndex = 0
        let sources: [Source] = try mappedSources.map { mapped in
            if case .paidItemSourceMapped(_, let document, _, let line) = mapped {
                guard let sourceID = document.documentPathSegments.last,
                      case .map(let fields) = line,
                      case .string(let lineID) = fields.first(where: { $0.key == "id" })?.value else {
                    throw FirebaseExpenseConversion.MappingFailure.incompleteInvoiceMapping
                }
                return .item(.init(source_document_id: sourceID, source_line_id: lineID,
                    source_bytes: bytes(try document.canonicalEvidenceData()),
                    line_source_bytes: bytes(try FirebaseSourceFixtureCatalog.canonicalData(for: line))))
            }
            if case .feeSourceMapped = mapped {
                defer { feeIndex += 1 }
                return .fee(fees[feeIndex])
            }
            defer { expenseIndex += 1 }
            return .expense(expenses[expenseIndex])
        }
        return Self(p_invoice: invoice, p_expenses: expenses, p_fees: fees, p_sources: sources, p_payment: payment,
            p_source_account: review.settlement.invoice.accountScopeID,
            p_source_invoice: review.settlement.invoice.documentPathSegments.last!,
            p_invoice_bytes: bytes(try review.settlement.invoice.canonicalEvidenceData()))
    }

    private static func bytes(_ data: Data) -> String {
        "\\x" + data.map { String(format: "%02x", $0) }.joined()
    }
}
