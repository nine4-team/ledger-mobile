import Foundation
import LedgerTargetCore
import PowerSync

public enum InventorySourceReturnOperationIdentity {
    public static func make(accountId: AccountID, uuid: UUID) throws -> OperationID {
        try AccountBoundOperationIdentity.make(family: .sourceReturn, accountId: accountId, uuid: uuid)
    }
}

actor InventorySourceReturnPowerSyncStore {
    enum Failure: Error { case unavailable, invalidIdentity, invalidClock, alreadyAccepted }
    let database: any PowerSyncDatabaseProtocol
    let accountId: AccountID
    let principalId: PrincipalID
    let accessFence: LedgerWorkspaceAccessFence
    let now: @Sendable () -> Date
    let afterOperationWrite: @Sendable () throws -> Void
    private let watches = BudgetCategoryReferenceWatchRegistry()

    init(database: any PowerSyncDatabaseProtocol, accountId: AccountID, principalId: PrincipalID,
         accessFence: LedgerWorkspaceAccessFence, now: @escaping @Sendable () -> Date = Date.init,
         afterOperationWrite: @escaping @Sendable () throws -> Void = {}) {
        self.database = database; self.accountId = accountId; self.principalId = principalId
        self.accessFence = accessFence; self.now = now; self.afterOperationWrite = afterOperationWrite
    }
    func cancelAndDrainWatches() async { await watches.cancelAndDrain() }

    nonisolated func watchReview(itemIds: [ItemID]) -> AsyncThrowingStream<InventorySourceReturnReview?, Error> {
        watchValue { [self] in
            do { return try await review(itemIds: itemIds) }
            catch Failure.unavailable { return nil }
            catch CategoryManagementFailure.categoryUnavailable { return nil }
            catch PropertyManagementReportFailure.incompleteReadiness { return nil }
        }
    }
    nonisolated func watch(_ id: OperationID) -> AsyncThrowingStream<OperationSnapshot?, Error> {
        watchValue { [self] in try await status(id) }
    }
    private nonisolated func watchValue<T: Sendable>(_ read: @escaping @Sendable () async throws -> T)
        -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            let id = UUID(), handle = BudgetCategoryReferenceWatchTaskHandle()
            let registration = Task { await watches.register(id: id, handle: handle) }
            let task = Task {
                guard await registration.value else { continuation.finish(); return }
                do {
                    try await withOwnedSyncStreamWatch(subscribe: { [self] in
                        try await database.syncStream(name: "physical_account_items",
                            params: ["account_id": .string(accountId.rawValue)]).subscribe()
                    }, observe: { [self] in
                        let changes = try database.watch(sql: """
                            SELECT (SELECT count(*) FROM inventory_source_entries),(SELECT count(*) FROM spike_item_placements),
                              (SELECT count(*) FROM spike_account_memberships),(SELECT count(*) FROM spike_budget_categories),
                              (SELECT count(*) FROM spike_projects),(SELECT count(*) FROM spike_clients),
                              (SELECT count(*) FROM spike_local_operations),(SELECT count(*) FROM spike_operation_results),
                              (SELECT count(*) FROM ps_stream_subscriptions)
                            """, parameters: nil) { _ in true }
                        for try await _ in changes {
                            try Task.checkCancellation()
                            let value = try await read()
                            try Task.checkCancellation()
                            guard !accessFence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
                            if case .terminated = continuation.yield(value) { break }
                        }
                    })
                    continuation.finish()
                } catch is CancellationError { continuation.finish() }
                catch { continuation.finish(throwing: error) }
                await watches.finished(id: id)
            }
            handle.install(task)
            continuation.onTermination = { _ in handle.cancel() }
        }
    }
    func review(itemIds: [ItemID]) async throws -> InventorySourceReturnReview {
        let account = accountId, principal = principalId, fence = accessFence
        return try await database.readTransaction { local in
            try Self.requireAccess(local, account: account, principal: principal, fence: fence)
            return try Self.readReview(local, account: account, principal: principal, itemIds: itemIds)
        }
    }
    private static func readReview(_ local: any Transaction, account: AccountID, principal: PrincipalID,
                                   itemIds: [ItemID]) throws -> InventorySourceReturnReview {
        guard (1...100).contains(itemIds.count), Set(itemIds).count == itemIds.count else { throw Failure.unavailable }
        let subscriptions = try local.getAll(sql: """
            SELECT local_params FROM ps_stream_subscriptions WHERE stream_name='physical_account_items' AND last_synced_at>0
            """, parameters: nil) { try $0.getString(index: 0) }
        let expected = JsonValue.object(["account_id": .string(account.rawValue)])
        guard try subscriptions.filter({ try JSONDecoder().decode(JsonValue.self, from: Data($0.utf8)) == expected }).count == 1 else {
            throw Failure.unavailable
        }
        let items = try itemIds.map { item -> InventorySourceReturnReview.Item in
            let entries = try local.getAll(sql: """
                SELECT e.id,e.inventory_placement_id,e.source_project_id,e.source_category_id,e.amount_minor_units,e.currency
                FROM inventory_source_entries e JOIN spike_item_placements p ON p.account_id=e.account_id
                  AND p.id=e.inventory_placement_id AND p.item_id=e.item_id
                WHERE e.account_id=? AND e.item_id=? AND p.scope_kind='business_inventory' AND p.ended_at IS NULL
                """, parameters: [account.rawValue,item.rawValue]) {
                    (try $0.getString(index: 0),try $0.getString(index: 1),try $0.getString(index: 2),
                     try $0.getString(index: 3),try $0.getString(index: 4),try $0.getString(index: 5))
                }
            guard entries.count == 1, let row = entries.first, let amount = Int64(row.4), String(amount) == row.4,
                  let project = try ClientProjectDirectoryPowerSyncQuery.readProject(.init(validating: row.2),
                    account: account, principal: principal, in: local), project.lifecycle == .active,
                  project.client.lifecycle == .active else { throw Failure.unavailable }
            let membership = try CategoryManagementLocalProjection.requireMembership(local, account: account, principal: principal)
            let visible = try local.get(sql: "SELECT count(*) FROM spike_budget_categories WHERE account_id=? AND id=? AND (visibility_class='ordinary' OR ?='full')",
                parameters: [account.rawValue,row.3,membership ? "full" : "restricted"]) { try $0.getInt(index: 0) }
            guard visible == 1 else { throw Failure.unavailable }
            let categoryName = try local.getOptional(sql: "SELECT display_name FROM spike_budget_categories WHERE account_id=? AND id=?",
                parameters: [account.rawValue,row.3]) { $0.getStringOptional(index: 0) } ?? nil
            return try .init(itemId: item, placementId: .init(validating: row.1), inventoryEntryId: .init(validating: row.0),
                sourceProjectId: .init(validating: row.2), sourceCategoryId: .init(validating: row.3),
                sourceAmount: .init(minorUnits: amount, currency: .init(validating: row.5)), categoryDisplayName: categoryName)
        }
        let projectName = try items.first.flatMap { item in
            try local.getOptional(sql: "SELECT display_name FROM spike_projects WHERE account_id=? AND id=?",
                parameters: [account.rawValue,item.sourceProjectId.rawValue]) { $0.getStringOptional(index: 0) } ?? nil
        }
        do { return try .init(accountId: account, principalId: principal, items: items, projectDisplayName: projectName) }
        catch { throw Failure.unavailable }
    }
    private static func requireAccess(_ local: any Transaction, account: AccountID, principal: PrincipalID,
                                      fence: LedgerWorkspaceAccessFence) throws {
        try Task.checkCancellation()
        guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
        _ = try CategoryManagementLocalProjection.requireMembership(local, account: account, principal: principal)
    }
    func submit(_ command: ReturnInventoryItemsToSourceCommand) async throws -> OperationReceipt {
        let e = command.envelope
        guard e.accountId == accountId, e.actorPrincipalId == principalId,
              AccountBoundOperationIdentity.isValid(e.operationId, family: .sourceReturn, accountId: accountId) else { throw Failure.invalidIdentity }
        let request = try InventorySourceReturnUploadRequest(command)
        let json = String(decoding: try OperationContractCodec.encode(e), as: UTF8.self)
        let instant = (now().timeIntervalSince1970 * 1000).rounded(.down)
        guard instant.isFinite, instant >= 0, instant < Double(Int64.max) else { throw Failure.invalidClock }
        let account = accountId, principal = principalId, fence = accessFence, checkpoint = afterOperationWrite
        return try await database.writeTransaction { local in
            try Self.requireAccess(local, account: account, principal: principal, fence: fence)
            let ownership: LocalOperationIdentityDisposition
            do {
                ownership = try LocalOperationIdentityGuard.inspect(transaction: local, operationId: e.operationId,
                    expectedFamily: .returnInventoryToSource, expectedFingerprint: request.fingerprint)
            } catch LocalOperationIdentityGuardFailure.payloadMismatch {
                throw OperationContractFailure.payloadMismatch(e.operationId)
            }
            if ownership == .matchingOwner {
                return try local.get(sql: "SELECT command_envelope_json,local_state FROM spike_local_operations WHERE id=?",
                    parameters: [e.operationId.rawValue]) {
                        guard try $0.getString(index: 0) == json,
                              let state = LocalOperationState(rawValue: try $0.getString(index: 1)) else { throw Failure.invalidIdentity }
                        return OperationReceipt(operationId: e.operationId, localState: state)
                    }
            }
            let review = try Self.readReview(local, account: account, principal: principal, itemIds: e.payload.items.map(\.itemId))
            guard review.projectId == e.payload.projectId else { throw Failure.unavailable }
            let pendingArchive = try local.get(sql: """
                SELECT count(*) FROM spike_local_operations WHERE account_id=? AND local_state IN ('queued','applying')
                  AND ((command_type='archive_project' AND subject_id=?) OR (command_type='archive_client'
                    AND subject_id=(SELECT client_id FROM spike_projects WHERE account_id=? AND id=?)))
                """, parameters: [account.rawValue,e.payload.projectId.rawValue,account.rawValue,e.payload.projectId.rawValue]) { try $0.getInt(index: 0) }
            guard pendingArchive == 0 else { throw Failure.unavailable }
            for (selected, item) in zip(e.payload.items, review.items) {
                guard selected.placementId == item.placementId, selected.inventoryEntryId == item.inventoryEntryId else { throw Failure.unavailable }
                let reserved = try local.get(sql: """
                    SELECT count(*) FROM spike_local_operations op,json_each(op.command_envelope_json,'$.payload.items') selected
                    WHERE op.account_id=? AND op.command_type IN ('sell_inventory_items','return_inventory_to_source')
                      AND op.local_state IN ('queued','applying','applied') AND json_extract(selected.value,'$.itemId')=?
                      AND json_extract(selected.value,'$.placementId')=?
                    """, parameters: [account.rawValue,item.itemId.rawValue,item.placementId.rawValue]) { try $0.getInt(index: 0) }
                guard reserved == 0 else { throw Failure.alreadyAccepted }
            }
            try local.execute(sql: """
                INSERT INTO spike_local_operations(id,account_id,actor_principal_id,contract_version,fingerprint,
                  subject_id,local_state,accepted_at_ms,updated_at_ms,command_type,command_envelope_json)
                VALUES (?,?,?,'return-inventory-to-source-v1',?,?,'queued',?,?,'return_inventory_to_source',?)
                """, parameters: [e.operationId.rawValue,account.rawValue,principal.rawValue,request.fingerprint,
                    e.payload.projectId.rawValue,Int64(instant),Int64(instant),json])
            try checkpoint()
            try local.execute(sql: """
                INSERT INTO spike_source_return_commands(id,account_id,actor_principal_id,project_id,contract_version,fingerprint,envelope_json)
                VALUES (?,?,?,?,'return-inventory-to-source-v1',?,?)
                """, parameters: [e.operationId.rawValue,account.rawValue,principal.rawValue,e.payload.projectId.rawValue,request.fingerprint,json])
            try Self.requireAccess(local, account: account, principal: principal, fence: fence)
            return OperationReceipt(operationId: e.operationId, localState: .queued)
        }
    }
    func status(_ operationId: OperationID) async throws -> OperationSnapshot? {
        let account = accountId, principal = principalId, fence = accessFence
        return try await database.readTransaction { local in
            try Self.requireAccess(local, account: account, principal: principal, fence: fence)
            guard AccountBoundOperationIdentity.isValid(operationId, family: .sourceReturn, accountId: account) else { throw Failure.invalidIdentity }
            let optionalRow = try local.getOptional(sql: """
                SELECT command_envelope_json,local_state,accepted_at_ms,updated_at_ms,terminal_error_code,
                  terminal_server_received_at_ms,terminal_completed_at_ms FROM spike_local_operations
                WHERE id=? AND account_id=? AND actor_principal_id=? AND command_type='return_inventory_to_source'
                """, parameters: [operationId.rawValue,account.rawValue,principal.rawValue]) {
                    (try $0.getString(index: 0),try $0.getString(index: 1),try $0.getInt64(index: 2),try $0.getInt64(index: 3),
                     try $0.getStringOptional(index: 4),try $0.getInt64Optional(index: 5),try $0.getInt64Optional(index: 6))
                }
            guard let row = optionalRow else { return nil }
            let command = try OperationContractCodec.decode(ReturnInventoryItemsToSourceCommand.self, from: Data("{\"envelope\":\(row.0)}".utf8))
            let fingerprint = try InventorySourceReturnUploadRequest(command).fingerprint
            guard command.envelope.operationId == operationId, command.envelope.accountId == account,
                  command.envelope.actorPrincipalId == principal, row.2 >= 0, row.3 >= row.2,
                  try LocalOperationIdentityGuard.inspect(transaction: local, operationId: operationId,
                expectedFamily: .returnInventoryToSource, expectedFingerprint: fingerprint) == .matchingOwner else { throw Failure.invalidIdentity }
            func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms)/1000) }
            let state: OperationState
            switch row.1 {
            case "queued": state = .queued(attemptCount: 0, lastTransientError: nil)
            case "applying": state = .applying(attempt: 1, startedAt: date(row.3))
            case "applied":
                guard let received = row.5, let completed = row.6 else { throw Failure.invalidIdentity }
                state = .applied(.init(resultCode: try .init(validating: "inventory_items_returned_to_source"),
                    serverReceivedAt: date(received), completedAt: date(completed)))
            case "rejected":
                guard let error = row.4, InventorySourceReturnServerResult.rejections.contains(error), let completed = row.6 else { throw Failure.invalidIdentity }
                state = .rejected(.init(error: .init(code: try .init(validating: error), category: .conflict,
                    retryDisposition: .afterUserCorrection), rejectedAt: date(completed)))
            default: throw Failure.invalidIdentity
            }
            return OperationSnapshot(operationId: operationId, accountId: account, contractVersion: command.envelope.contractVersion,
                fingerprint: try .init(validating: fingerprint), acceptedAt: date(row.2), updatedAt: date(row.3), state: state)
        }
    }
}
