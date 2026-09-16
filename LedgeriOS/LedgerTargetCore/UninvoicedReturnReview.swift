import Foundation

public protocol UninvoicedReturnWorkflowServing: Sendable {
    func watchUninvoicedReturnReview(projectId: ProjectID, itemIds: [ItemID]) -> AsyncThrowingStream<UninvoicedReturnReview?, Error>
    func returnUninvoicedItems(_ payload: ReturnUninvoicedItemsPayload, operationUUID: UUID,
                              capturedAt: Date) async throws -> OperationReceipt
    func watchUninvoicedReturn(_ operationId: OperationID) -> AsyncThrowingStream<OperationSnapshot?, Error>
}

/// Non-monetary evidence for the existing single/bulk Return to Inventory action.
public struct UninvoicedReturnReview: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public let itemId: ItemID
        public let placementId: EntityID
        public let chargeId: BillableItemOccurrenceID
        public let revision: Int64
        public init(itemId: ItemID, placementId: EntityID, chargeId: BillableItemOccurrenceID, revision: Int64) throws {
            guard revision > 0, revision < Int64.max else { throw ReturnUninvoicedItemsFailure.invalidRevision }
            self.itemId = itemId; self.placementId = placementId; self.chargeId = chargeId; self.revision = revision
        }
    }
    public let accountId: AccountID
    public let principalId: PrincipalID
    public let projectId: ProjectID
    public let items: [Item]

    public init(accountId: AccountID, principalId: PrincipalID, projectId: ProjectID, items: [Item]) throws {
        guard (1...500).contains(items.count), Set(items.map(\.itemId)).count == items.count,
              Set(items.map(\.placementId)).count == items.count, Set(items.map(\.chargeId)).count == items.count else {
            throw ReturnUninvoicedItemsFailure.invalidSelection
        }
        self.accountId = accountId; self.principalId = principalId; self.projectId = projectId; self.items = items
    }

    /// Create once on confirmation; retain the payload, UUID and time for retries.
    public func makePayload(makeUUID: () -> UUID = UUID.init) throws -> ReturnUninvoicedItemsPayload {
        try .init(projectId: projectId, items: items.map {
            try .init(itemId: $0.itemId, placementId: $0.placementId, chargeId: $0.chargeId,
                expectedChargeRevision: $0.revision,
                inventoryPlacementId: .init(validating: "return-placement-" + makeUUID().uuidString.lowercased()),
                returnOccurrenceId: .init(validating: "return-occurrence-" + makeUUID().uuidString.lowercased()))
        })
    }
}
