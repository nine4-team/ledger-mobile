import Foundation
import LedgerTargetCore
import PowerSync
import Testing
@testable import LedgerTargetPowerSync

@Suite("Space assignment destination PowerSync query", .serialized)
struct SpaceAssignmentDestinationPowerSyncQueryTests {
    @Test("Exact Project scope is canonical and only a current-process stream epoch plus fresh read completes it")
    func projectScopeAndCompleteness() async throws {
        let reader = SpaceRowReader(rows: [
            Self.row("space-z", name: "loft", revision: 3, count: 3),
            Self.row("space-upper", name: "Loft", revision: 2, count: 3),
            Self.row("space-a", name: "loft", revision: 4, count: 3),
        ])
        let sync = SpaceSyncSource()
        let query = Self.query(reader: reader, sync: sync)
        var iterator = query.watchEligibleDestinations(Self.request).makeAsyncIterator()

        let partial = try #require(try await iterator.next())
        #expect(partial.local.quality == .partial)
        #expect(!partial.local.isCompleteForQuery)
        #expect(partial.local.rows.map(\.id.rawValue) == ["space-upper", "space-a", "space-z"])
        #expect(partial.local.rows.map(\.revision) == [2, 4, 3])
        #expect(sync.scopes == [Self.scope])
        #expect(sync.identities == [SpaceAssignmentDestinationSyncStreamIdentity(
            accountId: Self.accountId, scope: Self.scope
        )])

        sync.advanceSyncEpoch()
        let ready = try #require(try await iterator.next())
        #expect(ready.local.quality == .ready)
        #expect(ready.local.isCompleteForQuery)
        #expect(ready.local.queryFingerprint == partial.local.queryFingerprint)
        #expect(ready.local.localDataVersion != partial.local.localDataVersion)
        await query.cancelAndDrainWatches()
        #expect(sync.unsubscribeCount == 1)
    }

    @Test("A delayed pre-sync watch payload cannot replace causally reread ready rows")
    func delayedOldWatchPayloadIsOnlyInvalidation() async throws {
        let oldRows = [Self.row("space-old", name: "Old")]
        let freshRows = [Self.row("space-fresh", name: "Fresh", revision: 2)]
        let reader = SpaceRowReader(rows: oldRows)
        let sync = SpaceSyncSource()
        let query = Self.query(reader: reader, sync: sync)
        var iterator = query.watchEligibleDestinations(Self.request).makeAsyncIterator()
        let initial = try #require(try await iterator.next())
        #expect(initial.local.rows.map(\.id.rawValue) == ["space-old"])

        reader.setCurrentRows(freshRows)
        sync.advanceSyncEpoch()
        let ready = try #require(try await iterator.next())
        #expect(ready.local.isCompleteForQuery)
        #expect(ready.local.rows.map(\.id.rawValue) == ["space-fresh"])

        reader.yieldWatchPayload(oldRows)
        let afterDelayedOldPayload = try #require(try await iterator.next())
        #expect(afterDelayedOldPayload.local.isCompleteForQuery)
        #expect(afterDelayedOldPayload.local.rows.map(\.id.rawValue) == ["space-fresh"])
        await query.cancelAndDrainWatches()
    }

    @Test("Exact stream identities and both initial source orders are deterministic")
    func identitiesAndInitialOrders() async throws {
        let project = SpaceAssignmentDestinationSyncStreamIdentity(
            accountId: Self.accountId, scope: Self.scope
        )
        #expect(project.name == "space_assignment_project_destinations")
        #expect(project.parameters == ["project_id": .string(Self.projectId.rawValue)])
        let inventory = SpaceAssignmentDestinationSyncStreamIdentity(
            accountId: Self.accountId, scope: .businessInventory
        )
        #expect(inventory.name == "space_assignment_business_inventory_destinations")
        #expect(inventory.parameters == ["account_id": .string(Self.accountId.rawValue)])

        var rowsFirst = SpaceAssignmentDestinationObservedState()
        #expect(rowsFirst.observeRows([Self.row("space-order")]) == nil)
        #expect(rowsFirst.observeSubscriptionStarted()?.currentProcessSyncEpoch == nil)
        #expect(rowsFirst.observeCurrentProcessSync(
            epoch: 11, freshRows: [Self.row("space-order")]
        )?.currentProcessSyncEpoch == 11)

        var syncFirst = SpaceAssignmentDestinationObservedState()
        #expect(syncFirst.observeSubscriptionStarted() == nil)
        #expect(syncFirst.observeCurrentProcessSync(
            epoch: 11, freshRows: [Self.row("space-order")]
        )?.currentProcessSyncEpoch == 11)
        #expect(syncFirst.observeRows(
            [Self.row("space-order")]
        )?.currentProcessSyncEpoch == 11)
    }

    @Test("Cached rows are stale before current first sync and pre-sync cancellation unsubscribes once")
    func staleAndCancellationBeforeFirstSync() async throws {
        let reader = SpaceRowReader(
            rows: [Self.row("space-cached")], hasLastSyncedAt: true
        )
        let sync = SpaceSyncSource()
        let query = Self.query(reader: reader, sync: sync)
        var iterator = query.watchEligibleDestinations(Self.request).makeAsyncIterator()
        let stale = try #require(try await iterator.next())
        #expect(stale.local.quality == .stale)
        #expect(!stale.local.isCompleteForQuery)
        await query.cancelAndDrainWatches()
        #expect(sync.unsubscribeCount == 1)

        let cancelSync = SpaceSyncSource()
        let cancelQuery = Self.query(
            reader: SpaceRowReader(rows: [Self.row("space-cancel")]),
            sync: cancelSync
        )
        let consumer = Task {
            do {
                for try await _ in cancelQuery.watchEligibleDestinations(Self.request) {}
            } catch { }
        }
        for _ in 0..<2_000 {
            if cancelSync.scopes.count == 1 { break }
            try? await Task.sleep(for: .milliseconds(1))
        }
        consumer.cancel()
        await consumer.value
        for _ in 0..<2_000 {
            if cancelSync.unsubscribeCount == 1 { break }
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(cancelSync.unsubscribeCount == 1)
        await cancelQuery.cancelAndDrainWatches()
        #expect(cancelSync.unsubscribeCount == 1)

        let failed = Self.query(
            reader: SpaceRowReader(rows: [], startError: true),
            sync: SpaceSyncSource(autoAdvance: true)
        )
        do {
            for try await _ in failed.watchEligibleDestinations(Self.request) {
                Issue.record("Database failure emitted evidence")
            }
            Issue.record("Expected bounded read failure")
        } catch let failure as SpaceAssignmentDestinationFailure {
            #expect(failure == .localReadFailed)
        }
        await failed.cancelAndDrainWatches()
    }

    @Test("Persisted exact-stream status is only a baseline; active explicit advancement triggers one fresh read")
    func currentProcessStatusAdvance() async throws {
        let reader = SpaceRowReader(
            rows: [Self.row("space-cached")], hasLastSyncedAt: true
        )
        let sync = SpaceSyncSource(baselineLastSyncedAt: 41)
        let query = Self.query(reader: reader, sync: sync)
        var iterator = query.watchEligibleDestinations(Self.request).makeAsyncIterator()
        let cached = try #require(try await iterator.next())
        #expect(cached.local.quality == .stale)
        let readsBeforeStatuses = reader.readCount

        sync.emit(.init(connected: true, active: true, hasExplicitSubscription: true,
                        lastSyncedAt: 41))
        sync.emit(.init(connected: false, active: true, hasExplicitSubscription: true,
                        lastSyncedAt: 42))
        sync.emit(.init(connected: true, active: false, hasExplicitSubscription: true,
                        lastSyncedAt: 42))
        sync.emit(.init(connected: true, active: true, hasExplicitSubscription: false,
                        lastSyncedAt: 42))
        for invalidEpoch in [
            -1.0, 0.0, TimeInterval.nan,
            TimeInterval.infinity, -TimeInterval.infinity,
        ] {
            sync.emit(.init(
                connected: true, active: true, hasExplicitSubscription: true,
                lastSyncedAt: invalidEpoch
            ))
        }
        try? await Task.sleep(for: .milliseconds(20))
        #expect(reader.readCount == readsBeforeStatuses)

        sync.emit(.init(connected: true, active: true, hasExplicitSubscription: true,
                        lastSyncedAt: 42))
        let ready = try #require(try await iterator.next())
        #expect(ready.local.isCompleteForQuery)
        #expect(reader.readCount == readsBeforeStatuses + 1)
        await query.cancelAndDrainWatches()
        #expect(sync.unsubscribeCount == 1)
    }

    @Test("An absent baseline uses causal first sync and ignores cached pre-sync status")
    func absentBaselineRequiresCausalFirstSync() async throws {
        let reader = SpaceRowReader(rows: [Self.row("space-old")], hasLastSyncedAt: true)
        let sync = SpaceSyncSource(
            baselineLastSyncedAt: nil
        )
        let query = Self.query(reader: reader, sync: sync)
        var iterator = query.watchEligibleDestinations(Self.request).makeAsyncIterator()
        _ = try #require(try await iterator.next())
        let readsBeforeStatuses = reader.readCount

        sync.emit(.init(connected: true, active: true, hasExplicitSubscription: true,
                        lastSyncedAt: 100))
        try? await Task.sleep(for: .milliseconds(20))
        #expect(reader.readCount == readsBeforeStatuses)
        sync.completeCausalFirstSync(.init(
            connected: true, active: true, hasExplicitSubscription: true,
            lastSyncedAt: 101
        ))
        let ready = try #require(try await iterator.next())
        #expect(ready.local.isCompleteForQuery)
        #expect(reader.readCount == readsBeforeStatuses + 1)
        await query.cancelAndDrainWatches()
    }

    @Test("A causal first-sync status buffered before observation completes without another sync")
    func causalFirstSyncBufferedBeforeObserver() async throws {
        let reader = SpaceRowReader(rows: [Self.row("space-first-sync")])
        let sync = SpaceSyncSource(
            autoAdvance: true,
            baselineLastSyncedAt: nil
        )
        let query = Self.query(reader: reader, sync: sync)
        let ready = try await Self.firstReady(query)
        #expect(ready.local.rows.map(\.id.rawValue) == ["space-first-sync"])
        #expect(ready.local.isCompleteForQuery)
        await query.cancelAndDrainWatches()
        #expect(sync.unsubscribeCount == 1)
    }

    @Test("Database display-name bytes must already be canonical; exterior whitespace is refused")
    func displayNameRawBytesMustBeCanonical() throws {
        let exact = try #require(try Self.row(
            "space-exact-name", name: "Loft"
        ).destination())
        #expect(Array(exact.displayName.rawValue.utf8) == Array("Loft".utf8))
        #expect(throws: SpaceAssignmentDestinationPowerSyncFailure.malformedDestinationRow) {
            try Self.row("space-trimmed-name", name: " Loft ").destination()
        }
    }

    @Test("Inventory, membership loss, and malformed evidence fail closed atomically")
    func inventoryLossAndRefusal() async throws {
        let inventoryRequest = try SpaceAssignmentDestinationRequest(
            accountId: Self.accountId, scope: .businessInventory
        )
        let reader = SpaceRowReader(rows: [Self.row(
            "space-inventory", scopeKind: "business_inventory", projectId: nil,
            count: 1
        )])
        let sync = SpaceSyncSource(autoAdvance: true)
        let query = Self.query(reader: reader, sync: sync)
        var iterator = query.watchEligibleDestinations(inventoryRequest).makeAsyncIterator()
        var ready = try #require(try await iterator.next())
        while !ready.local.isCompleteForQuery {
            ready = try #require(try await iterator.next())
        }
        #expect(ready.local.rows[0].scope == .businessInventory)

        reader.yield([Self.sentinel(active: false)])
        let revoked = try #require(try await iterator.next())
        #expect(revoked.local.rows.isEmpty)
        #expect(revoked.local.quality == .partial)
        #expect(!revoked.local.isCompleteForQuery)

        reader.yield([Self.row(
            "space-inventory", scopeKind: "business_inventory", projectId: nil,
            count: 1
        )])
        let restoredButIncomplete = try #require(try await iterator.next())
        #expect(!restoredButIncomplete.local.isCompleteForQuery)
        #expect(restoredButIncomplete.local.quality == .partial)
        sync.advanceSyncEpoch()
        let restoredReady = try #require(try await iterator.next())
        #expect(restoredReady.local.isCompleteForQuery)
        await query.cancelAndDrainWatches()

        let invalidCases: [([SpaceAssignmentDestinationPowerSyncRow], SpaceAssignmentDestinationFailure)] = [
            ([Self.row("space-x", accountId: "account-other")], .accountScopeMismatch),
            ([Self.row("space-x", lifecycle: "archived")], .inactiveDestination),
            ([Self.row("space-x", count: 2),
              Self.row("space-x", name: "Other", count: 2)],
             .duplicateSpaceIdentity),
            ([Self.row("", count: 1)], .localReadFailed),
            ([Self.row("space-x", revision: 0)], .localReadFailed),
            ([Self.row("space-x", name: " Loft ")], .localReadFailed),
            ([Self.row("space-x", count: 2)], .visibleCountMismatch),
        ]
        for (rows, expected) in invalidCases {
            let invalid = Self.query(
                reader: SpaceRowReader(rows: rows),
                sync: SpaceSyncSource(autoAdvance: true)
            )
            do {
                for try await _ in invalid.watchEligibleDestinations(Self.request) {
                    Issue.record("Invalid evidence emitted")
                }
                Issue.record("Expected bounded failure")
            } catch let failure as SpaceAssignmentDestinationFailure {
                #expect(failure == expected)
            }
            await invalid.cancelAndDrainWatches()
        }
    }

    @Test("Encrypted production SQL scopes exactly and preserves malformed lifecycle evidence for refusal")
    func encryptedProductionReaderScopeAndRefusalMatrix() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("space-reader-matrix-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try LedgerPowerSyncDatabaseFactory.open(
            absolutePath: root.appendingPathComponent("ledger.sqlite").path,
            encryptionKey: try LedgerPowerSyncEncryptionKey(
                hexadecimal: String(repeating: "3b", count: 32)
            )
        )
        _ = try await database.execute(sql: """
            INSERT INTO spike_account_memberships
              (id, account_id, principal_id, role, state, can_manage_clients,
               can_manage_projects, can_manage_project_budgets, financial_access)
            VALUES
              ('membership-exact', 'account-space', 'principal-space', 'owner', 'active', 1, 1, 1, 'full'),
              ('membership-other-principal', 'account-space', 'principal-other', 'owner', 'active', 1, 1, 1, 'full'),
              ('membership-other-account', 'account-other', 'principal-space', 'owner', 'active', 1, 1, 1, 'full')
            """, parameters: nil)
        _ = try await database.execute(sql: """
            INSERT INTO spike_spaces
              (id, account_id, scope_kind, project_id, display_name, lifecycle, revision)
            VALUES
              ('space-valid', 'account-space', 'project', 'project-space', 'Valid', 'active', 1),
              ('space-archived', 'account-space', 'project', 'project-space', 'Archived', 'archived', 2),
              ('space-unknown-lifecycle', 'account-space', 'project', 'project-space', 'Unknown', 'unknown', 3),
              ('space-zero-revision', 'account-space', 'project', 'project-space', 'Zero', 'active', 0),
              ('space-whitespace', 'account-space', 'project', 'project-space', ' Exterior ', 'active', 4),
              ('space-other-project', 'account-space', 'project', 'project-other', 'Other project', 'active', 1),
              ('space-other-account', 'account-other', 'project', 'project-space', 'Other account', 'active', 1),
              ('space-inventory', 'account-space', 'business_inventory', NULL, 'Inventory', 'active', 5),
              ('space-inventory-with-project', 'account-space', 'business_inventory', 'project-space', 'Bad inventory', 'active', 6)
            """, parameters: nil)

        let reader = PowerSyncSpaceAssignmentDestinationLocalReader(database: database)
        let projectRows = try await reader.readRows(
            request: Self.request, principalId: Self.principalId
        )
        #expect(Set(projectRows.compactMap(\.id)) == Set([
            "space-valid", "space-archived", "space-unknown-lifecycle",
            "space-zero-revision", "space-whitespace",
        ]))
        #expect(projectRows.allSatisfy { $0.visibleCount == 5 })
        for refusedID in [
            "space-archived", "space-unknown-lifecycle", "space-zero-revision",
            "space-whitespace",
        ] {
            let row = try #require(projectRows.first { $0.id == refusedID })
            #expect(throws: (any Error).self) { try row.destination() }
        }
        let valid = try #require(try projectRows.first { $0.id == "space-valid" }?.destination())
        #expect(valid.displayName.rawValue == "Valid")

        let inventoryRequest = try SpaceAssignmentDestinationRequest(
            accountId: Self.accountId, scope: .businessInventory
        )
        let inventoryRows = try await reader.readRows(
            request: inventoryRequest, principalId: Self.principalId
        )
        #expect(inventoryRows.compactMap(\.id) == ["space-inventory"])
        #expect(inventoryRows[0].visibleCount == 1)

        _ = try await database.execute(
            sql: "DELETE FROM spike_account_memberships WHERE id = 'membership-exact'",
            parameters: nil
        )
        let missingWithCrossPrincipal = try await reader.readRows(
            request: Self.request, principalId: Self.principalId
        )
        #expect(missingWithCrossPrincipal == [Self.sentinel(active: false)])
        _ = try await database.execute(sql: """
            INSERT INTO spike_account_memberships
              (id, account_id, principal_id, role, state, can_manage_clients,
               can_manage_projects, can_manage_project_budgets, financial_access)
            VALUES ('membership-inactive', 'account-space', 'principal-space', 'owner',
                    'inactive', 1, 1, 1, 'full')
            """, parameters: nil)
        let inactive = try await reader.readRows(
            request: Self.request, principalId: Self.principalId
        )
        #expect(inactive == [Self.sentinel(active: false)])

        try await database.close(deleteDatabase: true)
    }

    @Test("Production subscription source executes the exact Project and Inventory identities")
    func productionSubscriptionIdentityExecution() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("space-stream-identity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try LedgerPowerSyncDatabaseFactory.open(
            absolutePath: root.appendingPathComponent("ledger.sqlite").path,
            encryptionKey: try LedgerPowerSyncEncryptionKey(
                hexadecimal: String(repeating: "4c", count: 32)
            )
        )
        let source = PowerSyncSpaceAssignmentDestinationSyncSource(database: database)
        let project = try await source.subscribe(
            accountId: Self.accountId, scope: Self.scope
        )
        #expect(project.identity.name == "space_assignment_project_destinations")
        #expect(project.identity.parameters == ["project_id": .string(Self.projectId.rawValue)])
        try await project.unsubscribe()
        let inventory = try await source.subscribe(
            accountId: Self.accountId, scope: .businessInventory
        )
        #expect(inventory.identity.name == "space_assignment_business_inventory_destinations")
        #expect(inventory.identity.parameters == ["account_id": .string(Self.accountId.rawValue)])
        try await inventory.unsubscribe()
        try await database.close(deleteDatabase: true)
    }

    @Test("Production SDK status observer and deinit-owned subscription drain before database close")
    func productionSubscriptionDrainsBeforeClose() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("space-stream-drain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try LedgerPowerSyncDatabaseFactory.open(
            absolutePath: root.appendingPathComponent("ledger.sqlite").path,
            encryptionKey: try LedgerPowerSyncEncryptionKey(
                hexadecimal: String(repeating: "5d", count: 32)
            )
        )
        let lifecycle = SpaceProductionLifecycleRecorder()
        let source = SpaceProductionLifecycleSyncSource(
            base: PowerSyncSpaceAssignmentDestinationSyncSource(database: database),
            lifecycle: lifecycle
        )
        let query = SpaceAssignmentDestinationPowerSyncQuery(
            localReader: PowerSyncSpaceAssignmentDestinationLocalReader(database: database),
            syncSource: source,
            principalId: Self.principalId,
            accountId: Self.accountId
        )
        let consumer = Task {
            do {
                for try await _ in query.watchEligibleDestinations(Self.request) {}
            } catch { }
        }
        await Self.waitUntil {
            lifecycle.events.contains("observe-start")
        }
        #expect(lifecycle.events.contains("observe-start"))

        await query.cancelAndDrainWatches()
        await consumer.value
        #expect(lifecycle.events == [
            "subscribe", "observe-start", "observe-end", "unsubscribe", "subscription-deinit",
        ])
        try await database.close(deleteDatabase: true)
        lifecycle.append("database-close")
        #expect(lifecycle.events.last == "database-close")
    }

    @Test("Retained internal exact-stream epoch cannot complete when public baseline is absent")
    func encryptedRetainedEpochRequiresStrictAdvancement() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("space-retained-epoch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try LedgerPowerSyncDatabaseFactory.open(
            absolutePath: root.appendingPathComponent("ledger.sqlite").path,
            encryptionKey: try LedgerPowerSyncEncryptionKey(
                hexadecimal: String(repeating: "6e", count: 32)
            )
        )
        try await Self.seed(database)
        let identity = SpaceAssignmentDestinationSyncStreamIdentity(
            accountId: Self.accountId, scope: Self.scope
        )
        for _ in 0..<2_000 {
            if database.currentStatus.syncStreams != nil { break }
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(database.currentStatus.syncStreams != nil)
        #expect(database.currentStatus.forStream(stream: identity) == nil)

        // PowerSync core 0.5.3 stores stream parameters as JSON and timestamps as
        // integer microseconds. Seed after the public status snapshot is loaded so
        // the retained exact row is deliberately absent from that snapshot.
        _ = try await database.execute(sql: """
            INSERT INTO ps_stream_subscriptions
              (stream_name, active, is_default, local_params, last_synced_at)
            VALUES (?, 1, 0, ?, ?)
            """, parameters: [
                identity.name,
                #"{"project_id":"project-space"}"#,
                Int64(41_000_000),
            ])
        #expect(database.currentStatus.forStream(stream: identity) == nil)

        let retained = try await PowerSyncSpaceAssignmentDestinationSyncSource(
            database: database
        ).subscribe(accountId: Self.accountId, scope: Self.scope)
        #expect(retained.baselineLastSyncedAt == 41)
        let controlled = SpaceControlledProductionSubscription(base: retained)
        let reader = SpaceCountingLocalReader(
            base: PowerSyncSpaceAssignmentDestinationLocalReader(database: database)
        )
        let query = SpaceAssignmentDestinationPowerSyncQuery(
            localReader: reader,
            syncSource: SpaceSingleSubscriptionSource(subscription: controlled),
            principalId: Self.principalId,
            accountId: Self.accountId,
            now: { Date(timeIntervalSince1970: 1_788_600_000) }
        )
        var iterator = query.watchEligibleDestinations(Self.request).makeAsyncIterator()
        let initial = try #require(try await iterator.next())
        #expect(!initial.local.isCompleteForQuery)
        let readsBeforeOldEpoch = reader.readCount

        controlled.emit(.init(
            connected: true, active: true, hasExplicitSubscription: true,
            lastSyncedAt: 41
        ))
        try? await Task.sleep(for: .milliseconds(20))
        #expect(reader.readCount == readsBeforeOldEpoch)

        controlled.emit(.init(
            connected: true, active: true, hasExplicitSubscription: true,
            lastSyncedAt: 42
        ))
        let ready = try #require(try await iterator.next())
        #expect(ready.local.isCompleteForQuery)
        #expect(ready.local.rows.map(\.id.rawValue) == ["space-persisted"])
        #expect(reader.readCount == readsBeforeOldEpoch + 1)
        await query.cancelAndDrainWatches()
        #expect(controlled.waitForFirstSyncCallCount == 0)
        #expect(controlled.unsubscribeCount == 1)
        try await database.close(deleteDatabase: true)
    }

    @Test("Encrypted restart preserves rows but resets exact-subscription completeness")
    func encryptedRestartResetsCompleteness() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("space-destination-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("ledger.sqlite").path
        let key = try LedgerPowerSyncEncryptionKey(
            hexadecimal: String(repeating: "2a", count: 32)
        )
        let first = try LedgerPowerSyncDatabaseFactory.open(absolutePath: path, encryptionKey: key)
        try await Self.seed(first)
        let firstSync = SpaceSyncSource(autoAdvance: true)
        // Live subscriptions cannot complete without a connector, so use the same encrypted reader
        // with the reciprocal deterministic subscription source for lifecycle proof.
        let firstReader = PowerSyncSpaceAssignmentDestinationLocalReader(database: first)
        let deterministicFirst = Self.query(reader: firstReader, sync: firstSync)
        let before = try await Self.firstReady(deterministicFirst)
        #expect(before.local.rows.map(\.id.rawValue) == ["space-persisted"])
        let inventory = Self.query(
            reader: PowerSyncSpaceAssignmentDestinationLocalReader(database: first),
            sync: SpaceSyncSource(autoAdvance: true)
        )
        let inventoryRequest = try SpaceAssignmentDestinationRequest(
            accountId: Self.accountId, scope: .businessInventory
        )
        var inventoryReady: SpaceAssignmentDestinationDirectorySnapshot?
        for try await value in inventory.watchEligibleDestinations(inventoryRequest) {
            if value.local.isCompleteForQuery { inventoryReady = value; break }
        }
        #expect(inventoryReady?.local.rows.map(\.id.rawValue) == ["space-inventory-persisted"])
        await inventory.cancelAndDrainWatches()
        await deterministicFirst.cancelAndDrainWatches()
        try await first.close(deleteDatabase: false)

        let reopened = try LedgerPowerSyncDatabaseFactory.open(absolutePath: path, encryptionKey: key)
        let restartSync = SpaceSyncSource()
        let restarted = Self.query(
            reader: PowerSyncSpaceAssignmentDestinationLocalReader(database: reopened),
            sync: restartSync
        )
        var iterator = restarted.watchEligibleDestinations(Self.request).makeAsyncIterator()
        let cached = try #require(try await iterator.next())
        #expect(cached.local.rows.map(\.id.rawValue) == before.local.rows.map(\.id.rawValue))
        #expect(!cached.local.isCompleteForQuery)
        #expect(cached.local.quality == .partial)
        restartSync.advanceSyncEpoch()
        let ready = try #require(try await iterator.next())
        #expect(ready.local.isCompleteForQuery)
        await restarted.cancelAndDrainWatches()
        try await reopened.close(deleteDatabase: true)
    }

    private static let accountId = try! AccountID(validating: "account-space")
    private static let principalId = try! PrincipalID(validating: "principal-space")
    private static let projectId = try! ProjectID(validating: "project-space")
    private static let scope = ItemPlacementScope.project(projectId)
    private static let request = try! SpaceAssignmentDestinationRequest(
        accountId: accountId, scope: scope
    )

    private static func query(
        reader: any SpaceAssignmentDestinationLocalReading,
        sync: any SpaceAssignmentDestinationSyncSubscribing
    ) -> SpaceAssignmentDestinationPowerSyncQuery {
        .init(localReader: reader, syncSource: sync, principalId: principalId,
              accountId: accountId,
              now: { Date(timeIntervalSince1970: 1_788_600_000) })
    }

    private static func row(
        _ id: String, name: String = "Loft", accountId: String = accountId.rawValue,
        scopeKind: String = "project", projectId: String? = projectId.rawValue,
        lifecycle: String = "active", revision: Int64 = 1, count: Int64 = 1
    ) -> SpaceAssignmentDestinationPowerSyncRow {
        .init(scopeRawValue: 1, visibleCount: count, id: id, accountId: accountId,
              scopeKind: scopeKind, projectId: projectId, displayName: name,
              lifecycle: lifecycle, revision: revision)
    }

    private static func sentinel(active: Bool) -> SpaceAssignmentDestinationPowerSyncRow {
        .init(scopeRawValue: active ? 1 : 0, visibleCount: 0, id: nil,
              accountId: nil, scopeKind: nil, projectId: nil, displayName: nil,
              lifecycle: nil, revision: nil)
    }

    private static func firstReady(
        _ query: SpaceAssignmentDestinationPowerSyncQuery
    ) async throws -> SpaceAssignmentDestinationDirectorySnapshot {
        for try await value in query.watchEligibleDestinations(request) {
            if value.local.isCompleteForQuery { return value }
        }
        throw SpaceAssignmentDestinationFailure.localReadFailed
    }

    private static func waitUntil(_ condition: @escaping @Sendable () -> Bool) async {
        for _ in 0..<2_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Timed out waiting for production PowerSync lifecycle state")
    }

    private static func seed(_ database: any PowerSyncDatabaseProtocol) async throws {
        _ = try await database.execute(sql: """
            INSERT INTO spike_account_memberships
              (id, account_id, principal_id, role, state, can_manage_clients,
               can_manage_projects, can_manage_project_budgets, financial_access)
            VALUES ('membership-space', ?, ?, 'owner', 'active', 1, 1, 1, 'full')
            """, parameters: [accountId.rawValue, principalId.rawValue])
        _ = try await database.execute(sql: """
            INSERT INTO spike_spaces
              (id, account_id, scope_kind, project_id, display_name, lifecycle, revision)
            VALUES ('space-persisted', ?, 'project', ?, 'Persisted', 'active', 9)
            """, parameters: [accountId.rawValue, projectId.rawValue])
        _ = try await database.execute(sql: """
            INSERT INTO spike_spaces
              (id, account_id, scope_kind, project_id, display_name, lifecycle, revision)
            VALUES ('space-inventory-persisted', ?, 'business_inventory', NULL,
                    'Inventory', 'active', 10)
            """, parameters: [accountId.rawValue])
    }
}

