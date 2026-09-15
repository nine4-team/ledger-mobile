import Foundation

/// Retain this envelope unchanged across offline restart and upload retry.
public struct CreateExpenseCommand: Codable, Sendable {
    public let envelope: OperationEnvelope<BusinessPaidExpenseDraft>

    public init(operationId: OperationID, actorPrincipalId: PrincipalID,
                capturedAt: Date, draft: BusinessPaidExpenseDraft) throws {
        let milliseconds = (capturedAt.timeIntervalSince1970 * 1000).rounded(.down)
        guard milliseconds.isFinite, milliseconds >= 0, milliseconds < 1_000_000_000_000_000 else {
            throw Failure.invalidEnvelope
        }
        try self.init(envelope: .init(operationId: operationId,
            contractVersion: .init(validating: "expense-create-v1"), accountId: draft.accountId,
            actorPrincipalId: actorPrincipalId,
            clientCreatedAt: Date(timeIntervalSince1970: milliseconds / 1000), payload: draft))
    }

    private init(envelope: OperationEnvelope<BusinessPaidExpenseDraft>) throws {
        let milliseconds = envelope.clientCreatedAt.timeIntervalSince1970 * 1000
        guard envelope.contractVersion.rawValue == "expense-create-v1", envelope.preconditions.isEmpty,
              envelope.accountId == envelope.payload.accountId,
              milliseconds.isFinite, milliseconds >= 0, milliseconds < 1_000_000_000_000_000 else {
            throw Failure.invalidEnvelope
        }
        self.envelope = envelope
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(envelope: c.decode(OperationEnvelope<BusinessPaidExpenseDraft>.self, forKey: .envelope))
    }

    public enum Failure: Error, Equatable, Sendable { case invalidEnvelope }
    private enum CodingKeys: String, CodingKey { case envelope }
}
