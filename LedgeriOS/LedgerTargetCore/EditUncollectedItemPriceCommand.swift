import Foundation

/// Changes current price and the exact open charge, never an acquisition or
/// frozen Invoice. The server rechecks placement, revisions and the cost floor.
public struct EditUncollectedItemPriceCommand: Codable, Sendable {
    public struct Payload: Codable, Equatable, Sendable {
        public let projectId: ProjectID?
        public let itemId: ItemID
        public let placementId: EntityID
        public let occurrenceId: BillableItemOccurrenceID?
        public let expectedPriceRevision: Int64
        public let expectedChargeRevision: Int64?
        public let requestedPrice: Money
        public let reviewedPrice: Money
        /// Present only for Inventory v2. Zero remains an amount; clear is an
        /// explicit intent, normalized against the known purchase-cost floor.
        public let clearPrice: Bool?
        public let adjustmentTransactionId: TransactionID?
        public let expectedAdjustmentRevision: Int64?

        public init(inventoryItemId: ItemID, placementId: EntityID,
                    expectedPriceRevision: Int64, requestedPrice: Money,
                    reviewedPrice: Money, clearPrice: Bool,
                    adjustmentTransactionId: TransactionID? = nil, expectedAdjustmentRevision: Int64? = nil) throws {
            projectId = nil; itemId = inventoryItemId; self.placementId = placementId
            occurrenceId = nil; expectedChargeRevision = nil
            self.expectedPriceRevision = expectedPriceRevision
            self.requestedPrice = requestedPrice; self.reviewedPrice = reviewedPrice
            self.clearPrice = clearPrice
            self.adjustmentTransactionId = adjustmentTransactionId
            self.expectedAdjustmentRevision = expectedAdjustmentRevision
            try validate()
        }

        public init(projectId: ProjectID, itemId: ItemID, placementId: EntityID,
                    occurrenceId: BillableItemOccurrenceID, expectedPriceRevision: Int64,
                    expectedChargeRevision: Int64, requestedPrice: Money, reviewedPrice: Money,
                    adjustmentTransactionId: TransactionID? = nil, expectedAdjustmentRevision: Int64? = nil) throws {
            self.projectId = projectId
            self.itemId = itemId
            self.placementId = placementId
            self.occurrenceId = occurrenceId
            self.expectedPriceRevision = expectedPriceRevision
            self.expectedChargeRevision = expectedChargeRevision
            self.requestedPrice = requestedPrice
            self.reviewedPrice = reviewedPrice
            self.clearPrice = nil
            self.adjustmentTransactionId = adjustmentTransactionId
            self.expectedAdjustmentRevision = expectedAdjustmentRevision
            try validate()
        }

        fileprivate func validate() throws {
            guard (adjustmentTransactionId == nil) == (expectedAdjustmentRevision == nil),
                  expectedAdjustmentRevision.map({ $0 > 0 && $0 < .max }) ?? true else { throw Failure.invalidRevision }
            guard expectedPriceRevision >= 0, expectedPriceRevision < Int64.max else {
                throw Failure.invalidRevision
            }
            if projectId != nil {
                guard occurrenceId != nil, clearPrice == nil,
                      let revision = expectedChargeRevision, revision > 0, revision < Int64.max else {
                    throw Failure.invalidRevision
                }
            } else {
                guard occurrenceId == nil, expectedChargeRevision == nil, clearPrice != nil else {
                    throw Failure.invalidRevision
                }
                guard clearPrice != true || requestedPrice.minorUnits == 0 else { throw Failure.invalidPrice }
            }
            guard requestedPrice.currency == reviewedPrice.currency,
                  requestedPrice.minorUnits >= 0, reviewedPrice.minorUnits >= 0,
                  projectId == nil || adjustmentTransactionId != nil || reviewedPrice.minorUnits > 0,
                  adjustmentTransactionId == nil || reviewedPrice == requestedPrice,
                  reviewedPrice.minorUnits >= requestedPrice.minorUnits else {
                throw Failure.invalidPrice
            }
        }

        fileprivate var contractVersion: String {
            adjustmentTransactionId != nil ? "item-live-adjustment-price-edit-v3"
                : (projectId == nil ? "item-inventory-price-edit-v2" : "item-uncollected-price-edit-v1")
        }
    }

    public let envelope: OperationEnvelope<Payload>

    public init(operationId: OperationID, accountId: AccountID, actorPrincipalId: PrincipalID,
                capturedAt: Date, payload: Payload) throws {
        let milliseconds = (capturedAt.timeIntervalSince1970 * 1000).rounded(.down)
        guard milliseconds.isFinite, milliseconds >= 0, milliseconds < 1_000_000_000_000_000 else {
            throw Failure.invalidEnvelope
        }
        try self.init(envelope: .init(operationId: operationId,
            contractVersion: .init(validating: payload.contractVersion), accountId: accountId,
            actorPrincipalId: actorPrincipalId,
            clientCreatedAt: Date(timeIntervalSince1970: milliseconds / 1000), payload: payload))
    }

    private init(envelope: OperationEnvelope<Payload>) throws {
        let milliseconds = envelope.clientCreatedAt.timeIntervalSince1970 * 1000
        guard envelope.contractVersion.rawValue == envelope.payload.contractVersion,
              envelope.preconditions.isEmpty, milliseconds.isFinite,
              milliseconds >= 0, milliseconds < 1_000_000_000_000_000 else {
            throw Failure.invalidEnvelope
        }
        try envelope.payload.validate()
        self.envelope = envelope
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(envelope: c.decode(OperationEnvelope<Payload>.self, forKey: .envelope))
    }

    public enum Failure: Error, Equatable, Sendable { case invalidRevision, invalidPrice, invalidEnvelope }
    private enum CodingKeys: String, CodingKey { case envelope }
}
