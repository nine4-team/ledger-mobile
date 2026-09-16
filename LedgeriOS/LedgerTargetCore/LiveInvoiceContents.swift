import Foundation

public protocol ProjectLiveInvoiceReading: Sendable {
    func readLiveInvoices(accountId: AccountID, projectId: ProjectID) async throws -> [LiveInvoiceContents]
    func watchLiveInvoices(accountId: AccountID, projectId: ProjectID) -> AsyncThrowingStream<[LiveInvoiceContents]?, Error>
}

public protocol ProjectInvoiceCreating: ProjectLiveInvoiceReading {
    func createInvoice(_ payload: CreateInvoiceCommand.Payload, operationUUID: UUID, capturedAt: Date) async throws -> OperationReceipt
    func readPendingInvoiceCreations(accountId: AccountID, projectId: ProjectID) async throws -> [PendingInvoiceCreation]
    func readInvoiceCreationReview(accountId: AccountID, projectId: ProjectID) async throws -> InvoiceCreationReview
}

public struct InvoiceCreationReview: Equatable, Sendable {
    public let scope: TransactionScope
    public let candidates: [LiveInvoiceContents.Line]
    public let categoryNames: [BudgetCategoryID: String]
    public init(scope: TransactionScope, candidates: [LiveInvoiceContents.Line], categoryNames: [BudgetCategoryID: String] = [:]) {
        self.scope = scope; self.candidates = candidates; self.categoryNames = categoryNames
    }
}

/// Locally accepted intent, not authoritative Invoice membership or a payment.
public struct PendingInvoiceCreation: Identifiable, Equatable, Sendable {
    public let id: OperationID
    public let payload: CreateInvoiceCommand.Payload
    public let state: LocalOperationState
    public init(id: OperationID, payload: CreateInvoiceCommand.Payload, state: LocalOperationState) {
        self.id = id; self.payload = payload; self.state = state
    }
}

/// Current source facts for an uncollected Invoice; never a paid snapshot.
public struct LiveInvoiceContents: Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case created, sent }
    public struct Line: Equatable, Sendable {
        public let selection: LiveInvoiceSelection.Line
        public let categoryId: BudgetCategoryID
        public let description: String

        public init(selection: LiveInvoiceSelection.Line, categoryId: BudgetCategoryID, description: String) {
            self.selection = selection; self.categoryId = categoryId; self.description = description
        }
    }
    public let invoiceId: InvoiceID
    public let revision: Int64
    public let status: Status
    public let name: String
    public let notes: String
    public let selection: LiveInvoiceSelection
    public let lines: [Line]
    public var total: Money { selection.reviewedTotal }

    public init(invoiceId: InvoiceID, revision: Int64, status: Status, name: String, notes: String,
                scope: TransactionScope, lines: [Line], reportedTotal: Money) throws {
        guard revision > 0 else { throw Failure.invalidRevision }
        let selection = try LiveInvoiceSelection(scope: scope, lines: lines.map(\.selection))
        guard selection.reviewedTotal == reportedTotal else { throw Failure.totalMismatch }
        self.invoiceId = invoiceId; self.revision = revision; self.status = status
        self.name = name; self.notes = notes; self.selection = selection; self.lines = lines
    }
    public enum Failure: Error, Equatable, Sendable { case invalidRevision, totalMismatch }
}
