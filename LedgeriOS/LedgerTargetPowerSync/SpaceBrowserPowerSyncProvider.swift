import CryptoKit
import Foundation
import LedgerTargetCore
import PowerSync

enum SpaceBrowserPowerSyncFailure: Error, Equatable, Sendable {
  case malformedScopeEvidence
  case malformedSpaceHierarchy
}

protocol SpaceBrowserLocalReading: Sendable {
  var hasLastSyncedAt: Bool { get }
  func readRows(request: SpaceListRequest, principalId: PrincipalID) async throws
    -> [SpaceBrowserPowerSyncRow]
  func watchRows(request: SpaceListRequest, principalId: PrincipalID) throws -> AsyncThrowingStream<
    [SpaceBrowserPowerSyncRow], Error
  >
}

final class PowerSyncSpaceBrowserLocalReader: SpaceBrowserLocalReading, @unchecked Sendable {
  private let database: any PowerSyncDatabaseProtocol
  init(database: any PowerSyncDatabaseProtocol) { self.database = database }
  var hasLastSyncedAt: Bool { database.currentStatus.lastSyncedAt != nil }

  func readRows(request: SpaceListRequest, principalId: PrincipalID) async throws
    -> [SpaceBrowserPowerSyncRow]
  {
    let query = Self.query(request: request, principalId: principalId)
    return try await database.getAll(
      sql: query.sql, parameters: query.parameters, mapper: SpaceBrowserPowerSyncRow.init(cursor:))
  }

  func watchRows(request: SpaceListRequest, principalId: PrincipalID) throws -> AsyncThrowingStream<
    [SpaceBrowserPowerSyncRow], Error
  > {
    let query = Self.query(request: request, principalId: principalId)
    return try database.watch(sql: query.sql, parameters: query.parameters) {
      try SpaceBrowserPowerSyncRow(cursor: $0)
    }
  }

  private static func query(request: SpaceListRequest, principalId: PrincipalID) -> (
    sql: String, parameters: [Sendable?]
  ) {
    switch request.scope {
    case .project(let projectId):
      return (
        projectSQL,
        [
          request.accountId.rawValue, principalId.rawValue, request.accountId.rawValue,
          projectId.rawValue,
        ]
      )
    case .businessInventory:
      return (
        inventorySQL,
        [request.accountId.rawValue, principalId.rawValue, request.accountId.rawValue]
      )
    }
  }

  private static let select = """
    SELECT CAST(scope.is_active AS INTEGER) AS is_active,
           (SELECT count(*) FROM selected_spaces) AS visible_count,
           space.id AS space_id, space.account_id, space.scope_kind,
           space.project_id, space.display_name, space.lifecycle, space.revision,
           detail.id AS detail_id, detail.account_id AS detail_account_id,
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
    LEFT JOIN selected_spaces AS space ON scope.is_active
    LEFT JOIN \(LedgerPowerSyncTable.spaceCoreDetails) AS detail
      ON detail.account_id = space.account_id AND detail.id = space.id
    LEFT JOIN \(LedgerPowerSyncTable.spaceChecklists) AS checklist
      ON checklist.account_id = space.account_id AND checklist.space_id = space.id
    LEFT JOIN \(LedgerPowerSyncTable.spaceChecklistItems) AS item
      ON item.account_id = checklist.account_id
     AND item.space_id = checklist.space_id
     AND item.checklist_id = checklist.checklist_id
    ORDER BY lower(space.display_name), space.display_name, space.id,
             checklist.presentation_order, checklist.checklist_id,
             item.presentation_order, item.item_id
    """

  private static let projectSQL = """
    WITH scope AS (
      SELECT EXISTS (SELECT 1 FROM \(LedgerPowerSyncTable.memberships)
        WHERE account_id = ? AND principal_id = ? AND state = 'active') AS is_active
    ), selected_spaces AS (
      SELECT id, account_id, scope_kind, project_id, display_name, lifecycle, revision
      FROM \(LedgerPowerSyncTable.spaces)
      WHERE account_id = ? AND scope_kind = 'project' AND project_id = ?
        AND lifecycle = 'active' AND (SELECT is_active FROM scope)
    )
    \(select)
    """

  private static let inventorySQL = """
    WITH scope AS (
      SELECT EXISTS (SELECT 1 FROM \(LedgerPowerSyncTable.memberships)
        WHERE account_id = ? AND principal_id = ? AND state = 'active') AS is_active
    ), selected_spaces AS (
      SELECT id, account_id, scope_kind, project_id, display_name, lifecycle, revision
      FROM \(LedgerPowerSyncTable.spaces)
      WHERE account_id = ? AND scope_kind = 'business_inventory'
        AND project_id IS NULL AND lifecycle = 'active'
        AND (SELECT is_active FROM scope)
    )
    \(select)
    """
}

