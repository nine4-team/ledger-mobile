import Foundation

public protocol ItemDetailsEditing: Sendable {
    func editItemDetails(_ payload: EditItemDetailsCommand.Payload, operationUUID: UUID,
                         capturedAt: Date) async throws -> OperationReceipt
    func itemDetailsEditStatus(_ operationId: OperationID) async throws -> OperationSnapshot?
    func watchItemDetailsEdit(_ operationId: OperationID) -> AsyncThrowingStream<OperationSnapshot?, Error>
}

/// Descriptive changes only. Placement, money, vendor resolution and accounting
/// history have separate commands; a status label cannot perform a Return.
public struct EditItemDetailsCommand: Codable, Sendable {
    public enum TextChange: Codable, Equatable, Sendable {
        case set(String)
        case clear
    }
    public enum StatusChange: String, Codable, Sendable {
        case toPurchase = "to purchase", purchased, toReturn = "to return", returned, clear
    }
    public struct Selection: Codable, Equatable, Sendable {
        public let itemId: ItemID
        public let expectedRevision: Int64
        public init(itemId: ItemID, expectedRevision: Int64) {
            self.itemId = itemId; self.expectedRevision = expectedRevision
        }
    }
    public struct Changes: Codable, Equatable, Sendable {
        public let name: TextChange?
        public let sku: TextChange?
        public let notes: TextChange?
        public let status: StatusChange?
        public let bookmark: Bool?
        public init(name: TextChange? = nil, sku: TextChange? = nil, notes: TextChange? = nil,
                    status: StatusChange? = nil, bookmark: Bool? = nil) {
            self.name = name; self.sku = sku; self.notes = notes; self.status = status; self.bookmark = bookmark
        }
        fileprivate func validate() throws {
            guard name != nil || sku != nil || notes != nil || status != nil || bookmark != nil else {
                throw Failure.emptyChanges
            }
            for change in [name, sku, notes] {
                if case .set(let text) = change, text.unicodeScalars.contains(where: { $0.value == 0 }) {
                    throw Failure.unrepresentableText
                }
            }
        }
    }
    public struct Payload: Codable, Equatable, Sendable {
        public let items: [Selection]
        public let changes: Changes
        public init(items: [Selection], changes: Changes) throws {
            self.items = items; self.changes = changes
            try validate()
        }
        fileprivate func validate() throws {
            guard !items.isEmpty, Set(items.map(\.itemId)).count == items.count,
                  items.allSatisfy({ $0.expectedRevision > 0 && $0.expectedRevision < Int64.max }) else {
                throw Failure.invalidSelection
            }
            // The current bulk control changes status, not names or other fields.
            guard items.count == 1 || (changes.status != nil && changes.name == nil
                && changes.sku == nil && changes.notes == nil && changes.bookmark == nil) else {
                throw Failure.invalidSelection
            }
            try changes.validate()
        }
    }
    public let envelope: OperationEnvelope<Payload>
    public init(operationId: OperationID, accountId: AccountID, actorPrincipalId: PrincipalID,
                capturedAt: Date, payload: Payload) throws {
        let ms = (capturedAt.timeIntervalSince1970 * 1000).rounded(.down)
        guard ms.isFinite, ms >= 0, ms < 1_000_000_000_000_000 else { throw Failure.invalidEnvelope }
        try self.init(envelope: .init(operationId: operationId,
            contractVersion: .init(validating: "item-details-edit-v1"), accountId: accountId,
            actorPrincipalId: actorPrincipalId, clientCreatedAt: Date(timeIntervalSince1970: ms / 1000), payload: payload))
    }
    private init(envelope: OperationEnvelope<Payload>) throws {
        let ms = envelope.clientCreatedAt.timeIntervalSince1970 * 1000
        guard envelope.contractVersion.rawValue == "item-details-edit-v1", envelope.preconditions.isEmpty,
              ms.isFinite, ms >= 0, ms < 1_000_000_000_000_000 else { throw Failure.invalidEnvelope }
        try envelope.payload.validate()
        self.envelope = envelope
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(envelope: container.decode(OperationEnvelope<Payload>.self, forKey: .envelope))
    }
    private enum CodingKeys: String, CodingKey { case envelope }
    public enum Failure: Error, Equatable { case emptyChanges, invalidSelection, unrepresentableText, invalidEnvelope }
}
