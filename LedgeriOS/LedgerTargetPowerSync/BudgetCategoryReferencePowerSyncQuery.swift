import CryptoKit
import Foundation
import LedgerTargetCore
import PowerSync

enum BudgetCategoryReferencePowerSyncFailure: Error, Equatable, Sendable {
    case malformedScopeEvidence
    case malformedCategoryRow
}

protocol BudgetCategoryReferenceLocalReading: Sendable {
    var hasLastSyncedAt: Bool { get }

    func watchRows(
        accountId: AccountID,
        principalId: PrincipalID
    ) throws -> AsyncThrowingStream<[BudgetCategoryPowerSyncRow], Error>
}

private final class PowerSyncBudgetCategoryReferenceLocalReader:
    BudgetCategoryReferenceLocalReading, @unchecked Sendable
{
    private let database: any PowerSyncDatabaseProtocol

    init(database: any PowerSyncDatabaseProtocol) {
        self.database = database
    }

    var hasLastSyncedAt: Bool {
        database.currentStatus.lastSyncedAt != nil
    }

    func watchRows(
        accountId: AccountID,
        principalId: PrincipalID
    ) throws -> AsyncThrowingStream<[BudgetCategoryPowerSyncRow], Error> {
        try database.watch(
            sql: Self.categorySQL,
            parameters: [
                accountId.rawValue,
                principalId.rawValue,
                accountId.rawValue,
            ]
        ) { cursor in
            try BudgetCategoryPowerSyncRow(cursor: cursor)
        }
    }

    private static let categorySQL = """
        WITH scope AS (
          SELECT EXISTS (
            SELECT 1
            FROM spike_account_memberships
            WHERE account_id = ? AND principal_id = ? AND state = 'active'
          ) AS is_active
        )
        SELECT scope.is_active,
               category.id,
               category.account_id,
               category.display_name,
               category.kind,
               category.lifecycle,
               category.is_system,
               category.excludes_from_overall_budget,
               category.presentation_order,
               category.revision
        FROM scope
        LEFT JOIN spike_budget_categories AS category
          ON scope.is_active AND category.account_id = ?
        ORDER BY category.presentation_order, category.id
        """
}

