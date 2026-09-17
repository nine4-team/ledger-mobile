import Foundation

public enum ReturnPaidItemsFailure: Error, Equatable, Sendable {
    case invalidSelection, invalidEnvelope
}

/// Physical return plus a credit against an exact frozen line. No caller-supplied
/// amount, category, cash refund or mutation of the original paid charge.
public struct ReturnPaidItemsPayload: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public let itemId: ItemID
        public let placementId: EntityID
        public let chargeId: BillableItemOccurrenceID
        public let paidInvoiceLineId: EntityID
        public let inventoryPlacementId: EntityID
        public let returnOccurrenceId: EntityID
        public let creditId: EntityID

        public init(itemId: ItemID, placementId: EntityID, chargeId: BillableItemOccurrenceID,
                    paidInvoiceLineId: EntityID, inventoryPlacementId: EntityID,
                    returnOccurrenceId: EntityID, creditId: EntityID) {
            self.itemId = itemId; self.placementId = placementId; self.chargeId = chargeId
            self.paidInvoiceLineId = paidInvoiceLineId; self.inventoryPlacementId = inventoryPlacementId
            self.returnOccurrenceId = returnOccurrenceId; self.creditId = creditId
        }
    }

    public let projectId: ProjectID
    public let items: [Item]

    public init(projectId: ProjectID, items: [Item]) throws {
        self.projectId = projectId; self.items = items
        try validate()
    }

    fileprivate func validate() throws {
        guard !items.isEmpty, items.count <= 100,
              Set(items.map(\.itemId)).count == items.count,
              Set(items.map(\.placementId)).count == items.count,
              Set(items.map(\.chargeId)).count == items.count,
              Set(items.map(\.paidInvoiceLineId)).count == items.count,
              Set(items.map(\.inventoryPlacementId)).count == items.count,
              Set(items.map(\.returnOccurrenceId)).count == items.count,
              Set(items.map(\.creditId)).count == items.count,
              Set(items.map(\.placementId)).isDisjoint(with: Set(items.map(\.inventoryPlacementId))) else {
            throw ReturnPaidItemsFailure.invalidSelection
        }
    }
}

public struct ReturnPaidItemsCommand: Codable, Sendable {
    public let envelope: OperationEnvelope<ReturnPaidItemsPayload>

    public init(operationId: OperationID, accountId: AccountID, actorPrincipalId: PrincipalID,
                capturedAt: Date, payload: ReturnPaidItemsPayload) throws {
        let milliseconds = (capturedAt.timeIntervalSince1970 * 1000).rounded(.down)
        guard milliseconds.isFinite, milliseconds >= 0, milliseconds < 1_000_000_000_000_000 else {
            throw ReturnPaidItemsFailure.invalidEnvelope
        }
        try self.init(envelope: .init(operationId: operationId,
            contractVersion: .init(validating: "return-paid-items-v1"), accountId: accountId,
            actorPrincipalId: actorPrincipalId,
            clientCreatedAt: Date(timeIntervalSince1970: milliseconds / 1000), payload: payload))
    }

    private init(envelope: OperationEnvelope<ReturnPaidItemsPayload>) throws {
        let milliseconds = envelope.clientCreatedAt.timeIntervalSince1970 * 1000
        guard envelope.contractVersion.rawValue == "return-paid-items-v1", envelope.preconditions.isEmpty,
              milliseconds.isFinite, milliseconds >= 0, milliseconds < 1_000_000_000_000_000 else {
            throw ReturnPaidItemsFailure.invalidEnvelope
        }
        try envelope.payload.validate()
        self.envelope = envelope
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(envelope: container.decode(OperationEnvelope<ReturnPaidItemsPayload>.self, forKey: .envelope))
    }

    private enum CodingKeys: String, CodingKey { case envelope }
}
