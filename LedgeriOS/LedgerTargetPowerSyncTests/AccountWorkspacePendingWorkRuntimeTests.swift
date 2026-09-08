import Foundation
import LedgerTargetCore
import PowerSync
import Testing

@testable import LedgerTargetPowerSync

@Suite("Account workspace pending-work runtime", .serialized)
struct AccountWorkspacePendingWorkRuntimeTests {
    @Test("Property report facade preserves downloaded snapshot across encrypted restart and denies foreign or closed access")
    func propertyReportFacade() async throws {
        let context = try RuntimeTestContext(suffix: "property-report")
        var dependencies = physicalItemDependencies(context)
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            _ = try await database.execute(sql: "UPDATE spike_projects SET display_name='Property',lifecycle='active',revision=1 WHERE id='project-physical'", parameters: nil)
            _ = try await database.execute(sql: "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES('property_management_report',1,0,?,1000000)", parameters: [#"{"account_id":"account-runtime","project_id":"project-physical"}"#])
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let project = try ProjectID(validating: "project-physical")
        let currency = try CurrencyCode(validating: "USD")
        let asOf = try ProtectedArtifactEpochMilliseconds(validating: 1_800_000_000_000)
        let snapshot = try await runtime.readDownloadedPropertyManagementReport(accountId: context.accountId,
            projectId: project, currency: currency, asOf: asOf)
        #expect(snapshot.totals.itemCount == 1 && snapshot.totals.unknownMarketValueCount == 1)
        #expect(snapshot.groups.first?.rows.first?.name == "Chair")
        await #expect(throws: LedgerOfflineClientRuntimeFailure.accountScopeMismatch) {
            try await runtime.readDownloadedPropertyManagementReport(accountId: AccountID(validating: "foreign-account"),
                projectId: project, currency: currency, asOf: asOf)
        }
        try await runtime.close()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            try await runtime.readDownloadedPropertyManagementReport(accountId: context.accountId,
                projectId: project, currency: currency, asOf: asOf)
        }
        let reopened = try await context.openRuntime()
        let restored = try await reopened.readDownloadedPropertyManagementReport(accountId: context.accountId,
            projectId: project, currency: currency, asOf: asOf)
        #expect(restored.reference == snapshot.reference)
        try await reopened.lockAccessPreservingPendingWork()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            try await reopened.readDownloadedPropertyManagementReport(accountId: context.accountId,
                projectId: project, currency: currency, asOf: asOf)
        }
        context.remove()
    }

    @Test("Physical Item watch cleanup drains before workspace close or learned-removal teardown", arguments: [false, true])
    func physicalItemWatchCleanupDrain(removing: Bool) async throws {
        let context = try RuntimeTestContext(suffix: "physical-watch-cleanup-\(removing)")
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        let cleanup = ManualGate()
        let subscription = RuntimePhysicalSubscription(cleanup: cleanup)
        let subscribed = AsyncStream<Void>.makeStream()
        let values = AsyncStream<DownloadedItemPlacements>.makeStream()
        var dependencies = physicalItemDependencies(context)
        dependencies.lifecycleEvent = { events.append($0) }
        dependencies.subscribePhysicalItems = { account in
            #expect(account == context.accountId)
            subscribed.continuation.yield(())
            return subscription
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let consumer = Task {
            do {
                for try await value in runtime.watchDownloadedItemPlacements(accountId: context.accountId, scope: .businessInventory) {
                    values.continuation.yield(value)
                }
            } catch { }
        }
        var subscriptionIterator = subscribed.stream.makeAsyncIterator()
        _ = await subscriptionIterator.next()
        var valueIterator = values.stream.makeAsyncIterator()
        #expect(try #require(await valueIterator.next()).rows.isEmpty)
        let closing = Task {
            if removing { try await runtime.lockAccessPreservingPendingWork() }
            else { try await runtime.close() }
        }
        await cleanup.waitUntilEntered()
        #expect(!events.values.contains(.structuredDatabaseCloseAttempted))
        #expect(!events.values.contains(.attachmentDatabaseCloseAttempted))
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            try await runtime.readDownloadedItemPlacements(accountId: context.accountId, scope: .businessInventory)
        }
        await cleanup.release()
        try await closing.value
        await consumer.value
        #expect(await subscription.unsubscribeCount == 1)
        #expect(events.values.filter { $0 == .structuredDatabaseCloseAttempted }.count == 1)
        subscribed.continuation.finish(); values.continuation.finish()
        context.remove()
    }

    @Test("Concurrent physical Item watches release only their own subscription handles")
    func physicalItemConcurrentWatchOwnership() async throws {
        let context = try RuntimeTestContext(suffix: "physical-watch-peers")
        let cleanup = ManualGate()
        await cleanup.release()
        let subscriptions = AsyncStream<RuntimePhysicalSubscription>.makeStream()
        var dependencies = physicalItemDependencies(context)
        dependencies.subscribePhysicalItems = { _ in
            let subscription = RuntimePhysicalSubscription(cleanup: cleanup)
            subscriptions.continuation.yield(subscription)
            return subscription
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let first = Task {
            do { for try await _ in runtime.watchDownloadedItemPlacements(accountId: context.accountId, scope: .businessInventory) { } }
            catch { }
        }
        let second = Task {
            do { for try await _ in runtime.watchDownloadedItemPlacements(accountId: context.accountId, scope: .businessInventory) { } }
            catch { }
        }
        var iterator = subscriptions.stream.makeAsyncIterator()
        let a = try #require(await iterator.next())
        let b = try #require(await iterator.next())
        first.cancel()
        await first.value
        var count = 0
        for _ in 0..<2_000 {
            count = await a.unsubscribeCount + b.unsubscribeCount
            if count == 1 { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(count == 1)
        try await runtime.close()
        await second.value
        #expect(await a.unsubscribeCount == 1)
        #expect(await b.unsubscribeCount == 1)
        subscriptions.continuation.finish()
        context.remove()
    }

    @Test("Downloaded physical Item facade binds Account, reads owned storage and survives restart")
    func downloadedItemPlacementsFacade() async throws {
        let context = try RuntimeTestContext(suffix: "downloaded-items")
        let runtime = try await context.openRuntime(dependencies: physicalItemDependencies(context))
        let project = try ProjectID(validating: "project-physical")
        let empty = try await runtime.readDownloadedItemPlacements(accountId: context.accountId, scope: .businessInventory)
        #expect(empty.accountId == context.accountId)
        #expect(empty.scope == .businessInventory)
        #expect(empty.rows.isEmpty) // Downloaded rows only, not completeness.
        let snapshot = try await runtime.readDownloadedItemPlacements(accountId: context.accountId, scope: .project(project))
        #expect(snapshot.accountId == context.accountId)
        #expect(snapshot.scope == .project(project))
        #expect(snapshot.rows.count == 1)
        #expect(snapshot.rows.first?.itemId.rawValue == "physical-chair")
        #expect(snapshot.rows.first?.placementId.rawValue == "physical-placement")
        #expect(snapshot.rows.first?.itemRevision == 3)
        let itemId = try ItemID(validating: "physical-chair")
        let history = try await runtime.readDownloadedItemPlacementHistory(accountId: context.accountId, itemId: itemId)
        #expect(history.isPartial && history.intervals.map(\.placementId.rawValue) == ["physical-placement"])
        await #expect(throws: LedgerOfflineClientRuntimeFailure.accountScopeMismatch) {
            try await runtime.readDownloadedItemPlacementHistory(accountId: AccountID(validating: "account-other"), itemId: itemId)
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.accountScopeMismatch) {
            try await runtime.readDownloadedItemPlacements(accountId: AccountID(validating: "account-other"), scope: .project(project))
        }
        try await runtime.close()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            try await runtime.readDownloadedItemPlacements(accountId: context.accountId, scope: .project(project))
        }
        let reopened = try await context.openRuntime()
        let restored = try await reopened.readDownloadedItemPlacements(accountId: context.accountId, scope: .project(project))
        #expect(try await reopened.readDownloadedItemPlacementHistory(accountId: context.accountId, itemId: itemId) == history)
        #expect(restored.rows.map(\.placementId) == snapshot.rows.map(\.placementId))
        #expect(restored.rows.map(\.itemRevision) == snapshot.rows.map(\.itemRevision))
        try await reopened.close()
        context.remove()
    }

    @Test("Downloaded physical Item reads drain before close; learned removal suppresses admitted reads",
          arguments: [false, true], [false, true])
    func downloadedItemPlacementsDrain(removing: Bool, history: Bool) async throws {
        let context = try RuntimeTestContext(suffix: "downloaded-items-drain-\(removing)-\(history)")
        let gate = ManualGate()
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        let locked = AsyncStream<Void>.makeStream()
        var dependencies = physicalItemDependencies(context)
        dependencies.lifecycleEvent = { event in
            events.append(event)
            if event == .accessLocked { locked.continuation.yield(()) }
        }
        dependencies.finiteOperationCheckpoint = { operation in
            if operation == .readDownloadedItemPlacements { await gate.wait() }
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let itemId = try ItemID(validating: "physical-chair")
        let read = Task {
            if history {
                let value = try await runtime.readDownloadedItemPlacementHistory(accountId: context.accountId, itemId: itemId)
                #expect(value.intervals.count == 1)
            } else {
                let value = try await runtime.readDownloadedItemPlacements(accountId: context.accountId, scope: .businessInventory)
                #expect(value.rows.isEmpty)
            }
        }
        await gate.waitUntilEntered()
        let closing = Task {
            if removing { try await runtime.lockAccessPreservingPendingWork() }
            else { try await runtime.close() }
        }
        if removing {
            var iterator = locked.stream.makeAsyncIterator()
            _ = await iterator.next()
        } else {
            try await Task.sleep(for: .milliseconds(30))
        }
        #expect(!events.values.contains(.structuredDatabaseCloseAttempted))
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            if history {
                _ = try await runtime.readDownloadedItemPlacementHistory(accountId: context.accountId, itemId: itemId)
            } else {
                _ = try await runtime.readDownloadedItemPlacements(accountId: context.accountId, scope: .businessInventory)
            }
        }
        await gate.release()
        if removing {
            await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) { try await read.value }
        } else {
            try await read.value
        }
        try await closing.value
        #expect(events.values.filter { $0 == .structuredDatabaseCloseAttempted }.count == 1)
        locked.continuation.finish()
        context.remove()
    }

    @Test("Item history runtime watch terminates on close or learned removal and rejects further access",
          arguments: [false, true])
    func downloadedItemHistoryWatchLifecycle(removing: Bool) async throws {
        let context = try RuntimeTestContext(suffix: "history-watch-lifecycle-\(removing)")
        let runtime = try await context.openRuntime(dependencies: physicalItemDependencies(context))
        let itemId = try ItemID(validating: "physical-chair")
        let first = AsyncStream<Void>.makeStream()
        let consumer = Task {
            var count = 0
            do {
                for try await value in runtime.watchDownloadedItemPlacementHistory(accountId: context.accountId, itemId: itemId) {
                    #expect(value.accountId == context.accountId && value.itemId == itemId)
                    #expect(value.intervals.map(\.placementId.rawValue) == ["physical-placement"])
                    count += 1
                    first.continuation.yield(())
                }
            } catch is CancellationError {
                // Closing a tracked watch is cancellation, not missing history.
            } catch let failure as LedgerOfflineClientRuntimeFailure {
                #expect(failure == .runtimeClosed)
            } catch { Issue.record("Unexpected history stream failure: \(error)") }
            first.continuation.finish()
            return count
        }
        var iterator = first.stream.makeAsyncIterator()
        #expect(await iterator.next() != nil)
        var foreign = runtime.watchDownloadedItemPlacementHistory(
            accountId: try AccountID(validating: "account-other"), itemId: itemId).makeAsyncIterator()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.accountScopeMismatch) { try await foreign.next() }
        if removing { try await runtime.lockAccessPreservingPendingWork() }
        else { try await runtime.close() }
        #expect(await consumer.value >= 1)
        try await Self.expectClosed(runtime.watchDownloadedItemPlacementHistory(accountId: context.accountId, itemId: itemId))
        context.remove()
    }

    private func physicalItemDependencies(_ context: RuntimeTestContext) -> LedgerPowerSyncLocalBootstrapDependencies {
        var dependencies = context.dependencies()
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            for sql in [
                "INSERT INTO spike_account_memberships(id,account_id,principal_id,state) VALUES('physical-member','account-runtime','principal-runtime','active')",
                "INSERT INTO spike_projects(id,account_id) VALUES('project-physical','account-runtime')",
                "INSERT INTO spike_items(id,account_id,description,revision) VALUES('physical-chair','account-runtime','Chair',3)",
                "INSERT INTO spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at) VALUES('physical-placement','account-runtime','physical-chair','project','project-physical','2026-09-01')"
            ] { _ = try await database.execute(sql: sql, parameters: nil) }
        }
        return dependencies
    }

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

    @Test("CATPOWER-TEST-005 runtime close and reopen preserve local category rows")
    func categoryRowsSurviveRuntimeRestartWithoutCompletenessClaim() async throws {
        let context = try RuntimeTestContext(suffix: "category-restart")
        var dependencies = context.dependencies()
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            _ = try await database.execute(
                sql: """
                INSERT INTO spike_account_memberships (
                  id, account_id, principal_id, role, state,
                  can_manage_clients, can_manage_projects,
                  can_manage_project_budgets, financial_access
                ) VALUES (?, ?, ?, 'owner', 'active', 1, 1, 1, 'full')
                """,
                parameters: [
                    "membership-category-runtime",
                    context.accountId.rawValue,
                    context.principalId.rawValue,
                ]
            )
            _ = try await database.execute(
                sql: """
                INSERT INTO spike_budget_categories (
                  id, account_id, display_name, kind, lifecycle, is_system,
                  excludes_from_overall_budget, visibility_class,
                  presentation_order, revision, created_at_ms, updated_at_ms
                ) VALUES (?, ?, 'Furnishings', 'itemized', 'active', 0,
                          0, 'ordinary', 1, 3, 1788500000000, 1788500001000)
                """,
                parameters: ["category-runtime", context.accountId.rawValue]
            )
        }

        let first = try await context.openRuntime(dependencies: dependencies)
        var firstIterator = first.watchBudgetCategories().makeAsyncIterator()
        let beforeRestart = try #require(try await firstIterator.next())
        #expect(beforeRestart.local.rows.map(\.id.rawValue) == ["category-runtime"])
        #expect(beforeRestart.local.quality == .partial)
        #expect(!beforeRestart.local.isCompleteForQuery)
        try await first.close()

        let reopened = try await context.openRuntime()
        var reopenedIterator = reopened.watchBudgetCategories().makeAsyncIterator()
        let afterRestart = try #require(try await reopenedIterator.next())
        #expect(afterRestart.local.rows == beforeRestart.local.rows)
        #expect(afterRestart.local.quality == .partial)
        #expect(!afterRestart.local.isCompleteForQuery)
        #expect(afterRestart.local.queryFingerprint == beforeRestart.local.queryFingerprint)
        #expect(afterRestart.local.localDataVersion == beforeRestart.local.localDataVersion)
        try await reopened.close()
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
                (.budgetCategoryQueryConstruction, .succeeded, .succeeded),
                (.spaceAssignmentDestinationQueryConstruction, .succeeded, .succeeded),
                (.projectNoteQueryConstruction, .succeeded, .succeeded),
                (.spaceBrowserQueryConstruction, .succeeded, .succeeded),
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

    @Test("WORKRUNTIME-TEST-007 one gate drains finite work and all twelve streams")
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
        let projectCommand = try context.projectCommand(id: "gate")
        _ = try await runtime.createProject(projectCommand)
        let archiveCommand = try context.archiveCommand(id: "gate")
        _ = try await runtime.archive(archiveCommand)
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
        let spaceScope = ItemPlacementScope.project(
            try ProjectID(validating: "project-lifecycle")
        )
        let transferSource = try Self.transferSource(
            accountId: context.accountId,
            id: "project-lifecycle",
            clientId: "client-lifecycle"
        )
        let noteRequest = try ProjectNotePageRequest(
            accountId: context.accountId,
            projectId: projectRequest.projectId,
            pageSize: 20
        )
        let spaceId = try SpaceID(validating: "space-lifecycle")
        let spaceListRequest = try SpaceListRequest(
            accountId: context.accountId,
            scope: .project(projectRequest.projectId)
        )
        let streams: [Any] = [
            runtime.watchClient(clientRequest),
            runtime.watchProject(projectRequest),
            runtime.watchClients(),
            runtime.watchProjects(),
            runtime.watchBudgetCategories(),
            runtime.watchSpaceAssignmentDestinations(scope: spaceScope),
            runtime.watchTransferDestinations(source: transferSource),
            runtime.watchProjectNotes(noteRequest),
            runtime.watchSpaceCoreDetails(spaceId: spaceId),
            runtime.watchSpaces(spaceListRequest),
            runtime.watchProjectCreationOperation(projectCommand.envelope.operationId),
            runtime.watchOperation(archiveCommand.envelope.operationId),
        ]
        _ = streams
        await streamCounter.waitUntilEntered(12)
        let enteredStreams = await streamCounter.values()
        for operation in [
            AccountWorkspaceRuntimeStreamOperation.clientDetails,
            .projectDetails,
            .clientDirectory,
            .projectDirectory,
            .budgetCategories,
            .spaceAssignmentDestinations,
            .transferDestinations,
            .projectNotes,
            .spaceCoreDetails,
            .spaceDirectory,
            .projectCreationOperation,
            .projectArchiveOperation,
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
            _ = try await runtime.archive(context.archiveCommand(id: "while-closing"))
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
        try await Self.expectClosed(runtime.watchBudgetCategories())
        try await Self.expectClosed(runtime.watchSpaceAssignmentDestinations(scope: spaceScope))
        try await Self.expectClosed(
            runtime.watchTransferDestinations(source: transferSource)
        )
        try await Self.expectClosed(runtime.watchProjectNotes(noteRequest))
        try await Self.expectClosed(runtime.watchSpaceCoreDetails(spaceId: spaceId))
        try await Self.expectClosed(runtime.watchSpaces(spaceListRequest))
        try await Self.expectClosed(
            runtime.watchProjectCreationOperation(projectCommand.envelope.operationId)
        )
        try await Self.expectClosed(runtime.watchOperation(archiveCommand.envelope.operationId))
        await finiteGate.release()
        _ = try await finite.value
        try await close.value
        for operation in [
            AccountWorkspaceRuntimeFiniteOperation.createClient,
            .createProject,
            .archiveProject,
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
            _ = try await runtime.archive(context.archiveCommand(id: "after-close"))
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
        try await Self.expectClosed(runtime.watchBudgetCategories())
        try await Self.expectClosed(runtime.watchSpaceAssignmentDestinations(scope: spaceScope))
        try await Self.expectClosed(
            runtime.watchTransferDestinations(source: transferSource)
        )
        try await Self.expectClosed(runtime.watchProjectNotes(noteRequest))
        try await Self.expectClosed(runtime.watchSpaceCoreDetails(spaceId: spaceId))
        try await Self.expectClosed(runtime.watchSpaces(spaceListRequest))
        try await Self.expectClosed(
            runtime.watchProjectCreationOperation(projectCommand.envelope.operationId)
        )
        try await Self.expectClosed(runtime.watchOperation(archiveCommand.envelope.operationId))
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

    @Test("Removal signal reaches current and late presentation observers without unlocking")
    func removalSignalIsMonotonic() async {
        let fence = LedgerWorkspaceAccessFence()
        var early = fence.watchRemoval().makeAsyncIterator()
        fence.markRemoved()
        #expect(await early.next() != nil)
        #expect(await early.next() == nil)
        var late = fence.watchRemoval().makeAsyncIterator()
        #expect(await late.next() != nil)
        #expect(await late.next() == nil)
        fence.markRemoved()
        #expect(fence.isRemoved)
    }

    @Test("Removal drains a live watcher even after its runtime facade is released")
    func removalClosesOrphanedWatcher() async throws {
        let context = try RuntimeTestContext(suffix: "removal-orphaned-watcher")
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        let entered = EntryCounter()
        var dependencies = context.dependencies(events: events)
        dependencies.streamOperationCheckpoint = { operation in
            await entered.enter(operation)
            try await Task.sleep(for: .seconds(30))
        }
        var runtime: LedgerOfflineClientRuntime? = try await context.openRuntime(dependencies: dependencies)
        weak var releasedRuntime = runtime
        let stream = runtime!.watchClients()
        let consumer = Task {
            do {
                var iterator = stream.makeAsyncIterator()
                _ = try await iterator.next()
            } catch { /* Removal cancels the watcher. */ }
        }
        await entered.waitUntilEntered(1)
        runtime = nil
        for _ in 0..<1000 {
            if releasedRuntime == nil { break }
            await Task.yield()
        }
        #expect(releasedRuntime == nil)
        let identity = try LedgerWorkspaceRemovalRegistry.identity(
            environment: context.environment.manifest.environment,
            principalId: context.principalId, accountId: context.accountId
        )
        try await context.accessCoordinator.remove(identity: identity, persist: {})
        await consumer.value
        #expect(events.values.contains(.attachmentDatabaseCloseAttempted))
        #expect(events.values.contains(.structuredDatabaseCloseAttempted))
        #expect(events.values.contains(.vaultReleased))
        context.remove()
    }

    @Test("Removal locks peer handles and rejects a late concurrent bootstrap")
    func removalWinsConcurrentOpen() async throws {
        let first = try RuntimeTestContext(suffix: "removal-first")
        let peer = try RuntimeTestContext(suffix: "removal-peer")
        let late = try RuntimeTestContext(suffix: "removal-late")
        let runtime = try await first.openRuntime()
        var peerDependencies = peer.dependencies()
        peerDependencies.accessCoordinator = first.accessCoordinator
        let peerRuntime = try await peer.openRuntime(dependencies: peerDependencies)
        let gate = ManualGate()
        var lateDependencies = late.dependencies()
        lateDependencies.accessCoordinator = first.accessCoordinator
        let validate = lateDependencies.validateStructuredDatabase
        lateDependencies.validateStructuredDatabase = { database in
            try await validate(database)
            await gate.wait()
        }
        let openingDependencies = lateDependencies
        let opening = Task { try await late.openRuntime(dependencies: openingDependencies) }
        await gate.waitUntilEntered()
        try await runtime.lockAccessPreservingPendingWork()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await peerRuntime.pendingWorkSummary()
        }
        await gate.release()
        await #expect(throws: LedgerPowerSyncLocalBootstrapFailure(stage: .workspaceAccessRemoved)) {
            _ = try await opening.value
        }
        await #expect(throws: LedgerPowerSyncLocalBootstrapFailure(stage: .workspaceAccessRemoved)) {
            _ = try await first.openRuntime()
        }
        first.remove()
        peer.remove()
        late.remove()
    }

    @Test("Injected persisted removal denies bootstrap before opening protected databases")
    func persistedRemovalDeniesReopen() async throws {
        let context = try RuntimeTestContext(suffix: "persisted-removal")
        let removed = LockedRecorder<String>()
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        var dependencies = context.dependencies(events: events)
        dependencies.requireWorkspaceNotRemoved = { environment, principal, account in
            let identity = try LedgerWorkspaceRemovalRegistry.identity(
                environment: environment, principalId: principal, accountId: account
            )
            if removed.values.contains(identity) { throw LedgerWorkspaceRemovalFailure.removed }
        }
        dependencies.recordWorkspaceRemoval = { environment, principal, account in
            removed.append(try LedgerWorkspaceRemovalRegistry.identity(
                environment: environment, principalId: principal, accountId: account
            ))
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        _ = try await runtime.captureAttachment(context.capture(id: "pending-removal"))
        try await runtime.lockAccessPreservingPendingWork()
        let eventsBeforeReopen = events.values
        // Simulate a fresh process owner; denial must come from retained store,
        // not solely from the previous coordinator's in-memory latch.
        dependencies.accessCoordinator = LedgerWorkspaceAccessCoordinator()
        await #expect(throws: LedgerPowerSyncLocalBootstrapFailure(stage: .workspaceAccessRemoved)) {
            _ = try await context.openRuntime(dependencies: dependencies)
        }
        #expect(events.values == eventsBeforeReopen)
        context.remove()
    }

    @Test("Unavailable removal registry fails closed without falsely reporting removal")
    func unavailableRemovalRegistryIsNotRemoval() async throws {
        let context = try RuntimeTestContext(suffix: "removal-read-unavailable")
        defer { context.remove() }
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        var dependencies = context.dependencies(events: events)
        dependencies.requireWorkspaceNotRemoved = { _, _, _ in
            throw LedgerWorkspaceRemovalFailure.unavailable
        }
        await #expect(throws: LedgerPowerSyncLocalBootstrapFailure(stage: .workspaceAccessCheck)) {
            _ = try await context.openRuntime(dependencies: dependencies)
        }
        #expect(events.values.isEmpty)
    }

    @Test("Removal-record failure still closes access and can retry without reopening")
    func removalPersistenceFailureStaysLocked() async throws {
        let context = try RuntimeTestContext(suffix: "removal-write-failure")
        let attempts = LockedRecorder<Int>()
        var dependencies = context.dependencies()
        dependencies.recordWorkspaceRemoval = { _, _, _ in
            attempts.append(1)
            if attempts.values.count == 1 { throw RuntimeInjectedFailure() }
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        await #expect(throws: LedgerOfflineClientRuntimeFailure.removalPersistenceFailed) {
            try await runtime.lockAccessPreservingPendingWork()
        }
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.pendingWorkSummary()
        }
        await #expect(throws: LedgerPowerSyncLocalBootstrapFailure(stage: .workspaceAccessRemoved)) {
            _ = try await context.openRuntime(dependencies: dependencies)
        }
        try await runtime.lockAccessPreservingPendingWork()
        #expect(attempts.values.count == 2)
        context.remove()
    }

    @Test("Owned command upload completes using the workspace database")
    func ownedUploadCompletesThroughWorkspace() async throws {
        let context = try RuntimeTestContext(suffix: "owned-upload-success")
        let runtime = try await context.openRuntime()
        _ = try await runtime.createClient(context.clientCommand(id: "upload-success"))
        let gate = ManualGate()
        await gate.release()
        let cancelled = AsyncStream<Void>.makeStream()
        try await runtime.uploadPendingCommands(using: LedgerPowerSyncCommandAppliers(
            clientCreation: RuntimeGatedClientApplier(gate: gate, cancelled: cancelled.continuation)
        ))
        #expect(try await runtime.pendingWorkSummary().queuedOperationCount == 0)
        try await runtime.close()
        context.remove()
    }

    @Test("Workspace close and removal cancel uploads and drain before closing databases", arguments: [false, true])
    func ownedUploadDrainsBeforeClose(removing: Bool) async throws {
        let context = try RuntimeTestContext(suffix: "owned-upload-drain-\(removing)")
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        let runtime = try await context.openRuntime(dependencies: context.dependencies(events: events))
        _ = try await runtime.createClient(context.clientCommand(id: "upload-drain"))
        let peerContext = try RuntimeTestContext(suffix: "owned-upload-peer-\(removing)")
        var peerDependencies = peerContext.dependencies()
        peerDependencies.accessCoordinator = context.accessCoordinator
        let peer = try await peerContext.openRuntime(dependencies: peerDependencies)
        let gate = ManualGate()
        let cancelled = AsyncStream<Void>.makeStream()
        let appliers = LedgerPowerSyncCommandAppliers(
            clientCreation: RuntimeGatedClientApplier(gate: gate, cancelled: cancelled.continuation)
        )
        let upload = Task { try await runtime.uploadPendingCommands(using: appliers) }
        await gate.waitUntilEntered()
        await #expect(throws: LedgerPowerSyncUploadFailure.uploadAlreadyRunning) {
            try await runtime.uploadPendingCommands(using: appliers)
        }
        await #expect(throws: LedgerPowerSyncUploadFailure.uploadAlreadyRunning) {
            try await peer.uploadPendingCommands(using: appliers)
        }
        let close = Task {
            if removing { try await runtime.lockAccessPreservingPendingWork() }
            else { try await runtime.close() }
        }
        var signal = cancelled.stream.makeAsyncIterator()
        _ = await signal.next()
        #expect(!events.values.contains(.structuredDatabaseCloseAttempted))
        #expect(!events.values.contains(.attachmentDatabaseCloseAttempted))
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            try await runtime.uploadPendingCommands(using: appliers)
        }
        await gate.release()
        do {
            try await upload.value
            Issue.record("Closing workspace must not acknowledge cancelled upload")
        } catch {
            if removing { #expect(error as? LedgerOfflineClientRuntimeFailure == .runtimeClosed) }
            else { #expect(error is CancellationError) }
        }
        try await close.value
        #expect(events.values.contains(.structuredDatabaseCloseAttempted))
        if !removing {
            let reopened = try await context.openRuntime()
            #expect(try await reopened.pendingWorkSummary().queuedOperationCount == 1)
            try await reopened.close()
            // A finished cancelled upload releases shared admission for peers.
            try await peer.uploadPendingCommands(using: appliers)
        }
        try await peer.close()
        peerContext.remove()
        context.remove()
    }

    @Test("Removal identity separates environment, Principal and Account without ambiguous concatenation")
    func removalIdentityIsolation() throws {
        func identity(_ principal: String, _ account: String) throws -> String {
            try LedgerWorkspaceRemovalRegistry.identity(
                environment: .targetStaging,
                principalId: PrincipalID(validating: principal), accountId: AccountID(validating: account)
            )
        }
        #expect(try identity("ab", "c") != identity("a", "bc"))
        #expect(try identity("a", "b") != identity("b", "a"))
        #expect(try identity("a", "b") == identity("a", "b"))
        #expect(try identity("a", "b") != LedgerWorkspaceRemovalRegistry.identity(
            environment: .targetProduction,
            principalId: PrincipalID(validating: "a"), accountId: AccountID(validating: "b")
        ))
    }

    @Test("Learned-removal lock denies paused read admission and preserves pending media")
    func removalLockSuppressesLateBytes() async throws {
        let context = try RuntimeTestContext(suffix: "removal-lock")
        let gate = ManualGate()
        let locked = AsyncStream<Void>.makeStream()
        var dependencies = context.dependencies()
        dependencies.lifecycleEvent = { event in
            if event == .accessLocked { locked.continuation.yield(()) }
        }
        dependencies.finiteOperationCheckpoint = { operation in
            if operation == .resolveAttachmentBytes { await gate.wait() }
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let capture = try context.capture(id: "retained-after-removal")
        let receipt = try await runtime.captureAttachment(capture)
        let resolution = Task { try await runtime.resolveLocalAttachmentBytes(for: receipt) }
        await gate.waitUntilEntered()
        let lock = Task { try await runtime.lockAccessPreservingPendingWork() }
        var notification = locked.stream.makeAsyncIterator()
        _ = await notification.next()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.pendingWorkSummary()
        }
        await gate.release()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await resolution.value
        }
        try await lock.value
        try await runtime.lockAccessPreservingPendingWork()
        locked.continuation.finish()

        // Storage inspection via the test-only bootstrap proves preservation,
        // not permission to reactivate a removed Account in the application.
        var inspectionDependencies = context.dependencies()
        inspectionDependencies.accessCoordinator = LedgerWorkspaceAccessCoordinator()
        let inspection = try await context.openRuntime(dependencies: inspectionDependencies)
        #expect(try await inspection.resolveLocalAttachmentBytes(for: receipt) == capture.bytes)
        #expect(try await inspection.pendingWorkSummary().unverifiedAttachmentCount == 1)
        try await inspection.close()
        context.remove()
    }

    @Test("Learned-removal lock suppresses a result from an already running read body")
    func removalLockSuppressesCompletedRead() async throws {
        let context = try RuntimeTestContext(suffix: "removal-in-read-body")
        let gate = ManualGate()
        let locked = AsyncStream<Void>.makeStream()
        var dependencies = context.dependencies()
        let makeQuery = dependencies.makePendingWorkQuery
        dependencies.makePendingWorkQuery = { database, attachments, environment, principal, account, now in
            let query = try makeQuery(database, attachments, environment, principal, account, now)
            return SuspendedPendingSummary(query: query, gate: gate)
        }
        dependencies.lifecycleEvent = { event in
            if event == .accessLocked { locked.continuation.yield(()) }
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let read = Task { try await runtime.pendingWorkSummary() }
        await gate.waitUntilEntered()
        let lock = Task { try await runtime.lockAccessPreservingPendingWork() }
        var notification = locked.stream.makeAsyncIterator()
        _ = await notification.next()
        await gate.release()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await read.value
        }
        try await lock.value
        locked.continuation.finish()
        context.remove()
    }

    @Test("ATTACHRESOLVE-TEST-005 public runtime resolves the requested receipt and close drains its lease")
    func publicAttachmentResolutionAndCloseDrainage() async throws {
        let successContext = try RuntimeTestContext(suffix: "attachment-resolve-success")
        let successRuntime = try await successContext.openRuntime()
        _ = try await successRuntime.captureAttachment(
            successContext.capture(id: "attachment-runtime-resolve-a")
        )
        let secondCapture = try successContext.capture(
            id: "attachment-runtime-resolve-b"
        )
        let secondReceipt = try await successRuntime.captureAttachment(secondCapture)

        #expect(
            try await successRuntime.resolveLocalAttachmentBytes(for: secondReceipt)
                == secondCapture.bytes
        )
        try await successRuntime.close()
        successContext.remove()

        let drainContext = try RuntimeTestContext(suffix: "attachment-resolve-drain")
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        let gate = ManualGate()
        var dependencies = drainContext.dependencies(events: events)
        dependencies.finiteOperationCheckpoint = { operation in
            if operation == .resolveAttachmentBytes { await gate.wait() }
        }
        let runtime = try await drainContext.openRuntime(dependencies: dependencies)
        let capture = try drainContext.capture(id: "attachment-runtime-resolve-drain")
        let receipt = try await runtime.captureAttachment(capture)
        let resolution = Task {
            try await runtime.resolveLocalAttachmentBytes(for: receipt)
        }
        await gate.waitUntilEntered()
        let close = Task { try await runtime.close() }
        try await Task.sleep(for: .milliseconds(30))
        #expect(!events.values.contains(.attachmentDatabaseCloseAttempted))
        #expect(!events.values.contains(.structuredDatabaseCloseAttempted))
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.resolveLocalAttachmentBytes(for: receipt)
        }

        await gate.release()
        #expect(try await resolution.value == capture.bytes)
        try await close.value
        #expect(
            events.values.filter {
                $0 == .attachmentDatabaseCloseAttempted
                    || $0 == .structuredDatabaseCloseAttempted
            }.suffix(2) == [
                .attachmentDatabaseCloseAttempted,
                .structuredDatabaseCloseAttempted
            ]
        )
        drainContext.remove()
    }

    @Test("ATTACHRESOLVE-TEST-006 cancellation releases the lease and terminal close refuses reads")
    func cancelledAttachmentResolutionCannotStrandClose() async throws {
        let context = try RuntimeTestContext(suffix: "attachment-resolve-cancel")
        let gate = ManualGate()
        var dependencies = context.dependencies()
        dependencies.finiteOperationCheckpoint = { operation in
            if operation == .resolveAttachmentBytes { await gate.wait() }
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let receipt = try await runtime.captureAttachment(
            context.capture(id: "attachment-runtime-resolve-cancel")
        )
        let resolution = Task {
            try await runtime.resolveLocalAttachmentBytes(for: receipt)
        }
        await gate.waitUntilEntered()
        resolution.cancel()
        let close = Task { try await runtime.close() }
        await gate.release()

        await #expect(throws: CancellationError.self) {
            _ = try await resolution.value
        }
        try await close.value
        try await runtime.close()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            _ = try await runtime.resolveLocalAttachmentBytes(for: receipt)
        }
        context.remove()
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
            ),
            Self.consumeUntilTermination(
                runtime.watchBudgetCategories(),
                operation: .budgetCategories,
                requiredEmissions: 1,
                progress: progress
            )
        ]

        await progress.waitUntilEntered(10)
        try await runtime.close()
        for consumer in consumers { await consumer.value }
        await progress.waitUntilEntered(15)
        let observations = await progress.values()
        for operation in [
            AccountWorkspaceRuntimeStreamOperation.clientDetails,
            .projectDetails,
            .clientDirectory,
            .projectDirectory,
            .budgetCategories,
        ] {
            #expect(observations.filter { $0 == operation }.count == 3)
        }
        context.remove()
    }

    @Test("CATPOWER-TEST-005 provider drainage completes before database close")
    func categoryProviderDrainPrecedesDatabaseClose() async throws {
        let context = try RuntimeTestContext(suffix: "category-drain-order")
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        let streamStarted = EntryCounter()
        let drainGate = ManualGate()
        var dependencies = context.dependencies(events: events)
        dependencies.streamOperationCheckpoint = { operation in
            await streamStarted.enter(operation)
        }
        dependencies.makeBudgetCategoryQuery = { _, _, _, _ in
            BlockingDrainBudgetCategoryQuery(drainGate: drainGate)
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let consumer = Task {
            do {
                for try await _ in runtime.watchBudgetCategories() {}
            } catch {
                // Runtime close cancels the public stream.
            }
        }
        await streamStarted.waitUntilEntered(1)

        let close = Task { try await runtime.close() }
        await drainGate.waitUntilEntered()
        #expect(!events.values.contains(.attachmentDatabaseCloseAttempted))
        #expect(!events.values.contains(.structuredDatabaseCloseAttempted))

        await drainGate.release()
        try await close.value
        await consumer.value
        #expect(
            events.values.filter {
                $0 == .attachmentDatabaseCloseAttempted || $0 == .structuredDatabaseCloseAttempted
            }.suffix(2) == [.attachmentDatabaseCloseAttempted, .structuredDatabaseCloseAttempted]
        )
        context.remove()
    }

    @Test("Space-browser provider drainage completes before database close")
    func spaceBrowserProviderDrainPrecedesDatabaseClose() async throws {
        let context = try RuntimeTestContext(suffix: "space-browser-drain-order")
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        let drainGate = ManualGate()
        let query = BlockingDrainSpaceListQuery(drainGate: drainGate)
        var dependencies = context.dependencies(events: events)
        dependencies.makeSpaceBrowserQuery = { _, _, _, _ in query }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let request = try SpaceListRequest(
            accountId: context.accountId,
            scope: .businessInventory
        )
        let consumer = Task {
            do {
                for try await _ in runtime.watchSpaces(request) {}
            } catch {
                // Runtime close cancels the public stream.
            }
        }
        for _ in 0..<2_000 {
            if query.watchCount == 1 { break }
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(query.watchCount == 1)

        let close = Task { try await runtime.close() }
        await drainGate.waitUntilEntered()
        #expect(!events.values.contains(.attachmentDatabaseCloseAttempted))
        #expect(!events.values.contains(.structuredDatabaseCloseAttempted))

        await drainGate.release()
        try await close.value
        await consumer.value
        #expect(query.drainCount == 1)
        #expect(
            events.values.filter {
                $0 == .attachmentDatabaseCloseAttempted || $0 == .structuredDatabaseCloseAttempted
            }.suffix(2) == [.attachmentDatabaseCloseAttempted, .structuredDatabaseCloseAttempted]
        )
        context.remove()
    }

    @Test("Project setup provider drainage completes before database close")
    func projectSetupProviderDrainPrecedesDatabaseClose() async throws {
        let context = try RuntimeTestContext(suffix: "project-setup-drain-order")
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        let drainGate = ManualGate()
        let store = BlockingDrainProjectSetupStore(drainGate: drainGate)
        var dependencies = context.dependencies(events: events)
        dependencies.makeProjectSetupStore = { _, _, _, _ in store }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let operationId = try context.projectCommand(id: "drain-order")
            .envelope.operationId
        let consumer = Task {
            do {
                for try await _ in runtime.watchProjectCreationOperation(operationId) {}
            } catch {
                // Runtime close cancels the public stream.
            }
        }
        for _ in 0..<2_000 {
            if store.watchCount == 1 { break }
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(store.watchCount == 1)

        let close = Task { try await runtime.close() }
        await drainGate.waitUntilEntered()
        #expect(!events.values.contains(.attachmentDatabaseCloseAttempted))
        #expect(!events.values.contains(.structuredDatabaseCloseAttempted))

        await drainGate.release()
        try await close.value
        await consumer.value
        #expect(store.drainCount == 1)
        #expect(
            events.values.filter {
                $0 == .attachmentDatabaseCloseAttempted || $0 == .structuredDatabaseCloseAttempted
            }.suffix(2) == [.attachmentDatabaseCloseAttempted, .structuredDatabaseCloseAttempted]
        )
        context.remove()
    }

    @Test("Project archive provider drainage completes before database close")
    func projectArchiveProviderDrainPrecedesDatabaseClose() async throws {
        let context = try RuntimeTestContext(suffix: "project-archive-drain-order")
        let events = LockedRecorder<AccountWorkspaceRuntimeLifecycleEvent>()
        let drainGate = ManualGate()
        let store = BlockingDrainProjectArchiveStore(drainGate: drainGate)
        var dependencies = context.dependencies(events: events)
        dependencies.makeProjectArchiveStore = { _, _, _, _ in store }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let operationId = try context.archiveCommand(id: "drain-order").envelope.operationId
        let consumer = Task {
            do {
                for try await _ in runtime.watchOperation(operationId) {}
            } catch {
                // Runtime close cancels the public stream.
            }
        }
        for _ in 0..<2_000 {
            if store.watchCount == 1 { break }
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(store.watchCount == 1)

        let close = Task { try await runtime.close() }
        await drainGate.waitUntilEntered()
        #expect(!events.values.contains(.attachmentDatabaseCloseAttempted))
        #expect(!events.values.contains(.structuredDatabaseCloseAttempted))

        await drainGate.release()
        try await close.value
        await consumer.value
        #expect(store.drainCount == 1)
        #expect(
            events.values.filter {
                $0 == .attachmentDatabaseCloseAttempted || $0 == .structuredDatabaseCloseAttempted
            }.suffix(2) == [.attachmentDatabaseCloseAttempted, .structuredDatabaseCloseAttempted]
        )
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
        let _: any SpaceListQuerying = runtime
        let _: any SpaceCoreDetailsQuerying = runtime
        _ = runtime.watchClients()
        _ = runtime.watchProjects()
        _ = runtime.watchBudgetCategories()
        _ = runtime.watchSpaceAssignmentDestinations(
            scope: .project(try ProjectID(validating: "project-runtime"))
        )
        _ = runtime.watchTransferDestinations(
            source: try Self.transferSource(
                accountId: context.accountId,
                id: "project-runtime",
                clientId: "client-runtime"
            )
        )
        _ = runtime.watchProjectNotes(try ProjectNotePageRequest(
            accountId: context.accountId,
            projectId: ProjectID(validating: "project-runtime"),
            pageSize: 20
        ))
        _ = runtime.watchSpaceCoreDetails(
            spaceId: try SpaceID(validating: "space-runtime")
        )
        _ = runtime.watchSpaces(try SpaceListRequest(
            accountId: context.accountId,
            scope: .businessInventory
        ))
        _ = try await runtime.pendingUploadCount()
        _ = try await runtime.encryptionCipher()
        _ = try await runtime.pendingWorkSummary()
        try await runtime.close()
        context.remove()
    }

    @Test("Space destination facade binds Account and close cancels and drains its provider")
    func spaceDestinationFacadeAndDrain() async throws {
        let context = try RuntimeTestContext(suffix: "space-destination-facade")
        let query = RuntimeSpaceDestinationQuery()
        var dependencies = context.dependencies()
        dependencies.makeSpaceAssignmentDestinationQuery = { _, _, _, _ in query }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let scope = ItemPlacementScope.project(
            try ProjectID(validating: "project-runtime-space")
        )
        let consumer = Task {
            do {
                for try await _ in runtime.watchSpaceAssignmentDestinations(scope: scope) {}
            } catch { }
        }
        for _ in 0..<2_000 {
            if query.requests.count == 1 { break }
            try? await Task.sleep(for: .milliseconds(1))
        }
        let request = try #require(query.requests.first)
        #expect(request.accountId == context.accountId)
        #expect(request.scope == scope)

        try await runtime.close()
        await consumer.value
        #expect(query.cancelAndDrainCount == 1)
        #expect(query.terminationCount == 1)
        try await Self.expectClosed(
            runtime.watchSpaceAssignmentDestinations(scope: .businessInventory)
        )
        context.remove()
    }

    @Test("Transfer destination facade uses the current encrypted directory and drains on close")
    func transferDestinationFacadeAndDrain() async throws {
        let context = try RuntimeTestContext(suffix: "transfer-destination-facade")
        var dependencies = context.dependencies()
        let validate = dependencies.validateStructuredDatabase
        dependencies.validateStructuredDatabase = { database in
            try await validate(database)
            _ = try await database.execute(
                sql: """
                INSERT INTO spike_account_memberships (
                  id, account_id, principal_id, role, state,
                  can_manage_clients, can_manage_projects,
                  can_manage_project_budgets, financial_access
                ) VALUES (?, ?, ?, 'owner', 'active', 1, 1, 1, 'full')
                """,
                parameters: [
                    "membership-transfer-runtime",
                    context.accountId.rawValue,
                    context.principalId.rawValue,
                ]
            )
            for (id, name) in [
                ("client-current", "Current Client"),
                ("client-stale", "Stale Client"),
            ] {
                _ = try await database.execute(
                    sql: """
                    INSERT INTO spike_clients (
                      id, account_id, display_name, lifecycle, revision,
                      created_at_ms, updated_at_ms, created_by_principal_id
                    ) VALUES (?, ?, ?, 'active', 1,
                              1788500000000, 1788500001000, ?)
                    """,
                    parameters: [
                        id, context.accountId.rawValue, name,
                        context.principalId.rawValue,
                    ]
                )
            }
            for (id, clientId, name) in [
                ("project-source", "client-current", "Current Source"),
                ("project-destination", "client-current", "Destination"),
                ("project-stale-match", "client-stale", "Stale Match"),
            ] {
                _ = try await database.execute(
                    sql: """
                    INSERT INTO spike_projects (
                      id, account_id, client_id, display_name, description,
                      lifecycle, revision, created_at_ms, updated_at_ms,
                      created_by_principal_id
                    ) VALUES (?, ?, ?, ?, NULL, 'active', 1,
                              1788500000000, 1788500001000, ?)
                    """,
                    parameters: [
                        id, context.accountId.rawValue, clientId, name,
                        context.principalId.rawValue,
                    ]
                )
            }
        }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let staleCaller = try Self.transferSource(
            accountId: context.accountId,
            id: "project-source",
            clientId: "client-stale",
            name: "Caller Stale"
        )
        var iterator = runtime.watchTransferDestinations(
            source: staleCaller
        ).makeAsyncIterator()
        let snapshot = try #require(try await iterator.next())
        #expect(snapshot.source.clientId.rawValue == "client-current")
        #expect(snapshot.source.displayName.rawValue == "Current Source")
        #expect(snapshot.candidates.map(\.destination.id.rawValue) == [
            "project-destination"
        ])
        #expect(snapshot.quality == .partial)
        #expect(!snapshot.isCompleteForSelection)

        let blocked = Task { try await iterator.next() }
        try await runtime.close()
        _ = await blocked.result
        try await Self.expectClosed(
            runtime.watchTransferDestinations(source: staleCaller)
        )
        context.remove()
    }

    @Test("Project-note facade binds Account and close cancels and drains its provider")
    func projectNoteFacadeAndDrain() async throws {
        let context = try RuntimeTestContext(suffix: "project-note-facade")
        let query = RuntimeProjectNoteQuery()
        var dependencies = context.dependencies()
        dependencies.makeProjectNoteQuery = { _, _, _, _ in query }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let request = try ProjectNotePageRequest(
            accountId: context.accountId,
            projectId: ProjectID(validating: "project-runtime-note"),
            pageSize: 20
        )
        let consumer = Task {
            do {
                for try await _ in runtime.watchProjectNotes(request) {}
            } catch { }
        }
        for _ in 0..<2_000 {
            if query.requests.count == 1 { break }
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(query.requests == [request])

        try await runtime.close()
        await consumer.value
        #expect(query.cancelAndDrainCount == 1)
        #expect(query.terminationCount == 1)
        try await Self.expectClosed(runtime.watchProjectNotes(request))
        context.remove()
    }

    @Test("Space core-details facade binds exact Space and drains before close")
    func spaceCoreDetailsFacadeAndDrain() async throws {
        let context = try RuntimeTestContext(suffix: "space-core-details-facade")
        let query = RuntimeSpaceCoreDetailsQuery()
        var dependencies = context.dependencies()
        dependencies.makeSpaceCoreDetailsQuery = { _, _, _, _ in query }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let spaceId = try SpaceID(validating: "space-runtime-detail")
        let expected = try SpaceCoreDetailsRequest(
            accountId: context.accountId,
            spaceId: spaceId
        )
        let consumer = Task {
            do {
                for try await _ in runtime.watchSpaceCoreDetails(expected) {}
            } catch { }
        }
        for _ in 0..<2_000 {
            if query.requests.count == 1 { break }
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(query.requests == [expected])

        let wrongRequest = try SpaceCoreDetailsRequest(
            accountId: AccountID(validating: "account-other"),
            spaceId: spaceId
        )
        var wrongIterator = runtime.watchSpaceCoreDetails(wrongRequest).makeAsyncIterator()
        do {
            _ = try await wrongIterator.next()
            Issue.record("Expected immutable Account-scope refusal")
        } catch let failure as LedgerOfflineClientRuntimeFailure {
            #expect(failure == .accountScopeMismatch)
        }
        #expect(query.requests == [expected])

        try await runtime.close()
        await consumer.value
        #expect(query.cancelAndDrainCount == 1)
        #expect(query.terminationCount == 1)
        try await Self.expectClosed(runtime.watchSpaceCoreDetails(expected))
        context.remove()
    }

    @Test("Space browser facade preserves exact scope and drains before close")
    func spaceBrowserFacadeScopeAndDrain() async throws {
        let context = try RuntimeTestContext(suffix: "space-browser-facade")
        let query = RuntimeSpaceListQuery()
        var dependencies = context.dependencies()
        dependencies.makeSpaceBrowserQuery = { _, _, _, _ in query }
        let runtime = try await context.openRuntime(dependencies: dependencies)
        let request = try SpaceListRequest(
            accountId: context.accountId,
            scope: .project(ProjectID(validating: "project-runtime-space-browser"))
        )
        let consumer = Task {
            do {
                for try await _ in runtime.watchSpaces(request) {}
            } catch { }
        }
        for _ in 0..<2_000 {
            if query.requests.count == 1 { break }
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(query.requests == [request])

        let wrongRequest = try SpaceListRequest(
            accountId: AccountID(validating: "account-other"),
            scope: .businessInventory
        )
        var wrongIterator = runtime.watchSpaces(wrongRequest).makeAsyncIterator()
        do {
            _ = try await wrongIterator.next()
            Issue.record("Expected immutable Account-scope refusal")
        } catch let failure as LedgerOfflineClientRuntimeFailure {
            #expect(failure == .accountScopeMismatch)
        }
        #expect(query.requests == [request])

        try await runtime.close()
        await consumer.value
        #expect(query.cancelAndDrainCount == 1)
        #expect(query.terminationCount == 1)
        try await Self.expectClosed(runtime.watchSpaces(request))
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
            .budgetCategoryQueryConstructed,
            .spaceAssignmentDestinationQueryConstructed,
            .projectNoteQueryConstructed,
            .spaceBrowserQueryConstructed,
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
        let makeBudgetCategoryQuery = dependencies.makeBudgetCategoryQuery
        let makeSpaceAssignmentDestinationQuery =
            dependencies.makeSpaceAssignmentDestinationQuery
        let makeProjectNoteQuery = dependencies.makeProjectNoteQuery
        let makeSpaceBrowserQuery = dependencies.makeSpaceBrowserQuery

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
        if stage == .budgetCategoryQueryConstruction {
            dependencies.makeBudgetCategoryQuery = { _, _, _, _ in
                throw RuntimeInjectedFailure()
            }
        } else {
            dependencies.makeBudgetCategoryQuery = makeBudgetCategoryQuery
        }
        if stage == .spaceAssignmentDestinationQueryConstruction {
            dependencies.makeSpaceAssignmentDestinationQuery = { _, _, _, _ in
                throw RuntimeInjectedFailure()
            }
        } else {
            dependencies.makeSpaceAssignmentDestinationQuery =
                makeSpaceAssignmentDestinationQuery
        }
        if stage == .projectNoteQueryConstruction {
            dependencies.makeProjectNoteQuery = { _, _, _, _ in
                throw RuntimeInjectedFailure()
            }
        } else {
            dependencies.makeProjectNoteQuery = makeProjectNoteQuery
        }
        if stage == .spaceBrowserQueryConstruction {
            dependencies.makeSpaceBrowserQuery = { _, _, _, _ in
                throw RuntimeInjectedFailure()
            }
        } else {
            dependencies.makeSpaceBrowserQuery = makeSpaceBrowserQuery
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

    private static func transferSource(
        accountId: AccountID,
        id: String,
        clientId: String,
        name: String = "Source"
    ) throws -> ProjectSummary {
        let clientID = try ClientID(validating: clientId)
        let observedAt = Date(timeIntervalSince1970: 1_788_600_000)
        return try ProjectSummary(
            id: ProjectID(validating: id),
            accountId: accountId,
            clientId: clientID,
            client: ClientSummary(
                id: clientID,
                accountId: accountId,
                displayName: ClientDisplayName(validating: "Client \(clientId)"),
                lifecycle: .active,
                createdAt: observedAt,
                updatedAt: observedAt
            ),
            displayName: ProjectDisplayName(validating: name),
            description: nil,
            lifecycle: .active
        )
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

private final class BlockingDrainSpaceListQuery:
    AccountWorkspaceSpaceListQuerying, @unchecked Sendable
{
    private let lock = NSLock()
    private let drainGate: ManualGate
    private var watches = 0
    private var drains = 0

    init(drainGate: ManualGate) {
        self.drainGate = drainGate
    }

    var watchCount: Int { lock.withLock { watches } }
    var drainCount: Int { lock.withLock { drains } }

    func watchSpaces(
        _ request: SpaceListRequest
    ) -> AsyncThrowingStream<SpaceListUpdate, Error> {
        lock.withLock { watches += 1 }
        return AsyncThrowingStream { _ in }
    }

    func cancelAndDrainWatches() async {
        lock.withLock { drains += 1 }
        await drainGate.wait()
    }
}

private final class RuntimeSpaceListQuery:
    AccountWorkspaceSpaceListQuerying, @unchecked Sendable
{
    private let lock = NSLock()
    private var recordedRequests: [SpaceListRequest] = []
    private var drains = 0
    private var terminations = 0

    var requests: [SpaceListRequest] { lock.withLock { recordedRequests } }
    var cancelAndDrainCount: Int { lock.withLock { drains } }
    var terminationCount: Int { lock.withLock { terminations } }

    func watchSpaces(
        _ request: SpaceListRequest
    ) -> AsyncThrowingStream<SpaceListUpdate, Error> {
        lock.withLock { recordedRequests.append(request) }
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.terminations += 1 }
            }
        }
    }

    func cancelAndDrainWatches() async {
        lock.withLock { drains += 1 }
    }
}

private final class RuntimeSpaceDestinationQuery:
    AccountWorkspaceSpaceAssignmentDestinationQuerying, @unchecked Sendable
{
    private let lock = NSLock()
    private var recordedRequests: [SpaceAssignmentDestinationRequest] = []
    private var drains = 0
    private var terminations = 0
    var requests: [SpaceAssignmentDestinationRequest] {
        lock.withLock { recordedRequests }
    }
    var cancelAndDrainCount: Int { lock.withLock { drains } }
    var terminationCount: Int { lock.withLock { terminations } }

    func watchEligibleDestinations(
        _ request: SpaceAssignmentDestinationRequest
    ) -> AsyncThrowingStream<SpaceAssignmentDestinationDirectorySnapshot, Error> {
        lock.withLock { recordedRequests.append(request) }
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.terminations += 1 }
            }
        }
    }

    func cancelAndDrainWatches() async {
        lock.withLock { drains += 1 }
    }
}