private final class SpaceRowReader: SpaceAssignmentDestinationLocalReading, @unchecked Sendable {
    let hasLastSyncedAt: Bool
    private let lock = NSLock()
    private var currentRows: [SpaceAssignmentDestinationPowerSyncRow]
    private var reads = 0
    private let stream: AsyncThrowingStream<[SpaceAssignmentDestinationPowerSyncRow], Error>
    private let continuation: AsyncThrowingStream<[SpaceAssignmentDestinationPowerSyncRow], Error>.Continuation
    private let startError: Bool
    init(rows: [SpaceAssignmentDestinationPowerSyncRow], hasLastSyncedAt: Bool = false,
         startError: Bool = false) {
        self.hasLastSyncedAt = hasLastSyncedAt
        self.startError = startError
        currentRows = rows
        (stream, continuation) = AsyncThrowingStream.makeStream()
        continuation.yield(rows)
    }
    var readCount: Int { lock.withLock { reads } }
    func readRows(request: SpaceAssignmentDestinationRequest, principalId: PrincipalID) async throws
        -> [SpaceAssignmentDestinationPowerSyncRow]
    {
        if startError { throw SpaceDestinationInjectedReadFailure() }
        return lock.withLock {
            reads += 1
            return currentRows
        }
    }
    func watchRows(request: SpaceAssignmentDestinationRequest, principalId: PrincipalID) throws
        -> AsyncThrowingStream<[SpaceAssignmentDestinationPowerSyncRow], Error> {
        if startError { throw SpaceDestinationInjectedReadFailure() }
        return stream
    }
    func yield(_ rows: [SpaceAssignmentDestinationPowerSyncRow]) {
        lock.withLock { currentRows = rows }
        continuation.yield(rows)
    }
    func setCurrentRows(_ rows: [SpaceAssignmentDestinationPowerSyncRow]) {
        lock.withLock { currentRows = rows }
    }
    func yieldWatchPayload(_ rows: [SpaceAssignmentDestinationPowerSyncRow]) {
        continuation.yield(rows)
    }
}

