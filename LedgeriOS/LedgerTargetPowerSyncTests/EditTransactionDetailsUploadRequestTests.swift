import Foundation
import Testing
import LedgerTargetCore
import PowerSync
@testable import LedgerTargetPowerSync

struct EditTransactionDetailsUploadRequestTests {
    @Test func encryptedQueueRestartPreservesCommandAndRejectsTampering() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-transaction-edit-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("ledger.sqlite").path
        let key = try LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "4c", count: 32))
        let command = try command(), e = command.envelope
        let request = try EditTransactionDetailsUploadRequest(command)
        let json = String(decoding: try OperationContractCodec.encode(e), as: UTF8.self)
        let database = try LedgerPowerSyncDatabaseFactory.open(absolutePath: path, encryptionKey: key)
        do {
            _ = try await database.execute(sql: """
                INSERT INTO spike_transaction_details_edit_commands
                  (id,account_id,actor_principal_id,transaction_id,contract_version,fingerprint,envelope_json)
                VALUES (?,?,?,?,?,?,?)
                """, parameters: [e.operationId.rawValue,e.accountId.rawValue,e.actorPrincipalId.rawValue,
                    e.payload.transactionId.rawValue,e.contractVersion.rawValue,request.fingerprint,json])
            try await database.close()
        } catch { try? await database.close(); throw error }
        let reopened = try LedgerPowerSyncDatabaseFactory.open(absolutePath: path, encryptionKey: key)
        do {
            let original = try await reopened.get("SELECT data FROM ps_crud") { try $0.getString(index: 0) }
            let queue = try #require(await reopened.getNextCrudTransaction())
            #expect(queue.crud.count == 1)
            let restored = try EditTransactionDetailsUploadRequest.command(from: #require(queue.crud.first))
            #expect(try EditTransactionDetailsUploadRequest(restored).commandJSON == request.commandJSON)
            for (keyPath, value) in [
                ("$.id", "wrong"), ("$.type", LedgerPowerSyncTable.itemDetailsEditCommands), ("$.op", "PATCH"),
                ("$.data.account_id", "other"), ("$.data.actor_principal_id", "other"),
                ("$.data.transaction_id", "other"), ("$.data.contract_version", "wrong"),
                ("$.data.fingerprint", "wrong"), ("$.data.extra", "unexpected"),
                ("$.data.envelope_json", " \(json)")
            ] {
                _ = try await reopened.execute(sql: "UPDATE ps_crud SET data=json_set(data,?,?)", parameters: [keyPath,value])
                let corrupt = try #require(await reopened.getNextCrudTransaction())
                #expect(throws: LocalOperationIdentityGuardFailure.malformedEvidence) {
                    try EditTransactionDetailsUploadRequest.command(from: #require(corrupt.crud.first))
                }
                _ = try await reopened.execute(sql: "UPDATE ps_crud SET data=?", parameters: [original])
            }
            try await reopened.close()
        } catch { try? await reopened.close(); throw error }
    }
    @Test func encodedByteLimitIncludesEnvelopeAndEscaping() throws {
        let original = try command()
        func request(_ notes: String) throws -> EditTransactionDetailsUploadRequest {
            let e = original.envelope
            return try .init(.init(operationId: e.operationId, actorPrincipalId: e.actorPrincipalId,
                capturedAt: e.clientCreatedAt, payload: .init(transactionId: e.payload.transactionId,
                    scope: e.payload.scope, expectedRevision: e.payload.expectedRevision,
                    changes: .init(notes: .set(notes)))))
        }
        let overhead = try request("").commandJSON.utf8.count
        let remaining = EditTransactionDetailsUploadRequest.maximumBytes - overhead
        #expect(try request(String(repeating: "a", count: remaining)).commandJSON.utf8.count == 4 * 1024 * 1024)
        for notes in [String(repeating: "a", count: remaining + 1),
                      String(repeating: "é", count: remaining / 2 + 1),
                      String(repeating: "\n", count: remaining / 2 + 1)] {
            #expect(throws: EditTransactionDetailsUploadRequest.Failure.self) { try request(notes) }
        }
    }
    private func command(inventory: Bool = false) throws -> EditTransactionDetailsCommand {
        let account = try AccountID(validating: "account")
        return try .init(operationId: TransactionDetailsEditOperationIdentity.make(accountId: account,
            uuid: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!),
            actorPrincipalId: .init(validating: "member"), capturedAt: Date(timeIntervalSince1970: 123),
            payload: .init(transactionId: .init(validating: "transaction"), scope: inventory
                ? .businessInventory(accountId: account)
                : .project(accountId: account, projectId: .init(validating: "project"), clientId: .init(validating: "client")),
                expectedRevision: Int64.max - 1,
                changes: .init(source: .clear, notes: .set(""), hasEmailReceipt: false)))
    }

    @Test(arguments: [false, true]) func exactSparseWireAndStableRetry(inventory: Bool) throws {
        let command = try command(inventory: inventory)
        let request = try EditTransactionDetailsUploadRequest(command)
        if !inventory {
            #expect(request.fingerprint == "928e65eaf35551d4dd2e406a1f8cb06aab28f135fca887101276bbd167358a1d")
        }
        let wire = try #require(try JSONSerialization.jsonObject(with: Data(request.commandJSON.utf8)) as? [String: Any])
        #expect(wire.count == 11)
        #expect(wire["createdAtMs"] as? String == "123000")
        #expect(wire["expectedRevision"] as? String == "9223372036854775806")
        #expect(wire["scopeKind"] as? String == (inventory ? "business_inventory" : "project"))
        if inventory {
            #expect(wire["projectId"] is NSNull && wire["clientId"] is NSNull)
        } else {
            #expect(wire["projectId"] as? String == "project" && wire["clientId"] as? String == "client")
        }
        let changes = try #require(wire["changes"] as? [String: Any])
        #expect(changes.count == 3 && changes["paymentMethod"] == nil)
        #expect(changes["source"] is NSNull && changes["notes"] as? String == "")
        #expect(changes["hasEmailReceipt"] as? Bool == false)
        let restored = try OperationContractCodec.decode(EditTransactionDetailsCommand.self,
            from: OperationContractCodec.encode(command))
        let retry = try EditTransactionDetailsUploadRequest(restored)
        #expect(retry.commandJSON == request.commandJSON && retry.fingerprint == request.fingerprint)
        #expect(try JSONDecoder().decode([String: String].self, from: request.rpcBody)["p_command"] == request.commandJSON)
        #expect(AccountBoundOperationIdentity.isValid(command.envelope.operationId,
            family: .transactionDetailsEdit, accountId: command.envelope.accountId))
        #expect(!AccountBoundOperationIdentity.isValid(command.envelope.operationId,
            family: .itemDetailsEdit, accountId: command.envelope.accountId))
    }

    @Test func receiptMustMatchIdentityRequestAndTerminalState() throws {
        let command = try command(), request = try EditTransactionDetailsUploadRequest(command)
        let valid: [String: Any] = [
            "operation_id": command.envelope.operationId.rawValue, "account_id": "account", "actor_principal_id": "member",
            "command_type": "edit_transaction_details", "contract_version": "transaction-details-edit-v1",
            "command_fingerprint": request.fingerprint, "envelope_sha256": request.fingerprint,
            "subject_id": "transaction", "phase": "applied", "result_code": "transaction_details_updated",
            "client_created_at_ms": 123000, "server_received_at_ms": 124000, "completed_at_ms": 124000
        ]
        func validate(_ wire: [String: Any]) throws {
            try JSONDecoder().decode(EditTransactionDetailsServerResult.self,
                from: JSONSerialization.data(withJSONObject: wire)).validate(for: command)
        }
        try validate(valid)
        for field in ["operation_id", "account_id", "actor_principal_id", "command_type", "contract_version",
                      "command_fingerprint", "envelope_sha256", "subject_id", "phase", "result_code", "error_code", "request_sha256"] {
            var invalid = valid; invalid[field] = "wrong"
            #expect(throws: EditTransactionDetailsServerResult.Failure.self) { try validate(invalid) }
        }
        for (field, value) in [("client_created_at_ms", 123001), ("server_received_at_ms", -1), ("completed_at_ms", 123999)] {
            var invalid = valid; invalid[field] = value
            #expect(throws: EditTransactionDetailsServerResult.Failure.self) { try validate(invalid) }
        }
        var rejected = valid; rejected["phase"] = "rejected"; rejected.removeValue(forKey: "result_code")
        for error in EditTransactionDetailsServerResult.rejections {
            rejected["error_code"] = error
            try validate(rejected)
        }
        rejected["error_code"] = "unknown"
        #expect(throws: EditTransactionDetailsServerResult.Failure.self) { try validate(rejected) }
    }
}
