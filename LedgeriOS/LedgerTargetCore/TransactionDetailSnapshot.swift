import Foundation

public protocol TransactionDetailReading: Sendable {
    func read(transactionId: TransactionID) async throws -> TransactionDetailSnapshot
}

public enum TransactionBrowserUpdate: Equatable, Sendable {
    case incomplete
    case partial([TransactionDetailSnapshot])
    case ready([TransactionDetailSnapshot])
    case unavailable
}

public protocol TransactionBrowsing: AnyObject, Sendable {
    func watchTransactions(scope: TransactionScope) -> AsyncThrowingStream<TransactionBrowserUpdate, Error>
}

/// Canonical display evidence. This does not assert receipt balance, complete
/// Item membership, permission to edit, or that a scope has finished downloading.
public struct TransactionDetailSnapshot: Codable, Equatable, Sendable {
    public enum Failure: Error, Equatable { case invalidEvidence, scopeMismatch }
    public enum Origin: String, Codable, Sendable {
        case importedClientPayment = "firebase_client_payment"
        case vendorPayment = "vendor_payment"
    }
    public struct Category: Equatable, Sendable {
        public let id: BudgetCategoryID
        public let name: String
        public let kind: BudgetCategoryKind
        public let revision: Int64
    }
    /// Current Project attribution for an attached physical Item, not its
    /// historical receipt category or a frozen Invoice category snapshot.
    public struct ItemCategory: Equatable, Sendable {
        public let itemId: ItemID
        public let placementId: EntityID
        public let categoryId: BudgetCategoryID?
    }

    public let accountId: AccountID
    public let principalId: PrincipalID
    public let transactionId: TransactionID
    public let classification: TransactionClassification
    public let origin: Origin
    public let amount: Money
    public let category: Category?
    public let source: String?
    /// A calendar date, not midnight converted through the device's time zone.
    public let transactionDate: String?
    public let createdAtMilliseconds: Int64?
    public let notes: String?
    public let paymentMethod: String?
    public let hasEmailReceipt: Bool?
    /// Original source metadata, never inferred or used in receipt arithmetic.
    public let legacySubtotal: Money?
    public let legacyTaxRatePct: String?
    /// Nil means this evidence was not supplied. Empty means no current linked
    /// Project Items. A nil category means missing or unauthorized attribution.
    public let currentItemCategories: [ItemCategory]?
    /// Same canonical receipt evidence as the audit reader; absent is unknown,
    /// not zero Items or a balanced receipt. Client payments have no vendor receipt.
    public let receipt: TransactionReceiptSnapshot?
    public let paymentContents: TransactionPaymentContents?
    public var linkedItemCount: Int? {
        switch origin {
        case .importedClientPayment: paymentContents?.itemIDs.count
        case .vendorPayment: receipt.map { $0.items.filter { $0.membership == .linked }.count }
        }
    }

    public func validate(scope: TransactionScope, principalId: PrincipalID, transactionId: TransactionID) throws {
        guard classification.scope == scope, self.principalId == principalId,
              self.transactionId == transactionId else { throw Failure.scopeMismatch }
    }

