import Foundation

/// Frozen accounting contents plus the evidence of the authorized read used
/// for a report. Branding/category labels remain separate presentation inputs.
public struct CollectedInvoiceReportSnapshot: Encodable, Equatable, Sendable {
    public let invoice: FrozenInvoiceContents
    public let provenance: PropertyManagementReportProvenance
    public init(invoice: FrozenInvoiceContents, provenance: PropertyManagementReportProvenance) throws {
        guard invoice.scope.accountId == provenance.accountId,
              invoice.scope.projectId == provenance.projectId,
              provenance.readiness == .ready else { throw ProjectExpenses.Failure.invalidEvidence }
        self.invoice = invoice
        self.provenance = provenance
    }
}

/// Read boundary shared by the Invoicing presentation and offline provider.
/// Nil watch values mean unavailable, never a confirmed empty collection.
public protocol ProjectInvoicingReading: ProjectInvoicingChargeReading {
    func readCollectedInvoiceReport(accountId: AccountID, projectId: ProjectID, invoiceId: InvoiceID,
        asOf: ProtectedArtifactEpochMilliseconds) async throws -> CollectedInvoiceReportSnapshot
    /// Paid contents only; this does not assert coverage of live/canceled Invoices.
    func readCollectedInvoices(accountId: AccountID, projectId: ProjectID) async throws -> [FrozenInvoiceContents]
    func watchCollectedInvoices(accountId: AccountID, projectId: ProjectID, invoiceId: InvoiceID?) -> AsyncThrowingStream<[FrozenInvoiceContents]?, Error>
    func readExpenses(accountId: AccountID, projectId: ProjectID) async throws -> ProjectExpenses
    func watchExpenses(accountId: AccountID, projectId: ProjectID) -> AsyncThrowingStream<ProjectExpenses?, Error>
    func loadExpenseReceipt(projectId: ProjectID, expenseId: ExpenseID, attachmentId: AttachmentID,
                            allowDownload: Bool) async throws -> Data?
}

/// Canonical Expense sources; Invoice membership is a separate relationship.
public extension ProjectInvoicingReading {
    func watchCollectedInvoices(accountId: AccountID, projectId: ProjectID) -> AsyncThrowingStream<[FrozenInvoiceContents]?, Error> {
        watchCollectedInvoices(accountId: accountId, projectId: projectId, invoiceId: nil)
    }
}

public struct ProjectExpenses: Equatable, Sendable {
    /// Accepted local intent, kept separate from authoritative accounting facts.
    public struct PendingCreation: Equatable, Sendable, Identifiable {
        public let id: OperationID
        public let entry: BusinessPaidExpenseDraft
        public let state: LocalOperationState
        public init(id: OperationID, entry: BusinessPaidExpenseDraft, state: LocalOperationState) throws {
            guard [.queued, .applying, .applied, .rejected].contains(state) else { throw Failure.invalidEvidence }
            self.id = id; self.entry = entry; self.state = state
        }
    }
    public struct Expense: Equatable, Sendable, Identifiable {
        public var id: ExpenseID { entry.expenseId }
        public let entry: BusinessPaidExpenseDraft
        public let revision: Int64
        public let currentCategoryName: String?
        /// Downloaded metadata only; missing objects do not remove receipt references.
        public let receiptObjects: [DownloadedMediaObjectReference]
        /// Positive paid evidence only. Nil does not mean available/unpaid:
        /// live Invoice membership has its own completeness requirements.
        public let collectedInvoice: FrozenInvoiceContents?
        public init(entry: BusinessPaidExpenseDraft, revision: Int64, currentCategoryName: String? = nil,
                    receiptObjects: [DownloadedMediaObjectReference] = [], collectedInvoice: FrozenInvoiceContents? = nil) throws {
            guard revision > 0, Set(receiptObjects.map(\.attachmentId)).count == receiptObjects.count,
                  receiptObjects.allSatisfy({ $0.accountId == entry.accountId && entry.receiptAttachmentIds.contains($0.attachmentId) })
            else { throw Failure.invalidEvidence }
            if let invoice = collectedInvoice {
                let lines = invoice.lines.filter { $0.source == .expense(expenseId: entry.expenseId) }
                guard invoice.scope.accountId == entry.accountId, invoice.scope.projectId == entry.projectId,
                      lines.count == 1, let line = lines.first,
                      line.sourceRevision == revision, line.signedAmount == entry.finalAmount else {
                    throw Failure.invalidEvidence
                }
            }
            self.entry = entry; self.revision = revision
            self.currentCategoryName = currentCategoryName
            self.receiptObjects = receiptObjects
            self.collectedInvoice = collectedInvoice
        }
    }
    public let accountId: AccountID
    public let projectId: ProjectID
    public let expenses: [Expense]
    public let pendingCreations: [PendingCreation]
    public let unfinishedEntries: [ExpenseEntryRecovery]
    public init(accountId: AccountID, projectId: ProjectID, expenses: [Expense], pendingCreations: [PendingCreation] = [], unfinishedEntries: [ExpenseEntryRecovery] = []) throws {
        guard expenses.allSatisfy({ $0.entry.accountId == accountId && $0.entry.projectId == projectId }),
              Set(expenses.map(\.id)).count == expenses.count,
              pendingCreations.allSatisfy({ $0.entry.accountId == accountId && $0.entry.projectId == projectId }),
              Set(pendingCreations.map(\.id)).count == pendingCreations.count else { throw Failure.invalidEvidence }
        self.accountId = accountId; self.projectId = projectId; self.expenses = expenses
        self.pendingCreations = pendingCreations
        guard unfinishedEntries.allSatisfy({ $0.accountId == accountId && $0.projectId == projectId }) else { throw Failure.invalidEvidence }
        self.unfinishedEntries = unfinishedEntries
    }
    public enum Failure: Error, Equatable, Sendable { case invalidEvidence }
}
