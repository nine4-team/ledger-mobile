import Foundation
import LedgerTargetCore
import PowerSync

final class ProjectCoreDetailsPowerSyncQuery: ProjectCoreDetailsQuerying, @unchecked Sendable {
    private let database: any PowerSyncDatabaseProtocol
    private let principalId: PrincipalID
    private let boundAccountId: AccountID
    private let now: @Sendable () -> Date

    init(
        database: any PowerSyncDatabaseProtocol,
        principalId: PrincipalID,
        accountId: AccountID,
        now: @Sendable @escaping () -> Date = Date.init
    ) {
        self.database = database
        self.principalId = principalId
        boundAccountId = accountId
        self.now = now
    }

    public func watchProjectCoreDetails(
        _ request: ProjectCoreDetailsRequest
    ) -> AsyncThrowingStream<ProjectCoreDetailsUpdate, Error> {
        guard request.accountId == boundAccountId else {
            return Self.failedStream(ProjectCoreDetailsFailure.accountScopeMismatch)
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(try ProjectCoreDetailsUpdate(
                        request: request,
                        state: .waiting(.loading)
                    ))
                    let rows = try database.watch(
                        sql: """
                        WITH scope AS (
                          SELECT EXISTS (
                            SELECT 1
                            FROM \(LedgerPowerSyncTable.memberships)
                            WHERE account_id = ? AND principal_id = ? AND state = 'active'
                          ) AS is_active
                        ), selected_projects AS (
                          SELECT authoritative.id, authoritative.account_id,
                                 authoritative.client_id, authoritative.display_name,
                                 authoritative.description, authoritative.lifecycle,
                                 authoritative.revision AS base_revision,
                                 NULL AS pending_operation_id,
                                 pending.operation_id AS reconciliation_operation_id
                          FROM \(LedgerPowerSyncTable.projects) AS authoritative
                          LEFT JOIN \(LedgerPowerSyncTable.pendingProjects) AS pending
                            ON pending.account_id = authoritative.account_id
                           AND pending.id = authoritative.id
                           AND pending.created_by_principal_id = ?
                          WHERE authoritative.account_id = ? AND authoritative.id = ?
                            AND (SELECT is_active FROM scope)
                          UNION ALL
                          SELECT pending.id, pending.account_id, pending.client_id,
                                 pending.display_name, pending.description,
                                 pending.lifecycle, pending.revision AS base_revision,
                                 pending.operation_id AS pending_operation_id,
                                 NULL AS reconciliation_operation_id
                          FROM \(LedgerPowerSyncTable.pendingProjects) AS pending
                          WHERE pending.account_id = ? AND pending.id = ?
                            AND pending.created_by_principal_id = ?
                            AND (
                              NOT (SELECT is_active FROM scope)
                              OR NOT EXISTS (
                                SELECT 1 FROM \(LedgerPowerSyncTable.projects) AS authoritative
                                WHERE authoritative.account_id = pending.account_id
                                  AND authoritative.id = pending.id
                              )
                            )
                        ), selected_clients AS (
                          SELECT authoritative.id, authoritative.account_id,
                                 authoritative.display_name, authoritative.lifecycle,
                                 authoritative.created_at_ms,
                                 authoritative.updated_at_ms,
                                 NULL AS pending_operation_id,
                                 pending.operation_id AS reconciliation_operation_id
                          FROM \(LedgerPowerSyncTable.clients) AS authoritative
                          LEFT JOIN \(LedgerPowerSyncTable.pendingClients) AS pending
                            ON pending.account_id = authoritative.account_id
                           AND pending.id = authoritative.id
                           AND pending.created_by_principal_id = ?
                          WHERE authoritative.account_id = ?
                            AND (SELECT is_active FROM scope)
                          UNION ALL
                          SELECT pending.id, pending.account_id, pending.display_name,
                                 pending.lifecycle, pending.created_at_ms,
                                 pending.updated_at_ms,
                                 pending.operation_id AS pending_operation_id,
                                 NULL AS reconciliation_operation_id
                          FROM \(LedgerPowerSyncTable.pendingClients) AS pending
                          WHERE pending.account_id = ?
                            AND pending.created_by_principal_id = ?
                            AND (
                              NOT (SELECT is_active FROM scope)
                              OR NOT EXISTS (
                                SELECT 1 FROM \(LedgerPowerSyncTable.clients) AS authoritative
                                WHERE authoritative.account_id = pending.account_id
                                  AND authoritative.id = pending.id
                              )
                          )
                        )
                        SELECT scope.is_active,
                               project.id, project.account_id, project.client_id,
                               project.display_name, project.description,
                               CASE
                                 WHEN archive.operation_id IS NOT NULL
                                  AND project.base_revision <= archive.projected_revision
                                 THEN archive.lifecycle ELSE project.lifecycle
                               END AS lifecycle,
                               CASE
                                 WHEN archive.operation_id IS NOT NULL
                                  AND project.base_revision <= archive.projected_revision
                                 THEN archive.projected_revision ELSE project.base_revision
                               END AS revision,
                               project.lifecycle AS base_lifecycle,
                               project.base_revision,
                               project.pending_operation_id,
                               project.reconciliation_operation_id,
                               client.display_name AS client_display_name,
                               client.lifecycle AS client_lifecycle,
                               client.created_at_ms AS client_created_at_ms,
                               client.updated_at_ms AS client_updated_at_ms,
                               client.pending_operation_id AS client_pending_operation_id
                              ,client.reconciliation_operation_id AS client_reconciliation_operation_id,
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
                        FROM selected_projects AS project
                        CROSS JOIN scope
                        JOIN selected_clients AS client
                          ON client.account_id = project.account_id
                         AND client.id = project.client_id
                        LEFT JOIN \(LedgerPowerSyncTable.projectArchiveOverlays) AS archive
                          ON archive.account_id = project.account_id
                         AND archive.project_id = project.id
                        LEFT JOIN \(LedgerPowerSyncTable.localOperations) AS archive_operation
                          ON archive_operation.id = archive.operation_id
                        """,
                        parameters: [
                            request.accountId.rawValue,
                            principalId.rawValue,
                            principalId.rawValue,
                            request.accountId.rawValue,
                            request.projectId.rawValue,
                            request.accountId.rawValue,
                            request.projectId.rawValue,
                            principalId.rawValue,
                            principalId.rawValue,
                            request.accountId.rawValue,
                            request.accountId.rawValue,
                            principalId.rawValue
                        ]
                    ) { cursor in
                        try PowerSyncProjectCoreRow(cursor: cursor)
                    }

                    for try await localRows in rows {
                        let snapshots = try localRows.map {
                            try $0.snapshot(expectedPrincipalId: principalId.rawValue)
                        }
                        let status = database.currentStatus
                        let quality = ClientCoreDetailsPowerSyncQuery.snapshotQuality(
                            hasPendingOperation: localRows.contains { $0.isPending },
                            hasSynced: localRows.first?.scopeIsActive == true
                                && status.hasSynced == true,
                            hasLastSyncedAt: localRows.first?.scopeIsActive == true
                                && status.lastSyncedAt != nil
                        )
                        let local = try ProjectCoreDetailsLocalSnapshot(
                            request: request,
                            rows: snapshots,
                            visibleRowCountBeforeFiltering: snapshots.count,
                            isCompleteForQuery: quality == .ready,
                            quality: quality,
                            localDataVersion: LocalDataVersion(
                                validating: "powersync-spike-\(localRows.map(\.revision).max() ?? 0)"
                            ),
                            asOf: now()
                        )
                        for row in localRows {
                            if let operationId = row.projectReconciliationOperationId {
                                try await PowerSyncOverlayReconciler.reconcileProjectCore(
                                    database: database,
                                    projectId: row.id,
                                    accountId: row.accountId,
                                    operationId: operationId
                                )
                            }
                            if let operationId = row.clientReconciliationOperationId {
                                try await PowerSyncOverlayReconciler.reconcileClient(
                                    database: database,
                                    clientId: row.clientId,
                                    accountId: row.accountId,
                                    operationId: operationId
                                )
                            }
                            if let operationId = row.archiveOperationId {
                                try await PowerSyncOverlayReconciler.reconcileProjectArchive(
                                    database: database,
                                    projectId: row.id,
                                    accountId: row.accountId,
                                    operationId: operationId
                                )
                            }
                        }
                        continuation.yield(try ProjectCoreDetailsUpdate(
                            request: request,
                            state: .snapshot(local)
                        ))
                    }
                    continuation.finish()
                } catch {
                    do {
                        continuation.yield(try ProjectCoreDetailsUpdate(
                            request: request,
                            state: .failed(failure: .retryable, cached: nil)
                        ))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func failedStream<Value: Sendable>(
        _ error: Error
    ) -> AsyncThrowingStream<Value, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }
}

private struct PowerSyncProjectCoreRow: Sendable {
    let scopeIsActive: Bool
    let id: String
    let accountId: String
    let clientId: String
    let displayName: String
    let description: String?
    let lifecycle: String
    let revision: Int64
    let projectPendingOperationId: String?
    let projectReconciliationOperationId: String?
    let clientDisplayName: String
    let clientLifecycle: String
    let clientCreatedAtMilliseconds: Int64
    let clientUpdatedAtMilliseconds: Int64
    let clientPendingOperationId: String?
    let clientReconciliationOperationId: String?
    let baseLifecycle: String
    let baseRevision: Int64
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

    init(cursor: any SqlCursor) throws {
        scopeIsActive = try cursor.getInt64(name: "is_active") == 1
        id = try cursor.getString(name: "id")
        accountId = try cursor.getString(name: "account_id")
        clientId = try cursor.getString(name: "client_id")
        displayName = try cursor.getString(name: "display_name")
        description = try cursor.getStringOptional(name: "description")
        lifecycle = try cursor.getString(name: "lifecycle")
        revision = try cursor.getInt64(name: "revision")
        projectPendingOperationId = try cursor.getStringOptional(
            name: "pending_operation_id"
        )
        projectReconciliationOperationId = try cursor.getStringOptional(
            name: "reconciliation_operation_id"
        )
        clientDisplayName = try cursor.getString(name: "client_display_name")
        clientLifecycle = try cursor.getString(name: "client_lifecycle")
        clientCreatedAtMilliseconds = try cursor.getInt64(name: "client_created_at_ms")
        clientUpdatedAtMilliseconds = try cursor.getInt64(name: "client_updated_at_ms")
        clientPendingOperationId = try cursor.getStringOptional(
            name: "client_pending_operation_id"
        )
        clientReconciliationOperationId = try cursor.getStringOptional(
            name: "client_reconciliation_operation_id"
        )
        baseLifecycle = try cursor.getString(name: "base_lifecycle")
        baseRevision = try cursor.getInt64(name: "base_revision")
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

    func snapshot(expectedPrincipalId: String) throws -> ProjectCoreDetailsSnapshot {
        try validateArchiveOverlay(expectedPrincipalId: expectedPrincipalId)
        guard revision > 0,
              let projectLifecycle = DirectoryLifecycleState(rawValue: lifecycle),
              let parsedClientLifecycle = DirectoryLifecycleState(rawValue: clientLifecycle) else {
            throw ProjectCoreDetailsFailure.invalidEncodedProject
        }
        let accountId = try AccountID(validating: accountId)
        let clientId = try ClientID(validating: clientId)
        let client = try ClientSummary(
            id: clientId,
            accountId: accountId,
            displayName: ClientDisplayName(validating: clientDisplayName),
            lifecycle: parsedClientLifecycle,
            createdAt: Date(
                timeIntervalSince1970: Double(clientCreatedAtMilliseconds) / 1_000
            ),
            updatedAt: Date(
                timeIntervalSince1970: Double(clientUpdatedAtMilliseconds) / 1_000
            )
        )
        let project = try ProjectSummary(
            id: ProjectID(validating: id),
            accountId: accountId,
            clientId: clientId,
            client: client,
            displayName: ProjectDisplayName(validating: displayName),
            description: description,
            lifecycle: projectLifecycle
        )
        return try ProjectCoreDetailsSnapshot(
            project: project,
            locallyObservedRevision: ExpectedProjectRevision(UInt64(revision))
        )
    }

    private func validateArchiveOverlay(expectedPrincipalId: String) throws {
        guard missingAppliedArchiveOverlayCount == 0 else {
            throw ProjectCoreDetailsFailure.invalidEncodedProject
        }
        guard let archiveOperationId else {
            guard archiveOverlayCount == 0 else {
                throw ProjectCoreDetailsFailure.invalidEncodedProject
            }
            return
        }
        guard archiveOverlayCount == 1,
              archiveAccountId == accountId,
              archiveProjectId == id,
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
              archiveOperationSubjectId == id,
              ["queued", "applying", "applied"].contains(archiveOperationState),
              archiveOperationContractVersion == "project-archive-v1",
              archiveOperationCommandType == "archive_project",
              archiveOperationExpectedRevision == archiveExpectedRevision,
              let archiveOperationEnvelopeJSON,
              (try? OperationID(validating: archiveOperationId)) != nil,
              (try? OperationFingerprint(validating: archiveFingerprint)) != nil,
              DirectoryLifecycleState(rawValue: baseLifecycle) != nil,
              baseRevision > 0 else {
            throw ProjectCoreDetailsFailure.invalidEncodedProject
        }
        guard ProjectArchiveOverlayCommandValidator.isValid(
            operationId: archiveOperationId,
            accountId: accountId,
            actorPrincipalId: archiveActorPrincipalId,
            contractVersion: "project-archive-v1",
            projectId: id,
            expectedRevision: expected,
            fingerprint: archiveFingerprint,
            envelopeJSON: archiveOperationEnvelopeJSON
        ) else {
            throw ProjectCoreDetailsFailure.invalidEncodedProject
        }
    }
}
