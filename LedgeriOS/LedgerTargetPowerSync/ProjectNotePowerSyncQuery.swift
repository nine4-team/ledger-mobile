import CryptoKit
import Foundation
import LedgerTargetCore
import PowerSync

enum ProjectNotePowerSyncFailure: Error, Equatable, Sendable {
    case malformedScopeEvidence
    case malformedNoteRow
    case rowLimitExceeded
}

protocol ProjectNoteLocalReading: Sendable {
    var hasLastSyncedAt: Bool { get }

    func readRows(
        request: ProjectNotePageRequest,
        principalId: PrincipalID,
        fetchLimit: Int
    ) async throws -> [ProjectNotePowerSyncRow]

    func watchRows(
        request: ProjectNotePageRequest,
        principalId: PrincipalID,
        fetchLimit: Int
    ) throws -> AsyncThrowingStream<[ProjectNotePowerSyncRow], Error>
}

private final class PowerSyncProjectNoteLocalReader:
    ProjectNoteLocalReading, @unchecked Sendable
{
    private let database: any PowerSyncDatabaseProtocol

    init(database: any PowerSyncDatabaseProtocol) {
        self.database = database
    }

    var hasLastSyncedAt: Bool {
        database.currentStatus.lastSyncedAt != nil
    }

    func readRows(
        request: ProjectNotePageRequest,
        principalId: PrincipalID,
        fetchLimit: Int
    ) async throws -> [ProjectNotePowerSyncRow] {
        let query = try Self.query(
            request: request,
            principalId: principalId,
            fetchLimit: fetchLimit
        )
        return try await database.getAll(
            sql: query.sql,
            parameters: query.parameters
        ) { cursor in
            try ProjectNotePowerSyncRow(cursor: cursor)
        }
    }

    func watchRows(
        request: ProjectNotePageRequest,
        principalId: PrincipalID,
        fetchLimit: Int
    ) throws -> AsyncThrowingStream<[ProjectNotePowerSyncRow], Error> {
        let query = try Self.query(
            request: request,
            principalId: principalId,
            fetchLimit: fetchLimit
        )
        return try database.watch(
            sql: query.sql,
            parameters: query.parameters
        ) { cursor in
            try ProjectNotePowerSyncRow(cursor: cursor)
        }
    }

    private static func query(
        request: ProjectNotePageRequest,
        principalId: PrincipalID,
        fetchLimit: Int
    ) throws -> (sql: String, parameters: [any Sendable]) {
        var parameters: [any Sendable] = [
            request.accountId.rawValue,
            principalId.rawValue,
            request.accountId.rawValue,
            request.projectId.rawValue,
            request.accountId.rawValue,
            request.projectId.rawValue,
        ]
        let cursorPredicate: String
        if let cursor = request.after {
            let milliseconds = try Self.exactMilliseconds(cursor.createdAt)
            cursorPredicate = """
                AND (
                  note.created_at_ms < ?
                  OR (note.created_at_ms = ? AND note.keyset_id < ?)
                )
                """
            parameters.append(milliseconds)
            parameters.append(milliseconds)
            parameters.append(cursor.noteId.rawValue)
        } else {
            cursorPredicate = ""
        }
        parameters.append(Int64(fetchLimit))
        return (Self.sql(cursorPredicate: cursorPredicate), parameters)
    }

    private static func exactMilliseconds(_ date: Date) throws -> Int64 {
        let raw = date.timeIntervalSince1970 * 1_000
        guard raw.isFinite,
              let milliseconds = Int64(exactly: raw.rounded(.towardZero)),
              Date(timeIntervalSince1970: Double(milliseconds) / 1_000) == date else {
            throw ProjectNoteDataFailure.requestMismatch
        }
        return milliseconds
    }

    private static func sql(cursorPredicate: String) -> String {
        """
        WITH scope AS (
          SELECT EXISTS (
            SELECT 1
            FROM spike_account_memberships
            WHERE account_id = ? AND principal_id = ? AND state = 'active'
          ) AS is_active
        ), parent AS (
          SELECT EXISTS (
            SELECT 1
            FROM spike_projects
            WHERE account_id = ? AND id = ? AND (SELECT is_active FROM scope)
          ) AS is_visible
        )
        SELECT scope.is_active,
               parent.is_visible AS project_is_visible,
               note.id,
               note.account_id,
               note.project_id,
               note.keyset_id,
               note.content_kind,
               note.note_text,
               note.source,
               note.created_by_principal_id,
               note.creator_display_name,
               note.created_at_ms,
               note.revision AS revision_text,
               note.last_edited_by_principal_id,
               note.last_edited_at_ms,
               note.deleted_by_principal_id,
               note.deleted_at_ms
        FROM scope
        CROSS JOIN parent
        LEFT JOIN spike_project_notes AS note
          ON scope.is_active
         AND parent.is_visible
         AND note.account_id = ?
         AND note.project_id = ?
         \(cursorPredicate)
        ORDER BY note.created_at_ms DESC, note.keyset_id DESC
        LIMIT ?
        """
    }
}

