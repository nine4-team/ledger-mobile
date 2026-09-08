import Foundation
import LedgerTargetCore

package enum FrozenInvoiceStorageFailure: Error { case malformedRecord, unsupportedText }

/// Private persistence transport, not collection authorization. The existing
/// frozen contract remains the authority for scope, identities and arithmetic.
package struct FrozenInvoiceStorageRecord: Codable, Sendable {
    package struct Line: Codable, Sendable {
        package let id: String
        package let line_position: Int
        package let source_kind: String
        package let source_id: String
        package let item_id: String?
        package let source_revision: String
        package let category_id: String
        package let signed_amount_minor_units: String
        package let description: String
        // Text carries the existing typed source JSON without a JS Number hop.
        package let source_snapshot_json: String
    }
    package let invoice_id: String
    package let invoice_revision: String
    package let account_id: String
    package let project_id: String
    package let client_id: String
    package let purchase_id: String
    package let currency: String
    package let total_minor_units: String
    package let lines: [Line]

    package static func make(_ value: FrozenInvoiceContents) throws -> Self {
        guard let project = value.scope.projectId, let client = value.scope.clientId else {
            throw FrozenInvoiceStorageFailure.malformedRecord
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let lines = try value.lines.enumerated().map { position, line in
            guard !line.description.contains("\0") else { throw FrozenInvoiceStorageFailure.unsupportedText }
            let key = sourceKey(line.source)
            return Line(id: line.id.rawValue, line_position: position, source_kind: key.kind,
                source_id: key.id, item_id: key.item, source_revision: String(line.sourceRevision),
                category_id: line.categoryId.rawValue, signed_amount_minor_units: String(line.signedAmount.minorUnits),
                description: line.description,
                source_snapshot_json: String(decoding: try encoder.encode(line.source), as: UTF8.self))
        }
        return Self(invoice_id: value.invoiceId.rawValue, invoice_revision: String(value.invoiceRevision),
            account_id: value.scope.accountId.rawValue, project_id: project.rawValue, client_id: client.rawValue,
            purchase_id: value.purchaseId.rawValue, currency: value.total.currency.rawValue,
            total_minor_units: String(value.total.minorUnits), lines: lines)
    }

    package func restored() throws -> FrozenInvoiceContents {
        let scope = TransactionScope.project(accountId: try AccountID(validating: account_id),
            projectId: try ProjectID(validating: project_id), clientId: try ClientID(validating: client_id))
        let code = try CurrencyCode(validating: currency)
        let decoded = try lines.sorted { $0.line_position < $1.line_position }.enumerated().map { position, row in
            guard row.line_position == position, !row.description.contains("\0") else {
                throw FrozenInvoiceStorageFailure.malformedRecord
            }
            let source = try JSONDecoder().decode(FrozenInvoiceLineSource.self, from: Data(row.source_snapshot_json.utf8))
            let key = Self.sourceKey(source)
            // Database identities are byte-exact, unlike Swift's canonically
            // equivalent String equality. Never accept a different source link.
            guard key.kind == row.source_kind, key.id.utf8.elementsEqual(row.source_id.utf8),
                Self.sameIdentity(key.item, row.item_id) else {
                throw FrozenInvoiceStorageFailure.malformedRecord
            }
            return try FrozenInvoiceLine(id: InvoiceLineID(validating: row.id), scope: scope, source: source,
                sourceRevision: Self.integer(row.source_revision), categoryId: BudgetCategoryID(validating: row.category_id),
                signedAmount: Money(minorUnits: Self.integer(row.signed_amount_minor_units), currency: code),
                description: row.description)
        }
        return try FrozenInvoiceContents(invoiceId: InvoiceID(validating: invoice_id),
            invoiceRevision: Self.integer(invoice_revision), scope: scope,
            purchaseId: TransactionID(validating: purchase_id), lines: decoded,
            total: Money(minorUnits: Self.integer(total_minor_units), currency: code))
    }

    private static func integer(_ value: String) throws -> Int64 {
        guard let number = Int64(value), String(number) == value else { throw FrozenInvoiceStorageFailure.malformedRecord }
        return number
    }

    private static func sameIdentity(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case (.some(let left), .some(let right)): left.utf8.elementsEqual(right.utf8)
        default: false
        }
    }

    private static func sourceKey(_ source: FrozenInvoiceLineSource) -> (kind: String, id: String, item: String?) {
        switch source {
        case .item(let item, let occurrence, _): ("item", occurrence.rawValue, item.rawValue)
        case .expense(let expense): ("expense", expense.rawValue, nil)
        case .feeInstallment(let installment): ("fee_installment", installment.rawValue, nil)
        }
    }
}
