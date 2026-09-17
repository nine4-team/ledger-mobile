import Foundation
import LedgerTargetCore
import PowerSync
import Testing
@testable import LedgerTargetPowerSync

@Suite(.serialized)
struct TransactionDetailsEditQueueTests {
    @Test(arguments: [false, true])
    func admissionRestartReplayAndTerminalReceipt(inventory: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("transaction-save-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("ledger.sqlite").path
        let key = try LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "5a", count: 32))
        let account = try AccountID(validating: "account"), principal = try PrincipalID(validating: "member")
        let scope: TransactionScope = inventory ? .businessInventory(accountId: account)
            : .project(accountId: account, projectId: try .init(validating: "project"), clientId: try .init(validating: "client"))
        let fence = LedgerWorkspaceAccessFence()
        var db = try LedgerPowerSyncDatabaseFactory.open(absolutePath: path, encryptionKey: key)
        func store(_ database: any PowerSyncDatabaseProtocol,
                   checkpoint: @escaping @Sendable () throws -> Void = {}) -> TransactionDetailsEditPowerSyncStore {
            .init(database: database, accountId: account, principalId: principal, accessFence: fence,
                  now: { Date(timeIntervalSince1970: 124) }, afterOperationWrite: checkpoint)
        }
        func command(revision: Int64 = 7, id: OperationID? = nil, notes: String = "Edited offline") throws -> EditTransactionDetailsCommand {
            try .init(operationId: id ?? TransactionDetailsEditOperationIdentity.make(accountId: account, uuid: UUID()),
                actorPrincipalId: principal, capturedAt: Date(timeIntervalSince1970: 123),
                payload: .init(transactionId: .init(validating: "transaction"), scope: scope,
                    expectedRevision: revision, changes: .init(notes: .set(notes), paymentMethod: .clear)))
        }
        func count(_ table: String) async throws -> Int {
            try await db.get("SELECT count(*) FROM \(table)") { try $0.getInt(index: 0) }
        }
        do {
            let edit = try command()
            await #expect(throws: (any Error).self) { try await store(db).submit(edit) }
            try await seed(db, scope: scope, principal: principal)
            enum Injected: Error { case rollback }
            await #expect(throws: Injected.self) {
                try await store(db, checkpoint: { throw Injected.rollback }).submit(edit)
            }
            #expect(try await count("spike_local_operations") == 0)
            #expect(try await count("ps_crud") == 0)
            await #expect(throws: TransactionDetailsEditPowerSyncStore.Failure.self) {
                try await store(db).submit(command(revision: 6))
            }
            #expect(try await store(db).submit(edit).localState == .queued)
            #expect(try await store(db).submit(edit).localState == .queued)
            #expect(try await count("ps_crud") == 1)
            await #expect(throws: OperationContractFailure.self) {
                try await store(db).submit(command(id: edit.envelope.operationId, notes: "Different"))
            }
            await #expect(throws: TransactionDetailsEditPowerSyncStore.Failure.self) {
                try await store(db).submit(command())
            }
            let unchanged = try await TransactionDetailPowerSyncQuery(database: db, principalId: principal, scope: scope)
                .read(transactionId: edit.envelope.payload.transactionId)
            #expect(unchanged.notes == "Original" && unchanged.detailsRevision == 7)
            try await db.close()
            db = try LedgerPowerSyncDatabaseFactory.open(absolutePath: path, encryptionKey: key)
            let reopened = store(db)
            #expect(try await reopened.pending(scope: scope, transactionId: edit.envelope.payload.transactionId)?.payload == edit.envelope.payload)
            #expect(try await reopened.status(edit.envelope.operationId)?.state.localState == .queued)
            #expect(try await reopened.submit(edit).localState == .queued)
            let queue = try #require(await db.getNextCrudTransaction())
            let entry = try #require(queue.crud.first)
            let bad = Reply(rejected: inventory, wrongDigest: true)
            await #expect(throws: EditTransactionDetailsServerResult.Failure.self) {
                try await TransactionDetailsEditUpload.apply(entry, database: db, accessFence: fence, applier: bad)
            }
            #expect(try await reopened.status(edit.envelope.operationId)?.state.localState == .applying)
            let valid = Reply(rejected: inventory)
            try await TransactionDetailsEditUpload.apply(entry, database: db, accessFence: fence, applier: valid)
            try await TransactionDetailsEditUpload.apply(entry, database: db, accessFence: fence, applier: valid)
            #expect(try await reopened.status(edit.envelope.operationId)?.state.localState == (inventory ? .rejected : .applied))
            try await queue.complete()
            #expect(try await count("ps_crud") == 0)
            #expect(try await reopened.submit(edit).localState == (inventory ? .rejected : .applied))
            #expect(try await reopened.pending(scope: scope, transactionId: edit.envelope.payload.transactionId)?.receipt.localState == (inventory ? .rejected : .applied))
            // A local receipt does not fabricate a synchronized server row.
            #expect(try await TransactionDetailPowerSyncQuery(database: db, principalId: principal, scope: scope)
                .read(transactionId: edit.envelope.payload.transactionId) == unchanged)
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET financial_access='none'", parameters: nil)
            _ = try await db.execute(sql: "UPDATE spike_budget_categories SET kind='fee'", parameters: nil)
            // Current visibility is checked even when replaying an accepted edit.
            await #expect(throws: TransactionDetailsEditPowerSyncStore.Failure.self) { try await reopened.submit(edit) }
            await #expect(throws: TransactionDetailsEditPowerSyncStore.Failure.self) {
                try await reopened.pending(scope: scope, transactionId: edit.envelope.payload.transactionId)
            }
            _ = try await db.execute(sql: "UPDATE spike_budget_categories SET kind='general'", parameters: nil)
            #expect(try await reopened.submit(edit).localState == (inventory ? .rejected : .applied))
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed'", parameters: nil)
            await #expect(throws: (any Error).self) { try await reopened.submit(edit) }
            await #expect(throws: TransactionDetailsEditPowerSyncStore.Failure.self) {
                try await reopened.status(edit.envelope.operationId)
            }
            #expect(try await count("spike_local_operations") == 1)
            fence.markRemoved()
            await #expect(throws: LedgerOfflineClientRuntimeFailure.self) { try await reopened.submit(edit) }
            await reopened.cancelAndDrainWatches()
            try await db.close()
        } catch { try? await db.close(); throw error }
    }

    private struct Reply: EditTransactionDetailsApplying {
        var rejected: Bool
        var wrongDigest = false
        func apply(_ command: EditTransactionDetailsCommand) async throws -> EditTransactionDetailsServerResult {
            let e = command.envelope, request = try EditTransactionDetailsUploadRequest(command)
            let wire: [String: Any] = ["operation_id": e.operationId.rawValue, "account_id": e.accountId.rawValue,
                "actor_principal_id": e.actorPrincipalId.rawValue, "command_type": "edit_transaction_details",
                "contract_version": e.contractVersion.rawValue, "command_fingerprint": wrongDigest ? "wrong" : request.fingerprint,
                "envelope_sha256": request.fingerprint, "subject_id": e.payload.transactionId.rawValue,
                "phase": rejected ? "rejected" : "applied",
                "result_code": rejected ? NSNull() : "transaction_details_updated",
                "error_code": rejected ? "transaction_edit_stale" : NSNull(),
                "client_created_at_ms": 123000, "server_received_at_ms": 125000, "completed_at_ms": 125001]
            return try JSONDecoder().decode(EditTransactionDetailsServerResult.self,
                from: JSONSerialization.data(withJSONObject: wire))
        }
    }

    private func seed(_ db: any PowerSyncDatabaseProtocol, scope: TransactionScope, principal: PrincipalID) async throws {
        func json(_ value: Any) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
        }
        let identity = TransactionReceiptStreamIdentity(scope: scope)
        _ = try await db.syncStream(name: identity.name, params: identity.parameters).subscribe()
        let params = try JSONSerialization.jsonObject(with: JSONEncoder().encode(identity.parameters))
        let schema = try JSONSerialization.jsonObject(with: JSONEncoder().encode(LedgerPowerSyncSchema.schema))
        let facts: [(String,String,[String:Any])] = [
            ("spike_account_memberships","membership",["account_id":scope.accountId.rawValue,
                "principal_id":principal.rawValue,"state":"active","financial_access":"full"]),
            ("spike_budget_categories","category",["account_id":scope.accountId.rawValue,"display_name":"General",
                "kind":"general","lifecycle":"active","is_system":0,"excludes_from_overall_budget":0,
                "presentation_order":0,"revision":1]),
            ("spike_transactions","transaction",["account_id":scope.accountId.rawValue,
                "project_id":scope.projectId?.rawValue as Any? ?? NSNull(),"client_id":scope.clientId?.rawValue as Any? ?? NSNull(),
                "scope_kind":scope.ownerKind == .project ? "project" : "business_inventory",
                "origin":"vendor_payment","type":"purchase","role":"standalone",
                "amount_minor_units":"9007199254740993","currency":"USD","category_id":"category",
                "notes":"Original","payment_method":"Card","details_revision":"7","non_item_receipt_lines":"[]"])
        ]
        let rows = try facts.enumerated().map { index, fact -> [String:Any] in
            ["checksum":0,"op_id":String(index+1),"object_id":fact.1,"object_type":fact.0,"op":"PUT","data":try json(fact.2)]
        }
        let controls: [(String,String?)] = [
            ("start",try json(["parameters":[:],"schema":schema,"include_defaults":false,
                "active_streams":[["name":identity.name,"params":params]],"app_metadata":[:],"checkpoint_mode":"legacy"])),
            ("connection","established"),
            ("line_text",try json(["checkpoint":["last_op_id":"3","buckets":[
                ["bucket":"edit-bucket","priority":3,"checksum":0,"subscriptions":[["sub":0]]]],
                "streams":[["name":identity.name,"is_default":false,"errors":[]]]]])),
            ("line_text",try json(["data":["bucket":"edit-bucket","data":rows,"has_more":false]])),
            ("line_text",try json(["checkpoint_complete":["last_op_id":"3"]])), ("stop",nil)
        ]
        for (operation, parameter) in controls {
            _ = try await db.writeTransaction { tx in
                try tx.getAll(sql:"SELECT powersync_control(?,?) AS result",parameters:[operation,parameter]) {
                    try $0.getString(name:"result")
                }
            }
        }
    }
}
