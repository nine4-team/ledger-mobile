import Foundation
import LedgerTargetAppModel
import LedgerTargetCore
import PowerSync
import Testing
@testable import LedgerTargetPowerSync

@Suite("Space checklist revision PowerSync vertical slice", .serialized)
struct SpaceChecklistRevisionPowerSyncVerticalSliceTests {
    @Test("Account-bound identity and interrupted acceptance fail before durable writes")
    func identityAndAtomicRollback() async throws {
        let fixture = try ChecklistRevisionDatabaseFixture()
        let database = try fixture.open()
        try await Self.seedAuthority(database)

        let uuid = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        let wrongAccountCommand = try Self.command(
            operationId: SpaceChecklistRevisionOperationIdentity.make(
                accountId: AccountID(validating: "another-account"),
                uuid: uuid
            )
        )
        await #expect(throws: SpaceChecklistRevisionPowerSyncFailure.invalidOperationIdentity) {
            _ = try await Self.store(database).reviseChecklists(wrongAccountCommand)
        }

        let wrongNamespaceCommand = try Self.command(
            operationId: OperationID(
                validating: "project-archive-82ea1a79f57b6f3d639ab5b1f69cde7650ef8343799881678fb67529060a146d-11111111-2222-4333-8444-555555555555"
            )
        )
        await #expect(throws: SpaceChecklistRevisionPowerSyncFailure.invalidOperationIdentity) {
            _ = try await Self.store(database).reviseChecklists(wrongNamespaceCommand)
        }
        #expect(try await Self.pendingEvidenceCount(database) == 0)

        let interrupted = SpaceChecklistRevisionPowerSyncStore(
            database: database,
            accountId: Self.accountId,
            principalId: Self.principalId,
            now: { Self.acceptedAt },
            checkpoint: { point in
                if point == .commandWrite { throw ChecklistRevisionInjectedFailure() }
            }
        )
        await #expect(throws: SpaceChecklistRevisionFailure.localAcceptanceFailed) {
            _ = try await interrupted.reviseChecklists(
                Self.command(id: "interrupted")
            )
        }
        #expect(try await Self.pendingEvidenceCount(database) == 0)

        await interrupted.cancelAndDrainWatches()
        try await database.close(deleteDatabase: true)
        fixture.remove()
    }

    @Test("Acceptance is replay-safe, restart durable, and projects the exact checklist")
    func acceptanceReplayRestartAndProjection() async throws {
        let fixture = try ChecklistRevisionDatabaseFixture()
        let database = try fixture.open()
        try await Self.seedAuthority(database)
        let command = try Self.command(id: "offline")
        let store = Self.store(database)

        let receipt = try await store.reviseChecklists(command)
        #expect(receipt == OperationReceipt(
            operationId: command.envelope.operationId,
            localState: .queued
        ))
        #expect(try await Self.count(LedgerPowerSyncTable.localOperations, database) == 1)
        #expect(try await Self.count(
            LedgerPowerSyncTable.spaceChecklistRevisionOverlays,
            database
        ) == 1)
        let transaction = try #require(try await database.getNextCrudTransaction())
        let request = try LedgerPowerSyncUploadConnector.spaceChecklistRevisionRequest(
            from: transaction.crud
        )
        #expect(request.operationId == command.envelope.operationId.rawValue)
        #expect(request.expectedRevision == "7")
        #expect(request.collectionJSON == Self.collectionJSON(Self.checkedCollection))
        #expect(try await store.reviseChecklists(command).localState == .queued)

        let mismatched = try Self.command(
            operationId: command.envelope.operationId,
            collection: Self.uncheckedCollection
        )
        await #expect(throws: OperationContractFailure.payloadMismatch(command.envelope.operationId)) {
            _ = try await store.reviseChecklists(mismatched)
        }
        #expect(try await Self.pendingEvidenceCount(database) == 3)

        let projected = try Self.projectedSnapshot(
            command: command,
            authoritativeRevision: 7,
            authoritativeChecked: false,
            operationState: "queued"
        )
        #expect(projected.row?.revision == 8)
        #expect(projected.row?.checklists == Self.checkedCollection)
        #expect(projected.row?.completedItemCount == 1)
        #expect(projected.checklistRevisionProjection?.operationId == command.envelope.operationId)
        #expect(projected.checklistRevisionProjection?.localState == .queued)

        try await database.close(deleteDatabase: false)
        let bytes = try Data(contentsOf: fixture.databaseURL)
        #expect(!String(decoding: bytes, as: UTF8.self).contains("Verify lighting"))
        let reopened = try fixture.open()
        #expect(try await Self.store(reopened).reviseChecklists(command).localState == .queued)
        #expect(try await Self.pendingEvidenceCount(reopened) == 3)
        let detailRequest = try SpaceCoreDetailsRequest(
            accountId: Self.accountId,
            spaceId: Self.spaceId
        )
        let reopenedRows = try await PowerSyncSpaceCoreDetailsLocalReader(
            database: reopened
        ).readRows(request: detailRequest, principalId: Self.principalId)
        let reopenedSnapshot = try SpaceCoreDetailsPowerSyncQuery.localSnapshot(
            request: detailRequest,
            rows: reopenedRows,
            streamCompletionReported: false,
            hasLastSyncedAt: false,
            asOf: Self.asOf
        )
        #expect(reopenedSnapshot.checklistRevisionProjection?.operationId == command.envelope.operationId)
        #expect(reopenedSnapshot.row?.checklists == command.draft.collection)

        try await reopened.close(deleteDatabase: true)
        fixture.remove()
    }

    @Test("Upload retries safely, retains applied optimism through readback, and removes rejected optimism")
    func uploadLifecycleAndReadback() async throws {
        let fixture = try ChecklistRevisionDatabaseFixture()
        let database = try fixture.open()
        try await Self.seedAuthority(database)
        let first = try Self.command(id: "first")
        _ = try await Self.store(database).reviseChecklists(first)

        let transient = Self.connector(
            applier: ChecklistRevisionTransientApplier()
        )
        await #expect(throws: ChecklistRevisionInjectedFailure.self) {
            try await transient.uploadData(database: database)
        }
        #expect(try await Self.localState(first, database) == "queued")
        #expect(try await Self.count(
            LedgerPowerSyncTable.spaceChecklistRevisionOverlays,
            database
        ) == 1)
        #expect(try await Self.crudCount(database) == 1)

        let invalid = Self.connector(
            applier: ChecklistRevisionResultApplier(
                phase: "rejected",
                errorCode: "made_up_rejection"
            )
        )
        await #expect(throws: LedgerPowerSyncUploadFailure.invalidServerResult) {
            try await invalid.uploadData(database: database)
        }
        #expect(try await Self.localState(first, database) == "queued")
        #expect(try await Self.crudCount(database) == 1)

        try await Self.connector(
            applier: ChecklistRevisionResultApplier(phase: "applied")
        ).uploadData(database: database)
        #expect(try await Self.localState(first, database) == "applied")
        #expect(try await Self.count(
            LedgerPowerSyncTable.spaceChecklistRevisionOverlays,
            database
        ) == 1)
        #expect(try await Self.store(database).reviseChecklists(first).localState == .applied)
        #expect(try await Self.crudCount(database) == 0)
        guard case .applied = try await Self.firstOperation(first, database).state else {
            Issue.record("Expected applied operation evidence")
            return
        }

        let readback = try Self.projectedSnapshot(
            command: first,
            authoritativeRevision: 8,
            authoritativeChecked: true,
            operationState: "applied"
        )
        #expect(readback.row?.revision == 8)
        #expect(readback.row?.checklists == Self.checkedCollection)
        #expect(throws: SpaceCoreDetailsPowerSyncFailure.malformedSpaceRow) {
            _ = try Self.projectedSnapshot(
                command: first,
                authoritativeRevision: 8,
                authoritativeChecked: false,
                operationState: "applied"
            )
        }

        _ = try await database.execute(
            sql: "UPDATE spike_spaces SET revision = 8 WHERE id = ?",
            parameters: [Self.spaceId.rawValue]
        )
        _ = try await database.execute(
            sql: "UPDATE spike_space_checklist_items SET is_checked = 1 WHERE space_id = ?",
            parameters: [Self.spaceId.rawValue]
        )
        try await PowerSyncOverlayReconciler.reconcileSpaceChecklistRevision(
            database: database,
            candidate: SpaceChecklistRevisionReconciliationCandidate(
                operationId: first.envelope.operationId.rawValue,
                accountId: Self.accountId.rawValue,
                spaceId: Self.spaceId.rawValue,
                fingerprint: first.fingerprint.sha256,
                projectedRevision: 8
            )
        )
        #expect(try await Self.count(
            LedgerPowerSyncTable.spaceChecklistRevisionOverlays,
            database
        ) == 0)
        #expect(try await database.get(
            sql: "SELECT checklist_readback_revision FROM spike_local_operations WHERE id = ?",
            parameters: [first.envelope.operationId.rawValue]
        ) { try $0.getInt64(index: 0) } == 8)
        #expect(try await Self.store(database).reviseChecklists(first).localState == .applied)
        guard case .applied = try await Self.firstOperation(first, database).state else {
            Issue.record("Expected reconciled applied operation evidence")
            return
        }
        try await Self.drainCRUD(database)

        let second = try Self.command(
            id: "second",
            revision: 8,
            collection: Self.uncheckedCollection
        )
        _ = try await Self.store(database).reviseChecklists(second)
        #expect(try await Self.overlayOperationIds(database) == [
            second.envelope.operationId.rawValue
        ])
        try await Self.connector(
            applier: ChecklistRevisionResultApplier(
                phase: "rejected",
                errorCode: "space_checklist_revision_conflict"
            )
        ).uploadData(database: database)
        #expect(try await Self.localState(second, database) == "rejected")
        #expect(try await Self.count(
            LedgerPowerSyncTable.spaceChecklistRevisionOverlays,
            database
        ) == 0)
        guard case .rejected(let rejection) = try await Self.firstOperation(
            second,
            database
        ).state else {
            Issue.record("Expected rejected operation evidence")
            return
        }
        #expect(rejection.error.category == .conflict)

        try await database.close(deleteDatabase: true)
        fixture.remove()
    }

    @Test("An applied operation missing both overlay and readback proof fails closed")
    func missingAppliedOverlayWithoutReadbackProof() async throws {
        let fixture = try ChecklistRevisionDatabaseFixture()
        let database = try fixture.open()
        try await Self.seedAuthority(database)
        let command = try Self.command(id: "first")
        _ = try await Self.store(database).reviseChecklists(command)
        try await Self.connector(
            applier: ChecklistRevisionResultApplier(phase: "applied")
        ).uploadData(database: database)
        _ = try await database.execute(
            sql: "DELETE FROM spike_space_checklist_revision_overlays WHERE operation_id = ?",
            parameters: [command.envelope.operationId.rawValue]
        )

        await #expect(throws: SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence) {
            _ = try await Self.store(database).reviseChecklists(command)
        }
        await #expect(throws: SpaceChecklistRevisionPowerSyncFailure.malformedLocalEvidence) {
            _ = try await Self.firstOperation(command, database)
        }
        try await database.close(deleteDatabase: true)
        fixture.remove()
    }

    @Test("Server-ahead terminal clocks remain valid for applied and rejected results")
    func serverAheadClockSkew() async throws {
        for terminal in ["applied", "rejected"] {
            let fixture = try ChecklistRevisionDatabaseFixture()
            let database = try fixture.open()
            try await Self.seedAuthority(database)
            let command = try Self.command(id: terminal == "applied" ? "first" : "second")
            _ = try await Self.store(database).reviseChecklists(command)

            try await Self.connector(
                applier: ChecklistRevisionResultApplier(
                    phase: terminal,
                    errorCode: terminal == "rejected"
                        ? "space_checklist_revision_conflict"
                        : nil
                ),
                now: Self.capturedAt
            ).uploadData(database: database)

            let snapshot = try await Self.firstOperation(command, database)
            #expect(snapshot.updatedAt == Self.capturedAt.addingTimeInterval(2))
            #expect(snapshot.updatedAt > Self.acceptedAt)
            #expect(snapshot.state.localState?.rawValue == terminal)
            try await database.close(deleteDatabase: true)
            fixture.remove()
        }
    }

    @Test("Rejected full commands survive encrypted restart and order deterministically")
    func rejectedRecoveryRestartAndOrdering() async throws {
        let fixture = try ChecklistRevisionDatabaseFixture()
        let database = try fixture.open()
        try await Self.seedAuthority(database)
        let first = try Self.command(id: "first")
        let second = try Self.command(id: "second", collection: Self.uncheckedCollection)

        _ = try await Self.store(database).reviseChecklists(first)
        try await Self.connector(
            applier: ChecklistRevisionResultApplier(
                phase: "rejected",
                errorCode: "space_checklist_revision_conflict"
            )
        ).uploadData(database: database)
        _ = try await Self.store(database).reviseChecklists(second)
        try await Self.connector(
            applier: ChecklistRevisionResultApplier(
                phase: "rejected",
                errorCode: "space_checklist_revision_payload_invalid"
            )
        ).uploadData(database: database)
        _ = try await database.execute(
            sql: """
            UPDATE spike_local_operations
            SET updated_at_ms = updated_at_ms + 1000,
                terminal_completed_at_ms = terminal_completed_at_ms + 1000
            WHERE id = ?
            """,
            parameters: [second.envelope.operationId.rawValue]
        )

        let request = try Self.recoveryRequest()
        let beforeRestart = try await Self.store(database).rejectedOperations(request)
        #expect(beforeRestart.candidates.map(\.operationId) == [
            second.envelope.operationId, first.envelope.operationId
        ])
        guard case .reviseSpaceChecklists(let recoveredSecond) =
                beforeRestart.candidates[0].command else {
            Issue.record("Expected typed checklist command recovery")
            return
        }
        #expect(recoveredSecond == second)
        #expect(beforeRestart.candidates[0].rejection.error.code.rawValue ==
            "space_checklist_revision_payload_invalid")
        #expect(try await database.get(
            "SELECT count(*) FROM spike_local_operations WHERE local_state = 'rejected'"
        ) { try $0.getInt64(index: 0) } == 2)

        try await database.close(deleteDatabase: false)
        let encryptedBytes = try Data(contentsOf: fixture.databaseURL)
        #expect(!String(decoding: encryptedBytes, as: UTF8.self).contains("Verify lighting"))
        let reopened = try fixture.open()
        let reopenedStore = Self.store(reopened)
        let recovered = try await reopenedStore.rejectedOperations(request)
        #expect(recovered == beforeRestart)

        var watch = reopenedStore.watchRejectedOperations(request).makeAsyncIterator()
        #expect(try await watch.next() == recovered)
        await reopenedStore.cancelAndDrainWatches()
        do {
            #expect(try await watch.next() == nil)
        } catch is CancellationError {
            // An admitted recovery watch may terminate with cancellation while draining.
        }
        var refused = reopenedStore.watchRejectedOperations(request).makeAsyncIterator()
        #expect(try await refused.next() == nil)
        try await reopened.close(deleteDatabase: true)
        fixture.remove()
    }

    @MainActor
    @Test("A fresh coordinator and editor recover the exact rejected draft after encrypted restart")
    func rejectedRecoveryReachesFreshEditorAfterRestart() async throws {
        let fixture = try ChecklistRevisionDatabaseFixture()
        let database = try fixture.open()
        try await Self.seedAuthority(database)
        let command = try Self.command(id: "second")
        _ = try await Self.store(database).reviseChecklists(command)
        try await Self.connector(
            applier: ChecklistRevisionResultApplier(
                phase: "rejected",
                errorCode: "space_checklist_revision_conflict"
            )
        ).uploadData(database: database)
        #expect(try await Self.crudCount(database) == 0)

        try await database.close(deleteDatabase: false)
        let reopened = try fixture.open()
        let reopenedStore = Self.store(reopened)
        let request = try SpaceCoreDetailsRequest(
            accountId: Self.accountId,
            spaceId: Self.spaceId
        )
        let rows = try await PowerSyncSpaceCoreDetailsLocalReader(
            database: reopened
        ).readRows(request: request, principalId: Self.principalId)
        let snapshot = try SpaceCoreDetailsPowerSyncQuery.localSnapshot(
            request: request,
            rows: rows,
            streamCompletionReported: true,
            hasLastSyncedAt: true,
            asOf: Self.asOf
        )
        let update = try SpaceCoreDetailsUpdate(
            request: request,
            state: .snapshot(snapshot)
        )
        let coordinator = SpaceChecklistItemToggleStagingExercise(
            accountId: Self.accountId,
            actorPrincipalId: Self.principalId,
            operationContractVersion: command.envelope.contractVersion,
            makeIdentity: {
                SpaceChecklistItemToggleSubmissionIdentity(
                    operationId: try SpaceChecklistRevisionOperationIdentity.make(
                        accountId: Self.accountId,
                        uuid: UUID(uuidString: "99999999-9999-4999-8999-999999999999")!
                    )
                )
            },
            now: { Self.asOf }
        )
        let editor = SpaceChecklistEditorStagingExercise(
            coordinator: coordinator,
            makeChecklistId: { try SpaceChecklistID(validating: "unused-checklist") },
            makeItemId: { try SpaceChecklistItemID(validating: "unused-item") }
        )
        let runtime = SpaceChecklistItemToggleStagingRuntime(
            reviseChecklists: { try await reopenedStore.reviseChecklists($0) },
            watchOperation: { reopenedStore.watchOperation($0) },
            rejectedOperations: { try await reopenedStore.rejectedOperations($0) },
            watchRejectedOperations: { reopenedStore.watchRejectedOperations($0) }
        )

        await coordinator.start(runtime: runtime)
        await editor.start()
        await coordinator.receiveDetailUpdate(update, selectedSpaceId: Self.spaceId)
        await editor.receiveDetailUpdate(update, selectedSpaceId: Self.spaceId)
        for _ in 0..<200 where !coordinator.isRejectedRecoveryReady {
            await Task.yield()
        }

        #expect(coordinator.isRejectedRecoveryReady)
        #expect(coordinator.rejectedRecovery?.operationId == command.envelope.operationId)
        #expect(coordinator.rejectedRecoveryCollection == command.draft.collection)
        #expect(!coordinator.canSubmitCompleteDraft)
        #expect(editor.canReviewPreservedConflict)

        editor.reviewPreservedConflict()
        #expect(editor.isReviewingRejectedDraft)
        #expect(editor.checklists.first?.name == "Installation")
        #expect(editor.checklists.first?.items.first?.text == "Verify lighting")
        #expect(!editor.canMutateDraft)
        #expect(!editor.canSave)
        editor.renameChecklist(
            id: try SpaceChecklistID(validating: "installation"),
            name: "Must remain unchanged"
        )
        #expect(editor.checklists.first?.name == "Installation")

        editor.cancel()
        #expect(!editor.isPresented)
        #expect(editor.canReviewPreservedConflict)
        #expect(coordinator.rejectedRecovery?.operationId == command.envelope.operationId)
        #expect(try await Self.crudCount(reopened) == 0)

        await editor.stop()
        await coordinator.stop()
        await reopenedStore.cancelAndDrainWatches()
        try await reopened.close(deleteDatabase: true)
        fixture.remove()
    }

    @Test("Recovery is exactly scoped to Principal, Account, Space, family, and contract")
    func rejectedRecoveryExactScope() async throws {
        let fixture = try ChecklistRevisionDatabaseFixture()
        let database = try fixture.open()
        try await Self.seedAuthority(database)
        let command = try Self.command(id: "first")
        _ = try await Self.store(database).reviseChecklists(command)
        try await Self.connector(
            applier: ChecklistRevisionResultApplier(
                phase: "rejected",
                errorCode: "space_checklist_revision_conflict"
            )
        ).uploadData(database: database)
        let store = Self.store(database)

        let pendingCommand = try Self.command(id: "second", collection: Self.uncheckedCollection)
        _ = try await store.reviseChecklists(pendingCommand)
        #expect(try await store.rejectedOperations(Self.recoveryRequest()).candidates.map(\.operationId) == [
            command.envelope.operationId
        ])

        let wrongAccount = try RejectedOperationRecoveryRequest(
            accountId: AccountID(validating: "another-account"),
            actorPrincipalId: Self.principalId,
            family: .reviseSpaceChecklists,
            expectedContractVersion: OperationContractVersion(
                validating: "space-checklist-revision-v1"
            ),
            subject: command.subject
        )
        await #expect(throws: LedgerOfflineClientRuntimeFailure.accountScopeMismatch) {
            _ = try await store.rejectedOperations(wrongAccount)
        }

        let otherSpace = try RejectedOperationRecoveryRequest(
            accountId: Self.accountId,
            actorPrincipalId: Self.principalId,
            family: .reviseSpaceChecklists,
            expectedContractVersion: OperationContractVersion(
                validating: "space-checklist-revision-v1"
            ),
            subject: LedgerEntityReference(
                kind: .space,
                id: EntityID(validating: "another-space")
            )
        )
        #expect(try await store.rejectedOperations(otherSpace).candidates.isEmpty)

        let wrongContract = try Self.recoveryRequest(
            contract: "space-checklist-revision-v2"
        )
        await #expect(throws: RejectedOperationRecoveryFailure.localEvidenceMalformed) {
            _ = try await store.rejectedOperations(wrongContract)
        }

        let wrongPrincipal = try RejectedOperationRecoveryRequest(
            accountId: Self.accountId,
            actorPrincipalId: PrincipalID(validating: "another-principal"),
            family: .reviseSpaceChecklists,
            expectedContractVersion: OperationContractVersion(
                validating: "space-checklist-revision-v1"
            ),
            subject: command.subject
        )
        await #expect(throws: LedgerOfflineClientRuntimeFailure.principalScopeMismatch) {
            _ = try await store.rejectedOperations(wrongPrincipal)
        }

        await store.cancelAndDrainWatches()
        try await database.close(deleteDatabase: true)
        fixture.remove()
    }

    @Test("Malformed persisted command or terminal integrity fails recovery closed")
    func rejectedRecoveryCorruptionFailsClosed() async throws {
        for corruption in ["fingerprint", "request_hash", "envelope"] {
            let fixture = try ChecklistRevisionDatabaseFixture()
            let database = try fixture.open()
            try await Self.seedAuthority(database)
            let command = try Self.command(id: "first")
            _ = try await Self.store(database).reviseChecklists(command)
            try await Self.connector(
                applier: ChecklistRevisionResultApplier(
                    phase: "rejected",
                    errorCode: "space_checklist_revision_conflict"
                )
            ).uploadData(database: database)
            switch corruption {
            case "fingerprint":
                _ = try await database.execute(
                    sql: "UPDATE spike_local_operations SET fingerprint = ? WHERE id = ?",
                    parameters: [String(repeating: "0", count: 64), command.envelope.operationId.rawValue]
                )
            case "request_hash":
                _ = try await database.execute(
                    sql: "UPDATE spike_local_operations SET terminal_request_sha256 = ? WHERE id = ?",
                    parameters: [String(repeating: "0", count: 64), command.envelope.operationId.rawValue]
                )
            default:
                _ = try await database.execute(
                    sql: "UPDATE spike_local_operations SET command_envelope_json = '{}' WHERE id = ?",
                    parameters: [command.envelope.operationId.rawValue]
                )
            }
            await #expect(throws: RejectedOperationRecoveryFailure.localEvidenceMalformed) {
                _ = try await Self.store(database).rejectedOperations(
                    Self.recoveryRequest()
                )
            }
            try await database.close(deleteDatabase: true)
            fixture.remove()
        }
    }

    @Test("Operation watches cancel and drain, and strict result validation rejects malformed terminals")
    func cancellationDrainAndStrictResultValidation() async throws {
        let fixture = try ChecklistRevisionDatabaseFixture()
        let database = try fixture.open()
        try await Self.seedAuthority(database)
        let command = try Self.command(id: "drain")
        let store = Self.store(database)
        _ = try await store.reviseChecklists(command)

        var iterator = store.watchOperation(command.envelope.operationId).makeAsyncIterator()
        #expect(try await iterator.next()?.operationId == command.envelope.operationId)
        await store.cancelAndDrainWatches()
        do {
            #expect(try await iterator.next() == nil)
        } catch is CancellationError {
            // An admitted watch may surface cancellation while it drains.
        }
        var refused = store.watchOperation(command.envelope.operationId).makeAsyncIterator()
        #expect(try await refused.next() == nil)
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await store.reviseChecklists(command)
        }

        let transaction = try #require(try await database.getNextCrudTransaction())
        let request = try LedgerPowerSyncUploadConnector.spaceChecklistRevisionRequest(
            from: transaction.crud
        )
        #expect(LedgerPowerSyncUploadConnector.isValidSpaceChecklistRevisionResult(
            ChecklistRevisionResultApplier.result(request, phase: "applied"),
            request: request
        ))
        #expect(!LedgerPowerSyncUploadConnector.isValidSpaceChecklistRevisionResult(
            ChecklistRevisionResultApplier.result(
                request,
                phase: "rejected",
                errorCode: "unknown_code"
            ),
            request: request
        ))
        var wrongHash = ChecklistRevisionResultApplier.result(request, phase: "applied")
        wrongHash = SpaceChecklistRevisionServerResult(
            operationId: wrongHash.operationId,
            accountId: wrongHash.accountId,
            actorPrincipalId: wrongHash.actorPrincipalId,
            commandType: wrongHash.commandType,
            contractVersion: wrongHash.contractVersion,
            commandFingerprint: wrongHash.commandFingerprint,
            envelopeSHA256: wrongHash.envelopeSHA256,
            requestSHA256: String(repeating: "0", count: 64),
            subjectId: wrongHash.subjectId,
            phase: wrongHash.phase,
            resultCode: wrongHash.resultCode,
            errorCode: wrongHash.errorCode,
            clientCreatedAtMilliseconds: wrongHash.clientCreatedAtMilliseconds,
            serverReceivedAtMilliseconds: wrongHash.serverReceivedAtMilliseconds,
            completedAtMilliseconds: wrongHash.completedAtMilliseconds
        )
        #expect(!LedgerPowerSyncUploadConnector.isValidSpaceChecklistRevisionResult(
            wrongHash,
            request: request
        ))

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChecklistRevisionRecordingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            ChecklistRevisionRecordingURLProtocol.handler = nil
        }
        ChecklistRevisionRecordingURLProtocol.handler = { urlRequest in
            #expect(
                urlRequest.url?.path ==
                    "/rest/v1/rpc/spike_revise_space_checklists"
            )
            #expect(
                urlRequest.value(forHTTPHeaderField: "apikey") ==
                    "publishable-key"
            )
            #expect(
                urlRequest.value(forHTTPHeaderField: "Authorization") ==
                    "Bearer user-token"
            )
            let body = try checklistRevisionRequestBody(urlRequest)
            let json = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            #expect(Set(json.keys) == [
                "p_operation_id", "p_account_id", "p_actor_principal_id",
                "p_contract_version", "p_space_captured_at", "p_space_id",
                "p_expected_revision", "p_collection", "p_fingerprint",
                "p_envelope_json"
            ])
            #expect(json["p_operation_id"] as? String == request.operationId)
            #expect(json["p_account_id"] as? String == request.accountId)
            #expect(json["p_actor_principal_id"] as? String == request.actorPrincipalId)
            #expect(json["p_space_id"] as? String == request.spaceId)
            #expect(json["p_expected_revision"] as? String == request.expectedRevision)
            #expect(json["p_collection"] as? [String: Any] != nil)
            let response = try #require(HTTPURLResponse(
                url: urlRequest.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return (
                response,
                try JSONEncoder().encode(
                    ChecklistRevisionResultApplier.result(request, phase: "applied")
                )
            )
        }
        let rpc = try SupabaseSpaceChecklistRevisionRPC(
            supabaseURL: URL(string: "https://target.invalid")!,
            publishableKey: "publishable-key",
            accessTokenProvider: { "user-token" },
            session: session
        )
        #expect(try await rpc.apply(request).resultCode == "space_checklists_revised")
        #expect(throws: SupabaseSpaceChecklistRevisionRPCFailure.serviceRoleCredentialRefused) {
            _ = try SupabaseSpaceChecklistRevisionRPC(
                supabaseURL: URL(string: "https://target.invalid")!,
                publishableKey: "sb_secret_never-allowed",
                accessTokenProvider: { "unused" }
            )
        }

        try await database.close(deleteDatabase: true)
        fixture.remove()
    }

    private static let accountId = try! AccountID(validating: "checklist-account")
    private static let principalId = try! PrincipalID(validating: "checklist-principal")
    private static let projectId = try! ProjectID(validating: "checklist-project")
    private static let spaceId = try! SpaceID(validating: "checklist-space")
    private static let capturedAt = Date(timeIntervalSince1970: 1_789_000_000)
    private static let acceptedAt = Date(timeIntervalSince1970: 1_789_000_001)
    private static let asOf = Date(timeIntervalSince1970: 1_789_000_002)

    private static let uncheckedCollection = try! collection(checked: false)
    private static let checkedCollection = try! collection(checked: true)

    private static func collection(checked: Bool) throws -> SpaceChecklistCollection {
        try SpaceChecklistCollection(checklists: [
            SpaceChecklistState(
                id: SpaceChecklistID(validating: "installation"),
                name: SpaceChecklistName(validating: "Installation"),
                presentationOrder: 0,
                items: [
                    SpaceChecklistItemState(
                        id: SpaceChecklistItemID(validating: "verify-lighting"),
                        text: SpaceChecklistItemText(validating: "Verify lighting"),
                        isChecked: checked,
                        presentationOrder: 0
                    )
                ]
            )
        ])
    }

    private static func command(
        id: String,
        revision: UInt64 = 7,
        collection: SpaceChecklistCollection = checkedCollection
    ) throws -> ReviseSpaceChecklistsCommand {
        try command(
            operationId: SpaceChecklistRevisionOperationIdentity.make(
                accountId: accountId,
                uuid: UUID(uuidString: Self.uuid(for: id))!
            ),
            revision: revision,
            collection: collection
        )
    }

    private static func command(
        operationId: OperationID,
        revision: UInt64 = 7,
        collection: SpaceChecklistCollection = checkedCollection
    ) throws -> ReviseSpaceChecklistsCommand {
        try ReviseSpaceChecklistsCommand(
            operationId: operationId,
            draft: SpaceChecklistRevisionDraft(
                accountId: accountId,
                actorPrincipalId: principalId,
                operationContractVersion: OperationContractVersion(
                    validating: "space-checklist-revision-v1"
                ),
                spaceId: spaceId,
                collection: collection,
                expectedRevision: ExpectedSpaceRevision(revision),
                capturedAt: capturedAt
            )
        )
    }

    private static func uuid(for id: String) -> String {
        let byte = id == "first" ? "11" : id == "second" ? "22" : id == "drain" ? "33" : id == "interrupted" ? "44" : "55"
        return "\(byte)\(byte)\(byte)\(byte)-\(byte)\(byte)-4\(byte.dropFirst())\(byte)-8\(byte.dropFirst())\(byte)-\(byte)\(byte)\(byte)\(byte)\(byte)\(byte)"
    }

    private static func store(
        _ database: any PowerSyncDatabaseProtocol
    ) -> SpaceChecklistRevisionPowerSyncStore {
        SpaceChecklistRevisionPowerSyncStore(
            database: database,
            accountId: accountId,
            principalId: principalId,
            now: { acceptedAt }
        )
    }

    private static func recoveryRequest(
        contract: String = "space-checklist-revision-v1"
    ) throws -> RejectedOperationRecoveryRequest {
        try RejectedOperationRecoveryRequest(
            accountId: accountId,
            actorPrincipalId: principalId,
            family: .reviseSpaceChecklists,
            expectedContractVersion: OperationContractVersion(validating: contract),
            subject: LedgerEntityReference(
                kind: .space,
                id: EntityID(validating: spaceId.rawValue)
            )
        )
    }

    private static func connector(
        applier: any SpaceChecklistRevisionCommandApplying,
        now: Date = asOf
    ) -> LedgerPowerSyncUploadConnector {
        LedgerPowerSyncUploadConnector(
            accessFence: LedgerWorkspaceAccessFence(),
            credentialProvider: { nil },
            clientCreationApplier: ChecklistRevisionUnusedClientApplier(),
            spaceChecklistRevisionApplier: applier,
            now: { now }
        )
    }

    private static func projectedSnapshot(
        command: ReviseSpaceChecklistsCommand,
        authoritativeRevision: Int64,
        authoritativeChecked: Bool,
        operationState: String
    ) throws -> SpaceCoreDetailsLocalSnapshot {
        let collectionJSON = collectionJSON(command.draft.collection)
        let acceptedMilliseconds = Int64(acceptedAt.timeIntervalSince1970 * 1_000)
        let row = SpaceCoreDetailsPowerSyncRow(
            scopeIsActive: 1,
            visibleCount: 1,
            spaceId: spaceId.rawValue,
            accountId: accountId.rawValue,
            scopeKind: "project",
            projectId: projectId.rawValue,
            displayName: "Kitchen",
            lifecycle: "active",
            revision: authoritativeRevision,
            detailId: spaceId.rawValue,
            detailAccountId: accountId.rawValue,
            notes: "Confirm every fixture",
            createdAtMilliseconds: Int64(capturedAt.timeIntervalSince1970 * 1_000),
            updatedAtMilliseconds: acceptedMilliseconds,
            checklistRowId: "checklist-row",
            checklistAccountId: accountId.rawValue,
            checklistSpaceId: spaceId.rawValue,
            checklistId: "installation",
            checklistName: "Installation",
            checklistOrder: 0,
            itemRowId: "item-row",
            itemAccountId: accountId.rawValue,
            itemSpaceId: spaceId.rawValue,
            itemChecklistId: "installation",
            itemId: "verify-lighting",
            itemText: "Verify lighting",
            itemIsChecked: authoritativeChecked ? 1 : 0,
            itemOrder: 0,
            overlayOperationId: command.envelope.operationId.rawValue,
            overlayAccountId: accountId.rawValue,
            overlayActorPrincipalId: principalId.rawValue,
            overlaySpaceId: spaceId.rawValue,
            overlayFingerprint: command.fingerprint.sha256,
            overlayExpectedRevision: String(command.draft.expectedRevision.rawValue),
            overlayProjectedRevision: Int64(command.draft.expectedRevision.rawValue) + 1,
            overlayCollectionJSON: collectionJSON,
            overlayAcceptedAtMilliseconds: acceptedMilliseconds,
            overlayOperationAccountId: accountId.rawValue,
            overlayOperationActorPrincipalId: principalId.rawValue,
            overlayOperationContractVersion: command.envelope.contractVersion.rawValue,
            overlayOperationFingerprint: command.fingerprint.sha256,
            overlayOperationSubjectId: spaceId.rawValue,
            overlayOperationLocalState: operationState,
            overlayOperationCommandType: "revise_space_checklists",
            overlayOperationExpectedRevision: String(command.draft.expectedRevision.rawValue)
        )
        return try SpaceCoreDetailsPowerSyncQuery.localSnapshot(
            request: SpaceCoreDetailsRequest(accountId: accountId, spaceId: spaceId),
            rows: [row],
            streamCompletionReported: false,
            hasLastSyncedAt: true,
            asOf: asOf
        )
    }

    private static func collectionJSON(_ collection: SpaceChecklistCollection) -> String {
        String(decoding: try! OperationContractCodec.encode(collection), as: UTF8.self)
    }

    private static func seedAuthority(
        _ database: any PowerSyncDatabaseProtocol
    ) async throws {
        let capturedMilliseconds = Int64(capturedAt.timeIntervalSince1970 * 1_000)
        _ = try await database.execute(sql: """
            INSERT INTO spike_account_memberships
              (id, account_id, principal_id, role, state, can_manage_clients,
               can_manage_projects, can_manage_project_budgets, financial_access)
            VALUES ('membership', ?, ?, 'owner', 'active', 1, 1, 1, 'full')
            """, parameters: [accountId.rawValue, principalId.rawValue])
        _ = try await database.execute(sql: """
            INSERT INTO spike_spaces
              (id, account_id, scope_kind, project_id, display_name, lifecycle, revision)
            VALUES (?, ?, 'project', ?, 'Kitchen', 'active', 7)
            """, parameters: [spaceId.rawValue, accountId.rawValue, projectId.rawValue])
        _ = try await database.execute(sql: """
            INSERT INTO spike_space_core_details
              (id, account_id, notes, created_at_ms, updated_at_ms)
            VALUES (?, ?, 'Confirm every fixture', ?, ?)
            """, parameters: [
                spaceId.rawValue, accountId.rawValue,
                capturedMilliseconds, capturedMilliseconds
            ])
        _ = try await database.execute(sql: """
            INSERT INTO spike_space_checklists
              (id, account_id, space_id, checklist_id, name, presentation_order)
            VALUES ('checklist-row', ?, ?, 'installation', 'Installation', 0)
            """, parameters: [accountId.rawValue, spaceId.rawValue])
        _ = try await database.execute(sql: """
            INSERT INTO spike_space_checklist_items
              (id, account_id, space_id, checklist_id, item_id, item_text,
               is_checked, presentation_order)
            VALUES ('item-row', ?, ?, 'installation', 'verify-lighting',
                    'Verify lighting', 0, 0)
            """, parameters: [accountId.rawValue, spaceId.rawValue])
        try await drainCRUD(database)
    }

    private static func firstOperation(
        _ command: ReviseSpaceChecklistsCommand,
        _ database: any PowerSyncDatabaseProtocol
    ) async throws -> OperationSnapshot {
        let store = Self.store(database)
        var iterator = store.watchOperation(command.envelope.operationId).makeAsyncIterator()
        do {
            let snapshot = try #require(try await iterator.next())
            await store.cancelAndDrainWatches()
            return snapshot
        } catch {
            await store.cancelAndDrainWatches()
            throw error
        }
    }

    private static func localState(
        _ command: ReviseSpaceChecklistsCommand,
        _ database: any PowerSyncDatabaseProtocol
    ) async throws -> String {
        try await database.get(
            sql: "SELECT local_state FROM spike_local_operations WHERE id = ?",
            parameters: [command.envelope.operationId.rawValue]
        ) { try $0.getString(index: 0) }
    }

    private static func pendingEvidenceCount(
        _ database: any PowerSyncDatabaseProtocol
    ) async throws -> Int64 {
        try await count(LedgerPowerSyncTable.localOperations, database)
            + count(LedgerPowerSyncTable.spaceChecklistRevisionOverlays, database)
            + crudCount(database)
    }

    private static func count(
        _ table: String,
        _ database: any PowerSyncDatabaseProtocol
    ) async throws -> Int64 {
        try await database.get("SELECT count(*) FROM \(table)") {
            try $0.getInt64(index: 0)
        }
    }

    private static func crudCount(
        _ database: any PowerSyncDatabaseProtocol
    ) async throws -> Int64 {
        try await database.get("SELECT count(*) FROM ps_crud") {
            try $0.getInt64(index: 0)
        }
    }

    private static func overlayOperationIds(
        _ database: any PowerSyncDatabaseProtocol
    ) async throws -> [String] {
        try await database.getAll(
            sql: "SELECT operation_id FROM spike_space_checklist_revision_overlays ORDER BY operation_id",
            parameters: nil
        ) { try $0.getString(index: 0) }
    }

    private static func drainCRUD(
        _ database: any PowerSyncDatabaseProtocol
    ) async throws {
        while let transaction = try await database.getNextCrudTransaction() {
            try await transaction.complete()
        }
    }
}