struct SpaceBrowserSyncStreamIdentity: Equatable, Sendable, SyncStreamDescription {
  let name = "space_browser"
  let parameters: JsonParam?
  init(accountId: AccountID, scope: SpaceCreationScope) {
    switch scope {
    case .project(let projectId):
      parameters = [
        "account_id": .string(accountId.rawValue), "scope_kind": .string("project"),
        "project_id": .string(projectId.rawValue),
      ]
    case .businessInventory:
      parameters = [
        "account_id": .string(accountId.rawValue), "scope_kind": .string("business_inventory"),
      ]
    }
  }
}

struct SpaceBrowserSyncStatus: Equatable, Sendable {
  let connected: Bool
  let active: Bool
  let hasExplicitSubscription: Bool
  let lastSyncedAt: TimeInterval?
}

protocol SpaceBrowserSyncSubscription: Sendable {
  var identity: SpaceBrowserSyncStreamIdentity { get }
  var baselineLastSyncedAt: TimeInterval? { get }
  func waitForFirstSync() async throws
  func currentStatus() -> SpaceBrowserSyncStatus?
  func observeStatus(_ receive: @Sendable (SpaceBrowserSyncStatus) async throws -> Void)
    async throws
  func unsubscribe() async throws
}

protocol SpaceBrowserSyncSubscribing: Sendable {
  func subscribe(accountId: AccountID, scope: SpaceCreationScope) async throws
    -> any SpaceBrowserSyncSubscription
}

private struct PowerSyncSpaceBrowserSubscription: SpaceBrowserSyncSubscription, @unchecked Sendable
{
  let base: any SyncStreamSubscription
  let identity: SpaceBrowserSyncStreamIdentity
  let baselineLastSyncedAt: TimeInterval?
  let database: any PowerSyncDatabaseProtocol
  func waitForFirstSync() async throws { try await base.waitForFirstSync() }
  func currentStatus() -> SpaceBrowserSyncStatus? {
    guard let exact = database.currentStatus.forStream(stream: base) else { return nil }
    return .init(
      connected: database.currentStatus.connected, active: exact.subscription.active,
      hasExplicitSubscription: exact.subscription.hasExplicitSubscription,
      lastSyncedAt: exact.subscription.lastSyncedAt)
  }
  func observeStatus(_ receive: @Sendable (SpaceBrowserSyncStatus) async throws -> Void)
    async throws
  {
    for await status in database.currentStatus.asFlow() {
      try Task.checkCancellation()
      guard let exact = status.forStream(stream: base) else { continue }
      try await receive(
        .init(
          connected: status.connected, active: exact.subscription.active,
          hasExplicitSubscription: exact.subscription.hasExplicitSubscription,
          lastSyncedAt: exact.subscription.lastSyncedAt))
    }
    try Task.checkCancellation()
  }
  func unsubscribe() async throws { try await base.unsubscribe() }
}

final class PowerSyncSpaceBrowserSyncSource: SpaceBrowserSyncSubscribing, @unchecked Sendable {
  private let database: any PowerSyncDatabaseProtocol
  init(database: any PowerSyncDatabaseProtocol) { self.database = database }

  func subscribe(accountId: AccountID, scope: SpaceCreationScope) async throws
    -> any SpaceBrowserSyncSubscription
  {
    let identity = SpaceBrowserSyncStreamIdentity(accountId: accountId, scope: scope)
    var statuses = database.currentStatus.asFlow().makeAsyncIterator()
    var publicBaseline: TimeInterval?
    while let status = await statuses.next() {
      try Task.checkCancellation()
      guard status.syncStreams != nil else { continue }
      publicBaseline = try Self.validatedEpoch(
        status.forStream(stream: identity)?.subscription.lastSyncedAt)
      break
    }
    let retainedBaseline = try await retainedLastSyncedAt(for: identity)
    let baseline = [publicBaseline, retainedBaseline].compactMap { $0 }.max()
    let stream = database.syncStream(name: identity.name, params: identity.parameters)
    return PowerSyncSpaceBrowserSubscription(
      base: try await stream.subscribe(), identity: identity, baselineLastSyncedAt: baseline,
      database: database)
  }