struct ProjectNoteSyncStreamIdentity:
    Equatable, Sendable, SyncStreamDescription
{
    let name = "project_note_history"
    let parameters: JsonParam?

    init(accountId: AccountID, projectId: ProjectID) {
        parameters = [
            "account_id": .string(accountId.rawValue),
            "project_id": .string(projectId.rawValue),
        ]
    }
}

private final class PowerSyncProjectNoteFreshnessSource: @unchecked Sendable {
    private let database: any PowerSyncDatabaseProtocol

    init(database: any PowerSyncDatabaseProtocol) {
        self.database = database
    }

    func observe(
        accountId: AccountID,
        projectId: ProjectID,
        receive: @Sendable (ProjectNoteFreshnessEvent) async throws -> Void
    ) async throws {
        let identity = ProjectNoteSyncStreamIdentity(
            accountId: accountId,
            projectId: projectId
        )
        let baseline = try await baselineLastSyncedAt(for: identity)
        let stream = database.syncStream(
            name: identity.name,
            params: identity.parameters
        )
        let subscription = try await stream.subscribe()
        do {
            try await receive(.subscriptionStarted)
            let freshness = ProjectNoteFreshnessTracker(
                baselineLastSyncedAt: baseline
            )

            if baseline == nil {
                try await subscription.waitForFirstSync()
                try Task.checkCancellation()
                guard let status = Self.status(
                    database.currentStatus,
                    stream: subscription
                ) else {
                    throw ProjectNotePowerSyncFailure.malformedScopeEvidence
                }
                if let epoch = try await freshness.establishCausalFirstSync(status) {
                    try await receive(.currentProcessSync(epoch: epoch))
                }
            }

            for await status in database.currentStatus.asFlow() {
                try Task.checkCancellation()
                guard let exact = Self.status(status, stream: subscription) else { continue }
                if let epoch = await freshness.accept(exact) {
                    try await receive(.currentProcessSync(epoch: epoch))
                }
            }
            try Task.checkCancellation()
        } catch {
            try? await subscription.unsubscribe()
            throw error
        }
        try? await subscription.unsubscribe()
    }

    private func baselineLastSyncedAt(
        for identity: ProjectNoteSyncStreamIdentity
    ) async throws -> TimeInterval? {
        var statuses = database.currentStatus.asFlow().makeAsyncIterator()
        var publicEpoch: TimeInterval?
        while let status = await statuses.next() {
            try Task.checkCancellation()
            guard status.syncStreams != nil else { continue }
            publicEpoch = try Self.validatedEpoch(
                status.forStream(stream: identity)?.subscription.lastSyncedAt
            )
            break
        }
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
        let expected = identity.parameters.map(JsonValue.object) ?? .null
        let retained = try rows.compactMap { row -> TimeInterval? in
            let decoded = try JSONDecoder().decode(
                JsonValue.self,
                from: Data(row.localParametersJSON.utf8)
            )
            guard decoded == expected else { return nil }
            return try Self.validatedCoreEpoch(row.coreLastSyncedAt)
        }
        guard retained.count <= 1 else {
            throw ProjectNotePowerSyncFailure.malformedScopeEvidence
        }
        return [publicEpoch, retained.first].compactMap { $0 }.max()
    }

    private static func status(
        _ status: any SyncStatusData,
        stream: any SyncStreamDescription
    ) -> ProjectNoteSyncStreamStatus? {
        guard let exact = status.forStream(stream: stream) else { return nil }
        return ProjectNoteSyncStreamStatus(
            connected: status.connected,
            active: exact.subscription.active,
            hasExplicitSubscription: exact.subscription.hasExplicitSubscription,
            lastSyncedAt: exact.subscription.lastSyncedAt
        )
    }

