import Foundation
import LedgerTargetCore
import PowerSync

public enum ExpenseCreationOperationIdentity {
    public static func make(accountId: AccountID, uuid: UUID) throws -> OperationID {
        try AccountBoundOperationIdentity.make(family: .expenseCreation, accountId: accountId, uuid: uuid)
    }
}

/// Uses the existing operation ledger and PowerSync upload queue atomically.
/// It does not write downloaded Expense facts or claim media has uploaded.
actor ExpenseCreationPowerSyncStore {
    enum Failure: Error { case scopeMismatch, invalidIdentity, unavailable, invalidClock, duplicateExpense }
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

    /// Accept an edit intent without mutating downloaded authoritative facts.
    /// Collection may have happened while disconnected; the server checks it again.
    func submit(_ command: EditExpenseCommand, expectedRecovery: ExpenseEntryRecovery? = nil) async throws -> OperationReceipt {
        let e = command.envelope, draft = e.payload.entry
        guard e.accountId == accountId, e.actorPrincipalId == principalId else { throw Failure.scopeMismatch }
        guard AccountBoundOperationIdentity.isValid(e.operationId, family: .expenseEdit, accountId: accountId) else {
            throw Failure.invalidIdentity
        }
        let request = try EditExpenseUploadRequest(command)
        let expectedJSON = try expectedRecovery.map { String(decoding: try OperationContractCodec.encode($0), as: UTF8.self) }
        let json = String(decoding: try OperationContractCodec.encode(e), as: UTF8.self)
        let instant = (now().timeIntervalSince1970 * 1000).rounded(.down)
        guard instant.isFinite, instant >= 0, instant < Double(Int64.max) else { throw Failure.invalidClock }
        let account = accountId, principal = principalId, fence = accessFence, checkpoint = afterOperationWrite
        return try await database.writeTransaction { local in
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            _ = try CategoryManagementLocalProjection.requireMembership(local, account: account, principal: principal)
            let financial = try local.getOptional(sql: "SELECT financial_access FROM spike_account_memberships WHERE account_id=? AND principal_id=? AND state='active'",
                parameters: [account.rawValue, principal.rawValue]) { try $0.getString(index: 0) }
            guard financial == "full" else { throw Failure.unavailable }
            let ownership: LocalOperationIdentityDisposition
            do {
                ownership = try LocalOperationIdentityGuard.inspect(transaction: local, operationId: e.operationId,
                    expectedFamily: .editExpense, expectedFingerprint: request.fingerprint)
            } catch LocalOperationIdentityGuardFailure.payloadMismatch {
                throw OperationContractFailure.payloadMismatch(e.operationId)
            }
            if ownership == .matchingOwner {
                return try local.get(sql: "SELECT command_envelope_json,local_state FROM spike_local_operations WHERE id=?",
                    parameters: [e.operationId.rawValue]) {
                        guard try $0.getString(index: 0) == json,
                              let state = LocalOperationState(rawValue: try $0.getString(index: 1)) else {
                            throw LocalOperationIdentityGuardFailure.malformedEvidence
                        }
                        return OperationReceipt(operationId: e.operationId, localState: state)
                    }
            }
            if let expectedRecovery {
                guard expectedRecovery.accountId == account, expectedRecovery.projectId == draft.projectId,
                      expectedRecovery.expenseId == draft.expenseId,
                      expectedRecovery.editContext?.expectedRevision == e.payload.expectedRevision,
                      try AccountBoundOperationIdentity.make(family: .expenseEdit, accountId: account,
                        uuid: expectedRecovery.operationUUID) == e.operationId else { throw ExpenseEntryRecoveryFailure.staleEntry }
                let current = try local.getOptional(sql: "SELECT entry_json FROM spike_expense_entry_recovery WHERE id=? AND account_id=? AND actor_principal_id=?",
                    parameters: [draft.expenseId.rawValue,account.rawValue,principal.rawValue]) { try $0.getString(index: 0) }
                guard current == expectedJSON else { throw ExpenseEntryRecoveryFailure.staleEntry }
            }
            guard let project = try ClientProjectDirectoryPowerSyncQuery.readProject(draft.projectId,
                account: account, principal: principal, in: local), project.lifecycle == .active,
                project.client.lifecycle == .active else { throw Failure.unavailable }
            let editable = try local.get(sql: """
                SELECT count(*) FROM expenses e JOIN spike_budget_categories c ON c.account_id=e.account_id AND c.id=?
                WHERE e.account_id=? AND e.project_id=? AND e.id=? AND e.revision=? AND e.currency=?
                  AND c.kind='general' AND c.lifecycle='active'
                  AND NOT EXISTS(SELECT 1 FROM collected_invoice_lines l WHERE l.account_id=e.account_id
                    AND l.source_kind='expense' AND l.source_id=e.id)
                """, parameters: [draft.categoryId.rawValue, account.rawValue, draft.projectId.rawValue,
                    draft.expenseId.rawValue, String(e.payload.expectedRevision), draft.finalAmount.currency.rawValue]) { try $0.getInt(index: 0) }
            guard editable == 1 else { throw Failure.unavailable }
            let retained = try local.getAll(sql: "SELECT attachment_id FROM expense_receipt_attachments WHERE account_id=? AND expense_id=? ORDER BY position",
                parameters: [account.rawValue, draft.expenseId.rawValue]) { try $0.getString(index: 0) }
            // Additions retain the original ordered references. Removal/reordering
            // remains unavailable until its retention policy is approved.
            guard draft.receiptAttachmentIds.map(\.rawValue).starts(with: retained) else { throw Failure.unavailable }
            let pending = try local.get(sql: """
                SELECT count(*) FROM spike_local_operations WHERE account_id=? AND local_state IN ('queued','applying') AND
                  ((command_type IN ('create_expense','edit_expense') AND subject_id=?)
                   OR (command_type='archive_project' AND subject_id=?) OR (command_type='archive_client' AND subject_id=?))
                """, parameters: [account.rawValue,draft.expenseId.rawValue,project.id.rawValue,project.clientId.rawValue]) { try $0.getInt(index: 0) }
            guard pending == 0 else { throw Failure.unavailable }
            try local.execute(sql: """
                INSERT INTO spike_local_operations(id,account_id,actor_principal_id,contract_version,fingerprint,
                  subject_id,local_state,accepted_at_ms,updated_at_ms,command_type,command_envelope_json)
                VALUES (?,?,?,'expense-edit-v1',?,?,'queued',?,?,'edit_expense',?)
                """, parameters: [e.operationId.rawValue,account.rawValue,principal.rawValue,request.fingerprint,
                    draft.expenseId.rawValue,Int64(instant),Int64(instant),json])
            try checkpoint()
            try local.execute(sql: """
                INSERT INTO spike_expense_commands(id,account_id,actor_principal_id,expense_id,contract_version,fingerprint,envelope_json)
                VALUES (?,?,?,?,'expense-edit-v1',?,?)
                """, parameters: [e.operationId.rawValue,account.rawValue,principal.rawValue,draft.expenseId.rawValue,request.fingerprint,json])
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            return OperationReceipt(operationId: e.operationId, localState: .queued)
        }
    }

    func submit(_ command: CreateExpenseCommand, expectedRecovery: ExpenseEntryRecovery? = nil) async throws -> OperationReceipt {
        guard expectedRecovery?.editContext == nil else { throw ExpenseEntryRecoveryFailure.staleEntry }
        let e = command.envelope, draft = e.payload
        guard e.accountId == accountId, e.actorPrincipalId == principalId else { throw Failure.scopeMismatch }
        guard AccountBoundOperationIdentity.isValid(e.operationId, family: .expenseCreation, accountId: accountId) else {
            throw Failure.invalidIdentity
        }
        let request = try CreateExpenseUploadRequest(command)
        let json = String(decoding: try OperationContractCodec.encode(e), as: UTF8.self)
        let expectedEntryJSON = try expectedRecovery.map { String(decoding: try OperationContractCodec.encode($0), as: UTF8.self) }
        let instant = (now().timeIntervalSince1970 * 1000).rounded(.down)
        guard instant.isFinite, instant >= 0, instant < Double(Int64.max) else { throw Failure.invalidClock }
        let account = accountId, principal = principalId, fence = accessFence, checkpoint = afterOperationWrite
        return try await database.writeTransaction { local in
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            _ = try CategoryManagementLocalProjection.requireMembership(local, account: account, principal: principal)
            let financial = try local.getOptional(sql: "SELECT financial_access FROM spike_account_memberships WHERE account_id=? AND principal_id=? AND state='active'",
                parameters: [account.rawValue, principal.rawValue]) { try $0.getString(index: 0) }
            guard financial == "full" else { throw Failure.unavailable }
            let ownership: LocalOperationIdentityDisposition
            do {
                ownership = try LocalOperationIdentityGuard.inspect(transaction: local, operationId: e.operationId,
                    expectedFamily: .createExpense, expectedFingerprint: request.fingerprint)
            } catch LocalOperationIdentityGuardFailure.payloadMismatch {
                throw OperationContractFailure.payloadMismatch(e.operationId)
            }
            if ownership == .matchingOwner {
                return try local.get(sql: "SELECT command_envelope_json,local_state FROM spike_local_operations WHERE id=?",
                    parameters: [e.operationId.rawValue]) {
                        guard try $0.getString(index: 0) == json,
                              let state = LocalOperationState(rawValue: try $0.getString(index: 1)) else {
                            throw LocalOperationIdentityGuardFailure.malformedEvidence
                        }
                        return OperationReceipt(operationId: e.operationId, localState: state)
                    }
            }
            let savedEntry = try local.getOptional(sql: "SELECT entry_json FROM spike_expense_entry_recovery WHERE id=? AND account_id=? AND actor_principal_id=?",
                parameters: [draft.expenseId.rawValue, account.rawValue, principal.rawValue]) { try $0.getString(index: 0) }
            guard savedEntry == expectedEntryJSON else { throw ExpenseEntryRecoveryFailure.staleEntry }
            guard expectedRecovery == nil || (expectedRecovery?.expenseId == draft.expenseId
                && expectedRecovery?.projectId == draft.projectId && expectedRecovery?.accountId == account) else {
                throw ExpenseEntryRecoveryFailure.staleEntry
            }
            guard let project = try ClientProjectDirectoryPowerSyncQuery.readProject(draft.projectId,
                account: account, principal: principal, in: local), project.lifecycle == .active,
                project.client.lifecycle == .active else { throw Failure.unavailable }
            let category = try local.getOptional(sql: "SELECT kind FROM spike_budget_categories WHERE account_id=? AND id=? AND lifecycle='active'",
                parameters: [account.rawValue, draft.categoryId.rawValue]) { try $0.getString(index: 0) }
            guard category == "general" else { throw Failure.unavailable }
            let unavailable = try local.get(sql: """
                SELECT count(*) FROM spike_local_operations WHERE account_id=? AND
                 ((local_state IN ('queued','applying') AND
                   ((command_type='archive_project' AND subject_id=?) OR (command_type='archive_client' AND subject_id=?)))
                  OR (command_type='create_expense' AND subject_id=?))
                """, parameters: [account.rawValue,project.id.rawValue,project.clientId.rawValue,draft.expenseId.rawValue]) { try $0.getInt(index: 0) }
            guard unavailable == 0 else { throw Failure.duplicateExpense }
            try local.execute(sql: """
                INSERT INTO spike_local_operations(id,account_id,actor_principal_id,contract_version,fingerprint,
                  subject_id,local_state,accepted_at_ms,updated_at_ms,command_type,command_envelope_json)
                VALUES (?,?,?,'expense-create-v1',?,?,'queued',?,?,'create_expense',?)
                """, parameters: [e.operationId.rawValue,account.rawValue,principal.rawValue,request.fingerprint,
                    draft.expenseId.rawValue,Int64(instant),Int64(instant),json])
            try checkpoint()
            try local.execute(sql: """
                INSERT INTO spike_expense_commands(id,account_id,actor_principal_id,expense_id,contract_version,fingerprint,envelope_json)
                VALUES (?,?,?,?,'expense-create-v1',?,?)
                """, parameters: [e.operationId.rawValue,account.rawValue,principal.rawValue,draft.expenseId.rawValue,request.fingerprint,json])
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            return OperationReceipt(operationId: e.operationId, localState: .queued)
        }
    }
}