final class BudgetCategoryReferencePowerSyncQuery:
    BudgetCategoryReferenceQuerying, @unchecked Sendable
{
    typealias CompletenessObservation = @Sendable (AccountID) -> AsyncStream<Bool>

    private let localReader: any BudgetCategoryReferenceLocalReading
    private let principalId: PrincipalID
    private let boundAccountId: AccountID
    private let completenessObservation: CompletenessObservation
    private let now: @Sendable () -> Date
    private let watchRegistry = BudgetCategoryReferenceWatchRegistry()

    convenience init(
        database: any PowerSyncDatabaseProtocol,
        principalId: PrincipalID,
        accountId: AccountID,
        completenessObservation: @escaping CompletenessObservation = { _ in
            AsyncStream { continuation in
                continuation.yield(false)
                continuation.finish()
            }
        },
        now: @Sendable @escaping () -> Date = Date.init
    ) {
        self.init(
            localReader: PowerSyncBudgetCategoryReferenceLocalReader(database: database),
            principalId: principalId,
            accountId: accountId,
            completenessObservation: completenessObservation,
            now: now
        )
    }

    init(
        localReader: any BudgetCategoryReferenceLocalReading,
        principalId: PrincipalID,
        accountId: AccountID,
        completenessObservation: @escaping CompletenessObservation = { _ in
            AsyncStream { continuation in
                continuation.yield(false)
                continuation.finish()
            }
        },
        now: @Sendable @escaping () -> Date = Date.init
    ) {
        self.localReader = localReader
        self.principalId = principalId
        boundAccountId = accountId
        self.completenessObservation = completenessObservation
        self.now = now
    }

    func watchBudgetCategories(
        accountId: AccountID
    ) -> AsyncThrowingStream<BudgetCategoryReferenceSnapshot, Error> {
        guard accountId == boundAccountId else {
            return Self.failedStream(BudgetCategoryReferenceFailure.accountScopeMismatch)
        }

        return AsyncThrowingStream { continuation in
            let watchId = UUID()
            let handle = BudgetCategoryReferenceWatchTaskHandle()
            let registration = Task {
                await watchRegistry.register(id: watchId, handle: handle)
            }
            let task = Task {
                let admitted = await registration.value
                guard admitted, !Task.isCancelled else {
                    continuation.finish()
                    if admitted { await watchRegistry.finished(id: watchId) }
                    return
                }
                await runWatch(accountId: accountId, continuation: continuation)
                await watchRegistry.finished(id: watchId)
            }
            handle.install(task)
            continuation.onTermination = { _ in handle.cancel() }
        }
    }

    func cancelAndDrainWatches() async {
        await watchRegistry.cancelAndDrain()
    }

    private enum Event: Sendable {
        case rows([BudgetCategoryPowerSyncRow])
        case completeness(Bool)
    }

    private func runWatch(
        accountId: AccountID,
        continuation: AsyncThrowingStream<BudgetCategoryReferenceSnapshot, Error>.Continuation
    ) async {
        let eventChannel = AsyncThrowingStream<Event, Error>.makeStream()
        let databaseTask = Task {
            do {
                let updates = try localReader.watchRows(
                    accountId: accountId,
                    principalId: principalId
                )
                for try await rows in updates {
                    try Task.checkCancellation()
                    eventChannel.continuation.yield(.rows(rows))
                }
                eventChannel.continuation.finish()
            } catch is CancellationError {
                eventChannel.continuation.finish()
            } catch {
                eventChannel.continuation.finish(throwing: error)
            }
        }
        let completenessTask = Task {
            for await isComplete in completenessObservation(accountId) {
                guard !Task.isCancelled else { return }
                eventChannel.continuation.yield(.completeness(isComplete))
            }
        }

        do {
            var latestRows: [BudgetCategoryPowerSyncRow]?
            var completenessIsObserved = false

            for try await event in eventChannel.stream {
                try Task.checkCancellation()
                switch event {
                case .rows(let rows):
                    latestRows = rows
                case .completeness(let isComplete):
                    completenessIsObserved = isComplete
                }
                guard let observedRows = latestRows else { continue }

                let scopeIsActive = try Self.validateScope(rows: observedRows)
                let definitions = try observedRows.compactMap {
                    try $0.definition(boundAccountId: accountId)
                }
                let canonicalDefinitions = definitions.sorted(by: Self.canonicalOrder)
                let isComplete = scopeIsActive && completenessIsObserved
                let quality = Self.quality(
                    scopeIsActive: scopeIsActive,
                    isComplete: isComplete,
                    hasLastSyncedAt: localReader.hasLastSyncedAt
                )
                let local = try ListLocalSnapshot(
                    queryFingerprint: try Self.queryFingerprint(accountId: accountId),
                    rows: canonicalDefinitions,
                    visibleRowCountBeforeFiltering: canonicalDefinitions.count,
                    isCompleteForQuery: isComplete,
                    quality: quality,
                    localDataVersion: try Self.localDataVersion(
                        accountId: accountId,
                        scopeIsActive: scopeIsActive,
                        completenessIsObserved: completenessIsObserved,
                        isComplete: isComplete,
                        quality: quality,
                        rows: canonicalDefinitions
                    ),
                    asOf: now()
                )
                continuation.yield(
                    try BudgetCategoryReferenceSnapshot(accountId: accountId, local: local)
                )
            }
            continuation.finish()
        } catch is CancellationError {
            continuation.finish()
        } catch let failure as BudgetCategoryReferenceFailure {
            continuation.finish(throwing: failure)
        } catch {
            continuation.finish(throwing: BudgetCategoryReferenceFailure.localReadFailed)
        }

        databaseTask.cancel()
        completenessTask.cancel()
        _ = await databaseTask.result
        _ = await completenessTask.result
        eventChannel.continuation.finish()
    }

    private static func validateScope(rows: [BudgetCategoryPowerSyncRow]) throws -> Bool {
        guard let first = rows.first,
              rows.allSatisfy({ $0.scopeRawValue == first.scopeRawValue }),
              first.scopeRawValue == 0 || first.scopeRawValue == 1 else {
            throw BudgetCategoryReferencePowerSyncFailure.malformedScopeEvidence
        }
        let scopeIsActive = first.scopeRawValue == 1
        let sentinelRows = rows.filter { $0.id == nil }
        guard sentinelRows.allSatisfy(\.isExactSentinel),
              sentinelRows.count == (rows.count == 1 && rows[0].id == nil ? 1 : 0),
              scopeIsActive || sentinelRows.count == 1 else {
            throw BudgetCategoryReferencePowerSyncFailure.malformedScopeEvidence
        }
        return scopeIsActive
    }

    private static func canonicalOrder(
        _ lhs: BudgetCategoryDefinitionSnapshot,
        _ rhs: BudgetCategoryDefinitionSnapshot
    ) -> Bool {
        if lhs.presentationOrder != rhs.presentationOrder {
            return lhs.presentationOrder < rhs.presentationOrder
        }
        return lhs.id.rawValue < rhs.id.rawValue
    }

    private static func quality(
        scopeIsActive: Bool,
        isComplete: Bool,
        hasLastSyncedAt: Bool
    ) -> ListSnapshotQuality {
        guard scopeIsActive else { return .partial }
        if isComplete { return .ready }
        return hasLastSyncedAt ? .stale : .partial
    }

    private static func queryFingerprint(
        accountId: AccountID
    ) throws -> ListQueryFingerprint {
        try ListQueryFingerprint(
            validating: sha256(
                Data("budget-category-reference-query-v1|\(accountId.rawValue)".utf8)
            )
        )
    }

    private static func localDataVersion(
        accountId: AccountID,
        scopeIsActive: Bool,
        completenessIsObserved: Bool,
        isComplete: Bool,
        quality: ListSnapshotQuality,
        rows: [BudgetCategoryDefinitionSnapshot]
    ) throws -> LocalDataVersion {
        let basis = LocalVersionBasis(
            contractVersion: "budget-category-reference-local-v1",
            accountId: accountId,
            scopeIsActive: scopeIsActive,
            completenessIsObserved: completenessIsObserved,
            isComplete: isComplete,
            quality: quality,
            rows: rows
        )
        return try LocalDataVersion(
            validating: "budget-category-\(sha256(try OperationContractCodec.encode(basis)))"
        )
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func failedStream<Value: Sendable>(
        _ error: Error
    ) -> AsyncThrowingStream<Value, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }

    private struct LocalVersionBasis: Codable {
        let contractVersion: String
        let accountId: AccountID
        let scopeIsActive: Bool
        let completenessIsObserved: Bool
        let isComplete: Bool
        let quality: ListSnapshotQuality
        let rows: [BudgetCategoryDefinitionSnapshot]
    }

}

private final class BudgetCategoryReferenceWatchTaskHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var cancellationRequested = false

    func install(_ task: Task<Void, Never>) {
        let shouldCancel = lock.withLock {
            self.task = task
            return cancellationRequested
        }
        if shouldCancel { task.cancel() }
    }

    func cancel() {
        let installedTask = lock.withLock {
            cancellationRequested = true
            return task
        }
        installedTask?.cancel()
    }
}

private actor BudgetCategoryReferenceWatchRegistry {
    private var handles: [UUID: BudgetCategoryReferenceWatchTaskHandle] = [:]
    private var isClosing = false
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    func register(
        id: UUID,
        handle: BudgetCategoryReferenceWatchTaskHandle
    ) -> Bool {
        guard !isClosing else {
            handle.cancel()
            return false
        }
        handles[id] = handle
        return true
    }

    func finished(id: UUID) {
        handles.removeValue(forKey: id)
        guard handles.isEmpty else { return }
        let waiters = drainWaiters
        drainWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
    }

    func cancelAndDrain() async {
        isClosing = true
        for handle in handles.values { handle.cancel() }
        guard !handles.isEmpty else { return }
        await withCheckedContinuation { drainWaiters.append($0) }
    }
}

struct BudgetCategoryPowerSyncRow: Equatable, Sendable {
    let scopeRawValue: Int64
    let id: String?
    let accountId: String?
    let displayName: String?
    let kind: String?
    let lifecycle: String?
    let isSystem: Int64?
    let excludesFromOverallBudget: Int64?
    let presentationOrder: Int64?
    let revision: Int64?