  private func retainedLastSyncedAt(for identity: SpaceBrowserSyncStreamIdentity) async throws
    -> TimeInterval?
  {
    let rows: [RetainedEpoch] = try await database.getAll(
      sql: """
        SELECT local_params, last_synced_at FROM ps_stream_subscriptions
        WHERE stream_name = ? AND last_synced_at IS NOT NULL ORDER BY id
        """, parameters: [identity.name]
    ) { cursor in
      RetainedEpoch(
        parametersJSON: try cursor.getString(index: 0), coreEpoch: try cursor.getInt64(index: 1))
    }
    let expected = identity.parameters.map(JsonValue.object) ?? .null
    let exact = try rows.compactMap { row -> TimeInterval? in
      let decoded = try JSONDecoder().decode(JsonValue.self, from: Data(row.parametersJSON.utf8))
      guard decoded == expected else { return nil }
      return try Self.validatedEpoch(TimeInterval(row.coreEpoch) / 1_000_000)
    }
    guard exact.count <= 1 else { throw SpaceBrowserPowerSyncFailure.malformedScopeEvidence }
    return exact.first
  }

  private static func validatedEpoch(_ epoch: TimeInterval?) throws -> TimeInterval? {
    guard let epoch else { return nil }
    guard epoch.isFinite, epoch > 0 else {
      throw SpaceBrowserPowerSyncFailure.malformedScopeEvidence
    }
    return epoch
  }

  private struct RetainedEpoch: Sendable {
    let parametersJSON: String
    let coreEpoch: Int64
  }
}

final class SpaceBrowserPowerSyncProvider: SpaceListQuerying, @unchecked Sendable {
  private let localReader: any SpaceBrowserLocalReading
  private let syncSource: any SpaceBrowserSyncSubscribing
  private let principalId: PrincipalID
  private let boundAccountId: AccountID
  private let now: @Sendable () -> Date
  private let registry = SpaceBrowserWatchRegistry()

  convenience init(
    database: any PowerSyncDatabaseProtocol, principalId: PrincipalID, accountId: AccountID,
    now: @Sendable @escaping () -> Date = Date.init
  ) {
    self.init(
      localReader: PowerSyncSpaceBrowserLocalReader(database: database),
      syncSource: PowerSyncSpaceBrowserSyncSource(database: database), principalId: principalId,
      accountId: accountId, now: now)
  }

  init(
    localReader: any SpaceBrowserLocalReading, syncSource: any SpaceBrowserSyncSubscribing,
    principalId: PrincipalID, accountId: AccountID, now: @Sendable @escaping () -> Date = Date.init
  ) {
    self.localReader = localReader
    self.syncSource = syncSource
    self.principalId = principalId
    boundAccountId = accountId
    self.now = now
  }

  func watchSpaces(_ request: SpaceListRequest) -> AsyncThrowingStream<SpaceListUpdate, Error> {
    guard request.accountId == boundAccountId else {
      return Self.failedStream(SpaceListFailure.accountScopeMismatch)
    }
    return AsyncThrowingStream { continuation in
      let id = UUID()
      let handle = SpaceBrowserWatchTaskHandle()
      let registration = Task { await registry.register(id: id, handle: handle) }
      let task = Task {
        let admitted = await registration.value
        guard admitted, !Task.isCancelled else {
          continuation.finish()
          if admitted { await registry.finished(id: id) }
          return
        }
        await runWatch(request: request, continuation: continuation)
        await registry.finished(id: id)
      }
      handle.install(task)
      continuation.onTermination = { _ in handle.cancel() }
    }
  }

  func cancelAndDrainWatches() async { await registry.cancelAndDrain() }

  private enum Event: Sendable {
    case rowsInvalidated([SpaceBrowserPowerSyncRow])
    case currentProcessSync(TimeInterval)
    case freshnessLost
  }

