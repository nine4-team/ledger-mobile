import Foundation
import Testing
import LedgerTargetCore
@testable import LedgerTargetPowerSync

@Suite("Fee creation provider wire")
struct CreateFeeInstallmentUploadRequestTests {
    private func command(order: Int64? = nil) throws -> CreateFeeInstallmentCommand {
        try .init(operationId: .init(validating: "operation"), actorPrincipalId: .init(validating: "actor"),
            capturedAt: Date(timeIntervalSince1970: 1), draft: .init(accountId: .init(validating: "account"),
                projectId: .init(validating: "project"), installmentId: .init(validating: "fee"),
                categoryId: .init(validating: "category"), label: "Design fee",
                amount: .init(minorUnits: 9_007_199_254_740_993, currency: .init(validating: "USD")), sortOrder: order))
    }
    @Test func exactWireAndRestoredReplay() throws {
        for order: Int64? in [nil, 0, Int64(Int32.min), Int64(Int32.max)] {
            let value = try command(order: order), request = try CreateFeeInstallmentUploadRequest(value)
            let wire = try #require(JSONSerialization.jsonObject(with: Data(request.commandJSON.utf8)) as? [String: String])
            #expect(wire == ["operationId":"operation", "accountId":"account", "actorPrincipalId":"actor",
                "projectId":"project", "installmentId":"fee", "categoryId":"category",
                "contractVersion":"fee-installment-create-v1", "createdAtMs":"1000", "label":"Design fee",
                "amountMinorUnits":"9007199254740993", "currency":"USD", "sortOrder":order.map(String.init) ?? ""])
            let restored = try OperationContractCodec.decode(CreateFeeInstallmentCommand.self, from: OperationContractCodec.encode(value))
            #expect(try CreateFeeInstallmentUploadRequest(restored).fingerprint == request.fingerprint)
            #expect(try JSONSerialization.jsonObject(with: request.rpcBody) as? [String: String] == ["p_command":request.commandJSON])
        }
    }
    @Test func terminalResultCannotAcknowledgeAnotherCommand() throws {
        let value = try command(), fingerprint = try CreateFeeInstallmentUploadRequest(value).fingerprint
        let row: [String: Any] = ["operation_id":"operation", "account_id":"account", "actor_principal_id":"actor",
            "command_type":"create_fee_installment", "contract_version":"fee-installment-create-v1",
            "command_fingerprint":fingerprint, "envelope_sha256":fingerprint, "subject_id":"fee",
            "phase":"applied", "result_code":"fee_installment_created", "error_code":NSNull(),
            "request_sha256":NSNull(), "client_created_at_ms":1000, "server_received_at_ms":1001, "completed_at_ms":1002]
        func validate(_ row: [String: Any]) throws {
            try JSONDecoder().decode(CreateFeeInstallmentServerResult.self,
                from: JSONSerialization.data(withJSONObject: row)).validate(for: value)
        }
        try validate(row)
        for field in ["operation_id", "account_id", "actor_principal_id", "command_type", "contract_version",
                      "command_fingerprint", "envelope_sha256", "subject_id", "phase", "result_code", "error_code", "request_sha256"] {
            var invalid = row; invalid[field] = "wrong"
            #expect(throws: (any Error).self) { try validate(invalid) }
        }
        for code in CreateFeeInstallmentServerResult.rejections {
            var rejected = row; rejected["phase"] = "rejected"; rejected["result_code"] = NSNull(); rejected["error_code"] = code
            try validate(rejected)
        }
        for (field, number) in [("client_created_at_ms", 999), ("server_received_at_ms", -1), ("completed_at_ms", 1000)] {
            var invalid = row; invalid[field] = number
            #expect(throws: (any Error).self) { try validate(invalid) }
        }
    }
}
