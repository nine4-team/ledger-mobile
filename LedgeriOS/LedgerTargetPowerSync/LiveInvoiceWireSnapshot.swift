import Foundation
import LedgerTargetCore

/// Decimal strings preserve exact SQL Int64 values across JSON consumers.
public struct LiveInvoiceWireSnapshot: Decodable, Sendable {
    private struct Line: Decodable, Sendable {
        let kind: String, sourceId: String, sourceRevision: String, amountMinorUnits: String
        let currency: String, categoryId: String, description: String
    }
    private let accountId: String, projectId: String, clientId: String, invoiceId: String
    private let revision: String, status: LiveInvoiceContents.Status, name: String, notes: String
    private let currency: String, totalMinorUnits: String
    private let lines: [Line]

    public func contents(accountId expectedAccount: AccountID, projectId expectedProject: ProjectID,
                         invoiceId expectedInvoice: InvoiceID) throws -> LiveInvoiceContents {
        guard accountId == expectedAccount.rawValue, projectId == expectedProject.rawValue,
              invoiceId == expectedInvoice.rawValue else { throw Failure.scopeMismatch }
        let scope = try TransactionScope.project(accountId: expectedAccount, projectId: expectedProject,
            clientId: .init(validating: clientId))
        return try LiveInvoiceContents(invoiceId: expectedInvoice, revision: integer(revision), status: status,
            name: name, notes: notes, scope: scope, lines: lines.map { row in
                let source: LiveInvoiceSource
                switch row.kind {
                case "item": source = .itemOccurrence(try .init(validating: row.sourceId))
                case "expense": source = .expense(try .init(validating: row.sourceId))
                case "fee_installment": source = .feeInstallment(try .init(validating: row.sourceId))
                default: throw Failure.invalidSource
                }
                return try .init(selection: .init(source: source, expectedRevision: integer(row.sourceRevision),
                    reviewedAmount: .init(minorUnits: integer(row.amountMinorUnits), currency: .init(validating: row.currency))),
                    categoryId: .init(validating: row.categoryId), description: row.description)
            }, reportedTotal: .init(minorUnits: integer(totalMinorUnits), currency: .init(validating: currency)))
    }
    private func integer(_ text: String) throws -> Int64 {
        guard let value = Int64(text), String(value) == text else { throw Failure.invalidInteger }
        return value
    }
    public enum Failure: Error, Equatable, Sendable { case scopeMismatch, invalidSource, invalidInteger }
}
