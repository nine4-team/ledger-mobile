import Foundation

public extension ItemGrouping.Group where Row == TransactionReceiptSnapshot.Item {
    var thumbnailItem: TransactionReceiptSnapshot.Item {
        rows.first { ($0.imageCount ?? 0) > 0 } ?? representative
    }

    var spaceName: String? {
        let names = Set(rows.compactMap(\.currentSpaceName).filter { !$0.isEmpty })
        return names.count > 1 ? "Multiple spaces" : names.first
    }

    /// A missing receipt price is unknown, not zero. Never substitute current
    /// placement prices or silently overflow a historical receipt total.
    var receiptTotal: Money? {
        guard let first = rows.first?.amount else { return nil }
        var total = first
        for item in rows.dropFirst() {
            guard let amount = item.amount, let sum = try? total.adding(amount) else { return nil }
            total = sum
        }
        return total
    }
}

public protocol TransactionReceiptReading: Sendable {
    func read(transactionId: TransactionID) async throws -> TransactionReceiptSnapshot
}
public protocol TransactionReceiptWatching: Sendable {
    func watchTransactionReceipt(scope: TransactionScope, transactionId: TransactionID)
        -> AsyncThrowingStream<TransactionReceiptUpdate, Error>
}

public enum TransactionReceiptUpdate: Equatable, Sendable {
    case ready(TransactionReceiptSnapshot)
    case incomplete
    case unavailable
}

/// One complete authorized receipt read, not a collection of partially downloaded
/// rows. Providers must verify the requested Account, principal and Transaction.
/// Unknown prices remain unknown even when membership itself is complete.
public struct TransactionReceiptSnapshot: Codable, Equatable, Sendable {
    public enum Failure: Error, Equatable { case invalidEvidence, scopeMismatch }
    public enum AuditStatus: String, Sendable { case notApplicable, incompleteEvidence, balanced, mismatch }
    public enum Membership: String, Codable, Sendable { case linked, returned, sold }
    public struct Item: Equatable, Sendable {
        public let id: ItemID
        public let amount: Money?
        public let membership: Membership
        public let name: String?
        public let sku: String?
        public let source: String?
        public let currentSource: String?
        public let currentSpaceName: String?
        public let imageCount: Int64?
        public var metadata: TransactionItemMetadata {
            .init(id: id, name: name, sku: sku, source: source, currentSource: currentSource,
                currentSpaceName: currentSpaceName, imageCount: imageCount)
        }
    }

    public let accountId: AccountID
    public let principalId: PrincipalID
    public let transactionId: TransactionID
    public let classification: TransactionClassification
    public let finalAmount: Money
    public let categoryId: BudgetCategoryID
    public let categoryName: String
    public let categoryKind: BudgetCategoryKind
    public let categoryRevision: Int64
    public let items: [Item]
    public let lines: [NonItemReceiptLine]
    public let reconstruction: TransactionReceiptReconstruction?
    public let liveAdjustments: LiveItemAdjustmentOrder?
    public let requiresLiveAdjustments: Bool

    public var auditStatus: AuditStatus {
        guard categoryKind == .itemized else { return .notApplicable }
        if requiresLiveAdjustments {
            guard let liveAdjustments, liveAdjustments.differenceNumerator != nil else { return .incompleteEvidence }
            return liveAdjustments.isBalanced ? .balanced : .mismatch
        }
        guard let reconstruction else { return .incompleteEvidence }
        return reconstruction.variance.isZero ? .balanced : .mismatch
    }

    public func itemGroups(membership: Membership) -> [ItemGrouping.Group<Item>] {
        let members = items.filter { $0.membership == membership }
        return ItemGrouping.groups(in: members, selectedIDs: members.map(\.id), id: \.id,
            name: \.name, sku: \.sku, source: \.source)
    }

    public func validate(accountId: AccountID, principalId: PrincipalID, transactionId: TransactionID) throws {
        guard self.accountId == accountId, self.principalId == principalId,
              self.transactionId == transactionId else { throw Failure.scopeMismatch }
    }

