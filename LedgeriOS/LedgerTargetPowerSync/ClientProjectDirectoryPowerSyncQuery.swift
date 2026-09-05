import CryptoKit
import Foundation
import LedgerTargetCore
import PowerSync

enum ClientProjectDirectoryPowerSyncFailure: Error, Equatable, Sendable {
    case malformedClientRow
    case malformedProjectRow
}

public enum ClientProjectDirectoryStream: Sendable {
    case clients
    case projects
}

/// Account- and Principal-bound PowerSync implementation of the backend-neutral
/// Client/Project directory port. The target runtime deliberately supplies no
/// authoritative-completeness proof until a real isolated Sync Stream rehearsal
/// establishes one; local rows remain useful while their quality stays honest.
final class ClientProjectDirectoryPowerSyncQuery:
    ClientProjectDirectoryQuerying, @unchecked Sendable
{
    public typealias CompletenessObservation = @Sendable (
        ClientProjectDirectoryStream,
        AccountID
    ) -> AsyncStream<Bool>

    private let database: any PowerSyncDatabaseProtocol
    private let principalId: PrincipalID
    private let boundAccountId: AccountID
    private let completenessObservation: CompletenessObservation
    private let now: @Sendable () -> Date

    init(
        database: any PowerSyncDatabaseProtocol,
        principalId: PrincipalID,
        accountId: AccountID,
        completenessObservation: @escaping CompletenessObservation = { _, _ in
            AsyncStream { continuation in
                continuation.yield(false)
                continuation.finish()
            }
        },
        now: @Sendable @escaping () -> Date = Date.init
    ) {
        self.database = database
        self.principalId = principalId
        boundAccountId = accountId
        self.completenessObservation = completenessObservation
        self.now = now
    }

    public func watchClients(
        accountId: AccountID
    ) -> AsyncThrowingStream<ClientListSnapshot, Error> {
        guard accountId == boundAccountId else {
            return Self.failedStream(ClientProjectDirectoryFailure.accountScopeMismatch)
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var latestRows: [PowerSyncDirectoryClientRow]?
                    var directoryIsComplete = false
                    for try await event in clientEvents(accountId: accountId) {
                        switch event {
                        case .rows(let rows):
                            latestRows = rows
                        case .completeness(let isComplete):
                            directoryIsComplete = isComplete
                        }
                        guard let observedRows = latestRows else { continue }
                        let scopeIsActive = observedRows.first?.scopeIsActive == true
                        let materialRows = observedRows.filter { $0.id != nil }
                        let clients = try materialRows.map { try $0.clientSummary() }
                        let hasPending = materialRows.contains { $0.pendingOperationId != nil }
                        let isComplete = scopeIsActive
                            && directoryIsComplete
                            && !hasPending
                        let quality = Self.quality(
                            scopeIsActive: scopeIsActive,
                            hasPending: hasPending,
                            isComplete: isComplete,
                            hasLastSyncedAt: database.currentStatus.lastSyncedAt != nil
                        )
                        let local = try ListLocalSnapshot(
                            queryFingerprint: try Self.queryFingerprint(
                                kind: "clients",
                                accountId: accountId
                            ),
                            rows: clients,
                            visibleRowCountBeforeFiltering: materialRows.count,
                            isCompleteForQuery: isComplete,
                            quality: quality,
                            localDataVersion: try Self.localDataVersion(
                                kind: "clients",
                                accountId: accountId,
                                scopeIsActive: scopeIsActive,
                                isComplete: isComplete,
                                quality: quality,
                                rows: materialRows
                            ),
                            asOf: now()
                        )
                        let snapshot = try ClientListSnapshot(
                            accountId: accountId,
                            local: local
                        )

                        for row in materialRows {
                            guard let id = row.id,
                                  let operationId = row.reconciliationOperationId else {
                                continue
                            }
                            try await PowerSyncOverlayReconciler.reconcileClient(
                                database: database,
                                clientId: id,
                                accountId: accountId.rawValue,
                                operationId: operationId
                            )
                        }
                        continuation.yield(snapshot)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func watchProjects(
        accountId: AccountID
    ) -> AsyncThrowingStream<ProjectListSnapshot, Error> {
        guard accountId == boundAccountId else {
            return Self.failedStream(ClientProjectDirectoryFailure.accountScopeMismatch)
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var latestRows: [PowerSyncDirectoryProjectRow]?
                    var directoryIsComplete = false
                    for try await event in projectEvents(accountId: accountId) {
                        switch event {
                        case .rows(let rows):
                            latestRows = rows
                        case .completeness(let isComplete):
                            directoryIsComplete = isComplete
                        }
                        guard let observedRows = latestRows else { continue }
                        let scopeIsActive = observedRows.first?.scopeIsActive == true
                        let materialRows = observedRows.filter { $0.projectId != nil }
                        let projects = try materialRows.compactMap { try $0.projectSummary() }
                        let relationshipIsComplete = projects.count == materialRows.count
                        let hasPending = materialRows.contains { $0.isPending }
                        let isComplete = scopeIsActive
                            && directoryIsComplete
                            && relationshipIsComplete
                            && !hasPending
                        let quality = Self.quality(
                            scopeIsActive: scopeIsActive,
                            hasPending: hasPending || !relationshipIsComplete,
                            isComplete: isComplete,
                            hasLastSyncedAt: database.currentStatus.lastSyncedAt != nil
                        )
                        let local = try ListLocalSnapshot(
                            queryFingerprint: try Self.queryFingerprint(
                                kind: "projects",
                                accountId: accountId
                            ),
                            rows: projects,
                            visibleRowCountBeforeFiltering: materialRows.count,
                            isCompleteForQuery: isComplete,
                            quality: quality,
                            localDataVersion: try Self.localDataVersion(
                                kind: "projects",
                                accountId: accountId,
                                scopeIsActive: scopeIsActive,
                                isComplete: isComplete,
                                quality: quality,
                                rows: materialRows
                            ),
                            asOf: now()
                        )
                        let snapshot = try ProjectListSnapshot(
                            accountId: accountId,
                            local: local
                        )

                        for row in materialRows where row.hasCompleteRelationship {
                            if let projectId = row.projectId,
                               let operationId = row.projectReconciliationOperationId {
                                try await PowerSyncOverlayReconciler.reconcileProjectCore(
                                    database: database,
                                    projectId: projectId,
                                    accountId: accountId.rawValue,
                                    operationId: operationId
                                )
                            }
                            if let clientId = row.clientId,
                               let operationId = row.clientReconciliationOperationId {
                                try await PowerSyncOverlayReconciler.reconcileClient(
                                    database: database,
                                    clientId: clientId,
                                    accountId: accountId.rawValue,
                                    operationId: operationId
                                )
                            }
                        }
                        continuation.yield(snapshot)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private enum ClientDirectoryEvent: Sendable {
        case rows([PowerSyncDirectoryClientRow])
        case completeness(Bool)
    }

    private enum ProjectDirectoryEvent: Sendable {
        case rows([PowerSyncDirectoryProjectRow])
        case completeness(Bool)
    }

    private func clientEvents(
        accountId: AccountID
    ) -> AsyncThrowingStream<ClientDirectoryEvent, Error> {
        AsyncThrowingStream { continuation in
            let databaseTask = Task {
                do {
                    let updates = try database.watch(
                        sql: Self.clientDirectorySQL,
                        parameters: [
                            accountId.rawValue,
                            principalId.rawValue,
                            principalId.rawValue,
                            accountId.rawValue,
                            accountId.rawValue,
                            principalId.rawValue,
                            principalId.rawValue
                        ]
                    ) { cursor in
                        try PowerSyncDirectoryClientRow(cursor: cursor)
                    }
                    for try await rows in updates {
                        try Task.checkCancellation()
                        continuation.yield(.rows(rows))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            let completenessTask = Task {
                for await isComplete in completenessObservation(.clients, accountId) {
                    guard !Task.isCancelled else { return }
                    continuation.yield(.completeness(isComplete))
                }
            }
            continuation.onTermination = { _ in
                databaseTask.cancel()
                completenessTask.cancel()
            }
        }
    }

    private func projectEvents(
        accountId: AccountID
    ) -> AsyncThrowingStream<ProjectDirectoryEvent, Error> {
        AsyncThrowingStream { continuation in
            let databaseTask = Task {
                do {
                    let updates = try database.watch(
                        sql: Self.projectDirectorySQL,
                        parameters: [
                            accountId.rawValue,
                            principalId.rawValue,
                            principalId.rawValue,
                            accountId.rawValue,
                            accountId.rawValue,
                            principalId.rawValue,
                            principalId.rawValue,
                            accountId.rawValue,
                            accountId.rawValue,
                            principalId.rawValue,
                            principalId.rawValue
                        ]
                    ) { cursor in
                        try PowerSyncDirectoryProjectRow(cursor: cursor)
                    }
                    for try await rows in updates {
                        try Task.checkCancellation()
                        continuation.yield(.rows(rows))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            let completenessTask = Task {
                for await isComplete in completenessObservation(.projects, accountId) {
                    guard !Task.isCancelled else { return }
                    continuation.yield(.completeness(isComplete))
                }
            }
            continuation.onTermination = { _ in
                databaseTask.cancel()
                completenessTask.cancel()
            }
        }
    }

    private static func quality(
        scopeIsActive: Bool,
        hasPending: Bool,
        isComplete: Bool,
        hasLastSyncedAt: Bool
    ) -> ListSnapshotQuality {
        if !scopeIsActive || hasPending { return .partial }
        if isComplete { return .ready }
        if hasLastSyncedAt { return .stale }
        return .partial
    }

    private static func queryFingerprint(
        kind: String,
        accountId: AccountID
    ) throws -> ListQueryFingerprint {
        let bytes = Data("client-project-directory-v1|\(kind)|\(accountId.rawValue)".utf8)
        return try ListQueryFingerprint(validating: Self.sha256(bytes))
    }

    private static func localDataVersion<Row: Codable>(
        kind: String,
        accountId: AccountID,
        scopeIsActive: Bool,
        isComplete: Bool,
        quality: ListSnapshotQuality,
        rows: [Row]
    ) throws -> LocalDataVersion {
        let basis = DirectoryVersionBasis(
            contractVersion: "client-project-directory-local-v1",
            kind: kind,
            accountId: accountId,
            scopeIsActive: scopeIsActive,
            isComplete: isComplete,
            quality: quality,
            rows: rows
        )
        let digest = Self.sha256(try OperationContractCodec.encode(basis))
        return try LocalDataVersion(validating: "directory-\(digest)")
    }

    private static func sha256(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private static func failedStream<Value: Sendable>(
        _ error: Error
    ) -> AsyncThrowingStream<Value, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }

    private struct DirectoryVersionBasis<Row: Codable>: Codable {
        let contractVersion: String
        let kind: String
        let accountId: AccountID
        let scopeIsActive: Bool
        let isComplete: Bool
        let quality: ListSnapshotQuality
        let rows: [Row]
    }

    private static let clientDirectorySQL = """
        WITH scope AS (
          SELECT EXISTS (
            SELECT 1
            FROM spike_account_memberships
            WHERE account_id = ? AND principal_id = ? AND state = 'active'
          ) AS is_active
        ), selected_clients AS (
          SELECT authoritative.id, authoritative.account_id,
                 authoritative.display_name, authoritative.lifecycle,
                 authoritative.revision, authoritative.created_at_ms,
                 authoritative.updated_at_ms,
                 NULL AS pending_operation_id,
                 pending.operation_id AS reconciliation_operation_id,
                 NULL AS local_actor_principal_id
          FROM spike_clients AS authoritative
          LEFT JOIN spike_pending_clients AS pending
            ON pending.account_id = authoritative.account_id
           AND pending.id = authoritative.id
           AND pending.created_by_principal_id = ?
          WHERE authoritative.account_id = ?
            AND (SELECT is_active FROM scope)
          UNION ALL
          SELECT pending.id, pending.account_id, pending.display_name,
                 pending.lifecycle, pending.revision, pending.created_at_ms,
                 pending.updated_at_ms, pending.operation_id,
                 NULL AS reconciliation_operation_id,
                 pending.created_by_principal_id AS local_actor_principal_id
          FROM spike_pending_clients AS pending
          WHERE pending.account_id = ?
            AND pending.created_by_principal_id = ?
            AND (
              NOT (SELECT is_active FROM scope)
              OR NOT EXISTS (
                SELECT 1 FROM spike_clients AS authoritative
                WHERE authoritative.account_id = pending.account_id
                  AND authoritative.id = pending.id
              )
            )
        )
        SELECT scope.is_active, client.id, client.account_id,
               client.display_name, client.lifecycle, client.revision,
               client.created_at_ms, client.updated_at_ms,
               client.pending_operation_id, client.reconciliation_operation_id
        FROM scope
        LEFT JOIN selected_clients AS client
          ON scope.is_active OR client.local_actor_principal_id = ?
        ORDER BY client.id
        """

    private static let projectDirectorySQL = """
        WITH scope AS (
          SELECT EXISTS (
            SELECT 1
            FROM spike_account_memberships
            WHERE account_id = ? AND principal_id = ? AND state = 'active'
          ) AS is_active
        ), selected_clients AS (
          SELECT authoritative.id, authoritative.account_id,
                 authoritative.display_name, authoritative.lifecycle,
                 authoritative.created_at_ms, authoritative.updated_at_ms,
                 NULL AS pending_operation_id,
                 pending.operation_id AS reconciliation_operation_id,
                 NULL AS local_actor_principal_id
          FROM spike_clients AS authoritative
          LEFT JOIN spike_pending_clients AS pending
            ON pending.account_id = authoritative.account_id
           AND pending.id = authoritative.id
           AND pending.created_by_principal_id = ?
          WHERE authoritative.account_id = ?
            AND (SELECT is_active FROM scope)
          UNION ALL
          SELECT pending.id, pending.account_id, pending.display_name,
                 pending.lifecycle, pending.created_at_ms,
                 pending.updated_at_ms, pending.operation_id,
                 NULL AS reconciliation_operation_id,
                 pending.created_by_principal_id AS local_actor_principal_id
          FROM spike_pending_clients AS pending
          WHERE pending.account_id = ?
            AND pending.created_by_principal_id = ?
            AND (
              NOT (SELECT is_active FROM scope)
              OR NOT EXISTS (
                SELECT 1 FROM spike_clients AS authoritative
                WHERE authoritative.account_id = pending.account_id
                  AND authoritative.id = pending.id
              )
            )
        ), selected_projects AS (
          SELECT authoritative.id, authoritative.account_id,
                 authoritative.client_id, authoritative.display_name,
                 authoritative.description, authoritative.lifecycle,
                 authoritative.revision,
                 NULL AS pending_operation_id,
                 pending.operation_id AS reconciliation_operation_id,
                 NULL AS local_actor_principal_id
          FROM spike_projects AS authoritative
          LEFT JOIN spike_pending_projects AS pending
            ON pending.account_id = authoritative.account_id
           AND pending.id = authoritative.id
           AND pending.created_by_principal_id = ?
          WHERE authoritative.account_id = ?
            AND (SELECT is_active FROM scope)
          UNION ALL
          SELECT pending.id, pending.account_id, pending.client_id,
                 pending.display_name, pending.description, pending.lifecycle,
                 pending.revision, pending.operation_id,
                 NULL AS reconciliation_operation_id,
                 pending.created_by_principal_id AS local_actor_principal_id
          FROM spike_pending_projects AS pending
          WHERE pending.account_id = ?
            AND pending.created_by_principal_id = ?
            AND (
              NOT (SELECT is_active FROM scope)
              OR NOT EXISTS (
                SELECT 1 FROM spike_projects AS authoritative
                WHERE authoritative.account_id = pending.account_id
                  AND authoritative.id = pending.id
              )
            )
        )
        SELECT scope.is_active,
               project.id AS project_id, project.account_id,
               project.client_id, project.display_name AS project_display_name,
               project.description, project.lifecycle AS project_lifecycle,
               project.revision AS project_revision,
               project.pending_operation_id AS project_pending_operation_id,
               project.reconciliation_operation_id AS project_reconciliation_operation_id,
               client.id AS joined_client_id,
               client.display_name AS client_display_name,
               client.lifecycle AS client_lifecycle,
               client.created_at_ms AS client_created_at_ms,
               client.updated_at_ms AS client_updated_at_ms,
               client.pending_operation_id AS client_pending_operation_id,
               client.reconciliation_operation_id AS client_reconciliation_operation_id
        FROM scope
        LEFT JOIN selected_projects AS project
          ON scope.is_active OR project.local_actor_principal_id = ?
        LEFT JOIN selected_clients AS client
          ON client.account_id = project.account_id
         AND client.id = project.client_id
        ORDER BY project.id
        """
}

enum PowerSyncOverlayReconciler {
    static func reconcileClient(
        database: any PowerSyncDatabaseProtocol,
        clientId: String,
        accountId: String,
        operationId: String
    ) async throws {
        _ = try await database.execute(
            sql: """
            DELETE FROM spike_pending_clients
            WHERE id = ? AND account_id = ? AND operation_id = ?
            """,
            parameters: [clientId, accountId, operationId]
        )
    }

    static func reconcileProjectCore(
        database: any PowerSyncDatabaseProtocol,
        projectId: String,
        accountId: String,
        operationId: String
    ) async throws {
        _ = try await database.execute(
            sql: """
            DELETE FROM spike_pending_projects
            WHERE id = ? AND account_id = ? AND operation_id = ?
            """,
            parameters: [projectId, accountId, operationId]
        )
    }
}

private struct PowerSyncDirectoryClientRow: Codable, Sendable {
    let scopeIsActive: Bool
    let id: String?
    let accountId: String?
    let displayName: String?
    let lifecycle: String?
    let revision: Int64?
    let createdAtMilliseconds: Int64?
    let updatedAtMilliseconds: Int64?
    let pendingOperationId: String?
    let reconciliationOperationId: String?

    init(cursor: any SqlCursor) throws {
        scopeIsActive = try cursor.getInt64(name: "is_active") == 1
        id = try cursor.getStringOptional(name: "id")
        accountId = try cursor.getStringOptional(name: "account_id")
        displayName = try cursor.getStringOptional(name: "display_name")
        lifecycle = try cursor.getStringOptional(name: "lifecycle")
        revision = try cursor.getInt64Optional(name: "revision")
        createdAtMilliseconds = try cursor.getInt64Optional(name: "created_at_ms")
        updatedAtMilliseconds = try cursor.getInt64Optional(name: "updated_at_ms")
        pendingOperationId = try cursor.getStringOptional(name: "pending_operation_id")
        reconciliationOperationId = try cursor.getStringOptional(
            name: "reconciliation_operation_id"
        )
    }

    func clientSummary() throws -> ClientSummary {
        guard let id, let accountId, let displayName, let lifecycle,
              let revision, revision > 0,
              let createdAtMilliseconds, let updatedAtMilliseconds,
              let lifecycle = DirectoryLifecycleState(rawValue: lifecycle) else {
            throw ClientProjectDirectoryPowerSyncFailure.malformedClientRow
        }
        return try ClientSummary(
            id: ClientID(validating: id),
            accountId: AccountID(validating: accountId),
            displayName: ClientDisplayName(validating: displayName),
            lifecycle: lifecycle,
            createdAt: Date(timeIntervalSince1970: Double(createdAtMilliseconds) / 1_000),
            updatedAt: Date(timeIntervalSince1970: Double(updatedAtMilliseconds) / 1_000)
        )
    }
}

private struct PowerSyncDirectoryProjectRow: Codable, Sendable {
    let scopeIsActive: Bool
    let projectId: String?
    let accountId: String?
    let clientId: String?
    let projectDisplayName: String?
    let description: String?
    let projectLifecycle: String?
    let projectRevision: Int64?
    let projectPendingOperationId: String?
    let projectReconciliationOperationId: String?
    let joinedClientId: String?
    let clientDisplayName: String?
    let clientLifecycle: String?
    let clientCreatedAtMilliseconds: Int64?
    let clientUpdatedAtMilliseconds: Int64?
    let clientPendingOperationId: String?
    let clientReconciliationOperationId: String?

    var isPending: Bool {
        projectPendingOperationId != nil || clientPendingOperationId != nil
    }

    var hasCompleteRelationship: Bool {
        guard let clientId else { return false }
        return joinedClientId == clientId
            && clientDisplayName != nil
            && clientLifecycle != nil
            && clientCreatedAtMilliseconds != nil
            && clientUpdatedAtMilliseconds != nil
    }

    init(cursor: any SqlCursor) throws {
        scopeIsActive = try cursor.getInt64(name: "is_active") == 1
        projectId = try cursor.getStringOptional(name: "project_id")
        accountId = try cursor.getStringOptional(name: "account_id")
        clientId = try cursor.getStringOptional(name: "client_id")
        projectDisplayName = try cursor.getStringOptional(name: "project_display_name")
        description = try cursor.getStringOptional(name: "description")
        projectLifecycle = try cursor.getStringOptional(name: "project_lifecycle")
        projectRevision = try cursor.getInt64Optional(name: "project_revision")
        projectPendingOperationId = try cursor.getStringOptional(
            name: "project_pending_operation_id"
        )
        projectReconciliationOperationId = try cursor.getStringOptional(
            name: "project_reconciliation_operation_id"
        )
        joinedClientId = try cursor.getStringOptional(name: "joined_client_id")
        clientDisplayName = try cursor.getStringOptional(name: "client_display_name")
        clientLifecycle = try cursor.getStringOptional(name: "client_lifecycle")
        clientCreatedAtMilliseconds = try cursor.getInt64Optional(
            name: "client_created_at_ms"
        )
        clientUpdatedAtMilliseconds = try cursor.getInt64Optional(
            name: "client_updated_at_ms"
        )
        clientPendingOperationId = try cursor.getStringOptional(
            name: "client_pending_operation_id"
        )
        clientReconciliationOperationId = try cursor.getStringOptional(
            name: "client_reconciliation_operation_id"
        )
    }

    func projectSummary() throws -> ProjectSummary? {
        guard let projectId else {
            return nil
        }
        guard let accountId, let clientId,
              let projectDisplayName, let projectLifecycle,
              let projectRevision, projectRevision > 0 else {
            throw ClientProjectDirectoryPowerSyncFailure.malformedProjectRow
        }
        guard let projectLifecycle = DirectoryLifecycleState(rawValue: projectLifecycle) else {
            throw ClientProjectDirectoryPowerSyncFailure.malformedProjectRow
        }
        guard let joinedClientId else {
            return nil
        }
        guard joinedClientId == clientId else {
            throw ClientProjectDirectoryPowerSyncFailure.malformedProjectRow
        }
        guard let clientDisplayName, let clientLifecycle,
              let clientCreatedAtMilliseconds, let clientUpdatedAtMilliseconds,
              let clientLifecycle = DirectoryLifecycleState(rawValue: clientLifecycle) else {
            throw ClientProjectDirectoryPowerSyncFailure.malformedClientRow
        }
        let typedAccountId = try AccountID(validating: accountId)
        let typedClientId = try ClientID(validating: clientId)
        let client = try ClientSummary(
            id: typedClientId,
            accountId: typedAccountId,
            displayName: ClientDisplayName(validating: clientDisplayName),
            lifecycle: clientLifecycle,
            createdAt: Date(
                timeIntervalSince1970: Double(clientCreatedAtMilliseconds) / 1_000
            ),
            updatedAt: Date(
                timeIntervalSince1970: Double(clientUpdatedAtMilliseconds) / 1_000
            )
        )
        return try ProjectSummary(
            id: ProjectID(validating: projectId),
            accountId: typedAccountId,
            clientId: typedClientId,
            client: client,
            displayName: ProjectDisplayName(validating: projectDisplayName),
            description: description,
            lifecycle: projectLifecycle
        )
    }
}
