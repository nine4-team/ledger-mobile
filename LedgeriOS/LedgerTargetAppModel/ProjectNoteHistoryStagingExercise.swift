import Foundation
import LedgerTargetCore
import Observation

public struct ProjectNoteHistoryRowPresentation: Equatable, Identifiable, Sendable {
    public let id: ProjectNoteID
    public let body: String
    public let isTombstone: Bool
    public let creatorDisplayName: String?
    public let source: String
    public let createdAt: Date
    public let lastEditedAt: Date?

    init(note: ProjectNoteSnapshot) {
        id = note.id
        switch note.content {
        case .visible(let text):
            body = text.rawValue
            isTombstone = false
        case .tombstone:
            body = "Deleted note"
            isTombstone = true
        }
        creatorDisplayName = note.creatorDisplayName?.rawValue
        source = note.source.rawValue
        createdAt = note.createdAt
        lastEditedAt = note.lastEditedAt
    }
}

@MainActor
@Observable
public final class ProjectNoteHistoryStagingExercise {
    public private(set) var rows: [ProjectNoteHistoryRowPresentation] = []
    public private(set) var status = "not requested"
    public private(set) var diagnostic: String?
    public private(set) var selectedProjectId: ProjectID?
    public private(set) var hasOlderNotes = false
    public private(set) var isShowingNewestPage = true
    public private(set) var isAuthoritativelyEmpty = false

    private static let pageSize = ProjectNotePageRequest.maximumPageSize
    private let accountId: AccountID
    private var runtime: ProjectBrowsingStagingRuntime?
    private var currentRequest: ProjectNotePageRequest?
    private var nextCursor: ProjectNoteCursor?
    private var observationTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    public init(accountId: AccountID) {
        self.accountId = accountId
    }

    public func select(
        projectId: ProjectID,
        runtime: ProjectBrowsingStagingRuntime
    ) async {
        self.runtime = runtime
        selectedProjectId = projectId
        await observe(after: nil)
    }

    public func loadOlderNotes() async {
        guard let cursor = nextCursor else { return }
        await observe(after: cursor)
    }

    public func showNewestNotes() async {
        guard !isShowingNewestPage, selectedProjectId != nil else { return }
        await observe(after: nil)
    }

    public func clear() async {
        generation &+= 1
        let oldTask = observationTask
        observationTask = nil
        selectedProjectId = nil
        currentRequest = nil
        nextCursor = nil
        rows = []
        hasOlderNotes = false
        isShowingNewestPage = true
        isAuthoritativelyEmpty = false
        status = "not requested"
        diagnostic = nil
        oldTask?.cancel()
        await oldTask?.value
    }

    public func stop() async {
        await clear()
        runtime = nil
        status = "stopped"
    }

    private func observe(after cursor: ProjectNoteCursor?) async {
        guard let runtime, let projectId = selectedProjectId else {
            await clear()
            return
        }

        generation &+= 1
        let activeGeneration = generation
        let oldTask = observationTask
        observationTask = nil
        rows = []
        nextCursor = nil
        hasOlderNotes = false
        isShowingNewestPage = cursor == nil
        isAuthoritativelyEmpty = false
        status = "loading • completeness unknown"
        diagnostic = nil
        oldTask?.cancel()
        await oldTask?.value

        guard generation == activeGeneration,
              selectedProjectId == projectId,
              self.runtime != nil else { return }

        do {
            let request = try ProjectNotePageRequest(
                accountId: accountId,
                projectId: projectId,
                pageSize: Self.pageSize,
                after: cursor
            )
            currentRequest = request
            observationTask = Task { [weak self] in
                await self?.observe(
                    runtime: runtime,
                    request: request,
                    generation: activeGeneration
                )
            }
        } catch let failure as ProjectNoteDataFailure {
            status = "blocked • completeness unknown"
            diagnostic = failure.diagnosticCode
        } catch {
            status = "blocked • completeness unknown"
            diagnostic = ProjectNoteDataFailure.localReadFailed.diagnosticCode
        }
    }

    private func observe(
        runtime: ProjectBrowsingStagingRuntime,
        request: ProjectNotePageRequest,
        generation: UInt64
    ) async {
        var iterator = runtime.watchNotes(request).makeAsyncIterator()
        do {
            while let page = try await iterator.next() {
                try Task.checkCancellation()
                guard self.generation == generation,
                      currentRequest == request,
                      selectedProjectId == request.projectId else { return }
                guard page.request == request else {
                    throw ProjectNoteDataFailure.requestMismatch
                }
                rows = page.local.rows.map(ProjectNoteHistoryRowPresentation.init)
                nextCursor = page.nextCursor
                hasOlderNotes = page.nextCursor != nil
                isAuthoritativelyEmpty = page.local.quality == .ready
                    && page.isCompleteForProjectHistory
                    && page.local.rows.isEmpty
                let completeness = page.isCompleteForProjectHistory ? "complete" : "incomplete"
                status = "\(page.local.quality.rawValue) • \(completeness)"
                diagnostic = nil
            }
            guard !Task.isCancelled,
                  self.generation == generation else { return }
            status = "blocked • completeness unknown"
            diagnostic = "project_note_source_completed"
        } catch is CancellationError {
            guard !Task.isCancelled,
                  self.generation == generation,
                  currentRequest == request,
                  selectedProjectId == request.projectId else { return }
            rows = []
            nextCursor = nil
            hasOlderNotes = false
            isAuthoritativelyEmpty = false
            status = "blocked • completeness unknown"
            diagnostic = "project_note_source_cancelled"
        } catch let failure as ProjectNoteDataFailure {
            guard self.generation == generation else { return }
            rows = []
            nextCursor = nil
            hasOlderNotes = false
            isAuthoritativelyEmpty = false
            status = "blocked • completeness unknown"
            diagnostic = failure.diagnosticCode
        } catch {
            guard self.generation == generation else { return }
            rows = []
            nextCursor = nil
            hasOlderNotes = false
            isAuthoritativelyEmpty = false
            status = "blocked • completeness unknown"
            diagnostic = ProjectNoteDataFailure.localReadFailed.diagnosticCode
        }
    }
}
