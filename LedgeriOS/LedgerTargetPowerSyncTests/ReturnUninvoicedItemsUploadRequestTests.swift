import Foundation
import Testing
import LedgerTargetCore
@testable import LedgerTargetPowerSync

@Suite("Uninvoiced return provider contract")
struct ReturnUninvoicedItemsUploadRequestTests {
    @Test func sharedMCPWireFixture() throws {
        struct Fixture: Decodable {
            struct Input: Decodable {
                struct Payload: Decodable {
                    struct Item: Decodable {
                        let itemId: ItemID
                        let placementId: EntityID
                        let chargeId: BillableItemOccurrenceID
                        let expectedChargeRevision: String
                        let inventoryPlacementId: EntityID, returnOccurrenceId: EntityID
                    }
                    let projectId: ProjectID
                    let items: [Item]
                }
                let operationUUID: UUID
                let clientCreatedAtMilliseconds: Int64
                let payload: Payload
            }
            let accountId: AccountID, principalId: PrincipalID
            let input: Input
            let operationId: String, fingerprint: String
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf:
            root.appendingPathComponent("LedgerTargetMCP/tests/fixtures/uninvoiced-return.json")))
        let id = try ReturnUninvoicedItemsOperationIdentity.make(accountId: fixture.accountId, uuid: fixture.input.operationUUID)
        let items = try fixture.input.payload.items.map { row in
            try ReturnUninvoicedItemsPayload.Item(itemId: row.itemId, placementId: row.placementId,
                chargeId: row.chargeId, expectedChargeRevision: #require(Int64(row.expectedChargeRevision)),
                inventoryPlacementId: row.inventoryPlacementId, returnOccurrenceId: row.returnOccurrenceId)
        }
        let command = try ReturnUninvoicedItemsCommand(operationId: id, accountId: fixture.accountId,
            actorPrincipalId: fixture.principalId,
            capturedAt: Date(timeIntervalSince1970: Double(fixture.input.clientCreatedAtMilliseconds) / 1000),
            payload: .init(projectId: fixture.input.payload.projectId, items: items))
        #expect(id.rawValue == fixture.operationId)
        #expect(try ReturnUninvoicedItemsUploadRequest(command).fingerprint == fixture.fingerprint)
    }

    private func command() throws -> ReturnUninvoicedItemsCommand {
        try .init(operationId: .init(validating: "return"), accountId: .init(validating: "account"),
            actorPrincipalId: .init(validating: "actor"), capturedAt: Date(timeIntervalSince1970: 1000),
            payload: .init(projectId: .init(validating: "project"), items: [
                .init(itemId: .init(validating: "item"), placementId: .init(validating: "old"),
                    chargeId: .init(validating: "charge"), expectedChargeRevision: Int64.max - 1,
                    inventoryPlacementId: .init(validating: "new"), returnOccurrenceId: .init(validating: "return-fact"))]))
    }

    @Test func exactWireAndRestart() throws {
        let command = try command()
        let request = try ReturnUninvoicedItemsUploadRequest(command)
        let json = try #require(JSONSerialization.jsonObject(with: Data(request.commandJSON.utf8)) as? [String: Any])
        #expect(Set(json.keys) == Set(["operationId", "accountId", "actorPrincipalId", "projectId",
                                      "contractVersion", "createdAtMs", "items"]))
        let items = try #require(json["items"] as? [[String: String]])
        #expect(items[0]["expectedChargeRevision"] == "9223372036854775806")
        #expect(items[0]["chargeId"] == "charge")
        let body = try #require(JSONSerialization.jsonObject(with: request.rpcBody) as? [String: String])
        #expect(body == ["p_command": request.commandJSON])
        let restored = try OperationContractCodec.decode(ReturnUninvoicedItemsCommand.self,
            from: OperationContractCodec.encode(command))
        let replay = try ReturnUninvoicedItemsUploadRequest(restored)
        #expect(replay.commandJSON == request.commandJSON)
        #expect(replay.fingerprint == request.fingerprint)
    }

    @Test func receiptMustMatchExactIntent() throws {
        let command = try command()
        let digest = try ReturnUninvoicedItemsUploadRequest(command).fingerprint
        let valid: [String: Any] = ["operation_id":"return", "account_id":"account",
            "actor_principal_id":"actor", "subject_id":"project", "command_type":"return_uninvoiced_items",
            "contract_version":"return-uninvoiced-items-v1", "command_fingerprint":digest, "envelope_sha256":digest,
            "phase":"applied", "result_code":"uninvoiced_items_returned", "client_created_at_ms":1000000,
            "server_received_at_ms":1000001, "completed_at_ms":1000002]
        func validate(_ fields: [String: Any]) throws {
            let result = try JSONDecoder().decode(ReturnUninvoicedItemsServerResult.self,
                from: JSONSerialization.data(withJSONObject: fields))
            try result.validate(for: command)
        }
        try validate(valid)
        for key in ["operation_id", "account_id", "actor_principal_id", "subject_id", "command_type",
                    "contract_version", "command_fingerprint", "envelope_sha256", "phase", "result_code"] {
            var fields = valid; fields[key] = "wrong"
            #expect(throws: ReturnUninvoicedItemsServerResult.Failure.receiptMismatch) { try validate(fields) }
        }
        for error in ReturnUninvoicedItemsServerResult.rejections {
            var fields = valid; fields["phase"] = "rejected"; fields.removeValue(forKey: "result_code")
            fields["error_code"] = error
            try validate(fields)
        }
        var invalid = valid; invalid["completed_at_ms"] = 0
        #expect(throws: ReturnUninvoicedItemsServerResult.Failure.receiptMismatch) { try validate(invalid) }
        invalid = valid; invalid["error_code"] = "return_charge_stale"
        #expect(throws: ReturnUninvoicedItemsServerResult.Failure.receiptMismatch) { try validate(invalid) }
    }
}