private struct SpaceDestinationInjectedReadFailure: Error {}

private final class SpaceCountingLocalReader:
    SpaceAssignmentDestinationLocalReading, @unchecked Sendable
{
    private let base: any SpaceAssignmentDestinationLocalReading
    private let lock = NSLock()
    private var reads = 0
    init(base: any SpaceAssignmentDestinationLocalReading) { self.base = base }
    var hasLastSyncedAt: Bool { base.hasLastSyncedAt }
    var readCount: Int { lock.withLock { reads } }
    func readRows(
        request: SpaceAssignmentDestinationRequest,
        principalId: PrincipalID
    ) async throws -> [SpaceAssignmentDestinationPowerSyncRow] {
        lock.withLock { reads += 1 }
        return try await base.readRows(request: request, principalId: principalId)
    }
    func watchRows(
        request: SpaceAssignmentDestinationRequest,
        principalId: PrincipalID
    ) throws -> AsyncThrowingStream<[SpaceAssignmentDestinationPowerSyncRow], Error> {
        try base.watchRows(request: request, principalId: principalId)
    }
}

private final class SpaceSingleSubscriptionSource:
    SpaceAssignmentDestinationSyncSubscribing, @unchecked Sendable
{
    private let subscription: any SpaceAssignmentDestinationSyncSubscription
    private let lock = NSLock()
    private var taken = false
    init(subscription: any SpaceAssignmentDestinationSyncSubscription) {
        self.subscription = subscription
    }
    func subscribe(accountId: AccountID, scope: ItemPlacementScope) async throws
        -> any SpaceAssignmentDestinationSyncSubscription
    {
        let isFirst = lock.withLock {
            defer { taken = true }
            return !taken
        }
        guard isFirst else { throw SpaceDestinationInjectedReadFailure() }
        return subscription
    }
}

