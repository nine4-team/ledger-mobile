import Foundation
import LedgerTargetCore
import PowerSync
import Testing
@testable import LedgerTargetPowerSync

@Suite("Space core-details PowerSync provider")
struct SpaceCoreDetailsPowerSyncQueryTests {
    @Test("Project Space reconstructs ordered relational hierarchy and exact values")
    func projectHierarchy() throws {
        let rows = [
            Self.row(checklistRow: "check-b", checklist: "install", checklistName: "Install", checklistOrder: 20,
                     itemRow: "item-b2", item: "shared", itemText: "Hang art", checked: 1, itemOrder: 2),
            Self.row(checklistRow: "check-a", checklist: "prepare", checklistName: "Prepare", checklistOrder: 10,
                     itemRow: "item-a1", item: "shared", itemText: "Protect floor", checked: 1, itemOrder: 1),
            Self.row(checklistRow: "check-b", checklist: "install", checklistName: "Install", checklistOrder: 20,
                     itemRow: "item-b1", item: "level", itemText: "Level frames", checked: 0, itemOrder: 1),
            Self.row(checklistRow: "check-empty", checklist: "empty", checklistName: "Empty", checklistOrder: 30),
        ]
        let snapshot = try SpaceCoreDetailsPowerSyncQuery.localSnapshot(
            request: Self.request,
            rows: rows,
            streamCompletionReported: true,
            hasLastSyncedAt: true,
            asOf: Self.asOf
        )
        let space = try #require(snapshot.row)
        #expect(snapshot.local.quality == .ready)
        #expect(snapshot.local.isCompleteForQuery)
        #expect(space.scope == .project(Self.projectId))
        #expect(space.displayName.rawValue == "Living Room")
        #expect(space.notes.value == "Keep original trim")
        #expect(space.lifecycle == .active)
        #expect(space.revision == UInt64(Int64.max))
        #expect(space.createdAt == Date(timeIntervalSince1970: Double(Self.createdMS) / 1_000))
        #expect(space.updatedAt == Date(timeIntervalSince1970: Double(Self.updatedMS) / 1_000))
        #expect(space.checklists.checklists.map(\.id.rawValue) == ["prepare", "install", "empty"])
        #expect(space.checklists.checklists[1].items.map(\.id.rawValue) == ["level", "shared"])
        #expect(space.completedItemCount == 2)
        #expect(space.totalItemCount == 3)
        #expect(snapshot.progressCountsAreAuthoritative)
    }

    @Test("Archived inventory Space and authoritative absence retain distinct truth")
    func archivedInventoryAndAbsence() throws {
        let inventory = Self.row(
            scopeKind: "business_inventory",
            projectId: nil,
            lifecycle: "archived",
            notes: nil
        )
        let found = try SpaceCoreDetailsPowerSyncQuery.localSnapshot(
            request: Self.request,
            rows: [inventory],
            streamCompletionReported: false,
            hasLastSyncedAt: true,
            asOf: Self.asOf
        )
        #expect(found.row?.scope == .businessInventory)
        #expect(found.row?.lifecycle == .archived)
        #expect(found.row?.notes.value == nil)
        #expect(found.local.quality == .stale)
        #expect(!found.local.isCompleteForQuery)

        let absent = try SpaceCoreDetailsPowerSyncQuery.localSnapshot(
            request: Self.request,
            rows: [Self.sentinel(active: 1)],
            streamCompletionReported: true,
            hasLastSyncedAt: true,
            asOf: Self.asOf
        )
        #expect(absent.row == nil)
        #expect(absent.isAuthoritativeAbsence)

        let revoked = try SpaceCoreDetailsPowerSyncQuery.localSnapshot(
            request: Self.request,
            rows: [Self.sentinel(active: 0)],
            streamCompletionReported: true,
            hasLastSyncedAt: true,
            asOf: Self.asOf
        )
        #expect(revoked.row == nil)
        #expect(revoked.local.quality == .partial)
        #expect(!revoked.local.isCompleteForQuery)
        #expect(!revoked.isAuthoritativeAbsence)
    }

