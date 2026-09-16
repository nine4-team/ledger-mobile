import Foundation
import LedgerTargetCore
import PowerSync

struct ItemReturnReviewStreamIdentity: SyncStreamDescription, Sendable {
    let name = "item_return_review"
    let parameters: JsonParam?
    init(accountId: AccountID, projectId: ProjectID) {
        parameters = ["account_id": .string(accountId.rawValue), "project_id": .string(projectId.rawValue)]
    }
}

public enum ReturnUninvoicedItemsOperationIdentity {
    public static func make(accountId: AccountID, uuid: UUID) throws -> OperationID {
        try AccountBoundOperationIdentity.make(family: .uninvoicedReturn, accountId: accountId, uuid: uuid)
    }
}

/// One durable transaction records intent and its upload entry. Downloaded
/// placements and accounting facts remain server-owned until sync readback.
actor ReturnUninvoicedItemsPowerSyncStore {
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

    func status(_ operationId: OperationID) async throws -> OperationSnapshot? {
        let account = accountId, principal = principalId, fence = accessFence
        return try await database.readTransaction { local in
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            _ = try CategoryManagementLocalProjection.requireMembership(local, account: account, principal: principal)
            guard AccountBoundOperationIdentity.isValid(operationId, family: .uninvoicedReturn, accountId: account) else {
                throw Failure.invalidIdentity
            }
            let row = try local.getOptional(sql: """
                SELECT command_envelope_json,local_state,accepted_at_ms,updated_at_ms,
                  terminal_error_code,terminal_server_received_at_ms,terminal_completed_at_ms
                FROM spike_local_operations WHERE id=? AND account_id=? AND actor_principal_id=?
                  AND command_type='return_uninvoiced_items'
                """, parameters: [operationId.rawValue,account.rawValue,principal.rawValue]) {
                    (try $0.getString(index: 0),try $0.getString(index: 1),try $0.getInt64(index: 2),
                     try $0.getInt64(index: 3),try $0.getStringOptional(index: 4),
                     try $0.getInt64Optional(index: 5),try $0.getInt64Optional(index: 6))
                }
            guard let row else { return nil }
            let command = try OperationContractCodec.decode(ReturnUninvoicedItemsCommand.self, from: Data("{\"envelope\":\(row.0)}".utf8))
            let fingerprint = try ReturnUninvoicedItemsUploadRequest(command).fingerprint
            guard command.envelope.operationId == operationId, command.envelope.accountId == account,
                  command.envelope.actorPrincipalId == principal, row.2 >= 0, row.3 >= row.2,
                  try LocalOperationIdentityGuard.inspect(transaction: local, operationId: operationId,
                    expectedFamily: .returnUninvoicedItems, expectedFingerprint: fingerprint) == .matchingOwner else {
                throw LocalOperationIdentityGuardFailure.malformedEvidence
            }
            func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }
            let state: OperationState
            switch row.1 {
            case "queued": state = .queued(attemptCount: 0, lastTransientError: nil)
            case "applying": state = .applying(attempt: 1, startedAt: date(row.3))
            case "applied":
                guard let received = row.5, let completed = row.6 else { throw ReturnUninvoicedItemsServerResult.Failure.receiptMismatch }
                state = .applied(.init(resultCode: try .init(validating: "uninvoiced_items_returned"),
                    serverReceivedAt: date(received), completedAt: date(completed)))
            case "rejected":
                guard let error = row.4, ReturnUninvoicedItemsServerResult.rejections.contains(error), let completed = row.6 else {
                    throw ReturnUninvoicedItemsServerResult.Failure.receiptMismatch
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

    nonisolated func watchReview(projectId: ProjectID, itemIds: [ItemID]) -> AsyncThrowingStream<UninvoicedReturnReview?, Error> {
        AsyncThrowingStream { continuation in
            let id = UUID(), handle = BudgetCategoryReferenceWatchTaskHandle()
            let registration = Task { await watchRegistry.register(id: id, handle: handle) }
            let task = Task {
                guard await registration.value else { continuation.finish(); return }
                do {
                    try await withOwnedSyncStreamWatch(subscribe: { [self] in
                        try await database.syncStream(name: "physical_account_items",
                            params: ["account_id": .string(accountId.rawValue)]).subscribe()
                    }, observe: { [self] in
                        try await withOwnedSyncStreamWatch(subscribe: { [self] in
                            try await database.syncStream(name: "item_return_review",
                                params: ["account_id": .string(accountId.rawValue), "project_id": .string(projectId.rawValue)]).subscribe()
                        }, observe: { [self] in
                            let changes = try database.watch(sql: """
                                SELECT (SELECT count(*) FROM return_charge_sources),(SELECT count(*) FROM return_live_memberships),
                                  (SELECT count(*) FROM return_paid_memberships),(SELECT count(*) FROM spike_item_placements),
                                  (SELECT count(*) FROM spike_account_memberships),(SELECT count(*) FROM spike_budget_categories),
                                  (SELECT count(*) FROM spike_projects),(SELECT count(*) FROM spike_clients),
                                  (SELECT count(*) FROM ps_stream_subscriptions)
                                """, parameters: nil) { _ in true }
                            for try await _ in changes {
                                try Task.checkCancellation()
                                let value: UninvoicedReturnReview?
                                do { value = try await review(projectId: projectId, itemIds: itemIds) }
                                catch Failure.unavailable { value = nil }
                                catch PropertyManagementReportFailure.incompleteReadiness { value = nil }
                                try Task.checkCancellation()
                                guard !accessFence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
                                if case .terminated = continuation.yield(value) { break }
                            }
                        })
                    })
                    continuation.finish()
                } catch is CancellationError { continuation.finish() }
                catch { continuation.finish(throwing: error) }
                await watchRegistry.finished(id: id)
            }
            handle.install(task)
            continuation.onTermination = { _ in handle.cancel() }
        }
    }

    func review(projectId: ProjectID, itemIds: [ItemID]) async throws -> UninvoicedReturnReview {
        guard (1...500).contains(itemIds.count), Set(itemIds).count == itemIds.count else {
            throw ReturnUninvoicedItemsFailure.invalidSelection
        }
        let account = accountId, principal = principalId, fence = accessFence
        return try await database.readTransaction { local in
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            _ = try CategoryManagementLocalProjection.requireMembership(local, account: account, principal: principal)
            _ = try PropertyManagementReportPowerSyncQuery.completedStreamCheckpoint(transaction: local,
                identity: ItemReturnReviewStreamIdentity(accountId: account, projectId: projectId))
            guard let project = try ClientProjectDirectoryPowerSyncQuery.readProject(projectId,
                account: account, principal: principal, in: local), project.lifecycle == .active,
                project.client.lifecycle == .active else { throw Failure.unavailable }
            let items = try itemIds.map { item -> UninvoicedReturnReview.Item in
                let rows = try Self.readEligibleSources(local, account: account, principal: principal,
                    project: projectId, item: item)
                guard rows.count == 1 else { throw Failure.unavailable }
                return rows[0]
            }
            return try .init(accountId: account, principalId: principal, projectId: projectId, items: items)
        }
    }

    private static func readEligibleSources(_ local: any Transaction, account: AccountID,
        principal: PrincipalID, project: ProjectID, item: ItemID) throws -> [UninvoicedReturnReview.Item] {
        try local.getAll(sql: """
            SELECT c.id,c.placement_id,c.revision FROM return_charge_sources c
            JOIN spike_item_placements p ON p.account_id=c.account_id AND p.id=c.placement_id AND p.item_id=c.item_id
            JOIN spike_budget_categories b ON b.account_id=c.account_id AND b.id=c.category_id
            JOIN spike_account_memberships m ON m.account_id=c.account_id AND m.principal_id=? AND m.state='active'
            WHERE c.account_id=? AND c.project_id=? AND c.item_id=? AND p.project_id=c.project_id
              AND p.scope_kind='project' AND p.ended_at IS NULL
              AND p.start_evidence='recorded_move' AND EXISTS(
                SELECT 1 FROM spike_item_placements predecessor WHERE predecessor.account_id=p.account_id
                  AND predecessor.item_id=p.item_id AND predecessor.scope_kind='business_inventory'
                  AND predecessor.ended_at=p.started_at)
              AND (b.visibility_class='ordinary' OR m.financial_access='full')
              AND NOT EXISTS(SELECT 1 FROM return_live_memberships l WHERE l.account_id=c.account_id AND l.source_id=c.id)
              AND NOT EXISTS(SELECT 1 FROM return_paid_memberships l WHERE l.account_id=c.account_id AND l.source_id=c.id)
            """, parameters: [principal.rawValue,account.rawValue,project.rawValue,item.rawValue]) { row in
                let text = try row.getString(index: 2)
                guard let revision = Int64(text), String(revision) == text else { throw Failure.unavailable }
                return try .init(itemId: item, placementId: .init(validating: row.getString(index: 1)),
                    chargeId: .init(validating: row.getString(index: 0)), revision: revision)
            }
    }

    func submit(_ command: ReturnUninvoicedItemsCommand) async throws -> OperationReceipt {
        let e = command.envelope
        guard e.accountId == accountId, e.actorPrincipalId == principalId else { throw Failure.unavailable }
        guard AccountBoundOperationIdentity.isValid(e.operationId, family: .uninvoicedReturn, accountId: accountId) else {
            throw Failure.invalidIdentity
        }
        let request = try ReturnUninvoicedItemsUploadRequest(command)
        let json = String(decoding: try OperationContractCodec.encode(e), as: UTF8.self)
        let instant = (now().timeIntervalSince1970 * 1000).rounded(.down)
        guard instant.isFinite, instant >= 0, instant < Double(Int64.max) else { throw Failure.invalidClock }
        let account = accountId, principal = principalId, fence = accessFence, checkpoint = afterOperationWrite
        return try await database.writeTransaction { local in
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            _ = try CategoryManagementLocalProjection.requireMembership(local, account: account, principal: principal)
            let ownership: LocalOperationIdentityDisposition
            do {
                ownership = try LocalOperationIdentityGuard.inspect(transaction: local, operationId: e.operationId,
                    expectedFamily: .returnUninvoicedItems, expectedFingerprint: request.fingerprint)
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
                let sources = try Self.readEligibleSources(local, account: account, principal: principal,
                    project: e.payload.projectId, item: item.itemId)
                guard sources.count == 1, sources[0].placementId == item.placementId,
                      sources[0].chargeId == item.chargeId, sources[0].revision == item.expectedChargeRevision else {
                    throw Failure.unavailable
                }
                let reserved = try local.get(sql: """
                    SELECT count(*) FROM spike_local_operations op,json_each(op.command_envelope_json,'$.payload.items') selected
                    WHERE op.account_id=? AND op.command_type='return_uninvoiced_items'
                      AND op.local_state IN ('queued','applying','applied')
                      AND json_extract(selected.value,'$.itemId')=? AND json_extract(selected.value,'$.placementId')=?
                    """, parameters: [account.rawValue,item.itemId.rawValue,item.placementId.rawValue]) { try $0.getInt(index: 0) }
                guard reserved == 0 else { throw Failure.alreadyAccepted }
            }
            try local.execute(sql: """
                INSERT INTO spike_local_operations(id,account_id,actor_principal_id,contract_version,fingerprint,
                  subject_id,local_state,accepted_at_ms,updated_at_ms,command_type,command_envelope_json)
                VALUES (?,?,?,'return-uninvoiced-items-v1',?,?,'queued',?,?,'return_uninvoiced_items',?)
                """, parameters: [e.operationId.rawValue,account.rawValue,principal.rawValue,request.fingerprint,
                    e.payload.projectId.rawValue,Int64(instant),Int64(instant),json])
            try checkpoint()
            try local.execute(sql: """
                INSERT INTO spike_uninvoiced_return_commands(id,account_id,actor_principal_id,project_id,
                  contract_version,fingerprint,envelope_json) VALUES (?,?,?,?,'return-uninvoiced-items-v1',?,?)
                """, parameters: [e.operationId.rawValue,account.rawValue,principal.rawValue,
                    e.payload.projectId.rawValue,request.fingerprint,json])
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            return OperationReceipt(operationId: e.operationId, localState: .queued)
        }
    }
}
