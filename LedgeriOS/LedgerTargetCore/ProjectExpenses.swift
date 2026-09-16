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
    public struct PendingEdit: Equatable, Sendable, Identifiable {
        public let id: OperationID
        public let entry: BusinessPaidExpenseDraft
        public let expectedRevision: Int64
        public let state: LocalOperationState
        public init(id: OperationID, entry: BusinessPaidExpenseDraft, expectedRevision: Int64, state: LocalOperationState) throws {
            guard expectedRevision > 0, expectedRevision < Int64.max,
                  [.queued, .applying, .applied, .rejected].contains(state) else { throw Failure.invalidEvidence }
            self.id = id; self.entry = entry; self.expectedRevision = expectedRevision; self.state = state
        }
    }
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
        public let liveInvoice: LiveInvoiceContents?
        public let invoiceMembershipComplete: Bool
        public var availability: InvoicingAvailability? {
            if collectedInvoice != nil { return .paid }
            if let liveInvoice { return liveInvoice.status == .created ? .created : .sent }
            return invoiceMembershipComplete ? .available : nil
        }
        public init(entry: BusinessPaidExpenseDraft, revision: Int64, currentCategoryName: String? = nil,
                    receiptObjects: [DownloadedMediaObjectReference] = [], collectedInvoice: FrozenInvoiceContents? = nil,
                    liveInvoice: LiveInvoiceContents? = nil, invoiceMembershipComplete: Bool = false) throws {
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
            if let invoice = liveInvoice {
                let lines = invoice.lines.filter { $0.selection.source == .expense(entry.expenseId) }
                guard collectedInvoice == nil, invoice.selection.scope.accountId == entry.accountId,
                      invoice.selection.scope.projectId == entry.projectId, lines.count == 1,
                      lines[0].selection.expectedRevision == revision,
                      lines[0].selection.reviewedAmount == entry.finalAmount else { throw Failure.invalidEvidence }
            }
            self.liveInvoice = liveInvoice
            self.invoiceMembershipComplete = invoiceMembershipComplete
        }
    }
    public let accountId: AccountID
    public let projectId: ProjectID
    public let expenses: [Expense]
    public let pendingCreations: [PendingCreation]
    public let pendingEdits: [PendingEdit]
    public let unfinishedEntries: [ExpenseEntryRecovery]
    public let unfinishedEdits: [ExpenseEntryRecovery]
    public init(accountId: AccountID, projectId: ProjectID, expenses: [Expense], pendingCreations: [PendingCreation] = [], pendingEdits: [PendingEdit] = [], unfinishedEntries: [ExpenseEntryRecovery] = [], unfinishedEdits: [ExpenseEntryRecovery] = []) throws {
        guard expenses.allSatisfy({ $0.entry.accountId == accountId && $0.entry.projectId == projectId }),
              Set(expenses.map(\.id)).count == expenses.count,
              pendingCreations.allSatisfy({ $0.entry.accountId == accountId && $0.entry.projectId == projectId }),
              Set(pendingCreations.map(\.id)).count == pendingCreations.count else { throw Failure.invalidEvidence }
        self.accountId = accountId; self.projectId = projectId; self.expenses = expenses
        self.pendingCreations = pendingCreations
        guard pendingEdits.allSatisfy({ $0.entry.accountId == accountId && $0.entry.projectId == projectId }),
              Set(pendingEdits.map(\.id)).count == pendingEdits.count,
              Set(pendingCreations.map(\.id)).isDisjoint(with: pendingEdits.map(\.id)) else { throw Failure.invalidEvidence }
        self.pendingEdits = pendingEdits
        guard unfinishedEntries.allSatisfy({ $0.accountId == accountId && $0.projectId == projectId && $0.editContext == nil }),
              unfinishedEdits.allSatisfy({ $0.accountId == accountId && $0.projectId == projectId && $0.editContext != nil }),
              Set(unfinishedEntries.map(\.id) + unfinishedEdits.map(\.id)).count == unfinishedEntries.count + unfinishedEdits.count
        else { throw Failure.invalidEvidence }
        self.unfinishedEntries = unfinishedEntries
        self.unfinishedEdits = unfinishedEdits
    }
    public enum Failure: Error, Equatable, Sendable { case invalidEvidence }
}
