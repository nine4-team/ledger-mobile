import Foundation
import LedgerTargetCore
import PowerSync
import Testing

@testable import LedgerTargetPowerSync

@Suite("Account workspace pending-work runtime", .serialized)
struct AccountWorkspacePendingWorkRuntimeTests {
    @Test("WORKRUNTIME-TEST-001 exact composition returns clean and all pending classes")
    func exactCompositionAndPendingClasses() async throws {
        let cleanContext = try RuntimeTestContext(suffix: "clean")
        let cleanRecorder = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        let cleanRuntime = try await cleanContext.openRuntime(events: cleanRecorder)
        let clean = try await cleanRuntime.pendingWorkSummary()
        #expect(clean.environment == .targetLocal)
        #expect(clean.principalId == cleanContext.principalId)
        #expect(clean.accountId == cleanContext.accountId)
        #expect(clean.queuedOperationCount == 0)
        #expect(clean.applyingOperationCount == 0)
        #expect(clean.unresolvedRejectedOperationCount == 0)
        #expect(clean.unverifiedAttachmentCount == 0)
        Self.expectExactConstructionCounts(cleanRecorder.values)
        try await cleanRuntime.close()
        cleanContext.remove()

        let context = try RuntimeTestContext(suffix: "all-classes")
        let recorder = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        var dependencies = context.dependencies(events: recorder)
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            try await Self.insertOperation(database, id: "operation-applying", state: .applying)
            try await Self.insertOperation(database, id: "operation-rejected", state: .rejected)
        }
        let runtime = try await context.openRuntime(
            dependencies: dependencies
        )
        _ = try await runtime.createClient(context.clientCommand(id: "queued"))
        let capture = try context.capture(id: "attachment-all-classes")
        let receipt = try await runtime.captureAttachment(capture)
        #expect(receipt.attachmentId == capture.attachmentId)

