import Foundation
import LedgerTargetCore
import Observation

public struct ProjectBrowsingStagingRuntime: Sendable {
    public typealias ProjectDirectoryWatch = @Sendable ()
        -> AsyncThrowingStream<ProjectListSnapshot, Error>
    public typealias ProjectDetailWatch = @Sendable (ProjectCoreDetailsRequest)
        -> AsyncThrowingStream<ProjectCoreDetailsUpdate, Error>

    private let directoryWatch: ProjectDirectoryWatch
    private let detailWatch: ProjectDetailWatch

    public init(
        watchProjects: @escaping ProjectDirectoryWatch,
        watchProject: @escaping ProjectDetailWatch
    ) {
        directoryWatch = watchProjects
        detailWatch = watchProject
    }

    public func watchProjects() -> AsyncThrowingStream<ProjectListSnapshot, Error> {
        directoryWatch()
    }

    public func watchProject(
        _ request: ProjectCoreDetailsRequest
    ) -> AsyncThrowingStream<ProjectCoreDetailsUpdate, Error> {
        detailWatch(request)
    }
}

/// The two segment projections produced from one directory emission.
///
/// Keeping them in one value prevents the UI from observing an active segment
/// from one local revision and an archived segment from another.
public struct ProjectBrowsingDirectoryPresentation: Equatable, Sendable {
    public let active: ProjectDirectoryPresentationSnapshot
    public let archived: ProjectDirectoryPresentationSnapshot

    fileprivate init(snapshot: ProjectListSnapshot) throws {
        active = try ProjectDirectoryPresentationProjector.project(snapshot, segment: .active)
        archived = try ProjectDirectoryPresentationProjector.project(snapshot, segment: .archived)
    }

    public var readiness: ListReadiness { active.readiness }
    public var isCompleteForQuery: Bool { active.isCompleteForQuery }
    public var isSourceExhaustive: Bool { active.isSourceExhaustive }
}

@MainActor
@Observable
public final class ProjectBrowsingStagingExercise {
    public var activeProjects: [ProjectDirectoryCoreRow] {
        directoryViewState.presentation?.active.rows ?? []
    }

    public var archivedProjects: [ProjectDirectoryCoreRow] {
        directoryViewState.presentation?.archived.rows ?? []
    }

    /// A numeric count is presentation authority only after a validated
    /// directory snapshot exists. Loading, blocked, and stopped states must not
    /// look like an authoritative empty directory.
    public var activeProjectCountLabel: String {
        directoryViewState.presentation.map { String($0.active.rows.count) } ?? "unknown"
    }

    public var archivedProjectCountLabel: String {
        directoryViewState.presentation.map { String($0.archived.rows.count) } ?? "unknown"
    }

    public var directoryPresentation: ProjectBrowsingDirectoryPresentation? {
        directoryViewState.presentation
    }

    public var directoryStatus: String { directoryViewState.status }
    public var directoryDiagnostic: String? { directoryViewState.diagnostic?.rawValue }

    public var selectedProject: ProjectDirectoryCoreRow? { detailViewState.selection }
    public var selectedProjectId: ProjectID? { selectedProject?.projectId }
    public var selectedClientId: ClientID? { selectedProject?.clientId }
    public var selectedProjectName: String? {
        detailViewState.presentation?.state.content?.projectDisplayName.rawValue
            ?? selectedProject?.projectDisplayName.rawValue
    }
    public var selectedClientName: String? {
        detailViewState.presentation?.state.content?.clientDisplayName.rawValue
            ?? selectedProject?.clientDisplayName.rawValue
    }
    public var detailPresentation: ProjectDetailHeaderPresentation? {
        detailViewState.presentation
    }
    public var detailStateLabel: String { detailViewState.stateLabel }
    public var detailReadiness: String { detailViewState.readinessLabel }
    public var detailDiagnostic: String? { detailViewState.diagnostic?.rawValue }