  private func runWatch(
    request: SpaceListRequest,
    continuation: AsyncThrowingStream<SpaceListUpdate, Error>.Continuation
  ) async {
    let rowUpdates: AsyncThrowingStream<[SpaceBrowserPowerSyncRow], Error>
    let initialSnapshot: SpaceListLocalSnapshot
    do {
      // Install the invalidation watch before the point-in-time read so an
      // intervening local change cannot be missed. Row evidence is useful
      // offline and must not wait for subscription setup or network status.
      rowUpdates = try localReader.watchRows(request: request, principalId: principalId)
      let initialRows = try await localReader.readRows(request: request, principalId: principalId)
      initialSnapshot = try makeSnapshot(
        request: request,
        evidence: .init(rows: initialRows, currentProcessSyncEpoch: nil))
      continuation.yield(
        try SpaceListUpdate(request: request, state: .snapshot(initialSnapshot)))
    } catch is CancellationError {
      continuation.finish()
      return
    } catch let failure as SpaceListFailure {
      continuation.finish(throwing: failure)
      return
    } catch {
      continuation.finish(throwing: SpaceListFailure.localReadFailed)
      return
    }

    let events = AsyncThrowingStream<Event, Error>.makeStream()
    let databaseTask = Task {
      do {
        for try await rows in rowUpdates {
          try Task.checkCancellation()
          events.continuation.yield(.rowsInvalidated(rows))
        }
        events.continuation.finish()
      } catch is CancellationError {
        events.continuation.finish()
      } catch {
        events.continuation.finish(throwing: error)
      }
    }
    let subscriptionTask = Task {
      do {
        let subscription = try await syncSource.subscribe(
          accountId: request.accountId, scope: request.scope)
        let freshness = SpaceBrowserFreshnessTracker(baseline: subscription.baselineLastSyncedAt)
        var statusObserverCompletedNormally = false
        do {
          if subscription.baselineLastSyncedAt == nil {
            try await subscription.waitForFirstSync()
            try Task.checkCancellation()
            guard let status = subscription.currentStatus(),
              let epoch = try await freshness.establishCausalFirstSync(status)
            else {
              throw SpaceBrowserPowerSyncFailure.malformedScopeEvidence
            }
            events.continuation.yield(.currentProcessSync(epoch))
          }
          try await subscription.observeStatus { status in
            guard status.connected, status.active, status.hasExplicitSubscription else {
              events.continuation.yield(.freshnessLost)
              return
            }
            if let epoch = await freshness.accept(status) {
              events.continuation.yield(.currentProcessSync(epoch))
            }
          }
          statusObserverCompletedNormally = true
        } catch is CancellationError {
          // Cancellation is completed by unsubscribe and task drainage below.
        } catch {
          events.continuation.finish(throwing: error)
        }
        try? await subscription.unsubscribe()
        if statusObserverCompletedNormally {
          // A completed status observer no longer proves ongoing exact-stream
          // authority. Revoke readiness before ending this bounded watch.
          events.continuation.yield(.freshnessLost)
          events.continuation.finish()
        }
      } catch is CancellationError {
        events.continuation.finish()
      } catch {
        events.continuation.finish(throwing: error)
      }
    }

    do {
      var state = SpaceBrowserObservedState()
      var lastVersion = initialSnapshot.local.localDataVersion
      for try await event in events.stream {
        try Task.checkCancellation()
        let evidence: SpaceBrowserCombinedEvidence?
        switch event {
        case .rowsInvalidated(let observedRows):
          let observedActive = try Self.validateScope(observedRows)
          _ = try makeSnapshot(
            request: request, evidence: .init(rows: observedRows, currentProcessSyncEpoch: nil))
          if !observedActive { state.resetCompleteness() }
          evidence = state.observeRows(
            try await localReader.readRows(request: request, principalId: principalId))
        case .currentProcessSync(let epoch):
          let fresh = try await localReader.readRows(request: request, principalId: principalId)
          evidence = state.observeCurrentProcessSync(epoch: epoch, freshRows: fresh)
        case .freshnessLost:
          state.resetCompleteness()
          evidence = state.observeRows(
            try await localReader.readRows(request: request, principalId: principalId))
        }
        guard let evidence else { continue }
        let snapshot = try makeSnapshot(request: request, evidence: evidence)
        guard snapshot.local.localDataVersion != lastVersion else { continue }
        lastVersion = snapshot.local.localDataVersion
        continuation.yield(try SpaceListUpdate(request: request, state: .snapshot(snapshot)))
      }
      continuation.finish()
    } catch is CancellationError {
      continuation.finish()
    } catch let failure as SpaceListFailure {
      continuation.finish(throwing: failure)
    } catch {
      continuation.finish(throwing: SpaceListFailure.localReadFailed)
    }
    databaseTask.cancel()
    subscriptionTask.cancel()
    _ = await databaseTask.result
    _ = await subscriptionTask.result
    events.continuation.finish()
  }

  private func makeSnapshot(request: SpaceListRequest, evidence: SpaceBrowserCombinedEvidence)
    throws -> SpaceListLocalSnapshot
  {
    let active = try Self.validateScope(evidence.rows)
    let reconstructed = try Self.reconstruct(request: request, rows: evidence.rows)
    let complete = active && evidence.currentProcessSyncEpoch != nil
    let quality: ListSnapshotQuality =
      !active ? .partial : complete ? .ready : localReader.hasLastSyncedAt ? .stale : .partial
    let asOf = now()
    let provisional = try SpaceListLocalSnapshot(
      request: request, rows: reconstructed, visibleRowCountBeforeFiltering: reconstructed.count,
      isCompleteForQuery: complete, quality: quality,
      localDataVersion: LocalDataVersion(validating: "space-browser-provisional"), asOf: asOf)
    let version = try Self.localDataVersion(
      request: request, active: active, currentProcessSyncEpoch: evidence.currentProcessSyncEpoch,
      complete: complete, quality: quality, rows: provisional.local.rows)
    return try SpaceListLocalSnapshot(
      request: request, rows: provisional.local.rows,
      visibleRowCountBeforeFiltering: provisional.local.rows.count, isCompleteForQuery: complete,
      quality: quality, localDataVersion: version, asOf: asOf)
  }

