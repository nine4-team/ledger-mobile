import LedgerTargetAppModel
import LedgerTargetCore
import SwiftUI

/// Expense-specific fields composed from the existing form and attachment controls.
struct ExpenseCreationView: View {
    let accountId: AccountID
    let projectId: ProjectID
    let currency: CurrencyCode
    let service: any ExpenseCreating
    let onSaved: (OperationReceipt) -> Void
    let recovery: ExpenseEntryRecovery?
    @Environment(\.dismiss) private var dismiss
    @State private var session: ExpenseCreationSession
    @State private var operationUUID = UUID()
    @State private var expenseUUID = UUID()
    @State private var capturedAt = Date()
    @State private var categories: [BudgetCategoryDefinitionSnapshot] = []
    @State private var ready = false
    @State private var saving = false
    @State private var error: String?
    @State private var choosingReceipt = false
    @State private var importingReceipt = false
    @State private var prepared: [LocalAttachmentCapture]?
    @State private var frozenDraft: BusinessPaidExpenseDraft?
    @State private var restoring = false
    @State private var recoveryFailed = false

    init(accountId: AccountID, projectId: ProjectID, currency: CurrencyCode,
         service: any ExpenseCreating, recovery: ExpenseEntryRecovery? = nil, onSaved: @escaping (OperationReceipt) -> Void) {
        self.accountId = accountId; self.projectId = projectId; self.currency = currency
        self.service = service; self.onSaved = onSaved
        self.recovery = recovery
        _session = State(initialValue: ExpenseCreationSession(service: service))
        if let recovery {
            _operationUUID = State(initialValue: recovery.operationUUID)
            _capturedAt = State(initialValue: recovery.capturedAt)
        }
    }

