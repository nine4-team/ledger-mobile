import CryptoKit
import Foundation
import LedgerTargetCore
import PowerSync

enum SpaceAssignmentDestinationPowerSyncFailure: Error, Equatable, Sendable {
    case malformedScopeEvidence
    case malformedDestinationRow
}

protocol SpaceAssignmentDestinationLocalReading: Sendable {
    var hasLastSyncedAt: Bool { get }
    func readRows(
        request: SpaceAssignmentDestinationRequest,
        principalId: PrincipalID
    ) async throws -> [SpaceAssignmentDestinationPowerSyncRow]
    func watchRows(
        request: SpaceAssignmentDestinationRequest,
        principalId: PrincipalID
    ) throws -> AsyncThrowingStream<[SpaceAssignmentDestinationPowerSyncRow], Error>
}

protocol SpaceAssignmentDestinationSyncSubscription: Sendable {
    var identity: SpaceAssignmentDestinationSyncStreamIdentity { get }
    var baselineLastSyncedAt: TimeInterval? { get }
    func waitForFirstSync() async throws
    func currentStatus() -> SpaceAssignmentDestinationSyncStreamStatus?
    func observeStatus(
        _ receive: @Sendable (SpaceAssignmentDestinationSyncStreamStatus) async throws -> Void
    ) async throws
    func unsubscribe() async throws
}

struct SpaceAssignmentDestinationSyncStreamStatus: Equatable, Sendable {
    let connected: Bool
    let active: Bool
    let hasExplicitSubscription: Bool
    let lastSyncedAt: TimeInterval?
}

protocol SpaceAssignmentDestinationSyncSubscribing: Sendable {
    func subscribe(
        accountId: AccountID,
        scope: ItemPlacementScope
    ) async throws -> any SpaceAssignmentDestinationSyncSubscription
}

final class PowerSyncSpaceAssignmentDestinationLocalReader:
    SpaceAssignmentDestinationLocalReading, @unchecked Sendable
{
    private let database: any PowerSyncDatabaseProtocol
    init(database: any PowerSyncDatabaseProtocol) { self.database = database }
    var hasLastSyncedAt: Bool { database.currentStatus.lastSyncedAt != nil }

    func readRows(
        request: SpaceAssignmentDestinationRequest,
        principalId: PrincipalID
    ) async throws -> [SpaceAssignmentDestinationPowerSyncRow] {
        let query = Self.query(request: request, principalId: principalId)
        return try await database.getAll(
            sql: query.sql,
            parameters: query.parameters,
            mapper: SpaceAssignmentDestinationPowerSyncRow.init(cursor:)
        )
    }

    func watchRows(
        request: SpaceAssignmentDestinationRequest,
        principalId: PrincipalID
    ) throws -> AsyncThrowingStream<[SpaceAssignmentDestinationPowerSyncRow], Error> {
        let query = Self.query(request: request, principalId: principalId)
        return try database.watch(sql: query.sql, parameters: query.parameters) {
            try SpaceAssignmentDestinationPowerSyncRow(cursor: $0)
        }
    }

    private static func query(
        request: SpaceAssignmentDestinationRequest,
        principalId: PrincipalID
    ) -> (sql: String, parameters: [Sendable?]) {
        switch request.scope {
        case .project(let projectId):
            return (projectSQL, [
                request.accountId.rawValue, principalId.rawValue,
                request.accountId.rawValue, projectId.rawValue,
            ])
        case .businessInventory:
            return (inventorySQL, [
                request.accountId.rawValue, principalId.rawValue,
                request.accountId.rawValue,
            ])
        }
    }

    private static let select = """
        SELECT scope.is_active,
               CASE WHEN scope.is_active THEN visible.visible_count ELSE 0 END AS visible_count,
               destination.id, destination.account_id, destination.scope_kind,
               destination.project_id, destination.display_name,
               destination.lifecycle, destination.revision
        FROM scope CROSS JOIN visible
        LEFT JOIN destinations AS destination ON scope.is_active
        ORDER BY lower(destination.display_name), destination.display_name, destination.id
        """
    private static let projectSQL = """
        WITH scope AS (
          SELECT EXISTS (SELECT 1 FROM spike_account_memberships
            WHERE account_id = ? AND principal_id = ? AND state = 'active') AS is_active
        ), destinations AS (
          SELECT id, account_id, scope_kind, project_id, display_name, lifecycle, revision
          FROM spike_spaces
          WHERE account_id = ? AND scope_kind = 'project' AND project_id = ?
        ), visible AS (SELECT count(*) AS visible_count FROM destinations)
        \(select)
        """
    private static let inventorySQL = """
        WITH scope AS (
          SELECT EXISTS (SELECT 1 FROM spike_account_memberships
            WHERE account_id = ? AND principal_id = ? AND state = 'active') AS is_active
        ), destinations AS (
          SELECT id, account_id, scope_kind, project_id, display_name, lifecycle, revision
          FROM spike_spaces
          WHERE account_id = ? AND scope_kind = 'business_inventory' AND project_id IS NULL
        ), visible AS (SELECT count(*) AS visible_count FROM destinations)
        \(select)
        """
}

