import Foundation
import LedgerTargetCore
import PowerSync
import Testing
@testable import LedgerTargetPowerSync

@Suite("Client archive PowerSync vertical slice", .serialized)
struct ClientArchivePowerSyncVerticalSliceTests {
    @Test("Identity is generic, account-bound, namespace exact, and preserves Project archive bytes")
    func operationIdentity() async throws {
        let uuid = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        let digest = "820fcd051d436cfe81328997babf666384118e46578dce1afe250c40b3d3f07f"
        let client = try ClientArchiveOperationIdentity.make(accountId: Self.accountId, uuid: uuid)
        let project = try ProjectArchiveOperationIdentity.make(accountId: Self.accountId, uuid: uuid)
        #expect(client.rawValue == "client-archive-\(digest)-11111111-2222-4333-8444-555555555555")
        #expect(project.rawValue == "project-archive-\(digest)-11111111-2222-4333-8444-555555555555")
        #expect(ClientArchiveOperationIdentity.isValid(client, accountId: Self.accountId))
        #expect(!ClientArchiveOperationIdentity.isValid(project, accountId: Self.accountId))
        #expect(!ClientArchiveOperationIdentity.isValid(
            client, accountId: try AccountID(validating: "account-other")
        ))

        let fixture = try ClientArchiveDatabaseFixture()
        let database = try fixture.open()
        try await Self.seed(database)
        let wrong = try ArchiveClientCommand(
            operationId: project,
            draft: Self.draft(revision: 7)
        )
        await #expect(throws: ClientArchivePowerSyncFailure.invalidOperationIdentity) {
            _ = try await Self.store(database).archive(wrong)
        }
        #expect(try await Self.count(LedgerPowerSyncTable.localOperations, database) == 0)
        #expect(try await Self.count(LedgerPowerSyncTable.clientArchiveOverlays, database) == 0)
        try await database.close(deleteDatabase: true)
        fixture.remove()
    }

    @Test("Acceptance is atomic, replayable, restart durable, and shared by every Client projection")
    func acceptanceProjectionRestartAndProjectSetupAdmission() async throws {
        let fixture = try ClientArchiveDatabaseFixture()
        let database = try fixture.open()
        try await Self.seed(database)
        let setup = try Self.projectSetup(operation: "setup-before-archive", project: "project-before")
        let setupStore = ProjectSetupPowerSyncStore(database: database, now: { Self.acceptedAt })
        let setupReceipt = try await setupStore.create(setup)
        let command = try Self.command(id: "offline", revision: 7)

        let receipt = try await Self.store(database).archive(command)
        #expect(receipt.localState == .queued)
        #expect(try await Self.store(database).archive(command) == receipt)
        #expect(try await Self.count(LedgerPowerSyncTable.localOperations, database) == 2)
        #expect(try await Self.count(LedgerPowerSyncTable.clientArchiveOverlays, database) == 1)
        #expect(try await Self.clientAuthority(database) == "active|7|Client Name|principal-owner")
        #expect(try await Self.count(LedgerPowerSyncTable.projects, database) == 1)
        #expect(try await Self.count(LedgerPowerSyncTable.pendingProjects, database) == 1)

        let clientList = try await Self.firstClientList(database)
        #expect(clientList.local.quality == .partial)
        #expect(clientList.local.rows.only?.lifecycle == .archived)
        let clientDetail = try await Self.firstClientDetail(database)
        #expect(clientDetail.local.quality == .partial)
        #expect(clientDetail.row?.client.lifecycle == .archived)
        #expect(clientDetail.row?.locallyObservedRevision == ExpectedClientRevision(8))
        let projectList = try await Self.firstProjectList(database)
        #expect(projectList.local.rows.count == 2)
        #expect(projectList.local.rows.allSatisfy { $0.client.lifecycle == .archived })
        #expect(projectList.local.rows.contains { $0.id.rawValue == "project-before" })

        // Exact replay accepted before archive resolves before effective lifecycle admission.
        #expect(try await setupStore.create(setup) == setupReceipt)
        let afterArchive = try Self.projectSetup(
            operation: "setup-after-archive", project: "project-after"
        )
        await #expect(throws: ProjectSetupFailure.localAcceptanceFailed) {
            _ = try await setupStore.create(afterArchive)
        }
        #expect(try await Self.count(LedgerPowerSyncTable.pendingProjects, database) == 1)

        try await database.close(deleteDatabase: false)
        let bytes = try Data(contentsOf: fixture.databaseURL)
        #expect(!String(decoding: bytes, as: UTF8.self).contains("Client Name"))
        let reopened = try fixture.open()
        #expect((try await Self.firstClientDetail(reopened)).row?.client.lifecycle == .archived)
        #expect(try await Self.store(reopened).archive(command) == receipt)
        try await reopened.close(deleteDatabase: true)
        fixture.remove()
    }

    @Test("Dependency FIFO, transient retention, rejection rollback, and applied readback are exact")
    func dependencyUploadAndReconciliation() async throws {
        let fixture = try ClientArchiveDatabaseFixture()
        let database = try fixture.open()
        try await Self.seed(database)
        let setup = try Self.projectSetup(operation: "setup-dependency", project: "project-dependency")
        _ = try await ProjectSetupPowerSyncStore(database: database, now: { Self.acceptedAt })
            .create(setup)
        let archive = try Self.command(id: "upload", revision: 7)
        _ = try await Self.store(database).archive(archive)

        let order = ClientArchiveApplyOrder()
        let fifo = LedgerPowerSyncUploadConnector(
            credentialProvider: { nil },
            clientCreationApplier: ClientArchiveUnusedClientApplier(),
            projectCreationApplier: ClientArchiveOrderedProjectApplier(order: order),
            clientArchiveApplier: ClientArchiveOrderedApplier(order: order, phase: "applied"),
            now: { Self.updatedAt }
        )
        try await fifo.uploadData(database: database)
        #expect(await order.values == ["create_project"])
        let transient = LedgerPowerSyncUploadConnector(
            credentialProvider: { nil },
            clientCreationApplier: ClientArchiveUnusedClientApplier(),
            clientArchiveApplier: ClientArchiveThrowingApplier(),
            now: { Self.updatedAt }
        )
        await #expect(throws: ClientArchiveInjectedFailure.self) {
            try await transient.uploadData(database: database)
        }
        #expect(try await Self.localState(archive, database) == "queued")
        #expect(try await Self.count(LedgerPowerSyncTable.clientArchiveOverlays, database) == 1)
        try await fifo.uploadData(database: database)
        #expect(await order.values == ["create_project", "archive_client"])
        #expect(try await Self.localState(archive, database) == "applied")
        #expect(try await Self.count(LedgerPowerSyncTable.clientArchiveOverlays, database) == 1)

        // Applied optimism cannot clear on stale authority.
        try await PowerSyncOverlayReconciler.reconcileClientArchive(
            database: database,
            clientId: Self.clientId.rawValue,
            accountId: Self.accountId.rawValue,
            operationId: archive.envelope.operationId.rawValue
        )
        #expect(try await Self.count(LedgerPowerSyncTable.clientArchiveOverlays, database) == 1)
        _ = try await database.execute(
            sql: "UPDATE spike_clients SET lifecycle = 'archived', revision = 8 WHERE id = ?",
            parameters: [Self.clientId.rawValue]
        )
        try await Self.drainCRUD(database)
        try await PowerSyncOverlayReconciler.reconcileClientArchive(
            database: database,
            clientId: Self.clientId.rawValue,
            accountId: Self.accountId.rawValue,
            operationId: archive.envelope.operationId.rawValue
        )
        #expect(try await Self.count(LedgerPowerSyncTable.clientArchiveOverlays, database) == 0)
        #expect(try await Self.count(LedgerPowerSyncTable.projects, database) == 1)
        #expect(try await Self.store(database).archive(archive).localState == .applied)

        // A fresh rejection removes only its exact overlay and reveals underlying active truth.
        _ = try await database.execute(
            sql: "UPDATE spike_clients SET lifecycle = 'active', revision = 9 WHERE id = ?",
            parameters: [Self.clientId.rawValue]
        )
        try await Self.drainCRUD(database)
        let rejected = try Self.command(id: "rejected", revision: 9)
        _ = try await Self.store(database).archive(rejected)
        let rejectConnector = LedgerPowerSyncUploadConnector(
            credentialProvider: { nil },
            clientCreationApplier: ClientArchiveUnusedClientApplier(),
            clientArchiveApplier: ClientArchiveResultApplier(phase: "rejected"),
            now: { Self.updatedAt }
        )
        try await rejectConnector.uploadData(database: database)
        #expect(try await Self.localState(rejected, database) == "rejected")
        #expect(try await Self.count(LedgerPowerSyncTable.clientArchiveOverlays, database) == 0)
        #expect((try await Self.firstClientDetail(database)).row?.client.lifecycle == .active)
        try await database.close(deleteDatabase: true)
        fixture.remove()
    }

    @Test("Malformed linkage and missing optimism fail every shared projection closed")
    func malformedEvidenceFailsClosed() async throws {
        let fixture = try ClientArchiveDatabaseFixture()
        let database = try fixture.open()
        try await Self.seed(database)
        let command = try Self.command(id: "malformed", revision: 7)
        _ = try await Self.store(database).archive(command)
        _ = try await database.execute(
            sql: "UPDATE spike_client_archive_overlays SET fingerprint = ? WHERE operation_id = ?",
            parameters: [String(repeating: "0", count: 64), command.envelope.operationId.rawValue]
        )
        let directoryQuery = Self.query(database)
        var clients = directoryQuery.watchClients(accountId: Self.accountId).makeAsyncIterator()
        await #expect(throws: ClientProjectDirectoryPowerSyncFailure.malformedClientRow) {
            _ = try await clients.next()
        }
        var projects = directoryQuery.watchProjects(accountId: Self.accountId).makeAsyncIterator()
        await #expect(throws: ClientProjectDirectoryPowerSyncFailure.malformedClientRow) {
            _ = try await projects.next()
        }
        guard case .failed = (try await Self.firstClientDetailUpdate(database)).state else {
            Issue.record("Expected Client detail to fail closed")
            await directoryQuery.cancelAndDrainWatches()
            try await database.close(deleteDatabase: true)
            fixture.remove()
            return
        }
        _ = try await database.execute(
            sql: "DELETE FROM spike_client_archive_overlays WHERE operation_id = ?",
            parameters: [command.envelope.operationId.rawValue]
        )
        for state in ["queued", "applying", "applied"] {
            _ = try await database.execute(
                sql: "UPDATE spike_local_operations SET local_state = ? WHERE id = ?",
                parameters: [state, command.envelope.operationId.rawValue]
            )
            var missing = directoryQuery.watchClients(accountId: Self.accountId)
                .makeAsyncIterator()
            await #expect(throws: ClientProjectDirectoryPowerSyncFailure.malformedClientRow) {
                _ = try await missing.next()
            }
            guard case .failed = (try await Self.firstClientDetailUpdate(database)).state else {
                Issue.record("Expected missing \(state) overlay to fail closed")
                await directoryQuery.cancelAndDrainWatches()
                try await database.close(deleteDatabase: true)
                fixture.remove()
                return
            }
        }
        await directoryQuery.cancelAndDrainWatches()
        try await database.close(deleteDatabase: true)
        fixture.remove()
    }

    @Test("Replay validates changed payload, duplicate optimism, revision bounds, and exact terminal evidence")
    func replayCorruptionFailsClosed() async throws {
        let fixture = try ClientArchiveDatabaseFixture()
        let database = try fixture.open()
        try await Self.seed(database)
        let command = try Self.command(id: "replay", revision: 7)
        _ = try await Self.store(database).archive(command)

        let changed = try ArchiveClientCommand(
            operationId: command.envelope.operationId,
            draft: Self.draft(revision: 8)
        )
        await #expect(throws: OperationContractFailure.payloadMismatch(command.envelope.operationId)) {
            _ = try await Self.store(database).archive(changed)
        }
        await #expect(throws: ClientArchiveFailure.revisionPreconditionMismatch) {
            _ = try await Self.store(database).archive(
                try Self.command(id: "max-revision", revision: UInt64.max)
            )
        }

        _ = try await database.execute(sql: """
            INSERT INTO spike_client_archive_overlays (
              id, account_id, actor_principal_id, client_id, operation_id,
              fingerprint, expected_revision, projected_revision, lifecycle,
              accepted_at_ms
            ) SELECT 'duplicate-overlay', account_id, actor_principal_id, client_id,
                     operation_id, fingerprint, expected_revision,
                     projected_revision, lifecycle, accepted_at_ms
              FROM spike_client_archive_overlays WHERE operation_id = ?
            """, parameters: [command.envelope.operationId.rawValue])
        await #expect(throws: ClientArchivePowerSyncFailure.malformedLocalEvidence) {
            _ = try await Self.store(database).archive(command)
        }
        _ = try await database.execute(
            sql: "DELETE FROM spike_client_archive_overlays WHERE id = 'duplicate-overlay'",
            parameters: nil
        )

        let connector = LedgerPowerSyncUploadConnector(
            credentialProvider: { nil },
            clientCreationApplier: ClientArchiveUnusedClientApplier(),
            clientArchiveApplier: ClientArchiveResultApplier(phase: "applied"),
            now: { Self.updatedAt }
        )
        try await connector.uploadData(database: database)
        #expect(try await Self.store(database).archive(command).localState == .applied)
        let requestHash = LedgerPowerSyncUploadConnector.clientArchiveRequestSHA256(
            try Self.uploadRequest(command)
        )
        let corruptions: [(String, any Sendable, any Sendable)] = [
            ("terminal_envelope_sha256", String(repeating: "0", count: 64), command.fingerprint.sha256),
            ("terminal_request_sha256", String(repeating: "f", count: 64), requestHash),
            ("terminal_server_received_at_ms", Int64(-1), Int64(Self.capturedAt.timeIntervalSince1970 * 1_000) + 1_000),
            ("terminal_completed_at_ms", Int64(-1), Int64(Self.capturedAt.timeIntervalSince1970 * 1_000) + 2_000)
        ]
        for (column, invalid, restored) in corruptions {
            _ = try await database.execute(
                sql: "UPDATE spike_local_operations SET \(column) = ? WHERE id = ?",
                parameters: [invalid, command.envelope.operationId.rawValue]
            )
            await #expect(throws: ClientArchivePowerSyncFailure.malformedLocalEvidence) {
                _ = try await Self.store(database).archive(command)
            }
            _ = try await database.execute(
                sql: "UPDATE spike_local_operations SET \(column) = ? WHERE id = ?",
                parameters: [restored, command.envelope.operationId.rawValue]
            )
        }
        for terminalState in ["superseded", "resolved"] {
            _ = try await database.execute(
                sql: """
                UPDATE spike_local_operations
                SET local_state = ?, terminal_phase = NULL,
                    terminal_result_code = NULL, terminal_error_code = NULL,
                    terminal_envelope_sha256 = NULL, terminal_request_sha256 = NULL,
                    terminal_server_received_at_ms = NULL, terminal_completed_at_ms = NULL
                WHERE id = ?
                """,
                parameters: [terminalState, command.envelope.operationId.rawValue]
            )
            await #expect(throws: ClientArchivePowerSyncFailure.malformedLocalEvidence) {
                _ = try await Self.store(database).archive(command)
            }
        }
        try await database.close(deleteDatabase: true)
        fixture.remove()
    }

    @Test("Restarted replay requires byte-identical command, operation timing, and overlay acceptance evidence")
    func restartedReplayRequiresEveryDurableRecord() async throws {
        let fixture = try ClientArchiveDatabaseFixture()
        let database = try fixture.open()
        try await Self.seed(database)
        let command = try Self.command(id: "restart-corruption", revision: 7)
        _ = try await Self.store(database).archive(command)
        try await database.close(deleteDatabase: false)

        let reopened = try fixture.open()
        #expect(try await Self.store(reopened).archive(command).localState == .queued)
        let acceptedAt = Int64(Self.acceptedAt.timeIntervalSince1970 * 1_000)
        let capturedAt = Int64(Self.capturedAt.timeIntervalSince1970 * 1_000)
        _ = try await reopened.execute(
            sql: "UPDATE spike_client_archive_overlays SET accepted_at_ms = ? WHERE operation_id = ?",
            parameters: [acceptedAt + 1, command.envelope.operationId.rawValue]
        )
        await #expect(throws: ClientArchivePowerSyncFailure.malformedLocalEvidence) {
            _ = try await Self.store(reopened).archive(command)
        }
        _ = try await reopened.execute(
            sql: "UPDATE spike_client_archive_overlays SET accepted_at_ms = ? WHERE operation_id = ?",
            parameters: [acceptedAt, command.envelope.operationId.rawValue]
        )

        _ = try await reopened.execute(sql: """
            UPDATE ps_crud
            SET data = json_set(data, '$.data.fingerprint', ?)
            WHERE json_extract(data, '$.id') = ?
              AND json_extract(data, '$.type') = ?
            """, parameters: [
                String(repeating: "0", count: 64),
                command.envelope.operationId.rawValue,
                LedgerPowerSyncTable.clientArchiveCommands
            ])
        await #expect(throws: ClientArchivePowerSyncFailure.malformedLocalEvidence) {
            _ = try await Self.store(reopened).archive(command)
        }
        _ = try await reopened.execute(sql: """
            UPDATE ps_crud
            SET data = json_set(data, '$.data.fingerprint', ?)
            WHERE json_extract(data, '$.id') = ?
              AND json_extract(data, '$.type') = ?
            """, parameters: [
                command.fingerprint.sha256,
                command.envelope.operationId.rawValue,
                LedgerPowerSyncTable.clientArchiveCommands
            ])

        for invalidCapturedAtJSON in [
            "\(capturedAt).0",
            "\(capturedAt).5",
            "9223372036854775808",
            "true"
        ] {
            _ = try await reopened.execute(sql: """
                UPDATE ps_crud
                SET data = json_set(data, '$.data.client_created_at_ms', json(?))
                WHERE json_extract(data, '$.id') = ?
                  AND json_extract(data, '$.type') = ?
                """, parameters: [
                    invalidCapturedAtJSON,
                    command.envelope.operationId.rawValue,
                    LedgerPowerSyncTable.clientArchiveCommands
                ])
            await #expect(throws: ClientArchivePowerSyncFailure.malformedLocalEvidence) {
                _ = try await Self.store(reopened).archive(command)
            }
        }
        _ = try await reopened.execute(sql: """
            UPDATE ps_crud
            SET data = json_set(data, '$.data.client_created_at_ms', ?)
            WHERE json_extract(data, '$.id') = ?
              AND json_extract(data, '$.type') = ?
            """, parameters: [
                capturedAt,
                command.envelope.operationId.rawValue,
                LedgerPowerSyncTable.clientArchiveCommands
            ])

        _ = try await reopened.execute(
            sql: "UPDATE spike_local_operations SET updated_at_ms = accepted_at_ms - 1 WHERE id = ?",
            parameters: [command.envelope.operationId.rawValue]
        )
        await #expect(throws: ClientArchivePowerSyncFailure.malformedLocalEvidence) {
            _ = try await Self.store(reopened).archive(command)
        }
        _ = try await reopened.execute(
            sql: "UPDATE spike_local_operations SET updated_at_ms = accepted_at_ms WHERE id = ?",
            parameters: [command.envelope.operationId.rawValue]
        )
        _ = try await reopened.execute(sql: """
            DELETE FROM ps_crud
            WHERE json_extract(data, '$.id') = ?
              AND json_extract(data, '$.type') = ?
            """, parameters: [
                command.envelope.operationId.rawValue,
                LedgerPowerSyncTable.clientArchiveCommands
            ])
        await #expect(throws: ClientArchivePowerSyncFailure.malformedLocalEvidence) {
            _ = try await Self.store(reopened).archive(command)
        }
        try await reopened.close(deleteDatabase: true)
        fixture.remove()
    }

    @Test("Project Setup rejects missing archive optimism and every Client projection binds its actor")
    func projectSetupAndProjectionActorFailClosed() async throws {
        let fixture = try ClientArchiveDatabaseFixture()
        let database = try fixture.open()
        try await Self.seed(database)
        let command = try Self.command(id: "fail-closed", revision: 7)
        _ = try await Self.store(database).archive(command)
        _ = try await database.execute(
            sql: "DELETE FROM spike_client_archive_overlays WHERE operation_id = ?",
            parameters: [command.envelope.operationId.rawValue]
        )
        _ = try await database.execute(
            sql: "DELETE FROM spike_clients WHERE account_id = ? AND id = ?",
            parameters: [Self.accountId.rawValue, Self.clientId.rawValue]
        )
        try await Self.drainCRUD(database)
        await #expect(throws: ProjectSetupFailure.localAcceptanceFailed) {
            _ = try await ProjectSetupPowerSyncStore(database: database).create(
                try Self.projectSetup(operation: "setup-missing-overlay", project: "project-missing-overlay")
            )
        }
        try await database.close(deleteDatabase: true)
        fixture.remove()

        let actorFixture = try ClientArchiveDatabaseFixture()
        let actorDatabase = try actorFixture.open()
        try await Self.seed(actorDatabase)
        let original = try Self.command(id: "foreign-actor", revision: 7)
        _ = try await Self.store(actorDatabase).archive(original)
        let foreignPrincipal = try PrincipalID(validating: "principal-foreign")
        let foreign = try ArchiveClientCommand(
            operationId: original.envelope.operationId,
            draft: ClientArchiveDraft(
                accountId: Self.accountId,
                actorPrincipalId: foreignPrincipal,
                operationContractVersion: OperationContractVersion(validating: "client-archive-v1"),
                clientId: Self.clientId,
                expectedRevision: ExpectedClientRevision(7),
                capturedAt: Self.capturedAt
            )
        )
        let foreignEnvelope = String(
            decoding: try OperationContractCodec.encode(foreign.envelope), as: UTF8.self
        )
        _ = try await actorDatabase.execute(sql: """
            UPDATE spike_local_operations
            SET actor_principal_id = ?, fingerprint = ?, command_envelope_json = ?
            WHERE id = ?
            """, parameters: [
                foreignPrincipal.rawValue, foreign.fingerprint.sha256, foreignEnvelope,
                original.envelope.operationId.rawValue
            ])
        _ = try await actorDatabase.execute(sql: """
            UPDATE spike_client_archive_overlays
            SET actor_principal_id = ?, fingerprint = ? WHERE operation_id = ?
            """, parameters: [
                foreignPrincipal.rawValue, foreign.fingerprint.sha256,
                original.envelope.operationId.rawValue
            ])
        let directoryQuery = Self.query(actorDatabase)
        var clients = directoryQuery.watchClients(accountId: Self.accountId)
            .makeAsyncIterator()
        await #expect(throws: ClientProjectDirectoryPowerSyncFailure.malformedClientRow) {
            _ = try await clients.next()
        }
        var projects = directoryQuery.watchProjects(accountId: Self.accountId)
            .makeAsyncIterator()
        await #expect(throws: ClientProjectDirectoryPowerSyncFailure.malformedClientRow) {
            _ = try await projects.next()
        }
        guard case .failed = (try await Self.firstClientDetailUpdate(actorDatabase)).state else {
            Issue.record("Expected foreign archive actor to fail Client detail closed")
            await directoryQuery.cancelAndDrainWatches()
            try await actorDatabase.close(deleteDatabase: true)
            actorFixture.remove()
            return
        }
        await directoryQuery.cancelAndDrainWatches()
        try await actorDatabase.close(deleteDatabase: true)
        actorFixture.remove()
    }

    @Test("Project Setup distinguishes reconciled applied archive evidence from missing optimism")
    func projectSetupAppliedArchiveReadbackMatrix() async throws {
        let fixture = try ClientArchiveDatabaseFixture()
        let database = try fixture.open()
        try await Self.seed(database)
        let command = try Self.command(id: "setup-readback", revision: 7)
        _ = try await Self.store(database).archive(command)
        let connector = LedgerPowerSyncUploadConnector(
            credentialProvider: { nil },
            clientCreationApplier: ClientArchiveUnusedClientApplier(),
            clientArchiveApplier: ClientArchiveResultApplier(phase: "applied"),
            now: { Self.updatedAt }
        )
        try await connector.uploadData(database: database)
        _ = try await database.execute(
            sql: "DELETE FROM spike_client_archive_overlays WHERE operation_id = ?",
            parameters: [command.envelope.operationId.rawValue]
        )

        // Stale active authority cannot justify a missing applied overlay.
        await #expect(throws: ProjectSetupFailure.localAcceptanceFailed) {
            _ = try await ProjectSetupPowerSyncStore(database: database).create(
                try Self.projectSetup(operation: "setup-stale-readback", project: "project-stale-readback")
            )
        }
        // Equal projected revision only qualifies when authority is archived.
        _ = try await database.execute(
            sql: "UPDATE spike_clients SET lifecycle = 'active', revision = 8 WHERE id = ?",
            parameters: [Self.clientId.rawValue]
        )
        await #expect(throws: ProjectSetupFailure.localAcceptanceFailed) {
            _ = try await ProjectSetupPowerSyncStore(database: database).create(
                try Self.projectSetup(operation: "setup-equal-active", project: "project-equal-active")
            )
        }
        // Archived projected readback legitimately explains overlay removal, but
        // remains ineligible for a new Project because its lifecycle is inactive.
        _ = try await database.execute(
            sql: "UPDATE spike_clients SET lifecycle = 'archived' WHERE id = ?",
            parameters: [Self.clientId.rawValue]
        )
        await #expect(throws: ProjectSetupFailure.localAcceptanceFailed) {
            _ = try await ProjectSetupPowerSyncStore(database: database).create(
                try Self.projectSetup(operation: "setup-archived-readback", project: "project-archived-readback")
            )
        }
        // Any newer authoritative revision supersedes the archived result; an
        // active newer Client is selectable consistently with directory truth.
        _ = try await database.execute(
            sql: "UPDATE spike_clients SET lifecycle = 'active', revision = 9 WHERE id = ?",
            parameters: [Self.clientId.rawValue]
        )
        let accepted = try await ProjectSetupPowerSyncStore(database: database).create(
            try Self.projectSetup(operation: "setup-newer-active", project: "project-newer-active")
        )
        #expect(accepted.localState == .queued)

        // Removing that qualifying authority makes the missing applied overlay
        // fail closed again even though absent authority is normally tolerated.
        _ = try await database.execute(
            sql: "DELETE FROM spike_clients WHERE account_id = ? AND id = ?",
            parameters: [Self.accountId.rawValue, Self.clientId.rawValue]
        )
        await #expect(throws: ProjectSetupFailure.localAcceptanceFailed) {
            _ = try await ProjectSetupPowerSyncStore(database: database).create(
                try Self.projectSetup(operation: "setup-missing-readback", project: "project-missing-readback")
            )
        }
        try await database.close(deleteDatabase: true)
        fixture.remove()
    }

    @Test("Negative server timestamps cannot complete CRUD and operation watch decodes terminal evidence")
    func timestampAndOperationWatch() async throws {
        let fixture = try ClientArchiveDatabaseFixture()
        let database = try fixture.open()
        try await Self.seed(database)
        let command = try Self.command(id: "negative-time", revision: 7)
        _ = try await Self.store(database).archive(command)
        let invalidConnector = LedgerPowerSyncUploadConnector(
            credentialProvider: { nil },
            clientCreationApplier: ClientArchiveUnusedClientApplier(),
            clientArchiveApplier: ClientArchiveNegativeTimestampApplier(),
            now: { Self.updatedAt }
        )
        await #expect(throws: LedgerPowerSyncUploadFailure.invalidServerResult) {
            try await invalidConnector.uploadData(database: database)
        }
        #expect(try await Self.localState(command, database) == "queued")
        #expect(try await database.getNextCrudTransaction() != nil)

        let validConnector = LedgerPowerSyncUploadConnector(
            credentialProvider: { nil },
            clientCreationApplier: ClientArchiveUnusedClientApplier(),
            clientArchiveApplier: ClientArchiveResultApplier(phase: "applied"),
            now: { Self.updatedAt }
        )
        try await validConnector.uploadData(database: database)
        let snapshot = try await Self.firstOperation(command, database)
        #expect(snapshot.operationId == command.envelope.operationId)
        #expect(snapshot.fingerprint == command.fingerprint)
        guard case .applied(let result) = snapshot.state else {
            Issue.record("Expected applied operation watch evidence")
            try await database.close(deleteDatabase: true)
            fixture.remove()
            return
        }
        #expect(result.resultCode.rawValue == "client_archived")
        #expect(result.affectedRevisions.only?.revision == 8)
        let request = try Self.uploadRequest(command)
        let terminal = ClientArchiveResultApplier.result(request, phase: "applied")
        _ = try await database.execute(sql: """
            INSERT INTO spike_operation_results (
              id, account_id, actor_principal_id, command_type,
              contract_version, command_fingerprint, envelope_sha256,
              request_sha256, subject_id, phase, result_code, error_code,
              client_created_at_ms, server_received_at_ms, completed_at_ms
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, parameters: [
                terminal.operationId, terminal.accountId, terminal.actorPrincipalId,
                terminal.commandType, terminal.contractVersion,
                terminal.commandFingerprint, terminal.envelopeSHA256,
                terminal.requestSHA256, terminal.subjectId, terminal.phase,
                terminal.resultCode, terminal.errorCode,
                terminal.clientCreatedAtMilliseconds,
                terminal.serverReceivedAtMilliseconds,
                terminal.completedAtMilliseconds
            ])
        #expect(try await Self.firstOperation(command, database) == snapshot)
        _ = try await database.execute(
            sql: "UPDATE spike_operation_results SET actor_principal_id = ? WHERE id = ?",
            parameters: ["principal-foreign", command.envelope.operationId.rawValue]
        )
        let malformedStore = Self.store(database)
        var malformed = malformedStore.watchOperation(command.envelope.operationId)
            .makeAsyncIterator()
        await #expect(throws: ClientArchivePowerSyncFailure.malformedLocalEvidence) {
            _ = try await malformed.next()
        }
        await malformedStore.cancelAndDrainWatches()
        try await database.close(deleteDatabase: true)
        fixture.remove()
    }

    @Test("Terminally rejected Client and Project creation dependencies unblock archive disposition")
    func terminalDependencyRejectionsUnblock() async throws {
        let clientFixture = try ClientArchiveDatabaseFixture()
        let clientDatabase = try clientFixture.open()
        let creation = try CreateClientCommand(
            operationId: OperationID(validating: "client-create-before-archive"),
            draft: ClientCreationDraft(
                accountId: Self.accountId,
                actorPrincipalId: Self.principalId,
                operationContractVersion: OperationContractVersion(validating: "client-create-v1"),
                clientId: Self.clientId,
                displayName: ClientDisplayName(validating: "Pending Client"),
                capturedAt: Self.capturedAt
            )
        )
        _ = try await ClientCreationPowerSyncStore(database: clientDatabase).create(creation)
        let archive = try Self.command(id: "client-dependency-rejected", revision: 1)
        _ = try await Self.store(clientDatabase).archive(archive)
        let clientOrder = ClientArchiveApplyOrder()
        let clientConnector = LedgerPowerSyncUploadConnector(
            credentialProvider: { nil },
            clientCreationApplier: ClientArchiveRejectingClientCreationApplier(order: clientOrder),
            clientArchiveApplier: ClientArchiveOrderedApplier(
                order: clientOrder, phase: "rejected"
            ),
            now: { Self.updatedAt }
        )
        try await clientConnector.uploadData(database: clientDatabase)
        #expect(await clientOrder.values == ["create_client_rejected"])
        try await clientConnector.uploadData(database: clientDatabase)
        #expect(await clientOrder.values == ["create_client_rejected", "archive_client"])
        #expect(try await Self.localState(archive, clientDatabase) == "rejected")
        #expect(try await clientDatabase.getNextCrudTransaction() == nil)
        try await clientDatabase.close(deleteDatabase: true)
        clientFixture.remove()

        let projectFixture = try ClientArchiveDatabaseFixture()
        let projectDatabase = try projectFixture.open()
        try await Self.seed(projectDatabase)
        let setup = try Self.projectSetup(
            operation: "setup-rejected-dependency", project: "project-rejected-dependency"
        )
        _ = try await ProjectSetupPowerSyncStore(database: projectDatabase).create(setup)
        let afterProject = try Self.command(id: "project-dependency-rejected", revision: 7)
        _ = try await Self.store(projectDatabase).archive(afterProject)
        let projectOrder = ClientArchiveApplyOrder()
        let projectConnector = LedgerPowerSyncUploadConnector(
            credentialProvider: { nil },
            clientCreationApplier: ClientArchiveUnusedClientApplier(),
            projectCreationApplier: ClientArchiveRejectingProjectApplier(order: projectOrder),
            clientArchiveApplier: ClientArchiveOrderedApplier(
                order: projectOrder, phase: "applied"
            ),
            now: { Self.updatedAt }
        )
        try await projectConnector.uploadData(database: projectDatabase)
        #expect(await projectOrder.values == ["create_project_rejected"])
        try await projectConnector.uploadData(database: projectDatabase)
        #expect(await projectOrder.values == ["create_project_rejected", "archive_client"])
        #expect(try await Self.localState(afterProject, projectDatabase) == "applied")
        #expect(try await projectDatabase.getNextCrudTransaction() == nil)
        try await projectDatabase.close(deleteDatabase: true)
        projectFixture.remove()
    }

    @Test("Client archive RPC preserves UInt64 text, user credentials, and exact result linkage")
    func rpcBoundary() async throws {
        let command = try Self.command(id: "rpc", revision: UInt64(Int64.max) - 1)
        let request = try Self.uploadRequest(command)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ClientArchiveRecordingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            ClientArchiveRecordingURLProtocol.handler = nil
        }
        ClientArchiveRecordingURLProtocol.handler = { urlRequest in
            #expect(urlRequest.url?.path == "/rest/v1/rpc/spike_archive_client")
            #expect(urlRequest.value(forHTTPHeaderField: "apikey") == "publishable-key")
            #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == "Bearer user-token")
            let body = try clientArchiveRequestBody(urlRequest)
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(json["p_expected_revision"] as? String == "9223372036854775806")
            #expect(json["p_client_captured_at"] as? String != nil)
            let response = try #require(HTTPURLResponse(
                url: urlRequest.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return (
                response,
                try JSONEncoder().encode(
                    ClientArchiveResultApplier.result(request, phase: "applied")
                )
            )
        }
        let rpc = try SupabaseClientArchiveRPC(
            supabaseURL: URL(string: "https://target.invalid")!,
            publishableKey: "publishable-key",
            accessTokenProvider: { "user-token" },
            session: session
        )
        #expect(try await rpc.apply(request).resultCode == "client_archived")

        ClientArchiveRecordingURLProtocol.handler = { urlRequest in
            let bytes = try JSONEncoder().encode(
                ClientArchiveResultApplier.result(request, phase: "rejected")
            )
            var json = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            json["error_code"] = "client_archive_client_missing"
            let response = try #require(HTTPURLResponse(
                url: urlRequest.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return (response, try JSONSerialization.data(withJSONObject: json))
        }
        await #expect(throws: SupabaseClientArchiveRPCFailure.resultMismatch) {
            _ = try await rpc.apply(request)
        }
        #expect(throws: SupabaseClientArchiveRPCFailure.serviceRoleCredentialRefused) {
            _ = try SupabaseClientArchiveRPC(
                supabaseURL: URL(string: "https://target.invalid")!,
                publishableKey: "sb_secret_forbidden",
                accessTokenProvider: { "unused" }
            )
        }
    }

    @Test("Runtime close drains Client archive acceptance and observation before closing")
    func runtimeCloseDrainage() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("client-archive-runtime-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = try Self.runtimeEnvironment()
        let archiveGate = ClientArchiveAsyncGate()
        let streamEntered = ClientArchiveEntryCounter()
        let closeCompleted = ClientArchiveFlag()
        var dependencies = LedgerPowerSyncLocalBootstrapDependencies.live
        dependencies.loadDatabaseKey = { _, _ in
            try LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "2a", count: 32))
        }
        dependencies.loadMediaKeyBytes = { _, _ in Data(repeating: 0x4b, count: 32) }
        dependencies.createDirectory = {
            try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        }
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            try await Self.seed(database)
        }
        dependencies.finiteOperationCheckpoint = { operation in
            if operation == .archiveClient { await archiveGate.wait() }
        }
        dependencies.streamOperationCheckpoint = { operation in
            if operation == .clientArchiveOperation {
                await streamEntered.enter()
                try await Task.sleep(for: .seconds(30))
            }
        }
        dependencies.now = { Self.acceptedAt }
        let runtime = try await LedgerPowerSyncLocalBootstrap.open(
            validatedEnvironment: environment,
            principalId: Self.principalId,
            accountId: Self.accountId,
            applicationSupportDirectory: root,
            dependencies: dependencies
        )
        let command = try Self.command(id: "runtime-close", revision: 7)
        let archiveTask = Task { try await runtime.archive(command) }
        await archiveGate.waitUntilEntered()
        let consumer = Task {
            do {
                var iterator = runtime.watchClientArchiveOperation(
                    command.envelope.operationId
                ).makeAsyncIterator()
                _ = try await iterator.next()
            } catch {
                // Close cancellation is the expected terminal result.
            }
        }
        await streamEntered.waitUntilEntered()
        let close = Task {
            try await runtime.close()
            await closeCompleted.set()
        }
        try await Task.sleep(for: .milliseconds(30))
        #expect(!(await closeCompleted.value))
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.archive(command)
        }
        await archiveGate.release()
        #expect(try await archiveTask.value.localState == .queued)
        try await close.value
        await consumer.value
        #expect(await closeCompleted.value)
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.archive(command)
        }
        var closed = runtime.watchClientArchiveOperation(command.envelope.operationId)
            .makeAsyncIterator()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await closed.next()
        }
    }

    @Test("Client archive store shutdown drains active operation watches")
    func storeShutdownDrainsOperationWatches() async throws {
        let fixture = try ClientArchiveDatabaseFixture()
        let database = try fixture.open()
        try await Self.seed(database)
        let command = try Self.command(id: "store-drain", revision: 7)
        let store = Self.store(database)
        _ = try await store.archive(command)

        var iterator = store.watchOperation(command.envelope.operationId).makeAsyncIterator()
        #expect(try await iterator.next()?.operationId == command.envelope.operationId)
        await store.cancelAndDrainWatches()
        do {
            let value = try await iterator.next()
            #expect(value == nil)
        } catch is CancellationError {
            // Cancellation is also a valid terminal signal for an admitted watch.
        }
        var refused = store.watchOperation(command.envelope.operationId).makeAsyncIterator()
        #expect(try await refused.next() == nil)

        try await database.close(deleteDatabase: true)
        fixture.remove()
    }

    private static let accountId = try! AccountID(validating: "account-primary")
    private static let principalId = try! PrincipalID(validating: "principal-owner")
    private static let clientId = try! ClientID(validating: "client-main")
    private static let capturedAt = Date(timeIntervalSince1970: 1_788_523_200)
    private static let acceptedAt = Date(timeIntervalSince1970: 1_788_523_201)
    private static let updatedAt = Date(timeIntervalSince1970: 1_788_523_202)

    private static func command(id: String, revision: UInt64) throws -> ArchiveClientCommand {
        let uuids = [
            "offline": "00000000-0000-4000-8000-000000000001",
            "upload": "00000000-0000-4000-8000-000000000002",
            "rejected": "00000000-0000-4000-8000-000000000003",
            "malformed": "00000000-0000-4000-8000-000000000004",
            "replay": "00000000-0000-4000-8000-000000000005",
            "max-revision": "00000000-0000-4000-8000-000000000006",
            "fail-closed": "00000000-0000-4000-8000-000000000007",
            "foreign-actor": "00000000-0000-4000-8000-000000000008",
            "negative-time": "00000000-0000-4000-8000-000000000009",
            "client-dependency-rejected": "00000000-0000-4000-8000-00000000000a",
            "project-dependency-rejected": "00000000-0000-4000-8000-00000000000b",
            "rpc": "00000000-0000-4000-8000-00000000000c",
            "runtime-close": "00000000-0000-4000-8000-00000000000d",
            "setup-readback": "00000000-0000-4000-8000-00000000000e",
            "restart-corruption": "00000000-0000-4000-8000-00000000000f",
            "store-drain": "00000000-0000-4000-8000-000000000010"
        ]
        return try ArchiveClientCommand(
            operationId: ClientArchiveOperationIdentity.make(
                accountId: accountId,
                uuid: try #require(uuids[id].flatMap(UUID.init(uuidString:)))
            ),
            draft: draft(revision: revision)
        )
    }

    private static func draft(revision: UInt64) throws -> ClientArchiveDraft {
        try ClientArchiveDraft(
            accountId: accountId,
            actorPrincipalId: principalId,
            operationContractVersion: OperationContractVersion(validating: "client-archive-v1"),
            clientId: clientId,
            expectedRevision: ExpectedClientRevision(revision),
            capturedAt: capturedAt
        )
    }

    private static func runtimeEnvironment() throws -> ValidatedLedgerEnvironment {
        let versions = LedgerContractVersions(schema: "1", query: "1", operation: "1", sync: "1")
        let resources = Dictionary(uniqueKeysWithValues: LedgerTargetComponent.allCases.map {
            ($0, "client-archive-runtime-\($0.rawValue)")
        })
        let manifest = LedgerEnvironmentManifest(
            environment: .targetLocal,
            buildProfile: .targetLocalDevelopment,
            bundleIdentifier: "apps.nine4.ledger.client-archive-runtime-tests",
            displayName: "Ledger Client Archive Runtime Tests",
            localDataNamespacePrefix: "apps.nine4.ledger.client-archive-runtime-tests",
            contractVersions: versions,
            resources: LedgerTargetComponent.allCases.map {
                LedgerEnvironmentResource(
                    component: $0,
                    environment: .targetLocal,
                    publicIdentifier: resources[$0]!
                )
            }
        )
        return try LedgerEnvironmentValidator.validate(
            manifest,
            policy: LedgerEnvironmentPolicy(
                expectedEnvironment: .targetLocal,
                expectedBuildProfile: .targetLocalDevelopment,
                expectedBundleIdentifier: manifest.bundleIdentifier,
                expectedContractVersions: versions,
                allowedResourceIdentifiers: resources.mapValues { [$0] },
                forbiddenResourceIdentifiers: [],
                forbiddenBundleIdentifiers: []
            )
        )
    }

    private static func projectSetup(operation: String, project: String) throws -> CreateProjectCommand {
        try CreateProjectCommand(
            operationId: OperationID(validating: operation),
            draft: ProjectSetupDraft(
                accountId: accountId,
                actorPrincipalId: principalId,
                operationContractVersion: OperationContractVersion(validating: "project-create-v1"),
                projectId: ProjectID(validating: project),
                clientSelection: ProjectClientSelectionInput(existing: clientId),
                displayName: ProjectDisplayName(validating: "Project \(project)"),
                description: "Preserved history",
                categoryAllocations: [],
                capturedAt: capturedAt
            )
        )
    }

    private static func store(_ database: any PowerSyncDatabaseProtocol) -> ClientArchivePowerSyncStore {
        ClientArchivePowerSyncStore(
            database: database, accountId: accountId, principalId: principalId,
            now: { acceptedAt }
        )
    }

    private static func uploadRequest(
        _ command: ArchiveClientCommand
    ) throws -> ClientArchiveUploadRequest {
        ClientArchiveUploadRequest(
            operationId: command.envelope.operationId.rawValue,
            accountId: command.envelope.accountId.rawValue,
            actorPrincipalId: command.envelope.actorPrincipalId.rawValue,
            contractVersion: command.envelope.contractVersion.rawValue,
            clientCreatedAtMilliseconds: Int64(
                command.envelope.clientCreatedAt.timeIntervalSince1970 * 1_000
            ),
            clientId: command.draft.clientId.rawValue,
            expectedRevision: String(command.draft.expectedRevision.rawValue),
            fingerprint: command.fingerprint.sha256,
            envelopeJSON: String(
                decoding: try OperationContractCodec.encode(command.envelope), as: UTF8.self
            )
        )
    }

    private static func firstOperation(
        _ command: ArchiveClientCommand,
        _ database: any PowerSyncDatabaseProtocol
    ) async throws -> OperationSnapshot {
        let archiveStore = store(database)
        var iterator = archiveStore.watchOperation(command.envelope.operationId)
            .makeAsyncIterator()
        do {
            let snapshot = try await iterator.next()
            await archiveStore.cancelAndDrainWatches()
            return try #require(snapshot)
        } catch {
            await archiveStore.cancelAndDrainWatches()
            throw error
        }
    }

    private static func query(_ database: any PowerSyncDatabaseProtocol) -> ClientProjectDirectoryPowerSyncQuery {
        ClientProjectDirectoryPowerSyncQuery(
            database: database, principalId: principalId, accountId: accountId,
            now: { updatedAt }
        )
    }

    private static func seed(_ database: any PowerSyncDatabaseProtocol) async throws {
        let timestamp = Int64(capturedAt.timeIntervalSince1970 * 1_000)
        _ = try await database.execute(sql: """
            INSERT INTO spike_account_memberships (
              id, account_id, principal_id, role, state, can_manage_clients,
              can_manage_projects, can_manage_project_budgets, financial_access
            ) VALUES ('membership-owner', ?, ?, 'owner', 'active', 1, 1, 1, 'full')
            """, parameters: [accountId.rawValue, principalId.rawValue])
        _ = try await database.execute(sql: """
            INSERT INTO spike_clients (
              id, account_id, display_name, lifecycle, revision,
              created_at_ms, updated_at_ms, created_by_principal_id
            ) VALUES (?, ?, 'Client Name', 'active', 7, ?, ?, ?)
            """, parameters: [clientId.rawValue, accountId.rawValue, timestamp, timestamp, principalId.rawValue])
        _ = try await database.execute(sql: """
            INSERT INTO spike_projects (
              id, account_id, client_id, display_name, description, lifecycle,
              revision, created_at_ms, updated_at_ms, created_by_principal_id
            ) VALUES ('project-existing', ?, ?, 'Existing Project', 'Preserved history',
                      'active', 3, ?, ?, ?)
            """, parameters: [accountId.rawValue, clientId.rawValue, timestamp, timestamp, principalId.rawValue])
        try await drainCRUD(database)
    }

    private static func firstClientList(_ database: any PowerSyncDatabaseProtocol) async throws -> ClientListSnapshot {
        let directoryQuery = query(database)
        var iterator = directoryQuery.watchClients(accountId: accountId).makeAsyncIterator()
        do {
            let snapshot = try #require(try await iterator.next())
            await directoryQuery.cancelAndDrainWatches()
            return snapshot
        } catch {
            await directoryQuery.cancelAndDrainWatches()
            throw error
        }
    }

    private static func firstProjectList(_ database: any PowerSyncDatabaseProtocol) async throws -> ProjectListSnapshot {
        let directoryQuery = query(database)
        var iterator = directoryQuery.watchProjects(accountId: accountId).makeAsyncIterator()
        do {
            let snapshot = try #require(try await iterator.next())
            await directoryQuery.cancelAndDrainWatches()
            return snapshot
        } catch {
            await directoryQuery.cancelAndDrainWatches()
            throw error
        }
    }

    private static func firstClientDetailUpdate(_ database: any PowerSyncDatabaseProtocol) async throws -> ClientCoreDetailsUpdate {
        let request = try ClientCoreDetailsRequest(accountId: accountId, clientId: clientId)
        let query = ClientCoreDetailsPowerSyncQuery(
            database: database, principalId: principalId, accountId: accountId,
            now: { updatedAt }
        )
        var iterator = query.watchClientCoreDetails(request).makeAsyncIterator()
        do {
            _ = try await iterator.next()
            let update = try await iterator.next()
            await query.cancelAndDrainWatches()
            return try #require(update)
        } catch {
            await query.cancelAndDrainWatches()
            throw error
        }
    }

    private static func firstClientDetail(_ database: any PowerSyncDatabaseProtocol) async throws -> ClientCoreDetailsLocalSnapshot {
        let update = try await firstClientDetailUpdate(database)
        guard case .snapshot(let snapshot) = update.state else { throw ClientArchiveInjectedFailure() }
        return snapshot
    }

    private static func count(_ table: String, _ database: any PowerSyncDatabaseProtocol) async throws -> Int64 {
        try await database.get("SELECT count(*) FROM \(table)") { try $0.getInt64(index: 0) }
    }

    private static func clientAuthority(_ database: any PowerSyncDatabaseProtocol) async throws -> String {
        try await database.get(
            sql: "SELECT lifecycle || '|' || revision || '|' || display_name || '|' || created_by_principal_id FROM spike_clients WHERE id = ?",
            parameters: [clientId.rawValue]
        ) { try $0.getString(index: 0) }
    }

    private static func localState(_ command: ArchiveClientCommand, _ database: any PowerSyncDatabaseProtocol) async throws -> String {
        try await database.get(
            sql: "SELECT local_state FROM spike_local_operations WHERE id = ?",
            parameters: [command.envelope.operationId.rawValue]
        ) { try $0.getString(index: 0) }
    }

    private static func drainCRUD(_ database: any PowerSyncDatabaseProtocol) async throws {
        while let transaction = try await database.getNextCrudTransaction() {
            try await transaction.complete()
        }
    }
}

private final class ClientArchiveDatabaseFixture: @unchecked Sendable {
    let directoryURL: URL
    let databaseURL: URL
    private let key = try! LedgerPowerSyncEncryptionKey(
        hexadecimal: String(repeating: "7e", count: 32)
    )

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-client-archive-\(UUID().uuidString)")
        databaseURL = directoryURL.appendingPathComponent("ledger.sqlite")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func open() throws -> any PowerSyncDatabaseProtocol {
        try LedgerPowerSyncDatabaseFactory.open(
            absolutePath: databaseURL.path, encryptionKey: key
        )
    }

    func remove() { try? FileManager.default.removeItem(at: directoryURL) }
}

private struct ClientArchiveInjectedFailure: Error {}

private struct ClientArchiveUnusedClientApplier: ClientCreationCommandApplying {
    func apply(_ request: ClientCreationUploadRequest) async throws -> ClientCreationServerResult {
        throw ClientArchiveInjectedFailure()
    }
}

private struct ClientArchiveRejectingClientCreationApplier: ClientCreationCommandApplying {
    let order: ClientArchiveApplyOrder
    func apply(_ request: ClientCreationUploadRequest) async throws -> ClientCreationServerResult {
        await order.append("create_client_rejected")
        return ClientCreationServerResult(
            operationId: request.operationId,
            accountId: request.accountId,
            commandFingerprint: request.fingerprint,
            subjectId: request.clientId,
            phase: "rejected",
            resultCode: nil,
            errorCode: "client_creation_identity_conflict"
        )
    }
}

private struct ClientArchiveResultApplier: ClientArchiveCommandApplying {
    let phase: String

    func apply(_ request: ClientArchiveUploadRequest) async throws -> ClientArchiveServerResult {
        Self.result(request, phase: phase)
    }

    static func result(
        _ request: ClientArchiveUploadRequest,
        phase: String
    ) -> ClientArchiveServerResult {
        ClientArchiveServerResult(
            operationId: request.operationId,
            accountId: request.accountId,
            actorPrincipalId: request.actorPrincipalId,
            commandType: "archive_client",
            contractVersion: request.contractVersion,
            commandFingerprint: request.fingerprint,
            envelopeSHA256: request.fingerprint,
            requestSHA256: LedgerPowerSyncUploadConnector.clientArchiveRequestSHA256(request),
            subjectId: request.clientId,
            phase: phase,
            resultCode: phase == "applied" ? "client_archived" : nil,
            errorCode: phase == "rejected" ? "client_archive_revision_conflict" : nil,
            clientCreatedAtMilliseconds: request.clientCreatedAtMilliseconds,
            serverReceivedAtMilliseconds: request.clientCreatedAtMilliseconds + 1_000,
            completedAtMilliseconds: request.clientCreatedAtMilliseconds + 2_000
        )
    }
}

private struct ClientArchiveThrowingApplier: ClientArchiveCommandApplying {
    func apply(_ request: ClientArchiveUploadRequest) async throws -> ClientArchiveServerResult {
        throw ClientArchiveInjectedFailure()
    }
}

private struct ClientArchiveNegativeTimestampApplier: ClientArchiveCommandApplying {
    func apply(_ request: ClientArchiveUploadRequest) async throws -> ClientArchiveServerResult {
        let result = ClientArchiveResultApplier.result(request, phase: "applied")
        return ClientArchiveServerResult(
            operationId: result.operationId,
            accountId: result.accountId,
            actorPrincipalId: result.actorPrincipalId,
            commandType: result.commandType,
            contractVersion: result.contractVersion,
            commandFingerprint: result.commandFingerprint,
            envelopeSHA256: result.envelopeSHA256,
            requestSHA256: result.requestSHA256,
            subjectId: result.subjectId,
            phase: result.phase,
            resultCode: result.resultCode,
            errorCode: result.errorCode,
            clientCreatedAtMilliseconds: result.clientCreatedAtMilliseconds,
            serverReceivedAtMilliseconds: -2,
            completedAtMilliseconds: -1
        )
    }
}

private actor ClientArchiveApplyOrder {
    private(set) var values: [String] = []
    func append(_ value: String) { values.append(value) }
}

private struct ClientArchiveOrderedProjectApplier: ProjectCreationCommandApplying {
    let order: ClientArchiveApplyOrder
    func apply(_ request: ProjectCreationUploadRequest) async throws -> ProjectCreationServerResult {
        await order.append("create_project")
        return ProjectCreationServerResult(
            operationId: request.operationId, accountId: request.accountId,
            commandFingerprint: request.fingerprint, subjectId: request.projectId,
            phase: "applied", resultCode: "project_created", errorCode: nil
        )
    }
}

private struct ClientArchiveRejectingProjectApplier: ProjectCreationCommandApplying {
    let order: ClientArchiveApplyOrder
    func apply(_ request: ProjectCreationUploadRequest) async throws -> ProjectCreationServerResult {
        await order.append("create_project_rejected")
        return ProjectCreationServerResult(
            operationId: request.operationId,
            accountId: request.accountId,
            commandFingerprint: request.fingerprint,
            subjectId: request.projectId,
            phase: "rejected",
            resultCode: nil,
            errorCode: "project_setup_client_not_selectable"
        )
    }
}

private struct ClientArchiveOrderedApplier: ClientArchiveCommandApplying {
    let order: ClientArchiveApplyOrder
    let phase: String
    func apply(_ request: ClientArchiveUploadRequest) async throws -> ClientArchiveServerResult {
        await order.append("archive_client")
        return ClientArchiveResultApplier.result(request, phase: phase)
    }
}

private extension Array {
    var only: Element? { count == 1 ? self[0] : nil }
}

private final class ClientArchiveRecordingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler:
        ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

private func clientArchiveRequestBody(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody { return body }
    let stream = try #require(request.httpBodyStream)
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
        if count == 0 { break }
        data.append(buffer, count: count)
    }
    return data
}

private actor ClientArchiveAsyncGate {
    private var entered = false
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        entered = true
        if released { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func waitUntilEntered() async {
        while !entered { await Task.yield() }
    }

    func release() {
        released = true
        let current = waiters
        waiters.removeAll()
        current.forEach { $0.resume() }
    }
}

private actor ClientArchiveEntryCounter {
    private var count = 0
    func enter() { count += 1 }
    func waitUntilEntered() async {
        while count == 0 { await Task.yield() }
    }
}

private actor ClientArchiveFlag {
    private var stored = false
    var value: Bool { stored }
    func set() { stored = true }
}
