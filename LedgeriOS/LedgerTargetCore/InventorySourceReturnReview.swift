import Foundation

/// Review of a current, proven Project-origin Inventory entry. Providers must
/// bind each entry to its current placement and authorized Account before building
/// this value. This is not inferred from an Item's current price or old label.
public struct InventorySourceReturnReview: Equatable, Sendable {
    public enum Failure: Error, Equatable { case invalidSelection, mixedSourceProjects, invalidBasis }

    public struct Item: Equatable, Sendable {
        public let itemId: ItemID
        public let placementId: EntityID
        public let inventoryEntryId: EntityID
        public let sourceProjectId: ProjectID
        public let sourceCategoryId: BudgetCategoryID
        public let sourceAmount: Money

        public init(itemId: ItemID, placementId: EntityID, inventoryEntryId: EntityID,
                    sourceProjectId: ProjectID, sourceCategoryId: BudgetCategoryID, sourceAmount: Money) throws {
            guard sourceAmount.minorUnits > 0 else { throw Failure.invalidBasis }
            self.itemId = itemId; self.placementId = placementId; self.inventoryEntryId = inventoryEntryId
            self.sourceProjectId = sourceProjectId; self.sourceCategoryId = sourceCategoryId
            self.sourceAmount = sourceAmount
        }
    }

    public let accountId: AccountID
    public let principalId: PrincipalID
    public let projectId: ProjectID
    public let items: [Item]

    public init(accountId: AccountID, principalId: PrincipalID, items: [Item]) throws {
        guard (1...100).contains(items.count), let first = items.first,
              Set(items.map(\.itemId)).count == items.count,
              Set(items.map(\.placementId)).count == items.count,
              Set(items.map(\.inventoryEntryId)).count == items.count else { throw Failure.invalidSelection }
        guard items.allSatisfy({ $0.sourceProjectId == first.sourceProjectId }) else {
            throw Failure.mixedSourceProjects
        }
        guard items.allSatisfy({ $0.sourceAmount.currency == first.sourceAmount.currency }) else {
            throw Failure.invalidBasis
        }
        self.accountId = accountId; self.principalId = principalId
        self.projectId = first.sourceProjectId; self.items = items
    }

    /// Capture once for retry. No editable destination, amount or category: the
    /// writer must re-read the immutable entry and confirm current custody.
    public func makePayload(makeUUID: () -> UUID = UUID.init) throws -> ReturnInventoryItemsToSourcePayload {
        try .init(projectId: projectId, items: items.map {
            .init(itemId: $0.itemId, placementId: $0.placementId, inventoryEntryId: $0.inventoryEntryId,
                  projectPlacementId: try .init(validating: "source-return-placement-" + makeUUID().uuidString.lowercased()),
                  occurrenceId: try .init(validating: "source-return-charge-" + makeUUID().uuidString.lowercased()))
        })
    }
}

/// Separate from InventorySalePayload: a sale selects a new destination/price;
/// a source return restores the exact inventory-entry basis. Neither action's
/// availability determines the other's availability.
public struct ReturnInventoryItemsToSourcePayload: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public let itemId: ItemID
        public let placementId: EntityID
        public let inventoryEntryId: EntityID
        public let projectPlacementId: EntityID
        public let occurrenceId: BillableItemOccurrenceID

        public init(itemId: ItemID, placementId: EntityID, inventoryEntryId: EntityID,
                    projectPlacementId: EntityID, occurrenceId: BillableItemOccurrenceID) {
            self.itemId = itemId; self.placementId = placementId; self.inventoryEntryId = inventoryEntryId
            self.projectPlacementId = projectPlacementId; self.occurrenceId = occurrenceId
        }
    }
    public let projectId: ProjectID
    public let items: [Item]

    public init(projectId: ProjectID, items: [Item]) throws {
        guard (1...100).contains(items.count),
              Set(items.map(\.itemId)).count == items.count,
              Set(items.map(\.placementId)).count == items.count,
              Set(items.map(\.inventoryEntryId)).count == items.count,
              Set(items.map(\.projectPlacementId)).count == items.count,
              Set(items.map(\.occurrenceId)).count == items.count,
              Set(items.map(\.placementId)).isDisjoint(with: Set(items.map(\.projectPlacementId))) else {
            throw InventorySourceReturnReview.Failure.invalidSelection
        }
        self.projectId = projectId; self.items = items
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(projectId: values.decode(ProjectID.self, forKey: .projectId),
                      items: values.decode([Item].self, forKey: .items))
    }
    private enum CodingKeys: String, CodingKey { case projectId, items }
}

/// Persisted intent uses the shared operation envelope. The server resolves
/// the selected immutable entries; no client-authored monetary basis is posted.
public struct ReturnInventoryItemsToSourceCommand: Codable, Sendable {
    public enum Failure: Error { case invalidEnvelope }
    public let envelope: OperationEnvelope<ReturnInventoryItemsToSourcePayload>

    public init(operationId: OperationID, accountId: AccountID, actorPrincipalId: PrincipalID,
                capturedAt: Date, payload: ReturnInventoryItemsToSourcePayload) throws {
        let milliseconds = (capturedAt.timeIntervalSince1970 * 1000).rounded(.down)
        guard milliseconds.isFinite, milliseconds >= 0, milliseconds < 1_000_000_000_000_000 else {
            throw Failure.invalidEnvelope
        }
        try self.init(envelope: .init(operationId: operationId,
            contractVersion: .init(validating: "return-inventory-to-source-v1"), accountId: accountId,
            actorPrincipalId: actorPrincipalId,
            clientCreatedAt: Date(timeIntervalSince1970: milliseconds / 1000), payload: payload))
    }

    private init(envelope: OperationEnvelope<ReturnInventoryItemsToSourcePayload>) throws {
        let milliseconds = envelope.clientCreatedAt.timeIntervalSince1970 * 1000
        guard envelope.contractVersion.rawValue == "return-inventory-to-source-v1",
              envelope.preconditions.isEmpty, milliseconds.isFinite,
              milliseconds >= 0, milliseconds < 1_000_000_000_000_000 else { throw Failure.invalidEnvelope }
        self.envelope = envelope
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(envelope: values.decode(OperationEnvelope<ReturnInventoryItemsToSourcePayload>.self,
                                             forKey: .envelope))
    }
    private enum CodingKeys: String, CodingKey { case envelope }
}