  private static func validateScope(_ rows: [SpaceBrowserPowerSyncRow]) throws -> Bool {
    guard let first = rows.first, rows.allSatisfy({ $0.scopeRawValue == first.scopeRawValue }),
      first.scopeRawValue == 0 || first.scopeRawValue == 1
    else {
      throw SpaceBrowserPowerSyncFailure.malformedScopeEvidence
    }
    let active = first.scopeRawValue == 1
    let sentinels = rows.filter { $0.spaceId == nil }
    guard sentinels.allSatisfy(\.isExactSentinel),
      sentinels.count == (rows.count == 1 && first.spaceId == nil ? 1 : 0),
      active || sentinels.count == 1
    else {
      throw SpaceBrowserPowerSyncFailure.malformedScopeEvidence
    }
    let count = Set(rows.compactMap(\.spaceId)).count
    guard rows.allSatisfy({ $0.visibleCount == Int64(count) }) else {
      throw SpaceListFailure.visibleCountMismatch
    }
    return active
  }

  private static func reconstruct(request: SpaceListRequest, rows: [SpaceBrowserPowerSyncRow])
    throws -> [SpaceListSourceRow]
  {
    guard rows.first?.spaceId != nil else { return [] }
    var order: [String] = []
    var grouped: [String: [SpaceBrowserPowerSyncRow]] = [:]
    for row in rows {
      guard let id = row.spaceId else { throw SpaceBrowserPowerSyncFailure.malformedSpaceHierarchy }
      if grouped[id] == nil { order.append(id) }
      grouped[id, default: []].append(row)
    }
    return try order.map { try reconstructSpace(request: request, rows: grouped[$0]!) }
  }

