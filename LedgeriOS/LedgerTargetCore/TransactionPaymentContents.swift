import Foundation

/// Current physical Item labels for reused cards, never historical prices or
/// evidence that the Item is still in the payment's Project.
public struct TransactionItemMetadata: Codable, Equatable, Sendable, Identifiable {
    public let id: ItemID
    public let name, sku, source, currentSource, currentSpaceName: String?
    public let imageCount: Int64?

    init(id: ItemID, name: String?, sku: String?, source: String?, currentSource: String?,
         currentSpaceName: String?, imageCount: Int64?) {
        self.id = id; self.name = name; self.sku = sku; self.source = source
        self.currentSource = currentSource; self.currentSpaceName = currentSpaceName; self.imageCount = imageCount
    }
    public init(from decoder: Decoder) throws {
        let wire = try Wire(from: decoder)
        id = try ItemID(validating: wire.itemId)
        name = wire.name; sku = wire.sku; source = wire.source; currentSource = wire.currentSource
        currentSpaceName = wire.currentSpaceName
        if let raw = wire.imageCount {
            guard let count = Int64(raw), count >= 0, String(count) == raw else {
                throw TransactionPaymentContents.Failure.invalidEvidence
            }
            imageCount = count
        } else { imageCount = nil }
    }
    public func encode(to encoder: Encoder) throws {
        try Wire(itemId: id.rawValue, name: name, sku: sku, source: source, currentSource: currentSource,
            currentSpaceName: currentSpaceName, imageCount: imageCount.map(String.init)).encode(to: encoder)
    }
    private struct Wire: Codable {
        let itemId: String
        let name, sku, source, currentSource, currentSpaceName, imageCount: String?
    }
}

/// Payment history is not a vendor receipt or a query of current placements.
/// Closed links and frozen paid Invoice lines retain their physical Item IDs.
public struct TransactionPaymentContents: Codable, Equatable, Sendable {
    public enum Failure: Error, Equatable { case invalidEvidence, scopeMismatch }
    public struct Connection: Codable, Equatable, Sendable {
        public let id: EntityID
        public let itemId: ItemID
        public let placementId: EntityID
        public let endedAt: String?
    }
    public let accountId: AccountID
    public let principalId: PrincipalID
    public let transactionId: TransactionID
    public let projectId: ProjectID
    public let clientId: ClientID
    public let connections: [Connection]
    public let invoice: FrozenInvoiceContents?
    /// nil is older/incomplete metadata, not proof of no related Items.
    public let items: [TransactionItemMetadata]?

    /// Deduplicate only presentation membership, never its supporting history.
    public var itemIDs: [ItemID] {
        var ids = Set(connections.map(\.itemId))
        for line in invoice?.lines ?? [] {
            if case .item(let itemId, _, _) = line.source { ids.insert(itemId) }
        }
        return ids.sorted { $0.rawValue < $1.rawValue }
    }

    public func validate(scope: TransactionScope, principalId: PrincipalID,
        transactionId: TransactionID, currency: CurrencyCode) throws {
        guard scope == .project(accountId: accountId, projectId: projectId, clientId: clientId),
              self.principalId == principalId, self.transactionId == transactionId,
              invoice == nil || invoice?.total.currency == currency else { throw Failure.scopeMismatch }
    }

    public init(from decoder: Decoder) throws {
        let wire = try Wire(from: decoder)
        accountId = try AccountID(validating: wire.accountId)
        principalId = try PrincipalID(validating: wire.principalId)
        transactionId = try TransactionID(validating: wire.transactionId)
        projectId = try ProjectID(validating: wire.projectId)
        clientId = try ClientID(validating: wire.clientId)
        connections = try wire.connections.map {
            guard $0.endedAt == nil || !$0.endedAt!.isEmpty else { throw Failure.invalidEvidence }
            return Connection(id: try EntityID(validating: $0.id), itemId: try ItemID(validating: $0.itemId),
                placementId: try EntityID(validating: $0.placementId), endedAt: $0.endedAt)
        }
        guard Set(connections.map(\.id)).count == connections.count else { throw Failure.invalidEvidence }
        invoice = try wire.invoice?.restored()
        if let invoice {
            guard invoice.scope == .project(accountId: accountId, projectId: projectId, clientId: clientId),
                  invoice.purchaseId == transactionId else { throw Failure.scopeMismatch }
        }
        items = wire.items
        if let items {
            guard Set(items.map(\.id)).count == items.count,
                  Set(items.map(\.id)) == Set(itemIDs) else { throw Failure.invalidEvidence }
        }
    }

    public func encode(to encoder: Encoder) throws {
        try Wire(accountId: accountId.rawValue, principalId: principalId.rawValue,
            transactionId: transactionId.rawValue, projectId: projectId.rawValue, clientId: clientId.rawValue,
            connections: connections.map { .init(id: $0.id.rawValue, itemId: $0.itemId.rawValue,
                placementId: $0.placementId.rawValue, endedAt: $0.endedAt) },
            invoice: try invoice.map(FrozenInvoiceStorageRecord.make), items: items).encode(to: encoder)
    }

    private struct Wire: Codable {
        let accountId, principalId, transactionId, projectId, clientId: String
        let connections: [Link]
        let invoice: FrozenInvoiceStorageRecord?
        let items: [TransactionItemMetadata]?
        struct Link: Codable {
            let id, itemId, placementId: String
            let endedAt: String?
        }
    }
}
