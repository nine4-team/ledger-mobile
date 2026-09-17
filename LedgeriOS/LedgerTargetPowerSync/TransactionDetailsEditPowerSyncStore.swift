import Foundation
import LedgerTargetCore
import PowerSync

actor TransactionDetailsEditPowerSyncStore {
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

    func submit(_ command: EditTransactionDetailsCommand) async throws -> OperationReceipt {
        try await submit(.details(command))
    }

    func submit(_ command: EditTransactionReceiptLinesCommand) async throws -> OperationReceipt {
        try await submit(.receiptLines(command))
    }

    private func submit(_ e: TransactionEditWork) async throws -> OperationReceipt {
        guard e.accountId == accountId, e.actorPrincipalId == principalId else { throw Failure.unavailable }
        guard AccountBoundOperationIdentity.isValid(e.operationId, family: e.kind.namespace, accountId: accountId) else {
            throw Failure.invalidIdentity
        }
        let fingerprint = try e.fingerprint, json = try e.json
        let instant = (now().timeIntervalSince1970 * 1000).rounded(.down)
        guard instant.isFinite, instant >= 0, instant < Double(Int64.max) else { throw Failure.invalidClock }
        let fence = accessFence, checkpoint = afterOperationWrite
        let query = TransactionDetailPowerSyncQuery(database: database, principalId: principalId, scope: e.scope)
        return try await database.writeTransaction { local in
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            // Reuse the reader's membership, current category visibility and completed
            // download checks inside the same atomic snapshot as admission.
            let rows = try query.readRows(transaction: local, transactionId: e.transactionId)
            guard rows.count == 1, let current = rows.first, current.origin == .vendorPayment else {
                throw Failure.unavailable
            }
            let ownership: LocalOperationIdentityDisposition
            do {
                ownership = try LocalOperationIdentityGuard.inspect(transaction: local, operationId: e.operationId,
                    expectedFamily: e.kind.family, expectedFingerprint: fingerprint)
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
            guard e.matchesReview(current) else { throw Failure.staleReview }
            let pending = try local.get(sql: """
                SELECT count(*) FROM spike_local_operations WHERE account_id=? AND subject_id=?
                  AND command_type=? AND local_state IN ('queued','applying')
                """, parameters: [e.accountId.rawValue,e.transactionId.rawValue,e.kind.family.rawValue]) { try $0.getInt(index: 0) }
            guard pending == 0 else { throw Failure.alreadyAccepted }
            _ = try local.execute(sql: """
                INSERT INTO spike_local_operations(id,account_id,actor_principal_id,contract_version,fingerprint,
                  subject_id,local_state,accepted_at_ms,updated_at_ms,command_type,command_envelope_json)
                VALUES (?,?,?,?,?,?,'queued',?,?,?,?)
                """, parameters: [e.operationId.rawValue,e.accountId.rawValue,e.actorPrincipalId.rawValue,
                    e.contractVersion.rawValue,fingerprint,e.transactionId.rawValue,Int64(instant),Int64(instant),e.kind.family.rawValue,json])
            try checkpoint()
            _ = try local.execute(sql: """
                INSERT INTO \(e.kind.table)(id,account_id,actor_principal_id,transaction_id,
                  contract_version,fingerprint,envelope_json) VALUES (?,?,?,?,?,?,?)
                """, parameters: [e.operationId.rawValue,e.accountId.rawValue,e.actorPrincipalId.rawValue,
                    e.transactionId.rawValue,e.contractVersion.rawValue,fingerprint,json])
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            return OperationReceipt(operationId: e.operationId, localState: .queued)
        }
    }

    func pending(scope: TransactionScope, transactionId: TransactionID) async throws -> PendingTransactionDetailsEdit? {
        guard let saved = try await pending(kind: .details, scope: scope, transactionId: transactionId),
              case .details(let command) = saved.0 else { return nil }
        return .init(payload: command.envelope.payload, receipt: saved.1)
    }

    func pendingReceiptLines(scope: TransactionScope, transactionId: TransactionID) async throws -> PendingTransactionReceiptLinesEdit? {
        guard let saved = try await pending(kind: .receiptLines, scope: scope, transactionId: transactionId),
              case .receiptLines(let command) = saved.0 else { return nil }
        return .init(payload: command.envelope.payload, receipt: saved.1)
    }

    private func pending(kind: TransactionEditWork.Kind, scope: TransactionScope,
                         transactionId: TransactionID) async throws -> (TransactionEditWork, OperationReceipt)? {
        guard scope.accountId == accountId else { throw Failure.unavailable }
        let account = accountId, principal = principalId, fence = accessFence
        let query = TransactionDetailPowerSyncQuery(database: database, principalId: principal, scope: scope)
        return try await database.readTransaction { local in
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            let rows = try query.readRows(transaction: local, transactionId: transactionId)
            guard rows.count == 1, let current = rows.first, current.origin == .vendorPayment else { throw Failure.unavailable }
            let operations = try local.getAll(sql: """
                SELECT id,command_envelope_json,local_state FROM spike_local_operations
                WHERE account_id=? AND actor_principal_id=? AND subject_id=? AND command_type=?
                  AND local_state IN ('queued','applying','rejected','applied')
                ORDER BY accepted_at_ms DESC,id DESC
                """, parameters: [account.rawValue,principal.rawValue,transactionId.rawValue,kind.family.rawValue]) {
                    (try $0.getString(index: 0),try $0.getString(index: 1),try $0.getString(index: 2))
                }
            for row in operations {
                let e = try kind.decode(row.1)
                guard e.operationId.rawValue == row.0, e.accountId == account, e.actorPrincipalId == principal,
                      e.transactionId == transactionId, e.scope == scope,
                      let state = LocalOperationState(rawValue: row.2),
                      AccountBoundOperationIdentity.isValid(e.operationId, family: kind.namespace, accountId: account),
                      try LocalOperationIdentityGuard.inspect(transaction: local, operationId: e.operationId,
                        expectedFamily: kind.family,
                        expectedFingerprint: e.fingerprint) == .matchingOwner else {
                    throw LocalOperationIdentityGuardFailure.malformedEvidence
                }
                // Applied edits stop occupying the form only after their newer
                // authoritative row arrives; rejected work remains reviewable.
                if state == .applied, try e.hasReadback(current, local: local) { continue }
                return (e, .init(operationId: e.operationId, localState: state))
            }
            return nil
        }
    }

    func status(_ operationId: OperationID) async throws -> OperationSnapshot? {
        let account = accountId, principal = principalId, fence = accessFence
        guard let kind = [TransactionEditWork.Kind.details, .receiptLines].first(where: {
            AccountBoundOperationIdentity.isValid(operationId, family: $0.namespace, accountId: account)
        }) else { throw Failure.invalidIdentity }
        return try await database.readTransaction { local in
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            guard try ItemDetailsEditPowerSyncStore.hasMembership(local, account: account, principal: principal) else {
                throw Failure.unavailable
            }
            let row = try local.getOptional(sql: """
                SELECT command_envelope_json,local_state,accepted_at_ms,updated_at_ms,
                  terminal_error_code,terminal_server_received_at_ms,terminal_completed_at_ms
                FROM spike_local_operations WHERE id=? AND account_id=? AND actor_principal_id=?
                  AND command_type=?
                """, parameters: [operationId.rawValue,account.rawValue,principal.rawValue,kind.family.rawValue]) {
                    (try $0.getString(index: 0),try $0.getString(index: 1),try $0.getInt64(index: 2),
                     try $0.getInt64(index: 3),try $0.getStringOptional(index: 4),
                     try $0.getInt64Optional(index: 5),try $0.getInt64Optional(index: 6))
                }
            guard let row else { return nil }
            let command = try kind.decode(row.0)
            let fingerprint = try command.fingerprint
            guard command.operationId == operationId, command.accountId == account,
                  command.actorPrincipalId == principal, row.2 >= 0, row.3 >= row.2,
                  try LocalOperationIdentityGuard.inspect(transaction: local, operationId: operationId,
                    expectedFamily: kind.family, expectedFingerprint: fingerprint) == .matchingOwner else {
                throw LocalOperationIdentityGuardFailure.malformedEvidence
            }
            func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }
            let state: OperationState
            switch row.1 {
            case "queued": state = .queued(attemptCount: 0, lastTransientError: nil)
            case "applying": state = .applying(attempt: 1, startedAt: date(row.3))
            case "applied":
                guard let received = row.5, let completed = row.6 else { throw EditTransactionDetailsServerResult.Failure.receiptMismatch }
                state = .applied(.init(resultCode: try .init(validating: kind.resultCode),
                    serverReceivedAt: date(received), completedAt: date(completed)))
            case "rejected":
                guard let error = row.4, kind.rejections.contains(error), let completed = row.6 else {
                    throw EditTransactionDetailsServerResult.Failure.receiptMismatch
                }
                state = .rejected(.init(error: .init(code: try .init(validating: error), category: .conflict,
                    retryDisposition: .afterUserCorrection), rejectedAt: date(completed)))
            default: throw LocalOperationIdentityGuardFailure.malformedEvidence
            }
            return OperationSnapshot(operationId: operationId, accountId: account,
                contractVersion: command.contractVersion, fingerprint: try .init(validating: fingerprint),
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
}
