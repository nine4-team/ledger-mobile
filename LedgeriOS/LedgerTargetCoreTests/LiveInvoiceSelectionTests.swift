import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Live Invoice source selection")
struct LiveInvoiceSelectionTests {
    private func scope() throws -> TransactionScope {
        try .project(accountId: .init(validating: "account"), projectId: .init(validating: "project"),
            clientId: .init(validating: "client"))
    }
    private func line(_ source: LiveInvoiceSource, _ amount: Int64, currency: String = "USD") throws -> LiveInvoiceSelection.Line {
        try .init(source: source, expectedRevision: 7,
            reviewedAmount: .init(minorUnits: amount, currency: .init(validating: currency)))
    }

    @Test func retainsOccurrenceIdentityOrderAndExactSignedReview() throws {
        let lines = try [line(.itemOccurrence(.init(validating: "sale-one")), 9_007_199_254_740_993),
            line(.itemOccurrence(.init(validating: "return-one")), -100),
            line(.expense(.init(validating: "expense")), 101),
            line(.feeInstallment(.init(validating: "fee")), 200)]
        let selection = try LiveInvoiceSelection(scope: scope(), lines: lines)
        #expect(selection.reviewedTotal.minorUnits == 9_007_199_254_741_194)
        let decoded = try OperationContractCodec.decode(LiveInvoiceSelection.self,
            from: OperationContractCodec.encode(selection))
        #expect(decoded == selection)
        #expect(decoded.lines == lines)
    }

    @Test func creationCommandRetainsStableIdentityAndRejectsWrongContract() throws {
        let selection = try LiveInvoiceSelection(scope: scope(), lines: [line(.expense(.init(validating: "expense")), 100)])
        let command = try CreateInvoiceCommand(operationId: .init(validating: "operation"),
            actorPrincipalId: .init(validating: "actor"), capturedAt: Date(timeIntervalSince1970: 100),
            payload: .init(invoiceId: .init(validating: "invoice"), selection: selection,
                name: "Phase 1", notes: "Original notes"))
        let bytes = try OperationContractCodec.encode(command)
        let restored = try OperationContractCodec.decode(CreateInvoiceCommand.self, from: bytes)
        #expect(try OperationContractCodec.encode(restored) == bytes)
        #expect(restored.envelope.payload.selection == selection)
        #expect(restored.envelope.operationId.rawValue == "operation")
        let wrong = String(decoding: bytes, as: UTF8.self)
            .replacingOccurrences(of: "invoice-create-v1", with: "invoice-create-v2")
        #expect(throws: CreateInvoiceCommand.Failure.invalidEnvelope) {
            try OperationContractCodec.decode(CreateInvoiceCommand.self, from: Data(wrong.utf8))
        }
    }

    @Test func rejectsDuplicatesInvalidScopeAndInexactEvidence() throws {
        let source = LiveInvoiceSource.expense(try .init(validating: "expense"))
        let row = try line(source, 1)
        #expect(throws: LiveInvoiceSelection.Failure.duplicateSource) {
            try LiveInvoiceSelection(scope: scope(), lines: [row, row])
        }
        #expect(throws: LiveInvoiceSelection.Failure.emptySelection) {
            try LiveInvoiceSelection(scope: scope(), lines: [])
        }
        #expect(throws: LiveInvoiceSelection.Failure.requiresProject) {
            try LiveInvoiceSelection(scope: .businessInventory(accountId: .init(validating: "account")), lines: [row])
        }
        #expect(throws: LiveInvoiceSelection.Failure.invalidRevision) {
            try LiveInvoiceSelection.Line(source: source, expectedRevision: 0, reviewedAmount: row.reviewedAmount)
        }
        #expect(throws: (any Error).self) {
            try LiveInvoiceSelection(scope: scope(), lines: [row, line(.expense(.init(validating: "other")), 1, currency: "EUR")])
        }
        #expect(throws: (any Error).self) {
            try LiveInvoiceSelection(scope: scope(), lines: [line(source, Int64.max), line(.expense(.init(validating: "other")), 1)])
        }
        let valid = try LiveInvoiceSelection(scope: scope(), lines: [row])
        let malformed = String(decoding: try OperationContractCodec.encode(valid), as: UTF8.self)
            .replacingOccurrences(of: "\"expectedRevision\":7", with: "\"expectedRevision\":0")
        #expect(throws: LiveInvoiceSelection.Failure.invalidRevision) {
            try OperationContractCodec.decode(LiveInvoiceSelection.self, from: Data(malformed.utf8))
        }
    }
}
