import Foundation
import LedgerTargetCore
import PowerSync

public enum ReturnPaidItemsOperationIdentity {
    public static func make(accountId: AccountID, uuid: UUID) throws -> OperationID {
        try AccountBoundOperationIdentity.make(family: .paidReturn, accountId: accountId, uuid: uuid)
    }
}

/// Uses the existing local operation and insert-only upload queue, never optimistic
/// edits to server-owned placements or frozen accounting rows.
actor ReturnPaidItemsPowerSyncStore {
    enum Failure: Error { case unavailable, invalidIdentity, invalidClock, alreadyAccepted }
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

    func cancelAndDrainWatches() async { await watchRegistry.cancelAndDrain() }

    nonisolated func watch(_ operationId: OperationID) -> AsyncThrowingStream<OperationSnapshot?, Error> {
        trackedWatch { [self] continuation in
            let changes = try database.watch(sql: """
                SELECT (SELECT count(*) FROM spike_account_memberships WHERE account_id=? AND principal_id=?),
                  (SELECT count(*) FROM spike_local_operations WHERE id=?),
                  (SELECT count(*) FROM spike_operation_results WHERE id=?)
                """, parameters: [accountId.rawValue,principalId.rawValue,operationId.rawValue,operationId.rawValue]) { _ in true }
            for try await _ in changes {
                let value = try await status(operationId)
                try Task.checkCancellation()
                guard !accessFence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
                if case .terminated = continuation.yield(value) { break }
            }
        }
    }

    nonisolated func watchReview(projectId: ProjectID, itemIds: [ItemID]) -> AsyncThrowingStream<PaidReturnReview?, Error> {
        trackedWatch { [self] continuation in
            let identity = ItemReturnReviewStreamIdentity(accountId: accountId, projectId: projectId)
            try await withOwnedSyncStreamWatch(subscribe: { [self] in
                try await database.syncStream(name: identity.name, params: identity.parameters).subscribe()
            }, observe: { [self] in
                try await ProjectInvoicingChargePowerSyncQuery(database: database).run(accountId: accountId,
                    principalId: principalId, projectId: projectId) { [self] snapshot in
                        let value: PaidReturnReview?
                        if snapshot == nil { value = nil }
                        else {
                            do { value = try await review(projectId: projectId, itemIds: itemIds) }
                            catch Failure.unavailable { value = nil }
                            catch PropertyManagementReportFailure.incompleteReadiness { value = nil }
                            catch { continuation.finish(throwing: error); return false }
                        }
                        guard !Task.isCancelled, !accessFence.isRemoved else { return false }
                        if case .terminated = continuation.yield(value) { return false }
                        return true
                    }
            })
        }
    }

    private nonisolated func trackedWatch<Value: Sendable>(
        _ body: @escaping @Sendable (AsyncThrowingStream<Value, Error>.Continuation) async throws -> Void
    ) -> AsyncThrowingStream<Value, Error> {
        AsyncThrowingStream { continuation in
            let id = UUID(), handle = BudgetCategoryReferenceWatchTaskHandle()
            let registration = Task { await watchRegistry.register(id: id, handle: handle) }
            let task = Task {
                guard await registration.value else { continuation.finish(); return }
                do { try await body(continuation); continuation.finish() }
                catch is CancellationError { continuation.finish() }
                catch { continuation.finish(throwing: error) }
                await watchRegistry.finished(id: id)
            }
            handle.install(task)
            continuation.onTermination = { _ in handle.cancel() }
        }
    }

    func status(_ operationId: OperationID) async throws -> OperationSnapshot? {
        let account = accountId, principal = principalId, fence = accessFence
        return try await database.readTransaction { local in
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            _ = try CategoryManagementLocalProjection.requireMembership(local, account: account, principal: principal)
            guard AccountBoundOperationIdentity.isValid(operationId, family: .paidReturn, accountId: account) else {
                throw Failure.invalidIdentity
            }
            let row = try local.getOptional(sql: """
                SELECT command_envelope_json,local_state,accepted_at_ms,updated_at_ms,
                  terminal_error_code,terminal_server_received_at_ms,terminal_completed_at_ms
                FROM spike_local_operations WHERE id=? AND account_id=? AND actor_principal_id=?
                  AND command_type='return_paid_items'
                """, parameters: [operationId.rawValue,account.rawValue,principal.rawValue]) {
                    (try $0.getString(index: 0),try $0.getString(index: 1),try $0.getInt64(index: 2),
                     try $0.getInt64(index: 3),try $0.getStringOptional(index: 4),
                     try $0.getInt64Optional(index: 5),try $0.getInt64Optional(index: 6))
                }
            guard let row else { return nil }
            let command = try OperationContractCodec.decode(ReturnPaidItemsCommand.self, from: Data("{\"envelope\":\(row.0)}".utf8))
            let fingerprint = try ReturnPaidItemsUploadRequest(command).fingerprint
            guard command.envelope.operationId == operationId, command.envelope.accountId == account,
                  command.envelope.actorPrincipalId == principal, row.2 >= 0, row.3 >= row.2,
                  try LocalOperationIdentityGuard.inspect(transaction: local, operationId: operationId,
                    expectedFamily: .returnPaidItems, expectedFingerprint: fingerprint) == .matchingOwner else {
                throw LocalOperationIdentityGuardFailure.malformedEvidence
            }
            func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }
            let state: OperationState
            switch row.1 {
            case "queued": state = .queued(attemptCount: 0, lastTransientError: nil)
            case "applying": state = .applying(attempt: 1, startedAt: date(row.3))
            case "applied":
                guard let received = row.5, let completed = row.6 else { throw ReturnPaidItemsServerResult.Failure.receiptMismatch }
                state = .applied(.init(resultCode: try .init(validating: "paid_items_returned"),
                    serverReceivedAt: date(received), completedAt: date(completed)))
            case "rejected":
                guard let error = row.4, ReturnPaidItemsServerResult.rejections.contains(error), let completed = row.6 else {
                    throw ReturnPaidItemsServerResult.Failure.receiptMismatch
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

    func review(projectId: ProjectID, itemIds: [ItemID]) async throws -> PaidReturnReview {
        let account = accountId, principal = principalId, fence = accessFence
        return try await database.readTransaction { local in
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            try ProjectInvoicingItemLocalReader.requireAccess(transaction: local,
                accountId: account, principalId: principal, projectId: projectId)
            _ = try PropertyManagementReportPowerSyncQuery.completedStreamCheckpoint(transaction: local,
                identity: ProjectInvoicingChargeStreamIdentity(accountId: account, projectId: projectId))
            _ = try PropertyManagementReportPowerSyncQuery.completedStreamCheckpoint(transaction: local,
                identity: ItemReturnReviewStreamIdentity(accountId: account, projectId: projectId))
            guard let project = try ClientProjectDirectoryPowerSyncQuery.readProject(projectId,
                account: account, principal: principal, in: local), project.lifecycle == .active,
                project.client.lifecycle == .active else { throw Failure.unavailable }
            let evidence = try ProjectInvoicingItemLocalReader.readAuthorizedCharges(transaction: local,
                accountId: account, principalId: principal, projectId: projectId)
            let items = try itemIds.map { item -> PaidReturnReview.Item in
                let rows = try local.getAll(sql: """
                    SELECT c.id,c.placement_id,l.id AS line_id,l.signed_amount_minor_units,l.currency,l.category_id
                    FROM item_charge_occurrences c
                    JOIN spike_item_placements p ON p.account_id=c.account_id AND p.id=c.placement_id AND p.item_id=c.item_id
                    JOIN collected_invoice_lines l ON l.account_id=c.account_id AND l.source_kind='item'
                      AND l.source_id=c.id AND l.item_id=c.item_id
                    JOIN collected_invoices h ON h.account_id=l.account_id AND h.id=l.invoice_id AND h.project_id=c.project_id
                    WHERE c.account_id=? AND c.project_id=? AND c.item_id=? AND c.withdrawn_at IS NULL
                      AND p.scope_kind='project' AND p.project_id=c.project_id AND p.ended_at IS NULL
                      AND p.start_evidence='recorded_move' AND h.sealed=1
                      AND EXISTS(SELECT 1 FROM spike_item_placements prior WHERE prior.account_id=p.account_id
                        AND prior.item_id=p.item_id AND prior.scope_kind='business_inventory' AND prior.ended_at=p.started_at)
                      AND NOT EXISTS(SELECT 1 FROM paid_item_return_credits credit WHERE credit.account_id=c.account_id AND credit.charge_id=c.id)
                    """, parameters: [account.rawValue,projectId.rawValue,item.rawValue]) { cursor in
                        let text = try cursor.getString(name: "signed_amount_minor_units")
                        guard let amount = Int64(text), String(amount) == text else { throw Failure.unavailable }
                        return try PaidReturnReview.Item(itemId: item,
                            placementId: .init(validating: cursor.getString(name: "placement_id")),
                            chargeId: .init(validating: cursor.getString(name: "id")),
                            paidInvoiceLineId: .init(validating: cursor.getString(name: "line_id")),
                            paidAmount: .init(minorUnits: amount, currency: .init(validating: cursor.getString(name: "currency"))),
                            categoryId: .init(validating: cursor.getString(name: "category_id")))
                    }
                guard rows.count == 1, evidence.contains(where: {
                    $0.occurrence.id == rows[0].chargeId && $0.occurrence.polarity == .charge
                        && $0.availability == .paid && $0.amount == rows[0].paidAmount
                }) else { throw Failure.unavailable }
                return rows[0]
            }
            return try .init(accountId: account, principalId: principal, projectId: projectId, items: items)
        }
    }

    func submit(_ command: ReturnPaidItemsCommand) async throws -> OperationReceipt {
        let e = command.envelope
        guard e.accountId == accountId, e.actorPrincipalId == principalId else { throw Failure.unavailable }
        guard AccountBoundOperationIdentity.isValid(e.operationId, family: .paidReturn, accountId: accountId) else {
            throw Failure.invalidIdentity
        }
        let request = try ReturnPaidItemsUploadRequest(command)
        let json = String(decoding: try OperationContractCodec.encode(e), as: UTF8.self)
        let instant = (now().timeIntervalSince1970 * 1000).rounded(.down)
        guard instant.isFinite, instant >= 0, instant < Double(Int64.max) else { throw Failure.invalidClock }
        let account = accountId, principal = principalId, fence = accessFence, checkpoint = afterOperationWrite
        return try await database.writeTransaction { local in
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            try ProjectInvoicingItemLocalReader.requireAccess(transaction: local,
                accountId: account, principalId: principal, projectId: e.payload.projectId)
            let ownership: LocalOperationIdentityDisposition
            do {
                ownership = try LocalOperationIdentityGuard.inspect(transaction: local, operationId: e.operationId,
                    expectedFamily: .returnPaidItems, expectedFingerprint: request.fingerprint)
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
                identity: ProjectInvoicingChargeStreamIdentity(accountId: account, projectId: e.payload.projectId))
            _ = try PropertyManagementReportPowerSyncQuery.completedStreamCheckpoint(transaction: local,
                identity: ItemReturnReviewStreamIdentity(accountId: account, projectId: e.payload.projectId))
            guard let project = try ClientProjectDirectoryPowerSyncQuery.readProject(e.payload.projectId,
                account: account, principal: principal, in: local), project.lifecycle == .active,
                project.client.lifecycle == .active else { throw Failure.unavailable }
            let archived = try local.get(sql: """
                SELECT count(*) FROM spike_local_operations WHERE account_id=? AND local_state IN ('queued','applying')
                AND ((command_type='archive_project' AND subject_id=?) OR (command_type='archive_client' AND subject_id=?))
                """, parameters: [account.rawValue,project.id.rawValue,project.clientId.rawValue]) { try $0.getInt(index: 0) }
            guard archived == 0 else { throw Failure.unavailable }
            for item in e.payload.items {
                let eligible = try local.get(sql: """
                    SELECT count(*) FROM item_charge_occurrences c
                    JOIN spike_item_placements p ON p.account_id=c.account_id AND p.id=c.placement_id AND p.item_id=c.item_id
                    JOIN collected_invoice_lines l ON l.account_id=c.account_id AND l.source_kind='item'
                      AND l.source_id=c.id AND l.item_id=c.item_id
                    JOIN collected_invoices h ON h.account_id=l.account_id AND h.id=l.invoice_id AND h.project_id=c.project_id
                    WHERE c.account_id=? AND c.project_id=? AND c.item_id=? AND c.id=? AND p.id=? AND l.id=?
                      AND c.withdrawn_at IS NULL AND p.scope_kind='project' AND p.project_id=c.project_id
                      AND p.ended_at IS NULL AND p.start_evidence='recorded_move' AND h.sealed=1
                      AND EXISTS(SELECT 1 FROM spike_item_placements prior WHERE prior.account_id=p.account_id
                        AND prior.item_id=p.item_id AND prior.scope_kind='business_inventory' AND prior.ended_at=p.started_at)
                      AND NOT EXISTS(SELECT 1 FROM paid_item_return_credits credit WHERE credit.account_id=c.account_id AND credit.charge_id=c.id)
                    """, parameters: [account.rawValue,project.id.rawValue,item.itemId.rawValue,item.chargeId.rawValue,
                        item.placementId.rawValue,item.paidInvoiceLineId.rawValue]) { try $0.getInt(index: 0) }
                guard eligible == 1 else { throw Failure.unavailable }
                let reserved = try local.get(sql: """
                    SELECT count(*) FROM spike_local_operations op,json_each(op.command_envelope_json,'$.payload.items') selected
                    WHERE op.account_id=? AND op.command_type IN ('return_uninvoiced_items','return_paid_items')
                      AND op.local_state IN ('queued','applying','applied')
                      AND json_extract(selected.value,'$.itemId')=? AND json_extract(selected.value,'$.placementId')=?
                    """, parameters: [account.rawValue,item.itemId.rawValue,item.placementId.rawValue]) { try $0.getInt(index: 0) }
                guard reserved == 0 else { throw Failure.alreadyAccepted }
            }
            // Reuse typed accounting validation before accepting the frozen basis locally.
            let rows = try ProjectInvoicingItemLocalReader.readAuthorizedCharges(transaction: local,
                accountId: account, principalId: principal, projectId: project.id)
            guard e.payload.items.allSatisfy({ item in rows.contains {
                $0.occurrence.id == item.chargeId && $0.occurrence.polarity == .charge
                    && $0.availability == .paid && $0.amount.minorUnits > 0
            }}) else { throw Failure.unavailable }
            try local.execute(sql: """
                INSERT INTO spike_local_operations(id,account_id,actor_principal_id,contract_version,fingerprint,
                  subject_id,local_state,accepted_at_ms,updated_at_ms,command_type,command_envelope_json)
                VALUES (?,?,?,'return-paid-items-v1',?,?,'queued',?,?,'return_paid_items',?)
                """, parameters: [e.operationId.rawValue,account.rawValue,principal.rawValue,request.fingerprint,
                    project.id.rawValue,Int64(instant),Int64(instant),json])
            try checkpoint()
            try local.execute(sql: """
                INSERT INTO spike_paid_return_commands(id,account_id,actor_principal_id,project_id,
                  contract_version,fingerprint,envelope_json) VALUES (?,?,?,?,'return-paid-items-v1',?,?)
                """, parameters: [e.operationId.rawValue,account.rawValue,principal.rawValue,
                    project.id.rawValue,request.fingerprint,json])
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            return OperationReceipt(operationId: e.operationId, localState: .queued)
        }
    }
}
