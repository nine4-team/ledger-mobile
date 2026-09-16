import Foundation
import LedgerTargetCore
import PowerSync

public enum InvoiceCreationOperationIdentity {
    public static func make(accountId: AccountID, uuid: UUID) throws -> OperationID {
        try AccountBoundOperationIdentity.make(family: .invoiceCreation, accountId: accountId, uuid: uuid)
    }
}

/// Atomic local acceptance into the existing ledger/CRUD queue, not authoritative membership.
actor InvoiceCreationPowerSyncStore {
    enum Failure: Error { case unavailable, invalidIdentity, invalidClock }
    let database: any PowerSyncDatabaseProtocol
    let accountId: AccountID
    let principalId: PrincipalID
    let accessFence: LedgerWorkspaceAccessFence
    let now: @Sendable () -> Date
    let afterOperationWrite: @Sendable () throws -> Void

    init(database: any PowerSyncDatabaseProtocol, accountId: AccountID, principalId: PrincipalID,
         accessFence: LedgerWorkspaceAccessFence, now: @escaping @Sendable () -> Date = Date.init,
         afterOperationWrite: @escaping @Sendable () throws -> Void = {}) {
        self.database = database; self.accountId = accountId; self.principalId = principalId
        self.accessFence = accessFence; self.now = now; self.afterOperationWrite = afterOperationWrite
    }

    func submit(_ command: CreateInvoiceCommand) async throws -> OperationReceipt {
        let e = command.envelope, p = e.payload
        guard e.accountId == accountId, e.actorPrincipalId == principalId,
              let projectId = p.selection.scope.projectId, let clientId = p.selection.scope.clientId else { throw Failure.unavailable }
        guard AccountBoundOperationIdentity.isValid(e.operationId, family: .invoiceCreation, accountId: accountId) else {
            throw Failure.invalidIdentity
        }
        let request = try CreateInvoiceUploadRequest(command)
        let json = String(decoding: try OperationContractCodec.encode(e), as: UTF8.self)
        let instant = (now().timeIntervalSince1970 * 1000).rounded(.down)
        guard instant.isFinite, instant >= 0, instant < Double(Int64.max) else { throw Failure.invalidClock }
        let account = accountId, principal = principalId, fence = accessFence, checkpoint = afterOperationWrite
        return try await database.writeTransaction { local in
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            try ProjectInvoicingItemLocalReader.requireAccess(transaction: local,
                accountId: account, principalId: principal, projectId: projectId)
            let ownership: LocalOperationIdentityDisposition
            do {
                ownership = try LocalOperationIdentityGuard.inspect(transaction: local, operationId: e.operationId,
                    expectedFamily: .createInvoice, expectedFingerprint: request.fingerprint)
            } catch LocalOperationIdentityGuardFailure.payloadMismatch {
                throw OperationContractFailure.payloadMismatch(e.operationId)
            }
            if ownership == .matchingOwner {
                return try local.get(sql: "SELECT command_envelope_json,local_state FROM spike_local_operations WHERE id=?",
                    parameters: [e.operationId.rawValue]) { row in
                        guard try row.getString(index: 0) == json,
                              let state = LocalOperationState(rawValue: try row.getString(index: 1)) else {
                            throw LocalOperationIdentityGuardFailure.malformedEvidence
                        }
                        return OperationReceipt(operationId: e.operationId, localState: state)
                    }
            }
            guard let project = try ClientProjectDirectoryPowerSyncQuery.readProject(projectId,
                account: account, principal: principal, in: local), project.lifecycle == .active,
                project.clientId == clientId, project.client.lifecycle == .active else { throw Failure.unavailable }
            let existing = try local.get(sql: """
                SELECT (SELECT count(*) FROM live_invoices WHERE account_id=? AND id=?) +
                  (SELECT count(*) FROM spike_local_operations WHERE account_id=? AND command_type='create_invoice' AND subject_id=?)
                """, parameters: [account.rawValue,p.invoiceId.rawValue,account.rawValue,p.invoiceId.rawValue]) { try $0.getInt(index: 0) }
            guard existing == 0 else { throw Failure.unavailable }
            for line in p.selection.lines {
                let table: String, kind: String, id: String, amount: String, condition: String
                switch line.source {
                case .itemOccurrence(let value):
                    table = "item_charge_occurrences"; kind = "item"; id = value.rawValue
                    amount = "amount_minor_units"; condition = "AND withdrawn_at IS NULL"
                case .expense(let value):
                    table = "expenses"; kind = "expense"; id = value.rawValue
                    amount = "final_amount_minor_units"; condition = ""
                case .feeInstallment(let value):
                    table = "fee_installments"; kind = "fee_installment"; id = value.rawValue
                    amount = "amount_minor_units"; condition = ""
                }
                let matches = try local.get(sql: """
                    SELECT count(*) FROM \(table) WHERE account_id=? AND project_id=? AND id=?
                      AND CAST(revision AS TEXT)=? AND \(amount)=? AND currency=? \(condition)
                      AND NOT EXISTS(SELECT 1 FROM live_invoice_memberships WHERE account_id=? AND source_kind=? AND source_id=?)
                      AND NOT EXISTS(SELECT 1 FROM collected_invoice_lines WHERE account_id=? AND source_kind=? AND source_id=?)
                    """, parameters: [account.rawValue,projectId.rawValue,id,String(line.expectedRevision),
                        String(line.reviewedAmount.minorUnits),line.reviewedAmount.currency.rawValue,
                        account.rawValue,kind,id,account.rawValue,kind,id]) { try $0.getInt(index: 0) }
                guard matches == 1 else { throw Failure.unavailable }
            }
            try local.execute(sql: """
                INSERT INTO spike_local_operations(id,account_id,actor_principal_id,contract_version,fingerprint,
                  subject_id,local_state,accepted_at_ms,updated_at_ms,command_type,command_envelope_json)
                VALUES (?,?,?,'invoice-create-v1',?,?,'queued',?,?,'create_invoice',?)
                """, parameters: [e.operationId.rawValue,account.rawValue,principal.rawValue,request.fingerprint,
                    p.invoiceId.rawValue,Int64(instant),Int64(instant),json])
            try checkpoint()
            try local.execute(sql: """
                INSERT INTO spike_invoice_commands(id,account_id,actor_principal_id,invoice_id,contract_version,fingerprint,envelope_json)
                VALUES (?,?,?,?,'invoice-create-v1',?,?)
                """, parameters: [e.operationId.rawValue,account.rawValue,principal.rawValue,p.invoiceId.rawValue,request.fingerprint,json])
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            return OperationReceipt(operationId: e.operationId, localState: .queued)
        }
    }
}
