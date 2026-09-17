import Foundation
import LedgerTargetCore
import PowerSync

actor ItemDetailsEditPowerSyncStore {
    enum Failure: Error { case unavailable, invalidIdentity, invalidClock, staleReview, alreadyAccepted }
    let database: any PowerSyncDatabaseProtocol
    let accountId: AccountID
    let principalId: PrincipalID
    let accessFence: LedgerWorkspaceAccessFence
    let now: @Sendable () -> Date
    let afterOperationWrite: @Sendable () throws -> Void
    private let watchRegistry = BudgetCategoryReferenceWatchRegistry()

    init(database: any PowerSyncDatabaseProtocol, accountId: AccountID, principalId: PrincipalID,
         accessFence: LedgerWorkspaceAccessFence, now: @escaping @Sendable () -> Date = Date.init,
         afterOperationWrite: @escaping @Sendable () throws -> Void = {}) {
        self.database = database; self.accountId = accountId; self.principalId = principalId
        self.accessFence = accessFence; self.now = now; self.afterOperationWrite = afterOperationWrite
    }

    func submit(_ command: EditItemDetailsCommand) async throws -> OperationReceipt {
        let e = command.envelope
        guard e.accountId == accountId, e.actorPrincipalId == principalId else { throw Failure.unavailable }
        guard AccountBoundOperationIdentity.isValid(e.operationId, family: .itemDetailsEdit, accountId: accountId) else {
            throw Failure.invalidIdentity
        }
        let request = try EditItemDetailsUploadRequest(command)
        let json = String(decoding: try OperationContractCodec.encode(e), as: UTF8.self)
        let instant = (now().timeIntervalSince1970 * 1000).rounded(.down)
        guard instant.isFinite, instant >= 0, instant < Double(Int64.max) else { throw Failure.invalidClock }
        let account = accountId, principal = principalId, fence = accessFence, checkpoint = afterOperationWrite
        return try await database.writeTransaction { local in
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            guard try Self.hasMembership(local, account: account, principal: principal) else {
                throw Failure.unavailable
            }
            let ownership: LocalOperationIdentityDisposition
            do {
                ownership = try LocalOperationIdentityGuard.inspect(transaction: local, operationId: e.operationId,
                    expectedFamily: .editItemDetails, expectedFingerprint: request.fingerprint)
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
            for item in e.payload.items {
                let revision = try local.getOptional(sql: "SELECT revision FROM spike_items WHERE account_id=? AND id=?",
                    parameters: [account.rawValue,item.itemId.rawValue]) { try $0.getInt64(index: 0) }
                guard revision == item.expectedRevision else { throw Failure.staleReview }
                // Bulk commands own every selected Item, not just their first subject.
                let pending = try local.get(sql: """
                    SELECT count(*) FROM spike_local_operations o,
                      json_each(o.command_envelope_json,'$.payload.items') selected
                    WHERE o.account_id=? AND o.command_type='edit_item_details'
                      AND o.local_state IN ('queued','applying') AND json_extract(selected.value,'$.itemId')=?
                    """, parameters: [account.rawValue,item.itemId.rawValue]) { try $0.getInt(index: 0) }
                guard pending == 0 else { throw Failure.alreadyAccepted }
            }
            let subject = e.payload.items[0].itemId.rawValue
            _ = try local.execute(sql: """
                INSERT INTO spike_local_operations(id,account_id,actor_principal_id,contract_version,fingerprint,
                  subject_id,local_state,accepted_at_ms,updated_at_ms,command_type,command_envelope_json)
                VALUES (?,?,?,'item-details-edit-v1',?,?,'queued',?,?,'edit_item_details',?)
                """, parameters: [e.operationId.rawValue,account.rawValue,principal.rawValue,request.fingerprint,
                    subject,Int64(instant),Int64(instant),json])
            try checkpoint()
            _ = try local.execute(sql: """
                INSERT INTO spike_item_details_edit_commands(id,account_id,actor_principal_id,item_id,
                  contract_version,fingerprint,envelope_json) VALUES (?,?,?,?,'item-details-edit-v1',?,?)
                """, parameters: [e.operationId.rawValue,account.rawValue,principal.rawValue,subject,request.fingerprint,json])
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            return OperationReceipt(operationId: e.operationId, localState: .queued)
        }
    }

    func status(_ operationId: OperationID) async throws -> OperationSnapshot? {
        let account = accountId, principal = principalId, fence = accessFence
        return try await database.readTransaction { local in
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            guard try Self.hasMembership(local, account: account, principal: principal) else { throw Failure.unavailable }
            guard AccountBoundOperationIdentity.isValid(operationId, family: .itemDetailsEdit, accountId: account) else {
                throw Failure.invalidIdentity
            }
            let row = try local.getOptional(sql: """
                SELECT command_envelope_json,local_state,accepted_at_ms,updated_at_ms,
                  terminal_error_code,terminal_server_received_at_ms,terminal_completed_at_ms
                FROM spike_local_operations WHERE id=? AND account_id=? AND actor_principal_id=?
                  AND command_type='edit_item_details'
                """, parameters: [operationId.rawValue,account.rawValue,principal.rawValue]) {
                    (try $0.getString(index: 0),try $0.getString(index: 1),try $0.getInt64(index: 2),
                     try $0.getInt64(index: 3),try $0.getStringOptional(index: 4),
                     try $0.getInt64Optional(index: 5),try $0.getInt64Optional(index: 6))
                }
            guard let row else { return nil }
            let command = try OperationContractCodec.decode(EditItemDetailsCommand.self,
                from: Data("{\"envelope\":\(row.0)}".utf8))
            let fingerprint = try EditItemDetailsUploadRequest(command).fingerprint
            guard command.envelope.operationId == operationId, command.envelope.accountId == account,
                  command.envelope.actorPrincipalId == principal, row.2 >= 0, row.3 >= row.2,
                  try LocalOperationIdentityGuard.inspect(transaction: local, operationId: operationId,
                    expectedFamily: .editItemDetails, expectedFingerprint: fingerprint) == .matchingOwner else {
                throw LocalOperationIdentityGuardFailure.malformedEvidence
            }
            func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }
            let state: OperationState
            switch row.1 {
            case "queued": state = .queued(attemptCount: 0, lastTransientError: nil)
            case "applying": state = .applying(attempt: 1, startedAt: date(row.3))
            case "applied":
                guard let received = row.5, let completed = row.6 else { throw EditItemDetailsServerResult.Failure.receiptMismatch }
                state = .applied(.init(resultCode: try .init(validating: "item_details_updated"),
                    serverReceivedAt: date(received), completedAt: date(completed)))
            case "rejected":
                guard let error = row.4, EditItemDetailsServerResult.rejections.contains(error), let completed = row.6 else {
                    throw EditItemDetailsServerResult.Failure.receiptMismatch
                }
                state = .rejected(.init(error: .init(code: try .init(validating: error), category: .conflict,
                    retryDisposition: .afterUserCorrection), rejectedAt: date(completed)))
            default: throw LocalOperationIdentityGuardFailure.malformedEvidence
            }
            return OperationSnapshot(operationId: operationId, accountId: account,
                contractVersion: command.envelope.contractVersion, fingerprint: try .init(validating: fingerprint),
                acceptedAt: date(row.2), updatedAt: date(row.3), state: state)
        }
    }

    nonisolated func watch(_ operationId: OperationID) -> AsyncThrowingStream<OperationSnapshot?, Error> {
        AsyncThrowingStream { continuation in
            let id = UUID(), handle = BudgetCategoryReferenceWatchTaskHandle()
            let registration = Task { await watchRegistry.register(id: id, handle: handle) }
            let task = Task {
                guard await registration.value else { continuation.finish(); return }
                do {
                    let changes = try database.watch(sql: """
                        SELECT (SELECT count(*) FROM spike_account_memberships WHERE account_id=? AND principal_id=?),
                          (SELECT count(*) FROM spike_local_operations WHERE id=?),
                          (SELECT count(*) FROM spike_operation_results WHERE id=?)
                        """, parameters: [accountId.rawValue,principalId.rawValue,operationId.rawValue,operationId.rawValue]) { _ in true }
                    for try await _ in changes {
                        try Task.checkCancellation()
                        let snapshot = try await status(operationId)
                        try Task.checkCancellation()
                        guard !accessFence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
                        if case .terminated = continuation.yield(snapshot) { break }
                    }
                    continuation.finish()
                } catch is CancellationError { continuation.finish() }
                catch { continuation.finish(throwing: error) }
                await watchRegistry.finished(id: id)
            }
            handle.install(task)
            continuation.onTermination = { _ in handle.cancel() }
        }
    }

    func cancelAndDrainWatches() async { await watchRegistry.cancelAndDrain() }

    /// Descriptive edits require membership, not permission to see financial data.
    static func hasMembership(_ local: any Transaction, account: AccountID, principal: PrincipalID) throws -> Bool {
        try local.get(sql: """
            SELECT count(*) FROM spike_account_memberships
            WHERE account_id=? AND principal_id=? AND state='active'
            """, parameters: [account.rawValue,principal.rawValue]) { try $0.getInt(index: 0) == 1 }
    }
}
