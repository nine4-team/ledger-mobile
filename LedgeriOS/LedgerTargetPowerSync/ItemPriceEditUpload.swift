import Foundation
import LedgerTargetCore
import PowerSync

enum ItemPriceEditUpload {
    static func apply(_ entry: CrudEntry, database: any PowerSyncDatabaseProtocol,
                      accessFence: LedgerWorkspaceAccessFence,
                      applier: any EditUncollectedItemPriceApplying) async throws {
        let command = try EditUncollectedItemPriceUploadRequest.command(from: entry)
        let request = try EditUncollectedItemPriceUploadRequest(command)
        try await database.writeTransaction { local in
            try requireOwner(local, command: command, fingerprint: request.fingerprint, fence: accessFence)
            _ = try local.execute(sql: "UPDATE spike_local_operations SET local_state='applying' WHERE id=? AND local_state='queued'",
                parameters: [entry.id])
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
                    (try $0.getString(index: 0),try $0.getStringOptional(index: 1),try $0.getStringOptional(index: 2),
                     try $0.getInt64Optional(index: 3),try $0.getInt64Optional(index: 4))
                }
            if prior.0 == "applied" || prior.0 == "rejected" {
                guard prior.0 == result.phase, prior.1 == result.result_code, prior.2 == result.error_code,
                      prior.3 == result.server_received_at_ms, prior.4 == result.completed_at_ms else {
                    throw EditUncollectedItemPriceServerResult.Failure.receiptMismatch
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

    private static func requireOwner(_ local: any Transaction, command: EditUncollectedItemPriceCommand,
                                     fingerprint: String, fence: LedgerWorkspaceAccessFence) throws {
        try requireAccess(fence)
        guard try CategoryManagementLocalProjection.requireMembership(local,
            account: command.envelope.accountId, principal: command.envelope.actorPrincipalId),
              try LocalOperationIdentityGuard.inspect(transaction: local, operationId: command.envelope.operationId,
                expectedFamily: .editUncollectedItemPrice, expectedFingerprint: fingerprint) == .matchingOwner else {
            throw LocalOperationIdentityGuardFailure.malformedEvidence
        }
    }
}