private struct PowerSyncSpaceAssignmentDestinationSubscription:
    SpaceAssignmentDestinationSyncSubscription, @unchecked Sendable
{
    let base: any SyncStreamSubscription
    let identity: SpaceAssignmentDestinationSyncStreamIdentity
    let baselineLastSyncedAt: TimeInterval?
    let database: any PowerSyncDatabaseProtocol

    func waitForFirstSync() async throws { try await base.waitForFirstSync() }

    func currentStatus() -> SpaceAssignmentDestinationSyncStreamStatus? {
        Self.map(database.currentStatus, stream: base)
    }

    func observeStatus(
        _ receive: @Sendable (SpaceAssignmentDestinationSyncStreamStatus) async throws -> Void
    ) async throws {
        for await status in database.currentStatus.asFlow() {
            try Task.checkCancellation()
            guard let mapped = Self.map(status, stream: base) else { continue }
            try await receive(mapped)
        }
        try Task.checkCancellation()
    }

    private static func map(
        _ status: any SyncStatusData,
        stream: any SyncStreamDescription
    ) -> SpaceAssignmentDestinationSyncStreamStatus? {
        guard let exact = status.forStream(stream: stream) else { return nil }
        let subscription = exact.subscription
        return .init(
            connected: status.connected,
            active: subscription.active,
            hasExplicitSubscription: subscription.hasExplicitSubscription,
            lastSyncedAt: subscription.lastSyncedAt
        )
    }

    func unsubscribe() async throws { try await base.unsubscribe() }
}

