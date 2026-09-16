import Foundation
import Testing
import LedgerTargetCore
@testable import LedgerTargetPowerSync

@Suite("Invoice creation wire encoding")
struct CreateInvoiceUploadRequestTests {
    @Test func validatesTerminalIdentityFingerprintAndAllowedOutcomes() throws {
        let selection = try LiveInvoiceSelection(scope: .project(accountId: .init(validating: "account"),
            projectId: .init(validating: "project"), clientId: .init(validating: "client")), lines: [
                .init(source: .expense(.init(validating: "expense")), expectedRevision: 1,
                    reviewedAmount: .init(minorUnits: 100, currency: .init(validating: "USD")))])
        let command = try CreateInvoiceCommand(operationId: .init(validating: "operation"),
            actorPrincipalId: .init(validating: "actor"), capturedAt: Date(timeIntervalSince1970: 1),
            payload: .init(invoiceId: .init(validating: "invoice"), selection: selection, name: "", notes: ""))
        let fingerprint = try CreateInvoiceUploadRequest(command).fingerprint
        let row: [String: Any] = ["operation_id":"operation", "account_id":"account", "actor_principal_id":"actor",
            "command_type":"create_invoice", "contract_version":"invoice-create-v1", "command_fingerprint":fingerprint,
            "envelope_sha256":fingerprint, "subject_id":"invoice", "phase":"applied", "result_code":"invoice_created",
            "error_code":NSNull(), "request_sha256":NSNull(), "client_created_at_ms":1000,
            "server_received_at_ms":1001, "completed_at_ms":1002]
        func validate(_ value: [String: Any]) throws {
            try JSONDecoder().decode(CreateInvoiceServerResult.self, from: JSONSerialization.data(withJSONObject: value)).validate(for: command)
        }
        try validate(row)
        for field in ["operation_id", "account_id", "actor_principal_id", "command_type", "contract_version",
                      "command_fingerprint", "envelope_sha256", "subject_id", "result_code", "request_sha256"] {
            var invalid = row; invalid[field] = "wrong"
            #expect(throws: (any Error).self) { try validate(invalid) }
        }
        for code in CreateInvoiceServerResult.rejections {
            var rejected = row; rejected["phase"] = "rejected"; rejected["result_code"] = NSNull(); rejected["error_code"] = code
            try validate(rejected)
        }
        var invalid = row; invalid["completed_at_ms"] = 1000
        #expect(throws: (any Error).self) { try validate(invalid) }
    }
    @Test func exactSourceIdentityAndReplay() throws {
        let selection = try LiveInvoiceSelection(scope: .project(accountId: .init(validating: "account"),
            projectId: .init(validating: "project"), clientId: .init(validating: "client")), lines: [
                .init(source: .itemOccurrence(.init(validating: "occurrence")), expectedRevision: 9,
                    reviewedAmount: .init(minorUnits: 9_007_199_254_740_993, currency: .init(validating: "USD")))])
        let command = try CreateInvoiceCommand(operationId: .init(validating: "operation"),
            actorPrincipalId: .init(validating: "actor"), capturedAt: Date(timeIntervalSince1970: 100),
            payload: .init(invoiceId: .init(validating: "invoice"), selection: selection, name: "Phase 1", notes: "Notes"))
        let request = try CreateInvoiceUploadRequest(command)
        let wire = try #require(JSONSerialization.jsonObject(with: Data(request.commandJSON.utf8)) as? [String: Any])
        let source = try #require((wire["sources"] as? [[String: String]])?.first)
        #expect(source == ["kind":"item","sourceId":"occurrence","expectedRevision":"9",
            "amountMinorUnits":"9007199254740993","currency":"USD"])
        #expect(wire["clientId"] as? String == "client")
        #expect(wire["createdAtMs"] as? String == "100000")
        let restored = try OperationContractCodec.decode(CreateInvoiceCommand.self, from: OperationContractCodec.encode(command))
        #expect(try CreateInvoiceUploadRequest(restored).fingerprint == request.fingerprint)
        let body = try #require(JSONSerialization.jsonObject(with: request.rpcBody) as? [String: String])
        #expect(body == ["p_command":request.commandJSON])
    }
}
