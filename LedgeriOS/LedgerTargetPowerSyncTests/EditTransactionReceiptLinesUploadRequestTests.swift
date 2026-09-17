import Foundation
import Testing
import LedgerTargetCore
import PowerSync
@testable import LedgerTargetPowerSync

struct EditTransactionReceiptLinesUploadRequestTests {
    @Test func queuedEnvelopeIsCanonicalAndAccountBound() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("receipt-wire-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try LedgerPowerSyncDatabaseFactory.open(absolutePath: root.appendingPathComponent("ledger.sqlite").path,
            encryptionKey: .init(hexadecimal: String(repeating: "5a", count: 32)))
        do {
            let account = try AccountID(validating: "account")
            let id = try TransactionReceiptLinesEditOperationIdentity.make(accountId: account, uuid: UUID())
            let command = try EditTransactionReceiptLinesCommand(operationId: id,
                actorPrincipalId: .init(validating: "principal"), capturedAt: Date(timeIntervalSince1970: 123),
                payload: .init(transactionId: .init(validating: "transaction"), scope: .businessInventory(accountId: account),
                    currency: .init(validating: "USD"), expectedLines: [], lines: []))
            let envelope = String(decoding: try OperationContractCodec.encode(command.envelope), as: UTF8.self)
            let fingerprint = try EditTransactionReceiptLinesUploadRequest(command).fingerprint
            func entry(accountValue: String = "account", json: String? = nil, digest: String? = nil,
                       operationId: String? = nil) async throws -> CrudEntry {
                _ = try await database.execute(sql: """
                    INSERT INTO spike_transaction_receipt_lines_edit_commands
                    (id,account_id,actor_principal_id,transaction_id,contract_version,fingerprint,envelope_json)
                    VALUES (?,?, 'principal','transaction','transaction-receipt-lines-edit-v1',?,?)
                    """, parameters: [operationId ?? id.rawValue, accountValue, digest ?? fingerprint, json ?? envelope])
                let batch = try #require(await database.getNextCrudTransaction())
                let result = try #require(batch.crud.first)
                try await batch.complete()
                return result
            }
            let valid = try await entry()
            #expect(try EditTransactionReceiptLinesUploadRequest.command(from: valid).envelope.operationId == id)
            for invalid in [try await entry(accountValue: "foreign"), try await entry(json: " \(envelope)"),
                            try await entry(digest: String(repeating: "0", count: 64)),
                            try await entry(operationId: "wrong-namespace")] {
                #expect(throws: LocalOperationIdentityGuardFailure.malformedEvidence) {
                    try EditTransactionReceiptLinesUploadRequest.command(from: invalid)
                }
            }
            #expect(!AccountBoundOperationIdentity.isValid(id, family: .transactionDetailsEdit, accountId: account))
            #expect(!AccountBoundOperationIdentity.isValid(id, family: .transactionReceiptLinesEdit,
                accountId: try .init(validating: "other")))
            try await database.close()
        } catch { try? await database.close(); throw error }
    }
    @Test func receiptArraySizeIncludesPostgresSpacing() throws {
        func request(_ text: String) throws -> EditTransactionReceiptLinesUploadRequest {
            let currency = try CurrencyCode(validating: "USD")
            let line = try NonItemReceiptLine(id: .init(validating: "line"), description: .init(validating: text),
                magnitude: .init(minorUnits: 1, currency: currency), effect: .increase)
            let command = try EditTransactionReceiptLinesCommand(operationId: .init(validating: "edit"),
                actorPrincipalId: .init(validating: "principal"), capturedAt: Date(timeIntervalSince1970: 1),
                payload: .init(transactionId: .init(validating: "transaction"),
                    scope: .businessInventory(accountId: .init(validating: "account")), currency: currency,
                    expectedLines: [], lines: [line]))
            return try .init(command)
        }
        let wire = try #require(JSONSerialization.jsonObject(with: Data(request("x").commandJSON.utf8)) as? [String: Any])
        let array = try #require(wire["lines"] as? [[String: Any]])
        let overhead = try JSONSerialization.data(withJSONObject: array, options: [.sortedKeys, .withoutEscapingSlashes]).count + 9 - 1
        _ = try request(String(repeating: "x", count: 262_144 - overhead))
        #expect(throws: EditTransactionReceiptLinesUploadRequest.Failure.payloadTooLarge) {
            try request(String(repeating: "x", count: 262_145 - overhead))
        }
        #expect(throws: EditTransactionReceiptLinesUploadRequest.Failure.payloadTooLarge) {
            try request(String(repeating: "🪑", count: 70_000))
        }
    }
    @Test func exactMoneyOrderedLinesAndStableRetryBytes() throws {
        let currency = try CurrencyCode(validating: "USD")
        let line = try NonItemReceiptLine(id: .init(validating: "source-tax"),
            description: .init(validating: "  Tax refund 🪑  "),
            magnitude: .init(minorUnits: 9_007_199_254_740_993, currency: currency),
            effect: .decrease, quantity: Int64.min)
        let command = try EditTransactionReceiptLinesCommand(operationId: .init(validating:
            "transaction-receipt-edit-9af211329b2fc82e5efe906062c730082819b23fe8394bc435e0b1bf0458eb54-11111111-2222-3333-4444-555555555555"),
            actorPrincipalId: .init(validating: "principal"), capturedAt: Date(timeIntervalSince1970: 123),
            payload: .init(transactionId: .init(validating: "transaction"),
                scope: .businessInventory(accountId: .init(validating: "account")),
                currency: currency, expectedLines: [line], lines: []))
        let request = try EditTransactionReceiptLinesUploadRequest(command)
        #expect(request.fingerprint == "4cca4f266dd41bd787736998a3f500a155dfc4cf7667b9fd18939a1733224772")
        let restored = try OperationContractCodec.decode(EditTransactionReceiptLinesCommand.self,
            from: OperationContractCodec.encode(command))
        #expect(try EditTransactionReceiptLinesUploadRequest(restored).commandJSON == request.commandJSON)
        #expect(try EditTransactionReceiptLinesUploadRequest(restored).fingerprint == request.fingerprint)
        let wire = try #require(JSONSerialization.jsonObject(with: Data(request.commandJSON.utf8)) as? [String: Any])
        #expect(wire.count == 12)
        #expect(wire["projectId"] is NSNull && wire["clientId"] is NSNull)
        let expected = try #require(wire["expectedLines"] as? [[String: Any]])
        #expect(expected[0]["amountMinorUnits"] as? String == "9007199254740993")
        #expect(expected[0]["quantity"] as? String == "-9223372036854775808")
        #expect(expected[0]["description"] as? String == "  Tax refund 🪑  ")
        #expect((wire["lines"] as? [Any])?.isEmpty == true)
        let body = try #require(JSONSerialization.jsonObject(with: request.rpcBody) as? [String: String])
        #expect(body == ["p_command": request.commandJSON])
        let e = command.envelope
        var result: [String: Any] = ["operation_id": e.operationId.rawValue, "account_id": e.accountId.rawValue,
            "actor_principal_id": e.actorPrincipalId.rawValue, "subject_id": e.payload.transactionId.rawValue,
            "command_type": "edit_transaction_receipt_lines", "contract_version": e.contractVersion.rawValue,
            "command_fingerprint": request.fingerprint, "envelope_sha256": request.fingerprint,
            "request_sha256": NSNull(), "client_created_at_ms": 123000, "server_received_at_ms": 124000,
            "completed_at_ms": 124000, "phase": "applied", "result_code": "transaction_receipt_lines_updated", "error_code": NSNull(),
            "receipt_lines_revision": "9007199254740993"]
        func decode() throws -> EditTransactionReceiptLinesServerResult {
            try JSONDecoder().decode(EditTransactionReceiptLinesServerResult.self, from: JSONSerialization.data(withJSONObject: result))
        }
        try decode().validate(for: command)
        for revision in [NSNull(), "0", "01", "9223372036854775808"] as [Any] {
            result["receipt_lines_revision"] = revision
            #expect(throws: EditTransactionReceiptLinesServerResult.Failure.receiptMismatch) { try decode().validate(for: command) }
        }
        result["receipt_lines_revision"] = "2"
        result["account_id"] = "other"
        #expect(throws: EditTransactionReceiptLinesServerResult.Failure.receiptMismatch) { try decode().validate(for: command) }
    }
}