    public init(from decoder: Decoder) throws {
        let wire = try Wire(from: decoder)
        accountId = try AccountID(validating: wire.accountId)
        principalId = try PrincipalID(validating: wire.principalId)
        transactionId = try TransactionID(validating: wire.transactionId)
        guard let type = LedgerTransactionType(rawValue: wire.type), type != .transfer,
              wire.scopeKind == "project" || wire.scopeKind == "business_inventory" else {
            throw Failure.invalidEvidence
        }
        classification = try TransactionClassification(type: type, scope: TransactionScope(
            ownerKind: wire.scopeKind == "project" ? .project : .businessInventory,
            accountId: accountId, projectId: wire.projectId.map { try ProjectID(validating: $0) },
            clientId: wire.clientId.map { try ClientID(validating: $0) }), role: .standalone)
        let currency = try CurrencyCode(validating: wire.currency)
        finalAmount = Money(minorUnits: try Self.integer(wire.amountMinorUnits, minimum: wire.requiresLiveAdjustments == true && type == .purchase ? 0 : 1), currency: currency)
        categoryId = try BudgetCategoryID(validating: wire.category.id)
        guard !wire.category.name.isEmpty else { throw Failure.invalidEvidence }
        categoryName = wire.category.name
        categoryKind = wire.category.kind
        categoryRevision = try Self.integer(wire.category.revision, minimum: 1)
        items = try wire.items.map { row in
            Item(id: try ItemID(validating: row.itemId),
                 amount: try row.amountMinorUnits.map { Money(minorUnits: try Self.integer($0), currency: currency) },
                 membership: row.membershipKind, name: row.name, sku: row.sku,
                 source: row.source, currentSource: row.currentSource,
                 currentSpaceName: row.currentSpaceName, imageCount: try row.imageCount.map { try Self.integer($0) })
        }
        lines = try wire.nonItemReceiptLines.map { row in
            try NonItemReceiptLine(id: NonItemReceiptLineID(validating: row.id),
                description: NonItemReceiptLineDescription(validating: row.description),
                magnitude: Money(minorUnits: Self.integer(row.amountMinorUnits, minimum: 1), currency: currency),
                effect: row.effect, quantity: row.quantity.map { try Self.integer($0, minimum: .min) })
        }
        guard Set(items.map(\.id)).count == items.count,
              Set(lines.map(\.id)).count == lines.count else { throw Failure.invalidEvidence }
        requiresLiveAdjustments = wire.requiresLiveAdjustments ?? false
        if let allocation = wire.liveAdjustments,
           allocation.totalMinorUnits == String(finalAmount.minorUnits),
           let signedSum = try? lines.reduce(Money.zero(currency: currency), { sum, line in
               try line.effect == .increase ? sum.adding(line.magnitude) : sum.subtracting(line.magnitude)
           }), allocation.adjustmentsMinorUnits == String(signedSum.minorUnits),
           Set(allocation.items.map(\.itemId)) == Set(items.map { $0.id.rawValue }),
           allocation.items.count == items.count {
            liveAdjustments = allocation
        } else { liveAdjustments = nil }
        if requiresLiveAdjustments {
            // Legacy acquisition amounts remain evidence, not inputs to the
            // approved live audit or a competing overflow/validity gate.
            reconstruction = nil
            return
        }
        let known = Dictionary(uniqueKeysWithValues: items.compactMap { item in item.amount.map { (item.id, $0) } })
        if known.count != items.count {
            // Check known amounts and line sums, but do not reconstruct a total
            // or variance from a partial subtotal (including overflow guesses).
            var subtotal = Money.zero(currency: currency)
            for amount in known.values { subtotal = try subtotal.adding(amount) }
            var increase = Money.zero(currency: currency), decrease = Money.zero(currency: currency)
            for line in lines {
                if line.effect == .increase { increase = try increase.adding(line.magnitude) }
                else { decrease = try decrease.adding(line.magnitude) }
            }
            _ = try increase.subtracting(decrease)
            reconstruction = nil
            return
        }
        reconstruction = try TransactionReceiptReconstruction(accountId: accountId, transactionId: transactionId,
            classification: classification, recordedFinalAmount: finalAmount,
            linkedItemIds: items.filter { $0.amount != nil && $0.membership == .linked }.map(\.id),
            historicalItemIds: items.filter { $0.amount != nil && $0.membership != .linked }.map(\.id),
            itemAmounts: known, isItemMembershipComplete: true, lines: lines)
    }

    public func encode(to encoder: Encoder) throws {
        try Wire(accountId: accountId.rawValue, principalId: principalId.rawValue,
            transactionId: transactionId.rawValue, scopeKind: classification.scope.ownerKind == .project ? "project" : "business_inventory",
            type: classification.type.rawValue, amountMinorUnits: String(finalAmount.minorUnits), currency: finalAmount.currency.rawValue,
            projectId: classification.scope.projectId?.rawValue, clientId: classification.scope.clientId?.rawValue,
            category: .init(id: categoryId.rawValue, name: categoryName, revision: String(categoryRevision), kind: categoryKind),
            items: items.map { .init(itemId: $0.id.rawValue, name: $0.name, sku: $0.sku,
                source: $0.source, currentSource: $0.currentSource, currentSpaceName: $0.currentSpaceName,
                imageCount: $0.imageCount.map(String.init),
                amountMinorUnits: $0.amount.map { String($0.minorUnits) }, membershipKind: $0.membership) },
            nonItemReceiptLines: lines.map { .init(id: $0.id.rawValue, description: $0.description.rawValue,
                amountMinorUnits: String($0.magnitude.minorUnits), effect: $0.effect, quantity: $0.quantity.map(String.init)) },
            liveAdjustments: liveAdjustments, requiresLiveAdjustments: requiresLiveAdjustments)
            .encode(to: encoder)
    }

    private static func integer(_ raw: String, minimum: Int64 = 0) throws -> Int64 {
        guard let value = Int64(raw), value >= minimum,
              raw == String(value) || (minimum == .min && raw == "-0") else { throw Failure.invalidEvidence }
        return value
    }

    private struct Wire: Codable {
        let accountId, principalId, transactionId, scopeKind, type, amountMinorUnits, currency: String
        let projectId, clientId: String?
        let category: Category
        let items: [ReceiptItem]
        let nonItemReceiptLines: [Line]
        let liveAdjustments: LiveItemAdjustmentOrder?
        let requiresLiveAdjustments: Bool?
        struct Category: Codable {
            let id, name, revision: String
            let kind: BudgetCategoryKind
        }
        struct ReceiptItem: Codable {
            let itemId: String
            let name, sku, source, currentSource, currentSpaceName, imageCount: String?
            let amountMinorUnits: String?
            let membershipKind: Membership
        }
        struct Line: Codable {
            let id, description, amountMinorUnits: String
            let effect: NonItemReceiptLineEffect
            let quantity: String?
        }
    }
}
