import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetAppModel

@Suite("Project Note History Staging Flow")
@MainActor
struct ProjectNoteHistoryStagingExerciseTests {
    @Test("Selection reads a bounded first page and tombstones never expose deleted text")
    func firstPageAndTombstonePresentation() async throws {
        let probe = NotePageWatchProbe()
        let model = ProjectNoteHistoryStagingExercise(accountId: Self.accountId)
        let runtime = Self.runtime(probe)

        await model.select(projectId: Self.projectA, runtime: runtime)
        await Self.waitUntil { probe.requests.count == 1 }
        let request = try #require(probe.requests.first)
        #expect(request.pageSize == ProjectNotePageRequest.maximumPageSize)
        #expect(request.after == nil)

        probe.sources[0].yield(try Self.page(
            request: request,
            rows: [
                Self.note(id: "note-b", projectId: Self.projectA, text: "Visible"),
                Self.note(id: "note-a", projectId: Self.projectA, text: nil)
            ],
            quality: .stale,
            complete: false,
            hasMore: true
        ))
        await Self.waitUntil { model.rows.count == 2 }

        #expect(model.status == "stale • incomplete")
        #expect(model.rows[0].body == "Visible")
        #expect(model.rows[1].body == "Deleted note")
        #expect(model.rows[1].isTombstone)
        #expect(model.hasOlderNotes)
        #expect(model.isShowingNewestPage)
        await model.stop()
    }

    @Test("Older and newest navigation cancel and drain the prior exact page")
    func pageNavigationDrainsOldWatch() async throws {
        let probe = NotePageWatchProbe()
        let model = ProjectNoteHistoryStagingExercise(accountId: Self.accountId)
        let runtime = Self.runtime(probe)
        await model.select(projectId: Self.projectA, runtime: runtime)
        await Self.waitUntil { probe.requests.count == 1 }
        let firstRequest = probe.requests[0]
        probe.sources[0].yield(try Self.page(
            request: firstRequest,
            rows: [Self.note(id: "note-b", projectId: Self.projectA, text: "Newest")],
            complete: false,
            hasMore: true
        ))
        await Self.waitUntil { model.hasOlderNotes }

        await model.loadOlderNotes()
        await Self.waitUntil { probe.requests.count == 2 }
        #expect(probe.sources[0].terminationCount == 1)
        #expect(probe.requests[1].after?.noteId.rawValue == "note-b")
        probe.sources[1].yield(try Self.page(
            request: probe.requests[1],
            rows: [Self.note(
                id: "note-a",
                projectId: Self.projectA,
                text: "Older",
                createdAt: Self.t0
            )],
            complete: true,
            hasMore: false
        ))
        await Self.waitUntil { model.rows.first?.body == "Older" }
        #expect(!model.isShowingNewestPage)

        await model.showNewestNotes()
        await Self.waitUntil { probe.requests.count == 3 }
        #expect(probe.sources[1].terminationCount == 1)
        #expect(probe.requests[2].after == nil)
        #expect(model.rows.isEmpty)
        await model.stop()
    }

    @Test("Changing Project clears old rows and rejects late old-generation evidence")
    func selectionGenerationIsolation() async throws {
        let probe = NotePageWatchProbe()
        let model = ProjectNoteHistoryStagingExercise(accountId: Self.accountId)
        let runtime = Self.runtime(probe)
        await model.select(projectId: Self.projectA, runtime: runtime)
        await Self.waitUntil { probe.requests.count == 1 }
        probe.sources[0].yield(try Self.page(
            request: probe.requests[0],
            rows: [Self.note(id: "note-a", projectId: Self.projectA, text: "A")],
            complete: true,
            hasMore: false
        ))
        await Self.waitUntil { model.rows.first?.body == "A" }

        await model.select(projectId: Self.projectB, runtime: runtime)
        await Self.waitUntil { probe.requests.count == 2 }
        #expect(model.rows.isEmpty)
        #expect(model.selectedProjectId == Self.projectB)
        #expect(probe.sources[0].terminationCount == 1)

        probe.sources[0].yield(try Self.page(
            request: probe.requests[0],
            rows: [Self.note(id: "late", projectId: Self.projectA, text: "Late")],
            complete: true,
            hasMore: false
        ))
        for _ in 0..<10 { await Task.yield() }
        #expect(model.rows.isEmpty)
        await model.stop()
    }

    @Test("Only ready complete empty evidence is presented as no notes")
    func authoritativeEmptyIsDistinct() async throws {
        let probe = NotePageWatchProbe()
        let model = ProjectNoteHistoryStagingExercise(accountId: Self.accountId)
        await model.select(projectId: Self.projectA, runtime: Self.runtime(probe))
        await Self.waitUntil { probe.requests.count == 1 }
        let request = probe.requests[0]

        probe.sources[0].yield(try Self.page(
            request: request,
            rows: [],
            quality: .partial,
            complete: false,
            hasMore: false
        ))
        await Self.waitUntil { model.status == "partial • incomplete" }
        #expect(!model.isAuthoritativelyEmpty)

        probe.sources[0].yield(try Self.page(
            request: request,
            rows: [],
            quality: .ready,
            complete: true,
            hasMore: false
        ))
        await Self.waitUntil { model.isAuthoritativelyEmpty }
        #expect(model.status == "ready • complete")
        #expect(model.rows.isEmpty)
        await model.stop()
    }

