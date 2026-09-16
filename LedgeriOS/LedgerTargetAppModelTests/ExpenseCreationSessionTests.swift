import Foundation
import LedgerTargetCore
import Testing
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import LedgerTargetAppModel

@MainActor @Suite("Expense form durable submission")
struct ExpenseCreationSessionTests {
    @Test func recoveryRetriesWithoutSubmittingOrPublishingUncheckedFields() async throws {
        let service = Creator(), session = ExpenseCreationSession(service: service)
        let project = try ProjectID(validating: "project"), expense = try ExpenseID(validating: "expense")
        let capture = try LocalAttachmentCapture(attachmentId: .init(validating: "retained"),
            scope: await service.expenseAttachmentCaptureScope(projectId: project, expenseId: expense),
            capturedAt: .init(validating: 1000), bytes: Data([1,2,3]), metadata: nil)
        let entry = ExpenseEntryRecovery(accountId: try .init(validating: "account"), projectId: project,
            expenseId: expense, operationUUID: UUID(), capturedAt: Date(), vendor: "Retained vendor", date: Date(),
            amountText: "12.50", notes: "Retained notes", categoryId: nil, lines: [], attachmentIds: [capture.attachmentId])
        await service.configureRecovery(captures: [capture], failsOnce: true)
        await #expect(throws: Creator.Failure.once) { try await session.restore(entry) }
        #expect(session.vendor.isEmpty)
        #expect(session.savedEntry == entry)
        #expect(session.receiptCaptures.isEmpty)
        #expect(session.unconfirmedReceiptIds == entry.attachmentIds)
        try await session.restore(entry)
        #expect(session.vendor == entry.vendor)
        #expect(session.receiptCaptures == [capture])
        session.notes = "New unsaved wording"
        try await session.retryReceiptRecovery()
        #expect(session.notes == "New unsaved wording")
        #expect(await service.operations.isEmpty)
        await service.configureRecovery(captures: [], failsOnce: false)
        await #expect(throws: ExpenseCreationSession.Failure.invalidCaptures) { try await session.retryReceiptRecovery() }
        #expect(session.receiptCaptures == [capture])
    }

