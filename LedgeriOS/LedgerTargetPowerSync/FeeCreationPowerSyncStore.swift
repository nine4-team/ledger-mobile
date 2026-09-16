import Foundation
import LedgerTargetCore
import PowerSync

public enum FeeCreationOperationIdentity {
    public static func make(accountId: AccountID, uuid: UUID) throws -> OperationID {
        try AccountBoundOperationIdentity.make(family: .feeCreation, accountId: accountId, uuid: uuid)
    }
}

/// Durable intent, never a fabricated downloaded Fee or payment.
actor FeeCreationPowerSyncStore {
    enum Failure: Error { case unavailable, invalidIdentity, invalidClock }
    private struct ProjectConfigurationStream: SyncStreamDescription {
        let name = "spike_projects"
        let parameters: JsonParam? = nil
    }
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

    func submit(_ command: CreateFeeInstallmentCommand) async throws -> OperationReceipt {
        let e = command.envelope, p = e.payload
        guard e.accountId == accountId, e.actorPrincipalId == principalId else { throw Failure.unavailable }
        guard AccountBoundOperationIdentity.isValid(e.operationId, family: .feeCreation, accountId: accountId) else {
            throw Failure.invalidIdentity
        }
        let request = try CreateFeeInstallmentUploadRequest(command)
        let json = String(decoding: try OperationContractCodec.encode(e), as: UTF8.self)
        let instant = (now().timeIntervalSince1970 * 1000).rounded(.down)
        guard instant.isFinite, instant >= 0, instant < Double(Int64.max) else { throw Failure.invalidClock }
        let account = accountId, principal = principalId, fence = accessFence, checkpoint = afterOperationWrite
        return try await database.writeTransaction { local in
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            try ProjectInvoicingItemLocalReader.requireAccess(transaction: local,
                accountId: account, principalId: principal, projectId: p.projectId)
            let ownership: LocalOperationIdentityDisposition
            do {
                ownership = try LocalOperationIdentityGuard.inspect(transaction: local, operationId: e.operationId,
                    expectedFamily: .createFeeInstallment, expectedFingerprint: request.fingerprint)
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
            _ = try PropertyManagementReportPowerSyncQuery.completedStreamCheckpoint(transaction: local,
                identity: ProjectConfigurationStream())
            _ = try PropertyManagementReportPowerSyncQuery.completedStreamCheckpoint(transaction: local,
                identity: LiveInvoiceStreamIdentity(accountId: account, projectId: p.projectId))
            guard let project = try ClientProjectDirectoryPowerSyncQuery.readProject(p.projectId,
                account: account, principal: principal, in: local), project.lifecycle == .active,
                project.client.lifecycle == .active else { throw Failure.unavailable }
            let categoryAvailable = try local.get(sql: """
                SELECT count(*) FROM spike_budget_categories WHERE account_id=? AND id=? AND kind='fee' AND lifecycle='active'
                """, parameters: [account.rawValue, p.categoryId.rawValue]) { try $0.getInt(index: 0) == 1 }
            guard categoryAvailable else { throw Failure.unavailable }
            let existing = try local.get(sql: """
                SELECT (SELECT count(*) FROM fee_installments WHERE account_id=? AND id=?) +
                  (SELECT count(*) FROM spike_local_operations WHERE account_id=? AND command_type='create_fee_installment' AND subject_id=?)
                """, parameters: [account.rawValue,p.installmentId.rawValue,account.rawValue,p.installmentId.rawValue]) { try $0.getInt(index: 0) }
            guard existing == 0 else { throw Failure.unavailable }
            // Exact Swift money arithmetic avoids SQLite SUM converting/overflowing.
            let amounts = try local.getAll(sql: """
                SELECT amount_minor_units,currency FROM fee_installments WHERE account_id=? AND project_id=? AND category_id=?
                """, parameters: [account.rawValue,p.projectId.rawValue,p.categoryId.rawValue]) { row in
                    guard let amount = Int64(try row.getString(index: 0)) else { throw Failure.unavailable }
                    return try Money(minorUnits: amount, currency: .init(validating: row.getString(index: 1)))
                }
            var allocated = try Money(minorUnits: 0, currency: p.amount.currency)
            for amount in amounts { allocated = try allocated.adding(amount) }
            let pending = try local.getAll(sql: """
                SELECT command_envelope_json FROM spike_local_operations o
                WHERE account_id=? AND command_type='create_fee_installment' AND local_state IN ('queued','applying','applied')
                  AND NOT EXISTS(SELECT 1 FROM fee_installments f WHERE f.account_id=o.account_id AND f.id=o.subject_id)
                """, parameters: [account.rawValue]) { try $0.getString(index: 0) }
            for encoded in pending {
                let intent = try OperationContractCodec.decode(OperationEnvelope<FeeInstallmentDraft>.self, from: Data(encoded.utf8)).payload
                if intent.projectId == p.projectId && intent.categoryId == p.categoryId {
                    allocated = try allocated.adding(intent.amount)
                }
            }
            let caps = try local.getAll(sql: """
                SELECT allocation_minor_units,allocation_currency FROM spike_project_category_allocations
                WHERE account_id=? AND project_id=? AND category_id=?
                """, parameters: [account.rawValue,p.projectId.rawValue,p.categoryId.rawValue]) { row -> Money? in
                    guard let raw = try row.getStringOptional(index: 0) else {
                        guard try row.getStringOptional(index: 1) == nil else { throw Failure.unavailable }
                        return nil
                    }
                    guard let amount = Int64(raw) else { throw Failure.unavailable }
                    return try Money(minorUnits: amount, currency: .init(validating: row.getString(index: 1)))
                }
            guard caps.count <= 1 else { throw Failure.unavailable }
            try p.validateBudget(configuredTotal: caps.first ?? nil, alreadyAllocated: allocated)
            try local.execute(sql: """
                INSERT INTO spike_local_operations(id,account_id,actor_principal_id,contract_version,fingerprint,
                  subject_id,local_state,accepted_at_ms,updated_at_ms,command_type,command_envelope_json)
                VALUES (?,?,?,'fee-installment-create-v1',?,?,'queued',?,?,'create_fee_installment',?)
                """, parameters: [e.operationId.rawValue,account.rawValue,principal.rawValue,request.fingerprint,
                    p.installmentId.rawValue,Int64(instant),Int64(instant),json])
            try checkpoint()
            try local.execute(sql: """
                INSERT INTO spike_fee_commands(id,account_id,actor_principal_id,installment_id,contract_version,fingerprint,envelope_json)
                VALUES (?,?,?,?,'fee-installment-create-v1',?,?)
                """, parameters: [e.operationId.rawValue,account.rawValue,principal.rawValue,p.installmentId.rawValue,request.fingerprint,json])
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            return OperationReceipt(operationId: e.operationId, localState: .queued)
        }
    }
}
