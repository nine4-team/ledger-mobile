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

/// Full reviewed replacement of a created Invoice's membership and metadata.
/// The authoritative writer must lock the Invoice, require created status and
/// expected revision, and validate all sources before changing any membership.
/// Sent/paid/canceled editing is deliberately not authorized by this command.
public struct ReviseCreatedInvoiceCommand: Codable, Sendable {
    public struct Payload: Codable, Equatable, Sendable {
        public let invoice: CreateInvoiceCommand.Payload
        public let expectedRevision: Int64
        public init(invoice: CreateInvoiceCommand.Payload, expectedRevision: Int64) throws {
            guard expectedRevision > 0, expectedRevision < Int64.max else { throw Failure.invalidRevision }
            self.invoice = invoice; self.expectedRevision = expectedRevision
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(invoice: c.decode(CreateInvoiceCommand.Payload.self, forKey: .invoice),
                expectedRevision: c.decode(Int64.self, forKey: .expectedRevision))
        }
        private enum CodingKeys: String, CodingKey { case invoice, expectedRevision }
    }
    public let envelope: OperationEnvelope<Payload>
    public init(operationId: OperationID, actorPrincipalId: PrincipalID, capturedAt: Date, payload: Payload) throws {
        let normalized = try CreateInvoiceCommand(operationId: operationId, actorPrincipalId: actorPrincipalId,
            capturedAt: capturedAt, payload: payload.invoice).envelope
        try self.init(envelope: .init(operationId: operationId, contractVersion: .init(validating: "invoice-revise-created-v1"),
            accountId: normalized.accountId, actorPrincipalId: actorPrincipalId,
            clientCreatedAt: normalized.clientCreatedAt, payload: payload))
    }
    private init(envelope: OperationEnvelope<Payload>) throws {
        let milliseconds = envelope.clientCreatedAt.timeIntervalSince1970 * 1000
        guard envelope.contractVersion.rawValue == "invoice-revise-created-v1", envelope.preconditions.isEmpty,
              envelope.accountId == envelope.payload.invoice.selection.scope.accountId,
              milliseconds.isFinite, milliseconds >= 0, milliseconds < 1_000_000_000_000_000 else {
            throw Failure.invalidEnvelope
        }
        self.envelope = envelope
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(envelope: c.decode(OperationEnvelope<Payload>.self, forKey: .envelope))
    }
    public enum Failure: Error { case invalidRevision, invalidEnvelope }
    private enum CodingKeys: String, CodingKey { case envelope }
}
