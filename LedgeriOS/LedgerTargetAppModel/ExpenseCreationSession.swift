import Foundation
import LedgerTargetCore
import Observation

/// One immutable retryable save attempt. Receipt durability precedes queue acceptance.
@MainActor @Observable
public final class ExpenseCreationSession {
    public enum Failure: Error { case invalidCaptures, changedAttempt, saving, invalidReceipt }
    public private(set) var isSaving = false
    public private(set) var hasAttempt = false
    public private(set) var receipt: OperationReceipt?
    public var vendor = ""
    public var date = Date()
    public var amountText = ""
    public var notes = ""
    public var categoryId: BudgetCategoryID?
    public typealias ReceiptLineInput = ExpenseEntryRecovery.Line
    public var receiptLineInputs: [ReceiptLineInput] = []
    public enum ReceiptLineInputFailure: Error { case invalidQuantity }

    public func receiptLines(currency: CurrencyCode) throws -> [NonItemReceiptLine] {
        try receiptLineInputs.map { input in
            let text = input.quantityText.trimmingCharacters(in: .whitespacesAndNewlines)
            let quantity: Int64?
            if text.isEmpty { quantity = nil }
            else {
                let digits = text.hasPrefix("-") ? text.dropFirst() : text[...]
                guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int64(text) else {
                    throw ReceiptLineInputFailure.invalidQuantity
                }
                quantity = value
            }
            return try .init(id: .init(validating: input.sourceLineId ?? input.id.uuidString.lowercased()),
                description: .init(validating: input.description),
                magnitude: Money.parsePositiveEntry(input.amountText, currency: currency),
                effect: input.effect, quantity: quantity)
        }
    }
    public private(set) var receiptCaptures: [LocalAttachmentCapture] = []
    public private(set) var unconfirmedReceiptIds: [AttachmentID] = []
    public private(set) var hasStoredReceiptFiles = false
    private let service: any ExpenseCreating
    public private(set) var savedEntry: ExpenseEntryRecovery?
    private var attempt: Attempt?
    private struct Attempt: Equatable {
        let draft: BusinessPaidExpenseDraft
        let captures: [LocalAttachmentCapture]
        let uuid: UUID
        let capturedAt: Date
        let recovery: ExpenseEntryRecovery
    }

    public init(service: any ExpenseCreating) { self.service = service }

    public func loadForEditing(_ expense: ProjectExpenses.Expense, timeZone: TimeZone = .current) throws {
        guard !hasAttempt, !isSaving, expense.collectedInvoice == nil else { throw Failure.changedAttempt }
        let entry = expense.entry
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        guard let parsed = formatter.date(from: entry.date) else { throw Failure.invalidReceipt }
        vendor = entry.vendor; date = parsed; notes = entry.notes; categoryId = entry.categoryId
        amountText = Self.amountEntry(entry.finalAmount)
        receiptLineInputs = entry.receiptLines.map { line in
            var input = ReceiptLineInput()
            input.sourceLineId = line.id.rawValue
            input.description = line.description.rawValue
            input.amountText = Self.amountEntry(line.magnitude)
            input.effect = line.effect; input.quantityText = line.quantity.map(String.init) ?? ""
            return input
        }
    }

    private static func amountEntry(_ value: Money) -> String {
        let units = value.minorUnits
        return "\(units / 100).\(String(format: "%02lld", units % 100))"
    }

    private var editAttempt: EditAttempt?
    private struct EditAttempt: Equatable {
        let entry: BusinessPaidExpenseDraft
        let revision: Int64
        let uuid: UUID
        let date: Date
    }

    public func saveEdit(_ entry: BusinessPaidExpenseDraft, expectedRevision: Int64,
                         operationUUID: UUID, capturedAt: Date) async throws -> OperationReceipt {
        guard !isSaving else { throw Failure.saving }
        guard let editor = service as? any ExpenseEditing, attempt == nil else { throw Failure.changedAttempt }
        let requested = EditAttempt(entry: entry, revision: expectedRevision, uuid: operationUUID, date: capturedAt)
        if let editAttempt { guard editAttempt == requested else { throw Failure.changedAttempt } }
        if let receipt { return receipt }
        editAttempt = requested; hasAttempt = true; isSaving = true
        defer { isSaving = false }
        let accepted = try await editor.editExpense(entry, expectedRevision: expectedRevision,
            operationUUID: operationUUID, capturedAt: capturedAt, recovery: savedEntry)
        receipt = accepted
        return accepted
    }

    public func addReceipt(bytes: Data, fileName: String, projectId: ProjectID, expenseId: ExpenseID,
                           beforeCapture: @MainActor (LocalAttachmentCapture) async throws -> Void = { _ in }) async throws {
        guard !hasAttempt, !isSaving else { throw Failure.changedAttempt }
        let scope = try await service.expenseAttachmentCaptureScope(projectId: projectId, expenseId: expenseId)
        let id = try AttachmentID(validating: UUID().uuidString.lowercased())
        let instant = try AttachmentEpochMilliseconds(validating: Int64(Date().timeIntervalSince1970 * 1000))
        let capture = try await Task.detached {
            try AttachmentCapturePreparation.prepare(bytes: bytes, fileName: fileName, allowsPDF: true,
                attachmentId: id, scope: scope, transactionSection: nil, capturedAt: instant)
        }.value
        try await beforeCapture(capture)
        hasStoredReceiptFiles = true
        unconfirmedReceiptIds.append(capture.attachmentId)
        let saved = try await service.captureAttachment(capture)
        guard saved.attachmentId == capture.attachmentId, saved.scope == capture.scope,
              saved.contentSHA256 == capture.contentSHA256, saved.byteCount == capture.byteCount else { throw Failure.invalidReceipt }
        receiptCaptures.append(capture)
        unconfirmedReceiptIds.removeAll { $0 == capture.attachmentId }
    }

