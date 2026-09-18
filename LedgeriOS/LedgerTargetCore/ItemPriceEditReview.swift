import Foundation

public protocol ItemPriceEditing: Sendable {
    func watchItemPriceReview(project: ProjectID?, item: ItemID) -> AsyncThrowingStream<ItemPriceEditReview?, Error>
    func editItemPrice(_ payload: EditUncollectedItemPriceCommand.Payload,
                       operationUUID: UUID, capturedAt: Date) async throws -> OperationReceipt
    func watchItemPriceEdit(_ operationId: OperationID) -> AsyncThrowingStream<OperationSnapshot?, Error>
}

/// Downloaded edit context, separate from the user's proposed price.
public struct ItemPriceEditReview: Equatable, Sendable {
    public let projectId: ProjectID?
    public let itemId: ItemID
    public let placementId: EntityID
    public let occurrenceId: BillableItemOccurrenceID?
    public let priceRevision: Int64
    public let chargeRevision: Int64?
    public let currentPrice: Money?
    public let priceCurrency: CurrencyCode?
    public let purchaseCost: InventorySalePrice.Evidence
    public let livePricing: LiveItemPricingContext?

    public init(inventoryItemId: ItemID, placementId: EntityID, priceRevision: Int64,
                currentPrice: Money?, purchaseCost: InventorySalePrice.Evidence,
                priceCurrency: CurrencyCode? = nil, livePricing: LiveItemPricingContext? = nil) throws {
        guard priceRevision >= 0, priceRevision < Int64.max,
              currentPrice.map({ $0.minorUnits >= 0 }) ?? true,
              priceRevision != 0 || currentPrice == nil, purchaseCost != .unavailable || livePricing != nil else {
            throw EditUncollectedItemPriceCommand.Failure.invalidRevision
        }
        projectId = nil; itemId = inventoryItemId; self.placementId = placementId
        occurrenceId = nil; chargeRevision = nil; self.priceRevision = priceRevision
        self.currentPrice = currentPrice; self.purchaseCost = purchaseCost
        self.livePricing = livePricing
        self.priceCurrency = priceCurrency ?? currentPrice?.currency
        if let currentPrice, let priceCurrency, currentPrice.currency != priceCurrency {
            throw InventorySalePrice.Failure.currencyMismatch
        }
    }

    public init(projectId: ProjectID, itemId: ItemID, placementId: EntityID,
                occurrenceId: BillableItemOccurrenceID, priceRevision: Int64, chargeRevision: Int64,
                currentPrice: Money?, purchaseCost: InventorySalePrice.Evidence,
                priceCurrency: CurrencyCode? = nil, livePricing: LiveItemPricingContext? = nil) throws {
        guard priceRevision >= 0, priceRevision < Int64.max, chargeRevision > 0, chargeRevision < Int64.max,
              currentPrice.map({ $0.minorUnits >= 0 }) ?? true,
              (priceRevision != 0 || currentPrice == nil), purchaseCost != .unavailable || livePricing != nil else {
            throw EditUncollectedItemPriceCommand.Failure.invalidRevision
        }
        self.projectId = projectId; self.itemId = itemId; self.placementId = placementId
        self.occurrenceId = occurrenceId; self.priceRevision = priceRevision; self.chargeRevision = chargeRevision
        self.currentPrice = currentPrice; self.purchaseCost = purchaseCost
        self.livePricing = livePricing
        self.priceCurrency = priceCurrency ?? currentPrice?.currency
        if let currentPrice, let priceCurrency, currentPrice.currency != priceCurrency {
            throw InventorySalePrice.Failure.currencyMismatch
        }
    }

    public func payload(requested: Money) throws -> EditUncollectedItemPriceCommand.Payload {
        guard priceCurrency == nil || priceCurrency == requested.currency else {
            throw InventorySalePrice.Failure.currencyMismatch
        }
        guard let projectId, let occurrenceId, let chargeRevision else {
            return try inventoryPayload(requested: requested, clear: false)
        }
        return try .init(projectId: projectId, itemId: itemId, placementId: placementId,
            occurrenceId: occurrenceId, expectedPriceRevision: priceRevision, expectedChargeRevision: chargeRevision,
            requestedPrice: requested, reviewedPrice: livePricing != nil ? requested : InventorySalePrice.review(projectPrice: .known(requested),
                purchaseCost: purchaseCost, currency: requested.currency),
            adjustmentTransactionId: livePricing?.transactionId, expectedAdjustmentRevision: livePricing?.revision)
    }

    public func clearingInventoryPrice(currency: CurrencyCode) throws -> EditUncollectedItemPriceCommand.Payload {
        guard projectId == nil, priceCurrency == nil || priceCurrency == currency else {
            throw EditUncollectedItemPriceCommand.Failure.invalidPrice
        }
        return try inventoryPayload(requested: .init(minorUnits: 0, currency: currency), clear: true)
    }

    private func inventoryPayload(requested: Money, clear: Bool) throws -> EditUncollectedItemPriceCommand.Payload {
        if let livePricing {
            return try .init(inventoryItemId: itemId, placementId: placementId, expectedPriceRevision: priceRevision,
                requestedPrice: requested, reviewedPrice: requested, clearPrice: clear,
                adjustmentTransactionId: livePricing.transactionId, expectedAdjustmentRevision: livePricing.revision)
        }
        let normalized = try InventorySalePrice.reviewCurrentPrice(
            projectPrice: clear ? .confirmedAbsent : .known(requested), purchaseCost: purchaseCost,
            currency: requested.currency) ?? Money(minorUnits: 0, currency: requested.currency)
        return try .init(inventoryItemId: itemId, placementId: placementId, expectedPriceRevision: priceRevision,
                         requestedPrice: requested, reviewedPrice: normalized, clearPrice: clear)
    }
}
