import Foundation

/// Presentation of existing source/membership facts, not another Fee ledger.
public struct ProjectFeeRow: Identifiable, Equatable, Sendable {
    public let id: FeeInstallmentID
    public let title: String
    public let amount: Money
    public let categoryId: BudgetCategoryID
    public let categoryName: String?
    public let availability: InvoicingAvailability
    public let invoiceId: InvoiceID?
    public let invoiceName: String?

    public func matches(search: String, availability: InvoicingAvailability?) -> Bool {
        guard availability == nil || availability == self.availability else { return false }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || [title, categoryName, invoiceName].compactMap { $0 }
            .contains { $0.localizedStandardContains(query) }
    }

    public enum Failure: Error, Equatable { case scopeMismatch, conflictingMembership }

    /// Independent watches can overlap during collection. Frozen evidence takes
    /// precedence over the prior live version of that same Invoice, never vice versa.
    public static func compose(review: InvoiceCreationReview, live: [LiveInvoiceContents],
                               paid: [FrozenInvoiceContents]) throws -> [Self] {
        guard live.allSatisfy({ $0.selection.scope == review.scope }),
              paid.allSatisfy({ $0.scope == review.scope }) else { throw Failure.scopeMismatch }
        var rows: [FeeInstallmentID: Self] = [:]
        for invoice in paid {
            for line in invoice.lines {
                guard case .feeInstallment(let id) = line.source else { continue }
                guard rows[id] == nil else { throw Failure.conflictingMembership }
                rows[id] = Self(id: id, title: line.description, amount: line.signedAmount, categoryId: line.categoryId,
                    categoryName: nil, availability: .paid, invoiceId: invoice.invoiceId,
                    invoiceName: invoice.displayMetadata?.invoiceNumber)
            }
        }
        for invoice in live {
            for line in invoice.lines {
                guard case .feeInstallment(let id) = line.selection.source else { continue }
                if let previous = rows[id] {
                    guard previous.availability == .paid, previous.invoiceId == invoice.invoiceId else {
                        throw Failure.conflictingMembership
                    }
                    continue
                }
                rows[id] = Self(id: id, title: line.description, amount: line.selection.reviewedAmount, categoryId: line.categoryId,
                    categoryName: review.categoryNames[line.categoryId],
                    availability: invoice.status == .sent ? .sent : .created,
                    invoiceId: invoice.invoiceId, invoiceName: invoice.name.isEmpty ? nil : invoice.name)
            }
        }
        var available = Set<FeeInstallmentID>()
        for line in review.candidates {
            guard case .feeInstallment(let id) = line.selection.source else { continue }
            guard available.insert(id).inserted else { throw Failure.conflictingMembership }
            if rows[id] == nil {
                rows[id] = Self(id: id, title: line.description, amount: line.selection.reviewedAmount, categoryId: line.categoryId,
                    categoryName: review.categoryNames[line.categoryId], availability: .available,
                    invoiceId: nil, invoiceName: nil)
            }
        }
        return rows.values.sorted { $0.id.rawValue < $1.id.rawValue }
    }
}

/// Summary is computed before search/status filtering. Collection moves demand
/// into paid membership; it never adds the same Fee a second time.
public struct ProjectFeeGroup: Identifiable, Sendable {
    public let id: BudgetCategoryID
    public let name: String
    public let rows: [ProjectFeeRow]
    public let total: Money
    public let invoiced: Money
    public let received: Money
    public let remainingToInvoice: Money

    public init(category: FeeCreationCategory, rows: [ProjectFeeRow], currency: CurrencyCode,
                sortOrders: [FeeInstallmentID: Int64] = [:]) throws {
        guard rows.allSatisfy({ $0.categoryId == category.id }), Set(rows.map(\.id)).count == rows.count else {
            throw ProjectFeeRow.Failure.conflictingMembership
        }
        let currency = category.configuredTotal?.currency ?? rows.first?.amount.currency ?? currency
        var allocated = Money.zero(currency: currency), invoiced = allocated, received = allocated
        for row in rows {
            guard row.amount.minorUnits > 0 else { throw FeeInstallmentDraft.Failure.invalidDraft }
            allocated = try allocated.adding(row.amount)
            if row.availability != .available { invoiced = try invoiced.adding(row.amount) }
            if row.availability == .paid { received = try received.adding(row.amount) }
        }
        let total = category.configuredTotal ?? allocated
        guard total.minorUnits >= 0 else { throw FeeInstallmentDraft.Failure.invalidDraft }
        self.id = category.id; self.name = category.name
        self.rows = rows.sorted { lhs, rhs in
            let left = sortOrders[lhs.id] ?? 0, right = sortOrders[rhs.id] ?? 0
            if left != right { return left < right }
            let labels = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            return labels == .orderedSame ? lhs.id.rawValue < rhs.id.rawValue : labels == .orderedAscending
        }
        self.total = total; self.invoiced = invoiced; self.received = received
        // Clamping preserves the existing display only; no amounts are discarded.
        self.remainingToInvoice = try Money(minorUnits: max(total.minorUnits - invoiced.minorUnits, 0), currency: currency)
    }
}
