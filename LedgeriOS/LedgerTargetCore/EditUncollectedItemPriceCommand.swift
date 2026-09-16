import Foundation

/// Changes current price and the exact open charge, never an acquisition or
/// frozen Invoice. The server rechecks placement, revisions and the cost floor.
public struct EditUncollectedItemPriceCommand: Codable, Sendable {
    public struct Payload: Codable, Equatable, Sendable {
        public let projectId: ProjectID
        public let itemId: ItemID
        public let placementId: EntityID
        public let occurrenceId: BillableItemOccurrenceID
        public let expectedPriceRevision: Int64
        public let expectedChargeRevision: Int64
        public let requestedPrice: Money
        public let reviewedPrice: Money

        public init(projectId: ProjectID, itemId: ItemID, placementId: EntityID,
                    occurrenceId: BillableItemOccurrenceID, expectedPriceRevision: Int64,
                    expectedChargeRevision: Int64, requestedPrice: Money, reviewedPrice: Money) throws {
            self.projectId = projectId
            self.itemId = itemId
            self.placementId = placementId
            self.occurrenceId = occurrenceId
            self.expectedPriceRevision = expectedPriceRevision
            self.expectedChargeRevision = expectedChargeRevision
            self.requestedPrice = requestedPrice
            self.reviewedPrice = reviewedPrice
            try validate()
        }

        fileprivate func validate() throws {
            guard expectedPriceRevision >= 0, expectedPriceRevision < Int64.max,
                  expectedChargeRevision > 0, expectedChargeRevision < Int64.max else {
                throw Failure.invalidRevision
            }
            guard requestedPrice.currency == reviewedPrice.currency,
                  requestedPrice.minorUnits >= 0, reviewedPrice.minorUnits > 0,
                  reviewedPrice.minorUnits >= requestedPrice.minorUnits else {
                throw Failure.invalidPrice
            }
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
            contractVersion: .init(validating: "item-uncollected-price-edit-v1"), accountId: accountId,
            actorPrincipalId: actorPrincipalId,
            clientCreatedAt: Date(timeIntervalSince1970: milliseconds / 1000), payload: payload))
    }

    private init(envelope: OperationEnvelope<Payload>) throws {
        let milliseconds = envelope.clientCreatedAt.timeIntervalSince1970 * 1000
        guard envelope.contractVersion.rawValue == "item-uncollected-price-edit-v1",
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
