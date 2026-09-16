import Foundation

public protocol ItemPriceEditing: Sendable {
    func watchItemPriceReview(project: ProjectID, item: ItemID) -> AsyncThrowingStream<ItemPriceEditReview?, Error>
    func editItemPrice(_ payload: EditUncollectedItemPriceCommand.Payload,
                       operationUUID: UUID, capturedAt: Date) async throws -> OperationReceipt
    func watchItemPriceEdit(_ operationId: OperationID) -> AsyncThrowingStream<OperationSnapshot?, Error>
}

/// Downloaded edit context, separate from the user's proposed price.
public struct ItemPriceEditReview: Equatable, Sendable {
    public let projectId: ProjectID
    public let itemId: ItemID
    public let placementId: EntityID
    public let occurrenceId: BillableItemOccurrenceID
    public let priceRevision: Int64
    public let chargeRevision: Int64
    public let currentPrice: Money?
    public let purchaseCost: InventorySalePrice.Evidence

    public init(projectId: ProjectID, itemId: ItemID, placementId: EntityID,
                occurrenceId: BillableItemOccurrenceID, priceRevision: Int64, chargeRevision: Int64,
                currentPrice: Money?, purchaseCost: InventorySalePrice.Evidence) throws {
        guard priceRevision >= 0, priceRevision < Int64.max, chargeRevision > 0, chargeRevision < Int64.max,
              currentPrice.map({ $0.minorUnits >= 0 }) ?? true,
              (currentPrice == nil) == (priceRevision == 0), purchaseCost != .unavailable else {
            throw EditUncollectedItemPriceCommand.Failure.invalidRevision
        }
        self.projectId = projectId; self.itemId = itemId; self.placementId = placementId
        self.occurrenceId = occurrenceId; self.priceRevision = priceRevision; self.chargeRevision = chargeRevision
        self.currentPrice = currentPrice; self.purchaseCost = purchaseCost
    }

    public func payload(requested: Money) throws -> EditUncollectedItemPriceCommand.Payload {
        guard currentPrice == nil || currentPrice?.currency == requested.currency else {
            throw InventorySalePrice.Failure.currencyMismatch
        }
        return try .init(projectId: projectId, itemId: itemId, placementId: placementId,
            occurrenceId: occurrenceId, expectedPriceRevision: priceRevision, expectedChargeRevision: chargeRevision,
            requestedPrice: requested, reviewedPrice: InventorySalePrice.review(projectPrice: .known(requested),
                purchaseCost: purchaseCost, currency: requested.currency))
    }
}