    private let accountId: AccountID
    private var runtime: ProjectBrowsingStagingRuntime?
    private var directoryViewState: DirectoryViewState = .loading
    private var detailViewState: DetailViewState = .notSelected
    private var directoryTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private var lifecycleGeneration: UInt64 = 0
    private var detailGeneration: UInt64 = 0

    public init(accountId: AccountID) {
        self.accountId = accountId
    }

    public func start(runtime: ProjectBrowsingStagingRuntime) async {
        lifecycleGeneration &+= 1
        detailGeneration &+= 1
        let activeGeneration = lifecycleGeneration
        let oldDirectoryTask = directoryTask
        let oldDetailTask = detailTask

        directoryTask = nil
        detailTask = nil
        self.runtime = nil
        directoryViewState = .loading
        detailViewState = .notSelected
        oldDirectoryTask?.cancel()
        oldDetailTask?.cancel()
        await oldDetailTask?.value
        await oldDirectoryTask?.value

        guard lifecycleGeneration == activeGeneration else { return }
        self.runtime = runtime
        directoryTask = Task { [weak self] in
            await self?.observeDirectory(runtime, generation: activeGeneration)
        }
    }

    public func stop() async {
        lifecycleGeneration &+= 1
        detailGeneration &+= 1
        let activeGeneration = lifecycleGeneration
        let oldDirectoryTask = directoryTask
        let oldDetailTask = detailTask

        directoryTask = nil
        detailTask = nil
        runtime = nil
        directoryViewState = .stopped
        detailViewState = .stopped
        oldDirectoryTask?.cancel()
        oldDetailTask?.cancel()
        await oldDetailTask?.value
        await oldDirectoryTask?.value

        guard lifecycleGeneration == activeGeneration else { return }
    }

    public func select(
        projectId: ProjectID,
        segment: ProjectDirectorySegment
    ) async {
        let lifecycle = lifecycleGeneration
        let capturedSelection: Result<ProjectBrowsingSelection, Error> = Result {
            guard let snapshot = snapshot(for: segment) else {
                throw SelectionFailure.directoryNotRepresented
            }
            return try snapshot.selection(projectId: projectId)
        }

        detailGeneration &+= 1
        let selectionGeneration = detailGeneration
        let oldDetailTask = detailTask
        detailTask = nil
        detailViewState = .notSelected
        oldDetailTask?.cancel()
        await oldDetailTask?.value

        guard lifecycleGeneration == lifecycle,
              detailGeneration == selectionGeneration,
              let runtime else {
            return
        }

        do {
            let selection = try capturedSelection.get()
            guard let currentSnapshot = snapshot(for: segment) else {
                throw SelectionFailure.directoryNotRepresented
            }
            let request = try selection.detailRequest(validating: currentSnapshot)
            detailViewState = .awaiting(selection.row)
            detailTask = Task { [weak self] in
                await self?.observeDetail(
                    runtime,
                    request: request,
                    selection: selection.row,
                    lifecycleGeneration: lifecycle,
                    detailGeneration: selectionGeneration
                )
            }
        } catch {
            detailViewState = .blocked(
                selection: nil,
                diagnostic: .selectionInvalid
            )
        }
    }

    private func observeDirectory(
        _ runtime: ProjectBrowsingStagingRuntime,
        generation: UInt64
    ) async {
        var iterator = runtime.watchProjects().makeAsyncIterator()
        do {
            while let snapshot = try await iterator.next() {
                guard !Task.isCancelled else { return }
                do {
                    guard snapshot.accountId == accountId else {
                        throw ClientProjectDirectoryFailure.accountScopeMismatch
                    }
                    let presentation = try ProjectBrowsingDirectoryPresentation(
                        snapshot: snapshot
                    )
                    guard presentation.active.accountId == accountId,
                          presentation.archived.accountId == accountId else {
                        throw ClientProjectDirectoryFailure.accountScopeMismatch
                    }
                    guard lifecycleGeneration == generation else { return }
                    directoryViewState = .represented(presentation)
                } catch {
                    directoryTask?.cancel()
                    _ = try? await iterator.next()
                    await failDirectory(.invalidEvidence, generation: generation)
                    return
                }
            }
            guard !Task.isCancelled else { return }
            await failDirectory(.sourceCompleted, generation: generation)
        } catch is CancellationError {
            guard !Task.isCancelled else { return }
            await failDirectory(.sourceCancelled, generation: generation)
        } catch {
            await failDirectory(.localReadFailed, generation: generation)
        }
    }

