import Foundation
import LedgerTargetCore
import PowerSync

enum InvoiceCreationUpload {
    static func apply(_ entry: CrudEntry, database: any PowerSyncDatabaseProtocol,
                      accessFence: LedgerWorkspaceAccessFence, applier: (any CreateInvoiceCommandApplying)? = nil,
                      revisionApplier: (any ReviseCreatedInvoiceCommandApplying)? = nil) async throws {
        guard entry.op == .put, entry.table == LedgerPowerSyncTable.invoiceCommands,
              let data = entry.opData, let json = data["envelope_json"] ?? nil,
              Set(data.keys) == Set(["account_id", "actor_principal_id", "invoice_id", "contract_version", "fingerprint", "envelope_json"]) else {
            throw LocalOperationIdentityGuardFailure.malformedEvidence
        }
        let command: CreateInvoiceCommand
        let request: CreateInvoiceUploadRequest
        let contract: String, encodedEnvelope: String
        let family: LocalOperationCommandFamily
        let identityFamily: AccountBoundOperationFamily
        let send: @Sendable () async throws -> CreateInvoiceServerResult
        let bytes = Data("{\"envelope\":\(json)}".utf8)
        if data["contract_version"] == "invoice-revise-created-v1" {
            guard let revisionApplier else { throw LedgerPowerSyncUploadFailure.unsupportedCommandTable(entry.table) }
            let revision = try OperationContractCodec.decode(ReviseCreatedInvoiceCommand.self, from: bytes)
            let e = revision.envelope
            command = try CreateInvoiceCommand(operationId: e.operationId, actorPrincipalId: e.actorPrincipalId,
                capturedAt: e.clientCreatedAt, payload: e.payload.invoice)
            request = try CreateInvoiceUploadRequest(revision)
            contract = e.contractVersion.rawValue
            encodedEnvelope = String(decoding: try OperationContractCodec.encode(e), as: UTF8.self)
            family = .reviseCreatedInvoice; identityFamily = .invoiceRevision
            send = {
                let result = try await revisionApplier.apply(revision)
                try result.validate(for: revision)
                return result
            }
        } else {
            guard let applier else { throw LedgerPowerSyncUploadFailure.unsupportedCommandTable(entry.table) }
            command = try OperationContractCodec.decode(CreateInvoiceCommand.self, from: bytes)
            request = try CreateInvoiceUploadRequest(command)
            contract = command.envelope.contractVersion.rawValue
            encodedEnvelope = String(decoding: try OperationContractCodec.encode(command.envelope), as: UTF8.self)
            family = .createInvoice; identityFamily = .invoiceCreation
            send = {
                let result = try await applier.apply(command)
                try result.validate(for: command)
                return result
            }
        }
        let e = command.envelope
        guard entry.id == e.operationId.rawValue, data["account_id"] == e.accountId.rawValue,
              data["actor_principal_id"] == e.actorPrincipalId.rawValue, data["invoice_id"] == e.payload.invoiceId.rawValue,
              data["contract_version"] == contract, data["fingerprint"] == request.fingerprint,
              json == encodedEnvelope,
              AccountBoundOperationIdentity.isValid(e.operationId, family: identityFamily, accountId: e.accountId),
              let project = e.payload.selection.scope.projectId else { throw LocalOperationIdentityGuardFailure.malformedEvidence }
        let owner: @Sendable (any Transaction) throws -> Void = { local in
            try requireAccess(accessFence)
            try ProjectInvoicingItemLocalReader.requireAccess(transaction: local,
                accountId: e.accountId, principalId: e.actorPrincipalId, projectId: project)
            guard try LocalOperationIdentityGuard.inspect(transaction: local, operationId: e.operationId,
                expectedFamily: family, expectedFingerprint: request.fingerprint) == .matchingOwner else {
                throw LocalOperationIdentityGuardFailure.malformedEvidence
            }
        }
        try await database.writeTransaction { local in
            try owner(local)
            _ = try local.execute(sql: "UPDATE spike_local_operations SET local_state='applying' WHERE id=? AND local_state='queued'", parameters: [entry.id])
        }
        try requireAccess(accessFence)
        let result = try await send()
        try requireAccess(accessFence)
        try await database.writeTransaction { local in
            try owner(local)
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
                    throw CreateInvoiceServerResult.Failure.receiptMismatch
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
}