    private static func validatedCoreEpoch(_ epoch: Int64) throws -> TimeInterval {
        guard let value = try validatedEpoch(TimeInterval(epoch) / 1_000_000) else {
            throw ProjectNotePowerSyncFailure.malformedScopeEvidence
        }
        return value
    }

    private static func validatedEpoch(_ epoch: TimeInterval?) throws -> TimeInterval? {
        guard let epoch else { return nil }
        guard epoch.isFinite, epoch > 0 else {
            throw ProjectNotePowerSyncFailure.malformedScopeEvidence
        }
        return epoch
    }

    private struct RetainedSubscriptionEpoch: Sendable {
        let localParametersJSON: String
        let coreLastSyncedAt: Int64
    }
}

struct ProjectNoteSyncStreamStatus: Equatable, Sendable {
    let connected: Bool
    let active: Bool
    let hasExplicitSubscription: Bool
    let lastSyncedAt: TimeInterval?
}

enum ProjectNoteFreshnessEvent: Equatable, Sendable {
    case subscriptionStarted
    case currentProcessSync(epoch: TimeInterval)
}

actor ProjectNoteFreshnessTracker {
    private enum Mode {
        case reliable(lastAcceptedOrBaseline: TimeInterval?)
        case causal(firstSyncEpoch: TimeInterval, lastAccepted: TimeInterval?)
    }

    private var mode: Mode

    init(baselineLastSyncedAt: TimeInterval?) {
        mode = .reliable(lastAcceptedOrBaseline: baselineLastSyncedAt)
    }

    func establishCausalFirstSync(
        _ status: ProjectNoteSyncStreamStatus
    ) throws -> TimeInterval? {
        guard let epoch = status.lastSyncedAt, Self.isValidEpoch(epoch) else {
            throw ProjectNotePowerSyncFailure.malformedScopeEvidence
        }
        mode = .causal(firstSyncEpoch: epoch, lastAccepted: nil)
        return accept(status)
    }

    func accept(_ status: ProjectNoteSyncStreamStatus) -> TimeInterval? {
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

final class ProjectNotePowerSyncQuery: ProjectNoteQuerying, @unchecked Sendable {
    typealias CompletenessObservation = @Sendable (
        AccountID,
        ProjectID
    ) -> AsyncStream<Bool>

    private typealias FreshnessObservation = @Sendable (
        AccountID,
        ProjectID,
        @escaping @Sendable (ProjectNoteFreshnessEvent) async throws -> Void
    ) async throws -> Void

    private let localReader: any ProjectNoteLocalReading
    private let principalId: PrincipalID
    private let boundAccountId: AccountID
    private let freshnessObservation: FreshnessObservation
    private let now: @Sendable () -> Date
    private let watchRegistry = ProjectNoteWatchRegistry()

    convenience init(
        database: any PowerSyncDatabaseProtocol,
        principalId: PrincipalID,
        accountId: AccountID,
        now: @Sendable @escaping () -> Date = Date.init
    ) {
        let freshness = PowerSyncProjectNoteFreshnessSource(database: database)
        self.init(
            localReader: PowerSyncProjectNoteLocalReader(database: database),
            principalId: principalId,
            accountId: accountId,
            freshnessObservation: { accountId, projectId, receive in
                try await freshness.observe(
                    accountId: accountId,
                    projectId: projectId,
                    receive: receive
                )
            },
            now: now
        )
    }

    convenience init(
        database: any PowerSyncDatabaseProtocol,
        principalId: PrincipalID,
        accountId: AccountID,
        testCompletenessObservation: @escaping CompletenessObservation,
        now: @Sendable @escaping () -> Date = Date.init
    ) {
        self.init(
            localReader: PowerSyncProjectNoteLocalReader(database: database),
            principalId: principalId,
            accountId: accountId,
            completenessObservation: testCompletenessObservation,
            now: now
        )
    }

    convenience init(
        localReader: any ProjectNoteLocalReading,
        principalId: PrincipalID,
        accountId: AccountID,
        completenessObservation: @escaping CompletenessObservation,
        now: @Sendable @escaping () -> Date = Date.init
    ) {
        self.init(
            localReader: localReader,
            principalId: principalId,
            accountId: accountId,
            freshnessObservation: { accountId, projectId, receive in
                let source = completenessObservation(accountId, projectId)
                var syntheticEpoch: TimeInterval = 0
                for await value in source {
                    try Task.checkCancellation()
                    if value {
                        syntheticEpoch += 1
                        try await receive(.currentProcessSync(epoch: syntheticEpoch))
                    } else {
                        try await receive(.subscriptionStarted)
                    }
                }
                try Task.checkCancellation()
            },
            now: now
        )
    }

    private init(
        localReader: any ProjectNoteLocalReading,
        principalId: PrincipalID,
        accountId: AccountID,
        freshnessObservation: @escaping FreshnessObservation,
        now: @Sendable @escaping () -> Date
    ) {
        self.localReader = localReader
        self.principalId = principalId
        boundAccountId = accountId
        self.freshnessObservation = freshnessObservation
        self.now = now
    }

    func watchNotes(
        _ request: ProjectNotePageRequest
    ) -> AsyncThrowingStream<ProjectNotePage, Error> {
        guard request.accountId == boundAccountId else {
            return Self.failedStream(ProjectNoteDataFailure.requestMismatch)
        }

        return AsyncThrowingStream { continuation in
            let watchId = UUID()
            let handle = ProjectNoteWatchTaskHandle()
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
                await runWatch(request: request, continuation: continuation)
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
        case rowsInvalidated([ProjectNotePowerSyncRow])
        case subscriptionStarted
        case currentProcessSync(epoch: TimeInterval)
    }

    private func runWatch(
        request: ProjectNotePageRequest,
        continuation: AsyncThrowingStream<ProjectNotePage, Error>.Continuation
    ) async {
        let eventChannel = AsyncThrowingStream<Event, Error>.makeStream()
        let fetchLimit = Int(request.pageSize) + 1
        let databaseTask = Task {
            do {
                let rows = try localReader.watchRows(
                    request: request,
                    principalId: principalId,
                    fetchLimit: fetchLimit
                )
                for try await update in rows {
                    try Task.checkCancellation()
                    eventChannel.continuation.yield(.rowsInvalidated(update))
                }
                eventChannel.continuation.finish()
            } catch is CancellationError {
                eventChannel.continuation.finish()
            } catch {
                eventChannel.continuation.finish(throwing: error)
            }
        }
        let completenessTask = Task {
            do {
                try await freshnessObservation(
                    request.accountId,
                    request.projectId
                ) { freshness in
                    try Task.checkCancellation()
                    switch freshness {
                    case .subscriptionStarted:
                        eventChannel.continuation.yield(.subscriptionStarted)
                    case .currentProcessSync(let epoch):
                        eventChannel.continuation.yield(.currentProcessSync(epoch: epoch))
                    }
                }
            } catch is CancellationError {
                // The parent watch owns normal cancellation.
            } catch {
                eventChannel.continuation.finish(throwing: error)
            }
        }

        do {
            var latestRows: [ProjectNotePowerSyncRow]?
            var subscriptionWasObserved = false
            var currentProcessSyncEpoch: TimeInterval?
            var lastEmittedPage: ProjectNotePage?

            for try await event in eventChannel.stream {
                try Task.checkCancellation()
                switch event {
                case .rowsInvalidated(let observedRows):
                    let observedScope = try Self.validateScope(observedRows)
                    if !observedScope.isActive {
                        currentProcessSyncEpoch = nil
                    }
                    let freshRows = try await localReader.readRows(
                        request: request,
                        principalId: principalId,
                        fetchLimit: fetchLimit
                    )
                    let freshScope = try Self.validateScope(freshRows)
                    if !freshScope.isActive {
                        currentProcessSyncEpoch = nil
                    }
                    latestRows = freshRows
                case .subscriptionStarted:
                    subscriptionWasObserved = true
                    currentProcessSyncEpoch = nil
                case .currentProcessSync(let epoch):
                    guard epoch.isFinite,
                          epoch > 0 else {
                        throw ProjectNotePowerSyncFailure.malformedScopeEvidence
                    }
                    subscriptionWasObserved = true
                    let freshRows = try await localReader.readRows(
                        request: request,
                        principalId: principalId,
                        fetchLimit: fetchLimit
                    )
                    let scope = try Self.validateScope(freshRows)
                    latestRows = freshRows
                    currentProcessSyncEpoch = scope.isActive ? epoch : nil
                }

                guard let latestRows, subscriptionWasObserved else { continue }
                let page = try Self.page(
                    request: request,
                    rows: latestRows,
                    streamCompletionReported: currentProcessSyncEpoch != nil,
                    hasLastSyncedAt: localReader.hasLastSyncedAt,
                    asOf: now()
                )
                guard page != lastEmittedPage else { continue }
                lastEmittedPage = page
                continuation.yield(page)
            }
            continuation.finish()
        } catch is CancellationError {
            continuation.finish()
        } catch {
            continuation.finish(throwing: ProjectNoteDataFailure.localReadFailed)
        }

        databaseTask.cancel()
        completenessTask.cancel()
        _ = await databaseTask.result
        _ = await completenessTask.result
        eventChannel.continuation.finish()
    }

    private static func page(
        request: ProjectNotePageRequest,
        rows: [ProjectNotePowerSyncRow],
        streamCompletionReported: Bool,
        hasLastSyncedAt: Bool,
        asOf: Date
    ) throws -> ProjectNotePage {
        let scope = try validateScope(rows)
        guard rows.count <= Int(request.pageSize) + 1 else {
            throw ProjectNotePowerSyncFailure.rowLimitExceeded
        }
        guard !(scope.isActive && !scope.projectIsVisible && streamCompletionReported) else {
            throw ProjectNoteDataFailure.localReadFailed
        }

        let decoded = try rows.compactMap {
            try $0.note(
                accountId: request.accountId,
                projectId: request.projectId
            )
        }
        let hasExtra = decoded.count > Int(request.pageSize)
        let pageRows = Array(decoded.prefix(Int(request.pageSize)))
        let pageIsComplete = scope.isActive
            && scope.projectIsVisible
            && streamCompletionReported
        let quality: ListSnapshotQuality
        if pageIsComplete {
            quality = .ready
        } else if scope.isActive && scope.projectIsVisible && hasLastSyncedAt {
            quality = .stale
        } else {
            quality = .partial
        }
        let nextCursor: ProjectNoteCursor?
        if hasExtra, let boundary = pageRows.last {
            nextCursor = try ProjectNoteCursor(
                accountId: request.accountId,
                projectId: request.projectId,
                createdAt: boundary.createdAt,
                noteId: boundary.id
            )
        } else {
            nextCursor = nil
        }
        let local = try ListLocalSnapshot(
            queryFingerprint: request.queryFingerprint,
            rows: pageRows,
            visibleRowCountBeforeFiltering: pageRows.count,
            isCompleteForQuery: pageIsComplete,
            quality: quality,
            localDataVersion: try localDataVersion(
                request: request,
                scope: scope,
                streamIsComplete: streamCompletionReported,
                quality: quality,
                hasExtra: hasExtra,
                rows: pageRows
            ),
            asOf: asOf
        )
        return try ProjectNotePage(
            request: request,
            local: local,
            isCompleteForProjectHistory: pageIsComplete && !hasExtra,
            nextCursor: nextCursor
        )
    }

    private static func validateScope(
        _ rows: [ProjectNotePowerSyncRow]
    ) throws -> ProjectNoteScopeEvidence {
        guard let first = rows.first,
              first.scopeIsActive == 0 || first.scopeIsActive == 1,
              first.projectIsVisible == 0 || first.projectIsVisible == 1,
              rows.allSatisfy({
                  $0.scopeIsActive == first.scopeIsActive
                      && $0.projectIsVisible == first.projectIsVisible
              }) else {
            throw ProjectNotePowerSyncFailure.malformedScopeEvidence
        }
        let scope = ProjectNoteScopeEvidence(
            isActive: first.scopeIsActive == 1,
            projectIsVisible: first.projectIsVisible == 1
        )
        guard scope.isActive || !scope.projectIsVisible else {
            throw ProjectNotePowerSyncFailure.malformedScopeEvidence
        }
        let sentinels = rows.filter { $0.id == nil }
        guard sentinels.allSatisfy(\.isExactSentinel),
              sentinels.count == (rows.count == 1 && first.id == nil ? 1 : 0),
              (scope.isActive && scope.projectIsVisible) || sentinels.count == 1 else {
            throw ProjectNotePowerSyncFailure.malformedScopeEvidence
        }
        return scope
    }

    private static func localDataVersion(
        request: ProjectNotePageRequest,
        scope: ProjectNoteScopeEvidence,
        streamIsComplete: Bool,
        quality: ListSnapshotQuality,
        hasExtra: Bool,
        rows: [ProjectNoteSnapshot]
    ) throws -> LocalDataVersion {
        let basis = ProjectNoteLocalVersionBasis(
            contractVersion: "project-note-local-v1",
            requestFingerprint: request.queryFingerprint,
            scopeIsActive: scope.isActive,
            projectIsVisible: scope.projectIsVisible,
            streamIsComplete: streamIsComplete,
            quality: quality,
            hasExtra: hasExtra,
            rows: rows
        )
        let digest = SHA256.hash(data: try OperationContractCodec.encode(basis))
            .map { String(format: "%02x", $0) }
            .joined()
        return try LocalDataVersion(validating: "project-note-\(digest)")
    }

    private static func failedStream<Value: Sendable>(
        _ error: Error
    ) -> AsyncThrowingStream<Value, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }
}

private struct ProjectNoteScopeEvidence: Equatable, Sendable {
    let isActive: Bool
    let projectIsVisible: Bool
}

private struct ProjectNoteLocalVersionBasis: Codable {
    let contractVersion: String
    let requestFingerprint: ListQueryFingerprint
    let scopeIsActive: Bool
    let projectIsVisible: Bool
    let streamIsComplete: Bool
    let quality: ListSnapshotQuality
    let hasExtra: Bool
    let rows: [ProjectNoteSnapshot]
}

struct ProjectNotePowerSyncRow: Equatable, Sendable {
    let scopeIsActive: Int64
    let projectIsVisible: Int64
    let id: String?
    let keysetId: String?
    let accountId: String?
    let projectId: String?
    let contentKind: String?
    let noteText: String?
    let source: String?
    let createdByPrincipalId: String?
    let creatorDisplayName: String?
    let createdAtMilliseconds: Int64?
    let revisionText: String?
    let lastEditedByPrincipalId: String?
    let lastEditedAtMilliseconds: Int64?
    let deletedByPrincipalId: String?
    let deletedAtMilliseconds: Int64?

    init(
        scopeIsActive: Int64,
        projectIsVisible: Int64,
        id: String?,
        keysetId: String? = nil,
        accountId: String?,
        projectId: String?,
        contentKind: String?,
        noteText: String?,
        source: String?,
        createdByPrincipalId: String?,
        creatorDisplayName: String?,
        createdAtMilliseconds: Int64?,
        revisionText: String?,
        lastEditedByPrincipalId: String?,
        lastEditedAtMilliseconds: Int64?,
        deletedByPrincipalId: String?,
        deletedAtMilliseconds: Int64?
    ) {
        self.scopeIsActive = scopeIsActive
        self.projectIsVisible = projectIsVisible
        self.id = id
        self.keysetId = keysetId ?? id
        self.accountId = accountId
        self.projectId = projectId
        self.contentKind = contentKind
        self.noteText = noteText
        self.source = source
        self.createdByPrincipalId = createdByPrincipalId
        self.creatorDisplayName = creatorDisplayName
        self.createdAtMilliseconds = createdAtMilliseconds
        self.revisionText = revisionText
        self.lastEditedByPrincipalId = lastEditedByPrincipalId
        self.lastEditedAtMilliseconds = lastEditedAtMilliseconds
        self.deletedByPrincipalId = deletedByPrincipalId
        self.deletedAtMilliseconds = deletedAtMilliseconds
    }

    init(cursor: any SqlCursor) throws {
        scopeIsActive = try cursor.getInt64(name: "is_active")
        projectIsVisible = try cursor.getInt64(name: "project_is_visible")
        id = try cursor.getStringOptional(name: "id")
        keysetId = try cursor.getStringOptional(name: "keyset_id")
        accountId = try cursor.getStringOptional(name: "account_id")
        projectId = try cursor.getStringOptional(name: "project_id")
        contentKind = try cursor.getStringOptional(name: "content_kind")
        noteText = try cursor.getStringOptional(name: "note_text")
        source = try cursor.getStringOptional(name: "source")
        createdByPrincipalId = try cursor.getStringOptional(name: "created_by_principal_id")
        creatorDisplayName = try cursor.getStringOptional(name: "creator_display_name")
        createdAtMilliseconds = try cursor.getInt64Optional(name: "created_at_ms")
        revisionText = try cursor.getStringOptional(name: "revision_text")
        lastEditedByPrincipalId = try cursor.getStringOptional(
            name: "last_edited_by_principal_id"
        )
        lastEditedAtMilliseconds = try cursor.getInt64Optional(name: "last_edited_at_ms")
        deletedByPrincipalId = try cursor.getStringOptional(name: "deleted_by_principal_id")
        deletedAtMilliseconds = try cursor.getInt64Optional(name: "deleted_at_ms")
    }

    var isExactSentinel: Bool {
        id == nil
            && keysetId == nil
            && accountId == nil
            && projectId == nil
            && contentKind == nil
            && noteText == nil
            && source == nil
            && createdByPrincipalId == nil
            && creatorDisplayName == nil
            && createdAtMilliseconds == nil
            && revisionText == nil
            && lastEditedByPrincipalId == nil
            && lastEditedAtMilliseconds == nil
            && deletedByPrincipalId == nil
            && deletedAtMilliseconds == nil
    }

    func note(
        accountId expectedAccountId: AccountID,
        projectId expectedProjectId: ProjectID
    ) throws -> ProjectNoteSnapshot? {
        guard let id else {
            guard isExactSentinel else {
                throw ProjectNotePowerSyncFailure.malformedNoteRow
            }
            return nil
        }
        guard keysetId == id,
              let accountId,
              accountId == expectedAccountId.rawValue,
              let projectId,
              projectId == expectedProjectId.rawValue,
              let contentKind,
              let source,
              let createdByPrincipalId,
              let createdAtMilliseconds,
              let revisionText,
              let revision = UInt64(revisionText),
              String(revision) == revisionText else {
            throw ProjectNotePowerSyncFailure.malformedNoteRow
        }

        let content: ProjectNoteContentState
        switch contentKind {
        case "visible":
            guard let noteText,
                  deletedByPrincipalId == nil,
                  deletedAtMilliseconds == nil else {
                throw ProjectNotePowerSyncFailure.malformedNoteRow
            }
            content = .visible(try ProjectNoteText(validating: noteText))
        case "tombstone":
            guard noteText == nil,
                  let deletedByPrincipalId,
                  let deletedAtMilliseconds else {
                throw ProjectNotePowerSyncFailure.malformedNoteRow
            }
            content = .tombstone(try ProjectNoteDeletionAudit(
                deletedByPrincipalId: PrincipalID(validating: deletedByPrincipalId),
                deletedAt: Self.date(milliseconds: deletedAtMilliseconds)
            ))
        default:
            throw ProjectNotePowerSyncFailure.malformedNoteRow
        }

        let editedBy: PrincipalID?
        if let lastEditedByPrincipalId {
            editedBy = try PrincipalID(validating: lastEditedByPrincipalId)
        } else {
            editedBy = nil
        }
        return try ProjectNoteSnapshot(
            id: ProjectNoteID(validating: id),
            accountId: AccountID(validating: accountId),
            projectId: ProjectID(validating: projectId),
            content: content,
            source: ProjectNoteSource(validating: source),
            createdByPrincipalId: PrincipalID(validating: createdByPrincipalId),
            creatorDisplayName: try creatorDisplayName.map(
                ProjectNoteCreatorDisplayName.init(validating:)
            ),
            createdAt: Self.date(milliseconds: createdAtMilliseconds),
            revision: revision,
            lastEditedByPrincipalId: editedBy,
            lastEditedAt: lastEditedAtMilliseconds.map(Self.date(milliseconds:))
        )
    }

    private static func date(milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }
}

private final class ProjectNoteWatchTaskHandle: @unchecked Sendable {
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
        let installed = lock.withLock {
            cancellationRequested = true
            return task
        }
        installed?.cancel()
    }
}

private actor ProjectNoteWatchRegistry {
    private var handles: [UUID: ProjectNoteWatchTaskHandle] = [:]
    private var isClosing = false
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    func register(id: UUID, handle: ProjectNoteWatchTaskHandle) -> Bool {
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
