import Foundation

public enum InvoiceLineIDTag: Sendable {}
public enum FeeInstallmentIDTag: Sendable {}
public enum InventoryEntryIDTag: Sendable {}
public typealias InvoiceLineID = DomainEntityIdentifier<InvoiceLineIDTag>
public typealias FeeInstallmentID = DomainEntityIdentifier<FeeInstallmentIDTag>
public typealias InventoryEntryID = DomainEntityIdentifier<InventoryEntryIDTag>

public enum FrozenItemPriceBasis: Codable, Equatable, Sendable {
    case projectPrice
    case purchaseCost(acquisitionId: TransactionID)
    case paidInvoiceLine(invoiceId: InvoiceID, lineId: InvoiceLineID)
    case inventoryEntry(entryId: InventoryEntryID)
}

/// Exact charge/credit basis captured with the occurrence, not a future lookup
/// of the Item's current price. Referenced history must be retained by storage.
public struct FrozenItemPriceSnapshot: Codable, Equatable, Sendable {
    public let basis: FrozenItemPriceBasis
    public let amount: Money
    public init(basis: FrozenItemPriceBasis, amount: Money) throws {
        guard amount.sign != .negative else { throw FrozenInvoiceContentsFailure.invalidPriceSnapshot }
        self.basis = basis; self.amount = amount
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(basis: c.decode(FrozenItemPriceBasis.self, forKey: .basis),
                      amount: c.decode(Money.self, forKey: .amount))
    }
    private enum CodingKeys: String, CodingKey { case basis, amount }
}

/// Supported source identities, not current Item placement or mutable labels.
/// Manual adjustments remain subject to their separate product decision.
public enum FrozenInvoiceLineSource: Codable, Equatable, Sendable {
    case item(itemId: ItemID, occurrenceId: BillableItemOccurrenceID, price: FrozenItemPriceSnapshot)
    case expense(expenseId: ExpenseID)
    case feeInstallment(installmentId: FeeInstallmentID)
}

public enum FrozenInvoiceContentsFailure: Error, Equatable, Sendable {
    case requiresProjectScope, invalidRevision, emptyContents, duplicateLine
    case duplicateItemOccurrence, duplicateExpense, duplicateFeeInstallment
    case scopeMismatch, totalMismatch, requiresPositiveTotal, invalidPriceSnapshot
}

/// Financial values are copied at collection, never looked up from live Items.
public struct FrozenInvoiceLine: Codable, Equatable, Sendable {
    public let id: InvoiceLineID
    public let scope: TransactionScope
    public let source: FrozenInvoiceLineSource
    /// Revision of the billable Item occurrence, Expense, or Fee installment—not
    /// the mutable physical Item or a containing receipt/fee plan.
    public let sourceRevision: Int64
    public let categoryId: BudgetCategoryID
    public let signedAmount: Money
    public let description: String

    public init(id: InvoiceLineID, scope: TransactionScope, source: FrozenInvoiceLineSource,
                sourceRevision: Int64, categoryId: BudgetCategoryID, signedAmount: Money,
                description: String) throws {
        guard scope.ownerKind == .project else { throw FrozenInvoiceContentsFailure.requiresProjectScope }
        guard sourceRevision > 0 else { throw FrozenInvoiceContentsFailure.invalidRevision }
        if case .item(_, _, let price) = source {
            let magnitude = try signedAmount.sign == .negative ? signedAmount.negated() : signedAmount
            guard price.amount == magnitude else { throw FrozenInvoiceContentsFailure.invalidPriceSnapshot }
        }
        self.id = id; self.scope = scope; self.source = source; self.sourceRevision = sourceRevision
        self.categoryId = categoryId; self.signedAmount = signedAmount; self.description = description
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: c.decode(InvoiceLineID.self, forKey: .id),
            scope: c.decode(TransactionScope.self, forKey: .scope),
            source: c.decode(FrozenInvoiceLineSource.self, forKey: .source),
            sourceRevision: c.decode(Int64.self, forKey: .sourceRevision),
            categoryId: c.decode(BudgetCategoryID.self, forKey: .categoryId),
            signedAmount: c.decode(Money.self, forKey: .signedAmount),
            description: c.decode(String.self, forKey: .description))
    }
    private enum CodingKeys: String, CodingKey {
        case id, scope, source, sourceRevision, categoryId, signedAmount, description
    }
}

