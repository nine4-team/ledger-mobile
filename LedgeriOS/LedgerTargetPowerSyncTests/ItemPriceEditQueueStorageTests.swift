import Foundation
import LedgerTargetCore
@testable import LedgerTargetPowerSync
import PowerSync
import Testing

@Suite(.serialized)
struct ItemPriceEditQueueStorageTests {
    @Test func encryptedRestartRetainsExactCommandAndRollbackLeavesNoUpload() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-price-queue-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("ledger.sqlite").path
        let key = try LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "4c", count: 32))
        let database = try LedgerPowerSyncDatabaseFactory.open(absolutePath: path, encryptionKey: key)
        let account = try AccountID(validating: "price-account")
        let amount = Money(minorUnits: Int64.max, currency: try .init(validating: "USD"))
        let command = try EditUncollectedItemPriceCommand(
            operationId: ItemPriceEditOperationIdentity.make(accountId: account, uuid: UUID()),
            accountId: account, actorPrincipalId: .init(validating: "actor"),
            capturedAt: Date(timeIntervalSince1970: 123),
            payload: .init(projectId: .init(validating: "project"), itemId: .init(validating: "item"),
                placementId: .init(validating: "placement"), occurrenceId: .init(validating: "charge"),
                expectedPriceRevision: 0, expectedChargeRevision: 1,
                requestedPrice: amount, reviewedPrice: amount))
        let request = try EditUncollectedItemPriceUploadRequest(command)
        let json = String(decoding: try OperationContractCodec.encode(command.envelope), as: UTF8.self)
        let sql = """
            INSERT INTO spike_item_price_edit_commands
              (id,account_id,actor_principal_id,item_id,contract_version,fingerprint,envelope_json)
            VALUES (?,?,?,'item','item-uncollected-price-edit-v1',?,?)
            """
        enum InjectedFailure: Error { case rollback }
        do {
            try await database.writeTransaction { tx in
                try tx.execute(sql: sql, parameters: ["rolled-back", account.rawValue, "actor", request.fingerprint, json])
                throw InjectedFailure.rollback
            }
            Issue.record("Expected transaction rollback")
        } catch InjectedFailure.rollback {}
        try await database.writeTransaction { tx in
            try tx.execute(sql: sql, parameters: [command.envelope.operationId.rawValue,
                account.rawValue, "actor", request.fingerprint, json])
        }
        try await database.close()
        let reopened = try LedgerPowerSyncDatabaseFactory.open(absolutePath: path, encryptionKey: key)
        do {
            let rows = try await reopened.getAll("SELECT data FROM ps_crud") {
                try $0.getString(index: 0)
            }
            #expect(rows.count == 1)
            let row = try #require(rows.first)
            let object = try #require(JSONSerialization.jsonObject(with: Data(row.utf8)) as? [String: Any])
            #expect(object["type"] as? String == LedgerPowerSyncTable.itemPriceEditCommands)
            #expect(object["id"] as? String == command.envelope.operationId.rawValue)
            let fields = try #require(object["data"] as? [String: String])
            #expect(fields["fingerprint"] == request.fingerprint)
            #expect(fields["envelope_json"] == json)
            let queue = try #require(await reopened.getNextCrudTransaction())
            let restored = try EditUncollectedItemPriceUploadRequest.command(from: #require(queue.crud.first))
            #expect(try EditUncollectedItemPriceUploadRequest(restored).commandJSON == request.commandJSON)
            // Corrupt only queue evidence; a valid envelope must not excuse mismatched columns.
            for field in ["account_id", "actor_principal_id", "item_id", "contract_version", "fingerprint"] {
                _ = try await reopened.execute(sql: "UPDATE ps_crud SET data=json_set(data,?,?)",
                    parameters: ["$.data.\(field)", "different"])
                let corrupt = try #require(await reopened.getNextCrudTransaction())
                #expect(throws: LocalOperationIdentityGuardFailure.malformedEvidence) {
                    try EditUncollectedItemPriceUploadRequest.command(from: #require(corrupt.crud.first))
                }
                _ = try await reopened.execute(sql: "UPDATE ps_crud SET data=?", parameters: [row])
            }
            for (path, value) in [("$.id", "other-operation"), ("$.op", "PATCH"),
                                  ("$.type", LedgerPowerSyncTable.inventorySaleCommands)] {
                _ = try await reopened.execute(sql: "UPDATE ps_crud SET data=json_set(data,?,?)",
                    parameters: [path, value])
                let corrupt = try #require(await reopened.getNextCrudTransaction())
                #expect(throws: LocalOperationIdentityGuardFailure.malformedEvidence) {
                    try EditUncollectedItemPriceUploadRequest.command(from: #require(corrupt.crud.first))
                }
                _ = try await reopened.execute(sql: "UPDATE ps_crud SET data=?", parameters: [row])
            }
            try await reopened.close()
        } catch { try? await reopened.close(); throw error }
    }
}