    @Test("Malformed, rebound, duplicate and overflow evidence fails atomically")
    func malformedEvidence() {
        let malformed: [[SpaceCoreDetailsPowerSyncRow]] = [
            [],
            [Self.sentinel(active: 2)],
            [Self.row(account: "other-account")],
            [Self.row(space: "other-space")],
            [Self.row(revision: 0)],
            [Self.row(detailId: nil)],
            [Self.row(displayName: " Living Room ")],
            [Self.row(notes: " Keep original trim ")],
            [Self.row(createdMS: Int64.max)],
            [Self.row(scopeKind: "business_inventory", projectId: "project")],
            [Self.row(checklistRow: "c", checklist: "c", checklistName: " C ", checklistOrder: 0)],
            [Self.row(checklistRow: "c", checklist: "c", checklistName: "C", checklistOrder: -1)],
            [Self.row(checklistRow: "c", checklist: "c", checklistName: "C", checklistOrder: 4_294_967_296)],
            [Self.row(checklistRow: "c", checklist: "c", checklistName: "C", checklistOrder: 0,
                      itemRow: "i", item: "i", itemText: " I ", checked: 0, itemOrder: 0)],
            [Self.row(checklistRow: "c", checklist: "c", checklistName: "C", checklistOrder: 0,
                      itemRow: "i", item: "i", itemText: "I", checked: 2, itemOrder: 0)],
            [
                Self.row(checklistRow: "c", checklist: "c", checklistName: "C", checklistOrder: 0,
                         itemRow: "same-row", item: "one", itemText: "One", checked: 0, itemOrder: 0),
                Self.row(checklistRow: "c", checklist: "c", checklistName: "C", checklistOrder: 0,
                         itemRow: "same-row", item: "two", itemText: "Two", checked: 0, itemOrder: 1),
            ],
        ]
        for rows in malformed {
            #expect(throws: (any Error).self) {
                try SpaceCoreDetailsPowerSyncQuery.localSnapshot(
                    request: Self.request,
                    rows: rows,
                    streamCompletionReported: true,
                    hasLastSyncedAt: true,
                    asOf: Self.asOf
                )
            }
        }
    }

    @Test("Exact Account binding rejects cross-workspace requests before observation")
    func accountBinding() async throws {
        let reader = ControlledSpaceDetailsReader(rows: [Self.row()])
        let completeness = ControlledSpaceDetailsCompleteness()
        let query = SpaceCoreDetailsPowerSyncQuery(
            localReader: reader,
            principalId: Self.principalId,
            accountId: Self.accountId,
            completenessObservation: { _, _ in completeness.stream }
        )
        let other = try SpaceCoreDetailsRequest(
            accountId: AccountID(validating: "other-account"),
            spaceId: Self.spaceId
        )
        var iterator = query.watchSpaceCoreDetails(other).makeAsyncIterator()
        do {
            _ = try await iterator.next()
            Issue.record("Expected exact Account binding failure")
        } catch let failure as SpaceCoreDetailsFailure {
            #expect(failure == .accountScopeMismatch)
        }
        #expect(!reader.didInstallWatch)
    }

    @Test("Rows and exact-stream completion combine causally and revocation clears readiness")
    func causalCompletenessAndRevocation() async throws {
        let reader = ControlledSpaceDetailsReader(rows: [Self.row()], hasLastSyncedAt: true)
        let completeness = ControlledSpaceDetailsCompleteness()
        let query = SpaceCoreDetailsPowerSyncQuery(
            localReader: reader,
            principalId: Self.principalId,
            accountId: Self.accountId,
            completenessObservation: { account, space in
                #expect(account == Self.accountId)
                #expect(space == Self.spaceId)
                return completeness.stream
            },
            now: { Self.asOf }
        )
        let updates = LockedSpaceDetailsUpdates()
        let consumer = Task {
            do {
                for try await update in query.watchSpaceCoreDetails(Self.request) {
                    updates.append(update)
                }
            } catch { updates.record(error) }
        }
        await Self.waitUntil { reader.didInstallWatch && completeness.didInstall }
        completeness.send(false)
        reader.invalidate()
        await Self.waitUntil { updates.snapshots.contains(where: { $0.local.quality == .stale }) }
        #expect(!updates.snapshots.last!.local.isCompleteForQuery)

        completeness.send(true)
        await Self.waitUntil { updates.snapshots.last?.local.quality == .ready }
        #expect(updates.snapshots.last?.row?.id == Self.spaceId)

        reader.replace(with: [Self.sentinel(active: 0)])
        reader.invalidate()
        await Self.waitUntil { updates.snapshots.last?.local.quality == .partial && updates.snapshots.last?.row == nil }
        #expect(updates.snapshots.last?.local.isCompleteForQuery == false)

        reader.replace(with: [Self.row(lifecycle: "archived")])
        reader.invalidate()
        await Self.waitUntil { updates.snapshots.last?.row?.lifecycle == .archived }
        #expect(updates.snapshots.last?.local.quality == .stale)
        completeness.send(true)
        await Self.waitUntil { updates.snapshots.last?.local.quality == .ready }

        consumer.cancel()
        await query.cancelAndDrainWatches()
        _ = await consumer.result
        #expect(reader.terminationCount == 1)
        #expect(completeness.terminationCount == 1)
        #expect(updates.error == nil)
    }

    @Test("Completion before the first row event performs an exact fresh read")
    func completionBeforeRows() async throws {
        let reader = ControlledSpaceDetailsReader(rows: [Self.row()], hasLastSyncedAt: true)
        let completeness = ControlledSpaceDetailsCompleteness()
        let query = SpaceCoreDetailsPowerSyncQuery(
            localReader: reader,
            principalId: Self.principalId,
            accountId: Self.accountId,
            completenessObservation: { _, _ in completeness.stream },
            now: { Self.asOf }
        )
        let updates = LockedSpaceDetailsUpdates()
        let consumer = Self.consume(query: query, updates: updates)
        await Self.waitUntil { reader.didInstallWatch && completeness.didInstall }

        completeness.send(true)
        await Self.waitUntil { updates.snapshots.last?.local.quality == .ready }
        #expect(updates.snapshots.last?.row?.id == Self.spaceId)
        #expect(updates.snapshots.last?.local.isCompleteForQuery == true)
        #expect(reader.readCount == 1)

        consumer.cancel()
        await query.cancelAndDrainWatches()
        _ = await consumer.result
    }

    @Test("A post-ready row invalidation rereads the complete hierarchy")
    func postReadyInvalidationRereads() async throws {
        let reader = ControlledSpaceDetailsReader(rows: [Self.row()], hasLastSyncedAt: true)
        let completeness = ControlledSpaceDetailsCompleteness()
        let query = SpaceCoreDetailsPowerSyncQuery(
            localReader: reader,
            principalId: Self.principalId,
            accountId: Self.accountId,
            completenessObservation: { _, _ in completeness.stream },
            now: { Self.asOf }
        )
        let updates = LockedSpaceDetailsUpdates()
        let consumer = Self.consume(query: query, updates: updates)
        await Self.waitUntil { reader.didInstallWatch && completeness.didInstall }
        completeness.send(true)
        await Self.waitUntil { updates.snapshots.last?.local.quality == .ready }
        let readsAtReady = reader.readCount

        reader.replace(with: [Self.row(lifecycle: "archived", notes: "Fresh local detail")])
        reader.invalidate()
        await Self.waitUntil {
            updates.snapshots.last?.row?.notes.value == "Fresh local detail"
        }
        #expect(reader.readCount == readsAtReady + 1)
        #expect(updates.snapshots.last?.row?.lifecycle == .archived)
        #expect(updates.snapshots.last?.local.quality == .ready)
        #expect(updates.snapshots.last?.local.isCompleteForQuery == true)

        consumer.cancel()
        await query.cancelAndDrainWatches()
        _ = await consumer.result
    }

    @Test("Encrypted retained hierarchy reopens incomplete until current-process completion")
    func encryptedRestartResetsCompleteness() async throws {
        let fixture = try SpaceDetailsEncryptedDatabaseFixture()
        defer { fixture.remove() }
        let firstDatabase = try fixture.open()
        try await Self.seedEncryptedHierarchy(firstDatabase)
        let cipher: String = try await firstDatabase.get("PRAGMA cipher") {
            try $0.getString(index: 0)
        }
        #expect(!cipher.isEmpty)

        let firstReader = EncryptedSpaceDetailsReader(
            database: firstDatabase,
            hasLastSyncedAt: false
        )
        let firstCompleteness = ControlledSpaceDetailsCompleteness()
        let firstQuery = Self.query(reader: firstReader, completeness: firstCompleteness)
        let firstUpdates = LockedSpaceDetailsUpdates()
        let firstConsumer = Self.consume(query: firstQuery, updates: firstUpdates)
        await Self.waitUntil { firstReader.didInstallWatch && firstCompleteness.didInstall }
        firstCompleteness.send(false)
        await Self.waitUntil { firstUpdates.snapshots.last?.row != nil }
        #expect(firstUpdates.snapshots.last?.local.quality == .partial)
        firstCompleteness.send(true)
        await Self.waitUntil { firstUpdates.snapshots.last?.local.quality == .ready }
        let beforeClose = try #require(firstUpdates.snapshots.last)
        #expect(beforeClose.row?.checklists.checklists.first?.items.first?.id.rawValue == "item-one")
        firstConsumer.cancel()
        await firstQuery.cancelAndDrainWatches()
        _ = await firstConsumer.result
        try await firstDatabase.close(deleteDatabase: false)

        let reopenedDatabase = try fixture.open()
        let reopenedReader = EncryptedSpaceDetailsReader(
            database: reopenedDatabase,
            hasLastSyncedAt: true
        )
        let reopenedCompleteness = ControlledSpaceDetailsCompleteness()
        let reopenedQuery = Self.query(
            reader: reopenedReader,
            completeness: reopenedCompleteness
        )
        let reopenedUpdates = LockedSpaceDetailsUpdates()
        let reopenedConsumer = Self.consume(query: reopenedQuery, updates: reopenedUpdates)
        await Self.waitUntil {
            reopenedReader.didInstallWatch && reopenedCompleteness.didInstall
        }
        reopenedCompleteness.send(false)
        await Self.waitUntil { reopenedUpdates.snapshots.last?.row != nil }
        let retained = try #require(reopenedUpdates.snapshots.last)
        #expect(retained.row == beforeClose.row)
        #expect(retained.local.quality == .stale)
        #expect(!retained.local.isCompleteForQuery)
        #expect(!retained.progressCountsAreAuthoritative)

        reopenedCompleteness.send(true)
        await Self.waitUntil { reopenedUpdates.snapshots.last?.local.quality == .ready }
        #expect(reopenedUpdates.snapshots.last?.row == beforeClose.row)
        #expect(reopenedUpdates.snapshots.last?.progressCountsAreAuthoritative == true)
        reopenedConsumer.cancel()
        await reopenedQuery.cancelAndDrainWatches()
        _ = await reopenedConsumer.result
        try await reopenedDatabase.close(deleteDatabase: true)
    }

    @Test("Provider-owned observation is cancelled and drained")
    func cancellationDrainage() async throws {
        let reader = ControlledSpaceDetailsReader(rows: [Self.row()])
        let completeness = ControlledSpaceDetailsCompleteness()
        let query = SpaceCoreDetailsPowerSyncQuery(
            localReader: reader,
            principalId: Self.principalId,
            accountId: Self.accountId,
            completenessObservation: { _, _ in completeness.stream }
        )
        let consumer = Task {
            do { for try await _ in query.watchSpaceCoreDetails(Self.request) {} } catch {}
        }
        await Self.waitUntil { reader.didInstallWatch && completeness.didInstall }
        await query.cancelAndDrainWatches()
        _ = await consumer.result
        #expect(reader.terminationCount == 1)
        #expect(completeness.terminationCount == 1)

        var late = query.watchSpaceCoreDetails(Self.request).makeAsyncIterator()
        #expect(try await late.next() == nil)
    }

    private static let accountId = try! AccountID(validating: "space-account")
    private static let principalId = try! PrincipalID(validating: "space-principal")
    private static let spaceId = try! SpaceID(validating: "space-one")
    private static let projectId = try! ProjectID(validating: "archived-project")
    private static let request = try! SpaceCoreDetailsRequest(accountId: accountId, spaceId: spaceId)
    private static let asOf = Date(timeIntervalSince1970: 1_802_100_100)
    private static let createdMS: Int64 = 1_802_100_000_123
    private static let updatedMS: Int64 = 1_802_100_005_456

    private static func sentinel(active: Int64) -> SpaceCoreDetailsPowerSyncRow {
        SpaceCoreDetailsPowerSyncRow(scopeIsActive: active, visibleCount: 0)
    }

    private static func row(
        account: String = accountId.rawValue,
        space: String = spaceId.rawValue,
        scopeKind: String = "project",
        projectId: String? = projectId.rawValue,
        displayName: String = "Living Room",
        lifecycle: String = "active",
        revision: Int64 = .max,
        detailId: String? = spaceId.rawValue,
        notes: String? = "Keep original trim",
        createdMS: Int64 = createdMS,
        checklistRow: String? = nil,
        checklist: String? = nil,
        checklistName: String? = nil,
        checklistOrder: Int64? = nil,
        itemRow: String? = nil,
        item: String? = nil,
        itemText: String? = nil,
        checked: Int64? = nil,
        itemOrder: Int64? = nil
    ) -> SpaceCoreDetailsPowerSyncRow {
        SpaceCoreDetailsPowerSyncRow(
            scopeIsActive: 1,
            visibleCount: 1,
            spaceId: space,
            accountId: account,
            scopeKind: scopeKind,
            projectId: projectId,
            displayName: displayName,
            lifecycle: lifecycle,
            revision: revision,
            detailId: detailId,
            detailAccountId: account,
            notes: notes,
            createdAtMilliseconds: createdMS,
            updatedAtMilliseconds: updatedMS,
            checklistRowId: checklistRow,
            checklistAccountId: checklistRow == nil ? nil : account,
            checklistSpaceId: checklistRow == nil ? nil : space,
            checklistId: checklist,
            checklistName: checklistName,
            checklistOrder: checklistOrder,
            itemRowId: itemRow,
            itemAccountId: itemRow == nil ? nil : account,
            itemSpaceId: itemRow == nil ? nil : space,
            itemChecklistId: itemRow == nil ? nil : checklist,
            itemId: item,
            itemText: itemText,
            itemIsChecked: checked,
            itemOrder: itemOrder
        )
    }

    private static func waitUntil(_ condition: @escaping @Sendable () -> Bool) async {
        for _ in 0..<2_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Timed out waiting for controlled Space provider event")
    }

    private static func query(
        reader: any SpaceCoreDetailsLocalReading,
        completeness: ControlledSpaceDetailsCompleteness
    ) -> SpaceCoreDetailsPowerSyncQuery {
        SpaceCoreDetailsPowerSyncQuery(
            localReader: reader,
            principalId: principalId,
            accountId: accountId,
            completenessObservation: { _, _ in completeness.stream },
            now: { asOf }
        )
    }

    private static func consume(
        query: SpaceCoreDetailsPowerSyncQuery,
        updates: LockedSpaceDetailsUpdates
    ) -> Task<Void, Never> {
        Task {
            do {
                for try await update in query.watchSpaceCoreDetails(request) {
                    updates.append(update)
                }
            } catch {
                updates.record(error)
            }
        }
    }

    private static func seedEncryptedHierarchy(
        _ database: any PowerSyncDatabaseProtocol
    ) async throws {
        _ = try await database.execute(sql: """
            INSERT INTO spike_account_memberships
              (id, account_id, principal_id, role, state, can_manage_clients,
               can_manage_projects, can_manage_project_budgets, financial_access)
            VALUES
              ('space-detail-membership', 'space-account', 'space-principal',
               'owner', 'active', 1, 1, 1, 'full')
            """, parameters: nil)
        _ = try await database.execute(sql: """
            INSERT INTO spike_spaces
              (id, account_id, scope_kind, project_id, display_name, lifecycle, revision)
            VALUES
              ('space-one', 'space-account', 'project', 'archived-project',
               'Living Room', 'active', 7)
            """, parameters: nil)
        _ = try await database.execute(sql: """
            INSERT INTO spike_space_core_details
              (id, account_id, notes, created_at_ms, updated_at_ms)
            VALUES
              ('space-one', 'space-account', 'Keep original trim', ?, ?)
            """, parameters: [createdMS, updatedMS])
        _ = try await database.execute(sql: """
            INSERT INTO spike_space_checklists
              (id, account_id, space_id, checklist_id, name, presentation_order)
            VALUES
              ('checklist-row', 'space-account', 'space-one', 'checklist-one',
               'Prepare', 0)
            """, parameters: nil)
        _ = try await database.execute(sql: """
            INSERT INTO spike_space_checklist_items
              (id, account_id, space_id, checklist_id, item_id, item_text,
               is_checked, presentation_order)
            VALUES
              ('item-row', 'space-account', 'space-one', 'checklist-one',
               'item-one', 'Protect floor', 1, 0)
            """, parameters: nil)
    }
}

