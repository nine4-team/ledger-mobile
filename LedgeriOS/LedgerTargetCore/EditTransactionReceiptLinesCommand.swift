import Foundation

public protocol TransactionReceiptLinesEditing: Sendable {
    func editTransactionReceiptLines(_ payload: EditTransactionReceiptLinesCommand.Payload,
        operationUUID: UUID, capturedAt: Date) async throws -> OperationReceipt
    func pendingTransactionReceiptLinesEdit(scope: TransactionScope,
        transactionId: TransactionID) async throws -> PendingTransactionReceiptLinesEdit?
    func watchTransactionReceiptLinesEdit(_ operationId: OperationID) -> AsyncThrowingStream<OperationSnapshot?, Error>
}

public struct PendingTransactionReceiptLinesEdit: Sendable {
    public let payload: EditTransactionReceiptLinesCommand.Payload
    public let receipt: OperationReceipt
    public init(payload: EditTransactionReceiptLinesCommand.Payload, receipt: OperationReceipt) {
        self.payload = payload; self.receipt = receipt
    }
}

/// Replace only ordered vendor receipt lines. Comparing the reviewed lines under
/// the server row lock prevents overwriting another edit without coupling this
/// operation to descriptive fields, Item prices or billing allocations.
public struct EditTransactionReceiptLinesCommand: Codable, Sendable {
    public enum Failure: Error, Equatable {
        case invalidEnvelope, duplicateLine, currencyMismatch, unrepresentableText
        case immutableTransaction, incompleteEvidence
    }
    public struct Payload: Codable, Equatable, Sendable {
        public let transactionId: TransactionID
        public let scope: TransactionScope
        public let currency: CurrencyCode
        public let expectedLines: [NonItemReceiptLine]
        public let lines: [NonItemReceiptLine]

        public init(transactionId: TransactionID, scope: TransactionScope, currency: CurrencyCode,
                    expectedLines: [NonItemReceiptLine], lines: [NonItemReceiptLine]) throws {
            self.transactionId = transactionId; self.scope = scope; self.currency = currency
            self.expectedLines = expectedLines; self.lines = lines
            try validate()
        }
        fileprivate func validate() throws {
            for values in [expectedLines, lines] {
                guard Set(values.map(\.id)).count == values.count else { throw Failure.duplicateLine }
                guard values.allSatisfy({ $0.magnitude.currency == currency }) else { throw Failure.currencyMismatch }
                guard values.allSatisfy({ !$0.description.rawValue.contains("\0") }) else {
                    throw Failure.unrepresentableText
                }
            }
        }
    }
    public let envelope: OperationEnvelope<Payload>

    public init(operationId: OperationID, actorPrincipalId: PrincipalID,
                capturedAt: Date, payload: Payload) throws {
        let ms = (capturedAt.timeIntervalSince1970 * 1000).rounded(.down)
        guard ms.isFinite, ms >= 0, ms < 1_000_000_000_000_000 else { throw Failure.invalidEnvelope }
        try self.init(envelope: .init(operationId: operationId,
            contractVersion: .init(validating: "transaction-receipt-lines-edit-v1"),
            accountId: payload.scope.accountId, actorPrincipalId: actorPrincipalId,
            clientCreatedAt: Date(timeIntervalSince1970: ms / 1000), payload: payload))
    }
    private init(envelope: OperationEnvelope<Payload>) throws {
        let ms = envelope.clientCreatedAt.timeIntervalSince1970 * 1000
        guard envelope.contractVersion.rawValue == "transaction-receipt-lines-edit-v1",
              envelope.preconditions.isEmpty, envelope.accountId == envelope.payload.scope.accountId,
              ms.isFinite, ms >= 0, ms < 1_000_000_000_000_000 else { throw Failure.invalidEnvelope }
        try envelope.payload.validate()
        self.envelope = envelope
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(envelope: c.decode(OperationEnvelope<Payload>.self, forKey: .envelope))
    }
    private enum CodingKeys: String, CodingKey { case envelope }
}

public struct TransactionReceiptLinesEditDraft: Sendable {
    public let original: TransactionDetailSnapshot
    public var entries: [ReceiptLineEntry]

    public init(original: TransactionDetailSnapshot) throws {
        guard original.origin == .vendorPayment else {
            throw EditTransactionReceiptLinesCommand.Failure.immutableTransaction
        }
        guard let receipt = original.receipt else {
            throw EditTransactionReceiptLinesCommand.Failure.incompleteEvidence
        }
        self.original = original
        entries = receipt.lines.map { ReceiptLineEntry(line: $0) }
    }
    public func payload() throws -> EditTransactionReceiptLinesCommand.Payload? {
        guard let receipt = original.receipt else {
            throw EditTransactionReceiptLinesCommand.Failure.incompleteEvidence
        }
        let lines = try entries.map { try $0.receiptLine(currency: original.amount.currency) }
        guard lines != receipt.lines else { return nil }
        return try .init(transactionId: original.transactionId, scope: original.classification.scope,
            currency: original.amount.currency, expectedLines: receipt.lines, lines: lines)
    }
}