  private static func reconstructSpace(request: SpaceListRequest, rows: [SpaceBrowserPowerSyncRow])
    throws -> SpaceListSourceRow
  {
    guard let first = rows.first, let spaceId = first.spaceId, let accountId = first.accountId,
      accountId == request.accountId.rawValue, let displayName = first.displayName,
      first.lifecycle == DirectoryLifecycleState.active.rawValue,
      let revision = first.revision, revision > 0, first.detailId == spaceId,
      first.detailAccountId == accountId, rows.allSatisfy({ $0.sameParent(as: first) })
    else {
      throw SpaceBrowserPowerSyncFailure.malformedSpaceHierarchy
    }
    let scope: SpaceCreationScope
    switch first.scopeKind {
    case "project":
      guard let projectId = first.projectId else {
        throw SpaceBrowserPowerSyncFailure.malformedSpaceHierarchy
      }
      scope = .project(try ProjectID(validating: projectId))
    case "business_inventory":
      guard first.projectId == nil else {
        throw SpaceBrowserPowerSyncFailure.malformedSpaceHierarchy
      }
      scope = .businessInventory
    default:
      throw SpaceBrowserPowerSyncFailure.malformedSpaceHierarchy
    }
    guard scope == request.scope else { throw SpaceListFailure.spaceScopeMismatch }
    let canonicalName = try SpaceDisplayName(validating: displayName)
    guard canonicalName.rawValue == displayName, let exactRevision = UInt64(exactly: revision)
    else { throw SpaceBrowserPowerSyncFailure.malformedSpaceHierarchy }

    var checklistOrder: [String] = []
    var builders: [String: SpaceBrowserChecklistBuilder] = [:]
    for row in rows {
      guard let checklistRowId = row.checklistRowId else {
        guard row.hasNoChecklistOrItem else {
          throw SpaceBrowserPowerSyncFailure.malformedSpaceHierarchy
        }
        continue
      }
      guard row.checklistAccountId == accountId, row.checklistSpaceId == spaceId,
        let checklistId = row.checklistId, let checklistName = row.checklistName,
        let rawOrder = row.checklistOrder, let order = UInt32(exactly: rawOrder)
      else {
        throw SpaceBrowserPowerSyncFailure.malformedSpaceHierarchy
      }
      let header = SpaceBrowserChecklistHeader(
        rowId: checklistRowId, id: checklistId, name: checklistName, order: order)
      if let prior = builders[checklistRowId] {
        guard prior.header == header else {
          throw SpaceBrowserPowerSyncFailure.malformedSpaceHierarchy
        }
      } else {
        checklistOrder.append(checklistRowId)
        builders[checklistRowId] = .init(header: header, items: [])
      }
      guard let itemRowId = row.itemRowId else {
        guard row.hasNoItem else { throw SpaceBrowserPowerSyncFailure.malformedSpaceHierarchy }
        continue
      }
      guard row.itemAccountId == accountId, row.itemSpaceId == spaceId,
        row.itemChecklistId == checklistId, let itemId = row.itemId,
        let itemText = row.itemText, let checked = row.itemIsChecked,
        checked == 0 || checked == 1, let rawItemOrder = row.itemOrder,
        let itemOrder = UInt32(exactly: rawItemOrder), var builder = builders[checklistRowId],
        !builder.items.contains(where: { $0.rowId == itemRowId })
      else {
        throw SpaceBrowserPowerSyncFailure.malformedSpaceHierarchy
      }
      builder.items.append(
        .init(
          rowId: itemRowId, id: itemId, text: itemText, isChecked: checked == 1, order: itemOrder))
      builders[checklistRowId] = builder
    }
    let checklists = try checklistOrder.compactMap { builders[$0] }.map { builder in
      let name = try SpaceChecklistName(validating: builder.header.name)
      guard name.rawValue == builder.header.name else {
        throw SpaceBrowserPowerSyncFailure.malformedSpaceHierarchy
      }
      return try SpaceChecklistState(
        id: SpaceChecklistID(validating: builder.header.id), name: name,
        presentationOrder: builder.header.order,
        items: try builder.items.map { item in
          let text = try SpaceChecklistItemText(validating: item.text)
          guard text.rawValue == item.text else {
            throw SpaceBrowserPowerSyncFailure.malformedSpaceHierarchy
          }
          return SpaceChecklistItemState(
            id: try SpaceChecklistItemID(validating: item.id), text: text,
            isChecked: item.isChecked, presentationOrder: item.order)
        })
    }
    return SpaceListSourceRow(
      id: try SpaceID(validating: spaceId), accountId: try AccountID(validating: accountId),
      scope: scope, displayName: canonicalName, lifecycle: .active, revision: exactRevision,
      checklists: try SpaceChecklistCollection(checklists: checklists))
  }

  private static func localDataVersion(
    request: SpaceListRequest, active: Bool, currentProcessSyncEpoch: TimeInterval?, complete: Bool,
    quality: ListSnapshotQuality, rows: [SpaceListSourceRow]
  ) throws -> LocalDataVersion {
    let basis = VersionBasis(
      contractVersion: "space-browser-local-v1", request: request, active: active,
      currentProcessSyncEpoch: currentProcessSyncEpoch, complete: complete, quality: quality,
      rows: rows)
    let digest = SHA256.hash(data: try OperationContractCodec.encode(basis)).map {
      String(format: "%02x", $0)
    }.joined()
    return try LocalDataVersion(validating: "space-browser-\(digest)")
  }

  private static func failedStream<Value: Sendable>(_ error: Error) -> AsyncThrowingStream<
    Value, Error
  > { AsyncThrowingStream { $0.finish(throwing: error) } }
  private struct VersionBasis: Codable {
    let contractVersion: String
    let request: SpaceListRequest
    let active: Bool
    let currentProcessSyncEpoch: TimeInterval?
    let complete: Bool
    let quality: ListSnapshotQuality
    let rows: [SpaceListSourceRow]
  }
}

private actor SpaceBrowserFreshnessTracker {
  private enum Mode {
    case reliable(TimeInterval?)
    case causal(first: TimeInterval, accepted: TimeInterval?)
  }
  private var mode: Mode
  init(baseline: TimeInterval?) { mode = .reliable(baseline) }
  func establishCausalFirstSync(_ status: SpaceBrowserSyncStatus) throws -> TimeInterval? {
    guard let epoch = status.lastSyncedAt, Self.valid(epoch) else {
      throw SpaceBrowserPowerSyncFailure.malformedScopeEvidence
    }
    mode = .causal(first: epoch, accepted: nil)
    return accept(status)
  }
  func accept(_ status: SpaceBrowserSyncStatus) -> TimeInterval? {
    guard status.connected, status.active, status.hasExplicitSubscription else { return nil }
    if let epoch = status.lastSyncedAt, !Self.valid(epoch) { return nil }
    switch mode {
    case .reliable(let baseline):
      guard let epoch = status.lastSyncedAt, baseline.map({ epoch > $0 }) ?? true else {
        return nil
      }
      mode = .reliable(epoch)
      return epoch
    case .causal(let first, let accepted):
      guard let epoch = status.lastSyncedAt, epoch >= first, accepted.map({ epoch > $0 }) ?? true
      else { return nil }
      mode = .causal(first: first, accepted: epoch)
      return epoch
    }
  }
  private static func valid(_ epoch: TimeInterval) -> Bool { epoch.isFinite && epoch > 0 }
}