private final class ControlledSpaceDetailsReader: SpaceCoreDetailsLocalReading, @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [SpaceCoreDetailsPowerSyncRow]
    private var continuation: AsyncThrowingStream<[SpaceCoreDetailsPowerSyncRow], Error>.Continuation?
    private var terminations = 0
    private var reads = 0
    let hasLastSyncedAt: Bool

    init(rows: [SpaceCoreDetailsPowerSyncRow], hasLastSyncedAt: Bool = false) {
        self.rows = rows
        self.hasLastSyncedAt = hasLastSyncedAt
    }
    var didInstallWatch: Bool { lock.withLock { continuation != nil } }
    var terminationCount: Int { lock.withLock { terminations } }
    var readCount: Int { lock.withLock { reads } }
    func replace(with rows: [SpaceCoreDetailsPowerSyncRow]) { lock.withLock { self.rows = rows } }
    func invalidate() { lock.withLock { continuation }?.yield([]) }
    func readRows(request: SpaceCoreDetailsRequest, principalId: PrincipalID) async throws -> [SpaceCoreDetailsPowerSyncRow] {
        lock.withLock {
            reads += 1
            return rows
        }
    }
    func watchRows(request: SpaceCoreDetailsRequest, principalId: PrincipalID) throws -> AsyncThrowingStream<[SpaceCoreDetailsPowerSyncRow], Error> {
        AsyncThrowingStream { continuation in
            lock.withLock { self.continuation = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.terminations += 1; self?.continuation = nil }
            }
        }
    }
}

