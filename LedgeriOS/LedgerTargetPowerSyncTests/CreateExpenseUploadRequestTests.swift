import Foundation
import Testing
import LedgerTargetCore
@testable import LedgerTargetPowerSync

@Suite("Expense upload wire")
struct CreateExpenseUploadRequestTests {
    @Test func mcpCommandParity() throws {
        // Same vector as LedgerTargetMCP/tests/expenseCreation.test.ts.
        let currency = try CurrencyCode(validating: "USD")
        let account = try AccountID(validating: "account")
        let draft = try BusinessPaidExpenseDraft(accountId: account,
            projectId: .init(validating: "project"), expenseId: .init(validating: "expense"),
            vendor: "Original/vendor", date: "2024-02-29", finalAmount: .init(minorUnits: Int64.max, currency: currency),
            categoryId: .init(validating: "category"), notes: "Original notes",
            receiptAttachmentIds: [.init(validating: "receipt")], receiptLines: [
                .init(id: .init(validating: "line"), description: .init(validating: "Delivery"),
                    magnitude: .init(minorUnits: 1025, currency: currency), effect: .increase)
            ])
        let id = try AccountBoundOperationIdentity.make(family: .expenseCreation, accountId: account,
            uuid: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")))
        let command = try CreateExpenseCommand(operationId: id, actorPrincipalId: .init(validating: "actor"),
            capturedAt: Date(timeIntervalSince1970: 123), draft: draft)
        #expect(try CreateExpenseUploadRequest(command).fingerprint == "21c1aad8eefef9ea5025285e9e63ff978f1f97a19274c36a6005e581cf299356")
        let editID = try AccountBoundOperationIdentity.make(family: .expenseEdit, accountId: account,
            uuid: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")))
        let edit = try EditExpenseCommand(operationId: editID, actorPrincipalId: .init(validating: "actor"),
            capturedAt: Date(timeIntervalSince1970: 123), expectedRevision: 2, entry: draft)
        #expect(try EditExpenseUploadRequest(edit).fingerprint == "db5ccf77710ea81173301ba79d39d2772ade9becee4f98467669edc02816ac60")
        #expect(!AccountBoundOperationIdentity.isValid(editID, family: .expenseCreation, accountId: account))
        let otherAccount = try AccountID(validating: "other")
        #expect(!AccountBoundOperationIdentity.isValid(editID, family: .expenseEdit, accountId: otherAccount))
    }

    @Test func exactAmountsExplicitNullAndStableRetry() throws {
        let currency = try CurrencyCode(validating: "USD")
        let draft = try BusinessPaidExpenseDraft(accountId: .init(validating: "account"),
            projectId: .init(validating: "project"), expenseId: .init(validating: "expense"),
            vendor: "Source vendor", date: "2024-02-29", finalAmount: .init(minorUnits: Int64.max, currency: currency),
            categoryId: .init(validating: "category"), notes: "Original notes", receiptLines: [
                .init(id: .init(validating: "line"), description: .init(validating: "Delivery"),
                      magnitude: .init(minorUnits: Int64.max, currency: currency), effect: .increase)
            ])
        let command = try CreateExpenseCommand(operationId: .init(validating: "op"),
            actorPrincipalId: .init(validating: "actor"), capturedAt: Date(timeIntervalSince1970: 123), draft: draft)
        let request = try CreateExpenseUploadRequest(command)
        let json = try #require(JSONSerialization.jsonObject(with: Data(request.commandJSON.utf8)) as? [String: Any])
        #expect(json["amountMinorUnits"] as? String == String(Int64.max))
        #expect(json["date"] as? String == "2024-02-29")
        let lines = try #require(json["receiptLines"] as? [[String: Any]])
        #expect(lines[0]["magnitudeMinorUnits"] as? String == String(Int64.max))
        #expect(lines[0]["quantity"] is NSNull)
        let restored = try OperationContractCodec.decode(CreateExpenseCommand.self, from: OperationContractCodec.encode(command))
        #expect(try CreateExpenseUploadRequest(restored).commandJSON == request.commandJSON)
        #expect(try CreateExpenseUploadRequest(restored).fingerprint == request.fingerprint)
        let body = try #require(JSONSerialization.jsonObject(with: request.rpcBody) as? [String: String])
        #expect(body["p_command"] == request.commandJSON)
        #expect(json["expectedRevision"] == nil)
        let edit = try EditExpenseCommand(operationId: .init(validating: "edit"),
            actorPrincipalId: .init(validating: "actor"), capturedAt: Date(timeIntervalSince1970: 123),
            expectedRevision: Int64.max - 1, entry: draft)
        let editRequest = try EditExpenseUploadRequest(edit)
        let editJSON = try #require(JSONSerialization.jsonObject(with: Data(editRequest.commandJSON.utf8)) as? [String: Any])
        #expect(editJSON["expectedRevision"] as? String == String(Int64.max - 1))
        #expect(editJSON["contractVersion"] as? String == "expense-edit-v1")
        #expect(editJSON["amountMinorUnits"] as? String == String(Int64.max))
        #expect(editJSON["expenseId"] as? String == draft.expenseId.rawValue)
        let restoredEdit = try OperationContractCodec.decode(EditExpenseCommand.self, from: OperationContractCodec.encode(edit))
        #expect(try EditExpenseUploadRequest(restoredEdit).fingerprint == editRequest.fingerprint)
        let result: [String: Any] = [
            "operation_id": "op", "account_id": "account", "actor_principal_id": "actor",
            "command_type": "create_expense", "contract_version": "expense-create-v1",
            "command_fingerprint": request.fingerprint, "envelope_sha256": request.fingerprint,
            "subject_id": "expense", "phase": "applied", "result_code": "expense_created",
            "client_created_at_ms": 123000, "server_received_at_ms": 124000, "completed_at_ms": 124000
        ]
        func decode(_ value: [String: Any]) throws -> CreateExpenseServerResult {
            try JSONDecoder().decode(CreateExpenseServerResult.self, from: JSONSerialization.data(withJSONObject: value))
        }
        try decode(result).validate(for: command)
        for key in ["operation_id", "account_id", "actor_principal_id", "subject_id", "command_fingerprint", "envelope_sha256", "contract_version", "result_code"] {
            var changed = result; changed[key] = "wrong"
            #expect(throws: CreateExpenseServerResult.Failure.self) { try decode(changed).validate(for: command) }
        }
        var rejected = result
        rejected["phase"] = "rejected"; rejected.removeValue(forKey: "result_code")
        rejected["error_code"] = "expense_integrity_conflict"
        try decode(rejected).validate(for: command)
        rejected["error_code"] = "unknown-error"
        #expect(throws: CreateExpenseServerResult.Failure.self) { try decode(rejected).validate(for: command) }
        var editResult = result
        editResult["operation_id"] = "edit"
        editResult["command_type"] = "edit_expense"
        editResult["contract_version"] = "expense-edit-v1"
        editResult["result_code"] = "expense_edited"
        editResult["command_fingerprint"] = editRequest.fingerprint
        editResult["envelope_sha256"] = editRequest.fingerprint
        try decode(editResult).validate(for: edit)
        #expect(throws: ExpenseServerResult.Failure.self) { try decode(result).validate(for: edit) }
        #expect(throws: ExpenseServerResult.Failure.self) { try decode(editResult).validate(for: command) }
        for reason in ["expense_collected", "expense_revision_conflict", "expense_unavailable", "expense_receipt_change_unavailable"] {
            var denied = editResult
            denied["phase"] = "rejected"; denied.removeValue(forKey: "result_code"); denied["error_code"] = reason
            try decode(denied).validate(for: edit)
        }
    }
}
