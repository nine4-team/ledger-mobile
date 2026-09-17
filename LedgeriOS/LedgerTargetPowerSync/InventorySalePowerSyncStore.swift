import Foundation
import LedgerTargetCore
import PowerSync

public enum InventorySaleOperationIdentity {
    public static func make(accountId: AccountID, uuid: UUID) throws -> OperationID {
        try AccountBoundOperationIdentity.make(family: .inventorySale, accountId: accountId, uuid: uuid)
    }
}

/// Persist intent and SDK upload entry in one transaction. Downloaded Item and
/// accounting facts are never edited by this queue writer.
actor InventorySalePowerSyncStore {
    enum Failure: Error { case scopeMismatch, invalidIdentity, stalePlacement, stalePrice, invalidClock, destinationUnavailable }
    enum Checkpoint: Sendable { case operationWritten, commandWritten }
    let database: any PowerSyncDatabaseProtocol
    let accountId: AccountID
    let principalId: PrincipalID
    let accessFence: LedgerWorkspaceAccessFence
    private let watchRegistry = BudgetCategoryReferenceWatchRegistry()
    var now: @Sendable () -> Date = Date.init
    var checkpoint: @Sendable (Checkpoint) throws -> Void = { _ in }

    init(database: any PowerSyncDatabaseProtocol, accountId: AccountID, principalId: PrincipalID,
         accessFence: LedgerWorkspaceAccessFence, now: @escaping @Sendable () -> Date = Date.init,
         checkpoint: @escaping @Sendable (Checkpoint) throws -> Void = { _ in }) {
        self.database = database; self.accountId = accountId; self.principalId = principalId
        self.accessFence = accessFence; self.now = now; self.checkpoint = checkpoint
    }

    nonisolated func watch(_ operationId: OperationID) -> AsyncThrowingStream<OperationSnapshot?, Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            let handle = BudgetCategoryReferenceWatchTaskHandle()
            let registration = Task { await watchRegistry.register(id: id, handle: handle) }
            let task = Task {
                guard await registration.value else { continuation.finish(); return }
                do {
                    let changes = try database.watch(sql: """
                        SELECT
                          (SELECT count(*) FROM spike_account_memberships WHERE account_id=? AND principal_id=?),
                          (SELECT count(*) FROM spike_local_operations WHERE id=?),
                          (SELECT count(*) FROM spike_operation_results WHERE id=?)
                        """, parameters: [accountId.rawValue, principalId.rawValue,
                            operationId.rawValue, operationId.rawValue]) { _ in true }
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

    nonisolated func watchReview(itemIds: [ItemID]) -> AsyncThrowingStream<InventorySaleReview?, Error> {
        AsyncThrowingStream { continuation in
            let id = UUID(), handle = BudgetCategoryReferenceWatchTaskHandle()
            let registration = Task { await watchRegistry.register(id: id,handle: handle) }
            let task = Task {
                guard await registration.value else { continuation.finish(); return }
                do {
                    try await withOwnedSyncStreamWatch(subscribe: { [self] in
                        try await database.syncStream(name: "physical_account_items",
                            params: ["account_id": .string(accountId.rawValue)]).subscribe()
                    },observe: { [self] in
                        let changes = try database.watch(sql: """
                            SELECT
                              (SELECT count(*) FROM spike_account_memberships WHERE account_id=?),
                              (SELECT count(*) FROM spike_items WHERE account_id=?),
                              (SELECT count(*) FROM spike_item_placements WHERE account_id=?),
                              (SELECT count(*) FROM item_project_prices WHERE account_id=?),
                              (SELECT count(*) FROM item_acquisition_reviews WHERE account_id=?),
                              (SELECT count(*) FROM ps_stream_subscriptions WHERE stream_name='physical_account_items')
                            """,parameters: Array(repeating: accountId.rawValue,count: 5)) { _ in true }
                        for try await _ in changes {
                            try Task.checkCancellation()
                            let value: InventorySaleReview?
                            do { value = try await review(itemIds: itemIds) }
                            catch InventorySalePrice.Failure.evidenceUnavailable { value = nil }
                            catch Failure.stalePlacement { value = nil }
                            try Task.checkCancellation()
                            guard !accessFence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
                            if case .terminated = continuation.yield(value) { break }
                        }
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

    func review(itemIds: [ItemID]) async throws -> InventorySaleReview {
        guard (1...500).contains(itemIds.count), Set(itemIds).count == itemIds.count else {
            throw InventorySaleReview.Failure.selectionMismatch
        }
        let account = accountId, principal = principalId, fence = accessFence
        return try await database.readTransaction { local in
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            _ = try CategoryManagementLocalProjection.requireMembership(local, account: account, principal: principal)
            let subscriptions = try local.getAll(sql: """
                SELECT local_params,last_synced_at FROM ps_stream_subscriptions
                WHERE stream_name='physical_account_items' AND last_synced_at IS NOT NULL
                """, parameters: nil) { (try $0.getString(index: 0),try $0.getInt64(index: 1)) }
            let expected = JsonValue.object(["account_id": .string(account.rawValue)])
            let completed = try subscriptions.filter {
                try JSONDecoder().decode(JsonValue.self, from: Data($0.0.utf8)) == expected && $0.1 > 0
            }
            guard completed.count == 1 else { throw InventorySalePrice.Failure.evidenceUnavailable }
            let items = try itemIds.map { item -> InventorySaleReview.Item in
                let placements = try local.getAll(sql: """
                    SELECT p.id FROM spike_item_placements p JOIN spike_items i ON i.id=p.item_id AND i.account_id=p.account_id
                    WHERE p.account_id=? AND p.item_id=? AND p.scope_kind='business_inventory' AND p.ended_at IS NULL
                    """, parameters: [account.rawValue,item.rawValue]) { try $0.getString(index: 0) }
                guard placements.count == 1 else { throw Failure.stalePlacement }
                let price = try local.getOptional(sql: "SELECT revision,amount_minor_units,currency FROM item_project_prices WHERE account_id=? AND item_id=?",
                    parameters: [account.rawValue,item.rawValue]) {
                        (try $0.getString(index: 0),try $0.getStringOptional(index: 1),try $0.getString(index: 2))
                    }
                func money(_ amount: String?, _ currency: String?) throws -> Money {
                    guard let amount, let value = Int64(amount), String(value) == amount, let currency else {
                        throw InventorySaleReview.Failure.invalidEvidence
                    }
                    return Money(minorUnits: value,currency: try .init(validating: currency))
                }
                let acquisition = try local.getOptional(sql: "SELECT state,amount_minor_units,currency FROM item_acquisition_reviews WHERE account_id=? AND id=?",
                    parameters: [account.rawValue,item.rawValue]) {
                        (try $0.getString(index: 0),$0.getStringOptional(index: 1),$0.getStringOptional(index: 2))
                    }
                let cost: InventorySalePrice.Evidence
                if let acquisition {
                    switch acquisition.0 {
                    case "known": cost = .known(try money(acquisition.1,acquisition.2))
                    case "absent", "unavailable":
                        guard acquisition.1 == nil, acquisition.2 == nil else { throw InventorySaleReview.Failure.invalidEvidence }
                        cost = acquisition.0 == "absent" ? .confirmedAbsent : .unavailable
                    default: throw InventorySaleReview.Failure.invalidEvidence
                    }
                } else { cost = .unavailable }
                guard let revision = Int64(price?.0 ?? "0"), String(revision) == (price?.0 ?? "0") else {
                    throw InventorySaleReview.Failure.invalidEvidence
                }
                if let price { _ = try CurrencyCode(validating: price.2) }
                return .init(itemId: item,placementId: try .init(validating: placements[0]),priceRevision: revision,
                    projectPrice: try price.flatMap { row in try row.1.map { .known(try money($0,row.2)) } }
                        ?? .confirmedAbsent,purchaseCost: cost)
            }
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            return try InventorySaleReview(accountId: account,principalId: principal,items: items)
        }
    }

    func status(_ operationId: OperationID) async throws -> OperationSnapshot? {
        let account = accountId, principal = principalId, fence = accessFence
        return try await database.readTransaction { local in
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            _ = try CategoryManagementLocalProjection.requireMembership(local, account: account, principal: principal)
            guard AccountBoundOperationIdentity.isValid(operationId, family: .inventorySale, accountId: account) else {
                throw Failure.invalidIdentity
            }
            let row = try local.getOptional(sql: """
                SELECT command_envelope_json,local_state,accepted_at_ms,updated_at_ms,
                    terminal_error_code,terminal_server_received_at_ms,terminal_completed_at_ms
                FROM spike_local_operations WHERE id=? AND account_id=? AND actor_principal_id=?
                  AND command_type='sell_inventory_items'
                """, parameters: [operationId.rawValue,account.rawValue,principal.rawValue]) { cursor in
                    (try cursor.getString(name: "command_envelope_json"), try cursor.getString(name: "local_state"),
                     try cursor.getInt64(name: "accepted_at_ms"), try cursor.getInt64(name: "updated_at_ms"),
                     try cursor.getStringOptional(name: "terminal_error_code"),
                     try cursor.getInt64Optional(name: "terminal_server_received_at_ms"),
                     try cursor.getInt64Optional(name: "terminal_completed_at_ms"))
                }
            guard let row else { return nil }
            let command = try OperationContractCodec.decode(InventorySaleCommand.self, from: Data("{\"envelope\":\(row.0)}".utf8))
            let fingerprint = try InventorySaleUploadRequest(command).fingerprint
            guard command.envelope.operationId == operationId, command.envelope.accountId == account,
                  command.envelope.actorPrincipalId == principal,
                  row.2 >= 0, row.3 >= row.2,
                  try LocalOperationIdentityGuard.inspect(transaction: local, operationId: operationId,
                    expectedFamily: .sellInventoryItems, expectedFingerprint: fingerprint) == .matchingOwner else {
                throw LocalOperationIdentityGuardFailure.malformedEvidence
            }
            func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }
            let state: OperationState
            switch row.1 {
            case "queued": state = .queued(attemptCount: 0, lastTransientError: nil)
            case "applying": state = .applying(attempt: 1, startedAt: date(row.3))
            case "applied":
                guard let received = row.5, let completed = row.6 else { throw InventorySaleServerResult.Failure.receiptMismatch }
                state = .applied(.init(resultCode: try .init(validating: "inventory_items_sold"),
                    serverReceivedAt: date(received), completedAt: date(completed)))
            case "rejected":
                guard let error = row.4, InventorySaleServerResult.rejections.contains(error), let completed = row.6 else {
                    throw InventorySaleServerResult.Failure.receiptMismatch
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

    func submit(_ command: InventorySaleCommand) async throws -> OperationReceipt {
        let envelope = command.envelope
        guard envelope.accountId == accountId, envelope.actorPrincipalId == principalId else {
            throw Failure.scopeMismatch
        }
        guard AccountBoundOperationIdentity.isValid(envelope.operationId, family: .inventorySale, accountId: accountId) else {
            throw Failure.invalidIdentity
        }
        let request = try InventorySaleUploadRequest(command)
        let json = String(decoding: try OperationContractCodec.encode(envelope), as: UTF8.self)
        let instant = (now().timeIntervalSince1970 * 1000).rounded(.down)
        guard instant.isFinite, instant >= 0, instant < Double(Int64.max) else { throw Failure.invalidClock }
        let account = accountId, principal = principalId, fence = accessFence, check = checkpoint
        return try await database.writeTransaction { local in
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            _ = try CategoryManagementLocalProjection.requireMembership(local, account: account, principal: principal)
            let ownership: LocalOperationIdentityDisposition
            do {
                ownership = try LocalOperationIdentityGuard.inspect(transaction: local,
                    operationId: envelope.operationId, expectedFamily: .sellInventoryItems,
                    expectedFingerprint: request.fingerprint)
            } catch LocalOperationIdentityGuardFailure.payloadMismatch {
                throw OperationContractFailure.payloadMismatch(envelope.operationId)
            }
            if ownership == .matchingOwner {
                return try local.get(sql: "SELECT command_envelope_json,local_state FROM spike_local_operations WHERE id=?",
                    parameters: [envelope.operationId.rawValue]) { cursor in
                    guard try cursor.getString(name: "command_envelope_json") == json,
                          let state = LocalOperationState(rawValue: try cursor.getString(name: "local_state")) else {
                        throw LocalOperationIdentityGuardFailure.malformedEvidence
                    }
                    return OperationReceipt(operationId: envelope.operationId, localState: state)
                }
            }
            do {
                guard let destination = try ClientProjectDirectoryPowerSyncQuery.readProject(
                    envelope.payload.projectId, account: account, principal: principal, in: local),
                    destination.lifecycle == .active, destination.client.lifecycle == .active else {
                    throw Failure.destinationUnavailable
                }
                // A retained archive intent without a valid overlay is not
                // permission to accept a conflicting mutation while it uploads.
                let pendingArchive = try local.get(sql: """
                    SELECT count(*) AS n FROM spike_local_operations
                    WHERE account_id=? AND local_state IN ('queued','applying')
                      AND ((command_type='archive_project' AND subject_id=?)
                        OR (command_type='archive_client' AND subject_id=?))
                    """, parameters: [account.rawValue, destination.id.rawValue, destination.clientId.rawValue]) {
                        try $0.getInt(name: "n")
                    }
                guard pendingArchive == 0 else { throw Failure.destinationUnavailable }
            } catch is ClientProjectDirectoryPowerSyncFailure {
                throw Failure.destinationUnavailable
            }
            for item in envelope.payload.items {
                // A second UUID is a new sale, not a retry. Keep the original
                // placement reserved until rejection or downloaded placement
                // change, including the applied-before-readback interval.
                let reserved = try local.get(sql: """
                    SELECT count(*) AS n FROM spike_local_operations op,
                      json_each(op.command_envelope_json,'$.payload.items') selected
                    WHERE op.account_id=? AND op.command_type='sell_inventory_items'
                      AND op.local_state IN ('queued','applying','applied')
                      AND json_extract(selected.value,'$.itemId')=?
                      AND json_extract(selected.value,'$.placementId')=?
                    """, parameters: [account.rawValue,item.itemId.rawValue,item.placementId.rawValue]) {
                        try $0.getInt(name: "n")
                    }
                let count = try local.get(sql: """
                    SELECT count(*) AS n FROM spike_item_placements
                    WHERE id=? AND account_id=? AND item_id=? AND scope_kind='business_inventory' AND ended_at IS NULL
                    """, parameters: [item.placementId.rawValue, account.rawValue, item.itemId.rawValue]) {
                        try $0.getInt(name: "n")
                    }
                guard count == 1 else { throw Failure.stalePlacement }
                let price = try local.getOptional(sql: """
                    SELECT revision,currency FROM item_project_prices WHERE account_id=? AND item_id=?
                    """, parameters: [account.rawValue, item.itemId.rawValue]) {
                        (try $0.getString(name: "revision"), try $0.getString(name: "currency"))
                    }
                // Refuse a review already contradicted by downloaded facts.
                // Absence is not proof of complete acquisition/price evidence;
                // server admission still checks the authoritative cost floor.
                guard (price?.0 ?? "0") == item.priceRevision,
                      price == nil || price?.1 == envelope.payload.currency.rawValue else {
                    throw Failure.stalePrice
                }
                guard reserved == 0 else { throw InventorySaleCommandFailure.saleAlreadyAccepted }
            }
            try local.execute(sql: """
                INSERT INTO spike_local_operations(id,account_id,actor_principal_id,contract_version,fingerprint,
                    subject_id,local_state,accepted_at_ms,updated_at_ms,command_type,command_envelope_json)
                VALUES (?,?,?,'inventory-sale-v1',?,?,'queued',?,?,'sell_inventory_items',?)
                """, parameters: [envelope.operationId.rawValue, account.rawValue, principal.rawValue,
                    request.fingerprint, envelope.payload.projectId.rawValue, Int64(instant), Int64(instant), json])
            try check(.operationWritten)
            try local.execute(sql: """
                INSERT INTO spike_inventory_sale_commands(id,account_id,actor_principal_id,project_id,
                    contract_version,fingerprint,envelope_json) VALUES (?,?,?,?,'inventory-sale-v1',?,?)
                """, parameters: [envelope.operationId.rawValue, account.rawValue, principal.rawValue,
                    envelope.payload.projectId.rawValue, request.fingerprint, json])
            try check(.commandWritten)
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            return OperationReceipt(operationId: envelope.operationId, localState: .queued)
        }
    }
}
