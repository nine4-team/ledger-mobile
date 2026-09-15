import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Business-paid Expense entry data")
struct BusinessPaidExpenseDraftTests {
    private func draft(amount: Int64 = 100, date: String = "2024-02-29",
                       attachments: [AttachmentID] = [], lines: [NonItemReceiptLine] = []) throws -> BusinessPaidExpenseDraft {
        try .init(accountId: .init(validating: "account"), projectId: .init(validating: "project"),
            expenseId: .init(validating: "expense"), vendor: "  Vendor source wording  ", date: date,
            finalAmount: .init(minorUnits: amount, currency: .init(validating: "USD")),
            categoryId: .init(validating: "category"), notes: "Original\nnotes",
            receiptAttachmentIds: attachments, receiptLines: lines)
    }

    private func line(currency: String = "USD") throws -> NonItemReceiptLine {
        try .init(id: .init(validating: "line"), description: .init(validating: "Delivery"),
            magnitude: .init(minorUnits: 25, currency: .init(validating: currency)), effect: .increase)
    }

    @Test func preservesExactEntryWithoutFabricatingPaymentsOrBalancingLines() throws {
        let attachment = try AttachmentID(validating: "receipt")
        let detail = try line()
        let value = try draft(amount: Int64.max, attachments: [attachment], lines: [detail])
        #expect(value.finalAmount.minorUnits == Int64.max)
        #expect(value.vendor == "  Vendor source wording  ")
        #expect(value.notes == "Original\nnotes")
        #expect(value.date == "2024-02-29")
        #expect(value.receiptLines == [detail])
        #expect(value.receiptAttachmentIds == [attachment])
        #expect(try draft().receiptLines.isEmpty)
    }

    @Test func rejectsMalformedEmbeddedEvidence() throws {
        let attachment = try AttachmentID(validating: "receipt"), detail = try line()
        #expect(throws: BusinessPaidExpenseDraft.Failure.duplicateAttachment) {
            try draft(attachments: [attachment, attachment])
        }
        #expect(throws: BusinessPaidExpenseDraft.Failure.duplicateReceiptLine) {
            try draft(lines: [detail, detail])
        }
        #expect(throws: BusinessPaidExpenseDraft.Failure.currencyMismatch) {
            try draft(lines: [line(currency: "EUR")])
        }
        for date in ["2025-02-29", "2024-13-01", "2024-02-29T00:00:00Z", "0000-01-01", "2024-2-9"] {
            #expect(throws: BusinessPaidExpenseDraft.Failure.invalidDate) {
                try draft(date: date)
            }
        }
    }

    @Test func paidExpenseRequiresExactFrozenSourceButRetainsHistoricalLabels() throws {
        let source = try draft()
        func invoice(project: String = "project", revision: Int64 = 1, amount: Int64 = 100,
                     expense: String = "expense") throws -> FrozenInvoiceContents {
            let scope = try TransactionScope.project(accountId: .init(validating: "account"),
                projectId: .init(validating: project), clientId: .init(validating: "client"))
            let line = try FrozenInvoiceLine(id: .init(validating: "paid-line"), scope: scope,
                source: .expense(expenseId: .init(validating: expense)), sourceRevision: revision,
                categoryId: .init(validating: "historical-category"),
                signedAmount: .init(minorUnits: amount, currency: .init(validating: "USD")), description: "Historical vendor")
            return try .init(invoiceId: .init(validating: "invoice"), invoiceRevision: 1, scope: scope,
                purchaseId: .init(validating: "payment"), lines: [line], total: line.signedAmount)
        }
        #expect(try ProjectExpenses.Expense(entry: source, revision: 1).collectedInvoice == nil)
        let paid = try ProjectExpenses.Expense(entry: source, revision: 1, collectedInvoice: invoice())
        #expect(paid.collectedInvoice?.lines[0].description == "Historical vendor")
        #expect(paid.collectedInvoice?.lines[0].categoryId.rawValue == "historical-category")
        for invalid in [try invoice(project: "other"), try invoice(revision: 2), try invoice(amount: 101), try invoice(expense: "other")] {
            #expect(throws: ProjectExpenses.Failure.invalidEvidence) {
                try ProjectExpenses.Expense(entry: source, revision: 1, collectedInvoice: invalid)
            }
        }
    }

    @Test func receiptMetadataCannotIntroduceUnrelatedOrDuplicateObjects() throws {
        let id = try AttachmentID(validating: "receipt"), hash = String(repeating: "a", count: 64)
        func object(account: String) throws -> DownloadedMediaObjectReference {
            try .init(accountId: .init(validating: account), attachmentId: id.rawValue, sha256: hash,
                byteCount: "12", mediaType: "application/pdf",
                storagePath: "accounts/\(account)/attachments/receipt/\(hash)", kind: .pdf)
        }
        let source = try draft(attachments: [id]), valid = try object(account: "account")
        #expect(try ProjectExpenses.Expense(entry: source, revision: 1).receiptObjects.isEmpty)
        #expect(try ProjectExpenses.Expense(entry: source, revision: 1, receiptObjects: [valid]).entry == source)
        #expect(throws: ProjectExpenses.Failure.invalidEvidence) {
            try ProjectExpenses.Expense(entry: source, revision: 1, receiptObjects: [valid, valid])
        }
        #expect(throws: ProjectExpenses.Failure.invalidEvidence) {
            try ProjectExpenses.Expense(entry: source, revision: 1, receiptObjects: [object(account: "other")])
        }
        #expect(throws: ProjectExpenses.Failure.invalidEvidence) {
            try ProjectExpenses.Expense(entry: draft(), revision: 1, receiptObjects: [valid])
        }
    }

    @Test func commandEncodingRetainsIdentityAndValidatesPersistedPayload() throws {
        let value = try draft(amount: Int64.max, lines: [line()])
        let command = try CreateExpenseCommand(operationId: .init(validating: "expense-operation"),
            actorPrincipalId: .init(validating: "actor"), capturedAt: Date(timeIntervalSince1970: 1234), draft: value)
        let encoded = try OperationContractCodec.encode(command)
        let restored = try OperationContractCodec.decode(CreateExpenseCommand.self, from: encoded)
        #expect(restored.envelope.payload == value)
        #expect(restored.envelope.operationId == command.envelope.operationId)
        #expect(try OperationContractCodec.encode(restored) == encoded)
        let invalidDate = String(decoding: encoded, as: UTF8.self).replacingOccurrences(of: "2024-02-29", with: "2025-02-29")
        #expect(throws: BusinessPaidExpenseDraft.Failure.invalidDate) {
            try OperationContractCodec.decode(CreateExpenseCommand.self, from: Data(invalidDate.utf8))
        }
        let invalidContract = String(decoding: encoded, as: UTF8.self).replacingOccurrences(of: "expense-create-v1", with: "expense-create-v2")
        #expect(throws: CreateExpenseCommand.Failure.invalidEnvelope) {
            try OperationContractCodec.decode(CreateExpenseCommand.self, from: Data(invalidContract.utf8))
        }
    }
}