private final class SpaceControlledProductionSubscription:
    SpaceAssignmentDestinationSyncSubscription, @unchecked Sendable
{
    private let base: any SpaceAssignmentDestinationSyncSubscription
    private let stream: AsyncStream<SpaceAssignmentDestinationSyncStreamStatus>
    private let continuation: AsyncStream<SpaceAssignmentDestinationSyncStreamStatus>.Continuation
    private let lock = NSLock()
    private var waitCalls = 0
    private var unsubscribed = 0
    var identity: SpaceAssignmentDestinationSyncStreamIdentity { base.identity }
    var baselineLastSyncedAt: TimeInterval? { base.baselineLastSyncedAt }
    init(base: any SpaceAssignmentDestinationSyncSubscription) {
        self.base = base
        (stream, continuation) = AsyncStream.makeStream()
    }
    var waitForFirstSyncCallCount: Int { lock.withLock { waitCalls } }
    var unsubscribeCount: Int { lock.withLock { unsubscribed } }
    func waitForFirstSync() async throws {
        lock.withLock { waitCalls += 1 }
        throw SpaceDestinationInjectedReadFailure()
    }
    func currentStatus() -> SpaceAssignmentDestinationSyncStreamStatus? { nil }
    func observeStatus(
        _ receive: @Sendable (SpaceAssignmentDestinationSyncStreamStatus) async throws -> Void
    ) async throws {
        for await status in stream {
            try Task.checkCancellation()
            try await receive(status)
        }
        try Task.checkCancellation()
    }
    func emit(_ status: SpaceAssignmentDestinationSyncStreamStatus) {
        continuation.yield(status)
    }
    func unsubscribe() async throws {
        lock.withLock { unsubscribed += 1 }
        continuation.finish()
        try await base.unsubscribe()
    }
}

private final class SpaceProductionLifecycleRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    var events: [String] { lock.withLock { recorded } }
    func append(_ event: String) { lock.withLock { recorded.append(event) } }
}

private final class SpaceProductionLifecycleSyncSource:
    SpaceAssignmentDestinationSyncSubscribing, @unchecked Sendable
{
    private let base: PowerSyncSpaceAssignmentDestinationSyncSource
    private let lifecycle: SpaceProductionLifecycleRecorder
    init(
        base: PowerSyncSpaceAssignmentDestinationSyncSource,
        lifecycle: SpaceProductionLifecycleRecorder
    ) {
        self.base = base
        self.lifecycle = lifecycle
    }
    func subscribe(accountId: AccountID, scope: ItemPlacementScope) async throws
        -> any SpaceAssignmentDestinationSyncSubscription
    {
        let subscription = try await base.subscribe(accountId: accountId, scope: scope)
        lifecycle.append("subscribe")
        return SpaceProductionLifecycleSubscription(
            base: subscription,
            lifecycle: lifecycle
        )
    }
}

private final class SpaceProductionLifecycleSubscription:
    SpaceAssignmentDestinationSyncSubscription, @unchecked Sendable
{
    private let base: any SpaceAssignmentDestinationSyncSubscription
    private let lifecycle: SpaceProductionLifecycleRecorder
    var identity: SpaceAssignmentDestinationSyncStreamIdentity { base.identity }
    // Force the strict-baseline branch so the real production status observer is exercised
    // without requiring a connector or hosted sync in this local lifecycle test.
    var baselineLastSyncedAt: TimeInterval? { base.baselineLastSyncedAt ?? 1 }
    init(
        base: any SpaceAssignmentDestinationSyncSubscription,
        lifecycle: SpaceProductionLifecycleRecorder
    ) {
        self.base = base
        self.lifecycle = lifecycle
    }
    deinit { lifecycle.append("subscription-deinit") }
    func waitForFirstSync() async throws { try await base.waitForFirstSync() }
    func currentStatus() -> SpaceAssignmentDestinationSyncStreamStatus? {
        base.currentStatus()
    }
    func observeStatus(
        _ receive: @Sendable (SpaceAssignmentDestinationSyncStreamStatus) async throws -> Void
    ) async throws {
        lifecycle.append("observe-start")
        defer { lifecycle.append("observe-end") }
        try await base.observeStatus(receive)
    }
    func unsubscribe() async throws {
        lifecycle.append("unsubscribe")
        try await base.unsubscribe()
    }
}

