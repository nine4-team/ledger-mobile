import Foundation

public protocol ExpenseEditing: Sendable {
    func editExpense(_ entry: BusinessPaidExpenseDraft, expectedRevision: Int64,
                     operationUUID: UUID, capturedAt: Date, recovery: ExpenseEntryRecovery?) async throws -> OperationReceipt
}

public extension ExpenseEditing {
    func editExpense(_ entry: BusinessPaidExpenseDraft, expectedRevision: Int64,
                     operationUUID: UUID, capturedAt: Date) async throws -> OperationReceipt {
        try await editExpense(entry, expectedRevision: expectedRevision, operationUUID: operationUUID,
            capturedAt: capturedAt, recovery: nil)
    }
}

/// Creation capabilities only; this does not authorize editing or collection.
public protocol ExpenseCreating: Sendable {
    func watchBudgetCategories() -> AsyncThrowingStream<BudgetCategoryReferenceSnapshot, Error>
    func expenseAttachmentCaptureScope(projectId: ProjectID, expenseId: ExpenseID) async throws -> AttachmentCaptureScope
    func captureAttachment(_ capture: LocalAttachmentCapture) async throws -> AttachmentLocalDurabilityReceipt
    func createExpense(_ draft: BusinessPaidExpenseDraft, operationUUID: UUID, capturedAt: Date, recovery: ExpenseEntryRecovery?) async throws -> OperationReceipt
    func saveExpenseEntry(_ entry: ExpenseEntryRecovery, replacing previous: ExpenseEntryRecovery?) async throws
    func restoreExpenseEntryCaptures(_ entry: ExpenseEntryRecovery) async throws -> [LocalAttachmentCapture]
}

public extension ExpenseCreating {
    func createExpense(_ draft: BusinessPaidExpenseDraft, operationUUID: UUID, capturedAt: Date) async throws -> OperationReceipt {
        try await createExpense(draft, operationUUID: operationUUID, capturedAt: capturedAt, recovery: nil)
    }
    func saveExpenseEntry(_ entry: ExpenseEntryRecovery) async throws {
        try await saveExpenseEntry(entry, replacing: nil)
    }
}

public enum ExpenseEntryRecoveryFailure: Error { case staleEntry }

/// Unsubmitted form state, not an Expense fact or an upload command.
public struct ExpenseEntryRecovery: Codable, Equatable, Sendable, Identifiable {
    /// Captured files for an edit belong to the original revision, never a new Expense.
    public struct EditContext: Codable, Equatable, Sendable {
        public let expectedRevision: Int64
        public let retainedAttachmentIds: [AttachmentID]
        public init(expectedRevision: Int64, retainedAttachmentIds: [AttachmentID]) throws {
            guard expectedRevision > 0, expectedRevision < Int64.max else {
                throw EditExpenseCommand.Failure.invalidRevision
            }
            guard Set(retainedAttachmentIds).count == retainedAttachmentIds.count else {
                throw BusinessPaidExpenseDraft.Failure.duplicateAttachment
            }
            self.expectedRevision = expectedRevision
            self.retainedAttachmentIds = retainedAttachmentIds
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(expectedRevision: c.decode(Int64.self, forKey: .expectedRevision),
                retainedAttachmentIds: c.decode([AttachmentID].self, forKey: .retainedAttachmentIds))
        }
        private enum CodingKeys: String, CodingKey { case expectedRevision, retainedAttachmentIds }
    }
    public struct Line: Codable, Equatable, Sendable, Identifiable {
        public let id: UUID
        /// Existing receipt-line identity may come from migration and need not be a UUID.
        public var sourceLineId: String?
        public var description = ""
        public var amountText = ""
        public var effect: NonItemReceiptLineEffect = .increase
        public var quantityText = ""
        public init(id: UUID = UUID()) { self.id = id }
    }
    public var id: ExpenseID { expenseId }
    public let accountId: AccountID
    public let projectId: ProjectID
    public let expenseId: ExpenseID
    public let operationUUID: UUID
    public let capturedAt: Date
    public let editContext: EditContext?
    public var vendor: String
    public var date: Date
    public var amountText: String
    public var notes: String
    public var categoryId: BudgetCategoryID?
    public var lines: [Line]
    public var attachmentIds: [AttachmentID]
    public init(accountId: AccountID, projectId: ProjectID, expenseId: ExpenseID, operationUUID: UUID,
                capturedAt: Date, vendor: String, date: Date, amountText: String, notes: String,
                categoryId: BudgetCategoryID?, lines: [Line], attachmentIds: [AttachmentID],
                editContext: EditContext? = nil) {
        self.accountId = accountId; self.projectId = projectId; self.expenseId = expenseId
        self.operationUUID = operationUUID
        self.editContext = editContext
        self.capturedAt = Date(timeIntervalSince1970: (capturedAt.timeIntervalSince1970 * 1000).rounded(.down) / 1000)
        self.vendor = vendor
        self.date = Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded(.down) / 1000)
        self.amountText = amountText; self.notes = notes; self.categoryId = categoryId
        self.lines = lines; self.attachmentIds = attachmentIds
    }
}