    public init(from decoder: Decoder) throws {
        let wire = try Wire(from: decoder)
        accountId = try AccountID(validating: wire.accountId)
        principalId = try PrincipalID(validating: wire.principalId)
        transactionId = try TransactionID(validating: wire.transactionId)
        guard wire.scopeKind == "project" || wire.scopeKind == "business_inventory",
              let type = LedgerTransactionType(rawValue: wire.type), type != .transfer,
              wire.role == "standalone" else { throw Failure.invalidEvidence }
        classification = try TransactionClassification(type: type, scope: TransactionScope(
            ownerKind: wire.scopeKind == "project" ? .project : .businessInventory,
            accountId: accountId, projectId: wire.projectId.map { try ProjectID(validating: $0) },
            clientId: wire.clientId.map { try ClientID(validating: $0) }), role: .standalone)
        origin = wire.origin
        let minorUnits = try Self.integer(wire.amountMinorUnits)
        guard minorUnits > 0 else { throw Failure.invalidEvidence }
        amount = Money(minorUnits: minorUnits, currency: try CurrencyCode(validating: wire.currency))
        if let value = wire.category {
            let revision = try Self.integer(value.revision)
            guard !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  revision > 0 else { throw Failure.invalidEvidence }
            category = Category(id: try BudgetCategoryID(validating: value.id), name: value.name,
                                kind: value.kind, revision: revision)
        } else { category = nil }
        switch origin {
        case .vendorPayment:
            guard category != nil else { throw Failure.invalidEvidence }
        case .importedClientPayment:
            guard category == nil, type == .purchase, classification.scope.ownerKind == .project else {
                throw Failure.invalidEvidence
            }
        }
        if let date = wire.transactionDate { try Self.validateDate(date) }
        transactionDate = wire.transactionDate
        createdAtMilliseconds = try wire.createdAtMilliseconds.map(Self.integer)
        source = wire.source
        notes = wire.notes
        paymentMethod = wire.paymentMethod
        hasEmailReceipt = wire.hasEmailReceipt
        let currency = amount.currency
        legacySubtotal = try wire.legacySubtotalMinorUnits.map {
            Money(minorUnits: try Self.integer($0), currency: currency)
        }
        if let rate = wire.legacyTaxRatePct { try Self.validateDecimal(rate) }
        legacyTaxRatePct = wire.legacyTaxRatePct
        let isProject = classification.scope.ownerKind == .project
        currentItemCategories = try wire.currentItemCategories.map { rows in
            let values = try rows.map {
                ItemCategory(itemId: try ItemID(validating: $0.itemId),
                    placementId: try EntityID(validating: $0.placementId),
                    categoryId: try $0.categoryId.map(BudgetCategoryID.init(validating:)))
            }
            guard Set(values.map(\.itemId)).count == values.count,
                  Set(values.map(\.placementId)).count == values.count,
                  isProject || values.isEmpty else {
                throw Failure.invalidEvidence
            }
            return values.sorted { $0.itemId.rawValue < $1.itemId.rawValue }
        }
        paymentContents = wire.paymentContents
        if let paymentContents {
            guard origin == .importedClientPayment else { throw Failure.invalidEvidence }
            try paymentContents.validate(scope: classification.scope, principalId: principalId,
                transactionId: transactionId, currency: amount.currency)
        }
        receipt = wire.receipt
        if let receipt {
            guard origin == .vendorPayment, receipt.accountId == accountId, receipt.principalId == principalId,
                  receipt.transactionId == transactionId, receipt.classification == classification,
                  receipt.finalAmount == amount, receipt.categoryId == category?.id,
                  receipt.categoryName == category?.name, receipt.categoryKind == category?.kind,
                  receipt.categoryRevision == category?.revision else { throw Failure.invalidEvidence }
        }
    }

    public func encode(to encoder: Encoder) throws {
        try Wire(accountId: accountId.rawValue, principalId: principalId.rawValue,
            transactionId: transactionId.rawValue, scopeKind: classification.scope.ownerKind == .project ? "project" : "business_inventory",
            type: classification.type.rawValue, role: "standalone", amountMinorUnits: String(amount.minorUnits),
            currency: amount.currency.rawValue, projectId: classification.scope.projectId?.rawValue,
            clientId: classification.scope.clientId?.rawValue, origin: origin,
            category: category.map { .init(id: $0.id.rawValue, name: $0.name, revision: String($0.revision), kind: $0.kind) },
            source: source, transactionDate: transactionDate, createdAtMilliseconds: createdAtMilliseconds.map(String.init),
            notes: notes, paymentMethod: paymentMethod, hasEmailReceipt: hasEmailReceipt,
            legacySubtotalMinorUnits: legacySubtotal.map { String($0.minorUnits) },
            legacyTaxRatePct: legacyTaxRatePct,
            currentItemCategories: currentItemCategories.map { rows in rows.map {
                .init(itemId: $0.itemId.rawValue, placementId: $0.placementId.rawValue,
                      categoryId: $0.categoryId?.rawValue)
            } }, receipt: receipt, paymentContents: paymentContents).encode(to: encoder)
    }

    private static func integer(_ raw: String) throws -> Int64 {
        guard let value = Int64(raw), String(value) == raw else { throw Failure.invalidEvidence }
        return value
    }

    private static func validateDecimal(_ raw: String) throws {
        let magnitude = raw.first == "-" ? raw.dropFirst() : raw[...]
        let parts = magnitude.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }),
              parts[0].count == 1 || parts[0].first != "0" else { throw Failure.invalidEvidence }
    }

    static func validateDate(_ raw: String) throws {
        guard raw.utf8.count == 10, raw.utf8.allSatisfy({ (48...57).contains($0) || $0 == 45 }) else {
            throw Failure.invalidEvidence
        }
        let parts = raw.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...9999).contains(year), (1...12).contains(month) else { throw Failure.invalidEvidence }
        let leap = year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...days[month - 1]).contains(day) else { throw Failure.invalidEvidence }
    }

    private struct Wire: Codable {
        let accountId, principalId, transactionId, scopeKind, type, role, amountMinorUnits, currency: String
        let projectId, clientId: String?
        let origin: Origin
        let category: CategoryWire?
        let source, transactionDate, createdAtMilliseconds, notes, paymentMethod: String?
        let hasEmailReceipt: Bool?
        let legacySubtotalMinorUnits, legacyTaxRatePct: String?
        let currentItemCategories: [ItemCategoryWire]?
        let receipt: TransactionReceiptSnapshot?
        let paymentContents: TransactionPaymentContents?
        struct ItemCategoryWire: Codable {
            let itemId, placementId: String
            let categoryId: String?
        }
        struct CategoryWire: Codable {
            let id, name, revision: String
            let kind: BudgetCategoryKind
        }
    }
}
