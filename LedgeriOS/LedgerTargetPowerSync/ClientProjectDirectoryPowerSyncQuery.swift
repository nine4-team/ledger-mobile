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
                        let projects = try materialRows.compactMap {
                            try $0.projectSummary(expectedPrincipalId: principalId.rawValue)
                        }
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
                            if let projectId = row.projectId,
                               let archiveOperationId = row.archiveOperationId {
                                try await PowerSyncOverlayReconciler.reconcileProjectArchive(
                                    database: database,
                                    projectId: projectId,
                                    accountId: accountId.rawValue,
                                    operationId: archiveOperationId
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
                 authoritative.revision AS base_revision,
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
                 pending.revision AS base_revision, pending.operation_id,
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
               project.description,
               CASE
                 WHEN archive.operation_id IS NOT NULL
                  AND project.base_revision <= archive.projected_revision
                 THEN archive.lifecycle ELSE project.lifecycle
               END AS project_lifecycle,
               CASE
                 WHEN archive.operation_id IS NOT NULL
                  AND project.base_revision <= archive.projected_revision
                 THEN archive.projected_revision ELSE project.base_revision
               END AS project_revision,
               project.lifecycle AS project_base_lifecycle,
               project.base_revision AS project_base_revision,
               project.pending_operation_id AS project_pending_operation_id,
               project.reconciliation_operation_id AS project_reconciliation_operation_id,
               client.id AS joined_client_id,
               client.display_name AS client_display_name,
               client.lifecycle AS client_lifecycle,
               client.created_at_ms AS client_created_at_ms,
               client.updated_at_ms AS client_updated_at_ms,
               client.pending_operation_id AS client_pending_operation_id,
               client.reconciliation_operation_id AS client_reconciliation_operation_id,
               archive.operation_id AS archive_operation_id,
               archive.account_id AS archive_account_id,
               archive.actor_principal_id AS archive_actor_principal_id,
               archive.project_id AS archive_project_id,
               archive.fingerprint AS archive_fingerprint,
               archive.expected_revision AS archive_expected_revision,
               archive.projected_revision AS archive_projected_revision,
               archive.lifecycle AS archive_lifecycle,
               archive.accepted_at_ms AS archive_accepted_at_ms,
               archive_operation.account_id AS archive_operation_account_id,
               archive_operation.actor_principal_id AS archive_operation_actor_principal_id,
               archive_operation.contract_version AS archive_operation_contract_version,
               archive_operation.fingerprint AS archive_operation_fingerprint,
               archive_operation.subject_id AS archive_operation_subject_id,
               archive_operation.local_state AS archive_operation_state,
               archive_operation.command_type AS archive_operation_command_type,
               archive_operation.command_expected_revision AS archive_operation_expected_revision,
               archive_operation.command_envelope_json AS archive_operation_envelope_json,
               count(archive.id) OVER (
                 PARTITION BY project.account_id, project.id
               ) AS archive_overlay_count,
               (
                 SELECT count(*)
                 FROM \(LedgerPowerSyncTable.localOperations) AS applied_archive
                 WHERE applied_archive.account_id = project.account_id
                   AND applied_archive.subject_id = project.id
                   AND applied_archive.contract_version = 'project-archive-v1'
                   AND applied_archive.local_state IN ('queued', 'applying', 'applied')
                   AND NOT EXISTS (
                     SELECT 1
                     FROM \(LedgerPowerSyncTable.projectArchiveOverlays) AS retained_archive
                     WHERE retained_archive.operation_id = applied_archive.id
                   )
                   AND (
                     applied_archive.local_state IN ('queued', 'applying')
                     OR (
                       applied_archive.local_state = 'applied'
                       AND NOT (
                         applied_archive.command_expected_revision IS NOT NULL
                         AND CAST(CAST(applied_archive.command_expected_revision AS INTEGER) AS TEXT)
                           = applied_archive.command_expected_revision
                         AND CAST(applied_archive.command_expected_revision AS INTEGER) > 0
                         AND (
                           project.base_revision
                             > CAST(applied_archive.command_expected_revision AS INTEGER) + 1
                           OR (
                             project.base_revision
                               = CAST(applied_archive.command_expected_revision AS INTEGER) + 1
                             AND project.lifecycle = 'archived'
                           )
                         )
                       )
                     )
                   )
               ) AS missing_applied_archive_overlay_count
        FROM scope
        LEFT JOIN selected_projects AS project
          ON scope.is_active OR project.local_actor_principal_id = ?
        LEFT JOIN selected_clients AS client
          ON client.account_id = project.account_id
         AND client.id = project.client_id
        LEFT JOIN \(LedgerPowerSyncTable.projectArchiveOverlays) AS archive
          ON archive.account_id = project.account_id
         AND archive.project_id = project.id
        LEFT JOIN \(LedgerPowerSyncTable.localOperations) AS archive_operation
          ON archive_operation.id = archive.operation_id
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

    static func reconcileProjectArchive(
        database: any PowerSyncDatabaseProtocol,
        projectId: String,
        accountId: String,
        operationId: String
    ) async throws {
        _ = try await database.execute(
            sql: """
            DELETE FROM \(LedgerPowerSyncTable.projectArchiveOverlays)
            WHERE operation_id = ?
              AND account_id = ?
              AND project_id = ?
              AND lifecycle = 'archived'
              AND EXISTS (
                SELECT 1
                FROM \(LedgerPowerSyncTable.localOperations) AS operation
                WHERE operation.id = \(LedgerPowerSyncTable.projectArchiveOverlays).operation_id
                  AND operation.account_id = \(LedgerPowerSyncTable.projectArchiveOverlays).account_id
                  AND operation.actor_principal_id = \(LedgerPowerSyncTable.projectArchiveOverlays).actor_principal_id
                  AND operation.fingerprint = \(LedgerPowerSyncTable.projectArchiveOverlays).fingerprint
                  AND operation.subject_id = \(LedgerPowerSyncTable.projectArchiveOverlays).project_id
                  AND operation.local_state = 'applied'
              )
              AND EXISTS (
                SELECT 1
                FROM \(LedgerPowerSyncTable.projects) AS authoritative
                WHERE authoritative.account_id = \(LedgerPowerSyncTable.projectArchiveOverlays).account_id
                  AND authoritative.id = \(LedgerPowerSyncTable.projectArchiveOverlays).project_id
                  AND (
                    authoritative.revision > \(LedgerPowerSyncTable.projectArchiveOverlays).projected_revision
                    OR (
                      authoritative.revision = \(LedgerPowerSyncTable.projectArchiveOverlays).projected_revision
                      AND authoritative.lifecycle = 'archived'
                    )
                  )
              )
            """,
            parameters: [operationId, accountId, projectId]
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
    let projectBaseLifecycle: String?
    let projectBaseRevision: Int64?
    let archiveOperationId: String?
    let archiveAccountId: String?
    let archiveActorPrincipalId: String?
    let archiveProjectId: String?
    let archiveFingerprint: String?
    let archiveExpectedRevision: String?
    let archiveProjectedRevision: Int64?
    let archiveLifecycle: String?
    let archiveAcceptedAtMilliseconds: Int64?
    let archiveOperationAccountId: String?
    let archiveOperationActorPrincipalId: String?
    let archiveOperationContractVersion: String?
    let archiveOperationFingerprint: String?
    let archiveOperationSubjectId: String?
    let archiveOperationState: String?
    let archiveOperationCommandType: String?
    let archiveOperationExpectedRevision: String?
    let archiveOperationEnvelopeJSON: String?
    let archiveOverlayCount: Int64
    let missingAppliedArchiveOverlayCount: Int64

    var isPending: Bool {
        projectPendingOperationId != nil
            || clientPendingOperationId != nil
            || archiveOperationId != nil
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
        projectBaseLifecycle = try cursor.getStringOptional(name: "project_base_lifecycle")
        projectBaseRevision = try cursor.getInt64Optional(name: "project_base_revision")
        archiveOperationId = try cursor.getStringOptional(name: "archive_operation_id")
        archiveAccountId = try cursor.getStringOptional(name: "archive_account_id")
        archiveActorPrincipalId = try cursor.getStringOptional(
            name: "archive_actor_principal_id"
        )
        archiveProjectId = try cursor.getStringOptional(name: "archive_project_id")
        archiveFingerprint = try cursor.getStringOptional(name: "archive_fingerprint")
        archiveExpectedRevision = try cursor.getStringOptional(
            name: "archive_expected_revision"
        )
        archiveProjectedRevision = try cursor.getInt64Optional(
            name: "archive_projected_revision"
        )
        archiveLifecycle = try cursor.getStringOptional(name: "archive_lifecycle")
        archiveAcceptedAtMilliseconds = try cursor.getInt64Optional(
            name: "archive_accepted_at_ms"
        )
        archiveOperationAccountId = try cursor.getStringOptional(
            name: "archive_operation_account_id"
        )
        archiveOperationActorPrincipalId = try cursor.getStringOptional(
            name: "archive_operation_actor_principal_id"
        )
        archiveOperationContractVersion = try cursor.getStringOptional(
            name: "archive_operation_contract_version"
        )
        archiveOperationFingerprint = try cursor.getStringOptional(
            name: "archive_operation_fingerprint"
        )
        archiveOperationSubjectId = try cursor.getStringOptional(
            name: "archive_operation_subject_id"
        )
        archiveOperationState = try cursor.getStringOptional(name: "archive_operation_state")
        archiveOperationCommandType = try cursor.getStringOptional(
            name: "archive_operation_command_type"
        )
        archiveOperationExpectedRevision = try cursor.getStringOptional(
            name: "archive_operation_expected_revision"
        )
        archiveOperationEnvelopeJSON = try cursor.getStringOptional(
            name: "archive_operation_envelope_json"
        )
        archiveOverlayCount = try cursor.getInt64(name: "archive_overlay_count")
        missingAppliedArchiveOverlayCount = try cursor.getInt64(
            name: "missing_applied_archive_overlay_count"
        )
    }

    func projectSummary(expectedPrincipalId: String) throws -> ProjectSummary? {
        guard let projectId else {
            return nil
        }
        guard let accountId, let clientId,
              let projectDisplayName, let projectLifecycle,
              let projectRevision, projectRevision > 0 else {
            throw ClientProjectDirectoryPowerSyncFailure.malformedProjectRow
        }
        try validateArchiveOverlay(
            accountId: accountId,
            projectId: projectId,
            expectedPrincipalId: expectedPrincipalId
        )
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

    private func validateArchiveOverlay(
        accountId: String,
        projectId: String,
        expectedPrincipalId: String
    ) throws {
        guard missingAppliedArchiveOverlayCount == 0 else {
            throw ClientProjectDirectoryPowerSyncFailure.malformedProjectRow
        }
        guard let archiveOperationId else {
            guard archiveOverlayCount == 0 else {
                throw ClientProjectDirectoryPowerSyncFailure.malformedProjectRow
            }
            return
        }
        guard archiveOverlayCount == 1,
              archiveAccountId == accountId,
              archiveProjectId == projectId,
              archiveActorPrincipalId == expectedPrincipalId,
              archiveLifecycle == "archived",
              let archiveActorPrincipalId,
              let archiveFingerprint,
              let archiveExpectedRevision,
              let expected = UInt64(archiveExpectedRevision),
              String(expected) == archiveExpectedRevision,
              expected > 0,
              expected < UInt64(Int64.max),
              archiveProjectedRevision == Int64(expected) + 1,
              let archiveAcceptedAtMilliseconds,
              archiveAcceptedAtMilliseconds >= 0,
              archiveOperationAccountId == accountId,
              archiveOperationActorPrincipalId == archiveActorPrincipalId,
              archiveOperationFingerprint == archiveFingerprint,
              archiveOperationSubjectId == projectId,
              ["queued", "applying", "applied"].contains(archiveOperationState),
              archiveOperationContractVersion == "project-archive-v1",
              archiveOperationCommandType == "archive_project",
              archiveOperationExpectedRevision == archiveExpectedRevision,
              let archiveOperationEnvelopeJSON,
              (try? OperationID(validating: archiveOperationId)) != nil,
              (try? OperationFingerprint(validating: archiveFingerprint)) != nil,
              projectBaseLifecycle != nil,
              projectBaseRevision != nil else {
            throw ClientProjectDirectoryPowerSyncFailure.malformedProjectRow
        }
        guard ProjectArchiveOverlayCommandValidator.isValid(
            operationId: archiveOperationId,
            accountId: accountId,
            actorPrincipalId: archiveActorPrincipalId,
            contractVersion: "project-archive-v1",
            projectId: projectId,
            expectedRevision: expected,
            fingerprint: archiveFingerprint,
            envelopeJSON: archiveOperationEnvelopeJSON
        ) else {
            throw ClientProjectDirectoryPowerSyncFailure.malformedProjectRow
        }
    }
}

enum ProjectArchiveOverlayCommandValidator {
    static func isValid(
        operationId: String,
        accountId: String,
        actorPrincipalId: String,
        contractVersion: String,
        projectId: String,
        expectedRevision: UInt64,
        fingerprint: String,
        envelopeJSON: String
    ) -> Bool {
        guard let typedOperationId = try? OperationID(validating: operationId),
              let typedAccountId = try? AccountID(validating: accountId),
              ProjectArchiveOperationIdentity.isValid(
                typedOperationId,
                accountId: typedAccountId
              ),
              let data = envelopeJSON.data(using: .utf8),
              let envelope = try? OperationContractCodec.decode(
                OperationEnvelope<ArchiveProjectPayload>.self,
                from: data
              ),
              let canonical = try? OperationContractCodec.encode(envelope),
              canonical == data,
              envelope.operationId.rawValue == operationId,
              envelope.accountId.rawValue == accountId,
              envelope.actorPrincipalId.rawValue == actorPrincipalId,
              envelope.contractVersion.rawValue == contractVersion,
              envelope.payload.projectId.rawValue == projectId,
              let entityId = try? EntityID(validating: projectId),
              envelope.preconditions == [
                .expectedRevision(
                    subject: LedgerEntityReference(
                        kind: .project,
                        id: entityId
                    ),
                    revision: expectedRevision
                )
              ],
              let typedFingerprint = try? OperationFingerprint(validating: fingerprint),
              (try? OperationFingerprint.make(for: envelope)) == typedFingerprint else {
            return false
        }
        return true
    }
}