private final class EncryptedSpaceDetailsReader:
    SpaceCoreDetailsLocalReading, @unchecked Sendable
{
    private let database: any PowerSyncDatabaseProtocol
    private let lock = NSLock()
    private var installed = false
    let hasLastSyncedAt: Bool

    init(database: any PowerSyncDatabaseProtocol, hasLastSyncedAt: Bool) {
        self.database = database
        self.hasLastSyncedAt = hasLastSyncedAt
    }

    var didInstallWatch: Bool { lock.withLock { installed } }

    func readRows(
        request: SpaceCoreDetailsRequest,
        principalId: PrincipalID
    ) async throws -> [SpaceCoreDetailsPowerSyncRow] {
        try await database.getAll(
            sql: Self.sql,
            parameters: Self.parameters(request, principalId)
        ) { try SpaceCoreDetailsPowerSyncRow(cursor: $0) }
    }

    func watchRows(
        request: SpaceCoreDetailsRequest,
        principalId: PrincipalID
    ) throws -> AsyncThrowingStream<[SpaceCoreDetailsPowerSyncRow], Error> {
        let stream = try database.watch(
            sql: Self.sql,
            parameters: Self.parameters(request, principalId)
        ) { try SpaceCoreDetailsPowerSyncRow(cursor: $0) }
        lock.withLock { installed = true }
        return stream
    }

    private static func parameters(
        _ request: SpaceCoreDetailsRequest,
        _ principalId: PrincipalID
    ) -> [any Sendable] {
        [
            request.accountId.rawValue,
            principalId.rawValue,
            request.accountId.rawValue,
            request.spaceId.rawValue,
        ]
    }

    private static let sql = """
        WITH scope AS (
          SELECT EXISTS (
            SELECT 1 FROM spike_account_memberships
            WHERE account_id = ? AND principal_id = ? AND state = 'active'
          ) AS is_active
        ), selected_space AS (
          SELECT space.id, space.account_id, space.scope_kind, space.project_id,
                 space.display_name, space.lifecycle, space.revision
          FROM spike_spaces AS space
          WHERE space.account_id = ? AND space.id = ?
            AND (SELECT is_active FROM scope)
        )
        SELECT CAST(scope.is_active AS INTEGER) AS is_active,
               (SELECT count(*) FROM selected_space) AS visible_count,
               space.id AS space_id, space.account_id, space.scope_kind,
               space.project_id, space.display_name, space.lifecycle, space.revision,
               detail.id AS detail_id, detail.account_id AS detail_account_id,
               detail.notes, detail.created_at_ms, detail.updated_at_ms,
               checklist.id AS checklist_row_id,
               checklist.account_id AS checklist_account_id,
               checklist.space_id AS checklist_space_id,
               checklist.checklist_id, checklist.name AS checklist_name,
               checklist.presentation_order AS checklist_order,
               item.id AS item_row_id, item.account_id AS item_account_id,
               item.space_id AS item_space_id,
               item.checklist_id AS item_checklist_id, item.item_id,
               item.item_text, item.is_checked,
               item.presentation_order AS item_order
        FROM scope
        LEFT JOIN selected_space AS space ON scope.is_active
        LEFT JOIN spike_space_core_details AS detail
          ON detail.account_id = space.account_id AND detail.id = space.id
        LEFT JOIN spike_space_checklists AS checklist
          ON checklist.account_id = space.account_id AND checklist.space_id = space.id
        LEFT JOIN spike_space_checklist_items AS item
          ON item.account_id = checklist.account_id
         AND item.space_id = checklist.space_id
         AND item.checklist_id = checklist.checklist_id
        ORDER BY checklist.presentation_order, checklist.checklist_id,
                 item.presentation_order, item.item_id
        """
}