    init(
        scopeRawValue: Int64,
        id: String?,
        accountId: String?,
        displayName: String?,
        kind: String?,
        lifecycle: String?,
        isSystem: Int64?,
        excludesFromOverallBudget: Int64?,
        presentationOrder: Int64?,
        revision: Int64?
    ) {
        self.scopeRawValue = scopeRawValue
        self.id = id
        self.accountId = accountId
        self.displayName = displayName
        self.kind = kind
        self.lifecycle = lifecycle
        self.isSystem = isSystem
        self.excludesFromOverallBudget = excludesFromOverallBudget
        self.presentationOrder = presentationOrder
        self.revision = revision
    }

    init(cursor: any SqlCursor) throws {
        scopeRawValue = try cursor.getInt64(name: "is_active")
        id = try cursor.getStringOptional(name: "id")
        accountId = try cursor.getStringOptional(name: "account_id")
        displayName = try cursor.getStringOptional(name: "display_name")
        kind = try cursor.getStringOptional(name: "kind")
        lifecycle = try cursor.getStringOptional(name: "lifecycle")
        isSystem = try cursor.getInt64Optional(name: "is_system")
        excludesFromOverallBudget = try cursor.getInt64Optional(
            name: "excludes_from_overall_budget"
        )
        presentationOrder = try cursor.getInt64Optional(name: "presentation_order")
        revision = try cursor.getInt64Optional(name: "revision")
    }

    var isExactSentinel: Bool {
        id == nil
            && accountId == nil
            && displayName == nil
            && kind == nil
            && lifecycle == nil
            && isSystem == nil
            && excludesFromOverallBudget == nil
            && presentationOrder == nil
            && revision == nil
    }

    func definition(
        boundAccountId: AccountID
    ) throws -> BudgetCategoryDefinitionSnapshot? {
        guard let id else {
            guard isExactSentinel else {
                throw BudgetCategoryReferencePowerSyncFailure.malformedCategoryRow
            }
            return nil
        }
        guard let accountId,
              accountId == boundAccountId.rawValue,
              let displayName,
              let rawKind = kind,
              let kind = BudgetCategoryKind(rawValue: rawKind),
              let rawLifecycle = lifecycle,
              let lifecycle = DirectoryLifecycleState(rawValue: rawLifecycle),
              let isSystem,
              isSystem == 0 || isSystem == 1,
              let excludesFromOverallBudget,
              excludesFromOverallBudget == 0 || excludesFromOverallBudget == 1,
              let presentationOrder,
              presentationOrder >= 0,
              presentationOrder <= Int64(UInt32.max),
              let revision,
              revision > 0 else {
            throw BudgetCategoryReferencePowerSyncFailure.malformedCategoryRow
        }
        return try BudgetCategoryDefinitionSnapshot(
            id: BudgetCategoryID(validating: id),
            accountId: AccountID(validating: accountId),
            name: BudgetCategoryName(validating: displayName),
            kind: kind,
            lifecycle: lifecycle,
            isSystem: isSystem == 1,
            excludesFromOverallBudget: excludesFromOverallBudget == 1,
            presentationOrder: UInt32(presentationOrder),
            revision: UInt64(revision)
        )
    }
}
