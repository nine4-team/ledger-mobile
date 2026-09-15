import Foundation

public enum InventorySaleCommandFailure: Error, Equatable, Sendable {
    case invalidSelection, invalidPrice, invalidRevision, invalidEnvelope, saleAlreadyAccepted
}

/// IDs are allocated once when accepting the review, then retained for replay.
public struct InventorySaleSelection: Codable, Equatable, Sendable {
    public let itemId: ItemID
    public let placementId: EntityID
    public let priceRevision: String
    public let reviewedPriceMinorUnits: String
    public let newPlacementId: EntityID
    public let occurrenceId: BillableItemOccurrenceID

    public init(itemId: ItemID, placementId: EntityID, priceRevision: Int64,
                reviewedPriceMinorUnits: Int64, newPlacementId: EntityID,
                occurrenceId: BillableItemOccurrenceID) throws {
        guard priceRevision >= 0 else { throw InventorySaleCommandFailure.invalidRevision }
        guard reviewedPriceMinorUnits > 0 else { throw InventorySaleCommandFailure.invalidPrice }
        self.itemId = itemId
        self.placementId = placementId
        self.priceRevision = String(priceRevision)
        self.reviewedPriceMinorUnits = String(reviewedPriceMinorUnits)
        self.newPlacementId = newPlacementId
        self.occurrenceId = occurrenceId
    }

    fileprivate func validate() throws {
        guard let revision = Int64(priceRevision), revision >= 0,
              String(revision) == priceRevision else { throw InventorySaleCommandFailure.invalidRevision }
        guard let amount = Int64(reviewedPriceMinorUnits), amount > 0,
              String(amount) == reviewedPriceMinorUnits else { throw InventorySaleCommandFailure.invalidPrice }
        guard placementId != newPlacementId else { throw InventorySaleCommandFailure.invalidSelection }
    }
}

public struct InventorySalePayload: Codable, Equatable, Sendable {
    public let projectId: ProjectID
    public let currency: CurrencyCode
    public let items: [InventorySaleSelection]

    public init(projectId: ProjectID, currency: CurrencyCode, items: [InventorySaleSelection]) throws {
        self.projectId = projectId
        self.currency = currency
        self.items = items
        try validate()
    }

    fileprivate func validate() throws {
        guard (1...500).contains(items.count),
              Set(items.map(\.itemId)).count == items.count,
              Set(items.map(\.newPlacementId)).count == items.count,
              Set(items.map(\.occurrenceId)).count == items.count else {
            throw InventorySaleCommandFailure.invalidSelection
        }
        for item in items { try item.validate() }
    }
}

/// Shared app/MCP intent. Backend adapters translate the existing envelope;
/// admission here does not assert server permission or freshness of local data.
public struct InventorySaleCommand: Codable, Sendable {
    public let envelope: OperationEnvelope<InventorySalePayload>

    public init(operationId: OperationID, accountId: AccountID, actorPrincipalId: PrincipalID,
                capturedAt: Date, payload: InventorySalePayload) throws {
        let milliseconds = (capturedAt.timeIntervalSince1970 * 1000).rounded(.down)
        guard milliseconds.isFinite, milliseconds >= 0, milliseconds < 1_000_000_000_000_000 else {
            throw InventorySaleCommandFailure.invalidEnvelope
        }
        try self.init(envelope: .init(operationId: operationId,
            contractVersion: .init(validating: "inventory-sale-v1"), accountId: accountId,
            actorPrincipalId: actorPrincipalId,
            clientCreatedAt: Date(timeIntervalSince1970: milliseconds / 1000), payload: payload))
    }

    private init(envelope: OperationEnvelope<InventorySalePayload>) throws {
        let milliseconds = envelope.clientCreatedAt.timeIntervalSince1970 * 1000
        guard envelope.contractVersion.rawValue == "inventory-sale-v1", envelope.preconditions.isEmpty,
              milliseconds.isFinite, milliseconds >= 0, milliseconds < 1_000_000_000_000_000 else {
            throw InventorySaleCommandFailure.invalidEnvelope
        }
        try envelope.payload.validate()
        self.envelope = envelope
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(envelope: container.decode(OperationEnvelope<InventorySalePayload>.self, forKey: .envelope))
    }

    private enum CodingKeys: String, CodingKey { case envelope }
}
