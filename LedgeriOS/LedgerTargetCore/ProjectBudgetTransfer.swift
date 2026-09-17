import Foundation

/// Frozen Transfer evidence, not another charge or payment. The provider must
/// validate the authoritative pair and its source lineage before constructing it.
public struct ProjectBudgetTransfer: Equatable, Sendable {
    public enum Basis: Equatable, Sendable {
        case openCharge(LiveInvoiceContents.Line)
        case paidLine(FrozenInvoiceLine)
    }

    public struct Item: Equatable, Sendable {
        public let itemId: ItemID
        public let basis: Basis

        public init(itemId: ItemID, basis: Basis) {
            self.itemId = itemId
            self.basis = basis
        }
    }

    public let pair: TransferPairIdentity
    public let items: [Item]

    public init(pair: TransferPairIdentity, items: [Item]) throws {
        guard !items.isEmpty, Set(items.map(\.itemId)).count == items.count else {
            throw ProjectBudgetCalculation.Failure.duplicateSource
        }
        var sources = Set<LiveInvoiceSource>()
        for item in items {
            let source: LiveInvoiceSource
            switch item.basis {
            case .openCharge(let line):
                guard case .itemOccurrence = line.selection.source,
                      line.selection.reviewedAmount.minorUnits > 0 else {
                    throw ProjectBudgetCalculation.Failure.missingEvidence
                }
                source = line.selection.source
            case .paidLine(let line):
                guard case .item(let itemId, let occurrenceId, _) = line.source,
                      itemId == item.itemId, line.signedAmount.minorUnits > 0,
                      line.scope.accountId == pair.route.source.accountId,
                      line.scope.clientId == pair.route.source.clientId else {
                    throw ProjectBudgetCalculation.Failure.missingEvidence
                }
                source = .itemOccurrence(occurrenceId)
            }
            guard sources.insert(source).inserted else { throw ProjectBudgetCalculation.Failure.duplicateSource }
        }
        self.pair = pair
        self.items = items
    }
}
