import Foundation

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
    public struct Line: Codable, Equatable, Sendable, Identifiable {
        public let id: UUID
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
    public var vendor: String
    public var date: Date
    public var amountText: String
    public var notes: String
    public var categoryId: BudgetCategoryID?
    public var lines: [Line]
    public var attachmentIds: [AttachmentID]
    public init(accountId: AccountID, projectId: ProjectID, expenseId: ExpenseID, operationUUID: UUID,
                capturedAt: Date, vendor: String, date: Date, amountText: String, notes: String,
                categoryId: BudgetCategoryID?, lines: [Line], attachmentIds: [AttachmentID]) {
        self.accountId = accountId; self.projectId = projectId; self.expenseId = expenseId
        self.operationUUID = operationUUID
        self.capturedAt = Date(timeIntervalSince1970: (capturedAt.timeIntervalSince1970 * 1000).rounded(.down) / 1000)
        self.vendor = vendor
        self.date = Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded(.down) / 1000)
        self.amountText = amountText; self.notes = notes; self.categoryId = categoryId
        self.lines = lines; self.attachmentIds = attachmentIds
    }
}
