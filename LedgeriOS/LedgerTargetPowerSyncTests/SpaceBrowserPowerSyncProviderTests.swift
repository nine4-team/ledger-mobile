import Foundation
import LedgerTargetCore
import PowerSync
import Testing

@testable import LedgerTargetPowerSync

@Suite("Space browser PowerSync provider", .serialized)
struct SpaceBrowserPowerSyncProviderTests {
  @Test("Project hierarchy is exact, deterministic, and reconstructs checklist progress")
  func projectHierarchyAndCompleteness() async throws {
    let reader = BrowserRowReader(rows: [
      Self.row("space-z", name: "loft", count: 3),
      Self.row("space-upper", name: "Loft", count: 3),
      Self.row(
        "space-a", name: "loft", revision: 4, count: 3,
        checklist: "list-1", checklistName: "Install", checklistOrder: 5,
        item: "item-1", itemText: "Sink", checked: true, itemOrder: 10),
      Self.row(
        "space-a", name: "loft", revision: 4, count: 3,
        checklist: "list-1", checklistName: "Install", checklistOrder: 5,
        item: "item-2", itemText: "Tap", checked: false, itemOrder: 20),
    ])
    let sync = BrowserSyncSource()
    let provider = Self.provider(reader: reader, sync: sync)
    var iterator = provider.watchSpaces(Self.projectRequest).makeAsyncIterator()

    let partial = try Self.snapshot(#require(try await iterator.next()))
    #expect(partial.local.quality == .partial)
    #expect(!partial.local.isCompleteForQuery)
    #expect(partial.local.rows.map(\.id.rawValue) == ["space-upper", "space-a", "space-z"])
    #expect(partial.local.rows[1].completedChecklistItemCount == 1)
    #expect(partial.local.rows[1].totalChecklistItemCount == 2)
    let presented = try ActiveSpaceDirectoryPresentationSnapshot(source: partial)
    #expect(presented.rows.allSatisfy { $0.itemCountState == .unavailable })
    await Self.waitUntil { sync.identities.count == 1 }
    #expect(
      sync.identities == [
        SpaceBrowserSyncStreamIdentity(accountId: Self.accountId, scope: Self.projectScope)
      ])

    sync.emitFresh(epoch: 2)
    let ready = try Self.snapshot(#require(try await iterator.next()))
    #expect(ready.local.quality == .ready)
    #expect(ready.local.isCompleteForQuery)
    #expect(ready.local.rows[1].checklists.checklists[0].presentationOrder == 5)
    #expect(
      ready.local.rows[1].checklists.checklists[0].items.map(\.presentationOrder) == [10, 20])
    await provider.cancelAndDrainWatches()
    #expect(sync.unsubscribeCount == 1)
  }