    private func observeDetail(
        _ runtime: ProjectBrowsingStagingRuntime,
        request: ProjectCoreDetailsRequest,
        selection: ProjectDirectoryCoreRow,
        lifecycleGeneration: UInt64,
        detailGeneration: UInt64
    ) async {
        var iterator = runtime.watchProject(request).makeAsyncIterator()
        do {
            while let update = try await iterator.next() {
                guard !Task.isCancelled else { return }
                do {
                    let presentation = try ProjectDetailHeaderPresentationProjector.project(
                        update,
                        validating: request
                    )
                    guard self.lifecycleGeneration == lifecycleGeneration,
                          self.detailGeneration == detailGeneration else {
                        return
                    }
                    detailViewState = .represented(
                        selection: selection,
                        presentation: presentation
                    )
                } catch {
                    failDetail(
                        .invalidEvidence,
                        selection: selection,
                        lifecycleGeneration: lifecycleGeneration,
                        detailGeneration: detailGeneration
                    )
                    detailTask?.cancel()
                    _ = try? await iterator.next()
                    return
                }
            }
            guard !Task.isCancelled else { return }
            failDetail(
                .sourceCompleted,
                selection: selection,
                lifecycleGeneration: lifecycleGeneration,
                detailGeneration: detailGeneration
            )
        } catch is CancellationError {
            guard !Task.isCancelled else { return }
            failDetail(
                .sourceCancelled,
                selection: selection,
                lifecycleGeneration: lifecycleGeneration,
                detailGeneration: detailGeneration
            )
        } catch {
            failDetail(
                .localReadFailed,
                selection: selection,
                lifecycleGeneration: lifecycleGeneration,
                detailGeneration: detailGeneration
            )
        }
    }

    private func failDirectory(
        _ diagnostic: DirectoryDiagnostic,
        generation: UInt64
    ) async {
        guard lifecycleGeneration == generation else { return }
        directoryViewState = .blocked(diagnostic)

        detailGeneration &+= 1
        let invalidationGeneration = detailGeneration
        let oldDetailTask = detailTask
        detailTask = nil
        detailViewState = .notSelected
        oldDetailTask?.cancel()
        await oldDetailTask?.value

        guard lifecycleGeneration == generation,
              detailGeneration == invalidationGeneration else {
            return
        }
    }

    private func failDetail(
        _ diagnostic: DetailDiagnostic,
        selection: ProjectDirectoryCoreRow,
        lifecycleGeneration: UInt64,
        detailGeneration: UInt64
    ) {
        guard self.lifecycleGeneration == lifecycleGeneration,
              self.detailGeneration == detailGeneration else {
            return
        }
        detailViewState = .blocked(selection: selection, diagnostic: diagnostic)
    }

    private func snapshot(
        for segment: ProjectDirectorySegment
    ) -> ProjectDirectoryPresentationSnapshot? {
        guard let presentation = directoryViewState.presentation else { return nil }
        switch segment {
        case .active: return presentation.active
        case .archived: return presentation.archived
        }
    }
}

private extension ProjectBrowsingStagingExercise {
    enum SelectionFailure: Error {
        case directoryNotRepresented
    }

    enum DirectoryDiagnostic: String, Sendable {
        case invalidEvidence = "project_directory_evidence_invalid"
        case localReadFailed = "project_directory_local_failed"
        case sourceCancelled = "project_directory_source_cancelled"
        case sourceCompleted = "project_directory_source_completed"
    }

