import Foundation
import LedgerTargetCore
import PowerSync

enum CategoryManagementUpload {
    static func apply(_ entry: CrudEntry, database: any PowerSyncDatabaseProtocol,
                      accessFence: LedgerWorkspaceAccessFence,
                      applier: any CategoryManagementCommandApplying) async throws {
        guard entry.op == .put, entry.table == LedgerPowerSyncTable.categoryCommands,
              let data = entry.opData, let json = data["envelope_json"] ?? nil,
              Set(data.keys) == Set(["account_id", "actor_principal_id", "contract_version", "fingerprint", "envelope_json"]) else {
            throw CategoryManagementFailure.invalidCommand
        }
        let command = try OperationContractCodec.decode(CategoryManagementCommand.self,
            from: Data("{\"envelope\":\(json)}".utf8))
        let envelope = command.envelope
        let fingerprint = try command.fingerprint.sha256
        guard entry.id == envelope.operationId.rawValue,
              data["account_id"] == envelope.accountId.rawValue,
              data["actor_principal_id"] == envelope.actorPrincipalId.rawValue,
              data["contract_version"] == envelope.contractVersion.rawValue,
              data["fingerprint"] == fingerprint,
              json == String(decoding: try OperationContractCodec.encode(envelope), as: UTF8.self),
              AccountBoundOperationIdentity.isValid(envelope.operationId, family: .categoryManagement,
                accountId: envelope.accountId) else { throw CategoryManagementFailure.invalidCommand }
        try await database.writeTransaction { local in
            try requireAccess(accessFence)
            try requireOwner(local, command: command, fingerprint: fingerprint)
            _ = try local.execute(sql: """
                UPDATE spike_local_operations SET local_state = 'applying'
                WHERE id = ? AND local_state = 'queued'
                """, parameters: [entry.id])
        }
        // An interrupted request remains applying and keeps its immutable queue
        // entry. Retrying sends exactly the same operation, never a new ID.
        try requireAccess(accessFence)
        let result = try await applier.apply(command)
        try requireAccess(accessFence)
        try result.validate(for: command)
        try await database.writeTransaction { local in
            try requireAccess(accessFence)
            try requireOwner(local, command: command, fingerprint: fingerprint)
            let prior = try local.get(sql: """
                SELECT local_state, terminal_result_code, terminal_error_code,
                    terminal_server_received_at_ms, terminal_completed_at_ms
                FROM spike_local_operations WHERE id = ?
                """, parameters: [entry.id]) { cursor in
                (try cursor.getString(name: "local_state"),
                 try cursor.getStringOptional(name: "terminal_result_code"),
                 try cursor.getStringOptional(name: "terminal_error_code"),
                 try cursor.getInt64Optional(name: "terminal_server_received_at_ms"),
                 try cursor.getInt64Optional(name: "terminal_completed_at_ms"))
            }
            if prior.0 == "applied" || prior.0 == "rejected" {
                guard prior.0 == result.phase, prior.1 == result.result_code, prior.2 == result.error_code,
                      prior.3 == result.server_received_at_ms, prior.4 == result.completed_at_ms else {
                    throw CategoryManagementFailure.receiptMismatch
                }
                return
            }
            _ = try local.execute(sql: """
                UPDATE spike_local_operations SET local_state = ?, terminal_phase = ?,
                    terminal_result_code = ?, terminal_error_code = ?, terminal_envelope_sha256 = ?,
                    terminal_server_received_at_ms = ?, terminal_completed_at_ms = ?,
                    updated_at_ms = MAX(updated_at_ms, ?),
                    category_projection_json = CASE WHEN ? = 'rejected' THEN '[]' ELSE category_projection_json END
                WHERE id = ? AND local_state IN ('queued', 'applying')
                """, parameters: [result.phase, result.phase, result.result_code, result.error_code,
                    result.envelope_sha256, result.server_received_at_ms, result.completed_at_ms,
                    result.completed_at_ms, result.phase, entry.id])
        }
    }

    private static func requireAccess(_ fence: LedgerWorkspaceAccessFence) throws {
        try Task.checkCancellation()
        guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
    }

    private static func requireOwner(_ local: any Transaction, command: CategoryManagementCommand,
                                     fingerprint: String) throws {
        _ = try CategoryManagementLocalProjection.requireMembership(local,
            account: command.envelope.accountId, principal: command.envelope.actorPrincipalId)
        guard try LocalOperationIdentityGuard.inspect(transaction: local,
            operationId: command.envelope.operationId, expectedFamily: .manageCategories,
            expectedFingerprint: fingerprint) == .matchingOwner else {
            throw CategoryManagementFailure.receiptMismatch
        }
    }
}
