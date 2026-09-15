import Foundation

public protocol ProjectInvoicingChargeReading: Sendable {
    func readInvoicingCharges(accountId: AccountID, projectId: ProjectID) async throws -> ProjectInvoicingItems
    func watchInvoicingCharges(accountId: AccountID, projectId: ProjectID) -> AsyncThrowingStream<ProjectInvoicingItems?, Error>
}

public enum InvoicingAvailability: String, CaseIterable, Sendable {
    case available, created, sent, paid
}

/// Read-only display data attached to the canonical occurrence, not a new history.
public struct ProjectInvoicingItem: Equatable, Sendable, Identifiable {
    public var id: BillableItemOccurrenceID { occurrence.id }
    public let occurrence: BillableItemAccountingOccurrence
    public let amount: Money
    public let availability: InvoicingAvailability
    public let title: String
    public let invoiceDescription: String?
    public let categoryName: String?
    public let vendorName: String?
    public let invoiceName: String?

    public init(occurrence: BillableItemAccountingOccurrence, amount: Money,
                availability: InvoicingAvailability, title: String,
                invoiceDescription: String? = nil, categoryName: String? = nil,
                vendorName: String? = nil, invoiceName: String? = nil) throws {
        guard occurrence.polarity == .charge ? amount.minorUnits > 0 : amount.minorUnits < 0 else {
            throw ProjectInvoicingItemsFailure.invalidAmount
        }
        switch (occurrence.phase.kind, availability) {
        case (.availableToInvoice, .available):
            guard invoiceName == nil else { throw ProjectInvoicingItemsFailure.invalidMembership }
        case (.onLiveInvoice, .created), (.onLiveInvoice, .sent), (.frozenPaid, .paid): break
        default: throw ProjectInvoicingItemsFailure.invalidMembership
        }
        self.occurrence = occurrence; self.amount = amount; self.availability = availability
        self.title = title; self.invoiceDescription = invoiceDescription
        self.categoryName = categoryName; self.vendorName = vendorName; self.invoiceName = invoiceName
    }

    public func matches(search: String, availability: InvoicingAvailability? = nil) -> Bool {
        guard availability == nil || self.availability == availability else { return false }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || [title, invoiceDescription, categoryName, vendorName, invoiceName]
            .compactMap { $0 }.contains { $0.localizedStandardContains(query) }
    }
}

public enum ProjectInvoicingItemsFailure: Error, Equatable {
    case invalidAmount, invalidMembership, scopeMismatch, duplicateOccurrence
}

/// Membership/stream completeness is established by the provider before creating
/// this value. An unavailable read must not be converted to an empty snapshot.
public struct ProjectInvoicingItems: Equatable, Sendable {
    public let accountId: AccountID
    public let projectId: ProjectID
    public let rows: [ProjectInvoicingItem]

    public init(accountId: AccountID, projectId: ProjectID, rows: [ProjectInvoicingItem]) throws {
        guard rows.allSatisfy({ $0.occurrence.accountId == accountId && $0.occurrence.projectId == projectId }) else {
            throw ProjectInvoicingItemsFailure.scopeMismatch
        }
        guard Set(rows.map(\.id)).count == rows.count else { throw ProjectInvoicingItemsFailure.duplicateOccurrence }
        self.accountId = accountId; self.projectId = projectId; self.rows = rows
    }
}