private final class ChecklistRevisionDatabaseFixture: @unchecked Sendable {
    let databaseURL: URL
    private let directoryURL: URL
    private let key = try! LedgerPowerSyncEncryptionKey(
        hexadecimal: String(repeating: "73", count: 32)
    )

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ledger-space-checklist-revision-\(UUID().uuidString)"
        )
        databaseURL = directoryURL.appendingPathComponent("ledger.sqlite")
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    func open() throws -> any PowerSyncDatabaseProtocol {
        try LedgerPowerSyncDatabaseFactory.open(
            absolutePath: databaseURL.path,
            encryptionKey: key
        )
    }

    func remove() { try? FileManager.default.removeItem(at: directoryURL) }
}

private struct ChecklistRevisionInjectedFailure: Error {}

private final class ChecklistRevisionRecordingURLProtocol:
    URLProtocol, @unchecked Sendable
{
    nonisolated(unsafe) static var handler:
        ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw ChecklistRevisionInjectedFailure()
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func checklistRevisionRequestBody(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody { return body }
    let stream = try #require(request.httpBodyStream)
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 {
            throw stream.streamError ?? ChecklistRevisionInjectedFailure()
        }
        if count == 0 { break }
        data.append(buffer, count: count)
    }
    return data
}

private struct ChecklistRevisionUnusedClientApplier: ClientCreationCommandApplying {
    func apply(
        _ request: ClientCreationUploadRequest
    ) async throws -> ClientCreationServerResult {
        throw ChecklistRevisionInjectedFailure()
    }
}

