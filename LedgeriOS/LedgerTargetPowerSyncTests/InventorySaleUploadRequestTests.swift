import CryptoKit
import Foundation
import Testing
import LedgerTargetCore
@testable import LedgerTargetPowerSync

@Suite("Inventory sale provider contract")
struct InventorySaleUploadRequestTests {
    @Test func sharedMCPWireFixture() throws {
        struct Fixture: Decodable {
            struct Input: Decodable {
                let operationUUID: UUID
                let clientCreatedAtMilliseconds: Int64
                let payload: InventorySalePayload
            }
            let accountId: AccountID, principalId: PrincipalID
            let input: Input
            let operationId: String, fingerprint: String
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf:
            root.appendingPathComponent("LedgerTargetMCP/tests/fixtures/inventory-sale.json")))
        let id = try InventorySaleOperationIdentity.make(accountId: fixture.accountId,uuid: fixture.input.operationUUID)
        let command = try InventorySaleCommand(operationId: id,accountId: fixture.accountId,
            actorPrincipalId: fixture.principalId,
            capturedAt: Date(timeIntervalSince1970: Double(fixture.input.clientCreatedAtMilliseconds) / 1000),
            payload: fixture.input.payload)
        #expect(id.rawValue == fixture.operationId)
        #expect(try InventorySaleUploadRequest(command).fingerprint == fixture.fingerprint)
    }

    private func command() throws -> InventorySaleCommand {
        try .init(operationId: .init(validating: "sale"), accountId: .init(validating: "account"),
            actorPrincipalId: .init(validating: "actor"), capturedAt: Date(timeIntervalSince1970: 1000),
            payload: .init(projectId: .init(validating: "project"), currency: .init(validating: "USD"),
                items: [.init(itemId: .init(validating: "item"), placementId: .init(validating: "old"),
                    priceRevision: 0, reviewedPriceMinorUnits: Int64.max,
                    newPlacementId: .init(validating: "new"), occurrenceId: .init(validating: "charge"))]))
    }

    @Test func exactServerShapeAndReplay() throws {
        let command = try command()
        let request = try InventorySaleUploadRequest(command)
        let json = try #require(JSONSerialization.jsonObject(with: Data(request.commandJSON.utf8)) as? [String: Any])
        #expect(Set(json.keys) == Set(["operationId", "accountId", "actorPrincipalId", "projectId",
                                      "contractVersion", "createdAtMs", "currency", "items"]))
        #expect(json["createdAtMs"] as? String == "1000000")
        let rows = try #require(json["items"] as? [[String: String]])
        #expect(rows[0]["reviewedPriceMinorUnits"] == "9223372036854775807")
        #expect(rows[0]["priceRevision"] == "0")
        let body = try #require(JSONSerialization.jsonObject(with: request.rpcBody) as? [String: String])
        #expect(body == ["p_command": request.commandJSON])
        let restored = try OperationContractCodec.decode(InventorySaleCommand.self,
            from: OperationContractCodec.encode(command))
        #expect(try InventorySaleUploadRequest(restored).commandJSON == request.commandJSON)
        #expect(request.fingerprint == SHA256.hash(data: Data(request.commandJSON.utf8))
            .map { String(format: "%02x", $0) }.joined())
    }

    @Test func rejectsMisboundOrImpossibleResults() throws {
        let command = try command()
        let digest = try InventorySaleUploadRequest(command).fingerprint
        var values: [String: Any] = ["operation_id":"sale", "account_id":"account",
            "actor_principal_id":"actor", "subject_id":"project", "command_type":"sell_inventory_items",
            "contract_version":"inventory-sale-v1", "command_fingerprint":digest, "envelope_sha256":digest,
            "phase":"applied", "result_code":"inventory_items_sold", "client_created_at_ms":1000000,
            "server_received_at_ms":1000001, "completed_at_ms":1000002]
        func result(_ fields: [String: Any]) throws -> InventorySaleServerResult {
            try JSONDecoder().decode(InventorySaleServerResult.self,
                from: JSONSerialization.data(withJSONObject: fields))
        }
        try result(values).validate(for: command)
        for (key, wrong): (String, Any) in [("account_id", "other"), ("subject_id", "other"),
            ("command_fingerprint", "wrong"), ("completed_at_ms", 0), ("error_code", "sale_price_stale")] {
            var modified = values; modified[key] = wrong
            #expect(throws: InventorySaleServerResult.Failure.receiptMismatch) {
                try result(modified).validate(for: command)
            }
        }
        values["phase"] = "rejected"; values.removeValue(forKey: "result_code")
        values["error_code"] = "sale_price_stale"
        try result(values).validate(for: command)
        values["error_code"] = "unknown"
        #expect(throws: InventorySaleServerResult.Failure.receiptMismatch) {
            try result(values).validate(for: command)
        }
    }
}
