import Foundation

/// Presentation of existing source/membership facts, not another Fee ledger.
public struct ProjectFeeRow: Identifiable, Equatable, Sendable {
    public let id: FeeInstallmentID
    public let title: String
    public let amount: Money
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
                rows[id] = Self(id: id, title: line.description, amount: line.signedAmount,
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
                rows[id] = Self(id: id, title: line.description, amount: line.selection.reviewedAmount,
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
                rows[id] = Self(id: id, title: line.description, amount: line.selection.reviewedAmount,
                    categoryName: review.categoryNames[line.categoryId], availability: .available,
                    invoiceId: nil, invoiceName: nil)
            }
        }
        return rows.values.sorted { $0.id.rawValue < $1.id.rawValue }
    }
}
