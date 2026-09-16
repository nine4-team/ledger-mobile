import Foundation

/// Live membership refers to billable facts, never a mutable Item location or
/// an inferred payment. Item identity alone cannot distinguish repeated sales.
public enum LiveInvoiceSource: Codable, Equatable, Hashable, Sendable {
    case itemOccurrence(BillableItemOccurrenceID)
    case expense(ExpenseID)
    case feeInstallment(FeeInstallmentID)
}

/// What the user reviewed before requesting membership. This is not a frozen
/// paid line: the writer must resolve these sources again under its source locks.
public struct LiveInvoiceSelection: Codable, Equatable, Sendable {
    public struct Line: Codable, Equatable, Sendable {
        public let source: LiveInvoiceSource
        public let expectedRevision: Int64
        public let reviewedAmount: Money

        public init(source: LiveInvoiceSource, expectedRevision: Int64, reviewedAmount: Money) throws {
            guard expectedRevision > 0 else { throw Failure.invalidRevision }
            self.source = source; self.expectedRevision = expectedRevision; self.reviewedAmount = reviewedAmount
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(source: c.decode(LiveInvoiceSource.self, forKey: .source),
                expectedRevision: c.decode(Int64.self, forKey: .expectedRevision),
                reviewedAmount: c.decode(Money.self, forKey: .reviewedAmount))
        }
        private enum CodingKeys: String, CodingKey { case source, expectedRevision, reviewedAmount }
    }

    public let scope: TransactionScope
    public let lines: [Line]
    public let reviewedTotal: Money

    public init(scope: TransactionScope, lines: [Line]) throws {
        guard scope.ownerKind == .project else { throw Failure.requiresProject }
        guard let first = lines.first else { throw Failure.emptySelection }
        guard Set(lines.map(\.source)).count == lines.count else { throw Failure.duplicateSource }
        // Signed totals are exact review evidence, not permission to settle
        // zero/negative Invoices or to allocate client credits.
        reviewedTotal = try lines.reduce(Money.zero(currency: first.reviewedAmount.currency)) {
            try $0.adding($1.reviewedAmount)
        }
        self.scope = scope; self.lines = lines
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(scope: c.decode(TransactionScope.self, forKey: .scope),
            lines: c.decode([Line].self, forKey: .lines))
    }
    public enum Failure: Error, Equatable, Sendable {
        case requiresProject, emptySelection, duplicateSource, invalidRevision
    }
    private enum CodingKeys: String, CodingKey { case scope, lines }
}
