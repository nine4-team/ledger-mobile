import Foundation
import Testing
import LedgerTargetCore
@testable import LedgerTargetPowerSync

struct EditUncollectedItemPriceUploadRequestTests {
    @Test func sharedMCPWireFixture() throws {
        struct Fixture: Decodable {
            struct Input: Decodable {
                let operationUUID: UUID
                let clientCreatedAtMilliseconds: Int64
                let payload: [String: String]
            }
            let accountId: AccountID, principalId: PrincipalID
            let input: Input
            let operationId: String, fingerprint: String
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf:
            root.appendingPathComponent("LedgerTargetMCP/tests/fixtures/item-price-edit.json")))
        let p = fixture.input.payload
        func field(_ name: String) throws -> String { try #require(p[name]) }
        let currency = try CurrencyCode(validating: field("currency"))
        let id = try ItemPriceEditOperationIdentity.make(accountId: fixture.accountId, uuid: fixture.input.operationUUID)
        let command = try EditUncollectedItemPriceCommand(operationId: id, accountId: fixture.accountId,
            actorPrincipalId: fixture.principalId,
            capturedAt: Date(timeIntervalSince1970: Double(fixture.input.clientCreatedAtMilliseconds) / 1000),
            payload: .init(projectId: .init(validating: field("projectId")),
                itemId: .init(validating: field("itemId")), placementId: .init(validating: field("placementId")),
                occurrenceId: .init(validating: field("occurrenceId")),
                expectedPriceRevision: #require(Int64(field("expectedPriceRevision"))),
                expectedChargeRevision: #require(Int64(field("expectedChargeRevision"))),
                requestedPrice: .init(minorUnits: #require(Int64(field("requestedPriceMinorUnits"))), currency: currency),
                reviewedPrice: .init(minorUnits: #require(Int64(field("reviewedPriceMinorUnits"))), currency: currency)))
        #expect(id.rawValue == fixture.operationId)
        #expect(try EditUncollectedItemPriceUploadRequest(command).fingerprint == fixture.fingerprint)
    }

    @Test func acceptedIdentityIsAccountAndCommandBound() throws {
        let account = try AccountID(validating: "account"), other = try AccountID(validating: "other")
        let uuid = UUID()
        let id = try ItemPriceEditOperationIdentity.make(accountId: account, uuid: uuid)
        #expect(try ItemPriceEditOperationIdentity.make(accountId: account, uuid: uuid) == id)
        #expect(AccountBoundOperationIdentity.isValid(id, family: .itemPriceEdit, accountId: account))
        #expect(!AccountBoundOperationIdentity.isValid(id, family: .itemPriceEdit, accountId: other))
        #expect(!AccountBoundOperationIdentity.isValid(id, family: .inventorySale, accountId: account))
    }

    @Test func wireKeepsExactMoneyAndStableRetryBytes() throws {
        let money = Money(minorUnits: Int64.max, currency: try .init(validating: "USD"))
        let command = try EditUncollectedItemPriceCommand(operationId: .init(validating: "price-op"),
            accountId: .init(validating: "account"), actorPrincipalId: .init(validating: "actor"),
            capturedAt: Date(timeIntervalSince1970: 123), payload: .init(projectId: .init(validating: "project"),
                itemId: .init(validating: "item"), placementId: .init(validating: "placement"),
                occurrenceId: .init(validating: "charge"), expectedPriceRevision: 0,
                expectedChargeRevision: Int64.max - 1, requestedPrice: money, reviewedPrice: money))
        let request = try EditUncollectedItemPriceUploadRequest(command)
        let fields = try JSONDecoder().decode([String: String].self, from: Data(request.commandJSON.utf8))
        #expect(fields.count == 14)
        #expect(fields["requestedPriceMinorUnits"] == "9223372036854775807")
        #expect(fields["expectedChargeRevision"] == "9223372036854775806")
        #expect(fields["expectedPriceRevision"] == "0")
        #expect(fields["createdAtMs"] == "123000")
        let restored = try OperationContractCodec.decode(EditUncollectedItemPriceCommand.self,
            from: OperationContractCodec.encode(command))
        #expect(try EditUncollectedItemPriceUploadRequest(restored).fingerprint == request.fingerprint)
        #expect(try JSONDecoder().decode([String: String].self, from: request.rpcBody)["p_command"] == request.commandJSON)
        let valid: [String: Any] = [
            "operation_id": "price-op", "account_id": "account", "actor_principal_id": "actor",
            "command_type": "edit_uncollected_item_price", "contract_version": "item-uncollected-price-edit-v1",
            "command_fingerprint": request.fingerprint, "envelope_sha256": request.fingerprint,
            "subject_id": "item", "phase": "applied", "result_code": "item_price_updated",
            "client_created_at_ms": 123000, "server_received_at_ms": 124000, "completed_at_ms": 124000
        ]
        func decode(_ fields: [String: Any]) throws -> EditUncollectedItemPriceServerResult {
            try JSONDecoder().decode(EditUncollectedItemPriceServerResult.self,
                from: JSONSerialization.data(withJSONObject: fields))
        }
        try decode(valid).validate(for: command)
        for key in ["operation_id", "account_id", "actor_principal_id", "subject_id", "command_type",
                    "contract_version", "command_fingerprint", "envelope_sha256", "result_code", "phase"] {
            var invalid = valid
            invalid[key] = "mismatched"
            #expect(throws: EditUncollectedItemPriceServerResult.Failure.receiptMismatch) {
                try decode(invalid).validate(for: command)
            }
        }
        var rejected = valid
        rejected["phase"] = "rejected"
        rejected.removeValue(forKey: "result_code")
        for code in EditUncollectedItemPriceServerResult.rejections {
            rejected["error_code"] = code
            try decode(rejected).validate(for: command)
        }
        rejected["error_code"] = "unrecognized"
        #expect(throws: EditUncollectedItemPriceServerResult.Failure.receiptMismatch) {
            try decode(rejected).validate(for: command)
        }
        for (key, value) in [("client_created_at_ms", 123001), ("server_received_at_ms", -1), ("completed_at_ms", 123999)] {
            var invalid = valid
            invalid[key] = value
            #expect(throws: EditUncollectedItemPriceServerResult.Failure.receiptMismatch) {
                try decode(invalid).validate(for: command)
            }
        }
    }
}