    enum DetailDiagnostic: String, Sendable {
        case selectionInvalid = "project_detail_selection_invalid"
        case invalidEvidence = "project_detail_evidence_invalid"
        case localReadFailed = "project_detail_local_failed"
        case sourceCancelled = "project_detail_source_cancelled"
        case sourceCompleted = "project_detail_source_completed"
    }

    enum DirectoryViewState: Sendable {
        case loading
        case represented(ProjectBrowsingDirectoryPresentation)
        case blocked(DirectoryDiagnostic)
        case stopped

        var presentation: ProjectBrowsingDirectoryPresentation? {
            guard case .represented(let presentation) = self else { return nil }
            return presentation
        }

        var diagnostic: DirectoryDiagnostic? {
            guard case .blocked(let diagnostic) = self else { return nil }
            return diagnostic
        }

        var status: String {
            switch self {
            case .loading:
                "loading • completeness unknown"
            case .represented(let presentation):
                "\(presentation.readiness.rawValue) • "
                    + "\(presentation.isCompleteForQuery ? "complete" : "incomplete") • "
                    + "\(presentation.isSourceExhaustive ? "source exhaustive" : "source nonexhaustive")"
            case .blocked:
                "blocked • completeness unknown"
            case .stopped:
                "stopped • completeness unknown"
            }
        }
    }

    enum DetailViewState: Sendable {
        case notSelected
        case awaiting(ProjectDirectoryCoreRow)
        case represented(
            selection: ProjectDirectoryCoreRow,
            presentation: ProjectDetailHeaderPresentation
        )
        case blocked(selection: ProjectDirectoryCoreRow?, diagnostic: DetailDiagnostic)
        case stopped

        var selection: ProjectDirectoryCoreRow? {
            switch self {
            case .awaiting(let selection),
                 .represented(let selection, _),
                 .blocked(.some(let selection), _):
                selection
            case .notSelected, .blocked(.none, _), .stopped:
                nil
            }
        }

        var presentation: ProjectDetailHeaderPresentation? {
            guard case .represented(_, let presentation) = self else { return nil }
            return presentation
        }

        var diagnostic: DetailDiagnostic? {
            guard case .blocked(_, let diagnostic) = self else { return nil }
            return diagnostic
        }

        var stateLabel: String {
            switch self {
            case .notSelected: "not selected"
            case .awaiting: "awaiting local evidence"
            case .stopped: "stopped"
            case .blocked: "blocked"
            case .represented(_, let presentation):
                switch presentation.state {
                case .waiting: "waiting"
                case .found: "found"
                case .incomplete: "incomplete"
                case .authoritativeAbsence: "authoritative absence"
                case .unavailable: "unavailable"
                case .retryable(cached: .some): "retryable • cached"
                case .retryable(cached: .none): "retryable • uncached"
                case .requiredUpdate(cached: .some): "required update • cached"
                case .requiredUpdate(cached: .none): "required update • uncached"
                }
            }
        }

        var readinessLabel: String {
            switch self {
            case .notSelected: ListReadiness.notRequested.rawValue
            case .awaiting: ListReadiness.loading.rawValue
            case .stopped, .blocked: ListReadiness.blocked.rawValue
            case .represented(_, let presentation):
                switch presentation.state {
                case .waiting(let readiness), .incomplete(let readiness):
                    readiness.rawValue
                case .found(let content):
                    content.readiness.rawValue
                case .authoritativeAbsence:
                    ListReadiness.ready.rawValue
                case .unavailable:
                    ListReadiness.blocked.rawValue
                case .retryable(cached: .some(let content)),
                     .requiredUpdate(cached: .some(let content)):
                    content.readiness.rawValue
                case .retryable(cached: .none), .requiredUpdate(cached: .none):
                    ListReadiness.blocked.rawValue
                }
            }
        }
    }
}