    @Test("Upstream cancellation clears sensitive rows and fails closed")
    func upstreamCancellationClearsRows() async throws {
        let probe = NotePageWatchProbe()
        let model = ProjectNoteHistoryStagingExercise(accountId: Self.accountId)
        await model.select(projectId: Self.projectA, runtime: Self.runtime(probe))
        await Self.waitUntil { probe.requests.count == 1 }
        probe.sources[0].yield(try Self.page(
            request: probe.requests[0],
            rows: [Self.note(id: "note-sensitive", projectId: Self.projectA, text: "Sensitive")],
            complete: true,
            hasMore: false
        ))
        await Self.waitUntil { model.rows.first?.body == "Sensitive" }

        probe.sources[0].finish(throwing: CancellationError())
        await Self.waitUntil { model.diagnostic == "project_note_source_cancelled" }
        #expect(model.rows.isEmpty)
        #expect(model.status == "blocked • completeness unknown")
        #expect(!model.isAuthoritativelyEmpty)
        await model.stop()
    }

    private static let accountId = try! AccountID(validating: "project-account")
    private static let projectA = try! ProjectID(validating: "project-a")
    private static let projectB = try! ProjectID(validating: "project-b")
    private static let principalId = try! PrincipalID(validating: "principal-a")
    private static let t0 = Date(timeIntervalSince1970: 1_804_000_000)
    private static let t1 = Date(timeIntervalSince1970: 1_804_000_001)

    private static func runtime(_ probe: NotePageWatchProbe) -> ProjectBrowsingStagingRuntime {
        ProjectBrowsingStagingRuntime(
            watchProjects: { AsyncThrowingStream { _ in } },
            watchProject: { _ in AsyncThrowingStream { _ in } },
            watchNotes: { probe.watch($0) }
        )
    }

    private static func note(
        id: String,
        projectId: ProjectID,
        text: String?,
        createdAt: Date = t1
    ) throws -> ProjectNoteSnapshot {
        let content: ProjectNoteContentState = if let text {
            .visible(try ProjectNoteText(validating: text))
        } else {
            .tombstone(try ProjectNoteDeletionAudit(
                deletedByPrincipalId: principalId,
                deletedAt: createdAt
            ))
        }
        return try ProjectNoteSnapshot(
            id: ProjectNoteID(validating: id),
            accountId: accountId,
            projectId: projectId,
            content: content,
            source: ProjectNoteSource(validating: "text"),
            createdByPrincipalId: principalId,
            creatorDisplayName: try ProjectNoteCreatorDisplayName(validating: "Jordan"),
            createdAt: createdAt,
            revision: 1
        )
    }

    private static func page(
        request: ProjectNotePageRequest,
        rows: [ProjectNoteSnapshot],
        quality: ListSnapshotQuality = .ready,
        complete: Bool,
        hasMore: Bool
    ) throws -> ProjectNotePage {
        let next: ProjectNoteCursor? = if hasMore, let last = rows.last {
            try ProjectNoteCursor(
                accountId: request.accountId,
                projectId: request.projectId,
                createdAt: last.createdAt,
                noteId: last.id
            )
        } else {
            nil
        }
        return try ProjectNotePage(
            request: request,
            local: ListLocalSnapshot(
                queryFingerprint: request.queryFingerprint,
                rows: rows,
                visibleRowCountBeforeFiltering: rows.count,
                isCompleteForQuery: complete,
                quality: quality,
                localDataVersion: LocalDataVersion(validating: "notes-\(rows.count)-\(quality.rawValue)"),
                asOf: t1
            ),
            isCompleteForProjectHistory: complete,
            nextCursor: next
        )
    }

    private static func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<400 {
            if predicate() { return }
            await Task.yield()
        }
    }
}

private final class NotePageWatchProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedRequests: [ProjectNotePageRequest] = []
    private var recordedSources: [NotePageControlledStream] = []

    var requests: [ProjectNotePageRequest] { lock.withLock { recordedRequests } }
    var sources: [NotePageControlledStream] { lock.withLock { recordedSources } }

    func watch(_ request: ProjectNotePageRequest) -> AsyncThrowingStream<ProjectNotePage, Error> {
        let source = NotePageControlledStream()
        lock.withLock {
            recordedRequests.append(request)
            recordedSources.append(source)
        }
        return source.stream
    }
}

private final class NotePageControlledStream: @unchecked Sendable {
    let stream: AsyncThrowingStream<ProjectNotePage, Error>
    private let continuation: AsyncThrowingStream<ProjectNotePage, Error>.Continuation
    private let lock = NSLock()
    private var recordedTerminationCount = 0

    init() {
        var captured: AsyncThrowingStream<ProjectNotePage, Error>.Continuation?
        stream = AsyncThrowingStream { captured = $0 }
        continuation = captured!
        continuation.onTermination = { [weak self] _ in
            self?.lock.withLock { self?.recordedTerminationCount += 1 }
        }
    }

    var terminationCount: Int { lock.withLock { recordedTerminationCount } }
    func yield(_ page: ProjectNotePage) { continuation.yield(page) }
    func finish(throwing error: Error? = nil) {
        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }
}