final class PowerSyncSpaceAssignmentDestinationSyncSource:
    SpaceAssignmentDestinationSyncSubscribing, @unchecked Sendable
{
    private let database: any PowerSyncDatabaseProtocol
    init(database: any PowerSyncDatabaseProtocol) { self.database = database }

    func subscribe(
        accountId: AccountID,
        scope: ItemPlacementScope
    ) async throws -> any SpaceAssignmentDestinationSyncSubscription {
        let identity = SpaceAssignmentDestinationSyncStreamIdentity(
            accountId: accountId, scope: scope
        )
        var statuses = database.currentStatus.asFlow().makeAsyncIterator()
        var publicBaseline: TimeInterval?
        while let status = await statuses.next() {
            try Task.checkCancellation()
            guard status.syncStreams != nil else { continue }
            let exact = status.forStream(stream: identity)
            publicBaseline = try Self.validatedEpoch(exact?.subscription.lastSyncedAt)
            break
        }
        let retainedBaseline = try await retainedLastSyncedAt(for: identity)
        let baseline = [publicBaseline, retainedBaseline].compactMap { $0 }.max()
        let stream = database.syncStream(name: identity.name, params: identity.parameters)
        return PowerSyncSpaceAssignmentDestinationSubscription(
            base: try await stream.subscribe(),
            identity: identity,
            baselineLastSyncedAt: baseline,
            database: database
        )
    }

    /// PowerSync 1.16.1's subscribe UPSERT intentionally preserves the retained
    /// `last_synced_at`. Read that value before subscribing so a cached epoch can
    /// never satisfy this process's freshness requirement.
    private func retainedLastSyncedAt(
        for identity: SpaceAssignmentDestinationSyncStreamIdentity
    ) async throws -> TimeInterval? {
        let rows: [RetainedSubscriptionEpoch] = try await database.getAll(
            sql: """
                SELECT local_params, last_synced_at
                FROM ps_stream_subscriptions
                WHERE stream_name = ? AND last_synced_at IS NOT NULL
                ORDER BY id
                """,
            parameters: [identity.name]
        ) { cursor in
            RetainedSubscriptionEpoch(
                localParametersJSON: try cursor.getString(index: 0),
                coreLastSyncedAt: try cursor.getInt64(index: 1)
            )
        }
        let expectedParameters = identity.parameters.map(JsonValue.object) ?? .null
        let exact = try rows.compactMap { row -> TimeInterval? in
            let decoded = try JSONDecoder().decode(
                JsonValue.self, from: Data(row.localParametersJSON.utf8)
            )
            guard decoded == expectedParameters else { return nil }
            return try Self.validatedCoreEpoch(row.coreLastSyncedAt)
        }
        guard exact.count <= 1 else {
            throw SpaceAssignmentDestinationPowerSyncFailure.malformedScopeEvidence
        }
        return exact.first
    }

    private static func validatedCoreEpoch(_ epoch: Int64) throws -> TimeInterval {
        let decoded = TimeInterval(epoch) / 1_000_000
        guard let validated = try validatedEpoch(decoded) else {
            throw SpaceAssignmentDestinationPowerSyncFailure.malformedScopeEvidence
        }
        return validated
    }

    private static func validatedEpoch(_ epoch: TimeInterval?) throws -> TimeInterval? {
        guard let epoch else { return nil }
        guard epoch.isFinite, epoch > 0 else {
            throw SpaceAssignmentDestinationPowerSyncFailure.malformedScopeEvidence
        }
        return epoch
    }

    private struct RetainedSubscriptionEpoch: Sendable {
        let localParametersJSON: String
        let coreLastSyncedAt: Int64
    }
}

struct SpaceAssignmentDestinationSyncStreamIdentity: Equatable, Sendable, SyncStreamDescription {
    let name: String
    let parameters: JsonParam?

    init(accountId: AccountID, scope: ItemPlacementScope) {
        switch scope {
        case .project(let projectId):
            name = "space_assignment_project_destinations"
            parameters = ["project_id": .string(projectId.rawValue)]
        case .businessInventory:
            name = "space_assignment_business_inventory_destinations"
            parameters = ["account_id": .string(accountId.rawValue)]
        }
    }
}

