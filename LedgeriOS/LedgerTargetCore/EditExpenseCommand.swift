import Foundation

/// Revision-checked replacement of an existing Expense's entry fields.
/// The provider must atomically reject collected sources and stale revisions;
/// a missing paid-Invoice projection is not permission to edit.
public struct EditExpenseCommand: Codable, Sendable {
    public struct Payload: Codable, Equatable, Sendable {
        public let expectedRevision: Int64
        public let entry: BusinessPaidExpenseDraft

        public init(expectedRevision: Int64, entry: BusinessPaidExpenseDraft) throws {
            guard expectedRevision > 0, expectedRevision < Int64.max else {
                throw Failure.invalidRevision
            }
            self.expectedRevision = expectedRevision
            self.entry = entry
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(expectedRevision: c.decode(Int64.self, forKey: .expectedRevision),
                          entry: c.decode(BusinessPaidExpenseDraft.self, forKey: .entry))
        }
        private enum CodingKeys: String, CodingKey { case expectedRevision, entry }
    }

    public let envelope: OperationEnvelope<Payload>

    public init(operationId: OperationID, actorPrincipalId: PrincipalID,
                capturedAt: Date, expectedRevision: Int64, entry: BusinessPaidExpenseDraft) throws {
        let milliseconds = (capturedAt.timeIntervalSince1970 * 1000).rounded(.down)
        guard milliseconds.isFinite, milliseconds >= 0, milliseconds < 1_000_000_000_000_000 else {
            throw Failure.invalidEnvelope
        }
        try self.init(envelope: .init(operationId: operationId,
            contractVersion: .init(validating: "expense-edit-v1"), accountId: entry.accountId,
            actorPrincipalId: actorPrincipalId,
            clientCreatedAt: Date(timeIntervalSince1970: milliseconds / 1000),
            payload: .init(expectedRevision: expectedRevision, entry: entry)))
    }

    private init(envelope: OperationEnvelope<Payload>) throws {
        let milliseconds = envelope.clientCreatedAt.timeIntervalSince1970 * 1000
        guard envelope.contractVersion.rawValue == "expense-edit-v1", envelope.preconditions.isEmpty,
              envelope.accountId == envelope.payload.entry.accountId,
              milliseconds.isFinite, milliseconds >= 0, milliseconds < 1_000_000_000_000_000 else {
            throw Failure.invalidEnvelope
        }
        self.envelope = envelope
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(envelope: c.decode(OperationEnvelope<Payload>.self, forKey: .envelope))
    }
    public enum Failure: Error, Equatable, Sendable { case invalidRevision, invalidEnvelope }
    private enum CodingKeys: String, CodingKey { case envelope }
}
