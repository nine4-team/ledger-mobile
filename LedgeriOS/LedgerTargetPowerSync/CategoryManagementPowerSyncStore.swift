import Foundation
import LedgerTargetCore
import PowerSync

public enum CategoryManagementOperationIdentity {
    public static func make(accountId: AccountID, uuid: UUID) throws -> OperationID {
        try AccountBoundOperationIdentity.make(family: .categoryManagement, accountId: accountId, uuid: uuid)
    }
}

/// Uses the existing local-operation ledger and PowerSync insert-only queue.
/// Only changed definitions are projected; downloaded facts are never overwritten.
actor CategoryManagementPowerSyncStore: CategoryManaging {
    enum Checkpoint: Sendable { case operationWritten, commandWritten, beforeCommit }
    private let database: any PowerSyncDatabaseProtocol
    private let accountId: AccountID
    private let principalId: PrincipalID
    private let accessFence: LedgerWorkspaceAccessFence
    private let isDirectoryComplete: @Sendable () -> Bool
    private let now: @Sendable () -> Date
    private let checkpoint: @Sendable (Checkpoint) throws -> Void
    private let watchRegistry = BudgetCategoryReferenceWatchRegistry()

    init(database: any PowerSyncDatabaseProtocol, accountId: AccountID, principalId: PrincipalID,
         accessFence: LedgerWorkspaceAccessFence,
         isDirectoryComplete: @escaping @Sendable () -> Bool,
         now: @escaping @Sendable () -> Date = Date.init,
         checkpoint: @escaping @Sendable (Checkpoint) throws -> Void = { _ in }) {
        self.database = database
        self.accountId = accountId
        self.principalId = principalId
        self.accessFence = accessFence
        self.isDirectoryComplete = isDirectoryComplete
        self.now = now
        self.checkpoint = checkpoint
    }

    nonisolated func watchOperations() -> AsyncThrowingStream<[OperationSnapshot], Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            let handle = BudgetCategoryReferenceWatchTaskHandle()
            let registration = Task { await watchRegistry.register(id: id, handle: handle) }
            let task = Task {
                guard await registration.value else { continuation.finish(); return }
                do {
                    let changes = try database.watch(sql: """
                        SELECT
                          (SELECT count(*) FROM spike_account_memberships WHERE account_id = ? AND principal_id = ?),
                          (SELECT count(*) FROM spike_local_operations WHERE account_id = ? AND actor_principal_id = ?),
                          (SELECT count(*) FROM spike_operation_results WHERE account_id = ?)
                        """, parameters: [accountId.rawValue, principalId.rawValue, accountId.rawValue,
                            principalId.rawValue, accountId.rawValue]) { _ in true }
                    for try await _ in changes {
                        try Task.checkCancellation()
                        guard !accessFence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
                        let snapshots = try await database.readTransaction { [accountId, principalId] local in
                            _ = try CategoryManagementLocalProjection.requireMembership(local,
                                account: accountId, principal: principalId)
                            let rows = try local.getAll(sql: """
                                SELECT * FROM spike_local_operations
                                WHERE account_id = ? AND actor_principal_id = ? AND command_type = 'manage_categories'
                                ORDER BY accepted_at_ms, id
                                """, parameters: [accountId.rawValue, principalId.rawValue], mapper: CategoryOperationRow.init)
                            return try rows.map { row in
                                let command = row.command
                                guard command.envelope.accountId == accountId,
                                      command.envelope.actorPrincipalId == principalId,
                                      AccountBoundOperationIdentity.isValid(command.envelope.operationId,
                                        family: .categoryManagement, accountId: accountId),
                                      try LocalOperationIdentityGuard.inspect(transaction: local,
                                        operationId: command.envelope.operationId, expectedFamily: .manageCategories,
                                        expectedFingerprint: command.fingerprint.sha256) == .matchingOwner else {
                                    throw CategoryManagementFailure.receiptMismatch
                                }
                                return try row.snapshot()
                            }
                        }
                        try Task.checkCancellation()
                        guard !accessFence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
                        if case .terminated = continuation.yield(snapshots) { break }
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

    func submit(_ command: CategoryManagementCommand) async throws -> OperationReceipt {
        guard command.envelope.accountId == accountId else { throw CategoryManagementFailure.wrongAccount }
        guard command.envelope.actorPrincipalId == principalId else {
            throw LedgerOfflineClientRuntimeFailure.principalScopeMismatch
        }
        guard AccountBoundOperationIdentity.isValid(command.envelope.operationId,
            family: .categoryManagement, accountId: accountId) else {
            throw CategoryManagementFailure.invalidCommand
        }
        let fingerprint = try command.fingerprint.sha256
        let envelopeJSON = String(decoding: try OperationContractCodec.encode(command.envelope), as: UTF8.self)
        let instant = now()
        let milliseconds = (instant.timeIntervalSince1970 * 1000).rounded(.down)
        guard milliseconds.isFinite, milliseconds >= 0, milliseconds < Double(Int64.max) else {
            throw CategoryManagementFailure.invalidCommand
        }
        let id = command.envelope.operationId.rawValue
        let account = accountId
        let principal = principalId
        let fence = accessFence
        let complete = isDirectoryComplete
        let check = checkpoint
        try Task.checkCancellation()
        return try await database.writeTransaction { transaction in
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            let fullFinancialAccess = try CategoryManagementLocalProjection.requireMembership(
                transaction, account: account, principal: principal)
            let ownership: LocalOperationIdentityDisposition
            do {
                ownership = try LocalOperationIdentityGuard.inspect(transaction: transaction,
                    operationId: command.envelope.operationId, expectedFamily: .manageCategories,
                    expectedFingerprint: fingerprint)
            } catch LocalOperationIdentityGuardFailure.payloadMismatch {
                throw OperationContractFailure.payloadMismatch(command.envelope.operationId)
            }
            if ownership == .matchingOwner {
                let receipt = try transaction.get(sql: """
                    SELECT command_envelope_json, local_state FROM spike_local_operations WHERE id = ?
                    """, parameters: [id]) { cursor in
                    guard try cursor.getString(name: "command_envelope_json") == envelopeJSON,
                          let state = LocalOperationState(rawValue: try cursor.getString(name: "local_state")) else {
                        throw CategoryManagementFailure.receiptMismatch
                    }
                    return OperationReceipt(operationId: command.envelope.operationId, localState: state)
                }
                return receipt
            }
            guard complete() else { throw CategoryManagementFailure.incompleteDirectory }
            if command.envelope.payload.kind == .fee && !fullFinancialAccess {
                throw CategoryManagementFailure.categoryUnavailable
            }
            let before = try CategoryManagementLocalProjection.read(transaction,
                account: account, principal: principal, fullFinancialAccess: fullFinancialAccess)
            let snapshot = try BudgetCategoryReferenceSnapshot(accountId: account, local: ListLocalSnapshot(
                queryFingerprint: ListQueryFingerprint(validating: String(repeating: "c", count: 64)),
                rows: before, visibleRowCountBeforeFiltering: before.count, isCompleteForQuery: true,
                quality: .ready, localDataVersion: LocalDataVersion(validating: "category-admission"), asOf: instant))
            let after = try CategoryManagement.applying(command.envelope.payload, to: snapshot)
            let prior = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0) })
            let changes = after.filter { prior[$0.id] != $0 }
            let projection = String(decoding: try OperationContractCodec.encode(changes), as: UTF8.self)
            let last = try transaction.get(sql: """
                SELECT COALESCE(MAX(accepted_at_ms), 0) AS last FROM spike_local_operations
                WHERE account_id = ? AND command_type = 'manage_categories'
                """, parameters: [account.rawValue]) { try $0.getInt64(name: "last") }
            guard last < Int64.max else { throw CategoryManagementFailure.invalidCommand }
            let accepted = max(Int64(milliseconds), last + 1)
            try transaction.execute(sql: """
                INSERT INTO spike_local_operations(id, account_id, actor_principal_id, contract_version,
                    fingerprint, subject_id, local_state, accepted_at_ms, updated_at_ms,
                    command_type, command_envelope_json, category_projection_json)
                VALUES (?, ?, ?, 'category-management-v1', ?, ?, 'queued', ?, ?, 'manage_categories', ?, ?)
                """, parameters: [id, account.rawValue, principal.rawValue, fingerprint, account.rawValue,
                    accepted, accepted, envelopeJSON, projection])
            try check(.operationWritten)
            try transaction.execute(sql: """
                INSERT INTO spike_category_commands(id, account_id, actor_principal_id,
                    contract_version, fingerprint, envelope_json)
                VALUES (?, ?, ?, 'category-management-v1', ?, ?)
                """, parameters: [id, account.rawValue, principal.rawValue, fingerprint, envelopeJSON])
            try check(.commandWritten)
            try Task.checkCancellation()
            guard !fence.isRemoved else { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
            try check(.beforeCommit)
            return OperationReceipt(operationId: command.envelope.operationId, localState: .queued)
        }
    }
}

private struct CategoryOperationRow {
    let command: CategoryManagementCommand
    let phase: String
    let accepted: Date
    let updated: Date
    let received: Date?
    let completed: Date?
    let errorCode: String?

    init(_ cursor: any SqlCursor) throws {
        let json = try cursor.getString(name: "command_envelope_json")
        command = try OperationContractCodec.decode(CategoryManagementCommand.self,
            from: Data("{\"envelope\":\(json)}".utf8))
        guard try cursor.getString(name: "id") == command.envelope.operationId.rawValue else {
            throw CategoryManagementFailure.receiptMismatch
        }
        phase = try cursor.getString(name: "local_state")
        let acceptedMS = try cursor.getInt64(name: "accepted_at_ms")
        let updatedMS = try cursor.getInt64(name: "updated_at_ms")
        guard acceptedMS >= 0, updatedMS >= acceptedMS else { throw CategoryManagementFailure.receiptMismatch }
        accepted = Date(timeIntervalSince1970: Double(acceptedMS) / 1000)
        updated = Date(timeIntervalSince1970: Double(updatedMS) / 1000)
        received = try cursor.getInt64Optional(name: "terminal_server_received_at_ms").map { Date(timeIntervalSince1970: Double($0) / 1000) }
        completed = try cursor.getInt64Optional(name: "terminal_completed_at_ms").map { Date(timeIntervalSince1970: Double($0) / 1000) }
        errorCode = try cursor.getStringOptional(name: "terminal_error_code")
    }

    func snapshot() throws -> OperationSnapshot {
        let state: OperationState
        switch phase {
        case "queued": state = .queued(attemptCount: 0, lastTransientError: nil)
        case "applying": state = .applying(attempt: 1, startedAt: updated)
        case "applied":
            guard let received, let completed else { throw CategoryManagementFailure.receiptMismatch }
            state = .applied(.init(resultCode: try ApplicationResultCode(validating: "categories_updated"),
                serverReceivedAt: received, completedAt: completed))
        case "rejected":
            guard let errorCode, let completed else { throw CategoryManagementFailure.receiptMismatch }
            state = .rejected(.init(error: .init(code: try ApplicationErrorCode(validating: errorCode),
                category: .conflict, retryDisposition: .afterUserCorrection), rejectedAt: completed))
        default: throw CategoryManagementFailure.receiptMismatch
        }
        return OperationSnapshot(operationId: command.envelope.operationId, accountId: command.envelope.accountId,
            contractVersion: command.envelope.contractVersion, fingerprint: try command.fingerprint,
            acceptedAt: accepted, updatedAt: updated, state: state)
    }
}

enum CategoryManagementLocalProjection {
    static func requireMembership(_ transaction: any Transaction, account: AccountID,
                                  principal: PrincipalID) throws -> Bool {
        guard let financial = try transaction.getOptional(sql: """
            SELECT financial_access FROM spike_account_memberships
            WHERE account_id = ? AND principal_id = ? AND state = 'active'
            """, parameters: [account.rawValue, principal.rawValue], mapper: {
                try $0.getString(name: "financial_access")
            }) else { throw CategoryManagementFailure.categoryUnavailable }
        return financial == "full"
    }

    static func read(_ transaction: any Transaction, account: AccountID, principal: PrincipalID,
                     fullFinancialAccess: Bool) throws -> [BudgetCategoryDefinitionSnapshot] {
        let currentlyHiddenIds = fullFinancialAccess ? Set<String>() : Set(try transaction.getAll(sql: """
            SELECT id FROM spike_budget_categories WHERE account_id = ? AND kind = 'fee'
            """, parameters: [account.rawValue]) { try $0.getString(name: "id") })
        let authoritative = try transaction.getAll(sql: """
            SELECT id, account_id, display_name, kind, lifecycle, is_system,
                excludes_from_overall_budget, presentation_order, revision
            FROM spike_budget_categories WHERE account_id = ? AND (kind <> 'fee' OR ?)
            """, parameters: [account.rawValue, fullFinancialAccess ? 1 : 0]) { cursor in
            let order = try cursor.getInt64(name: "presentation_order")
            let revision = try cursor.getInt64(name: "revision")
            let system = try cursor.getInt64(name: "is_system")
            let excluded = try cursor.getInt64(name: "excludes_from_overall_budget")
            guard let kind = BudgetCategoryKind(rawValue: try cursor.getString(name: "kind")),
                  let lifecycle = DirectoryLifecycleState(rawValue: try cursor.getString(name: "lifecycle")),
                  let position = UInt32(exactly: order), revision > 0,
                  (0...1).contains(system), (0...1).contains(excluded) else {
                throw BudgetCategoryReferencePowerSyncFailure.malformedCategoryRow
            }
            return BudgetCategoryDefinitionSnapshot(id: try BudgetCategoryID(validating: cursor.getString(name: "id")),
                accountId: account, name: try BudgetCategoryName(validating: cursor.getString(name: "display_name")),
                kind: kind, lifecycle: lifecycle, isSystem: system == 1,
                excludesFromOverallBudget: excluded == 1,
                presentationOrder: position, revision: UInt64(revision))
        }
        let operations = try transaction.getAll(sql: """
            SELECT operation.local_state, operation.category_projection_json,
                json_extract(operation.command_envelope_json, '$.payload.action') AS action,
                json_extract(operation.command_envelope_json, '$.payload.categoryId') AS category_id,
                EXISTS (
                    SELECT 1 FROM spike_operation_results result
                    WHERE result.id = operation.id AND result.account_id = operation.account_id
                      AND result.actor_principal_id = operation.actor_principal_id
                      AND result.command_type = operation.command_type
                      AND result.contract_version = operation.contract_version
                      AND result.envelope_sha256 = operation.fingerprint
                      AND result.command_fingerprint = operation.fingerprint
                      AND result.phase IN ('applied', 'rejected')
                ) AS replicated
            FROM spike_local_operations operation
            WHERE operation.account_id = ? AND operation.actor_principal_id = ?
              AND operation.command_type = 'manage_categories'
              AND operation.local_state IN ('queued', 'applying', 'applied')
            ORDER BY operation.accepted_at_ms, operation.id
            """, parameters: [account.rawValue, principal.rawValue]) { cursor in
            (state: try cursor.getString(name: "local_state"),
             encoded: try cursor.getString(name: "category_projection_json"),
             createdId: try cursor.getString(name: "action") == "create"
                ? try cursor.getStringOptional(name: "category_id") : nil,
             replicated: try cursor.getInt64(name: "replicated") == 1)
        }
        let serverRows = Dictionary(uniqueKeysWithValues: authoritative.map { ($0.id, $0) })
        let unreplicatedCreates = Set(operations.filter { !$0.replicated }.compactMap(\.createdId))
        var visible = serverRows
        for operation in operations where !operation.replicated {
            let changes = try OperationContractCodec.decode([BudgetCategoryDefinitionSnapshot].self,
                from: Data(operation.encoded.utf8))
            guard Set(changes.map(\.id)).count == changes.count,
                  changes.allSatisfy({ $0.accountId == account && !$0.isSystem
                      && $0.revision > 0 && $0.revision <= UInt64(Int64.max) }) else {
                throw CategoryManagementFailure.invalidCommand
            }
            for row in changes {
                // Pending intent is not permission to disclose a currently
                // hidden downloaded definition after a financial downgrade.
                guard !currentlyHiddenIds.contains(row.id.rawValue) else { continue }
                // Sync can withdraw a row entirely. An edit cannot restore it;
                // only an unreplicated local creation explains a missing baseline.
                // A replicated terminal result retires that creation's overlay,
                // preventing old applied commands from reviving withdrawn data.
                guard serverRows[row.id] != nil || unreplicatedCreates.contains(row.id.rawValue) else { continue }
                // Once server evidence is at least this revision, newer synced
                // definitions win. Rejected operations never reach this loop.
                if operation.state == "applied", let server = serverRows[row.id], server.revision >= row.revision { continue }
                visible[row.id] = row
            }
        }
        return visible.values.filter { $0.kind != .fee || fullFinancialAccess }
            .sorted { $0.presentationOrder < $1.presentationOrder }
    }
}
