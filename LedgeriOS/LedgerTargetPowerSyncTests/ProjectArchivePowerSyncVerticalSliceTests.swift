import Foundation
import LedgerTargetCore
import PowerSync
import Testing
@testable import LedgerTargetPowerSync

@Suite("Project archive PowerSync vertical slice", .serialized)
struct ProjectArchivePowerSyncVerticalSliceTests {
    @Test("Archive operation identity is account-bound and namespace-exact before writes")
    func accountBoundOperationIdentityRejectsBeforeWrite() async throws {
        let fixture = try ArchiveDatabaseFixture()
        let database = try fixture.open()
        try await Self.seedAuthority(database, revision: 7)
        let uuid = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        #expect(
            try ProjectArchiveOperationIdentity.make(accountId: Self.accountId, uuid: uuid)
                .rawValue
                == "project-archive-820fcd051d436cfe81328997babf666384118e46578dce1afe250c40b3d3f07f-11111111-2222-4333-8444-555555555555"
        )
        let wrongAccount = try ArchiveProjectCommand(
            operationId: ProjectArchiveOperationIdentity.make(
                accountId: AccountID(validating: "account-other"),
                uuid: uuid
            ),
            draft: Self.draft(revision: 7)
        )
        await #expect(throws: ProjectArchivePowerSyncFailure.invalidOperationIdentity) {
            _ = try await Self.store(database).archive(wrongAccount)
        }
        let wrongNamespace = try ArchiveProjectCommand(
            operationId: OperationID(
                validating: "project-create-820fcd051d436cfe81328997babf666384118e46578dce1afe250c40b3d3f07f-11111111-2222-4333-8444-555555555555"
            ),
            draft: Self.draft(revision: 7)
        )
        await #expect(throws: ProjectArchivePowerSyncFailure.invalidOperationIdentity) {
            _ = try await Self.store(database).archive(wrongNamespace)
        }
        #expect(try await Self.count(LedgerPowerSyncTable.localOperations, database) == 0)
        #expect(try await Self.count(LedgerPowerSyncTable.projectArchiveOverlays, database) == 0)
        #expect(try await database.get("SELECT count(*) FROM ps_crud") {
            try $0.getInt64(index: 0)
        } == 0)
        let missingOperationId = try ProjectArchiveOperationIdentity.make(
            accountId: Self.accountId,
            uuid: UUID(uuidString: "11111111-2222-4333-8444-666666666666")!
        )
        var missing = Self.store(database).watchOperation(missingOperationId)
            .makeAsyncIterator()
        await #expect(throws: ProjectArchivePowerSyncFailure.operationNotFound) {
            _ = try await missing.next()
        }
        try await database.close(deleteDatabase: true)
        var invalid = Self.store(database)
            .watchOperation(wrongNamespace.envelope.operationId).makeAsyncIterator()
        await #expect(throws: ProjectArchivePowerSyncFailure.invalidOperationIdentity) {
            _ = try await invalid.next()
        }
        fixture.remove()
    }

    @Test("Offline acceptance is atomic, encrypted, replayable, projected, and restart durable")
    func offlineAcceptanceProjectionAndRestart() async throws {
        let fixture = try ArchiveDatabaseFixture()
        let database = try fixture.open()
        try await Self.seedAuthority(database, revision: 7)
        let command = try Self.command(id: "offline", revision: 7)
        let store = Self.store(database)

        let receipt = try await store.archive(command)
        #expect(receipt == OperationReceipt(operationId: command.envelope.operationId, localState: .queued))
        #expect(try await Self.count(LedgerPowerSyncTable.localOperations, database) == 1)
        let queued = try #require(try await database.getNextCrudTransaction())
        let queuedRequest = try LedgerPowerSyncUploadConnector.projectArchiveRequest(
            from: queued.crud
        )
        #expect(queuedRequest.expectedRevision == "7")
        #expect(queuedRequest.fingerprint == command.fingerprint.sha256)
        #expect(try await Self.count(LedgerPowerSyncTable.projectArchiveOverlays, database) == 1)
        #expect(try await Self.projectAuthority(database) == "active|7|client-main|Project Name|Project Description|principal-owner")
        #expect(try await Self.count(LedgerPowerSyncTable.budgetCategories, database) == 1)
        #expect(try await Self.count(LedgerPowerSyncTable.projectCategoryAllocations, database) == 1)

        let replay = try await store.archive(command)
        #expect(replay.localState == .queued)
        let list = try await Self.firstProjectList(database)
        #expect(list.local.quality == .partial)
        #expect(!list.local.isCompleteForQuery)
        #expect(list.local.rows.first?.id == Self.projectId)
        #expect(list.local.rows.first?.lifecycle == .archived)
        let detail = try await Self.firstProjectDetail(database)
        #expect(detail.local.quality == .partial)
        #expect(detail.row?.project.lifecycle == .archived)
        #expect(detail.row?.locallyObservedRevision == ExpectedProjectRevision(8))

        try await database.close(deleteDatabase: false)
        let bytes = try Data(contentsOf: fixture.databaseURL)
        #expect(!String(decoding: bytes, as: UTF8.self).contains("Project Description"))
        let reopened = try fixture.open()
        #expect(try await Self.count(LedgerPowerSyncTable.projectArchiveOverlays, reopened) == 1)
        #expect((try await Self.firstProjectDetail(reopened)).row?.project.lifecycle == .archived)
        #expect(try await Self.store(reopened).archive(command).localState == .queued)

        let invalid = ProjectArchivePowerSyncStore(
            database: reopened,
            accountId: Self.accountId,
            principalId: Self.principalId,
            now: { Date(timeIntervalSince1970: .infinity) }
        )
        await #expect(throws: ProjectArchivePowerSyncFailure.invalidAcceptanceTime) {
            _ = try await invalid.archive(Self.command(id: "invalid-time", revision: 7))
        }
        await #expect(throws: ProjectArchiveFailure.invalidEncodedCommand) {
            _ = try await Self.store(reopened).archive(Self.command(
                id: "fractional-command-time",
                revision: 7,
                capturedAt: Date(timeIntervalSince1970: 1_788_523_200.123_789)
            ))
        }
        #expect(try await Self.count(LedgerPowerSyncTable.localOperations, reopened) == 1)
        try await reopened.close(deleteDatabase: true)
        fixture.remove()
    }

    @Test("Transient failure retains work; rejection rolls back exact optimism; retry reconciles once")
    func rejectionRetryAndReadbackReconciliation() async throws {
        let fixture = try ArchiveDatabaseFixture()
        let database = try fixture.open()
        try await Self.seedAuthority(database, revision: 7)
        let first = try Self.command(id: "conflict", revision: 7)
        _ = try await Self.store(database).archive(first)
        guard case .queued = (try await Self.firstOperation(first, database)).state else {
            Issue.record("Expected queued operation evidence")
            try await database.close(deleteDatabase: true)
            fixture.remove()
            return
        }
        _ = try await database.execute(
            sql: "UPDATE spike_local_operations SET local_state = 'applying' WHERE id = ?",
            parameters: [first.envelope.operationId.rawValue]
        )
        guard case .applying = (try await Self.firstOperation(first, database)).state else {
            Issue.record("Expected applying operation evidence")
            try await database.close(deleteDatabase: true)
            fixture.remove()
            return
        }
        _ = try await database.execute(
            sql: "UPDATE spike_local_operations SET local_state = 'queued' WHERE id = ?",
            parameters: [first.envelope.operationId.rawValue]
        )

        let transientConnector = LedgerPowerSyncUploadConnector(
            credentialProvider: { nil },
            clientCreationApplier: ArchiveUnusedClientApplier(),
            projectArchiveApplier: ArchiveTransientApplier(),
            now: { Self.capturedAt }
        )
        do {
            try await transientConnector.uploadData(database: database)
            Issue.record("Expected transient archive upload failure")
        } catch is ArchiveInjectedFailure {
            // Expected: transient transport failure retains the exact queued transaction.
        }
        #expect(try await Self.localState(first, database) == "queued")
        #expect(try await Self.firstOperation(first, database).updatedAt == Self.acceptedAt)
        #expect(try await Self.count(LedgerPowerSyncTable.projectArchiveOverlays, database) == 1)
        #expect(try await database.get("SELECT count(*) FROM ps_crud") {
            try $0.getInt64(index: 0)
        } == 1)

        let rejectedConnector = LedgerPowerSyncUploadConnector(
            credentialProvider: { nil },
            clientCreationApplier: ArchiveUnusedClientApplier(),
            projectArchiveApplier: ArchiveResultApplier(phase: "rejected"),
            now: { Self.capturedAt }
        )
        try await rejectedConnector.uploadData(database: database)
        #expect(try await Self.localState(first, database) == "rejected")
        #expect(try await Self.count(LedgerPowerSyncTable.projectArchiveOverlays, database) == 0)
        #expect((try await Self.firstProjectDetail(database)).row?.project.lifecycle == .active)
        let rejectedSnapshot = try await Self.firstOperation(first, database)
        guard case .rejected(let rejection) = rejectedSnapshot.state else {
            Issue.record("Expected rejected operation evidence")
            try await database.close(deleteDatabase: true)
            fixture.remove()
            return
        }
        #expect(rejection.error.category == .conflict)
        #expect(rejectedSnapshot.updatedAt == Self.acceptedAt)

        let retry = try Self.command(id: "retry", revision: 7)
        _ = try await Self.store(database).archive(retry)
        let appliedConnector = LedgerPowerSyncUploadConnector(
            credentialProvider: { nil },
            clientCreationApplier: ArchiveUnusedClientApplier(),
            projectArchiveApplier: ArchiveResultApplier(phase: "applied"),
            now: { Self.capturedAt }
        )
        try await appliedConnector.uploadData(database: database)
        #expect(try await Self.localState(retry, database) == "applied")
        let appliedSnapshot = try await Self.firstOperation(retry, database)
        #expect(appliedSnapshot.updatedAt == Self.acceptedAt)
        guard case .applied = appliedSnapshot.state else {
            Issue.record("Expected applied operation evidence")
            try await database.close(deleteDatabase: true)
            fixture.remove()
            return
        }
        _ = try await database.execute(
            sql: "DELETE FROM spike_project_archive_overlays WHERE operation_id = ?",
            parameters: [retry.envelope.operationId.rawValue]
        )
        var missingAppliedList = Self.query(database)
            .watchProjects(accountId: Self.accountId).makeAsyncIterator()
        await #expect(throws: ClientProjectDirectoryPowerSyncFailure.malformedProjectRow) {
            _ = try await missingAppliedList.next()
        }
        let missingAppliedDetail = try await Self.firstProjectDetailUpdate(database)
        guard case .failed = missingAppliedDetail.state else {
            Issue.record("Expected missing applied archive overlay to fail closed")
            try await database.close(deleteDatabase: true)
            fixture.remove()
            return
        }
        _ = try await database.execute(
            sql: """
            INSERT INTO spike_project_archive_overlays (
              id, account_id, actor_principal_id, project_id, operation_id,
              fingerprint, expected_revision, projected_revision, lifecycle,
              accepted_at_ms
            ) VALUES (?, ?, ?, ?, ?, ?, '7', 8, 'archived', ?)
            """,
            parameters: [
                retry.envelope.operationId.rawValue,
                Self.accountId.rawValue,
                Self.principalId.rawValue,
                Self.projectId.rawValue,
                retry.envelope.operationId.rawValue,
                retry.fingerprint.sha256,
                Int64(Self.acceptedAt.timeIntervalSince1970 * 1_000)
            ]
        )
        #expect(try await Self.count(LedgerPowerSyncTable.projectArchiveOverlays, database) == 1)
        #expect((try await Self.firstProjectDetail(database)).row?.project.lifecycle == .archived)

        _ = try await database.execute(
            sql: "UPDATE spike_projects SET lifecycle = 'archived', revision = 8 WHERE id = ?",
            parameters: [Self.projectId.rawValue]
        )
        try await PowerSyncOverlayReconciler.reconcileProjectArchive(
            database: database,
            projectId: Self.projectId.rawValue,
            accountId: Self.accountId.rawValue,
            operationId: retry.envelope.operationId.rawValue
        )
        #expect(try await Self.count(LedgerPowerSyncTable.projectArchiveOverlays, database) == 0)
        _ = try await database.execute(
            sql: "UPDATE spike_projects SET lifecycle = 'active', revision = 7 WHERE id = ?",
            parameters: [Self.projectId.rawValue]
        )
        var regressedList = Self.query(database)
            .watchProjects(accountId: Self.accountId).makeAsyncIterator()
        await #expect(throws: ClientProjectDirectoryPowerSyncFailure.malformedProjectRow) {
            _ = try await regressedList.next()
        }
        guard case .failed = (try await Self.firstProjectDetailUpdate(database)).state else {
            Issue.record("Expected regressed authority after archive readback to fail closed")
            try await database.close(deleteDatabase: true)
            fixture.remove()
            return
        }

        try await database.close(deleteDatabase: true)
        fixture.remove()
    }

    @Test("A pending Project creation dispatches before its dependent archive")
    func pendingCreationArchivesFIFO() async throws {
        let fixture = try ArchiveDatabaseFixture()
        let database = try fixture.open()
        let creation = try Self.creationCommand()
        _ = try await ProjectSetupPowerSyncStore(database: database, now: { Self.acceptedAt })
            .create(creation)
        let archive = try Self.command(id: "pending-create", revision: 1)
        _ = try await Self.store(database).archive(archive)

        let order = ArchiveApplyOrder()
        let connector = LedgerPowerSyncUploadConnector(
            credentialProvider: { nil },
            clientCreationApplier: ArchiveUnusedClientApplier(),
            projectCreationApplier: OrderedProjectCreationApplier(order: order),
            projectArchiveApplier: OrderedArchiveApplier(order: order),
            now: { Self.updatedAt }
        )
        try await connector.uploadData(database: database)
        #expect(await order.values == ["create_project"])
        try await connector.uploadData(database: database)
        #expect(await order.values == ["create_project", "archive_project"])
        #expect(try await database.getNextCrudTransaction() == nil)

        let list = try await Self.firstProjectList(database)
        #expect(list.local.quality == .partial)
        #expect(list.local.rows.first?.lifecycle == .archived)
        try await database.close(deleteDatabase: true)
        fixture.remove()
    }

    @Test("RPC preserves decimal UInt64 evidence and validates exact terminal linkage")
    func rpcPrecisionCredentialsAndTerminalValidation() async throws {
        let vector = ProjectArchiveUploadRequest(
            operationId: "project-archive-820fcd051d436cfe81328997babf666384118e46578dce1afe250c40b3d3f07f-11111111-2222-4333-8444-555555555555",
            accountId: "account-primary",
            actorPrincipalId: "principal-owner",
            contractVersion: "project-archive-v1",
            clientCreatedAtMilliseconds: 1_788_609_600_000,
            projectId: "project-archive-vector",
            expectedRevision: "41",
            fingerprint: "285d889a2f53b8aaf0355ddaca6c13228bdcc8dde0c0fdbda80de6ea5f5bb933",
            envelopeJSON: #"{"accountId":"account-primary","actorPrincipalId":"principal-owner","clientCreatedAt":1788609600000,"contractVersion":"project-archive-v1","operationId":"project-archive-820fcd051d436cfe81328997babf666384118e46578dce1afe250c40b3d3f07f-11111111-2222-4333-8444-555555555555","payload":{"projectId":"project-archive-vector"},"preconditions":[{"expectedRevision":{"revision":41,"subject":{"id":"project-archive-vector","kind":"project"}}}]}"#
        )
        #expect(
            LedgerPowerSyncUploadConnector.archiveRequestSHA256(vector)
                == "9ac984815935b833e106d154f3b8f968e4d7a7f877d8199bb1698bfbd9e6bc43"
        )
        let command = try Self.command(id: "rpc-max", revision: UInt64(Int64.max) - 1)
        let request = try Self.uploadRequest(command)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ArchiveRecordingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            ArchiveRecordingURLProtocol.handler = nil
        }
        ArchiveRecordingURLProtocol.handler = { urlRequest in
            #expect(urlRequest.url?.path == "/rest/v1/rpc/spike_archive_project")
            #expect(urlRequest.value(forHTTPHeaderField: "apikey") == "publishable-key")
            #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == "Bearer user-token")
            let body = try archiveRequestBody(urlRequest)
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(json["p_expected_revision"] as? String == "9223372036854775806")
            #expect(json["p_project_captured_at"] as? String != nil)
            let response = try #require(HTTPURLResponse(
                url: urlRequest.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return (response, try JSONEncoder().encode(ArchiveResultApplier.result(request, phase: "applied")))
        }
        let rpc = try SupabaseProjectArchiveRPC(
            supabaseURL: URL(string: "https://target.invalid")!,
            publishableKey: "publishable-key",
            accessTokenProvider: { "user-token" },
            session: session
        )
        #expect(try await rpc.apply(request).resultCode == "project_archived")

        ArchiveRecordingURLProtocol.handler = { urlRequest in
            let bytes = try JSONEncoder().encode(ArchiveResultApplier.result(request, phase: "rejected"))
            var json = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            json["error_code"] = "unknown_terminal_code"
            let response = try #require(HTTPURLResponse(
                url: urlRequest.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return (response, try JSONSerialization.data(withJSONObject: json))
        }
        await #expect(throws: SupabaseProjectArchiveRPCFailure.resultMismatch) {
            _ = try await rpc.apply(request)
        }
        #expect(throws: SupabaseProjectArchiveRPCFailure.serviceRoleCredentialRefused) {
            _ = try SupabaseProjectArchiveRPC(
                supabaseURL: URL(string: "https://target.invalid")!,
                publishableKey: "sb_secret_never-allowed",
                accessTokenProvider: { "unused" }
            )
        }
    }

    @Test("Malformed overlay linkage fails directory and detail reads closed")
    func malformedOverlayFailsClosed() async throws {
        let fixture = try ArchiveDatabaseFixture()
        let database = try fixture.open()
        try await Self.seedAuthority(database, revision: 7)
        let command = try Self.command(id: "malformed", revision: 7)
        _ = try await Self.store(database).archive(command)
        _ = try await database.execute(
            sql: "UPDATE spike_project_archive_overlays SET fingerprint = ? WHERE operation_id = ?",
            parameters: [String(repeating: "0", count: 64), command.envelope.operationId.rawValue]
        )
        var listIterator = Self.query(database).watchProjects(accountId: Self.accountId).makeAsyncIterator()
        await #expect(throws: ClientProjectDirectoryPowerSyncFailure.malformedProjectRow) {
            _ = try await listIterator.next()
        }
        let detailUpdate = try await Self.firstProjectDetailUpdate(database)
        guard case .failed = detailUpdate.state else {
            Issue.record("Expected fail-closed detail evidence")
            try await database.close(deleteDatabase: true)
            fixture.remove()
            return
        }
        _ = try await database.execute(
            sql: "UPDATE spike_project_archive_overlays SET fingerprint = ? WHERE operation_id = ?",
            parameters: [command.fingerprint.sha256, command.envelope.operationId.rawValue]
        )
        let canonicalEnvelope = try #require(String(
            data: OperationContractCodec.encode(command.envelope),
            encoding: .utf8
        ))
        let commandMutations: [(column: String, invalid: String, restored: String)] = [
            ("command_type", "create_project", "archive_project"),
            ("command_expected_revision", "8", "7"),
            ("command_envelope_json", canonicalEnvelope + " ", canonicalEnvelope)
        ]
        for mutation in commandMutations {
            _ = try await database.execute(
                sql: "UPDATE spike_local_operations SET \(mutation.column) = ? WHERE id = ?",
                parameters: [mutation.invalid, command.envelope.operationId.rawValue]
            )
            var invalidList = Self.query(database)
                .watchProjects(accountId: Self.accountId).makeAsyncIterator()
            await #expect(throws: ClientProjectDirectoryPowerSyncFailure.malformedProjectRow) {
                _ = try await invalidList.next()
            }
            let invalidDetail = try await Self.firstProjectDetailUpdate(database)
            guard case .failed = invalidDetail.state else {
                Issue.record("Expected command-linkage detail failure for \(mutation.column)")
                try await database.close(deleteDatabase: true)
                fixture.remove()
                return
            }
            _ = try await database.execute(
                sql: "UPDATE spike_local_operations SET \(mutation.column) = ? WHERE id = ?",
                parameters: [mutation.restored, command.envelope.operationId.rawValue]
            )
        }
        _ = try await database.execute(
            sql: "DELETE FROM spike_project_archive_overlays WHERE operation_id = ?",
            parameters: [command.envelope.operationId.rawValue]
        )
        for missingOverlayState in ["queued", "applying"] {
            _ = try await database.execute(
                sql: "UPDATE spike_local_operations SET local_state = ? WHERE id = ?",
                parameters: [missingOverlayState, command.envelope.operationId.rawValue]
            )
            var missingList = Self.query(database)
                .watchProjects(accountId: Self.accountId).makeAsyncIterator()
            await #expect(throws: ClientProjectDirectoryPowerSyncFailure.malformedProjectRow) {
                _ = try await missingList.next()
            }
            let missingDetail = try await Self.firstProjectDetailUpdate(database)
            guard case .failed = missingDetail.state else {
                Issue.record("Expected missing \(missingOverlayState) overlay detail failure")
                try await database.close(deleteDatabase: true)
                fixture.remove()
                return
            }
        }
        _ = try await database.execute(
            sql: "UPDATE spike_local_operations SET local_state = 'queued' WHERE id = ?",
            parameters: [command.envelope.operationId.rawValue]
        )
        var operationIterator = Self.store(database)
            .watchOperation(command.envelope.operationId).makeAsyncIterator()
        await #expect(throws: ProjectArchivePowerSyncFailure.malformedLocalEvidence) {
            _ = try await operationIterator.next()
        }
        await #expect(throws: ProjectArchivePowerSyncFailure.malformedLocalEvidence) {
            _ = try await Self.store(database).archive(command)
        }
        let connector = LedgerPowerSyncUploadConnector(
            credentialProvider: { nil },
            clientCreationApplier: ArchiveUnusedClientApplier(),
            projectArchiveApplier: ArchiveResultApplier(phase: "applied"),
            now: { Self.updatedAt }
        )
        await #expect(throws: LedgerPowerSyncUploadFailure.pendingOverlayMismatch) {
            try await connector.uploadData(database: database)
        }
        try await database.close(deleteDatabase: true)
        fixture.remove()
    }

    @Test("Validated terminal evidence is exact and durable before synchronized readback")
    func exactTerminalEvidenceSurvivesRestartAndChecksReadback() async throws {
        let fixture = try ArchiveDatabaseFixture()
        let database = try fixture.open()
        try await Self.seedAuthority(database, revision: 7)
        let command = try Self.command(id: "terminal-durable", revision: 7)
        _ = try await Self.store(database).archive(command)
        let connector = LedgerPowerSyncUploadConnector(
            credentialProvider: { nil },
            clientCreationApplier: ArchiveUnusedClientApplier(),
            projectArchiveApplier: ArchiveResultApplier(
                phase: "rejected",
                errorCode: "project_archive_payload_invalid"
            ),
            now: { Self.updatedAt }
        )
        try await connector.uploadData(database: database)
        let durable = try await Self.firstOperation(command, database)
        guard case .rejected(let rejection) = durable.state else {
            Issue.record("Expected durable rejection")
            try await database.close(deleteDatabase: true)
            fixture.remove()
            return
        }
        #expect(rejection.error.code.rawValue == "project_archive_payload_invalid")
        #expect(rejection.error.category == .validation)
        #expect(rejection.rejectedAt == Date(timeIntervalSince1970: 1_788_523_202))
        try await database.close(deleteDatabase: false)

        let reopened = try fixture.open()
        let restarted = try await Self.firstOperation(command, reopened)
        #expect(restarted == durable)
        let uploadRequest = try Self.uploadRequest(command)
        let requestSHA256 = LedgerPowerSyncUploadConnector.archiveRequestSHA256(uploadRequest)
        _ = try await reopened.execute(
            sql: "UPDATE spike_local_operations SET terminal_request_sha256 = ? WHERE id = ?",
            parameters: [
                String(repeating: "0", count: 64),
                command.envelope.operationId.rawValue
            ]
        )
        await #expect(throws: ProjectArchivePowerSyncFailure.malformedLocalEvidence) {
            _ = try await Self.store(reopened).archive(command)
        }
        _ = try await reopened.execute(
            sql: "UPDATE spike_local_operations SET terminal_request_sha256 = ? WHERE id = ?",
            parameters: [requestSHA256, command.envelope.operationId.rawValue]
        )
        _ = try await reopened.execute(sql: """
            INSERT INTO spike_operation_results (
              id, account_id, actor_principal_id, command_type,
              contract_version, command_fingerprint, envelope_sha256, request_sha256,
              subject_id, phase, result_code, error_code,
              client_created_at_ms, server_received_at_ms, completed_at_ms
            ) VALUES (?, ?, ?, 'archive_project', ?, ?, ?, ?, ?, 'rejected', NULL, ?, ?, ?, ?)
            """, parameters: [
                command.envelope.operationId.rawValue,
                Self.accountId.rawValue,
                Self.principalId.rawValue,
                command.envelope.contractVersion.rawValue,
                command.fingerprint.sha256,
                command.fingerprint.sha256,
                requestSHA256,
                Self.projectId.rawValue,
                "project_archive_payload_invalid",
                Int64(Self.capturedAt.timeIntervalSince1970 * 1_000),
                Int64(Self.capturedAt.timeIntervalSince1970 * 1_000) + 1_000,
                Int64(Self.capturedAt.timeIntervalSince1970 * 1_000) + 2_000
            ])
        #expect(try await Self.firstOperation(command, reopened) == durable)
        _ = try await reopened.execute(
            sql: "UPDATE spike_operation_results SET request_sha256 = ? WHERE id = ?",
            parameters: [
                String(repeating: "f", count: 64),
                command.envelope.operationId.rawValue
            ]
        )
        var requestMismatch = Self.store(reopened)
            .watchOperation(command.envelope.operationId).makeAsyncIterator()
        await #expect(throws: ProjectArchivePowerSyncFailure.malformedLocalEvidence) {
            _ = try await requestMismatch.next()
        }
        _ = try await reopened.execute(
            sql: "UPDATE spike_operation_results SET request_sha256 = ? WHERE id = ?",
            parameters: [requestSHA256, command.envelope.operationId.rawValue]
        )
        _ = try await reopened.execute(
            sql: "UPDATE spike_operation_results SET error_code = 'contract_unsupported' WHERE id = ?",
            parameters: [command.envelope.operationId.rawValue]
        )
        var mismatched = Self.store(reopened).watchOperation(command.envelope.operationId)
            .makeAsyncIterator()
        await #expect(throws: ProjectArchivePowerSyncFailure.malformedLocalEvidence) {
            _ = try await mismatched.next()
        }
        try await reopened.close(deleteDatabase: true)
        fixture.remove()
    }

    @Test("Store shutdown cancels and drains active operation watches before database close")
    func storeShutdownDrainsOperationWatches() async throws {
        let fixture = try ArchiveDatabaseFixture()
        let database = try fixture.open()
        try await Self.seedAuthority(database, revision: 7)
        let command = try Self.command(id: "drain", revision: 7)
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
    private static let projectId = try! ProjectID(validating: "project-main")
    private static let capturedAt = Date(timeIntervalSince1970: 1_788_523_200)
    private static let acceptedAt = Date(timeIntervalSince1970: 1_788_523_201)
    private static let updatedAt = Date(timeIntervalSince1970: 1_788_523_202)

    private static func command(
        id: String,
        revision: UInt64,
        capturedAt: Date = capturedAt
    ) throws -> ArchiveProjectCommand {
        let uuids: [String: String] = [
            "offline": "00000000-0000-4000-8000-000000000001",
            "invalid-time": "00000000-0000-4000-8000-000000000002",
            "fractional-command-time": "00000000-0000-4000-8000-000000000009",
            "conflict": "00000000-0000-4000-8000-000000000003",
            "retry": "00000000-0000-4000-8000-000000000004",
            "pending-create": "00000000-0000-4000-8000-000000000005",
            "rpc-max": "00000000-0000-4000-8000-000000000006",
            "malformed": "00000000-0000-4000-8000-000000000007",
            "terminal-durable": "00000000-0000-4000-8000-000000000008",
            "drain": "00000000-0000-4000-8000-000000000010"
        ]
        let uuid = try #require(uuids[id].flatMap(UUID.init(uuidString:)))
        return try ArchiveProjectCommand(
            operationId: ProjectArchiveOperationIdentity.make(accountId: accountId, uuid: uuid),
            draft: draft(revision: revision, capturedAt: capturedAt)
        )
    }

    private static func draft(
        revision: UInt64,
        capturedAt: Date = capturedAt
    ) throws -> ProjectArchiveDraft {
        try ProjectArchiveDraft(
            accountId: accountId,
            actorPrincipalId: principalId,
            operationContractVersion: OperationContractVersion(validating: "project-archive-v1"),
            projectId: projectId,
            expectedRevision: ExpectedProjectRevision(revision),
            capturedAt: capturedAt
        )
    }

    private static func creationCommand() throws -> CreateProjectCommand {
        try CreateProjectCommand(
            operationId: OperationID(validating: "operation-create-before-archive"),
            draft: ProjectSetupDraft(
                accountId: accountId,
                actorPrincipalId: principalId,
                operationContractVersion: OperationContractVersion(validating: "project-create-v1"),
                projectId: projectId,
                clientSelection: ProjectClientSelectionInput(
                    newClientId: clientId,
                    displayName: ClientDisplayName(validating: "Pending Client")
                ),
                displayName: ProjectDisplayName(validating: "Pending Project"),
                description: "Pending Description",
                categoryAllocations: [],
                capturedAt: capturedAt
            )
        )
    }

    private static func store(_ database: any PowerSyncDatabaseProtocol) -> ProjectArchivePowerSyncStore {
        ProjectArchivePowerSyncStore(
            database: database,
            accountId: accountId,
            principalId: principalId,
            now: { acceptedAt }
        )
    }

    private static func query(_ database: any PowerSyncDatabaseProtocol) -> ClientProjectDirectoryPowerSyncQuery {
        ClientProjectDirectoryPowerSyncQuery(
            database: database,
            principalId: principalId,
            accountId: accountId,
            now: { updatedAt }
        )
    }

    private static func seedAuthority(_ database: any PowerSyncDatabaseProtocol, revision: Int64) async throws {
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
            ) VALUES (?, ?, 'Client Name', 'active', 3, ?, ?, ?)
            """, parameters: [clientId.rawValue, accountId.rawValue, timestamp, timestamp, principalId.rawValue])
        _ = try await database.execute(sql: """
            INSERT INTO spike_projects (
              id, account_id, client_id, display_name, description, lifecycle,
              revision, created_at_ms, updated_at_ms, created_by_principal_id
            ) VALUES (?, ?, ?, 'Project Name', 'Project Description', 'active', ?, ?, ?, ?)
            """, parameters: [projectId.rawValue, accountId.rawValue, clientId.rawValue, revision, timestamp, timestamp, principalId.rawValue])
        _ = try await database.execute(sql: """
            INSERT INTO spike_budget_categories (
              id, account_id, display_name, kind, lifecycle, is_system,
              excludes_from_overall_budget, visibility_class, presentation_order,
              revision, created_at_ms, updated_at_ms
            ) VALUES ('category-main', ?, 'Main', 'percentage', 'active', 0, 0, 'standard', 1, 2, ?, ?)
            """, parameters: [accountId.rawValue, timestamp, timestamp])
        _ = try await database.execute(sql: """
            INSERT INTO spike_project_category_allocations (
              id, account_id, project_id, category_id, allocation_minor_units,
              allocation_currency, revision, created_at_ms, updated_at_ms,
              created_by_principal_id
            ) VALUES ('allocation-main', ?, ?, 'category-main', 12345, 'USD', 4, ?, ?, ?)
            """, parameters: [accountId.rawValue, projectId.rawValue, timestamp, timestamp, principalId.rawValue])
        try await drainCRUD(database)
    }

    private static func firstProjectList(_ database: any PowerSyncDatabaseProtocol) async throws -> ProjectListSnapshot {
        var iterator = query(database).watchProjects(accountId: accountId).makeAsyncIterator()
        return try #require(try await iterator.next())
    }

    private static func firstProjectDetailUpdate(_ database: any PowerSyncDatabaseProtocol) async throws -> ProjectCoreDetailsUpdate {
        let request = try ProjectCoreDetailsRequest(accountId: accountId, projectId: projectId)
        var iterator = ProjectCoreDetailsPowerSyncQuery(
            database: database,
            principalId: principalId,
            accountId: accountId,
            now: { updatedAt }
        ).watchProjectCoreDetails(request).makeAsyncIterator()
        _ = try await iterator.next()
        return try #require(try await iterator.next())
    }

    private static func firstProjectDetail(_ database: any PowerSyncDatabaseProtocol) async throws -> ProjectCoreDetailsLocalSnapshot {
        let update = try await firstProjectDetailUpdate(database)
        guard case .snapshot(let snapshot) = update.state else { throw ArchiveInjectedFailure() }
        return snapshot
    }

    private static func firstOperation(_ command: ArchiveProjectCommand, _ database: any PowerSyncDatabaseProtocol) async throws -> OperationSnapshot {
        var iterator = store(database).watchOperation(command.envelope.operationId).makeAsyncIterator()
        return try #require(try await iterator.next())
    }

    private static func uploadRequest(_ command: ArchiveProjectCommand) throws -> ProjectArchiveUploadRequest {
        ProjectArchiveUploadRequest(
            operationId: command.envelope.operationId.rawValue,
            accountId: command.envelope.accountId.rawValue,
            actorPrincipalId: command.envelope.actorPrincipalId.rawValue,
            contractVersion: command.envelope.contractVersion.rawValue,
            clientCreatedAtMilliseconds: Int64(capturedAt.timeIntervalSince1970 * 1_000),
            projectId: command.draft.projectId.rawValue,
            expectedRevision: String(command.draft.expectedRevision.rawValue),
            fingerprint: command.fingerprint.sha256,
            envelopeJSON: String(decoding: try OperationContractCodec.encode(command.envelope), as: UTF8.self)
        )
    }

    private static func count(_ table: String, _ database: any PowerSyncDatabaseProtocol) async throws -> Int64 {
        try await database.get("SELECT count(*) FROM \(table)") { try $0.getInt64(index: 0) }
    }

    private static func drainCRUD(_ database: any PowerSyncDatabaseProtocol) async throws {
        while let transaction = try await database.getNextCrudTransaction() {
            try await transaction.complete()
        }
    }

    private static func projectAuthority(_ database: any PowerSyncDatabaseProtocol) async throws -> String {
        try await database.get(
            sql: """
            SELECT lifecycle || '|' || revision || '|' || client_id || '|' ||
                   display_name || '|' || description || '|' || created_by_principal_id
            FROM spike_projects WHERE id = ?
            """,
            parameters: [projectId.rawValue]
        ) { try $0.getString(index: 0) }
    }

    private static func localState(_ command: ArchiveProjectCommand, _ database: any PowerSyncDatabaseProtocol) async throws -> String {
        try await database.get(
            sql: "SELECT local_state FROM spike_local_operations WHERE id = ?",
            parameters: [command.envelope.operationId.rawValue]
        ) { try $0.getString(index: 0) }
    }
}

private final class ArchiveDatabaseFixture: @unchecked Sendable {
    let directoryURL: URL
    let databaseURL: URL
    private let key = try! LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "6d", count: 32))

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-project-archive-\(UUID().uuidString)")
        databaseURL = directoryURL.appendingPathComponent("ledger.sqlite")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func open() throws -> any PowerSyncDatabaseProtocol {
        try LedgerPowerSyncDatabaseFactory.open(absolutePath: databaseURL.path, encryptionKey: key)
    }

    func remove() { try? FileManager.default.removeItem(at: directoryURL) }
}

private struct ArchiveInjectedFailure: Error {}

private struct ArchiveUnusedClientApplier: ClientCreationCommandApplying {
    func apply(_ request: ClientCreationUploadRequest) async throws -> ClientCreationServerResult { throw ArchiveInjectedFailure() }
}

private struct ArchiveTransientApplier: ProjectArchiveCommandApplying {
    func apply(_ request: ProjectArchiveUploadRequest) async throws -> ProjectArchiveServerResult { throw ArchiveInjectedFailure() }
}

private struct ArchiveResultApplier: ProjectArchiveCommandApplying {
    let phase: String
    let errorCode: String

    init(
        phase: String,
        errorCode: String = "project_archive_revision_conflict"
    ) {
        self.phase = phase
        self.errorCode = errorCode
    }
    func apply(_ request: ProjectArchiveUploadRequest) async throws -> ProjectArchiveServerResult {
        Self.result(request, phase: phase, errorCode: errorCode)
    }

    static func result(
        _ request: ProjectArchiveUploadRequest,
        phase: String,
        errorCode: String = "project_archive_revision_conflict"
    ) -> ProjectArchiveServerResult {
        ProjectArchiveServerResult(
            operationId: request.operationId,
            accountId: request.accountId,
            actorPrincipalId: request.actorPrincipalId,
            commandType: "archive_project",
            contractVersion: request.contractVersion,
            commandFingerprint: request.fingerprint,
            envelopeSHA256: request.fingerprint,
            requestSHA256: LedgerPowerSyncUploadConnector.archiveRequestSHA256(request),
            subjectId: request.projectId,
            phase: phase,
            resultCode: phase == "applied" ? "project_archived" : nil,
            errorCode: phase == "rejected" ? errorCode : nil,
            clientCreatedAtMilliseconds: request.clientCreatedAtMilliseconds,
            serverReceivedAtMilliseconds: request.clientCreatedAtMilliseconds + 1_000,
            completedAtMilliseconds: request.clientCreatedAtMilliseconds + 2_000
        )
    }
}

private actor ArchiveApplyOrder {
    private(set) var values: [String] = []
    func append(_ value: String) { values.append(value) }
}

private struct OrderedProjectCreationApplier: ProjectCreationCommandApplying {
    let order: ArchiveApplyOrder
    func apply(_ request: ProjectCreationUploadRequest) async throws -> ProjectCreationServerResult {
        await order.append("create_project")
        return ProjectCreationServerResult(
            operationId: request.operationId, accountId: request.accountId,
            commandFingerprint: request.fingerprint, subjectId: request.projectId,
            phase: "applied", resultCode: "project_created", errorCode: nil
        )
    }
}

private struct OrderedArchiveApplier: ProjectArchiveCommandApplying {
    let order: ArchiveApplyOrder
    func apply(_ request: ProjectArchiveUploadRequest) async throws -> ProjectArchiveServerResult {
        await order.append("archive_project")
        return ArchiveResultApplier.result(request, phase: "applied")
    }
}

private final class ArchiveRecordingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw ArchiveInjectedFailure() }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private func archiveRequestBody(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody { return body }
    let stream = try #require(request.httpBodyStream)
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 { throw stream.streamError ?? ArchiveInjectedFailure() }
        if count == 0 { break }
        data.append(buffer, count: count)
    }
    return data
}
