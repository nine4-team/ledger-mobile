import Foundation

/// Creates live demand, never a payment or paid snapshot. Providers must check
/// authorization, source revisions/amounts and exclusive membership atomically.
public struct CreateInvoiceCommand: Codable, Sendable {
    public struct Payload: Codable, Equatable, Sendable {
        public let invoiceId: InvoiceID
        public let selection: LiveInvoiceSelection
        public let name: String
        public let notes: String
        public init(invoiceId: InvoiceID, selection: LiveInvoiceSelection, name: String, notes: String) {
            self.invoiceId = invoiceId; self.selection = selection; self.name = name; self.notes = notes
        }
    }
    public let envelope: OperationEnvelope<Payload>

    public init(operationId: OperationID, actorPrincipalId: PrincipalID, capturedAt: Date, payload: Payload) throws {
        let milliseconds = (capturedAt.timeIntervalSince1970 * 1000).rounded(.down)
        guard milliseconds.isFinite, milliseconds >= 0, milliseconds < 1_000_000_000_000_000 else {
            throw Failure.invalidEnvelope
        }
        try self.init(envelope: .init(operationId: operationId,
            contractVersion: .init(validating: "invoice-create-v1"), accountId: payload.selection.scope.accountId,
            actorPrincipalId: actorPrincipalId,
            clientCreatedAt: Date(timeIntervalSince1970: milliseconds / 1000), payload: payload))
    }
    private init(envelope: OperationEnvelope<Payload>) throws {
        let milliseconds = envelope.clientCreatedAt.timeIntervalSince1970 * 1000
        guard envelope.contractVersion.rawValue == "invoice-create-v1", envelope.preconditions.isEmpty,
              envelope.accountId == envelope.payload.selection.scope.accountId,
              milliseconds.isFinite, milliseconds >= 0, milliseconds < 1_000_000_000_000_000 else {
            throw Failure.invalidEnvelope
        }
        self.envelope = envelope
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(envelope: c.decode(OperationEnvelope<Payload>.self, forKey: .envelope))
    }
    public enum Failure: Error { case invalidEnvelope }
    private enum CodingKeys: String, CodingKey { case envelope }
}