/// Immutable contents of a positive collected Invoice. This value is NOT a
/// collection command or proof that payment occurred. The transactional writer
/// must verify actual payment, tenant access, source revisions, price provenance
/// and category eligibility before storing it. Zero/negative settlement and
/// manual-adjustment policy are not chosen here.
public struct FrozenInvoiceContents: Codable, Equatable, Sendable {
    public let invoiceId: InvoiceID
    public let invoiceRevision: Int64
    public let scope: TransactionScope
    public let purchaseId: TransactionID
    public let lines: [FrozenInvoiceLine]
    public let total: Money

    public init(invoiceId: InvoiceID, invoiceRevision: Int64, scope: TransactionScope,
                purchaseId: TransactionID, lines: [FrozenInvoiceLine], total: Money) throws {
        guard scope.ownerKind == .project else { throw FrozenInvoiceContentsFailure.requiresProjectScope }
        guard invoiceRevision > 0 else { throw FrozenInvoiceContentsFailure.invalidRevision }
        guard !lines.isEmpty else { throw FrozenInvoiceContentsFailure.emptyContents }
        guard total.sign == .positive else { throw FrozenInvoiceContentsFailure.requiresPositiveTotal }
        var lineIDs = Set<InvoiceLineID>()
        var occurrences = Set<BillableItemOccurrenceID>()
        var expenses = Set<ExpenseID>()
        var installments = Set<FeeInstallmentID>()
        var sum = Money.zero(currency: total.currency)
        for line in lines {
            guard line.scope == scope else { throw FrozenInvoiceContentsFailure.scopeMismatch }
            guard lineIDs.insert(line.id).inserted else { throw FrozenInvoiceContentsFailure.duplicateLine }
            switch line.source {
            case .item(_, let occurrenceId, _):
                guard occurrences.insert(occurrenceId).inserted else { throw FrozenInvoiceContentsFailure.duplicateItemOccurrence }
            case .expense(let expenseId):
                guard expenses.insert(expenseId).inserted else { throw FrozenInvoiceContentsFailure.duplicateExpense }
            case .feeInstallment(let installmentId):
                guard installments.insert(installmentId).inserted else { throw FrozenInvoiceContentsFailure.duplicateFeeInstallment }
            }
            sum = try sum.adding(line.signedAmount)
        }
        guard sum == total else { throw FrozenInvoiceContentsFailure.totalMismatch }
        // Compute category totals now too: overflow must not hide until display.
        _ = try Self.totals(lines, currency: total.currency)
        self.invoiceId = invoiceId; self.invoiceRevision = invoiceRevision; self.scope = scope
        self.purchaseId = purchaseId; self.lines = lines; self.total = total
    }

    /// The Purchase face value must not be counted again in addition to these
    /// frozen category allocations when moving budget value from unpaid to paid.
    public func categoryTotals() throws -> [BudgetCategoryID: Money] {
        try Self.totals(lines, currency: total.currency)
    }

    private static func totals(_ lines: [FrozenInvoiceLine], currency: CurrencyCode) throws -> [BudgetCategoryID: Money] {
        var result: [BudgetCategoryID: Money] = [:]
        for line in lines {
            result[line.categoryId] = try (result[line.categoryId] ?? .zero(currency: currency)).adding(line.signedAmount)
        }
        return result
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(invoiceId: c.decode(InvoiceID.self, forKey: .invoiceId),
            invoiceRevision: c.decode(Int64.self, forKey: .invoiceRevision),
            scope: c.decode(TransactionScope.self, forKey: .scope),
            purchaseId: c.decode(TransactionID.self, forKey: .purchaseId),
            lines: c.decode([FrozenInvoiceLine].self, forKey: .lines),
            total: c.decode(Money.self, forKey: .total))
    }
    private enum CodingKeys: String, CodingKey { case invoiceId, invoiceRevision, scope, purchaseId, lines, total }
}