private struct ChecklistRevisionTransientApplier: SpaceChecklistRevisionCommandApplying {
    func apply(
        _ request: SpaceChecklistRevisionUploadRequest
    ) async throws -> SpaceChecklistRevisionServerResult {
        throw ChecklistRevisionInjectedFailure()
    }
}

private struct ChecklistRevisionResultApplier: SpaceChecklistRevisionCommandApplying {
    let phase: String
    let errorCode: String?

    init(phase: String, errorCode: String? = nil) {
        self.phase = phase
        self.errorCode = errorCode
    }

    func apply(
        _ request: SpaceChecklistRevisionUploadRequest
    ) async throws -> SpaceChecklistRevisionServerResult {
        Self.result(request, phase: phase, errorCode: errorCode)
    }

    static func result(
        _ request: SpaceChecklistRevisionUploadRequest,
        phase: String,
        errorCode: String? = nil
    ) -> SpaceChecklistRevisionServerResult {
        SpaceChecklistRevisionServerResult(
            operationId: request.operationId,
            accountId: request.accountId,
            actorPrincipalId: request.actorPrincipalId,
            commandType: "revise_space_checklists",
            contractVersion: request.contractVersion,
            commandFingerprint: request.fingerprint,
            envelopeSHA256: request.fingerprint,
            requestSHA256: LedgerPowerSyncUploadConnector
                .spaceChecklistRevisionRequestSHA256(request),
            subjectId: request.spaceId,
            phase: phase,
            resultCode: phase == "applied" ? "space_checklists_revised" : nil,
            errorCode: phase == "rejected" ? errorCode : nil,
            clientCreatedAtMilliseconds: request.clientCreatedAtMilliseconds,
            serverReceivedAtMilliseconds: request.clientCreatedAtMilliseconds + 1_000,
            completedAtMilliseconds: request.clientCreatedAtMilliseconds + 2_000
        )
    }
}