  @Test("Row evidence never waits for subscription setup and never inherits completeness")
  func rowOnlyEvidence() {
    let rows = [Self.row("space-order")]
    var state = SpaceBrowserObservedState()
    #expect(state.observeRows(rows)?.currentProcessSyncEpoch == nil)
    #expect(
      state.observeCurrentProcessSync(epoch: 2, freshRows: rows)?.currentProcessSyncEpoch == 2)
    #expect(state.observeRows(rows)?.currentProcessSyncEpoch == 2)
    state.resetCompleteness()
    #expect(state.observeRows(rows)?.currentProcessSyncEpoch == nil)
  }

  @Test("Valid local rows emit while subscription setup is still blocked")
  func rowsDoNotWaitForSubscription() async throws {
    let sync = BrowserBlockedSyncSource()
    let provider = Self.provider(
      reader: BrowserRowReader(rows: [Self.row("offline-row")], hasLastSyncedAt: true),
      sync: sync)
    var iterator = provider.watchSpaces(Self.projectRequest).makeAsyncIterator()
    let immediate = try Self.snapshot(#require(try await iterator.next()))
    #expect(immediate.local.rows.map(\.id.rawValue) == ["offline-row"])
    #expect(immediate.local.quality == .stale)
    #expect(!immediate.local.isCompleteForQuery)
    await Self.waitUntil { sync.subscribeStarted }
    await provider.cancelAndDrainWatches()
  }

  @Test("Inventory has its own exact identity and Account-bound admission")
  func inventoryAndAccountIsolation() async throws {
    let inventoryIdentity = SpaceBrowserSyncStreamIdentity(
      accountId: Self.accountId, scope: .businessInventory)
    #expect(inventoryIdentity.name == "space_browser")
    #expect(
      inventoryIdentity.parameters == [
        "account_id": .string(Self.accountId.rawValue),
        "scope_kind": .string("business_inventory"),
      ])
    let projectIdentity = SpaceBrowserSyncStreamIdentity(
      accountId: Self.accountId, scope: Self.projectScope)
    #expect(
      projectIdentity.parameters == [
        "account_id": .string(Self.accountId.rawValue),
        "scope_kind": .string("project"),
        "project_id": .string(Self.projectId.rawValue),
      ])

    let inventoryRow = Self.row("inventory-space", scopeKind: "business_inventory", projectId: nil)
    let provider = Self.provider(
      reader: BrowserRowReader(rows: [inventoryRow]), sync: BrowserSyncSource())
    var iterator = provider.watchSpaces(Self.inventoryRequest).makeAsyncIterator()
    let snapshot = try Self.snapshot(#require(try await iterator.next()))
    #expect(snapshot.local.rows.map(\.id.rawValue) == ["inventory-space"])
    await provider.cancelAndDrainWatches()

    let foreign = try SpaceListRequest(
      accountId: AccountID(validating: "foreign-account"), scope: Self.projectScope)
    var foreignIterator = provider.watchSpaces(foreign).makeAsyncIterator()
    do {
      _ = try await foreignIterator.next()
      Issue.record("Foreign Account request emitted evidence")
    } catch let failure as SpaceListFailure {
      #expect(failure == .accountScopeMismatch)
    }
  }

  @Test("Cached rows remain stale, fresh sync completes, and freshness loss revokes completeness")
  func staleFreshAndFreshnessLoss() async throws {
    let sync = BrowserSyncSource()
    let provider = Self.provider(
      reader: BrowserRowReader(rows: [Self.row("cached")], hasLastSyncedAt: true), sync: sync)
    var iterator = provider.watchSpaces(Self.projectRequest).makeAsyncIterator()
    let stale = try Self.snapshot(#require(try await iterator.next()))
    #expect(stale.local.quality == .stale)
    #expect(!stale.local.isCompleteForQuery)

    sync.emitFresh(epoch: 2)
    let ready = try Self.snapshot(#require(try await iterator.next()))
    #expect(ready.local.quality == .ready)
    #expect(ready.local.isCompleteForQuery)

    sync.emitLost()
    let revoked = try Self.snapshot(#require(try await iterator.next()))
    #expect(revoked.local.quality == .stale)
    #expect(!revoked.local.isCompleteForQuery)
    await provider.cancelAndDrainWatches()
  }

  @Test("Normal status completion revokes authority and late rows cannot rebound")
  func statusCompletionIsTerminal() async throws {
    let reader = BrowserRowReader(
      rows: [Self.row("before-completion")], hasLastSyncedAt: true)
    let sync = BrowserSyncSource()
    let provider = Self.provider(reader: reader, sync: sync)
    var iterator = provider.watchSpaces(Self.projectRequest).makeAsyncIterator()
    _ = try Self.snapshot(#require(try await iterator.next()))
    sync.emitFresh(epoch: 2)
    let ready = try Self.snapshot(#require(try await iterator.next()))
    #expect(ready.local.isCompleteForQuery)

    sync.finishStatuses()
    let revoked = try Self.snapshot(#require(try await iterator.next()))
    #expect(revoked.local.quality == .stale)
    #expect(!revoked.local.isCompleteForQuery)
    reader.yield([Self.row("late-row")])
    #expect(try await iterator.next() == nil)
    await provider.cancelAndDrainWatches()
    #expect(sync.unsubscribeCount == 1)
  }

  @Test(
    "Empty is authoritative only after this subscription completes and membership loss clears it")
  func emptyAndMembershipLoss() async throws {
    let reader = BrowserRowReader(rows: [Self.sentinel(active: true)])
    let sync = BrowserSyncSource()
    let provider = Self.provider(reader: reader, sync: sync)
    var iterator = provider.watchSpaces(Self.projectRequest).makeAsyncIterator()
    let partial = try Self.snapshot(#require(try await iterator.next()))
    #expect(partial.local.rows.isEmpty)
    #expect(!partial.local.isCompleteForQuery)

    sync.emitFresh(epoch: 2)
    let ready = try Self.snapshot(#require(try await iterator.next()))
    #expect(ready.local.rows.isEmpty)
    #expect(ready.local.isCompleteForQuery)
    let presentation = try ActiveSpaceDirectoryPresentationSnapshot(source: ready)
    #expect(presentation.isAuthoritativeEmpty)

    reader.yield([Self.sentinel(active: false)])
    let inactive = try Self.snapshot(#require(try await iterator.next()))
    #expect(inactive.local.quality == .partial)
    #expect(!inactive.local.isCompleteForQuery)
    await provider.cancelAndDrainWatches()
  }

  @Test(
    "Malformed, duplicate, foreign, archived, incomplete, and overflow evidence fails closed",
    arguments: [
      [Self.row("space", accountId: "foreign-account")],
      [Self.row("space", scopeKind: "business_inventory", projectId: nil)],
      [Self.row("space", lifecycle: "archived")],
      [Self.row("space", detailId: nil)],
      [Self.row("space", revision: -1)],
      [Self.row("space", checklist: "list", checklistOrder: -1)],
      [Self.row("space", checklist: "list", item: "item", checked: false, itemOrder: Int64.max)],
      [Self.row("space", count: 2)],
      [
        Self.row("space", checklist: "list-a", checklistOrder: 1),
        Self.row("space", checklist: "list-b", checklistOrder: 1),
      ],
      [
        Self.row("space", checklist: "list", item: "item", itemOrder: 1),
        Self.row("space", checklist: "list", item: "item", itemOrder: 1),
      ],
    ])
  func malformedEvidence(rows: [SpaceBrowserPowerSyncRow]) async throws {
    let provider = Self.provider(reader: BrowserRowReader(rows: rows), sync: BrowserSyncSource())
    var iterator = provider.watchSpaces(Self.projectRequest).makeAsyncIterator()
    do {
      _ = try await iterator.next()
      Issue.record("Malformed evidence emitted a mixed-trust snapshot")
    } catch let failure as SpaceListFailure {
      #expect([.localReadFailed, .spaceScopeMismatch, .visibleCountMismatch].contains(failure))
    }
    await provider.cancelAndDrainWatches()
  }

  @Test("Consumer cancellation and workspace close unsubscribe and reject new watches")
  func cancellationAndCloseDrain() async throws {
    let sync = BrowserSyncSource()
    let provider = Self.provider(reader: BrowserRowReader(rows: [Self.row("space")]), sync: sync)
    let consumer = Task {
      do { for try await _ in provider.watchSpaces(Self.projectRequest) {} } catch {}
    }
    await Self.waitUntil { sync.identities.count == 1 }
    consumer.cancel()
    await consumer.value
    await Self.waitUntil { sync.unsubscribeCount == 1 }
    #expect(sync.unsubscribeCount == 1)
    await provider.cancelAndDrainWatches()
    var afterClose = provider.watchSpaces(Self.projectRequest).makeAsyncIterator()
    #expect(try await afterClose.next() == nil)
  }

  @Test("Encrypted reader returns active exact scopes and complete hierarchy")
  func encryptedReaderScopeAndHierarchy() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "space-browser-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let database = try LedgerPowerSyncDatabaseFactory.open(
      absolutePath: root.appendingPathComponent("ledger.sqlite").path,
      encryptionKey: try LedgerPowerSyncEncryptionKey(
        hexadecimal: String(repeating: "7a", count: 32))
    )
    try await Self.seed(database)
    let reader = PowerSyncSpaceBrowserLocalReader(database: database)
    let projectRows = try await reader.readRows(
      request: Self.projectRequest, principalId: Self.principalId)
    #expect(Set(projectRows.compactMap(\.spaceId)) == ["space-project"])
    #expect(projectRows.count == 2)
    let inventoryRows = try await reader.readRows(
      request: Self.inventoryRequest, principalId: Self.principalId)
    #expect(Set(inventoryRows.compactMap(\.spaceId)) == ["space-inventory"])
    #expect(projectRows.allSatisfy { $0.lifecycle == "active" })
    let unauthorized = try await reader.readRows(
      request: Self.projectRequest,
      principalId: PrincipalID(validating: "foreign-principal")
    )
    #expect(unauthorized == [Self.sentinel(active: false)])

    let provider = Self.provider(reader: reader, sync: BrowserSyncSource())
    var iterator = provider.watchSpaces(Self.projectRequest).makeAsyncIterator()
    let snapshot = try Self.snapshot(#require(try await iterator.next()))
    #expect(snapshot.local.rows[0].completedChecklistItemCount == 1)
    #expect(snapshot.local.rows[0].totalChecklistItemCount == 2)
    await provider.cancelAndDrainWatches()
    try await database.close(deleteDatabase: true)
  }

  @Test("Encrypted close and reopen preserves rows but resets exact-list completeness")
  func encryptedRestartResetsCompleteness() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "space-browser-restart-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let path = root.appendingPathComponent("ledger.sqlite").path
    let key = try LedgerPowerSyncEncryptionKey(
      hexadecimal: String(repeating: "8b", count: 32))

    let firstDatabase = try LedgerPowerSyncDatabaseFactory.open(
      absolutePath: path, encryptionKey: key)
    try await Self.seed(firstDatabase)
    let firstSync = BrowserSyncSource()
    let first = Self.provider(
      reader: PowerSyncSpaceBrowserLocalReader(database: firstDatabase), sync: firstSync)
    var firstIterator = first.watchSpaces(Self.projectRequest).makeAsyncIterator()
    let beforeSync = try Self.snapshot(#require(try await firstIterator.next()))
    #expect(!beforeSync.local.isCompleteForQuery)
    firstSync.emitFresh(epoch: 2)
    let beforeClose = try Self.snapshot(#require(try await firstIterator.next()))
    #expect(beforeClose.local.isCompleteForQuery)
    await first.cancelAndDrainWatches()
    try await firstDatabase.close(deleteDatabase: false)

    let reopened = try LedgerPowerSyncDatabaseFactory.open(
      absolutePath: path, encryptionKey: key)
    let restartReader = BrowserLastSyncedReader(
      base: PowerSyncSpaceBrowserLocalReader(database: reopened))
    let restartSync = BrowserSyncSource()
    let restarted = Self.provider(reader: restartReader, sync: restartSync)
    var restartIterator = restarted.watchSpaces(Self.projectRequest).makeAsyncIterator()
    let cached = try Self.snapshot(#require(try await restartIterator.next()))
    #expect(cached.local.rows == beforeClose.local.rows)
    #expect(cached.local.quality == .stale)
    #expect(!cached.local.isCompleteForQuery)
    restartSync.emitFresh(epoch: 2)
    let restored = try Self.snapshot(#require(try await restartIterator.next()))
    #expect(restored.local.rows == beforeClose.local.rows)
    #expect(restored.local.quality == .ready)
    #expect(restored.local.isCompleteForQuery)
    await restarted.cancelAndDrainWatches()
    try await reopened.close(deleteDatabase: true)
  }

  @Test("Retained exact epoch is honored and malformed or duplicate retained evidence fails closed")
  func retainedEpochValidation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "space-browser-retained-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let database = try LedgerPowerSyncDatabaseFactory.open(
      absolutePath: root.appendingPathComponent("ledger.sqlite").path,
      encryptionKey: try LedgerPowerSyncEncryptionKey(
        hexadecimal: String(repeating: "9c", count: 32)))
    try await Self.seed(database)
    for _ in 0..<2_000 {
      if database.currentStatus.syncStreams != nil { break }
      try? await Task.sleep(for: .milliseconds(1))
    }
    #expect(database.currentStatus.syncStreams != nil)
    let source = PowerSyncSpaceBrowserSyncSource(database: database)
    let exactJSON =
      #"{"account_id":"account-space-browser","project_id":"project-space-browser","scope_kind":"project"}"#
    _ = try await database.execute(
      sql: """
        INSERT INTO ps_stream_subscriptions
          (stream_name, active, is_default, local_params, last_synced_at)
        VALUES ('space_browser', 1, 0, ?, 41000000)
        """, parameters: [exactJSON])
    let retained = try await source.subscribe(accountId: Self.accountId, scope: Self.projectScope)
    #expect(retained.baselineLastSyncedAt == 41)
    try await retained.unsubscribe()

    _ = try await database.execute(
      sql: "DELETE FROM ps_stream_subscriptions WHERE stream_name = 'space_browser'",
      parameters: nil)
    _ = try await database.execute(
      sql: """
        INSERT INTO ps_stream_subscriptions
          (stream_name, active, is_default, local_params, last_synced_at)
        VALUES ('space_browser', 1, 0, 'not-json', 42000000)
        """, parameters: nil)
    do {
      _ = try await source.subscribe(accountId: Self.accountId, scope: Self.projectScope)
      Issue.record("Malformed retained evidence was accepted")
    } catch {}

    _ = try await database.execute(
      sql: "DELETE FROM ps_stream_subscriptions WHERE stream_name = 'space_browser'",
      parameters: nil)
    let reorderedJSON =
      #"{"scope_kind":"project","project_id":"project-space-browser","account_id":"account-space-browser"}"#
    _ = try await database.execute(
      sql: """
        INSERT INTO ps_stream_subscriptions
          (stream_name, active, is_default, local_params, last_synced_at)
        VALUES ('space_browser', 1, 0, ?, 43000000),
               ('space_browser', 1, 0, ?, 44000000)
        """, parameters: [exactJSON, reorderedJSON])
    do {
      _ = try await source.subscribe(accountId: Self.accountId, scope: Self.projectScope)
      Issue.record("Duplicate retained evidence was accepted")
    } catch let failure as SpaceBrowserPowerSyncFailure {
      #expect(failure == .malformedScopeEvidence)
    }
    try await database.close(deleteDatabase: true)
  }

  private static let accountId = try! AccountID(validating: "account-space-browser")
  private static let principalId = try! PrincipalID(validating: "principal-space-browser")
  private static let projectId = try! ProjectID(validating: "project-space-browser")
  private static let projectScope = SpaceCreationScope.project(projectId)
  private static let projectRequest = try! SpaceListRequest(
    accountId: accountId, scope: projectScope)
  private static let inventoryRequest = try! SpaceListRequest(
    accountId: accountId, scope: .businessInventory)

  private static func provider(
    reader: any SpaceBrowserLocalReading, sync: any SpaceBrowserSyncSubscribing
  ) -> SpaceBrowserPowerSyncProvider {
    .init(
      localReader: reader, syncSource: sync, principalId: principalId, accountId: accountId,
      now: { Date(timeIntervalSince1970: 1_788_600_000) })
  }

  private static func snapshot(_ update: SpaceListUpdate) throws -> SpaceListLocalSnapshot {
    guard case .snapshot(let snapshot) = update.state else {
      throw SpaceListFailure.localReadFailed
    }
    return snapshot
  }

  private static func row(
    _ id: String, name: String = "Loft", accountId: String = accountId.rawValue,
    scopeKind: String = "project", projectId: String? = projectId.rawValue,
    lifecycle: String = "active", revision: Int64 = 1, count: Int64 = 1,
    detailId: String? = "__default__", checklist: String? = nil,
    checklistName: String = "Checklist", checklistOrder: Int64? = nil, item: String? = nil,
    itemText: String = "Item", checked: Bool = false, itemOrder: Int64? = nil
  ) -> SpaceBrowserPowerSyncRow {
    let exactDetail = detailId == "__default__" ? id : detailId
    return .init(
      scopeRawValue: 1, visibleCount: count, spaceId: id, accountId: accountId,
      scopeKind: scopeKind, projectId: projectId, displayName: name, lifecycle: lifecycle,
      revision: revision, detailId: exactDetail, detailAccountId: accountId,
      checklistRowId: checklist.map { "\(id):\($0)" },
      checklistAccountId: checklist == nil ? nil : accountId,
      checklistSpaceId: checklist == nil ? nil : id, checklistId: checklist,
      checklistName: checklist == nil ? nil : checklistName,
      checklistOrder: checklist.map { _ in checklistOrder ?? 1 },
      itemRowId: item.map { "\(id):\(checklist ?? "missing"):\($0)" },
      itemAccountId: item == nil ? nil : accountId, itemSpaceId: item == nil ? nil : id,
      itemChecklistId: item == nil ? nil : checklist, itemId: item,
      itemText: item == nil ? nil : itemText, itemIsChecked: item.map { _ in checked ? 1 : 0 },
      itemOrder: item.map { _ in itemOrder ?? 1 })
  }

  private static func sentinel(active: Bool) -> SpaceBrowserPowerSyncRow {
    .init(scopeRawValue: active ? 1 : 0, visibleCount: 0)
  }

  private static func waitUntil(_ condition: @escaping @Sendable () -> Bool) async {
    for _ in 0..<2_000 {
      if condition() { return }
      try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("Timed out waiting for provider lifecycle")
  }

  private static func seed(_ database: any PowerSyncDatabaseProtocol) async throws {
    _ = try await database.execute(
      sql: """
        INSERT INTO spike_account_memberships
          (id, account_id, principal_id, role, state, can_manage_clients, can_manage_projects, can_manage_project_budgets, financial_access)
        VALUES ('browser-membership', ?, ?, 'owner', 'active', 1, 1, 1, 'full')
        """, parameters: [accountId.rawValue, principalId.rawValue])
    _ = try await database.execute(
      sql: """
        INSERT INTO spike_spaces (id, account_id, scope_kind, project_id, display_name, lifecycle, revision) VALUES
          ('space-project', ?, 'project', ?, 'Project Space', 'active', 4),
          ('space-archived', ?, 'project', ?, 'Archived', 'archived', 2),
          ('space-inventory', ?, 'business_inventory', NULL, 'Inventory Space', 'active', 5)
        """,
      parameters: [
        accountId.rawValue, projectId.rawValue, accountId.rawValue, projectId.rawValue,
        accountId.rawValue,
      ])
    for id in ["space-project", "space-archived", "space-inventory"] {
      _ = try await database.execute(
        sql:
          "INSERT INTO spike_space_core_details (id, account_id, notes, created_at_ms, updated_at_ms) VALUES (?, ?, NULL, 1, 1)",
        parameters: [id, accountId.rawValue])
    }
    _ = try await database.execute(
      sql:
        "INSERT INTO spike_space_checklists (id, account_id, space_id, checklist_id, name, presentation_order) VALUES ('space-project:list', ?, 'space-project', 'list', 'Install', 5)",
      parameters: [accountId.rawValue])
    _ = try await database.execute(
      sql: """
        INSERT INTO spike_space_checklist_items (id, account_id, space_id, checklist_id, item_id, item_text, is_checked, presentation_order) VALUES
          ('space-project:list:item-1', ?, 'space-project', 'list', 'item-1', 'Sink', 1, 10),
          ('space-project:list:item-2', ?, 'space-project', 'list', 'item-2', 'Tap', 0, 20)
        """, parameters: [accountId.rawValue, accountId.rawValue])
  }
}

private final class BrowserRowReader: SpaceBrowserLocalReading, @unchecked Sendable {
  let hasLastSyncedAt: Bool
  private let lock = NSLock()
  private var current: [SpaceBrowserPowerSyncRow]
  private let stream: AsyncThrowingStream<[SpaceBrowserPowerSyncRow], Error>
  private let continuation: AsyncThrowingStream<[SpaceBrowserPowerSyncRow], Error>.Continuation
  init(rows: [SpaceBrowserPowerSyncRow], hasLastSyncedAt: Bool = false) {
    self.hasLastSyncedAt = hasLastSyncedAt
    current = rows
    (stream, continuation) = AsyncThrowingStream.makeStream()
    continuation.yield(rows)
  }
  func readRows(request: SpaceListRequest, principalId: PrincipalID) async throws
    -> [SpaceBrowserPowerSyncRow]
  { lock.withLock { current } }
  func watchRows(request: SpaceListRequest, principalId: PrincipalID) throws -> AsyncThrowingStream<
    [SpaceBrowserPowerSyncRow], Error
  > { stream }
  func yield(_ rows: [SpaceBrowserPowerSyncRow]) {
    lock.withLock { current = rows }
    continuation.yield(rows)
  }
}

private final class BrowserLastSyncedReader: SpaceBrowserLocalReading, @unchecked Sendable {
  private let base: any SpaceBrowserLocalReading
  init(base: any SpaceBrowserLocalReading) { self.base = base }
  var hasLastSyncedAt: Bool { true }
  func readRows(request: SpaceListRequest, principalId: PrincipalID) async throws
    -> [SpaceBrowserPowerSyncRow]
  { try await base.readRows(request: request, principalId: principalId) }
  func watchRows(request: SpaceListRequest, principalId: PrincipalID) throws -> AsyncThrowingStream<
    [SpaceBrowserPowerSyncRow], Error
  > { try base.watchRows(request: request, principalId: principalId) }
}

private final class BrowserBlockedSyncSource: SpaceBrowserSyncSubscribing, @unchecked Sendable {
  private let lock = NSLock()
  private var started = false
  var subscribeStarted: Bool { lock.withLock { started } }
  func subscribe(accountId: AccountID, scope: SpaceCreationScope) async throws
    -> any SpaceBrowserSyncSubscription
  {
    lock.withLock { started = true }
    try await Task.sleep(for: .seconds(31_536_000))
    throw BrowserTestFailure()
  }
}

private final class BrowserSyncSource: SpaceBrowserSyncSubscribing, @unchecked Sendable {
  private let lock = NSLock()
  private var recordedIdentities: [SpaceBrowserSyncStreamIdentity] = []
  private var unsubscribed = 0
  private let statusStream: AsyncStream<SpaceBrowserSyncStatus>
  private let statusContinuation: AsyncStream<SpaceBrowserSyncStatus>.Continuation
  init() { (statusStream, statusContinuation) = AsyncStream.makeStream() }
  var identities: [SpaceBrowserSyncStreamIdentity] { lock.withLock { recordedIdentities } }
  var unsubscribeCount: Int { lock.withLock { unsubscribed } }
  func subscribe(accountId: AccountID, scope: SpaceCreationScope) async throws
    -> any SpaceBrowserSyncSubscription
  {
    let identity = SpaceBrowserSyncStreamIdentity(accountId: accountId, scope: scope)
    lock.withLock { recordedIdentities.append(identity) }
    return BrowserSubscription(owner: self, identity: identity)
  }
  func emitFresh(epoch: TimeInterval) {
    statusContinuation.yield(
      .init(connected: true, active: true, hasExplicitSubscription: true, lastSyncedAt: epoch))
  }
  func emitLost() {
    statusContinuation.yield(
      .init(connected: false, active: true, hasExplicitSubscription: true, lastSyncedAt: 2))
  }
  func finishStatuses() { statusContinuation.finish() }
  fileprivate func statuses() -> AsyncStream<SpaceBrowserSyncStatus> { statusStream }
  fileprivate func didUnsubscribe() { lock.withLock { unsubscribed += 1 } }
}

private final class BrowserSubscription: SpaceBrowserSyncSubscription, @unchecked Sendable {
  private let owner: BrowserSyncSource
  let identity: SpaceBrowserSyncStreamIdentity
  let baselineLastSyncedAt: TimeInterval? = 1
  init(owner: BrowserSyncSource, identity: SpaceBrowserSyncStreamIdentity) {
    self.owner = owner
    self.identity = identity
  }
  func waitForFirstSync() async throws { throw BrowserTestFailure() }
  func currentStatus() -> SpaceBrowserSyncStatus? { nil }
  func observeStatus(_ receive: @Sendable (SpaceBrowserSyncStatus) async throws -> Void)
    async throws
  {
    for await status in owner.statuses() {
      try Task.checkCancellation()
      try await receive(status)
    }
    try Task.checkCancellation()
  }
  func unsubscribe() async throws { owner.didUnsubscribe() }
}

private struct BrowserTestFailure: Error {}