    @Test func receiptLinesKeepIdentitySourceOrderAndExactAmounts() throws {
        let session = ExpenseCreationSession(service: Creator())
        let currency = try CurrencyCode(validating: "USD")
        var shipping = ExpenseCreationSession.ReceiptLineInput()
        shipping.description = "Printed delivery wording"; shipping.amountText = "10.25"; shipping.quantityText = "2"
        var discount = ExpenseCreationSession.ReceiptLineInput()
        discount.description = "Promotion"; discount.amountText = "1.01"; discount.effect = .decrease
        session.receiptLineInputs = [shipping, discount]
        let lines = try session.receiptLines(currency: currency)
        #expect(lines.map(\.id.rawValue) == [shipping.id, discount.id].map { $0.uuidString.lowercased() })
        #expect(lines.map(\.magnitude.minorUnits) == [1025, 101])
        #expect(lines.map(\.effect) == [.increase, .decrease])
        #expect(lines.map(\.quantity) == [2, nil])
        session.receiptLineInputs[0].description = "Corrected wording"
        #expect(try session.receiptLines(currency: currency)[0].id == lines[0].id)
        session.receiptLineInputs[0].quantityText = "-2"
        #expect(try session.receiptLines(currency: currency)[0].quantity == -2)
        session.receiptLineInputs[0].quantityText = "0"
        #expect(try session.receiptLines(currency: currency)[0].quantity == 0)
        session.receiptLineInputs[0].quantityText = "1.5"
        #expect(throws: ExpenseCreationSession.ReceiptLineInputFailure.invalidQuantity) {
            try session.receiptLines(currency: currency)
        }
    }

    @Test func failedSaveWithoutReceiptsKeepsLatestFormForReopening() async throws {
        let service = Creator(), session = ExpenseCreationSession(service: service)
        let account = try AccountID(validating: "account"), project = try ProjectID(validating: "project")
        let expense = try ExpenseID(validating: "expense"), category = try BudgetCategoryID(validating: "general")
        let date = Date(timeIntervalSince1970: 1000.1234567), uuid = UUID()
        let recovery = ExpenseEntryRecovery(accountId: account, projectId: project, expenseId: expense,
            operationUUID: uuid, capturedAt: date, vendor: "Latest vendor", date: date, amountText: "12.50",
            notes: "Latest unsaved notes", categoryId: category, lines: [], attachmentIds: [])
        let draft = try BusinessPaidExpenseDraft(accountId: account, projectId: project, expenseId: expense,
            vendor: recovery.vendor, date: "1970-01-01",
            finalAmount: Money.parsePositiveEntry("12.50", currency: .init(validating: "USD")),
            categoryId: category, notes: recovery.notes, receiptAttachmentIds: [])
        await service.failNextEntry()
        await #expect(throws: Creator.Failure.once) {
            try await session.save(draft: draft, captures: [], operationUUID: uuid, capturedAt: date, recovery: recovery)
        }
        #expect(!session.hasAttempt && !session.isSaving)
        #expect(await service.operations.isEmpty)
        #expect(await service.savedEntries.isEmpty)
        await #expect(throws: Creator.Failure.once) {
            try await session.save(draft: draft, captures: [], operationUUID: uuid, capturedAt: date, recovery: recovery)
        }
        #expect(session.hasAttempt && !session.isSaving)
        #expect(await service.events == ["entry", "entry", "create"])
        let retained = try #require(await service.savedEntries.last)
        #expect(retained == recovery)
        let reopened = ExpenseCreationSession(service: service)
        try await reopened.restore(retained)
        #expect(reopened.vendor == recovery.vendor && reopened.notes == recovery.notes)
        #expect(reopened.amountText == "12.50" && reopened.categoryId == category)
        _ = try await reopened.save(draft: draft, captures: [], operationUUID: uuid, capturedAt: date, recovery: retained)
        #expect(await service.operations == [uuid, uuid])
        #expect(await service.drafts == [draft, draft])
    }

    #if canImport(CoreGraphics)
    @Test func receiptSelectionRequiresDurabilityAndRemovalRetainsFiles() async throws {
        let service = Creator(), session = ExpenseCreationSession(service: service)
        let output = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: output))
        var bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        context.beginPDFPage(nil); context.endPDFPage(); context.closePDF()
        let project = try ProjectID(validating: "project"), expense = try ExpenseID(validating: "expense")
        await service.failNextCapture()
        await #expect(throws: Creator.Failure.once) {
            try await session.addReceipt(bytes: output as Data, fileName: "Receipt.pdf", projectId: project, expenseId: expense)
        }
        #expect(session.receiptCaptures.isEmpty)
        #expect(session.unconfirmedReceiptIds.count == 1)
        #expect(session.hasStoredReceiptFiles) // An uncertain persistence result must still warn on close.
        #expect(!session.hasAttempt)
        try await session.addReceipt(bytes: output as Data, fileName: "Receipt.pdf", projectId: project, expenseId: expense)
        let capture = try #require(session.receiptCaptures.first)
        #expect(capture.bytes == output as Data)
        #expect(capture.scope.parent.id.rawValue == expense.rawValue)
        #expect(await service.events == ["capture", "capture"])
        #expect(session.unconfirmedReceiptIds.count == 1) // A different successful selection cannot erase the uncertain file.
        session.removeReceipt(capture.attachmentId)
        #expect(session.receiptCaptures.isEmpty)
        #expect(session.hasStoredReceiptFiles)
        #expect(await service.operations.isEmpty)
    }
    #endif

    @Test func retriesSameAttemptAfterReceiptDurabilityWithoutDuplicateSubmission() async throws {
        let service = Creator(), session = ExpenseCreationSession(service: service)
        let id = try ExpenseID(validating: "expense"), account = try AccountID(validating: "account")
        let project = try ProjectID(validating: "project"), attachment = try AttachmentID(validating: "receipt")
        let capture = try LocalAttachmentCapture(attachmentId: attachment,
            scope: await service.expenseAttachmentCaptureScope(projectId: project, expenseId: id),
            capturedAt: .init(validating: 1000), bytes: Data([1,2,3]), metadata: .init(mediaType: "image/png", fileName: nil))
        let draft = try BusinessPaidExpenseDraft(accountId: account, projectId: project, expenseId: id,
            vendor: "Vendor", date: "2024-02-29", finalAmount: Money.parsePositiveEntry("125.50", currency: .init(validating: "USD")),
            categoryId: .init(validating: "general"), notes: "Source notes", receiptAttachmentIds: [attachment])
        let uuid = UUID(), date = Date(timeIntervalSince1970: 1000)
        let recovery = ExpenseEntryRecovery(accountId: account, projectId: project, expenseId: id,
            operationUUID: uuid, capturedAt: date, vendor: draft.vendor, date: date, amountText: "125.50",
            notes: draft.notes, categoryId: draft.categoryId, lines: [], attachmentIds: [attachment])
        await #expect(throws: Creator.Failure.once) {
            try await session.save(draft: draft, captures: [capture], operationUUID: uuid, capturedAt: date, recovery: recovery)
        }
        #expect(session.hasAttempt && !session.isSaving)
        #expect(await service.events == ["entry", "capture", "create"])
        #expect(await service.savedEntries == [recovery])
        #expect(session.savedEntry == recovery)
        await #expect(throws: ExpenseCreationSession.Failure.invalidCaptures) {
            try await session.save(draft: draft, captures: [capture], operationUUID: UUID(), capturedAt: date, recovery: recovery)
        }
        await #expect(throws: ExpenseCreationSession.Failure.changedAttempt) {
            var changed = recovery
            changed.notes = "Changed after failed acceptance"
            return try await session.save(draft: draft, captures: [capture], operationUUID: uuid, capturedAt: date, recovery: changed)
        }
        let result = try await session.save(draft: draft, captures: [capture], operationUUID: uuid, capturedAt: date, recovery: recovery)
        #expect(try await session.save(draft: draft, captures: [capture], operationUUID: uuid, capturedAt: date, recovery: recovery) == result)
        #expect(await service.events == ["entry", "capture", "create", "capture", "create"])
        #expect(await service.savedEntries == [recovery])
        #expect(await service.operations == [uuid, uuid])
        #expect(await service.drafts == [draft, draft])
    }

    @Test func editingPreservesSourceLineIdentityAndExactAmountsAcrossRetry() async throws {
        let service = Creator(), session = ExpenseCreationSession(service: service)
        let currency = try CurrencyCode(validating: "USD")
        let entry = try BusinessPaidExpenseDraft(accountId: .init(validating: "account"), projectId: .init(validating: "project"),
            expenseId: .init(validating: "expense"), vendor: "Original", date: "2024-02-29",
            finalAmount: .init(minorUnits: Int64.max, currency: currency), categoryId: .init(validating: "general"), notes: "Notes",
            receiptAttachmentIds: [.init(validating: "receipt")], receiptLines: [
                .init(id: .init(validating: "imported-line-not-a-uuid"), description: .init(validating: "Delivery"),
                    magnitude: .init(minorUnits: 1025, currency: currency), effect: .increase, quantity: 2)])
        try session.loadForEditing(.init(entry: entry, revision: 3))
        let displayedDate = DateFormatter()
        displayedDate.locale = Locale(identifier: "en_US_POSIX")
        displayedDate.timeZone = .current
        displayedDate.dateFormat = "yyyy-MM-dd"
        #expect(displayedDate.string(from: session.date) == entry.date)
        for identifier in ["America/Los_Angeles", "Pacific/Kiritimati", "UTC"] {
            let zone = try #require(TimeZone(identifier: identifier))
            try session.loadForEditing(.init(entry: entry, revision: 3), timeZone: zone)
            displayedDate.timeZone = zone
            #expect(displayedDate.string(from: session.date) == entry.date)
        }
        #expect(try Money.parsePositiveEntry(session.amountText, currency: currency) == entry.finalAmount)
        #expect(try session.receiptLines(currency: currency) == entry.receiptLines)
        let uuid = UUID(), date = Date(timeIntervalSince1970: 1000)
        await #expect(throws: Creator.Failure.once) {
            try await session.saveEdit(entry, expectedRevision: 3, operationUUID: uuid, capturedAt: date)
        }
        await #expect(throws: ExpenseCreationSession.Failure.changedAttempt) {
            try await session.saveEdit(entry, expectedRevision: 4, operationUUID: uuid, capturedAt: date)
        }
        let receipt = try await session.saveEdit(entry, expectedRevision: 3, operationUUID: uuid, capturedAt: date)
        #expect(try await session.saveEdit(entry, expectedRevision: 3, operationUUID: uuid, capturedAt: date) == receipt)
        #expect(await service.events == ["edit", "edit"])
        #expect(await service.drafts == [entry, entry])
        #expect(await service.operations == [uuid, uuid])
    }

    private actor Creator: ExpenseCreating, ExpenseEditing {
        enum Failure: Error { case once }
        var events: [String] = []
        func editExpense(_ entry: BusinessPaidExpenseDraft, expectedRevision: Int64, operationUUID: UUID, capturedAt: Date) throws -> OperationReceipt {
            events.append("edit"); operations.append(operationUUID); drafts.append(entry)
            if operations.count == 1 { throw Failure.once }
            return .init(operationId: try .init(validating: operationUUID.uuidString), localState: .queued)
        }
        var operations: [UUID] = []
        var drafts: [BusinessPaidExpenseDraft] = []
        var shouldFailCapture = false
        func failNextCapture() { shouldFailCapture = true }
        var savedEntries: [ExpenseEntryRecovery] = []
        var shouldFailEntry = false
        func failNextEntry() { shouldFailEntry = true }
        func saveExpenseEntry(_ entry: ExpenseEntryRecovery, replacing previous: ExpenseEntryRecovery?) async throws {
            events.append("entry")
            if shouldFailEntry { shouldFailEntry = false; throw Failure.once }
            savedEntries.append(entry)
        }
        var restoredCaptures: [LocalAttachmentCapture] = []
        var recoveryFailsOnce = false
        func configureRecovery(captures: [LocalAttachmentCapture], failsOnce: Bool) {
            restoredCaptures = captures; recoveryFailsOnce = failsOnce
        }
        func restoreExpenseEntryCaptures(_ entry: ExpenseEntryRecovery) async throws -> [LocalAttachmentCapture] {
            if recoveryFailsOnce { recoveryFailsOnce = false; throw Failure.once }
            return restoredCaptures
        }
        nonisolated func watchBudgetCategories() -> AsyncThrowingStream<BudgetCategoryReferenceSnapshot, Error> {
            AsyncThrowingStream { _ in }
        }
        func expenseAttachmentCaptureScope(projectId: ProjectID, expenseId: ExpenseID) throws -> AttachmentCaptureScope {
            try .init(environment: .targetLocal, principalId: .init(validating: "principal"), accountId: .init(validating: "account"),
                parent: .init(kind: .expense, id: .init(validating: expenseId.rawValue)))
        }
        func captureAttachment(_ capture: LocalAttachmentCapture) throws -> AttachmentLocalDurabilityReceipt {
            events.append("capture")
            if shouldFailCapture { shouldFailCapture = false; throw Failure.once }
            return try .init(accepting: capture, persistedEvidence: .init(attachmentId: capture.attachmentId, scope: capture.scope,
                localObjectId: .init(validating: "receipt-local"), byteCount: capture.byteCount,
                contentSHA256: capture.contentSHA256, persistedAt: capture.capturedAt))
        }
        func createExpense(_ draft: BusinessPaidExpenseDraft, operationUUID: UUID, capturedAt: Date, recovery: ExpenseEntryRecovery?) throws -> OperationReceipt {
            events.append("create"); operations.append(operationUUID); drafts.append(draft)
            if operations.count == 1 { throw Failure.once }
            return .init(operationId: try .init(validating: operationUUID.uuidString), localState: .queued)
        }
    }
}