private final class RuntimeProjectNoteQuery:
    AccountWorkspaceProjectNoteQuerying, @unchecked Sendable
{
    private let lock = NSLock()
    private var recordedRequests: [ProjectNotePageRequest] = []
    private var drains = 0
    private var terminations = 0
    var requests: [ProjectNotePageRequest] { lock.withLock { recordedRequests } }
    var cancelAndDrainCount: Int { lock.withLock { drains } }
    var terminationCount: Int { lock.withLock { terminations } }

    func watchNotes(
        _ request: ProjectNotePageRequest
    ) -> AsyncThrowingStream<ProjectNotePage, Error> {
        lock.withLock { recordedRequests.append(request) }
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.terminations += 1 }
            }
        }
    }

    func cancelAndDrainWatches() async {
        lock.withLock { drains += 1 }
    }
}

private final class RuntimeSpaceCoreDetailsQuery:
    AccountWorkspaceSpaceCoreDetailsQuerying, @unchecked Sendable
{
    private let lock = NSLock()
    private var recordedRequests: [SpaceCoreDetailsRequest] = []
    private var drains = 0
    private var terminations = 0
    var requests: [SpaceCoreDetailsRequest] { lock.withLock { recordedRequests } }
    var cancelAndDrainCount: Int { lock.withLock { drains } }
    var terminationCount: Int { lock.withLock { terminations } }

    func watchSpaceCoreDetails(
        _ request: SpaceCoreDetailsRequest
    ) -> AsyncThrowingStream<SpaceCoreDetailsUpdate, Error> {
        lock.withLock { recordedRequests.append(request) }
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.terminations += 1 }
            }
        }
    }

    func cancelAndDrainWatches() async {
        lock.withLock { drains += 1 }
    }
}

