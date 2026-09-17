import Foundation

public protocol InventorySaleReviewReading: Sendable {
    func readInventorySaleReview(itemIds: [ItemID]) async throws -> InventorySaleReview
}

/// The reused sale form needs only these existing directory, review and outbox
/// operations; it must not import a concrete backend or write Item rows itself.
public protocol InventorySaleWorkflowServing: InventorySaleReviewReading {
    func watchInventorySaleReview(itemIds: [ItemID]) -> AsyncThrowingStream<InventorySaleReview?, Error>
    func watchProjects() -> AsyncThrowingStream<ProjectListSnapshot, Error>
    func sellInventoryItems(_ payload: InventorySalePayload, operationUUID: UUID,
                            capturedAt: Date) async throws -> OperationReceipt
    func watchInventorySale(_ operationId: OperationID) -> AsyncThrowingStream<OperationSnapshot?, Error>
}

/// A complete server read of the selected identities, not proof that their
/// acquisition is resolvable or that a later sale will still be authorized.
public struct InventorySaleReview: Decodable, Equatable, Sendable {
    public enum Failure: Error { case invalidEvidence, scopeMismatch, selectionMismatch }
    public let accountId: AccountID
    public let principalId: PrincipalID
    public let items: [Item]

    /// Call once on confirmation and retain the resulting payload for retries.
    /// Entered prices apply only where complete evidence requires price entry.
    public func makePayload(projectId: ProjectID, currency: CurrencyCode,
                            enteredPrices: [ItemID: Money],
                            makeUUID: () -> UUID = UUID.init) throws -> InventorySalePayload {
        try validate(accountId: accountId, principalId: principalId, itemIds: items.map(\.itemId))
        var usedEntries = Set<ItemID>()
        let selected = try items.map { item -> InventorySaleSelection in
            let amount: Money
            do { amount = try item.reviewedPrice(currency: currency) }
            catch InventorySalePrice.Failure.priceRequired {
                guard let entered = enteredPrices[item.itemId], entered.minorUnits > 0 else {
                    throw InventorySalePrice.Failure.priceRequired
                }
                guard entered.currency == currency else { throw InventorySalePrice.Failure.currencyMismatch }
                amount = entered
                usedEntries.insert(item.itemId)
            }
            guard let revision = Int64(item.priceRevision) else { throw Failure.invalidEvidence }
            return try .init(itemId: item.itemId, placementId: item.placementId,
                priceRevision: revision, reviewedPriceMinorUnits: amount.minorUnits,
                newPlacementId: .init(validating: "sale-placement-" + makeUUID().uuidString.lowercased()),
                occurrenceId: .init(validating: "sale-charge-" + makeUUID().uuidString.lowercased()))
        }
        guard Set(enteredPrices.keys) == usedEntries else { throw Failure.invalidEvidence }
        return try .init(projectId: projectId, currency: currency, items: selected)
    }

    public init(accountId: AccountID, principalId: PrincipalID, items: [Item]) throws {
        self.accountId = accountId; self.principalId = principalId; self.items = items
        try validate(accountId: accountId, principalId: principalId, itemIds: items.map(\.itemId))
    }

    public struct Item: Decodable, Equatable, Sendable {
        public let itemId: ItemID
        public let placementId: EntityID
        public let priceRevision: String
        public let projectPrice: InventorySalePrice.Evidence
        public let purchaseCost: InventorySalePrice.Evidence

        public init(itemId: ItemID, placementId: EntityID, priceRevision: Int64,
                    projectPrice: InventorySalePrice.Evidence, purchaseCost: InventorySalePrice.Evidence) {
            self.itemId = itemId; self.placementId = placementId; self.priceRevision = String(priceRevision)
            self.projectPrice = projectPrice; self.purchaseCost = purchaseCost
        }

        public func reviewedPrice(currency: CurrencyCode) throws -> Money {
            try InventorySalePrice.review(projectPrice: projectPrice, purchaseCost: purchaseCost, currency: currency)
        }
    }

    public func validate(accountId: AccountID, principalId: PrincipalID, itemIds: [ItemID]) throws {
        guard self.accountId == accountId, self.principalId == principalId else { throw Failure.scopeMismatch }
        guard (1...500).contains(itemIds.count), Set(itemIds).count == itemIds.count,
              items.count == itemIds.count, Set(items.map(\.itemId)) == Set(itemIds),
              Set(items.map(\.placementId)).count == items.count else { throw Failure.selectionMismatch }
        for item in items {
            guard let revision = Int64(item.priceRevision), revision >= 0,
                  String(revision) == item.priceRevision else { throw Failure.invalidEvidence }
            switch item.projectPrice {
            case .known(let money):
                guard revision > 0, money.minorUnits >= 0 else { throw Failure.invalidEvidence }
            case .confirmedAbsent:
                break // A cleared price retains its nonzero revision.
            case .unavailable: throw Failure.invalidEvidence
            }
        }
    }
}

extension InventorySalePrice.Evidence: Decodable {
    private enum Keys: String, CodingKey { case state, amountMinorUnits, currency }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        let state = try values.decode(String.self, forKey: .state)
        switch state {
        case "known":
            let text = try values.decode(String.self, forKey: .amountMinorUnits)
            guard let amount = Int64(text), String(amount) == text else { throw InventorySaleReview.Failure.invalidEvidence }
            self = .known(Money(minorUnits: amount, currency: try values.decode(CurrencyCode.self, forKey: .currency)))
        case "absent", "unavailable":
            guard !values.contains(.amountMinorUnits), !values.contains(.currency) else {
                throw InventorySaleReview.Failure.invalidEvidence
            }
            self = state == "absent" ? .confirmedAbsent : .unavailable
        default: throw InventorySaleReview.Failure.invalidEvidence
        }
    }
}
