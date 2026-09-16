import Foundation

public enum ReturnUninvoicedItemsFailure: Error, Equatable, Sendable {
    case invalidSelection, invalidRevision, invalidEnvelope
}

/// Reverses an exact unbilled sale cycle, not a vendor return or cash refund.
/// The authoritative writer must also prove Inventory origin, current placement,
/// no active Invoice membership and no collected membership before changing facts.
public struct ReturnUninvoicedItemsPayload: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public let itemId: ItemID
        public let placementId: EntityID
        public let chargeId: BillableItemOccurrenceID
        public let expectedChargeRevision: Int64
        public let inventoryPlacementId: EntityID
        public let returnOccurrenceId: EntityID

        public init(itemId: ItemID, placementId: EntityID, chargeId: BillableItemOccurrenceID,
                    expectedChargeRevision: Int64, inventoryPlacementId: EntityID,
                    returnOccurrenceId: EntityID) throws {
            self.itemId = itemId; self.placementId = placementId; self.chargeId = chargeId
            self.expectedChargeRevision = expectedChargeRevision
            self.inventoryPlacementId = inventoryPlacementId; self.returnOccurrenceId = returnOccurrenceId
            try validate()
        }

        fileprivate func validate() throws {
            guard expectedChargeRevision > 0, expectedChargeRevision < Int64.max else {
                throw ReturnUninvoicedItemsFailure.invalidRevision
            }
            guard placementId != inventoryPlacementId else { throw ReturnUninvoicedItemsFailure.invalidSelection }
        }
    }

    public let projectId: ProjectID
    public let items: [Item]

    public init(projectId: ProjectID, items: [Item]) throws {
        self.projectId = projectId; self.items = items
        try validate()
    }

    fileprivate func validate() throws {
        guard (1...500).contains(items.count),
              Set(items.map(\.itemId)).count == items.count,
              Set(items.map(\.placementId)).count == items.count,
              Set(items.map(\.chargeId)).count == items.count,
              Set(items.map(\.inventoryPlacementId)).count == items.count,
              Set(items.map(\.returnOccurrenceId)).count == items.count,
              Set(items.map(\.placementId)).isDisjoint(with: Set(items.map(\.inventoryPlacementId))) else {
            throw ReturnUninvoicedItemsFailure.invalidSelection
        }
        for item in items { try item.validate() }
    }
}

public struct ReturnUninvoicedItemsCommand: Codable, Sendable {
    public let envelope: OperationEnvelope<ReturnUninvoicedItemsPayload>

    public init(operationId: OperationID, accountId: AccountID, actorPrincipalId: PrincipalID,
                capturedAt: Date, payload: ReturnUninvoicedItemsPayload) throws {
        let milliseconds = (capturedAt.timeIntervalSince1970 * 1000).rounded(.down)
        guard milliseconds.isFinite, milliseconds >= 0, milliseconds < 1_000_000_000_000_000 else {
            throw ReturnUninvoicedItemsFailure.invalidEnvelope
        }
        try self.init(envelope: .init(operationId: operationId,
            contractVersion: .init(validating: "return-uninvoiced-items-v1"), accountId: accountId,
            actorPrincipalId: actorPrincipalId,
            clientCreatedAt: Date(timeIntervalSince1970: milliseconds / 1000), payload: payload))
    }

    private init(envelope: OperationEnvelope<ReturnUninvoicedItemsPayload>) throws {
        let milliseconds = envelope.clientCreatedAt.timeIntervalSince1970 * 1000
        guard envelope.contractVersion.rawValue == "return-uninvoiced-items-v1", envelope.preconditions.isEmpty,
              milliseconds.isFinite, milliseconds >= 0, milliseconds < 1_000_000_000_000_000 else {
            throw ReturnUninvoicedItemsFailure.invalidEnvelope
        }
        try envelope.payload.validate()
        self.envelope = envelope
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(envelope: container.decode(OperationEnvelope<ReturnUninvoicedItemsPayload>.self, forKey: .envelope))
    }

    private enum CodingKeys: String, CodingKey { case envelope }
}
