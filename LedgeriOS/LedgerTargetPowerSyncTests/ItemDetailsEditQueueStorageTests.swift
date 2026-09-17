import Foundation
import LedgerTargetCore
@testable import LedgerTargetPowerSync
import PowerSync
import Testing

struct ItemDetailsEditQueueStorageTests {
    @Test(arguments: [false, true]) func encryptedRestartAndQueueValidation(market: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-details-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("ledger.sqlite").path
        let key = try LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "4c", count: 32))
        let account = try AccountID(validating: "account")
        let id = try ItemDetailsEditOperationIdentity.make(accountId: account, uuid: UUID())
        #expect(!AccountBoundOperationIdentity.isValid(id, family: .itemPriceEdit, accountId: account))
        let other = try AccountID(validating: "other")
        #expect(!AccountBoundOperationIdentity.isValid(id, family: .itemDetailsEdit, accountId: other))
        let command = try EditItemDetailsCommand(operationId: id, accountId: account,
            actorPrincipalId: .init(validating: "actor"), capturedAt: Date(timeIntervalSince1970: 123),
            payload: .init(items: [.init(itemId: .init(validating: "item"), expectedRevision: 7)],
                           changes: .init(sku: .clear, notes: .set("  notes  "), bookmark: false,
                               marketValue: market ? .set(Money(minorUnits: 9007199254740993, currency: try .init(validating: "USD"))) : nil)))
        let request = try EditItemDetailsUploadRequest(command)
        let json = String(decoding: try OperationContractCodec.encode(command.envelope), as: UTF8.self)
        let database = try LedgerPowerSyncDatabaseFactory.open(absolutePath: path, encryptionKey: key)
        do {
            _ = try await database.execute(sql: """
                INSERT INTO spike_local_operations(id,account_id,actor_principal_id,contract_version,fingerprint,
                  subject_id,local_state,accepted_at_ms,updated_at_ms,command_type,command_envelope_json)
                VALUES (?,?,'actor',?,?,'item','queued',123000,123000,'edit_item_details',?)
                """, parameters: [id.rawValue, account.rawValue, command.envelope.contractVersion.rawValue, request.fingerprint, json])
            _ = try await database.execute(sql: """
                INSERT INTO spike_item_details_edit_commands
                  (id,account_id,actor_principal_id,item_id,contract_version,fingerprint,envelope_json)
                VALUES (?,?,'actor','item',?,?,?)
                """, parameters: [id.rawValue, account.rawValue, command.envelope.contractVersion.rawValue, request.fingerprint, json])
            try await database.close()
        } catch { try? await database.close(); throw error }
        let reopened = try LedgerPowerSyncDatabaseFactory.open(absolutePath: path, encryptionKey: key)
        do {
            try await reopened.readTransaction { local throws in
                #expect(try LocalOperationIdentityGuard.inspect(transaction: local, operationId: id,
                    expectedFamily: .editItemDetails, expectedFingerprint: request.fingerprint) == .matchingOwner)
                #expect(throws: LocalOperationIdentityGuardFailure.self) {
                    try LocalOperationIdentityGuard.inspect(transaction: local, operationId: id,
                        expectedFamily: .editUncollectedItemPrice, expectedFingerprint: request.fingerprint)
                }
                #expect(throws: LocalOperationIdentityGuardFailure.self) {
                    try LocalOperationIdentityGuard.inspect(transaction: local, operationId: id,
                        expectedFamily: .editItemDetails, expectedFingerprint: String(repeating: "0", count: 64))
                }
            }
            let original = try await reopened.get("SELECT data FROM ps_crud") { try $0.getString(index: 0) }
            let queue = try #require(await reopened.getNextCrudTransaction())
            #expect(queue.crud.count == 1)
            let restored = try EditItemDetailsUploadRequest.command(from: #require(queue.crud.first))
            #expect(try EditItemDetailsUploadRequest(restored).commandJSON == request.commandJSON)
            for field in ["account_id", "actor_principal_id", "item_id", "contract_version", "fingerprint"] {
                _ = try await reopened.execute(sql: "UPDATE ps_crud SET data=json_set(data,?,?)",
                    parameters: ["$.data.\(field)", "wrong"])
                let corrupt = try #require(await reopened.getNextCrudTransaction())
                #expect(throws: LocalOperationIdentityGuardFailure.malformedEvidence) {
                    try EditItemDetailsUploadRequest.command(from: #require(corrupt.crud.first))
                }
                _ = try await reopened.execute(sql: "UPDATE ps_crud SET data=?", parameters: [original])
            }
            try await reopened.close()
        } catch { try? await reopened.close(); throw error }
    }
}
