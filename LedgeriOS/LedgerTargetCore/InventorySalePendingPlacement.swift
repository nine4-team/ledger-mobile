import Foundation

/// A local presentation of accepted intent, never a replacement history fact.
public struct InventorySalePendingPlacement: Equatable, Sendable {
    public let operationId: OperationID
    public let accountId: AccountID
    public let projectId: ProjectID
    public let projectName: String
    public let item: InventorySaleSelection
    public let price: Money
    public let state: LocalOperationState

    public init(command: InventorySaleCommand, projectName: String, itemId: ItemID,
                state: LocalOperationState) throws {
        guard let item = command.envelope.payload.items.first(where: { $0.itemId == itemId }),
              let amount = Int64(item.reviewedPriceMinorUnits) else { throw InventorySaleCommandFailure.invalidSelection }
        operationId = command.envelope.operationId; accountId = command.envelope.accountId
        projectId = command.envelope.payload.projectId; self.projectName = projectName
        self.item = item; self.state = state
        price = Money(minorUnits: amount, currency: command.envelope.payload.currency)
    }

    /// Caller supplies authorized downloaded evidence from the same Account.
    /// Retain the pending destination through the gap between source closure
    /// and destination download. A newer physical cycle always wins.
    public func resolve(source: PhysicalItemPlacement, current: PhysicalItemPlacement?) throws -> PhysicalItemPlacement? {
        guard source.itemId == item.itemId, source.placementId == item.placementId,
              source.scope == .businessInventory, source.pendingSale == nil,
              current == nil || current?.itemId == item.itemId else { throw InventorySaleCommandFailure.invalidSelection }
        guard state == .queued || state == .applying || state == .applied else { return current }
        if let current, current.placementId != item.placementId {
            if current.placementId == item.newPlacementId, current.scope != .project(projectId) {
                throw InventorySaleCommandFailure.invalidSelection
            }
            return current
        }
        guard current == nil || current?.scope == .businessInventory else {
            throw InventorySaleCommandFailure.invalidSelection
        }
        let value = current ?? source
        return try PhysicalItemPlacement(itemId: value.itemId, description: value.description, itemRevision: value.itemRevision,
            placementId: item.newPlacementId, scope: .project(projectId), spaceId: nil,
            name: value.name, sku: value.sku, createdAt: value.createdAt,
            workflowStatusRaw: value.workflowStatusRaw, isBookmarked: value.isBookmarked,
            source: value.source, currentSource: value.currentSource, imageCount: value.imageCount, pendingSale: self)
    }
}