    var body: some View {
        FormSheet(title: "New Expense", showDismissButton: false,
            primaryAction: FormSheetAction(title: session.hasAttempt ? "Retry Save" : "Save", isLoading: saving,
                isDisabled: saving || importingReceipt || restoring || recoveryFailed || !session.unconfirmedReceiptIds.isEmpty || !ready || session.categoryId == nil, action: save),
            secondaryAction: FormSheetAction(title: session.hasAttempt ? "Close" : recovery != nil || session.hasStoredReceiptFiles ? "Save for later" : "Cancel",
                isDisabled: saving || importingReceipt || restoring, action: close), error: error) {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    FormField(label: "Vendor", text: $session.vendor, placeholder: "Vendor")
                    FormDateField(label: "Date", date: $session.date)
                    FormField(label: "Amount (\(currency.rawValue))", text: $session.amountText, placeholder: "0.00")
                    Picker("Budget category", selection: $session.categoryId) {
                        Text("Choose budget category").tag(Optional<BudgetCategoryID>.none)
                        ForEach(categories, id: \.id) { row in Text(row.name.rawValue).tag(Optional(row.id)) }
                    }
                    .accessibilityIdentifier("target-expense-category")
                    FormField(label: "Notes", text: $session.notes, placeholder: "Notes", axis: .vertical)
                    Text("Other receipt lines").font(.headline)
                    ForEach($session.receiptLineInputs) { $line in
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            FormField(label: "Description", text: $line.description, placeholder: "Receipt wording")
                            FormField(label: "Line total", text: $line.amountText, placeholder: "Line amount")
                            Picker("Effect", selection: $line.effect) {
                                Text("Increase").tag(NonItemReceiptLineEffect.increase)
                                Text("Decrease").tag(NonItemReceiptLineEffect.decrease)
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("target-expense-line-effect-\(line.id.uuidString.lowercased())")
                            FormField(label: "Quantity (optional)", text: $line.quantityText, placeholder: "Quantity")
                            Button("Remove line") {
                                let id = line.id
                                session.receiptLineInputs.removeAll { $0.id == id }
                            }
                        }
                    }
                    Button("Add receipt line") { session.receiptLineInputs.append(.init()) }
                    Text("Line amounts describe the receipt. They do not change the Expense amount or create Items.").font(.caption)
                    Button("Add receipt") { choosingReceipt = true }
                    ForEach(session.receiptCaptures, id: \.attachmentId) { upload in
                        HStack {
                            Text(upload.metadata?.fileName ?? "Receipt")
                            Spacer()
                            Button("Remove selection") { session.removeReceipt(upload.attachmentId) }
                        }
                    }
                    Text("This records a business-paid cost, not a client payment.").font(.caption)
                    if !ready { Text("Download budget categories before saving.").font(.caption) }
                    if session.hasAttempt { Text("This save is kept unchanged for a safe retry.").font(.caption) }
                }
                .disabled(saving || restoring || recoveryFailed || !session.unconfirmedReceiptIds.isEmpty || frozenDraft != nil)
                if (recoveryFailed || !session.unconfirmedReceiptIds.isEmpty), !session.hasAttempt {
                    Button("Retry receipt recovery") {
                        restoring = true
                        Task {
                            defer { restoring = false }
                            do {
                                if recoveryFailed, let entry = session.savedEntry { try await session.restore(entry) }
                                else { try await session.retryReceiptRecovery() }
                                recoveryFailed = false; error = nil
                            } catch { self.error = "The receipt is still unavailable. Its saved reference is retained; no Expense was submitted." }
                        }
                    }
                    .disabled(restoring || saving || importingReceipt)
                }
            }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("target-expense-form")
        #if DEBUG
        .accessibilityValue(expenseUUID.uuidString)
        #endif
        .interactiveDismissDisabled(saving || importingReceipt || restoring || recovery != nil || session.hasAttempt || session.hasStoredReceiptFiles)
        .modifier(MediaCapturePresentation(showAddSourceMenu: $choosingReceipt, isUploading: $importingReceipt,
            uploadError: $error, remainingSlots: max(0, 50 - session.receiptCaptures.count), allowedKinds: [.image, .pdf],
            onUploadAttachmentFile: { try await addReceipt($0.data, name: $0.displayFileName) },
            onUploadDocument: { try await addReceipt($0, name: $1) }, allowsImagePaste: true))
        .task {
            guard let recovery else { return }
            restoring = true
            defer { restoring = false }
            do { try await session.restore(recovery) }
            catch { recoveryFailed = true; self.error = "The saved form is retained, but a receipt could not be restored. Saving is disabled to avoid losing its references." }
        }
        .task {
            do {
                for try await snapshot in service.watchBudgetCategories() {
                    try Task.checkCancellation()
                    guard snapshot.accountId == accountId else { break }
                    ready = snapshot.local.isCompleteForQuery
                    categories = snapshot.local.rows.filter { $0.kind == .general && $0.lifecycle == .active }
                }
            } catch { }
            if !Task.isCancelled { ready = false; categories = [] }
        }
    }

    private func addReceipt(_ data: Data, name: String) async throws {
        try await session.addReceipt(bytes: data, fileName: name, projectId: projectId,
            expenseId: recovery?.expenseId ?? ExpenseID(validating: expenseUUID.uuidString.lowercased()), beforeCapture: { capture in
                try await session.persistEntry(recoverySnapshot(additionalAttachment: capture.attachmentId))
            })
    }

    private func recoverySnapshot(additionalAttachment: AttachmentID? = nil) throws -> ExpenseEntryRecovery {
        .init(accountId: accountId, projectId: projectId, expenseId: try recovery?.expenseId ?? .init(validating: expenseUUID.uuidString.lowercased()),
            operationUUID: operationUUID, capturedAt: capturedAt, vendor: session.vendor, date: session.date,
            amountText: session.amountText, notes: session.notes, categoryId: session.categoryId,
            lines: session.receiptLineInputs, attachmentIds: session.receiptCaptures.map(\.attachmentId)
                + session.unconfirmedReceiptIds + (additionalAttachment.map { [$0] } ?? []))
    }

    private func close() {
        guard !saving, !importingReceipt, !restoring else { return }
        if session.hasAttempt || recoveryFailed || (recovery == nil && !session.hasStoredReceiptFiles) { dismiss(); return }
        saving = true
        Task {
            defer { saving = false }
            do { try await session.persistEntry(recoverySnapshot()); dismiss() }
            catch ExpenseEntryRecoveryFailure.staleEntry {
                recoveryFailed = true
                error = "A newer saved version exists. These edits were not saved. Close and reopen the unfinished Expense."
            } catch { self.error = "The unfinished Expense could not be saved. Keep this form open and retry." }
        }
    }

    private func save() {
        guard !saving else { return }
        saving = true; error = nil
        Task {
            defer { saving = false }
            do {
                if frozenDraft == nil {
                    guard let category = session.categoryId, categories.contains(where: { $0.id == category }) else {
                        error = "Choose an available budget category before saving."
                        return
                    }
                    let formatter = DateFormatter()
                    formatter.calendar = Calendar(identifier: .gregorian)
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.dateFormat = "yyyy-MM-dd"
                    let id = try recovery?.expenseId ?? ExpenseID(validating: expenseUUID.uuidString.lowercased())
                    let draft = try BusinessPaidExpenseDraft(accountId: accountId, projectId: projectId, expenseId: id,
                        vendor: session.vendor, date: formatter.string(from: session.date), finalAmount: Money.parsePositiveEntry(session.amountText, currency: currency),
                        categoryId: category, notes: session.notes,
                        receiptAttachmentIds: session.receiptCaptures.map(\.attachmentId),
                        receiptLines: session.receiptLines(currency: currency))
                    _ = try await service.expenseAttachmentCaptureScope(projectId: projectId, expenseId: id)
                    prepared = session.receiptCaptures
                    frozenDraft = draft
                }
                guard let draft = frozenDraft, let prepared else { return }
                let receipt = try await session.save(draft: draft, captures: prepared, operationUUID: operationUUID,
                    capturedAt: capturedAt, recovery: recoverySnapshot())
                onSaved(receipt); dismiss()
            } catch ExpenseEntryRecoveryFailure.staleEntry {
                recoveryFailed = true
                error = "A newer saved version exists. These edits were not saved. Close and reopen the unfinished Expense."
            } catch is Money.EntryFailure {
                error = "Enter a positive amount with no more than two decimal places."
            } catch is ExpenseCreationSession.ReceiptLineInputFailure {
                error = "Enter a whole-number quantity as printed on the receipt, or leave it blank."
            } catch ReceiptLineReconstructionFailure.invalidDescription {
                error = "Enter a description for each receipt line."
            } catch let failure as AttachmentCapturePreparation.Failure {
                error = failure.localizedDescription
            } catch {
                self.error = "The Expense could not finish saving. Your selected data is retained here for retry."
            }
        }
    }
}
