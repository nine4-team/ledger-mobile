import Foundation
import LedgerTargetCore
import PowerSync

enum ExpenseCreationUpload {
    enum Failure: Error { case receiptNotReady, unavailable }

    static func apply(_ entry: CrudEntry, database: any PowerSyncDatabaseProtocol,
                      accessFence: LedgerWorkspaceAccessFence,
                      applier: any CreateExpenseCommandApplying,
                      verifiedReceipts: @Sendable (CreateExpenseCommand) async throws -> Set<AttachmentID> = { _ in [] }) async throws {
        guard entry.op == .put, entry.table == LedgerPowerSyncTable.expenseCommands,
              let data = entry.opData, let json = data["envelope_json"] ?? nil,
              Set(data.keys) == Set(["account_id", "actor_principal_id", "expense_id", "contract_version", "fingerprint", "envelope_json"]) else {
            throw LocalOperationIdentityGuardFailure.malformedEvidence
        }
        let command = try OperationContractCodec.decode(CreateExpenseCommand.self, from: Data("{\"envelope\":\(json)}".utf8))
        let e = command.envelope, request = try CreateExpenseUploadRequest(command)
        guard entry.id == e.operationId.rawValue, data["account_id"] == e.accountId.rawValue,
              data["actor_principal_id"] == e.actorPrincipalId.rawValue, data["expense_id"] == e.payload.expenseId.rawValue,
              data["contract_version"] == e.contractVersion.rawValue, data["fingerprint"] == request.fingerprint,
              json == String(decoding: try OperationContractCodec.encode(e), as: UTF8.self),
              AccountBoundOperationIdentity.isValid(e.operationId, family: .expenseCreation, accountId: e.accountId) else {
            throw LocalOperationIdentityGuardFailure.malformedEvidence
        }
        try requireAccess(accessFence)
        let published = try await verifiedReceipts(command)
        try await database.writeTransaction { local in
            try requireOwner(local, command: command, fingerprint: request.fingerprint, fence: accessFence)
            // Missing publication evidence is retryable, not a permanent server
            // rejection of a locally accepted Expense. Media delivery owns upload.
            for attachment in e.payload.receiptAttachmentIds {
                // A receipt verified before Expense creation has no synced parent
                // reference yet. Durable verifier evidence breaks that dependency;
                // the server still validates the canonical object FK atomically.
                if published.contains(attachment) { continue }
                let found = try local.get(sql: "SELECT count(*) FROM item_image_objects WHERE account_id=? AND id=?",
                    parameters: [e.accountId.rawValue, attachment.rawValue]) { try $0.getInt(index: 0) }
                guard found == 1 else { throw Failure.receiptNotReady }
            }
            _ = try local.execute(sql: "UPDATE spike_local_operations SET local_state='applying' WHERE id=? AND local_state='queued'", parameters: [entry.id])
        }
        try requireAccess(accessFence)
        let result = try await applier.apply(command)
        try requireAccess(accessFence)
        try result.validate(for: command)
        try await database.writeTransaction { local in
            try requireOwner(local, command: command, fingerprint: request.fingerprint, fence: accessFence)
            let prior = try local.get(sql: """
                SELECT local_state,terminal_result_code,terminal_error_code,
                  terminal_server_received_at_ms,terminal_completed_at_ms FROM spike_local_operations WHERE id=?
                """, parameters: [entry.id]) {
                    (try $0.getString(index: 0), try $0.getStringOptional(index: 1), try $0.getStringOptional(index: 2),
                     try $0.getInt64Optional(index: 3), try $0.getInt64Optional(index: 4))
                }
            if prior.0 == "applied" || prior.0 == "rejected" {
                guard prior.0 == result.phase, prior.1 == result.result_code, prior.2 == result.error_code,
                      prior.3 == result.server_received_at_ms, prior.4 == result.completed_at_ms else {
                    throw CreateExpenseServerResult.Failure.receiptMismatch
                }
                return
            }
            _ = try local.execute(sql: """
                UPDATE spike_local_operations SET local_state=?,terminal_phase=?,terminal_result_code=?,terminal_error_code=?,
                  terminal_envelope_sha256=?,terminal_server_received_at_ms=?,terminal_completed_at_ms=?,
                  updated_at_ms=MAX(updated_at_ms,?) WHERE id=? AND local_state IN ('queued','applying')
                """, parameters: [result.phase,result.phase,result.result_code,result.error_code,result.envelope_sha256,
                    result.server_received_at_ms,result.completed_at_ms,result.completed_at_ms,entry.id])
        }
    }

    private static func requireAccess(_ fence: LedgerWorkspaceAccessFence) throws {
        try Task.checkCancellation()
        guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
    }
    private static func requireOwner(_ local: any Transaction, command: CreateExpenseCommand, fingerprint: String,
                                     fence: LedgerWorkspaceAccessFence) throws {
        try requireAccess(fence)
        let e = command.envelope
        _ = try CategoryManagementLocalProjection.requireMembership(local, account: e.accountId, principal: e.actorPrincipalId)
        let financial = try local.getOptional(sql: "SELECT financial_access FROM spike_account_memberships WHERE account_id=? AND principal_id=? AND state='active'",
            parameters: [e.accountId.rawValue, e.actorPrincipalId.rawValue]) { try $0.getString(index: 0) }
        guard financial == "full" else { throw Failure.unavailable }
        guard try LocalOperationIdentityGuard.inspect(transaction: local, operationId: e.operationId,
            expectedFamily: .createExpense, expectedFingerprint: fingerprint) == .matchingOwner else {
            throw LocalOperationIdentityGuardFailure.malformedEvidence
        }
    }
}