private final class BlockingDrainBudgetCategoryQuery:
    AccountWorkspaceBudgetCategoryQuerying, @unchecked Sendable
{
    private let drainGate: ManualGate

    init(drainGate: ManualGate) {
        self.drainGate = drainGate
    }

    func watchBudgetCategories(
        accountId: AccountID
    ) -> AsyncThrowingStream<BudgetCategoryReferenceSnapshot, Error> {
        AsyncThrowingStream { _ in }
    }

    func cancelAndDrainWatches() async {
        await drainGate.wait()
    }
}

private final class BlockingDrainProjectArchiveStore:
    AccountWorkspaceProjectArchiveStoring, @unchecked Sendable
{
    private let lock = NSLock()
    private let drainGate: ManualGate
    private var watches = 0
    private var drains = 0

    init(drainGate: ManualGate) {
        self.drainGate = drainGate
    }

    var watchCount: Int { lock.withLock { watches } }
    var drainCount: Int { lock.withLock { drains } }

    func archive(_ command: ArchiveProjectCommand) async throws -> OperationReceipt {
        throw RuntimeInjectedFailure()
    }

    func watchOperation(
        _ operationId: OperationID
    ) -> AsyncThrowingStream<OperationSnapshot, Error> {
        lock.withLock { watches += 1 }
        return AsyncThrowingStream { _ in }
    }

    func cancelAndDrainWatches() async {
        lock.withLock { drains += 1 }
        await drainGate.wait()
    }
}

