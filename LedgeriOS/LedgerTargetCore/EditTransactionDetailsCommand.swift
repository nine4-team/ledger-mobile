import Foundation

public protocol TransactionDetailsEditing: Sendable {
    func editTransactionDetails(_ payload: EditTransactionDetailsCommand.Payload, operationUUID: UUID,
                                capturedAt: Date) async throws -> OperationReceipt
    func transactionDetailsEditStatus(_ operationId: OperationID) async throws -> OperationSnapshot?
    func pendingTransactionDetailsEdit(scope: TransactionScope, transactionId: TransactionID) async throws -> PendingTransactionDetailsEdit?
    func watchTransactionDetailsEdit(_ operationId: OperationID) -> AsyncThrowingStream<OperationSnapshot?, Error>
}

public struct PendingTransactionDetailsEdit: Sendable {
    public let payload: EditTransactionDetailsCommand.Payload
    public let receipt: OperationReceipt
    public init(payload: EditTransactionDetailsCommand.Payload, receipt: OperationReceipt) {
        self.payload = payload; self.receipt = receipt
    }
}

/// Descriptive edits only. This command cannot change cash, classification,
/// placement, receipt lines, or frozen Invoice evidence.
public struct EditTransactionDetailsCommand: Codable, Sendable {
    public enum TextChange: Codable, Equatable, Sendable {
        case set(String)
        case clear
    }
    public struct Changes: Codable, Equatable, Sendable {
        public let source: TextChange?
        public let notes: TextChange?
        public let paymentMethod: TextChange?
        public let hasEmailReceipt: Bool?

        public init(source: TextChange? = nil, notes: TextChange? = nil,
                    paymentMethod: TextChange? = nil, hasEmailReceipt: Bool? = nil) {
            self.source = source; self.notes = notes
            self.paymentMethod = paymentMethod; self.hasEmailReceipt = hasEmailReceipt
        }

        fileprivate func validate() throws {
            guard source != nil || notes != nil || paymentMethod != nil || hasEmailReceipt != nil else {
                throw Failure.emptyChanges
            }
            for change in [source, notes, paymentMethod] {
                if case .set(let text) = change, text.unicodeScalars.contains(where: { $0.value == 0 }) {
                    throw Failure.unrepresentableText
                }
            }
        }
    }
    public struct Payload: Codable, Equatable, Sendable {
        public let transactionId: TransactionID
        public let scope: TransactionScope
        public let expectedRevision: Int64
        public let changes: Changes

        public init(transactionId: TransactionID, scope: TransactionScope,
                    expectedRevision: Int64, changes: Changes) throws {
            self.transactionId = transactionId; self.scope = scope
            self.expectedRevision = expectedRevision; self.changes = changes
            try validate()
        }

        fileprivate func validate() throws {
            guard expectedRevision > 0, expectedRevision < Int64.max else { throw Failure.invalidRevision }
            try changes.validate()
        }
    }

    public let envelope: OperationEnvelope<Payload>

    public init(operationId: OperationID, actorPrincipalId: PrincipalID,
                capturedAt: Date, payload: Payload) throws {
        let ms = (capturedAt.timeIntervalSince1970 * 1000).rounded(.down)
        guard ms.isFinite, ms >= 0, ms < 1_000_000_000_000_000 else { throw Failure.invalidEnvelope }
        try self.init(envelope: .init(operationId: operationId,
            contractVersion: .init(validating: "transaction-details-edit-v1"),
            accountId: payload.scope.accountId, actorPrincipalId: actorPrincipalId,
            clientCreatedAt: Date(timeIntervalSince1970: ms / 1000), payload: payload))
    }

    private init(envelope: OperationEnvelope<Payload>) throws {
        let ms = envelope.clientCreatedAt.timeIntervalSince1970 * 1000
        guard envelope.contractVersion.rawValue == "transaction-details-edit-v1",
              envelope.preconditions.isEmpty, envelope.accountId == envelope.payload.scope.accountId,
              ms.isFinite, ms >= 0, ms < 1_000_000_000_000_000 else { throw Failure.invalidEnvelope }
        try envelope.payload.validate()
        self.envelope = envelope
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(envelope: container.decode(OperationEnvelope<Payload>.self, forKey: .envelope))
    }
    private enum CodingKeys: String, CodingKey { case envelope }
    public enum Failure: Error, Equatable {
        case emptyChanges, invalidRevision, unrepresentableText, invalidEnvelope, immutableTransaction
    }
}

/// Preserve unknown/legacy values on unchanged Save; editing display fields
/// must not accidentally turn missing evidence into false or clear raw text.
public struct TransactionDetailsEditDraft: Sendable {
    public let original: TransactionDetailSnapshot
    public var source: String
    public var notes: String
    public var paymentMethod: String
    /// Nil makes no selection; it does not erase an existing yes/no answer.
    public var hasEmailReceipt: Bool?

    public init(original: TransactionDetailSnapshot) {
        self.original = original
        source = original.source ?? ""; notes = original.notes ?? ""
        paymentMethod = original.paymentMethod ?? ""
        hasEmailReceipt = original.hasEmailReceipt
    }

    public func payload() throws -> EditTransactionDetailsCommand.Payload? {
        func change(_ value: String, original: String?) -> EditTransactionDetailsCommand.TextChange? {
            guard value != (original ?? "") else { return nil }
            return value.isEmpty ? .clear : .set(value)
        }
        let source = change(source, original: original.source)
        let notes = change(notes, original: original.notes)
        let method = change(paymentMethod, original: original.paymentMethod)
        let email = hasEmailReceipt == original.hasEmailReceipt ? nil : hasEmailReceipt
        guard source != nil || notes != nil || method != nil || email != nil else { return nil }
        guard original.origin == .vendorPayment else { throw EditTransactionDetailsCommand.Failure.immutableTransaction }
        guard let revision = original.detailsRevision else { throw EditTransactionDetailsCommand.Failure.invalidRevision }
        return try .init(transactionId: original.transactionId, scope: original.classification.scope,
            expectedRevision: revision,
            changes: .init(source: source, notes: notes, paymentMethod: method, hasEmailReceipt: email))
    }
}
