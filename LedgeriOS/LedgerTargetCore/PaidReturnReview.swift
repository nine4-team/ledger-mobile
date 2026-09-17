import Foundation

public protocol PaidReturnWorkflowServing: Sendable {
    func watchPaidReturnReview(projectId: ProjectID, itemIds: [ItemID]) -> AsyncThrowingStream<PaidReturnReview?, Error>
    func returnPaidItems(_ payload: ReturnPaidItemsPayload, operationUUID: UUID,
                         capturedAt: Date) async throws -> OperationReceipt
    func watchPaidReturn(_ operationId: OperationID) -> AsyncThrowingStream<OperationSnapshot?, Error>
}

/// Frozen credit basis displayed before the existing Return to Inventory action.
/// Money is review evidence only; the authoritative command accepts line identities.
public struct PaidReturnReview: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public let itemId: ItemID
        public let placementId: EntityID
        public let chargeId: BillableItemOccurrenceID
        public let paidInvoiceLineId: EntityID
        public let paidAmount: Money
        public let categoryId: BudgetCategoryID

        public init(itemId: ItemID, placementId: EntityID, chargeId: BillableItemOccurrenceID,
                    paidInvoiceLineId: EntityID, paidAmount: Money, categoryId: BudgetCategoryID) throws {
            guard paidAmount.minorUnits > 0 else { throw ReturnPaidItemsFailure.invalidSelection }
            self.itemId = itemId; self.placementId = placementId; self.chargeId = chargeId
            self.paidInvoiceLineId = paidInvoiceLineId; self.paidAmount = paidAmount; self.categoryId = categoryId
        }
    }

    public let accountId: AccountID
    public let principalId: PrincipalID
    public let projectId: ProjectID
    public let items: [Item]

    public init(accountId: AccountID, principalId: PrincipalID, projectId: ProjectID, items: [Item]) throws {
        guard (1...100).contains(items.count), Set(items.map(\.itemId)).count == items.count,
              Set(items.map(\.placementId)).count == items.count,
              Set(items.map(\.chargeId)).count == items.count,
              Set(items.map(\.paidInvoiceLineId)).count == items.count else {
            throw ReturnPaidItemsFailure.invalidSelection
        }
        self.accountId = accountId; self.principalId = principalId; self.projectId = projectId; self.items = items
    }

    /// Capture once on confirmation and retain for retries. Never recalculate
    /// credits from current Item prices or send mutable monetary fields.
    public func makePayload(makeUUID: () -> UUID = UUID.init) throws -> ReturnPaidItemsPayload {
        try .init(projectId: projectId, items: items.map {
            try .init(itemId: $0.itemId, placementId: $0.placementId, chargeId: $0.chargeId,
                paidInvoiceLineId: $0.paidInvoiceLineId,
                inventoryPlacementId: .init(validating: "return-placement-" + makeUUID().uuidString.lowercased()),
                returnOccurrenceId: .init(validating: "return-occurrence-" + makeUUID().uuidString.lowercased()),
                creditId: .init(validating: "return-credit-" + makeUUID().uuidString.lowercased()))
        })
    }
}
