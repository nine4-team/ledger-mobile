import Foundation
import LedgerTargetCore
import PowerSync
import Testing
@testable import LedgerTargetPowerSync

@Suite("Project note PowerSync query", .serialized)
struct ProjectNotePowerSyncQueryTests {
    @Test("Exact stream identity and freshness reject retained or non-explicit evidence")
    func exactStreamFreshnessEvidence() async throws {
        let identity = ProjectNoteSyncStreamIdentity(
            accountId: Self.accountId,
            projectId: Self.projectId
        )
        #expect(identity.name == "project_note_history")
        #expect(identity.parameters == [
            "account_id": .string(Self.accountId.rawValue),
            "project_id": .string(Self.projectId.rawValue),
        ])

        let retained = ProjectNoteFreshnessTracker(baselineLastSyncedAt: 41)
        let disconnected = await retained.accept(.init(
            connected: false,
            active: true,
            hasExplicitSubscription: true,
            lastSyncedAt: 42
        ))
        let implicit = await retained.accept(.init(
            connected: true,
            active: true,
            hasExplicitSubscription: false,
            lastSyncedAt: 42
        ))
        let sameEpoch = await retained.accept(.init(
            connected: true,
            active: true,
            hasExplicitSubscription: true,
            lastSyncedAt: 41
        ))
        let freshEpoch = await retained.accept(.init(
            connected: true,
            active: true,
            hasExplicitSubscription: true,
            lastSyncedAt: 42
        ))
        #expect(disconnected == nil)
        #expect(implicit == nil)
        #expect(sameEpoch == nil)
        #expect(freshEpoch == 42)

        let firstProcessSync = ProjectNoteFreshnessTracker(baselineLastSyncedAt: nil)
        let causal = try await firstProcessSync.establishCausalFirstSync(.init(
            connected: true,
            active: true,
            hasExplicitSubscription: true,
            lastSyncedAt: 51
        ))
        #expect(causal == 51)
    }

    @Test("Exact Account and Project scope returns active and archived history identically")
    func exactScopeAndLifecycleParity() async throws {
        let rows = [
            Self.row(id: "note-z", createdAt: Self.t3, revision: "18446744073709551615"),
            Self.row(
                id: "note-b",
                text: "Edited note",
                createdAt: Self.t2,
                revision: "8",
                editedBy: "principal-editor",
                editedAt: Self.t3
            ),
            Self.row(
                id: "note-a",
                kind: "tombstone",
                text: nil,
                createdAt: Self.t1,
                revision: "9",
                deletedBy: "principal-editor",
                deletedAt: Self.t3
            ),
        ]
        let reader = ControlledProjectNoteReader(initialRows: rows, hasLastSyncedAt: false)
        let query = Self.query(reader, complete: true)
        let request = try Self.request(pageSize: 3)
        let page = try await Self.firstPage(query, request: request)

        #expect(page.local.quality == .ready)
        #expect(page.local.isCompleteForQuery)
        #expect(page.isCompleteForProjectHistory)
        #expect(page.nextCursor == nil)
        #expect(page.local.rows.map(\.id.rawValue) == ["note-z", "note-b", "note-a"])
        #expect(page.local.rows[0].revision == UInt64.max)
        #expect(reader.requests == [request])
        #expect(reader.principals == [Self.principalId])
        #expect(reader.fetchLimits == [4])

        if case .tombstone = page.local.rows[2].content {
            // Expected structural deletion evidence with no deleted prose.
        } else {
            Issue.record("Expected tombstone")
        }

        let wrongAccount = try Self.request(
            accountId: AccountID(validating: "account-other"),
            pageSize: 3
        )
        do {
            var iterator = query.watchNotes(wrongAccount).makeAsyncIterator()
            _ = try await iterator.next()
            Issue.record("Expected Account-bound refusal")
        } catch let failure as ProjectNoteDataFailure {
            #expect(failure == .requestMismatch)
        }
        #expect(reader.observationCount == 1)
    }

    @Test("One, two-hundred, and page-size-plus-one rows use exact descending keysets")
    func boundedKeysetPagination() async throws {
        let oneReader = ControlledProjectNoteReader(
            initialRows: [Self.row(id: "note-z", createdAt: Self.t3)],
            hasLastSyncedAt: false
        )
        let one = try await Self.firstPage(
            Self.query(oneReader, complete: true),
            request: try Self.request(pageSize: 1)
        )
        #expect(one.local.rows.count == 1)
        #expect(one.isCompleteForProjectHistory)
        #expect(one.nextCursor == nil)
        #expect(oneReader.fetchLimits == [2])

        let base = Int64(Self.t3.timeIntervalSince1970 * 1_000)
        let rows = (0...200).map { offset in
            Self.row(
                id: String(format: "note-%03d", 200 - offset),
                createdAtMilliseconds: base - Int64(offset),
                revision: String(offset)
            )
        }
        let reader = ControlledProjectNoteReader(initialRows: rows, hasLastSyncedAt: false)
        let request = try Self.request(pageSize: 200)
        let first = try await Self.firstPage(Self.query(reader, complete: true), request: request)
        #expect(first.local.rows.count == 200)
        #expect(!first.isCompleteForProjectHistory)
        #expect(first.nextCursor?.noteId == first.local.rows.last?.id)
        #expect(first.nextCursor?.createdAt == first.local.rows.last?.createdAt)
        #expect(reader.fetchLimits == [201])

        let cursor = try #require(first.nextCursor)
        let continuationRequest = try Self.request(pageSize: 200, after: cursor)
        let continuationReader = ControlledProjectNoteReader(
            initialRows: [rows[200]],
            hasLastSyncedAt: false
        )
        let tail = try await Self.firstPage(
            Self.query(continuationReader, complete: true),
            request: continuationRequest
        )
        #expect(tail.local.rows.map(\.id) == [rows[200].decodedID])
        #expect(tail.isCompleteForProjectHistory)
        #expect(tail.nextCursor == nil)
        #expect(continuationReader.requests == [continuationRequest])

        let tiedRows = [
            Self.row(id: "note-z", createdAt: Self.t2),
            Self.row(id: "note-b", createdAt: Self.t2),
            Self.row(id: "note-a", createdAt: Self.t2),
        ]
        let tiedReader = ControlledProjectNoteReader(initialRows: tiedRows, hasLastSyncedAt: false)
        let tied = try await Self.firstPage(
            Self.query(tiedReader, complete: true),
            request: try Self.request(pageSize: 2)
        )
        #expect(tied.local.rows.map(\.id.rawValue) == ["note-z", "note-b"])
        #expect(tied.nextCursor?.noteId.rawValue == "note-b")
    }

    @Test("Retained rows stay stale until fresh exact completion")
    func retainedRowsRequireFreshCompletion() async throws {
        let reader = ControlledProjectNoteReader(
            initialRows: [Self.row(id: "note-z", createdAt: Self.t3)],
            hasLastSyncedAt: true
        )
        let completion = ControlledProjectNoteCompleteness(initialValue: false)
        let query = Self.query(reader, completeness: completion.stream)
        var iterator = query.watchNotes(try Self.request(pageSize: 20)).makeAsyncIterator()

        let retained = try #require(try await iterator.next())
        #expect(retained.local.quality == .stale)
        #expect(!retained.local.isCompleteForQuery)
        #expect(!retained.isCompleteForProjectHistory)
        let readsBeforeCompletion = reader.readCount

        completion.yield(true)
        let fresh = try #require(try await iterator.next())
        #expect(fresh.local.quality == .ready)
        #expect(fresh.isCompleteForProjectHistory)
        #expect(fresh.local.rows == retained.local.rows)
        #expect(fresh.local.localDataVersion != retained.local.localDataVersion)
        #expect(reader.readCount == readsBeforeCompletion + 1)
    }

    @Test("Status-first and row-first removals reread current rows before readiness")
    func removalsRequireCausalReread() async throws {
        let oldRows = [Self.row(id: "note-z", createdAt: Self.t3)]

        let statusFirstReader = ControlledProjectNoteReader(
            initialRows: oldRows,
            hasLastSyncedAt: true
        )
        let statusFirstCompletion = ControlledProjectNoteCompleteness(initialValue: false)
        let statusFirstQuery = Self.query(
            statusFirstReader,
            completeness: statusFirstCompletion.stream
        )
        var statusFirst = statusFirstQuery.watchNotes(
            try Self.request(pageSize: 20)
        ).makeAsyncIterator()
        #expect(try #require(try await statusFirst.next()).local.rows.count == 1)
        statusFirstReader.setCurrentRows([Self.sentinel(scope: 1, parent: 1)])
        statusFirstCompletion.yield(true)
        let statusFirstReady = try #require(try await statusFirst.next())
        #expect(statusFirstReady.local.rows.isEmpty)
        #expect(statusFirstReady.local.quality == .ready)
        #expect(statusFirstReady.isCompleteForProjectHistory)

        let newlyAppliedRows = [Self.row(id: "note-a", createdAt: Self.t2)]
        statusFirstReader.setCurrentRows(newlyAppliedRows)
        statusFirstReader.yieldWatchPayload(oldRows)
        let afterDelayedOldPayload = try #require(try await statusFirst.next())
        #expect(afterDelayedOldPayload.local.rows.map(\.id.rawValue) == ["note-a"])
        #expect(afterDelayedOldPayload.local.quality == .ready)

        let rowFirstReader = ControlledProjectNoteReader(
            initialRows: oldRows,
            hasLastSyncedAt: true
        )
        let rowFirstCompletion = ControlledProjectNoteCompleteness(initialValue: false)
        let rowFirstQuery = Self.query(rowFirstReader, completeness: rowFirstCompletion.stream)
        var rowFirst = rowFirstQuery.watchNotes(
            try Self.request(pageSize: 20)
        ).makeAsyncIterator()
        #expect(try #require(try await rowFirst.next()).local.rows.count == 1)
        rowFirstReader.yield([Self.sentinel(scope: 1, parent: 1)])
        let rowFirstStale = try #require(try await rowFirst.next())
        #expect(rowFirstStale.local.rows.isEmpty)
        #expect(rowFirstStale.local.quality == .stale)
        #expect(!rowFirstStale.isCompleteForProjectHistory)
        rowFirstCompletion.yield(true)
        let rowFirstReady = try #require(try await rowFirst.next())
        #expect(rowFirstReady.local.rows.isEmpty)
        #expect(rowFirstReady.local.quality == .ready)
        #expect(rowFirstReady.isCompleteForProjectHistory)
    }

    @Test("Membership loss clears rows and reactivation requires new completion")
    func revocationAndReactivationResetCompleteness() async throws {
        let reader = ControlledProjectNoteReader(
            initialRows: [Self.row(id: "note-z", createdAt: Self.t3)],
            hasLastSyncedAt: true
        )
        let completion = ControlledProjectNoteCompleteness(initialValue: true)
        let query = Self.query(reader, completeness: completion.stream)
        var iterator = query.watchNotes(try Self.request(pageSize: 20)).makeAsyncIterator()
        #expect(try #require(try await iterator.next()).local.quality == .ready)

        reader.yield([Self.sentinel(scope: 0, parent: 0)])
        let revoked = try #require(try await iterator.next())
        #expect(revoked.local.rows.isEmpty)
        #expect(revoked.local.quality == .partial)
        #expect(!revoked.local.isCompleteForQuery)
        #expect(!revoked.isCompleteForProjectHistory)

        reader.yield([Self.row(id: "note-z", createdAt: Self.t3)])
        let reactivated = try #require(try await iterator.next())
        #expect(reactivated.local.rows.count == 1)
        #expect(reactivated.local.quality == .stale)
        #expect(!reactivated.isCompleteForProjectHistory)

        completion.yield(true)
        #expect(try #require(try await iterator.next()).local.quality == .ready)
    }

    @Test("Status-first membership revocation clears retained rows and completeness")
    func statusFirstRevocationClearsCompleteness() async throws {
        let reader = ControlledProjectNoteReader(
            initialRows: [Self.row(id: "note-z", createdAt: Self.t3)],
            hasLastSyncedAt: true
        )
        let completion = ControlledProjectNoteCompleteness(initialValue: true)
        let query = Self.query(reader, completeness: completion.stream)
        var iterator = query.watchNotes(try Self.request(pageSize: 20)).makeAsyncIterator()
        #expect(try #require(try await iterator.next()).local.quality == .ready)

        reader.setCurrentRows([Self.sentinel(scope: 0, parent: 0)])
        completion.yield(true)
        let revoked = try #require(try await iterator.next())
        #expect(revoked.local.rows.isEmpty)
        #expect(revoked.local.quality == .partial)
        #expect(!revoked.local.isCompleteForQuery)
        #expect(!revoked.isCompleteForProjectHistory)

        reader.yield([Self.row(id: "note-z", createdAt: Self.t3)])
        let reactivated = try #require(try await iterator.next())
        #expect(reactivated.local.quality == .stale)
        #expect(!reactivated.isCompleteForProjectHistory)
        completion.yield(true)
        #expect(try #require(try await iterator.next()).local.quality == .ready)
    }

    @Test("Missing parent is partial until fresh completion then fails without existence detail")
    func missingParentFailsBoundedly() async throws {
        let reader = ControlledProjectNoteReader(
            initialRows: [Self.sentinel(scope: 1, parent: 0)],
            hasLastSyncedAt: true
        )
        let completion = ControlledProjectNoteCompleteness(initialValue: false)
        let query = Self.query(reader, completeness: completion.stream)
        var iterator = query.watchNotes(try Self.request(pageSize: 20)).makeAsyncIterator()
        let partial = try #require(try await iterator.next())
        #expect(partial.local.rows.isEmpty)
        #expect(partial.local.quality == .partial)
        #expect(!partial.isCompleteForProjectHistory)

        completion.yield(true)
        do {
            _ = try await iterator.next()
            Issue.record("Expected missing parent failure after exact-stream completion")
        } catch let failure as ProjectNoteDataFailure {
            #expect(failure == .localReadFailed)
            #expect(failure.diagnosticCode == "project_note_local_read_failed")
        }
    }

    @Test("Malformed scope, row, order, and revision fail atomically")
    func malformedEvidenceFailsAtomically() async throws {
        let cases: [[ProjectNotePowerSyncRow]] = [
            [],
            [Self.sentinel(scope: 2, parent: 0)],
            [Self.sentinel(scope: 0, parent: 1)],
            [Self.row(id: "note-z", revision: "01")],
            [Self.row(id: "note-z", text: nil)],
            [Self.row(id: "note-a", createdAt: Self.t1), Self.row(id: "note-z", createdAt: Self.t3)],
            [Self.row(id: "note-z"), Self.row(id: "note-z")],
        ]
        for rows in cases {
            let reader = ControlledProjectNoteReader(initialRows: rows, hasLastSyncedAt: false)
            let query = Self.query(reader, complete: false)
            var emitted = 0
            do {
                for try await _ in query.watchNotes(try Self.request(pageSize: 20)) {
                    emitted += 1
                }
                Issue.record("Expected malformed local evidence failure")
            } catch let failure as ProjectNoteDataFailure {
                #expect(failure == .localReadFailed)
            }
            #expect(emitted == 0)
        }

        let tooMany = (0..<22).map {
            Self.row(
                id: String(format: "note-%03d", 22 - $0),
                createdAtMilliseconds: Int64(Self.t3.timeIntervalSince1970 * 1_000) - Int64($0)
            )
        }
        let reader = ControlledProjectNoteReader(initialRows: tooMany, hasLastSyncedAt: false)
        do {
            _ = try await Self.firstPage(
                Self.query(reader, complete: false),
                request: try Self.request(pageSize: 20)
            )
            Issue.record("Expected pageSize+1 enforcement")
        } catch let failure as ProjectNoteDataFailure {
            #expect(failure == .localReadFailed)
        }
    }

    @Test("Consumer cancellation and provider shutdown drain both owned sources")
    func cancellationAndShutdownDrainSources() async throws {
        let reader = ControlledProjectNoteReader(
            initialRows: [Self.row(id: "note-z")],
            hasLastSyncedAt: false
        )
        let completion = ControlledProjectNoteCompleteness(initialValue: false)
        let query = Self.query(reader, completeness: completion.stream)
        let emitted = LockedNoteCounter()
        let signal = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let consumer = Task {
            do {
                for try await _ in query.watchNotes(try Self.request(pageSize: 20)) {
                    emitted.increment()
                    signal.continuation.yield(())
                }
            } catch {
                Issue.record("Cancellation must finish normally")
            }
        }
        var signalIterator = signal.stream.makeAsyncIterator()
        _ = await signalIterator.next()
        consumer.cancel()
        await consumer.value

        for _ in 0..<100 where reader.terminationCount != 1 || completion.terminationCount != 1 {
            await Task.yield()
        }
        #expect(reader.terminationCount == 1)
        #expect(completion.terminationCount == 1)
        let count = emitted.value
        reader.yield([Self.row(id: "note-a")])
        completion.yield(true)
        try await Task.sleep(for: .milliseconds(20))
        #expect(emitted.value == count)
        signal.continuation.finish()

        let shutdownReader = ControlledProjectNoteReader(
            initialRows: [Self.row(id: "note-z")],
            hasLastSyncedAt: false
        )
        let shutdownCompletion = ControlledProjectNoteCompleteness(initialValue: nil)
        let shutdownQuery = Self.query(shutdownReader, completeness: shutdownCompletion.stream)
        let shutdownConsumer = Task {
            do {
                for try await _ in shutdownQuery.watchNotes(try Self.request(pageSize: 20)) {}
            } catch {
                Issue.record("Provider shutdown must finish normally")
            }
        }
        for _ in 0..<100 where shutdownReader.observationCount == 0 { await Task.yield() }
        await shutdownQuery.cancelAndDrainWatches()
        await shutdownConsumer.value
        for _ in 0..<100
        where shutdownReader.terminationCount != 1
            || shutdownCompletion.terminationCount != 1 {
            await Task.yield()
        }
        #expect(shutdownReader.terminationCount == 1)
        #expect(shutdownCompletion.terminationCount == 1)
    }

    @Test("Encrypted local paging survives lifecycle change and restart without retaining completeness")
    func encryptedRestartAndArchiveParity() async throws {
        let fixture = try ProjectNoteDatabaseFixture()
        let database = fixture.open()
        try await fixture.seed(database)
        let request = try Self.request(pageSize: 2)
        let before = try await Self.firstPage(
            Self.query(database, complete: true),
            request: request
        )
        #expect(before.local.rows.map(\.id.rawValue) == ["note-z", "note-b"])
        let tailCursor = try #require(before.nextCursor)
        #expect(tailCursor.noteId.rawValue == "note-b")

        _ = try await database.execute(
            sql: "UPDATE spike_projects SET lifecycle = 'archived' WHERE id = ?",
            parameters: [Self.projectId.rawValue]
        )
        let archived = try await Self.firstPage(
            Self.query(database, complete: true),
            request: request
        )
        #expect(archived == before)

        try await database.close(deleteDatabase: false)
        let bytes = try Data(contentsOf: fixture.databaseURL)
        #expect(!String(decoding: bytes, as: UTF8.self).contains("Highly confidential note"))

        let reopened = fixture.open()
        let retained = try await Self.firstPage(
            Self.query(reopened, complete: false),
            request: request
        )
        #expect(retained.local.rows == before.local.rows)
        #expect(retained.local.quality != .ready)
        #expect(!retained.local.isCompleteForQuery)
        #expect(!retained.isCompleteForProjectHistory)
        #expect(retained.nextCursor == tailCursor)

        let tailRequest = try Self.request(pageSize: 2, after: tailCursor)
        let tail = try await Self.firstPage(
            Self.query(reopened, complete: true),
            request: tailRequest
        )
        #expect(tail.local.rows.map(\.id.rawValue) == ["note-a"])
        #expect(tail.isCompleteForProjectHistory)

        try await reopened.close(deleteDatabase: true)
        fixture.remove()
    }

    private static let accountId = try! AccountID(validating: "account-primary")
    private static let principalId = try! PrincipalID(validating: "principal-owner")
    private static let projectId = try! ProjectID(validating: "project-primary")
    private static let observedAt = Date(timeIntervalSince1970: 1_788_700_000)
    private static let t1 = Date(timeIntervalSince1970: 1_788_600_001)
    private static let t2 = Date(timeIntervalSince1970: 1_788_600_002)
    private static let t3 = Date(timeIntervalSince1970: 1_788_600_003)

    private static func query(
        _ reader: any ProjectNoteLocalReading,
        complete: Bool
    ) -> ProjectNotePowerSyncQuery {
        query(reader, completeness: fixedStream(complete))
    }

    private static func query(
        _ reader: any ProjectNoteLocalReading,
        completeness: AsyncStream<Bool>
    ) -> ProjectNotePowerSyncQuery {
        ProjectNotePowerSyncQuery(
            localReader: reader,
            principalId: principalId,
            accountId: accountId,
            completenessObservation: { _, _ in completeness },
            now: { observedAt }
        )
    }

    private static func query(
        _ database: any PowerSyncDatabaseProtocol,
        complete: Bool
    ) -> ProjectNotePowerSyncQuery {
        ProjectNotePowerSyncQuery(
            database: database,
            principalId: principalId,
            accountId: accountId,
            testCompletenessObservation: { _, _ in fixedStream(complete) },
            now: { observedAt }
        )
    }

    private static func request(
        accountId: AccountID = accountId,
        pageSize: UInt16,
        after: ProjectNoteCursor? = nil
    ) throws -> ProjectNotePageRequest {
        try ProjectNotePageRequest(
            accountId: accountId,
            projectId: projectId,
            pageSize: pageSize,
            after: after
        )
    }

    private static func firstPage(
        _ query: ProjectNotePowerSyncQuery,
        request: ProjectNotePageRequest
    ) async throws -> ProjectNotePage {
        var iterator = query.watchNotes(request).makeAsyncIterator()
        return try #require(try await iterator.next())
    }

    private static func fixedStream(_ value: Bool) -> AsyncStream<Bool> {
        AsyncStream { continuation in
            continuation.yield(value)
            continuation.finish()
        }
    }

    private static func row(
        id: String,
        accountId: String = "account-primary",
        projectId: String = "project-primary",
        kind: String = "visible",
        text: String? = "Highly confidential note",
        source: String = "app",
        createdBy: String = "principal-owner",
        creatorName: String? = "Owner",
        createdAt: Date = t1,
        createdAtMilliseconds: Int64? = nil,
        revision: String = "1",
        editedBy: String? = nil,
        editedAt: Date? = nil,
        deletedBy: String? = nil,
        deletedAt: Date? = nil
    ) -> ProjectNotePowerSyncRow {
        ProjectNotePowerSyncRow(
            scopeIsActive: 1,
            projectIsVisible: 1,
            id: id,
            accountId: accountId,
            projectId: projectId,
            contentKind: kind,
            noteText: text,
            source: source,
            createdByPrincipalId: createdBy,
            creatorDisplayName: creatorName,
            createdAtMilliseconds: createdAtMilliseconds
                ?? Int64(createdAt.timeIntervalSince1970 * 1_000),
            revisionText: revision,
            lastEditedByPrincipalId: editedBy,
            lastEditedAtMilliseconds: editedAt.map {
                Int64($0.timeIntervalSince1970 * 1_000)
            },
            deletedByPrincipalId: deletedBy,
            deletedAtMilliseconds: deletedAt.map {
                Int64($0.timeIntervalSince1970 * 1_000)
            }
        )
    }

    private static func sentinel(scope: Int64, parent: Int64) -> ProjectNotePowerSyncRow {
        ProjectNotePowerSyncRow(
            scopeIsActive: scope,
            projectIsVisible: parent,
            id: nil,
            accountId: nil,
            projectId: nil,
            contentKind: nil,
            noteText: nil,
            source: nil,
            createdByPrincipalId: nil,
            creatorDisplayName: nil,
            createdAtMilliseconds: nil,
            revisionText: nil,
            lastEditedByPrincipalId: nil,
            lastEditedAtMilliseconds: nil,
            deletedByPrincipalId: nil,
            deletedAtMilliseconds: nil
        )
    }
}