private final class SpaceDetailsEncryptedDatabaseFixture: @unchecked Sendable {
    private let root: URL
    private let databaseURL: URL
    private let key: LedgerPowerSyncEncryptionKey

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ledger-space-core-details-\(UUID().uuidString)",
            isDirectory: true
        )
        databaseURL = root.appendingPathComponent("ledger.sqlite")
        key = try LedgerPowerSyncEncryptionKey(
            hexadecimal: String(repeating: "7f", count: 32)
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
    }

    func open() throws -> any PowerSyncDatabaseProtocol {
        try LedgerPowerSyncDatabaseFactory.open(
            absolutePath: databaseURL.path,
            encryptionKey: key
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class ControlledSpaceDetailsCompleteness: @unchecked Sendable {
    private let lock = NSLock()
    let stream: AsyncStream<Bool>
    private let continuation: AsyncStream<Bool>.Continuation
    private var terminations = 0

    init() {
        var captured: AsyncStream<Bool>.Continuation!
        stream = AsyncStream { captured = $0 }
        continuation = captured
        continuation.onTermination = { [weak self] _ in
            self?.lock.withLock { self?.terminations += 1 }
        }
    }

    var didInstall: Bool { true }
    var terminationCount: Int { lock.withLock { terminations } }
    func send(_ value: Bool) { continuation.yield(value) }
}

private final class LockedSpaceDetailsUpdates: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [SpaceCoreDetailsUpdate] = []
    private var capturedError: Error?
    func append(_ value: SpaceCoreDetailsUpdate) { lock.withLock { values.append(value) } }
    func record(_ error: Error) { lock.withLock { capturedError = error } }
    var snapshots: [SpaceCoreDetailsLocalSnapshot] {
        lock.withLock { values.compactMap { if case .snapshot(let value) = $0.state { value } else { nil } } }
    }
    var error: Error? { lock.withLock { capturedError } }
}