private final class BlockingDrainProjectSetupStore:
    AccountWorkspaceProjectSetupStoring, @unchecked Sendable
{
    private let lock = NSLock()
    private let drainGate: ManualGate
    private var watches = 0
    private var drains = 0

    init(drainGate: ManualGate) {
        self.drainGate = drainGate
    }

    var watchCount: Int { lock.withLock { watches } }
    var drainCount: Int { lock.withLock { drains } }

    func create(_ command: CreateProjectCommand) async throws -> OperationReceipt {
        throw RuntimeInjectedFailure()
    }

    func watchOperation(
        _ operationId: OperationID
    ) -> AsyncThrowingStream<OperationSnapshot, Error> {
        lock.withLock { watches += 1 }
        return AsyncThrowingStream { _ in }
    }

    func cancelAndDrainWatches() async {
        lock.withLock { drains += 1 }
        await drainGate.wait()
    }
}

private actor FailingPendingWorkSummary: AccountWorkspacePendingWorkSummarizing {
    func summary() async throws -> PendingLocalWorkSummary {
        throw RuntimeInjectedFailure()
    }
}

private final class RuntimeTestContext: @unchecked Sendable {
    let root: URL
    let accessCoordinator = LedgerWorkspaceAccessCoordinator()
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
        dependencies.accessCoordinator = accessCoordinator
        // These tests use injected storage; removal persistence has dedicated
        // tests below and must not mutate the developer's real keychain.
        dependencies.requireWorkspaceNotRemoved = { _, _, _ in }
        dependencies.recordWorkspaceRemoval = { _, _, _ in }
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