private extension ProjectNotePowerSyncRow {
    var decodedID: ProjectNoteID? { id.flatMap { try? ProjectNoteID(validating: $0) } }
}

private final class ControlledProjectNoteReader:
    ProjectNoteLocalReading, @unchecked Sendable
{
    let hasLastSyncedAt: Bool
    private let lock = NSLock()
    private var currentRows: [ProjectNotePowerSyncRow]
    private var continuation:
        AsyncThrowingStream<[ProjectNotePowerSyncRow], Error>.Continuation?
    private var recordedRequests: [ProjectNotePageRequest] = []
    private var recordedPrincipals: [PrincipalID] = []
    private var recordedFetchLimits: [Int] = []
    private var reads = 0
    private var observations = 0
    private var terminations = 0

    init(initialRows: [ProjectNotePowerSyncRow], hasLastSyncedAt: Bool) {
        currentRows = initialRows
        self.hasLastSyncedAt = hasLastSyncedAt
    }

    var requests: [ProjectNotePageRequest] { lock.withLock { recordedRequests } }
    var principals: [PrincipalID] { lock.withLock { recordedPrincipals } }
    var fetchLimits: [Int] { lock.withLock { recordedFetchLimits } }
    var readCount: Int { lock.withLock { reads } }
    var observationCount: Int { lock.withLock { observations } }
    var terminationCount: Int { lock.withLock { terminations } }

    func readRows(
        request: ProjectNotePageRequest,
        principalId: PrincipalID,
        fetchLimit: Int
    ) async throws -> [ProjectNotePowerSyncRow] {
        lock.withLock {
            reads += 1
            return currentRows
        }
    }

    func watchRows(
        request: ProjectNotePageRequest,
        principalId: PrincipalID,
        fetchLimit: Int
    ) throws -> AsyncThrowingStream<[ProjectNotePowerSyncRow], Error> {
        lock.withLock {
            recordedRequests.append(request)
            recordedPrincipals.append(principalId)
            recordedFetchLimits.append(fetchLimit)
            observations += 1
        }
        return AsyncThrowingStream { continuation in
            lock.withLock { self.continuation = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.terminations += 1 }
            }
            continuation.yield(lock.withLock { currentRows })
        }
    }

    func yield(_ rows: [ProjectNotePowerSyncRow]) {
        lock.withLock { currentRows = rows }
        lock.withLock { continuation }?.yield(rows)
    }

    func setCurrentRows(_ rows: [ProjectNotePowerSyncRow]) {
        lock.withLock { currentRows = rows }
    }

    func yieldWatchPayload(_ rows: [ProjectNotePowerSyncRow]) {
        lock.withLock { continuation }?.yield(rows)
    }
}

