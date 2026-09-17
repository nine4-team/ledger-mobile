import Foundation
import Testing
import LedgerTargetCore
@testable import LedgerTargetPowerSync

@Suite("Space assignment provider wire")
struct ItemSpaceUploadRequestTests {
    private func assignment(revision: UInt64 = 9_007_199_254_740_993,
                            time: Date = Date(timeIntervalSince1970: 1000.125)) throws -> AssignItemsToSpaceCommand {
        try .init(operationId: .init(validating: "assign"), draft: .init(
            accountId: .init(validating: "account"), actorPrincipalId: .init(validating: "actor"),
            operationContractVersion: .init(validating: "item-space-assignment-v1"),
            destinationSpaceId: .init(validating: "room"), scope: .project(.init(validating: "project")),
            expectedSpaceRevision: .init(7), items: [.init(itemId: .init(validating: "item"), expectedRevision: .init(revision))], capturedAt: time))
    }

    @Test func assignmentExactRevisionAndRestartEncoding() throws {
        let command = try assignment()
        let request = try ItemSpaceUploadRequest(command)
        let json = try #require(JSONSerialization.jsonObject(with: Data(request.commandJSON.utf8)) as? [String: Any])
        #expect(json["contractVersion"] as? String == "item-space-v1")
        #expect(json["createdAtMs"] as? String == "1000125")
        #expect(json["projectId"] as? String == "project")
        #expect(json["expectedSpaceRevision"] as? String == "7")
        let item = try #require((json["items"] as? [[String: Any]])?.first)
        #expect(item["expectedRevision"] as? String == "9007199254740993")
        #expect(item["currentSpaceId"] is NSNull)
        let restored = try OperationContractCodec.decode(AssignItemsToSpaceCommand.self,
            from: OperationContractCodec.encode(command))
        #expect(try ItemSpaceUploadRequest(restored).commandJSON == request.commandJSON)
        #expect(try ItemSpaceUploadRequest(restored).fingerprint == request.fingerprint)
        #expect(try JSONSerialization.jsonObject(with: request.rpcBody) as? [String: String] == ["p_command": request.commandJSON])
    }

    @Test func clearingPreservesEachOldSpaceAndExplicitNullScope() throws {
        let command = try ClearItemSpaceAssignmentsCommand(operationId: .init(validating: "clear"), draft: .init(
            accountId: .init(validating: "account"), actorPrincipalId: .init(validating: "actor"),
            operationContractVersion: .init(validating: "item-space-clearing-v1"), scope: .businessInventory,
            items: [.init(itemId: .init(validating: "b"), expectedRevision: .init(3), currentSpaceId: .init(validating: "room-b")),
                    .init(itemId: .init(validating: "a"), expectedRevision: .init(2), currentSpaceId: .init(validating: "room-a"))],
            capturedAt: Date(timeIntervalSince1970: 1000)))
        let request = try ItemSpaceUploadRequest(command)
        let json = try #require(JSONSerialization.jsonObject(with: Data(request.commandJSON.utf8)) as? [String: Any])
        #expect(json["projectId"] is NSNull)
        #expect(json["destinationSpaceId"] is NSNull)
        #expect(json["expectedSpaceRevision"] is NSNull)
        #expect(json["scopeKind"] as? String == "business_inventory")
        #expect(json["items"] as? [[String: String]] == [
            ["itemId":"a","expectedRevision":"2","currentSpaceId":"room-a"],
            ["itemId":"b","expectedRevision":"3","currentSpaceId":"room-b"]])
        #expect(request.subjectId == "a" && request.commandType == "clear_item_space_assignments")
        let restored = try OperationContractCodec.decode(ClearItemSpaceAssignmentsCommand.self,
            from: OperationContractCodec.encode(command))
        #expect(try ItemSpaceUploadRequest(restored).commandJSON == request.commandJSON)
    }

    @Test func invalidProviderInputsFailBeforeSending() throws {
        for revision in [UInt64(0), UInt64(Int64.max), UInt64.max] {
            let command = try assignment(revision: revision)
            #expect(throws: ItemSpaceUploadRequest.Failure.self) { try ItemSpaceUploadRequest(command) }
        }
        let old = try assignment(time: Date(timeIntervalSince1970: -1))
        #expect(throws: ItemSpaceUploadRequest.Failure.self) { try ItemSpaceUploadRequest(old) }
    }

    @Test func serverReceiptBindsExactIntentAndKnownOutcome() throws {
        let request = try ItemSpaceUploadRequest(assignment())
        let valid: [String: Any] = ["operation_id":"assign","account_id":"account","actor_principal_id":"actor",
            "command_type":"assign_items_to_space","contract_version":"item-space-v1",
            "command_fingerprint":request.fingerprint,"envelope_sha256":request.fingerprint,"subject_id":"room",
            "phase":"applied","result_code":"item_spaces_updated","client_created_at_ms":1000125,
            "server_received_at_ms":1000200,"completed_at_ms":1000200]
        func decode(_ json: [String: Any]) throws -> ItemSpaceServerResult {
            try JSONDecoder().decode(ItemSpaceServerResult.self, from: JSONSerialization.data(withJSONObject: json))
        }
        try decode(valid).validate(for: request)
        for key in ["operation_id","account_id","actor_principal_id","command_type","contract_version",
                    "command_fingerprint","envelope_sha256","subject_id","phase","result_code"] {
            var invalid = valid; invalid[key] = "foreign"
            #expect(throws: ItemSpaceServerResult.Failure.self) { try decode(invalid).validate(for: request) }
        }
        var rejected = valid; rejected["phase"] = "rejected"; rejected.removeValue(forKey: "result_code")
        rejected["error_code"] = "space_item_stale"
        try decode(rejected).validate(for: request)
        rejected["error_code"] = "unknown_success"
        #expect(throws: ItemSpaceServerResult.Failure.self) { try decode(rejected).validate(for: request) }
        for key in ["client_created_at_ms","server_received_at_ms","completed_at_ms"] {
            var invalid = valid; invalid[key] = -1
            #expect(throws: ItemSpaceServerResult.Failure.self) { try decode(invalid).validate(for: request) }
        }
    }
}
