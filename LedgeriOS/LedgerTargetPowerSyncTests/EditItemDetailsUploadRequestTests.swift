import Foundation
import Testing
import LedgerTargetCore
@testable import LedgerTargetPowerSync

struct EditItemDetailsUploadRequestTests {
    @Test func sharedMCPDigest() throws {
        let account = try AccountID(validating: "account")
        let command = try EditItemDetailsCommand(operationId: ItemDetailsEditOperationIdentity.make(accountId: account,
            uuid: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!),
            accountId: account, actorPrincipalId: .init(validating: "member"), capturedAt: Date(timeIntervalSince1970: 123),
            payload: .init(items: [.init(itemId: .init(validating: "item"), expectedRevision: Int64.max - 1)],
                           changes: .init(sku: .clear, notes: .set(""), bookmark: false)))
        #expect(try EditItemDetailsUploadRequest(command).fingerprint == "95f10367ab70297bf29a4ad499b22836f7d3cb1dca37624a74cca08382fde647")
    }

    @Test func receiptMustMatchAcceptedCommand() throws {
        let command = try EditItemDetailsCommand(operationId: .init(validating: "details-op"),
            accountId: .init(validating: "account"), actorPrincipalId: .init(validating: "actor"),
            capturedAt: Date(timeIntervalSince1970: 123), payload: .init(items: [
                .init(itemId: .init(validating: "item"), expectedRevision: 1)
            ], changes: .init(name: .set("Chair"))))
        let request = try EditItemDetailsUploadRequest(command)
        let valid: [String: Any] = [
            "operation_id": "details-op", "account_id": "account", "actor_principal_id": "actor",
            "command_type": "edit_item_details", "contract_version": "item-details-edit-v1",
            "command_fingerprint": request.fingerprint, "envelope_sha256": request.fingerprint,
            "subject_id": "item", "phase": "applied", "result_code": "item_details_updated",
            "client_created_at_ms": 123000, "server_received_at_ms": 124000, "completed_at_ms": 124000
        ]
        func validate(_ object: [String: Any]) throws {
            try JSONDecoder().decode(EditItemDetailsServerResult.self,
                from: JSONSerialization.data(withJSONObject: object)).validate(for: command)
        }
        try validate(valid)
        for key in ["operation_id", "account_id", "actor_principal_id", "command_type", "contract_version",
                    "command_fingerprint", "envelope_sha256", "subject_id", "phase", "result_code"] {
            var invalid = valid; invalid[key] = "wrong"
            #expect(throws: EditItemDetailsServerResult.Failure.self) { try validate(invalid) }
        }
        for (key, value) in [("client_created_at_ms", 123001), ("server_received_at_ms", -1), ("completed_at_ms", 123999)] {
            var invalid = valid; invalid[key] = value
            #expect(throws: EditItemDetailsServerResult.Failure.self) { try validate(invalid) }
        }
        for key in ["error_code", "request_sha256"] {
            var invalid = valid; invalid[key] = "unexpected"
            #expect(throws: EditItemDetailsServerResult.Failure.self) { try validate(invalid) }
        }
        var rejected = valid
        rejected["phase"] = "rejected"; rejected.removeValue(forKey: "result_code")
        for error in EditItemDetailsServerResult.rejections {
            rejected["error_code"] = error
            try validate(rejected)
        }
        rejected["error_code"] = "unknown"
        #expect(throws: EditItemDetailsServerResult.Failure.self) { try validate(rejected) }
    }

    @Test func exactFieldsAndStableReplay() throws {
        let command = try EditItemDetailsCommand(operationId: .init(validating: "details-op"),
            accountId: .init(validating: "account"), actorPrincipalId: .init(validating: "actor"),
            capturedAt: Date(timeIntervalSince1970: 123), payload: .init(items: [
                .init(itemId: .init(validating: "item"), expectedRevision: Int64.max - 1)
            ], changes: .init(sku: .clear, notes: .set(""), status: .clear, bookmark: false)))
        let request = try EditItemDetailsUploadRequest(command)
        let object = try #require(JSONSerialization.jsonObject(with: Data(request.commandJSON.utf8)) as? [String: Any])
        #expect(object.count == 7)
        #expect(object["createdAtMs"] as? String == "123000")
        let items = try #require(object["items"] as? [[String: String]])
        #expect(items == [["itemId": "item", "expectedRevision": "9223372036854775806"]])
        let changes = try #require(object["changes"] as? [String: Any])
        #expect(changes.count == 4)
        #expect(changes["name"] == nil)
        #expect(changes["sku"] is NSNull)
        #expect(changes["status"] is NSNull)
        #expect(changes["notes"] as? String == "")
        #expect(changes["bookmark"] as? Bool == false)
        let restored = try OperationContractCodec.decode(EditItemDetailsCommand.self,
            from: OperationContractCodec.encode(command))
        let retry = try EditItemDetailsUploadRequest(restored)
        #expect(retry.commandJSON == request.commandJSON)
        #expect(retry.fingerprint == request.fingerprint)
        #expect(try JSONDecoder().decode([String: String].self, from: request.rpcBody)["p_command"] == request.commandJSON)
    }
}
