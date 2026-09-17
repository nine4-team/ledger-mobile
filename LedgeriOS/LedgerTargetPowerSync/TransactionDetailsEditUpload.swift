import Foundation
import LedgerTargetCore
import PowerSync

enum TransactionDetailsEditUpload {
    static func apply(_ entry: CrudEntry, database: any PowerSyncDatabaseProtocol,
                      accessFence: LedgerWorkspaceAccessFence, applier: any EditTransactionDetailsApplying) async throws {
        let command = try EditTransactionDetailsUploadRequest.command(from: entry)
        try await apply(.details(command), entry: entry, database: database, accessFence: accessFence) {
            let result = try await applier.apply(command)
            try result.validate(for: command)
            return TerminalReceipt(phase: result.phase, result_code: result.result_code, error_code: result.error_code,
                envelope_sha256: result.envelope_sha256, server_received_at_ms: result.server_received_at_ms,
                completed_at_ms: result.completed_at_ms)
        }
    }

    static func applyReceiptLines(_ entry: CrudEntry, database: any PowerSyncDatabaseProtocol,
        accessFence: LedgerWorkspaceAccessFence, applier: any EditTransactionReceiptLinesApplying) async throws {
        let command = try EditTransactionReceiptLinesUploadRequest.command(from: entry)
        try await apply(.receiptLines(command), entry: entry, database: database, accessFence: accessFence) {
            let result = try await applier.apply(command)
            try result.validate(for: command)
            return TerminalReceipt(phase: result.phase, result_code: result.result_code, error_code: result.error_code,
                envelope_sha256: result.envelope_sha256, server_received_at_ms: result.server_received_at_ms,
                completed_at_ms: result.completed_at_ms)
        }
    }

    private struct TerminalReceipt: Sendable {
        let phase: String
        let result_code, error_code: String?
        let envelope_sha256: String
        let server_received_at_ms, completed_at_ms: Int64
    }

    private static func apply(_ command: TransactionEditWork, entry: CrudEntry,
        database: any PowerSyncDatabaseProtocol, accessFence: LedgerWorkspaceAccessFence,
        send: @Sendable () async throws -> TerminalReceipt) async throws {
        let fingerprint = try command.fingerprint
        try await database.writeTransaction { local in
            try requireOwner(local, command: command, fingerprint: fingerprint, fence: accessFence)
            _ = try local.execute(sql: "UPDATE spike_local_operations SET local_state='applying' WHERE id=? AND local_state='queued'",
                parameters: [entry.id])
        }
        try requireAccess(accessFence)
        let result = try await send()
        try requireAccess(accessFence)
        try await database.writeTransaction { local in
            try requireOwner(local, command: command, fingerprint: fingerprint, fence: accessFence)
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
                    throw EditTransactionDetailsServerResult.Failure.receiptMismatch
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

    private static func requireOwner(_ local: any Transaction, command: TransactionEditWork,
                                     fingerprint: String, fence: LedgerWorkspaceAccessFence) throws {
        try requireAccess(fence)
        guard try ItemDetailsEditPowerSyncStore.hasMembership(local,
            account: command.accountId, principal: command.actorPrincipalId),
              try LocalOperationIdentityGuard.inspect(transaction: local, operationId: command.operationId,
                expectedFamily: command.kind.family, expectedFingerprint: fingerprint) == .matchingOwner else {
            throw LocalOperationIdentityGuardFailure.malformedEvidence
        }
    }
}