struct SpaceBrowserCombinedEvidence: Equatable, Sendable {
  let rows: [SpaceBrowserPowerSyncRow]
  let currentProcessSyncEpoch: TimeInterval?
}

struct SpaceBrowserObservedState: Sendable {
  private var rows: [SpaceBrowserPowerSyncRow]?
  private var currentProcessSyncEpoch: TimeInterval?
  mutating func resetCompleteness() { currentProcessSyncEpoch = nil }
  mutating func observeRows(_ value: [SpaceBrowserPowerSyncRow]) -> SpaceBrowserCombinedEvidence? {
    rows = value
    if value.first?.scopeRawValue != 1 { currentProcessSyncEpoch = nil }
    return evidence
  }
  mutating func observeCurrentProcessSync(
    epoch: TimeInterval, freshRows: [SpaceBrowserPowerSyncRow]
  ) -> SpaceBrowserCombinedEvidence? {
    rows = freshRows
    currentProcessSyncEpoch = freshRows.first?.scopeRawValue == 1 ? epoch : nil
    return evidence
  }
  private var evidence: SpaceBrowserCombinedEvidence? {
    guard let rows else { return nil }
    return .init(rows: rows, currentProcessSyncEpoch: currentProcessSyncEpoch)
  }
}

private final class SpaceBrowserWatchTaskHandle: @unchecked Sendable {
  private let lock = NSLock()
  private var task: Task<Void, Never>?
  private var cancellationRequested = false
  func install(_ task: Task<Void, Never>) {
    let cancel = lock.withLock {
      self.task = task
      return cancellationRequested
    }
    if cancel { task.cancel() }
  }
  func cancel() {
    let task = lock.withLock {
      cancellationRequested = true
      return self.task
    }
    task?.cancel()
  }
}

private actor SpaceBrowserWatchRegistry {
  private var handles: [UUID: SpaceBrowserWatchTaskHandle] = [:]
  private var closing = false
  private var waiters: [CheckedContinuation<Void, Never>] = []
  func register(id: UUID, handle: SpaceBrowserWatchTaskHandle) -> Bool {
    guard !closing else {
      handle.cancel()
      return false
    }
    handles[id] = handle
    return true
  }
  func finished(id: UUID) {
    handles.removeValue(forKey: id)
    guard handles.isEmpty else { return }
    let current = waiters
    waiters.removeAll()
    current.forEach { $0.resume() }
  }
  func cancelAndDrain() async {
    closing = true
    handles.values.forEach { $0.cancel() }
    guard !handles.isEmpty else { return }
    await withCheckedContinuation { waiters.append($0) }
  }
}

private struct SpaceBrowserChecklistHeader: Equatable, Sendable {
  let rowId: String
  let id: String
  let name: String
  let order: UInt32
}
private struct SpaceBrowserItemBuilder: Equatable, Sendable {
  let rowId: String
  let id: String
  let text: String
  let isChecked: Bool
  let order: UInt32
}
private struct SpaceBrowserChecklistBuilder: Equatable, Sendable {
  let header: SpaceBrowserChecklistHeader
  var items: [SpaceBrowserItemBuilder]
}

struct SpaceBrowserPowerSyncRow: Equatable, Sendable {
  let scopeRawValue: Int64
  let visibleCount: Int64
  let spaceId: String?
  let accountId: String?
  let scopeKind: String?
  let projectId: String?
  let displayName: String?
  let lifecycle: String?
  let revision: Int64?
  let detailId: String?
  let detailAccountId: String?
  let checklistRowId: String?
  let checklistAccountId: String?
  let checklistSpaceId: String?
  let checklistId: String?
  let checklistName: String?
  let checklistOrder: Int64?
  let itemRowId: String?
  let itemAccountId: String?
  let itemSpaceId: String?
  let itemChecklistId: String?
  let itemId: String?
  let itemText: String?
  let itemIsChecked: Int64?
  let itemOrder: Int64?