    func archiveCommand(
        id: String,
        accountId: AccountID? = nil,
        principalId: PrincipalID? = nil
    ) throws -> ArchiveProjectCommand {
        let archiveAccountId = accountId ?? self.accountId
        let uuids: [String: String] = [
            "gate": "00000000-0000-4000-8000-000000000101",
            "while-closing": "00000000-0000-4000-8000-000000000102",
            "after-close": "00000000-0000-4000-8000-000000000103",
            "drain-order": "00000000-0000-4000-8000-000000000104"
        ]
        guard let uuidText = uuids[id], let uuid = UUID(uuidString: uuidText) else {
            throw RuntimeInjectedFailure()
        }
        return try ArchiveProjectCommand(
            operationId: ProjectArchiveOperationIdentity.make(
                accountId: archiveAccountId,
                uuid: uuid
            ),
            draft: ProjectArchiveDraft(
                accountId: archiveAccountId,
                actorPrincipalId: principalId ?? self.principalId,
                operationContractVersion: OperationContractVersion(
                    validating: "project-archive-v1"
                ),
                projectId: ProjectID(validating: "project-runtime-\(id)"),
                expectedRevision: ExpectedProjectRevision(1),
                capturedAt: Date(timeIntervalSince1970: 1_788_600_001)
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

private struct SuspendedPendingSummary: AccountWorkspacePendingWorkSummarizing {
    let query: any AccountWorkspacePendingWorkSummarizing
    let gate: ManualGate

    func summary() async throws -> PendingLocalWorkSummary {
        let value = try await query.summary()
        await gate.wait()
        return value
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

private struct RuntimeGatedClientApplier: ClientCreationCommandApplying {
    let gate: ManualGate
    let cancelled: AsyncStream<Void>.Continuation

    func apply(_ request: ClientCreationUploadRequest) async throws -> ClientCreationServerResult {
        await withTaskCancellationHandler {
            // Intentionally ignores cancellation until released, as an already
            // dispatched request may do. The owner must retain its database.
            await gate.wait()
        } onCancel: { cancelled.yield(()) }
        return ClientCreationServerResult(
            operationId: request.operationId, accountId: request.accountId,
            commandFingerprint: request.fingerprint, subjectId: request.clientId,
            phase: "applied", resultCode: "client_created", errorCode: nil
        )
    }
}

private actor RuntimePhysicalSubscription: SyncStreamSubscription {
    nonisolated let name = "physical_account_items"
    nonisolated let parameters: JsonParam? = ["account_id": .string("account-runtime")]
    let cleanup: ManualGate
    private(set) var unsubscribeCount = 0
    init(cleanup: ManualGate) { self.cleanup = cleanup }
    func waitForFirstSync() async throws { Issue.record("Physical watch must not gate local rows on first sync") }
    func unsubscribe() async throws {
        unsubscribeCount += 1
        await cleanup.wait()
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
