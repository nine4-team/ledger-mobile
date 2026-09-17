import Foundation
import Testing
import LedgerTargetCore
@testable import LedgerTargetPowerSync

@Suite("Paid return wire contract")
struct ReturnPaidItemsUploadRequestTests {
    @Test func sharedMCPWireFixture() throws {
        struct Fixture: Decodable {
            struct Input: Decodable {
                let operationUUID: UUID
                let clientCreatedAtMilliseconds: Int64
                let payload: ReturnPaidItemsPayload
            }
            let accountId: AccountID, principalId: PrincipalID
            let input: Input
            let operationId: String, fingerprint: String
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf:
            root.appendingPathComponent("LedgerTargetMCP/tests/fixtures/paid-return.json")))
        let id = try ReturnPaidItemsOperationIdentity.make(accountId: fixture.accountId, uuid: fixture.input.operationUUID)
        let command = try ReturnPaidItemsCommand(operationId: id, accountId: fixture.accountId,
            actorPrincipalId: fixture.principalId,
            capturedAt: Date(timeIntervalSince1970: Double(fixture.input.clientCreatedAtMilliseconds) / 1000),
            payload: fixture.input.payload)
        #expect(id.rawValue == fixture.operationId)
        #expect(try ReturnPaidItemsUploadRequest(command).fingerprint == fixture.fingerprint)
    }

    @Test func exactFrozenIdentityWithoutMutableMoneyAndStableReplay() throws {
        let command = try ReturnPaidItemsCommand(operationId: .init(validating: "return"),
            accountId: .init(validating: "account"), actorPrincipalId: .init(validating: "actor"),
            capturedAt: Date(timeIntervalSince1970: 1000.125),
            payload: .init(projectId: .init(validating: "project"), items: [
                .init(itemId: .init(validating: "item"), placementId: .init(validating: "old"),
                    chargeId: .init(validating: "charge"), paidInvoiceLineId: .init(validating: "line"),
                    inventoryPlacementId: .init(validating: "new"),
                    returnOccurrenceId: .init(validating: "occurrence"), creditId: .init(validating: "credit"))]))
        let request = try ReturnPaidItemsUploadRequest(command)
        let json = try #require(JSONSerialization.jsonObject(with: Data(request.commandJSON.utf8)) as? [String: Any])
        #expect(Set(json.keys) == Set(["operationId", "accountId", "actorPrincipalId", "projectId",
                                      "contractVersion", "createdAtMs", "items"]))
        #expect(json["createdAtMs"] as? String == "1000125")
        #expect(json["contractVersion"] as? String == "return-paid-items-v1")
        let rows = try #require(json["items"] as? [[String: String]])
        #expect(rows == [["itemId": "item", "placementId": "old", "chargeId": "charge",
                         "paidInvoiceLineId": "line", "inventoryPlacementId": "new",
                         "returnOccurrenceId": "occurrence", "creditId": "credit"]])
        let body = try #require(JSONSerialization.jsonObject(with: request.rpcBody) as? [String: String])
        #expect(body == ["p_command": request.commandJSON])
        let restored = try OperationContractCodec.decode(ReturnPaidItemsCommand.self,
            from: OperationContractCodec.encode(command))
        let replay = try ReturnPaidItemsUploadRequest(restored)
        #expect(replay.commandJSON == request.commandJSON)
        #expect(replay.fingerprint == request.fingerprint)
        let valid: [String: Any] = ["operation_id":"return", "account_id":"account",
            "actor_principal_id":"actor", "subject_id":"project", "command_type":"return_paid_items",
            "contract_version":"return-paid-items-v1", "command_fingerprint":request.fingerprint,
            "envelope_sha256":request.fingerprint, "phase":"applied", "result_code":"paid_items_returned",
            "client_created_at_ms":1000125, "server_received_at_ms":1000126, "completed_at_ms":1000127]
        func validate(_ fields: [String: Any]) throws {
            let result = try JSONDecoder().decode(ReturnPaidItemsServerResult.self,
                from: JSONSerialization.data(withJSONObject: fields))
            try result.validate(for: command)
        }
        try validate(valid)
        for key in ["operation_id", "account_id", "actor_principal_id", "subject_id", "command_type",
                    "contract_version", "command_fingerprint", "envelope_sha256", "phase", "result_code"] {
            var fields = valid; fields[key] = "wrong"
            #expect(throws: ReturnPaidItemsServerResult.Failure.receiptMismatch) { try validate(fields) }
        }
        for rejection in ReturnPaidItemsServerResult.rejections {
            var fields = valid; fields["phase"] = "rejected"; fields.removeValue(forKey: "result_code")
            fields["error_code"] = rejection
            try validate(fields)
        }
        var invalid = valid; invalid["completed_at_ms"] = 0
        #expect(throws: ReturnPaidItemsServerResult.Failure.receiptMismatch) { try validate(invalid) }
        invalid = valid; invalid["error_code"] = "return_charge_stale"
        #expect(throws: ReturnPaidItemsServerResult.Failure.receiptMismatch) { try validate(invalid) }
    }
}
