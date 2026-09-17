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
    /// Charge and credit facts live in different authoritative tables. Their
    /// raw IDs may coincide; list identity must retain the source kind.
    public var id: String { "\(occurrence.polarity.rawValue):\(occurrence.id.rawValue)" }
    public let occurrence: BillableItemAccountingOccurrence
    public let amount: Money
    public let availability: InvoicingAvailability
    public let title: String
    public let invoiceDescription: String?
    public let categoryName: String?
    public let categoryId: BudgetCategoryID?
    public let vendorName: String?
    public let invoiceName: String?

    public init(occurrence: BillableItemAccountingOccurrence, amount: Money,
                availability: InvoicingAvailability, title: String,
                invoiceDescription: String? = nil, categoryName: String? = nil,
                vendorName: String? = nil, invoiceName: String? = nil,
                categoryId: BudgetCategoryID? = nil) throws {
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
        self.categoryId = categoryId
    }

    public func matches(search: String, availability: InvoicingAvailability? = nil) -> Bool {
        guard availability == nil || self.availability == availability else { return false }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || [title, invoiceDescription, categoryName, vendorName, invoiceName]
            .compactMap { $0 }.contains { $0.localizedStandardContains(query) }
    }
}

public enum ProjectInvoicingItemsFailure: Error, Equatable {
    case invalidAmount, invalidMembership, scopeMismatch, duplicateOccurrence, missingBudgetCategory
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

    /// Item-only contributions, not a complete Project budget. The caller must
    /// establish download completeness and compose direct payments/Expenses/Fees.
    /// Collected Item lines must not also be added by that caller.
    public func budgetContributions(categories: [BudgetCategoryDefinitionSnapshot],
                                    currency: CurrencyCode) throws -> [ProjectBudgetCategorySegment] {
        guard categories.allSatisfy({ $0.accountId == accountId }) else {
            throw ProjectBudgetSegmentFailure.accountScopeMismatch
        }
        guard Set(categories.map(\.id)).count == categories.count else {
            throw ProjectBudgetSegmentFailure.duplicateCategoryIdentity
        }
        let known = Set(categories.map(\.id))
        var paid: [BudgetCategoryID: Money] = [:], unpaid: [BudgetCategoryID: Money] = [:]
        for row in rows {
            guard let category = row.categoryId, known.contains(category) else {
                throw ProjectInvoicingItemsFailure.missingBudgetCategory
            }
            guard row.amount.currency == currency else { throw ProjectBudgetSegmentFailure.currencyMismatch }
            if row.availability == .paid {
                paid[category] = try (paid[category] ?? .zero(currency: currency)).adding(row.amount)
            } else {
                unpaid[category] = try (unpaid[category] ?? .zero(currency: currency)).adding(row.amount)
            }
        }
        return try categories.map { category in
            try .init(category: category, clientPaid: paid[category.id] ?? .zero(currency: currency),
                invoicingUnpaid: unpaid[category.id] ?? .zero(currency: currency))
        }
    }
}