  init(
    scopeRawValue: Int64, visibleCount: Int64, spaceId: String? = nil, accountId: String? = nil,
    scopeKind: String? = nil, projectId: String? = nil, displayName: String? = nil,
    lifecycle: String? = nil, revision: Int64? = nil, detailId: String? = nil,
    detailAccountId: String? = nil, checklistRowId: String? = nil,
    checklistAccountId: String? = nil, checklistSpaceId: String? = nil, checklistId: String? = nil,
    checklistName: String? = nil, checklistOrder: Int64? = nil, itemRowId: String? = nil,
    itemAccountId: String? = nil, itemSpaceId: String? = nil, itemChecklistId: String? = nil,
    itemId: String? = nil, itemText: String? = nil, itemIsChecked: Int64? = nil,
    itemOrder: Int64? = nil
  ) {
    self.scopeRawValue = scopeRawValue
    self.visibleCount = visibleCount
    self.spaceId = spaceId
    self.accountId = accountId
    self.scopeKind = scopeKind
    self.projectId = projectId
    self.displayName = displayName
    self.lifecycle = lifecycle
    self.revision = revision
    self.detailId = detailId
    self.detailAccountId = detailAccountId
    self.checklistRowId = checklistRowId
    self.checklistAccountId = checklistAccountId
    self.checklistSpaceId = checklistSpaceId
    self.checklistId = checklistId
    self.checklistName = checklistName
    self.checklistOrder = checklistOrder
    self.itemRowId = itemRowId
    self.itemAccountId = itemAccountId
    self.itemSpaceId = itemSpaceId
    self.itemChecklistId = itemChecklistId
    self.itemId = itemId
    self.itemText = itemText
    self.itemIsChecked = itemIsChecked
    self.itemOrder = itemOrder
  }

  init(cursor: any SqlCursor) throws {
    scopeRawValue = try cursor.getInt64(name: "is_active")
    visibleCount = try cursor.getInt64(name: "visible_count")
    spaceId = try cursor.getStringOptional(name: "space_id")
    accountId = try cursor.getStringOptional(name: "account_id")
    scopeKind = try cursor.getStringOptional(name: "scope_kind")
    projectId = try cursor.getStringOptional(name: "project_id")
    displayName = try cursor.getStringOptional(name: "display_name")
    lifecycle = try cursor.getStringOptional(name: "lifecycle")
    revision = try cursor.getInt64Optional(name: "revision")
    detailId = try cursor.getStringOptional(name: "detail_id")
    detailAccountId = try cursor.getStringOptional(name: "detail_account_id")
    checklistRowId = try cursor.getStringOptional(name: "checklist_row_id")
    checklistAccountId = try cursor.getStringOptional(name: "checklist_account_id")
    checklistSpaceId = try cursor.getStringOptional(name: "checklist_space_id")
    checklistId = try cursor.getStringOptional(name: "checklist_id")
    checklistName = try cursor.getStringOptional(name: "checklist_name")
    checklistOrder = try cursor.getInt64Optional(name: "checklist_order")
    itemRowId = try cursor.getStringOptional(name: "item_row_id")
    itemAccountId = try cursor.getStringOptional(name: "item_account_id")
    itemSpaceId = try cursor.getStringOptional(name: "item_space_id")
    itemChecklistId = try cursor.getStringOptional(name: "item_checklist_id")
    itemId = try cursor.getStringOptional(name: "item_id")
    itemText = try cursor.getStringOptional(name: "item_text")
    itemIsChecked = try cursor.getInt64Optional(name: "is_checked")
    itemOrder = try cursor.getInt64Optional(name: "item_order")
  }

  var isExactSentinel: Bool {
    visibleCount == 0 && spaceId == nil && accountId == nil && scopeKind == nil
      && projectId == nil && displayName == nil && lifecycle == nil && revision == nil
      && detailId == nil && detailAccountId == nil && hasNoChecklistOrItem
  }
  var hasNoChecklistOrItem: Bool {
    checklistRowId == nil && checklistAccountId == nil && checklistSpaceId == nil
      && checklistId == nil && checklistName == nil && checklistOrder == nil && hasNoItem
  }
  var hasNoItem: Bool {
    itemRowId == nil && itemAccountId == nil && itemSpaceId == nil
      && itemChecklistId == nil && itemId == nil && itemText == nil
      && itemIsChecked == nil && itemOrder == nil
  }
  func sameParent(as other: Self) -> Bool {
    spaceId == other.spaceId && accountId == other.accountId && scopeKind == other.scopeKind
      && projectId == other.projectId && displayName == other.displayName
      && lifecycle == other.lifecycle && revision == other.revision
      && detailId == other.detailId && detailAccountId == other.detailAccountId
  }
}