private final class ControlledProjectNoteCompleteness: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Bool>.Continuation?
    private var terminations = 0
    let stream: AsyncStream<Bool>

    init(initialValue: Bool?) {
        var captured: AsyncStream<Bool>.Continuation?
        stream = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            captured = continuation
        }
        continuation = captured
        continuation?.onTermination = { [weak self] _ in
            self?.lock.withLock { self?.terminations += 1 }
        }
        if let initialValue { continuation?.yield(initialValue) }
    }

    var terminationCount: Int { lock.withLock { terminations } }

    func yield(_ value: Bool) {
        continuation?.yield(value)
    }
}

private final class LockedNoteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private final class ProjectNoteDatabaseFixture: @unchecked Sendable {
    let directoryURL: URL
    let databaseURL: URL
    private let keyHex = String(repeating: "7c", count: 32)

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ledger-project-notes-\(UUID().uuidString)",
            isDirectory: true
        )
        databaseURL = directoryURL.appendingPathComponent("ledger.sqlite")
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    func open() -> any PowerSyncDatabaseProtocol {
        PowerSyncDatabase(
            schema: Self.schema,
            dbFilename: databaseURL.path,
            initialStatements: ["PRAGMA key = \"x'\(keyHex)'\""]
        )
    }

    func seed(_ database: any PowerSyncDatabaseProtocol) async throws {
        _ = try await database.execute(
            sql: """
            INSERT INTO spike_account_memberships (id, account_id, principal_id, state)
            VALUES ('membership-primary', 'account-primary', 'principal-owner', 'active')
            """,
            parameters: nil
        )
        _ = try await database.execute(
            sql: """
            INSERT INTO spike_projects (id, account_id, lifecycle)
            VALUES ('project-primary', 'account-primary', 'active')
            """,
            parameters: nil
        )
        for values: [any Sendable] in [
            ["note-z", "Highly confidential note", Int64(1_788_600_003_000), "18446744073709551615"],
            ["note-b", "Second note", Int64(1_788_600_002_000), "8"],
            ["note-a", "Old note", Int64(1_788_600_001_000), "1"],
        ] {
            _ = try await database.execute(
                sql: """
                INSERT INTO spike_project_notes (
                  id, account_id, project_id, keyset_id, content_kind, note_text, source,
                  created_by_principal_id, creator_display_name, created_at_ms,
                  revision
                ) VALUES (?, 'account-primary', 'project-primary', ?, 'visible', ?,
                          'app', 'principal-owner', 'Owner', ?, ?)
                """,
                parameters: [values[0], values[0], values[1], values[2], values[3]]
            )
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private static let schema = Schema(
        Table(
            name: "spike_account_memberships",
            columns: [.text("account_id"), .text("principal_id"), .text("state")]
        ),
        Table(
            name: "spike_projects",
            columns: [.text("account_id"), .text("lifecycle")]
        ),
        Table(
            name: "spike_project_notes",
            columns: [
                .text("account_id"), .text("project_id"), .text("keyset_id"),
                .text("content_kind"),
                .text("note_text"), .text("source"), .text("created_by_principal_id"),
                .text("creator_display_name"), .integer("created_at_ms"),
                .text("revision"), .text("last_edited_by_principal_id"),
                .integer("last_edited_at_ms"), .text("deleted_by_principal_id"),
                .integer("deleted_at_ms"),
            ],
            indexes: [
                .ascending(
                    name: "project_note_history",
                    columns: ["account_id", "project_id", "created_at_ms", "keyset_id"]
                )
            ]
        )
    )
}