private final class SpaceSyncSource: SpaceAssignmentDestinationSyncSubscribing, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ItemPlacementScope] = []
    private var recordedIdentities: [SpaceAssignmentDestinationSyncStreamIdentity] = []
    private var subscriptions: [SpaceTestSubscription] = []
    private let autoAdvance: Bool
    private let baselineLastSyncedAt: TimeInterval?
    init(
        autoAdvance: Bool = false,
        baselineLastSyncedAt: TimeInterval? = 10
    ) {
        self.autoAdvance = autoAdvance
        self.baselineLastSyncedAt = baselineLastSyncedAt
    }
    var scopes: [ItemPlacementScope] { lock.withLock { recorded } }
    var identities: [SpaceAssignmentDestinationSyncStreamIdentity] {
        lock.withLock { recordedIdentities }
    }
    var unsubscribeCount: Int { lock.withLock { subscriptions.reduce(0) { $0 + $1.unsubscribeCount } } }
    func subscribe(accountId: AccountID, scope: ItemPlacementScope) async throws
        -> any SpaceAssignmentDestinationSyncSubscription
    {
        let identity = SpaceAssignmentDestinationSyncStreamIdentity(
            accountId: accountId, scope: scope
        )
        let subscription = SpaceTestSubscription(
            identity: identity,
            baselineLastSyncedAt: baselineLastSyncedAt,
            autoAdvance: autoAdvance
        )
        lock.withLock {
            recorded.append(scope)
            recordedIdentities.append(identity)
            subscriptions.append(subscription)
        }
        return subscription
    }
    func advanceSyncEpoch() { lock.withLock { subscriptions }.forEach { $0.advance() } }
    func emit(_ status: SpaceAssignmentDestinationSyncStreamStatus) {
        lock.withLock { subscriptions }.forEach { $0.emit(status) }
    }
    func completeCausalFirstSync(
        _ status: SpaceAssignmentDestinationSyncStreamStatus
    ) {
        lock.withLock { subscriptions }.forEach { $0.completeFirstSync(status) }
    }
}

