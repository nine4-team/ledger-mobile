import Foundation

/// Current source facts for an uncollected Invoice; never a paid snapshot.
public struct LiveInvoiceContents: Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case created, sent }
    public struct Line: Equatable, Sendable {
        public let selection: LiveInvoiceSelection.Line
        public let categoryId: BudgetCategoryID
        public let description: String

        public init(selection: LiveInvoiceSelection.Line, categoryId: BudgetCategoryID, description: String) {
            self.selection = selection; self.categoryId = categoryId; self.description = description
        }
    }
    public let invoiceId: InvoiceID
    public let revision: Int64
    public let status: Status
    public let name: String
    public let notes: String
    public let selection: LiveInvoiceSelection
    public let lines: [Line]
    public var total: Money { selection.reviewedTotal }

    public init(invoiceId: InvoiceID, revision: Int64, status: Status, name: String, notes: String,
                scope: TransactionScope, lines: [Line], reportedTotal: Money) throws {
        guard revision > 0 else { throw Failure.invalidRevision }
        let selection = try LiveInvoiceSelection(scope: scope, lines: lines.map(\.selection))
        guard selection.reviewedTotal == reportedTotal else { throw Failure.totalMismatch }
        self.invoiceId = invoiceId; self.revision = revision; self.status = status
        self.name = name; self.notes = notes; self.selection = selection; self.lines = lines
    }
    public enum Failure: Error, Equatable, Sendable { case invalidRevision, totalMismatch }
}