        let summary = try await runtime.pendingWorkSummary()
        #expect(summary.queuedOperationCount == 1)
        #expect(summary.applyingOperationCount == 1)
        #expect(summary.unresolvedRejectedOperationCount == 1)
        #expect(summary.unverifiedAttachmentCount == 1)
        Self.expectExactConstructionCounts(recorder.values)
        try await runtime.close()
        context.remove()
    }

    @Test("WORKRUNTIME-TEST-002 invalid scope and equal keys refuse before storage")
    func invalidScopeAndEqualKeysRefuseBeforeStorage() async throws {
        let invalid = try RuntimeTestContext(suffix: "invalid-scope", namespace: "../escape")
        let invalidRecorder = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        do {
            _ = try await invalid.openRuntime(events: invalidRecorder)
            Issue.record("Expected invalid namespace failure")
        } catch let failure as LedgerPowerSyncLocalBootstrapFailure {
            #expect(failure.stage == .workspaceLocationResolution)
            #expect(failure.attachmentDatabaseCleanup == .notOpened)
            #expect(failure.structuredDatabaseCleanup == .notOpened)
        }
        #expect(invalidRecorder.values.isEmpty)

        let equal = try RuntimeTestContext(suffix: "equal-keys")
        let equalRecorder = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        var dependencies = equal.dependencies(events: equalRecorder)
        dependencies.loadMediaKeyBytes = { _, _ in Data(repeating: 0x1a, count: 32) }
        do {
            _ = try await equal.openRuntime(dependencies: dependencies)
            Issue.record("Expected equal key values to refuse bootstrap")
        } catch let failure as LedgerPowerSyncLocalBootstrapFailure {
            #expect(failure.stage == .keyValidation)
            #expect(failure.attachmentDatabaseCleanup == .notOpened)
            #expect(failure.structuredDatabaseCleanup == .notOpened)
        }
        #expect(!FileManager.default.fileExists(atPath: equal.root.path))

        let scoped = try RuntimeTestContext(suffix: "cross-scope")
        let scopedRuntime = try await scoped.openRuntime()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.accountScopeMismatch) {
            _ = try await scopedRuntime.createClient(
                scoped.clientCommand(
                    id: "wrong-account",
                    accountId: AccountID(validating: "account-other")
                )
            )
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.principalScopeMismatch) {
            _ = try await scopedRuntime.createProject(
                scoped.projectCommand(
                    id: "wrong-principal",
                    principalId: PrincipalID(validating: "principal-other")
                )
            )
        }
        await #expect(throws: AttachmentCapturePowerSyncStoreFailure.scopeMismatch) {
            _ = try await scopedRuntime.captureAttachment(
                scoped.capture(
                    id: "attachment-cross-scope",
                    accountId: AccountID(validating: "account-other")
                )
            )
        }
        let scopedSummary = try await scopedRuntime.pendingWorkSummary()
        #expect(scopedSummary.unverifiedAttachmentCount == 0)
        try await scopedRuntime.close()
        scoped.remove()
    }

    @Test("WORKRUNTIME-TEST-003 paths and keys isolate while database key bytes match")
    func locationsAndKeySeparation() async throws {
        let context = try RuntimeTestContext(suffix: "key-capture")
        let keyRecorder = LockedRecorder<String>()
        var dependencies = context.dependencies()
        let openStructured = dependencies.openStructuredDatabase
        let openAttachment = dependencies.openAttachmentDatabase
        dependencies.openStructuredDatabase = { path, key in
            keyRecorder.append(
                "structured:\(key.hexadecimal):\(URL(fileURLWithPath: path).lastPathComponent)")
            return try openStructured(path, key)
        }
        dependencies.openAttachmentDatabase = { path, key in
            keyRecorder.append(
                "attachment:\(key.hexadecimal):\(URL(fileURLWithPath: path).lastPathComponent)")
            return try openAttachment(path, key)
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        #expect(
            keyRecorder.values == [
                "structured:\(context.databaseKey.hexadecimal):ledger.sqlite",
                "attachment:\(context.databaseKey.hexadecimal):attachments.sqlite",
            ])

        let location = try context.location()
        #expect(
            location.structuredDatabaseURL.deletingLastPathComponent()
                == location.attachmentDatabaseURL.deletingLastPathComponent())
        #expect(
            location.mediaVaultRootURL.deletingLastPathComponent()
                == location.structuredDatabaseURL.deletingLastPathComponent())
        #expect(location.databaseKeychainService == "ledger.target.powersync.workspace-key.v1")
        #expect(location.databaseKeychainService != location.mediaKeychainService)
        #expect(!location.structuredDatabaseURL.path.contains(context.principalId.rawValue))
        #expect(!location.structuredDatabaseURL.path.contains(context.accountId.rawValue))
        try await runtime.close()

        let otherPrincipal = try context.location(
            principalId: PrincipalID(validating: "principal-other")
        )
        let otherAccount = try context.location(accountId: AccountID(validating: "account-other"))
        #expect(otherPrincipal.structuredDatabaseURL != location.structuredDatabaseURL)
        #expect(otherPrincipal.attachmentDatabaseURL != location.attachmentDatabaseURL)
        #expect(otherPrincipal.mediaVaultRootURL != location.mediaVaultRootURL)
        #expect(otherAccount.structuredDatabaseURL != location.structuredDatabaseURL)
        #expect(otherAccount.databaseKeychainAccount != location.databaseKeychainAccount)
        #expect(otherAccount.mediaKeychainAccount != location.mediaKeychainAccount)
        context.remove()
    }

    @Test("WORKRUNTIME-TEST-004 close and reopen preserve summary, receipt, and evidence revision")
    func closeReopenAndEqualCountReplacement() async throws {
        let context = try RuntimeTestContext(suffix: "restart")
        let first = try await context.openRuntime()
        _ = try await first.createClient(context.clientCommand(id: "restart-a"))
        let capture = try context.capture(id: "attachment-restart")
        let receipt = try await first.captureAttachment(capture)
        let initial = try await first.pendingWorkSummary()
        try await first.close()

        let reopened = try await context.openRuntime()
        let replayed = try await reopened.captureAttachment(capture)
        let unchanged = try await reopened.pendingWorkSummary()
        #expect(replayed == receipt)
        #expect(unchanged == initial)
        try await reopened.close()

        var changedDependencies = context.dependencies()
        let validate = changedDependencies.validateStructuredDatabase
        changedDependencies.validateStructuredDatabase = { database in
            try await validate(database)
            _ = try await database.execute(
                sql: "DELETE FROM \(LedgerPowerSyncTable.localOperations) WHERE id = ?",
                parameters: ["operation-runtime-restart-a"]
            )
            try await Self.insertOperation(
                database,
                id: "operation-replacement",
                state: .queued,
                timestamp: 9
            )
        }
        let changedRuntime = try await context.openRuntime(dependencies: changedDependencies)
        let changed = try await changedRuntime.pendingWorkSummary()
        #expect(changed.queuedOperationCount == initial.queuedOperationCount)
        #expect(changed.unverifiedAttachmentCount == initial.unverifiedAttachmentCount)
        #expect(changed.snapshotRevision == initial.snapshotRevision + 1)
        #expect(changed.fingerprint != initial.fingerprint)
        try await changedRuntime.close()
        context.remove()
    }

    @Test("WORKRUNTIME-TEST-005 every staged bootstrap failure closes opened stores in order")
    func stagedBootstrapCleanupMatrix() async throws {
        let cases:
            [(
                LedgerPowerSyncLocalBootstrapStage,
                LedgerPowerSyncLocalCleanupOutcome,
                LedgerPowerSyncLocalCleanupOutcome
            )] = [
                (.databaseKeyLoad, .notOpened, .notOpened),
                (.mediaKeyLoad, .notOpened, .notOpened),
                (.keyValidation, .notOpened, .notOpened),
                (.directoryPreparation, .notOpened, .notOpened),
                (.structuredDatabaseOpen, .notOpened, .notOpened),
                (.structuredDatabaseValidation, .notOpened, .succeeded),
                (.attachmentDatabaseOpen, .notOpened, .succeeded),
                (.attachmentDatabaseValidation, .succeeded, .succeeded),
                (.mediaVaultOpen, .succeeded, .succeeded),
                (.attachmentStoreConstruction, .succeeded, .succeeded),
                (.pendingWorkQueryConstruction, .succeeded, .succeeded),
                (.runtimeConstruction, .succeeded, .succeeded),
            ]

        for (stage, expectedAttachment, expectedStructured) in cases {
            let context = try RuntimeTestContext(suffix: "stage-\(stage.rawValue)")
            let recorder = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
            let weakVault = WeakVaultRecorder()
            var dependencies = Self.faultedDependencies(
                stage: stage,
                context: context,
                recorder: recorder
            )
            let makeVault = dependencies.makeVault
            dependencies.makeVault = { root, scope, key in
                let vault = try makeVault(root, scope, key)
                weakVault.capture(vault)
                return vault
            }
            do {
                _ = try await context.openRuntime(dependencies: dependencies)
                Issue.record("Expected failure at \(stage.rawValue)")
            } catch let failure as LedgerPowerSyncLocalBootstrapFailure {
                #expect(failure.stage == stage)
                #expect(failure.attachmentDatabaseCleanup == expectedAttachment)
                #expect(failure.structuredDatabaseCleanup == expectedStructured)
            }
            let closeEvents = recorder.values.filter {
                $0 == .attachmentDatabaseCloseAttempted
                    || $0 == .structuredDatabaseCloseAttempted
            }
            let expectedEvents: [AccountWorkspaceRuntimeLifecycleEvent] =
                switch (
                    expectedAttachment,
                    expectedStructured
                ) {
                case (.notOpened, .notOpened): []
                case (.notOpened, _): [.structuredDatabaseCloseAttempted]
                default: [.attachmentDatabaseCloseAttempted, .structuredDatabaseCloseAttempted]
            }
            #expect(closeEvents == expectedEvents)
            if recorder.values.contains(.vaultConstructed) {
                #expect(weakVault.value == nil)
            }
            let recovered = try await context.openRuntime()
            _ = try await recovered.pendingWorkSummary()
            try await recovered.close()
            context.remove()
        }

        let dual = try RuntimeTestContext(suffix: "dual-bootstrap-cleanup")
        let dualRecorder = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        var dualDependencies = Self.faultedDependencies(
            stage: .runtimeConstruction,
            context: dual,
            recorder: dualRecorder
        )
        let openStructured = dualDependencies.openStructuredDatabase
        let openAttachment = dualDependencies.openAttachmentDatabase
        dualDependencies.openStructuredDatabase = { path, key in
            let opened = try openStructured(path, key)
            return AccountWorkspaceOpenedDatabase(
                database: opened.database,
                closePreservingData: {
                    try? await opened.closePreservingData()
                    throw RuntimeInjectedFailure()
                }
            )
        }
        dualDependencies.openAttachmentDatabase = { path, key in
            let opened = try openAttachment(path, key)
            return AccountWorkspaceOpenedDatabase(
                database: opened.database,
                closePreservingData: {
                    try? await opened.closePreservingData()
                    throw RuntimeInjectedFailure()
                }
            )
        }
        do {
            _ = try await dual.openRuntime(dependencies: dualDependencies)
            Issue.record("Expected dual cleanup failure")
        } catch let failure as LedgerPowerSyncLocalBootstrapFailure {
            #expect(failure.stage == .runtimeConstruction)
            #expect(failure.attachmentDatabaseCleanup == .failed)
            #expect(failure.structuredDatabaseCleanup == .failed)
        }
        #expect(
            dualRecorder.values.filter {
                $0 == .attachmentDatabaseCloseAttempted || $0 == .structuredDatabaseCloseAttempted
            }.suffix(2) == [.attachmentDatabaseCloseAttempted, .structuredDatabaseCloseAttempted])
        dual.remove()
    }

    @Test("WORKRUNTIME-TEST-006 wrong database and media keys never report false clean")
    func wrongKeysFailClosedIndependently() async throws {
        let context = try RuntimeTestContext(suffix: "wrong-keys")
        let capture = try context.capture(id: "attachment-wrong-key")
        let initial = try await context.openRuntime()
        _ = try await initial.createClient(context.clientCommand(id: "wrong-key"))
        _ = try await initial.captureAttachment(capture)
        try await initial.close()

        var wrongStructured = context.dependencies()
        wrongStructured.loadDatabaseKey = { _, _ in
            try LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "7b", count: 32))
        }
        do {
            _ = try await context.openRuntime(dependencies: wrongStructured)
            Issue.record("Expected wrong structured key failure")
        } catch let failure as LedgerPowerSyncLocalBootstrapFailure {
            #expect(failure.stage == .structuredDatabaseValidation)
            #expect(failure.attachmentDatabaseCleanup == .notOpened)
            #expect(failure.structuredDatabaseCleanup == .failed)
        }

        var wrongAttachment = context.dependencies()
        let openWrongAttachment = wrongAttachment.openAttachmentDatabase
        wrongAttachment.openAttachmentDatabase = { path, _ in
            try openWrongAttachment(
                path,
                LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "6c", count: 32))
            )
        }
        do {
            _ = try await context.openRuntime(dependencies: wrongAttachment)
            Issue.record("Expected wrong attachment database key failure")
        } catch let failure as LedgerPowerSyncLocalBootstrapFailure {
            #expect(failure.stage == .attachmentDatabaseValidation)
            #expect(failure.attachmentDatabaseCleanup == .failed)
            #expect(failure.structuredDatabaseCleanup == .succeeded)
        }

        var wrongMedia = context.dependencies()
        wrongMedia.loadMediaKeyBytes = { _, _ in Data(repeating: 0x55, count: 32) }
        do {
            _ = try await context.openRuntime(dependencies: wrongMedia)
            Issue.record("Expected wrong media key to refuse bootstrap")
        } catch let failure as LedgerPowerSyncLocalBootstrapFailure {
            #expect(failure.stage == .mediaVaultOpen)
            #expect(failure.attachmentDatabaseCleanup == .succeeded)
            #expect(failure.structuredDatabaseCleanup == .succeeded)
        }
        let recovered = try await context.openRuntime()
        let summary = try await recovered.pendingWorkSummary()
        #expect(summary.queuedOperationCount == 1)
        #expect(summary.unverifiedAttachmentCount == 1)
        #expect(try await recovered.captureAttachment(capture).attachmentId == capture.attachmentId)
        try await recovered.close()
        context.remove()
    }

    @Test("WORKRUNTIME-TEST-006 missing, corrupt, orphaned, and unavailable media stay explicit")
    func mediaAndObservationFailuresNeverBecomeClean() async throws {
        for mode in ["missing", "corrupt"] {
            let context = try RuntimeTestContext(suffix: mode)
            let capture = try context.capture(id: "attachment-\(mode)")
            let initial = try await context.openRuntime()
            let receipt = try await initial.captureAttachment(capture)
            try await initial.close()
            let objectURL = try Self.objectURL(context: context, receipt: receipt)
            if mode == "missing" {
                try FileManager.default.removeItem(at: objectURL)
            } else {
                try Data("corrupted ciphertext".utf8).write(to: objectURL, options: .atomic)
            }

            let reopened = try await context.openRuntime()
            let summary = try await reopened.pendingWorkSummary()
            #expect(summary.unverifiedAttachmentCount == 1)
            try await reopened.close()
            context.remove()
        }

        let orphanContext = try RuntimeTestContext(suffix: "orphan")
        let orphanRuntime = try await orphanContext.openRuntime()
        let receipt = try await orphanRuntime.captureAttachment(
            orphanContext.capture(id: "attachment-orphan-anchor")
        )
        try await orphanRuntime.close()
        let objectDirectory = try Self.objectURL(
            context: orphanContext,
            receipt: receipt
        ).deletingLastPathComponent()
        try Data("unreferenced encrypted object".utf8).write(
            to: objectDirectory.appendingPathComponent(String(repeating: "f", count: 64)),
            options: .atomic
        )
        let orphanReopened = try await orphanContext.openRuntime()
        await #expect(throws: PendingWorkPowerSyncQueryFailure.orphanedAttachmentEvidence) {
            _ = try await orphanReopened.pendingWorkSummary()
        }
        try await orphanReopened.close()
        orphanContext.remove()

        let unavailableContext = try RuntimeTestContext(suffix: "observation-unavailable")
        var unavailableDependencies = unavailableContext.dependencies()
        unavailableDependencies.makePendingWorkQuery = { _, _, _, _, _, _ in
            FailingPendingWorkSummary()
        }
        let unavailableRuntime = try await unavailableContext.openRuntime(
            dependencies: unavailableDependencies
        )
        await #expect(throws: RuntimeInjectedFailure.self) {
            _ = try await unavailableRuntime.pendingWorkSummary()
        }
        try await unavailableRuntime.close()
        unavailableContext.remove()
    }

    @Test("WORKRUNTIME-TEST-007 one gate drains finite work and all four streams")
    func lifecycleGateDrainsAndRejectsPostClose() async throws {
        let context = try RuntimeTestContext(suffix: "lifecycle")
        let finiteGate = ManualGate()
        let finiteOperations = LockedRecorder<AccountWorkspaceRuntimeFiniteOperation>()
        let streamCounter = EntryCounter()
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        var dependencies = context.dependencies(events: events)
        dependencies.finiteOperationCheckpoint = { operation in
            finiteOperations.append(operation)
            if operation == .pendingUploadCount { await finiteGate.wait() }
        }
        dependencies.streamOperationCheckpoint = { operation in
            await streamCounter.enter(operation)
            try await Task.sleep(for: .seconds(30))
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)

        _ = try await runtime.createClient(context.clientCommand(id: "gate"))
        _ = try await runtime.createProject(context.projectCommand(id: "gate"))
        _ = try await runtime.encryptionCipher()
        _ = try await runtime.captureAttachment(context.capture(id: "attachment-gate"))
        _ = try await runtime.pendingWorkSummary()

        let clientRequest = try ClientCoreDetailsRequest(
            accountId: context.accountId,
            clientId: ClientID(validating: "client-lifecycle")
        )
        let projectRequest = try ProjectCoreDetailsRequest(
            accountId: context.accountId,
            projectId: ProjectID(validating: "project-lifecycle")
        )
        let streams: [Any] = [
            runtime.watchClient(clientRequest),
            runtime.watchProject(projectRequest),
            runtime.watchClients(),
            runtime.watchProjects(),
        ]
        _ = streams
        await streamCounter.waitUntilEntered(4)
        let enteredStreams = await streamCounter.values()
        for operation in [
            AccountWorkspaceRuntimeStreamOperation.clientDetails,
            .projectDetails,
            .clientDirectory,
            .projectDirectory,
        ] {
            #expect(enteredStreams.filter { $0 == operation }.count == 1)
        }

        let finite = Task { try await runtime.pendingUploadCount() }
        await finiteGate.waitUntilEntered()
        let close = Task { try await runtime.close() }
        try await Task.sleep(for: .milliseconds(50))
        #expect(!events.values.contains(.attachmentDatabaseCloseAttempted))
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.createClient(context.clientCommand(id: "while-closing"))
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.createProject(context.projectCommand(id: "while-closing"))
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.pendingUploadCount()
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.encryptionCipher()
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.captureAttachment(
                context.capture(id: "attachment-while-closing")
            )
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.pendingWorkSummary()
        }
        try await Self.expectClosed(runtime.watchClients())
        try await Self.expectClosed(runtime.watchProjects())
        try await Self.expectClosed(runtime.watchClient(clientRequest))
        try await Self.expectClosed(runtime.watchProject(projectRequest))
        await finiteGate.release()
        _ = try await finite.value
        try await close.value
        for operation in [
            AccountWorkspaceRuntimeFiniteOperation.createClient,
            .createProject,
            .pendingUploadCount,
            .encryptionCipher,
            .captureAttachment,
            .pendingWorkSummary,
        ] {
            #expect(finiteOperations.values.filter { $0 == operation }.count == 1)
        }
        #expect(
            events.values.filter {
                $0 == .attachmentDatabaseCloseAttempted || $0 == .structuredDatabaseCloseAttempted
            }.suffix(2) == [.attachmentDatabaseCloseAttempted, .structuredDatabaseCloseAttempted])

        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.pendingUploadCount()
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.encryptionCipher()
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.createClient(context.clientCommand(id: "after-close"))
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.createProject(context.projectCommand(id: "after-close"))
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.captureAttachment(
                context.capture(id: "attachment-after-close")
            )
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.pendingWorkSummary()
        }
        try await Self.expectClosed(runtime.watchClients())
        try await Self.expectClosed(runtime.watchProjects())
        try await Self.expectClosed(runtime.watchClient(clientRequest))
        try await Self.expectClosed(runtime.watchProject(projectRequest))
        context.remove()
    }

    @Test("WORKRUNTIME-TEST-007 consumer and close-caller cancellation cannot strand teardown")
    func cancellationCannotStrandLifecycle() async throws {
        let streamContext = try RuntimeTestContext(suffix: "consumer-cancel")
        let streamEntered = EntryCounter()
        var streamDependencies = streamContext.dependencies()
        streamDependencies.streamOperationCheckpoint = { operation in
            await streamEntered.enter(operation)
            try await Task.sleep(for: .seconds(30))
        }
        let streamRuntime = try await streamContext.openRuntime(
            dependencies: streamDependencies
        )
        let consumer = Task {
            do {
                var iterator = streamRuntime.watchClients().makeAsyncIterator()
                _ = try await iterator.next()
            } catch {
                // Cancellation is the expected terminal outcome.
            }
        }
        await streamEntered.waitUntilEntered(1)
        consumer.cancel()
        await consumer.value
        try await streamRuntime.close()
        streamContext.remove()

        let closeContext = try RuntimeTestContext(suffix: "close-caller-cancel")
        let finiteGate = ManualGate()
        var closeDependencies = closeContext.dependencies()
        closeDependencies.finiteOperationCheckpoint = { operation in
            if operation == .pendingUploadCount { await finiteGate.wait() }
        }
        let closeRuntime = try await closeContext.openRuntime(
            dependencies: closeDependencies
        )
        let finite = Task { try await closeRuntime.pendingUploadCount() }
        await finiteGate.waitUntilEntered()
        let closeCaller = Task { try await closeRuntime.close() }
        try await Task.sleep(for: .milliseconds(20))
        closeCaller.cancel()
        await finiteGate.release()
        _ = try await finite.value
        try await closeCaller.value
        try await closeRuntime.close()
        closeContext.remove()
    }

    @Test("WORKRUNTIME-TEST-007 close drains active real PowerSync watches")
    func closeDrainsActivePowerSyncWatches() async throws {
        let context = try RuntimeTestContext(suffix: "real-watch-close")
        let progress = EntryCounter()
        var dependencies = context.dependencies()
        dependencies.streamOperationCheckpoint = { operation in
            await progress.enter(operation)
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let clientRequest = try ClientCoreDetailsRequest(
            accountId: context.accountId,
            clientId: ClientID(validating: "client-real-watch")
        )
        let projectRequest = try ProjectCoreDetailsRequest(
            accountId: context.accountId,
            projectId: ProjectID(validating: "project-real-watch")
        )
        let consumers = [
            Self.consumeUntilTermination(
                runtime.watchClient(clientRequest),
                operation: .clientDetails,
                requiredEmissions: 2,
                progress: progress
            ),
            Self.consumeUntilTermination(
                runtime.watchProject(projectRequest),
                operation: .projectDetails,
                requiredEmissions: 2,
                progress: progress
            ),
            Self.consumeUntilTermination(
                runtime.watchClients(),
                operation: .clientDirectory,
                requiredEmissions: 1,
                progress: progress
            ),
            Self.consumeUntilTermination(
                runtime.watchProjects(),
                operation: .projectDirectory,
                requiredEmissions: 1,
                progress: progress
            )
        ]

        await progress.waitUntilEntered(8)
        try await runtime.close()
        for consumer in consumers { await consumer.value }
        await progress.waitUntilEntered(12)
        let observations = await progress.values()
        for operation in [
            AccountWorkspaceRuntimeStreamOperation.clientDetails,
            .projectDetails,
            .clientDirectory,
            .projectDirectory,
        ] {
            #expect(observations.filter { $0 == operation }.count == 3)
        }
        context.remove()
    }

    @Test("WORKRUNTIME-TEST-007 close failure is terminal, combined, and never retried")
    func terminalDualCloseFailureIsIdempotent() async throws {
        let context = try RuntimeTestContext(suffix: "terminal-close")
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        var dependencies = context.dependencies(events: events)
        let openStructured = dependencies.openStructuredDatabase
        let openAttachment = dependencies.openAttachmentDatabase
        dependencies.openStructuredDatabase = { path, key in
            let opened = try openStructured(path, key)
            return AccountWorkspaceOpenedDatabase(
                database: opened.database,
                closePreservingData: {
                    try? await opened.closePreservingData()
                    throw RuntimeInjectedFailure()
                }
            )
        }
        dependencies.openAttachmentDatabase = { path, key in
            let opened = try openAttachment(path, key)
            return AccountWorkspaceOpenedDatabase(
                database: opened.database,
                closePreservingData: {
                    try? await opened.closePreservingData()
                    throw RuntimeInjectedFailure()
                }
            )
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let first = Task { try await runtime.close() }
        let second = Task { try await runtime.close() }
        for task in [first, second] {
            do {
                try await task.value
                Issue.record("Expected combined close failure")
            } catch let failure as LedgerOfflineClientRuntimeFailure {
                #expect(
                    failure
                        == .databaseCloseFailed(
                            attachmentDatabase: true,
                            structuredDatabase: true
                        ))
            }
        }
        do {
            try await runtime.close()
            Issue.record("Expected stored close failure")
        } catch let failure as LedgerOfflineClientRuntimeFailure {
            #expect(
                failure
                    == .databaseCloseFailed(
                        attachmentDatabase: true,
                        structuredDatabase: true
                    ))
        }
        #expect(events.values.filter { $0 == .attachmentDatabaseCloseAttempted }.count == 1)
        #expect(events.values.filter { $0 == .structuredDatabaseCloseAttempted }.count == 1)
        context.remove()
    }

    @Test("WORKRUNTIME-TEST-008 public runtime remains a narrow non-destructive surface")
    func publicSurfaceCompilesWithoutResourceEscape() async throws {
        let context = try RuntimeTestContext(suffix: "public-surface")
        let runtime: LedgerOfflineClientRuntime = try await context.openRuntime()
        _ = runtime.watchClients()
        _ = runtime.watchProjects()
        _ = try await runtime.pendingUploadCount()
        _ = try await runtime.encryptionCipher()
        _ = try await runtime.pendingWorkSummary()
        try await runtime.close()
        context.remove()
    }

    private static func expectExactConstructionCounts(
        _ events: [AccountWorkspaceRuntimeLifecycleEvent]
    ) {
        for event in [
            AccountWorkspaceRuntimeLifecycleEvent.structuredDatabaseOpened,
            .attachmentDatabaseOpened,
            .vaultConstructed,
            .attachmentStoreConstructed,
            .pendingWorkQueryConstructed,
            .lifecycleOwnerConstructed,
        ] {
            #expect(events.filter { $0 == event }.count == 1)
        }
    }

    private static func insertOperation(
        _ database: any PowerSyncDatabaseProtocol,
        id: String,
        state: LocalOperationState,
        timestamp: Int64 = 1
    ) async throws {
        _ = try await database.execute(
            sql: """
                INSERT INTO \(LedgerPowerSyncTable.localOperations) (
                  id, account_id, actor_principal_id, contract_version, fingerprint,
                  subject_id, local_state, accepted_at_ms, updated_at_ms
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            parameters: [
                id, "account-runtime", "principal-runtime", "pending-work-v1",
                String(repeating: "a", count: 64), "subject-\(id)", state.rawValue,
                timestamp, timestamp,
            ]
        )
    }

    private static func objectURL(
        context: RuntimeTestContext,
        receipt: AttachmentLocalDurabilityReceipt
    ) throws -> URL {
        let root = try context.location().mediaVaultRootURL
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        else {
            throw RuntimeInjectedFailure()
        }
        for case let url as URL in enumerator
        where
            url.lastPathComponent == receipt.localObjectId.rawValue
        {
            return url
        }
        throw RuntimeInjectedFailure()
    }

    private static func faultedDependencies(
        stage: LedgerPowerSyncLocalBootstrapStage,
        context: RuntimeTestContext,
        recorder: LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>
    ) -> LedgerPowerSyncLocalBootstrapDependencies {
        var dependencies = context.dependencies(events: recorder)
        let validateStructured = dependencies.validateStructuredDatabase
        let validateAttachment = dependencies.validateAttachmentDatabase
        let makeVault = dependencies.makeVault
        let makeStore = dependencies.makeAttachmentStore
        let makeQuery = dependencies.makePendingWorkQuery

        if stage == .databaseKeyLoad {
            dependencies.loadDatabaseKey = { _, _ in throw RuntimeInjectedFailure() }
        }
        if stage == .mediaKeyLoad {
            dependencies.loadMediaKeyBytes = { _, _ in throw RuntimeInjectedFailure() }
        }
        if stage == .keyValidation {
            dependencies.loadMediaKeyBytes = { _, _ in Data(repeating: 0x1a, count: 32) }
        }
        if stage == .directoryPreparation {
            dependencies.createDirectory = { _ in throw RuntimeInjectedFailure() }
        }
        if stage == .structuredDatabaseOpen {
            dependencies.openStructuredDatabase = { _, _ in throw RuntimeInjectedFailure() }
        }
        if stage == .structuredDatabaseValidation {
            dependencies.validateStructuredDatabase = { database in
                try await validateStructured(database)
                throw RuntimeInjectedFailure()
            }
        }
        if stage == .attachmentDatabaseOpen {
            dependencies.openAttachmentDatabase = { _, _ in throw RuntimeInjectedFailure() }
        }
        if stage == .attachmentDatabaseValidation {
            dependencies.validateAttachmentDatabase = { database in
                try await validateAttachment(database)
                throw RuntimeInjectedFailure()
            }
        }
        if stage == .mediaVaultOpen {
            dependencies.makeVault = { _, _, _ in throw RuntimeInjectedFailure() }
        } else {
            dependencies.makeVault = makeVault
        }
        if stage == .attachmentStoreConstruction {
            dependencies.makeAttachmentStore = { _, _, _, _ in throw RuntimeInjectedFailure() }
        } else {
            dependencies.makeAttachmentStore = makeStore
        }
        if stage == .pendingWorkQueryConstruction {
            dependencies.makePendingWorkQuery = { _, _, _, _, _, _ in
                throw RuntimeInjectedFailure()
            }
        } else {
            dependencies.makePendingWorkQuery = makeQuery
        }
        if stage == .runtimeConstruction {
            dependencies.makeLifecycleOwner = { _ in throw RuntimeInjectedFailure() }
        }
        return dependencies
    }

    private static func expectClosed<Value: Sendable>(
        _ stream: AsyncThrowingStream<Value, Error>
    ) async throws {
        var iterator = stream.makeAsyncIterator()
        do {
            _ = try await iterator.next()
            Issue.record("Expected closed stream failure")
        } catch let failure as LedgerOfflineClientRuntimeFailure {
            #expect(failure == .runtimeClosed)
        }
    }

    private static func consumeUntilTermination<Value: Sendable>(
        _ stream: AsyncThrowingStream<Value, Error>,
        operation: AccountWorkspaceRuntimeStreamOperation,
        requiredEmissions: Int,
        progress: EntryCounter
    ) -> Task<Void, Never> {
        Task {
            var emissionCount = 0
            do {
                for try await _ in stream {
                    emissionCount += 1
                    if emissionCount == requiredEmissions {
                        await progress.enter(operation)
                    }
                }
            } catch {
                // Runtime close terminates the public stream with cancellation.
            }
            await progress.enter(operation)
        }
    }
}

private struct RuntimeInjectedFailure: Error {}

private actor FailingPendingWorkSummary: AccountWorkspacePendingWorkSummarizing {
    func summary() async throws -> PendingLocalWorkSummary {
        throw RuntimeInjectedFailure()
    }
}

private final class RuntimeTestContext: @unchecked Sendable {
    let root: URL
    let environment: ValidatedLedgerEnvironment
    let principalId = try! PrincipalID(validating: "principal-runtime")
    let accountId = try! AccountID(validating: "account-runtime")
    let databaseKey = try! LedgerPowerSyncEncryptionKey(
        hexadecimal: String(repeating: "1a", count: 32)
    )
    let mediaKeyBytes = Data(repeating: 0x42, count: 32)

    init(suffix: String, namespace: String = "apps.nine4.ledger.runtime-tests") throws {
        root =
            FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "workspace-runtime-\(suffix)-\(UUID().uuidString)", isDirectory: true
            )
            .standardizedFileURL
        environment = try Self.makeEnvironment(namespace: namespace)
    }

    func dependencies(
        events: LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>? = nil
    ) -> LedgerPowerSyncLocalBootstrapDependencies {
        var dependencies = LedgerPowerSyncLocalBootstrapDependencies.live
        dependencies.loadDatabaseKey = { [databaseKey] _, _ in databaseKey }
        dependencies.loadMediaKeyBytes = { [mediaKeyBytes] _, _ in mediaKeyBytes }
        dependencies.createDirectory = { directory in
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        dependencies.lifecycleEvent = { events?.append($0) }
        dependencies.now = { Date(timeIntervalSince1970: 1_788_600_000) }
        return dependencies
    }

    func openRuntime(
        events: LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>? = nil
    ) async throws -> LedgerOfflineClientRuntime {
        try await openRuntime(dependencies: dependencies(events: events))
    }

    func openRuntime(
        dependencies: LedgerPowerSyncLocalBootstrapDependencies
    ) async throws -> LedgerOfflineClientRuntime {
        try await LedgerPowerSyncLocalBootstrap.open(
            validatedEnvironment: environment,
            principalId: principalId,
            accountId: accountId,
            applicationSupportDirectory: root,
            dependencies: dependencies
        )
    }

    func location(
        principalId: PrincipalID? = nil,
        accountId: AccountID? = nil
    ) throws -> LedgerWorkspaceRuntimeLocation {
        try LedgerWorkspaceRuntimeIsolation.resolve(
            validatedEnvironment: environment,
            principalId: principalId ?? self.principalId,
            accountId: accountId ?? self.accountId,
            applicationSupportDirectory: root
        )
    }

    func clientCommand(
        id: String,
        accountId: AccountID? = nil,
        principalId: PrincipalID? = nil
    ) throws -> CreateClientCommand {
        try CreateClientCommand(
            operationId: OperationID(validating: "operation-runtime-\(id)"),
            draft: ClientCreationDraft(
                accountId: accountId ?? self.accountId,
                actorPrincipalId: principalId ?? self.principalId,
                operationContractVersion: OperationContractVersion(validating: "client-create-v1"),
                clientId: ClientID(validating: "client-runtime-\(id)"),
                displayName: ClientDisplayName(validating: "Runtime \(id)"),
                capturedAt: Date(timeIntervalSince1970: 1_788_600_000)
            )
        )
    }

    func projectCommand(
        id: String,
        accountId: AccountID? = nil,
        principalId: PrincipalID? = nil
    ) throws -> CreateProjectCommand {
        try CreateProjectCommand(
            operationId: OperationID(validating: "operation-project-runtime-\(id)"),
            draft: ProjectSetupDraft(
                accountId: accountId ?? self.accountId,
                actorPrincipalId: principalId ?? self.principalId,
                operationContractVersion: OperationContractVersion(validating: "project-create-v1"),
                projectId: ProjectID(validating: "project-runtime-\(id)"),
                clientSelection: ProjectClientSelectionInput(
                    newClientId: ClientID(validating: "client-project-runtime-\(id)"),
                    displayName: ClientDisplayName(validating: "Project Client \(id)")
                ),
                displayName: ProjectDisplayName(validating: "Project Runtime \(id)"),
                description: nil,
                categoryAllocations: [],
                capturedAt: Date(timeIntervalSince1970: 1_788_600_000)
            )
        )
    }

    func capture(
        id: String,
        accountId: AccountID? = nil
    ) throws -> LocalAttachmentCapture {
        try LocalAttachmentCapture(
            attachmentId: AttachmentID(validating: id),
            scope: AttachmentCaptureScope(
                environment: .targetLocal,
                principalId: principalId,
                accountId: accountId ?? self.accountId,
                parent: LedgerEntityReference(
                    kind: .item,
                    id: EntityID(validating: "item-runtime")
                )
            ),
            capturedAt: AttachmentEpochMilliseconds(validating: 1_000),
            bytes: Data("runtime bytes for \(id)".utf8)
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func makeEnvironment(namespace: String) throws -> ValidatedLedgerEnvironment {
        let versions = LedgerContractVersions(schema: "1", query: "1", operation: "1", sync: "1")
        let resources = Dictionary(
            uniqueKeysWithValues: LedgerTargetComponent.allCases.map {
                ($0, "runtime-tests-\($0.rawValue)")
            }
        )
        let manifest = LedgerEnvironmentManifest(
            environment: .targetLocal,
            buildProfile: .targetLocalDevelopment,
            bundleIdentifier: "apps.nine4.ledger.runtime-tests",
            displayName: "Ledger Runtime Tests",
            localDataNamespacePrefix: namespace,
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
}

private final class LockedRecorder<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    var values: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: Value) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

private final class WeakVaultRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private weak var storage: AttachmentLocalByteVault?

    var value: AttachmentLocalByteVault? {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func capture(_ vault: AttachmentLocalByteVault) {
        lock.lock()
        storage = vault
        lock.unlock()
    }
}

private actor ManualGate {
    private var entered = false
    private var released = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        entered = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        guard !released else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func release() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}

private actor EntryCounter {
    private var operations: [AccountWorkspaceRuntimeStreamOperation] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func enter(_ operation: AccountWorkspaceRuntimeStreamOperation) {
        operations.append(operation)
        let ready = waiters.filter { operations.count >= $0.0 }
        waiters.removeAll { operations.count >= $0.0 }
        for (_, waiter) in ready { waiter.resume() }
    }

    func waitUntilEntered(_ count: Int) async {
        guard operations.count < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func values() -> [AccountWorkspaceRuntimeStreamOperation] {
        operations
    }
}