private final class SpaceTestSubscription: SpaceAssignmentDestinationSyncSubscription, @unchecked Sendable {
    private let lock = NSLock()
    let identity: SpaceAssignmentDestinationSyncStreamIdentity
    let baselineLastSyncedAt: TimeInterval?
    private let stream: AsyncStream<SpaceAssignmentDestinationSyncStreamStatus>
    private let continuation: AsyncStream<SpaceAssignmentDestinationSyncStreamStatus>.Continuation
    private let firstSyncStream: AsyncStream<Void>
    private let firstSyncContinuation: AsyncStream<Void>.Continuation
    private var nextEpoch: TimeInterval
    private var latestStatus: SpaceAssignmentDestinationSyncStreamStatus?
    private var unsubscribed = 0
    init(
        identity: SpaceAssignmentDestinationSyncStreamIdentity,
        baselineLastSyncedAt: TimeInterval?,
        autoAdvance: Bool
    ) {
        self.identity = identity
        self.baselineLastSyncedAt = baselineLastSyncedAt
        nextEpoch = (baselineLastSyncedAt ?? 0) + 1
        (stream, continuation) = AsyncStream.makeStream()
        (firstSyncStream, firstSyncContinuation) = AsyncStream.makeStream()
        if autoAdvance {
            let status = SpaceAssignmentDestinationSyncStreamStatus(
                connected: true,
                active: true,
                hasExplicitSubscription: true,
                lastSyncedAt: nextEpoch
            )
            latestStatus = status
            continuation.yield(status)
            firstSyncContinuation.yield(())
            firstSyncContinuation.finish()
            nextEpoch += 1
        }
    }
    var unsubscribeCount: Int { lock.withLock { unsubscribed } }
    func waitForFirstSync() async throws {
        for await _ in firstSyncStream { return }
        try Task.checkCancellation()
    }
    func currentStatus() -> SpaceAssignmentDestinationSyncStreamStatus? {
        lock.withLock { latestStatus }
    }
    func observeStatus(
        _ receive: @Sendable (SpaceAssignmentDestinationSyncStreamStatus) async throws -> Void
    ) async throws {
        for await status in stream {
            try Task.checkCancellation()
            try await receive(status)
        }
        try Task.checkCancellation()
    }
    func advance() {
        let epoch = lock.withLock {
            let value = nextEpoch
            nextEpoch += 1
            return value
        }
        completeFirstSync(.init(
            connected: true, active: true, hasExplicitSubscription: true,
            lastSyncedAt: epoch
        ))
    }
    func emit(_ status: SpaceAssignmentDestinationSyncStreamStatus) {
        lock.withLock { latestStatus = status }
        continuation.yield(status)
    }
    func completeFirstSync(_ status: SpaceAssignmentDestinationSyncStreamStatus) {
        emit(status)
        firstSyncContinuation.yield(())
        firstSyncContinuation.finish()
    }
    func unsubscribe() async throws {
        lock.withLock { unsubscribed += 1 }
        continuation.finish()
        firstSyncContinuation.finish()
    }
}