    public func restoreForEditing(_ entry: ExpenseEntryRecovery, source: ProjectExpenses.Expense) async throws {
        guard let context = entry.editContext,
              source.collectedInvoice == nil, source.revision == context.expectedRevision,
              source.entry.accountId == entry.accountId, source.entry.projectId == entry.projectId,
              source.id == entry.expenseId,
              source.entry.receiptAttachmentIds == context.retainedAttachmentIds,
              Set(entry.attachmentIds).isDisjoint(with: context.retainedAttachmentIds) else {
            throw ExpenseEntryRecoveryFailure.staleEntry
        }
        try await restore(entry)
    }

    public func restore(_ entry: ExpenseEntryRecovery) async throws {
        guard !hasAttempt, !isSaving else { throw Failure.changedAttempt }
        savedEntry = entry
        hasStoredReceiptFiles = !entry.attachmentIds.isEmpty
        unconfirmedReceiptIds = entry.attachmentIds
        let captures = try await restoredCaptures(entry)
        vendor = entry.vendor; date = entry.date; amountText = entry.amountText; notes = entry.notes
        categoryId = entry.categoryId; receiptLineInputs = entry.lines
        receiptCaptures = captures
        unconfirmedReceiptIds = []
    }

    public func retryReceiptRecovery() async throws {
        guard !hasAttempt, !isSaving, let savedEntry else { throw Failure.changedAttempt }
        let captures = try await restoredCaptures(savedEntry)
        receiptCaptures = captures
        unconfirmedReceiptIds = []
    }

    private func restoredCaptures(_ entry: ExpenseEntryRecovery) async throws -> [LocalAttachmentCapture] {
        let captures = try await service.restoreExpenseEntryCaptures(entry)
        guard captures.map(\.attachmentId) == entry.attachmentIds,
              captures.allSatisfy({ $0.scope.accountId == entry.accountId && $0.scope.parent.kind == .expense
                  && $0.scope.parent.id.rawValue == entry.expenseId.rawValue }) else { throw Failure.invalidCaptures }
        return captures
    }

    public func persistEntry(_ entry: ExpenseEntryRecovery) async throws {
        try await service.saveExpenseEntry(entry, replacing: savedEntry)
        savedEntry = entry
    }

    /// Removes only the draft selection; protected files remain in the existing recovery queue.
    public func removeReceipt(_ id: AttachmentID) {
        guard !hasAttempt, !isSaving else { return }
        receiptCaptures.removeAll { $0.attachmentId == id }
    }

    public func save(draft: BusinessPaidExpenseDraft, captures: [LocalAttachmentCapture],
                     operationUUID: UUID, capturedAt: Date, recovery: ExpenseEntryRecovery) async throws -> OperationReceipt {
        guard !isSaving else { throw Failure.saving }
        guard unconfirmedReceiptIds.isEmpty else { throw Failure.invalidCaptures }
        guard recovery.editContext == nil,
              recovery.accountId == draft.accountId, recovery.projectId == draft.projectId,
              recovery.expenseId == draft.expenseId, recovery.operationUUID == operationUUID,
              recovery.capturedAt == Date(timeIntervalSince1970: (capturedAt.timeIntervalSince1970 * 1000).rounded(.down) / 1000),
              recovery.attachmentIds == draft.receiptAttachmentIds else {
            throw Failure.invalidCaptures
        }
        let requested = Attempt(draft: draft, captures: captures, uuid: operationUUID, capturedAt: capturedAt, recovery: recovery)
        if let attempt { guard attempt == requested else { throw Failure.changedAttempt } }
        guard captures.map(\.attachmentId) == draft.receiptAttachmentIds,
              captures.allSatisfy({ $0.scope.accountId == draft.accountId && $0.scope.parent.kind == .expense
                && $0.scope.parent.id.rawValue == draft.expenseId.rawValue }) else { throw Failure.invalidCaptures }
        if let receipt { return receipt }
        isSaving = true
        defer { isSaving = false }
        // Keep the latest form before freezing an attempt. If acceptance fails,
        // Close/reopen must recover these edits, including forms without media.
        if attempt == nil { try await persistEntry(recovery) }
        attempt = requested; hasAttempt = true
        for capture in captures {
            let saved = try await service.captureAttachment(capture)
            guard saved.attachmentId == capture.attachmentId, saved.scope == capture.scope,
                  saved.contentSHA256 == capture.contentSHA256, saved.byteCount == capture.byteCount else {
                throw Failure.invalidReceipt
            }
        }
        let accepted = try await service.createExpense(draft, operationUUID: operationUUID, capturedAt: capturedAt, recovery: savedEntry)
        receipt = accepted
        return accepted
    }
}