final class SpaceAssignmentDestinationPowerSyncQuery:
    SpaceAssignmentDestinationQuerying, @unchecked Sendable
{
    private let localReader: any SpaceAssignmentDestinationLocalReading
    private let syncSource: any SpaceAssignmentDestinationSyncSubscribing
    private let principalId: PrincipalID
    private let boundAccountId: AccountID
    private let now: @Sendable () -> Date
    private let registry = SpaceAssignmentDestinationWatchRegistry()

    convenience init(
        database: any PowerSyncDatabaseProtocol,
        principalId: PrincipalID,
        accountId: AccountID,
        now: @Sendable @escaping () -> Date = Date.init
    ) {
        self.init(
            localReader: PowerSyncSpaceAssignmentDestinationLocalReader(database: database),
            syncSource: PowerSyncSpaceAssignmentDestinationSyncSource(database: database),
            principalId: principalId, accountId: accountId, now: now
        )
    }

    init(
        localReader: any SpaceAssignmentDestinationLocalReading,
        syncSource: any SpaceAssignmentDestinationSyncSubscribing,
        principalId: PrincipalID,
        accountId: AccountID,
        now: @Sendable @escaping () -> Date = Date.init
    ) {
        self.localReader = localReader
        self.syncSource = syncSource
        self.principalId = principalId
        boundAccountId = accountId
        self.now = now
    }

    func watchEligibleDestinations(
        _ request: SpaceAssignmentDestinationRequest
    ) -> AsyncThrowingStream<SpaceAssignmentDestinationDirectorySnapshot, Error> {
        guard request.accountId == boundAccountId else {
            return AsyncThrowingStream { $0.finish(
                throwing: SpaceAssignmentDestinationFailure.accountScopeMismatch
            ) }
        }
        return AsyncThrowingStream { continuation in
            let id = UUID()
            let handle = SpaceAssignmentDestinationWatchTaskHandle()
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

    enum Event: Sendable {
        case rowsInvalidated([SpaceAssignmentDestinationPowerSyncRow])
        case subscriptionStarted
        case currentProcessSync(epoch: TimeInterval)
    }

    private func runWatch(
        request: SpaceAssignmentDestinationRequest,
        continuation: AsyncThrowingStream<SpaceAssignmentDestinationDirectorySnapshot, Error>.Continuation
    ) async {
        let events = AsyncThrowingStream<Event, Error>.makeStream()
        let databaseTask = Task {
            do {
                for try await rows in try localReader.watchRows(
                    request: request, principalId: principalId
                ) {
                    try Task.checkCancellation()
                    events.continuation.yield(.rowsInvalidated(rows))
                }
                events.continuation.finish()
            } catch is CancellationError {
                events.continuation.finish()
            } catch { events.continuation.finish(throwing: error) }
        }
        let subscriptionTask = Task {
            do {
                let subscription = try await syncSource.subscribe(
                    accountId: request.accountId, scope: request.scope
                )
                events.continuation.yield(.subscriptionStarted)
                let freshness = SpaceAssignmentDestinationFreshnessTracker(
                    baselineLastSyncedAt: subscription.baselineLastSyncedAt
                )
                do {
                    if subscription.baselineLastSyncedAt == nil {
                        try await subscription.waitForFirstSync()
                        try Task.checkCancellation()
                        guard let causalStatus = subscription.currentStatus() else {
                            throw SpaceAssignmentDestinationPowerSyncFailure.malformedScopeEvidence
                        }
                        if let epoch = try await freshness.establishCausalFirstSync(causalStatus) {
                            events.continuation.yield(.currentProcessSync(epoch: epoch))
                        }
                    }
                    try await subscription.observeStatus { status in
                        if let epoch = await freshness.accept(status) {
                            events.continuation.yield(.currentProcessSync(epoch: epoch))
                        }
                    }
                } catch is CancellationError {
                    // The directly awaited status loop is cancellation-responsive.
                } catch {
                    events.continuation.finish(throwing: error)
                }
                try? await subscription.unsubscribe()
            } catch is CancellationError {
                events.continuation.finish()
            } catch { events.continuation.finish(throwing: error) }
        }

        do {
            var state = SpaceAssignmentDestinationObservedState()
            for try await event in events.stream {
                try Task.checkCancellation()
                let evidence: SpaceAssignmentDestinationCombinedEvidence?
                switch event {
                case .rowsInvalidated(let observedRows):
                    let observedActive = try Self.validateScope(observedRows)
                    _ = try makeDirectory(
                        request: request,
                        evidence: .init(
                            rows: observedRows,
                            currentProcessSyncEpoch: nil
                        )
                    )
                    if !observedActive { state.resetCompleteness() }
                    let freshRows = try await localReader.readRows(
                        request: request, principalId: principalId
                    )
                    evidence = state.observeRows(freshRows)
                case .subscriptionStarted:
                    evidence = state.observeSubscriptionStarted()
                case .currentProcessSync(let epoch):
                    let freshRows = try await localReader.readRows(
                        request: request, principalId: principalId
                    )
                    evidence = state.observeCurrentProcessSync(
                        epoch: epoch, freshRows: freshRows
                    )
                }
                guard let evidence else { continue }
                continuation.yield(try makeDirectory(request: request, evidence: evidence))
            }
            continuation.finish()
        } catch is CancellationError {
            continuation.finish()
        } catch let failure as SpaceAssignmentDestinationFailure {
            continuation.finish(throwing: failure)
        } catch {
            continuation.finish(throwing: SpaceAssignmentDestinationFailure.localReadFailed)
        }
        databaseTask.cancel()
        subscriptionTask.cancel()
        _ = await databaseTask.result
        _ = await subscriptionTask.result
        events.continuation.finish()
    }

    private func makeDirectory(
        request: SpaceAssignmentDestinationRequest,
        evidence: SpaceAssignmentDestinationCombinedEvidence
    ) throws -> SpaceAssignmentDestinationDirectorySnapshot {
        let active = try Self.validateScope(evidence.rows)
        let count = evidence.rows.filter { $0.id != nil }.count
        guard evidence.rows.allSatisfy({ $0.visibleCount == Int64(count) }) else {
            throw SpaceAssignmentDestinationFailure.visibleCountMismatch
        }
        let rows = try evidence.rows.compactMap { try $0.destination() }
        let complete = active && evidence.currentProcessSyncEpoch != nil
        let quality: ListSnapshotQuality = !active ? .partial
            : complete ? .ready : localReader.hasLastSyncedAt ? .stale : .partial
        let provisional = try SpaceAssignmentDestinationDirectorySnapshot(
            request: request,
            local: ListLocalSnapshot(
                queryFingerprint: request.queryFingerprint,
                rows: rows,
                visibleRowCountBeforeFiltering: count,
                isCompleteForQuery: complete,
                quality: quality,
                localDataVersion: LocalDataVersion(validating: "space-destination-provisional"),
                asOf: now()
            )
        )
        let version = try Self.localDataVersion(
            request: request, active: active,
            currentProcessSyncEpoch: evidence.currentProcessSyncEpoch,
            complete: complete, quality: quality, rows: provisional.local.rows
        )
        return try SpaceAssignmentDestinationDirectorySnapshot(
            request: request,
            local: ListLocalSnapshot(
                queryFingerprint: request.queryFingerprint,
                rows: provisional.local.rows,
                visibleRowCountBeforeFiltering: count,
                isCompleteForQuery: complete,
                quality: quality,
                localDataVersion: version,
                asOf: provisional.local.asOf
            )
        )
    }

    private static func validateScope(
        _ rows: [SpaceAssignmentDestinationPowerSyncRow]
    ) throws -> Bool {
        guard let first = rows.first,
              rows.allSatisfy({ $0.scopeRawValue == first.scopeRawValue }),
              first.scopeRawValue == 0 || first.scopeRawValue == 1 else {
            throw SpaceAssignmentDestinationPowerSyncFailure.malformedScopeEvidence
        }
        let active = first.scopeRawValue == 1
        let sentinels = rows.filter { $0.id == nil }
        guard sentinels.allSatisfy(\.isExactSentinel),
              sentinels.count == (rows.count == 1 && rows[0].id == nil ? 1 : 0),
              active || sentinels.count == 1 else {
            throw SpaceAssignmentDestinationPowerSyncFailure.malformedScopeEvidence
        }
        return active
    }

    private static func localDataVersion(
        request: SpaceAssignmentDestinationRequest,
        active: Bool,
        currentProcessSyncEpoch: TimeInterval?,
        complete: Bool,
        quality: ListSnapshotQuality,
        rows: [SpaceAssignmentDestinationSnapshot]
    ) throws -> LocalDataVersion {
        let basis = VersionBasis(request: request, active: active,
                                 currentProcessSyncEpoch: currentProcessSyncEpoch,
                                 complete: complete, quality: quality, rows: rows)
        let digest = SHA256.hash(data: try OperationContractCodec.encode(basis))
            .map { String(format: "%02x", $0) }.joined()
        return try LocalDataVersion(validating: "space-destination-\(digest)")
    }

    private struct VersionBasis: Codable {
        let request: SpaceAssignmentDestinationRequest
        let active: Bool
        let currentProcessSyncEpoch: TimeInterval?
        let complete: Bool
        let quality: ListSnapshotQuality
        let rows: [SpaceAssignmentDestinationSnapshot]
    }
}

private actor SpaceAssignmentDestinationFreshnessTracker {
    private enum Mode {
        case reliable(lastAcceptedOrBaseline: TimeInterval?)
        case unreliable
        case causal(firstSyncEpoch: TimeInterval, lastAccepted: TimeInterval?)
    }

    private var mode: Mode

    init(baselineLastSyncedAt: TimeInterval?) {
        if baselineLastSyncedAt.map(Self.isValidEpoch) ?? false {
            mode = .reliable(lastAcceptedOrBaseline: baselineLastSyncedAt)
        } else {
            mode = .unreliable
        }
    }

    func establishCausalFirstSync(
        _ status: SpaceAssignmentDestinationSyncStreamStatus
    ) throws -> TimeInterval? {
        guard let epoch = status.lastSyncedAt, Self.isValidEpoch(epoch) else {
            throw SpaceAssignmentDestinationPowerSyncFailure.malformedScopeEvidence
        }
        mode = .causal(firstSyncEpoch: epoch, lastAccepted: nil)
        return accept(status)
    }

    func accept(_ status: SpaceAssignmentDestinationSyncStreamStatus) -> TimeInterval? {
        guard status.connected,
              status.active,
              status.hasExplicitSubscription else { return nil }
        if let epoch = status.lastSyncedAt, !Self.isValidEpoch(epoch) { return nil }

        switch mode {
        case .reliable(let baseline):
            guard let epoch = status.lastSyncedAt,
                  baseline.map({ epoch > $0 }) ?? true else { return nil }
            mode = .reliable(lastAcceptedOrBaseline: epoch)
            return epoch
        case .unreliable:
            mode = .reliable(lastAcceptedOrBaseline: status.lastSyncedAt)
            return nil
        case .causal(let firstSyncEpoch, let lastAccepted):
            guard let epoch = status.lastSyncedAt,
                  epoch >= firstSyncEpoch,
                  lastAccepted.map({ epoch > $0 }) ?? true else { return nil }
            mode = .causal(firstSyncEpoch: firstSyncEpoch, lastAccepted: epoch)
            return epoch
        }
    }

    private static func isValidEpoch(_ epoch: TimeInterval) -> Bool {
        epoch.isFinite && epoch > 0
    }
}

struct SpaceAssignmentDestinationCombinedEvidence: Equatable, Sendable {
    let rows: [SpaceAssignmentDestinationPowerSyncRow]
    let currentProcessSyncEpoch: TimeInterval?
}

struct SpaceAssignmentDestinationObservedState: Sendable {
    private var rows: [SpaceAssignmentDestinationPowerSyncRow]?
    private var subscriptionStarted = false
    private var currentProcessSyncEpoch: TimeInterval?
    mutating func resetCompleteness() { currentProcessSyncEpoch = nil }
    mutating func observeRows(
        _ value: [SpaceAssignmentDestinationPowerSyncRow]
    ) -> SpaceAssignmentDestinationCombinedEvidence? {
        rows = value
        if value.first?.scopeRawValue != 1 {
            currentProcessSyncEpoch = nil
        }
        return evidence
    }

    mutating func observeSubscriptionStarted()
        -> SpaceAssignmentDestinationCombinedEvidence?
    {
        subscriptionStarted = true
        return evidence
    }

    mutating func observeCurrentProcessSync(
        epoch: TimeInterval,
        freshRows: [SpaceAssignmentDestinationPowerSyncRow]
    ) -> SpaceAssignmentDestinationCombinedEvidence? {
        subscriptionStarted = true
        rows = freshRows
        currentProcessSyncEpoch = freshRows.first?.scopeRawValue == 1 ? epoch : nil
        return evidence
    }

    private var evidence: SpaceAssignmentDestinationCombinedEvidence? {
        guard let rows, subscriptionStarted else { return nil }
        return .init(rows: rows, currentProcessSyncEpoch: currentProcessSyncEpoch)
    }
}

private final class SpaceAssignmentDestinationWatchTaskHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var cancellationRequested = false
    func install(_ task: Task<Void, Never>) {
        let cancel = lock.withLock { self.task = task; return cancellationRequested }
        if cancel { task.cancel() }
    }
    func cancel() {
        let task = lock.withLock { cancellationRequested = true; return self.task }
        task?.cancel()
    }
}

private actor SpaceAssignmentDestinationWatchRegistry {
    private var handles: [UUID: SpaceAssignmentDestinationWatchTaskHandle] = [:]
    private var closing = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func register(id: UUID, handle: SpaceAssignmentDestinationWatchTaskHandle) -> Bool {
        guard !closing else { handle.cancel(); return false }
        handles[id] = handle
        return true
    }
    func finished(id: UUID) {
        handles.removeValue(forKey: id)
        guard handles.isEmpty else { return }
        let current = waiters; waiters.removeAll()
        current.forEach { $0.resume() }
    }
    func cancelAndDrain() async {
        closing = true
        handles.values.forEach { $0.cancel() }
        guard !handles.isEmpty else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

struct SpaceAssignmentDestinationPowerSyncRow: Equatable, Sendable {
    let scopeRawValue: Int64
    let visibleCount: Int64
    let id: String?
    let accountId: String?
    let scopeKind: String?
    let projectId: String?
    let displayName: String?
    let lifecycle: String?
    let revision: Int64?

    init(scopeRawValue: Int64, visibleCount: Int64, id: String?, accountId: String?,
         scopeKind: String?, projectId: String?, displayName: String?,
         lifecycle: String?, revision: Int64?) {
        self.scopeRawValue = scopeRawValue; self.visibleCount = visibleCount
        self.id = id; self.accountId = accountId; self.scopeKind = scopeKind
        self.projectId = projectId; self.displayName = displayName
        self.lifecycle = lifecycle; self.revision = revision
    }

    init(cursor: any SqlCursor) throws {
        scopeRawValue = try cursor.getInt64(name: "is_active")
        visibleCount = try cursor.getInt64(name: "visible_count")
        id = try cursor.getStringOptional(name: "id")
        accountId = try cursor.getStringOptional(name: "account_id")
        scopeKind = try cursor.getStringOptional(name: "scope_kind")
        projectId = try cursor.getStringOptional(name: "project_id")
        displayName = try cursor.getStringOptional(name: "display_name")
        lifecycle = try cursor.getStringOptional(name: "lifecycle")
        revision = try cursor.getInt64Optional(name: "revision")
    }

    var isExactSentinel: Bool {
        visibleCount == 0 && id == nil && accountId == nil && scopeKind == nil
            && projectId == nil && displayName == nil && lifecycle == nil && revision == nil
    }

    func destination() throws -> SpaceAssignmentDestinationSnapshot? {
        guard let id else {
            guard isExactSentinel else {
                throw SpaceAssignmentDestinationPowerSyncFailure.malformedDestinationRow
            }
            return nil
        }
        guard let accountId, let scopeKind, let displayName,
              let rawLifecycle = lifecycle,
              let lifecycle = DirectoryLifecycleState(rawValue: rawLifecycle),
              let revision, revision > 0 else {
            throw SpaceAssignmentDestinationPowerSyncFailure.malformedDestinationRow
        }
        let scope: ItemPlacementScope
        switch scopeKind {
        case "project":
            guard let projectId else {
                throw SpaceAssignmentDestinationPowerSyncFailure.malformedDestinationRow
            }
            scope = .project(try ProjectID(validating: projectId))
        case "business_inventory":
            guard projectId == nil else {
                throw SpaceAssignmentDestinationPowerSyncFailure.malformedDestinationRow
            }
            scope = .businessInventory
        default: throw SpaceAssignmentDestinationPowerSyncFailure.malformedDestinationRow
        }
        let canonicalName: SpaceDisplayName
        do {
            canonicalName = try SpaceDisplayName(validating: displayName)
        } catch {
            throw SpaceAssignmentDestinationPowerSyncFailure.malformedDestinationRow
        }
        guard canonicalName.rawValue.utf8.elementsEqual(displayName.utf8) else {
            throw SpaceAssignmentDestinationPowerSyncFailure.malformedDestinationRow
        }
        return try SpaceAssignmentDestinationSnapshot(
            id: SpaceID(validating: id), accountId: AccountID(validating: accountId),
            scope: scope, displayName: canonicalName,
            lifecycle: lifecycle, revision: UInt64(revision)
        )
    }
}
