import Foundation
import LedgerTargetCore
import Observation

public struct ClientBrowsingStagingRuntime: Sendable {
    public typealias ClientDirectoryWatch = @Sendable ()
        -> AsyncThrowingStream<ClientListSnapshot, Error>
    public typealias ClientDetailWatch = @Sendable (ClientCoreDetailsRequest)
        -> AsyncThrowingStream<ClientCoreDetailsUpdate, Error>

    private let directoryWatch: ClientDirectoryWatch
    private let detailWatch: ClientDetailWatch

    public init(
        watchClients: @escaping ClientDirectoryWatch,
        watchClient: @escaping ClientDetailWatch
    ) {
        directoryWatch = watchClients
        detailWatch = watchClient
    }

    public func watchClients() -> AsyncThrowingStream<ClientListSnapshot, Error> {
        directoryWatch()
    }

    public func watchClient(
        _ request: ClientCoreDetailsRequest
    ) -> AsyncThrowingStream<ClientCoreDetailsUpdate, Error> {
        detailWatch(request)
    }
}

@MainActor
@Observable
public final class ClientBrowsingStagingExercise {
    public var activeClients: [ClientDirectoryCoreRow] {
        directoryViewState.presentation?.active.rows ?? []
    }

    public var archivedClients: [ClientDirectoryCoreRow] {
        directoryViewState.presentation?.archived.rows ?? []
    }

    public var activeClientCountLabel: String {
        directoryViewState.presentation.map { String($0.active.rows.count) } ?? "unknown"
    }

    public var archivedClientCountLabel: String {
        directoryViewState.presentation.map { String($0.archived.rows.count) } ?? "unknown"
    }

    public var directoryPresentation: ClientBrowsingDirectoryPresentation? {
        directoryViewState.presentation
    }

    public var directoryStatus: String { directoryViewState.status }
    public var directoryDiagnostic: String? { directoryViewState.diagnostic?.rawValue }

    public var selectedClient: ClientDirectoryCoreRow? { detailViewState.selection }
    public var selectedClientId: ClientID? { selectedClient?.clientId }
    public var selectedClientName: String? {
        detailViewState.presentation?.state.content?.displayName.rawValue
            ?? selectedClient?.displayName.rawValue
    }
    public var detailPresentation: ClientDetailPresentation? {
        detailViewState.presentation
    }
    public var detailStateLabel: String { detailViewState.stateLabel }
    public var detailReadiness: String { detailViewState.readinessLabel }
    public var detailDiagnostic: String? { detailViewState.diagnostic?.rawValue }

    public var selectedClientArchiveEvidence: ClientArchiveBrowserEvidence? {
        guard let selection = detailViewState.selection,
              let content = detailViewState.presentation?.state.content,
              let revision = selectedClientRevision,
              selection.lifecycle == .active,
              content.lifecycle == .active,
              content.clientId == selection.clientId,
              content.displayName == selection.displayName,
              directoryViewState.presentation?.active.rows.first(where: {
                  $0.clientId == selection.clientId
              }) == selection else {
            return nil
        }
        return ClientArchiveBrowserEvidence(
            accountId: accountId,
            clientId: selection.clientId,
            expectedRevision: revision,
            selectionGeneration: detailGeneration
        )
    }

    private let accountId: AccountID
    private var runtime: ClientBrowsingStagingRuntime?
    private var directoryViewState: DirectoryViewState = .loading
    private var detailViewState: DetailViewState = .notSelected
    private var directoryTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private var selectedClientRevision: ExpectedClientRevision?
    private var lifecycleGeneration: UInt64 = 0
    private var detailGeneration: UInt64 = 0

    public init(accountId: AccountID) {
        self.accountId = accountId
    }

    public func start(runtime: ClientBrowsingStagingRuntime) async {
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
        selectedClientRevision = nil
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
        selectedClientRevision = nil
        oldDirectoryTask?.cancel()
        oldDetailTask?.cancel()
        await oldDetailTask?.value
        await oldDirectoryTask?.value

        guard lifecycleGeneration == activeGeneration else { return }
    }

    public func select(clientId: ClientID, segment: ClientDirectorySegment) async {
        let lifecycle = lifecycleGeneration
        let capturedSelection: Result<ClientBrowsingSelection, Error> = Result {
            guard let snapshot = snapshot(for: segment) else {
                throw SelectionFailure.directoryNotRepresented
            }
            return try snapshot.selection(clientId: clientId)
        }

        detailGeneration &+= 1
        let selectionGeneration = detailGeneration
        let oldDetailTask = detailTask
        detailTask = nil
        detailViewState = .notSelected
        selectedClientRevision = nil
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
            detailViewState = .blocked(selection: nil, diagnostic: .selectionInvalid)
        }
    }

    private func observeDirectory(
        _ runtime: ClientBrowsingStagingRuntime,
        generation: UInt64
    ) async {
        var iterator = runtime.watchClients().makeAsyncIterator()
        do {
            while let snapshot = try await iterator.next() {
                guard !Task.isCancelled else { return }
                do {
                    guard snapshot.accountId == accountId else {
                        throw ClientProjectDirectoryFailure.accountScopeMismatch
                    }
                    let presentation = try ClientDirectoryPresentationProjector.project(snapshot)
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
        _ runtime: ClientBrowsingStagingRuntime,
        request: ClientCoreDetailsRequest,
        selection: ClientDirectoryCoreRow,
        lifecycleGeneration: UInt64,
        detailGeneration: UInt64
    ) async {
        var iterator = runtime.watchClient(request).makeAsyncIterator()
        do {
            while let update = try await iterator.next() {
                guard !Task.isCancelled else { return }
                do {
                    let presentation = try ClientDetailPresentationProjector.project(
                        update,
                        validating: request
                    )
                    guard self.lifecycleGeneration == lifecycleGeneration,
                          self.detailGeneration == detailGeneration else {
                        return
                    }
                    selectedClientRevision = Self.locallyObservedRevision(from: update)
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

    private func failDirectory(_ diagnostic: DirectoryDiagnostic, generation: UInt64) async {
        guard lifecycleGeneration == generation else { return }
        directoryViewState = .blocked(diagnostic)

        detailGeneration &+= 1
        let invalidationGeneration = detailGeneration
        let oldDetailTask = detailTask
        detailTask = nil
        detailViewState = .notSelected
        selectedClientRevision = nil
        oldDetailTask?.cancel()
        await oldDetailTask?.value

        guard lifecycleGeneration == generation,
              detailGeneration == invalidationGeneration else { return }
    }

    private func failDetail(
        _ diagnostic: DetailDiagnostic,
        selection: ClientDirectoryCoreRow,
        lifecycleGeneration: UInt64,
        detailGeneration: UInt64
    ) {
        guard self.lifecycleGeneration == lifecycleGeneration,
              self.detailGeneration == detailGeneration else { return }
        selectedClientRevision = nil
        detailViewState = .blocked(selection: selection, diagnostic: diagnostic)
    }

    private static func locallyObservedRevision(
        from update: ClientCoreDetailsUpdate
    ) -> ExpectedClientRevision? {
        switch update.state {
        case .waiting: nil
        case .snapshot(let snapshot): snapshot.row?.locallyObservedRevision
        case .failed(_, let cached): cached?.row?.locallyObservedRevision
        }
    }

    private func snapshot(for segment: ClientDirectorySegment)
        -> ClientDirectoryPresentationSnapshot?
    {
        guard let presentation = directoryViewState.presentation else { return nil }
        switch segment {
        case .active: return presentation.active
        case .archived: return presentation.archived
        }
    }
}

private extension ClientBrowsingStagingExercise {
    enum SelectionFailure: Error { case directoryNotRepresented }

    enum DirectoryDiagnostic: String, Sendable {
        case invalidEvidence = "client_directory_evidence_invalid"
        case localReadFailed = "client_directory_local_failed"
        case sourceCancelled = "client_directory_source_cancelled"
        case sourceCompleted = "client_directory_source_completed"
    }

    enum DetailDiagnostic: String, Sendable {
        case selectionInvalid = "client_detail_selection_invalid"
        case invalidEvidence = "client_detail_evidence_invalid"
        case localReadFailed = "client_detail_local_failed"
        case sourceCancelled = "client_detail_source_cancelled"
        case sourceCompleted = "client_detail_source_completed"
    }

    enum DirectoryViewState: Sendable {
        case loading
        case represented(ClientBrowsingDirectoryPresentation)
        case blocked(DirectoryDiagnostic)
        case stopped

        var presentation: ClientBrowsingDirectoryPresentation? {
            guard case .represented(let presentation) = self else { return nil }
            return presentation
        }

        var diagnostic: DirectoryDiagnostic? {
            guard case .blocked(let diagnostic) = self else { return nil }
            return diagnostic
        }

        var status: String {
            switch self {
            case .loading: "loading • completeness unknown"
            case .represented(let presentation):
                "\(presentation.readiness.rawValue) • "
                    + "\(presentation.isCompleteForQuery ? "complete" : "incomplete") • "
                    + "\(presentation.isSourceExhaustive ? "source exhaustive" : "source nonexhaustive")"
            case .blocked: "blocked • completeness unknown"
            case .stopped: "stopped • completeness unknown"
            }
        }
    }

    enum DetailViewState: Sendable {
        case notSelected
        case awaiting(ClientDirectoryCoreRow)
        case represented(selection: ClientDirectoryCoreRow, presentation: ClientDetailPresentation)
        case blocked(selection: ClientDirectoryCoreRow?, diagnostic: DetailDiagnostic)
        case stopped

        var selection: ClientDirectoryCoreRow? {
            switch self {
            case .awaiting(let selection), .represented(let selection, _),
                 .blocked(.some(let selection), _): selection
            case .notSelected, .blocked(.none, _), .stopped: nil
            }
        }

        var presentation: ClientDetailPresentation? {
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
                case .waiting(let readiness), .incomplete(let readiness): readiness.rawValue
                case .found(let content): content.readiness.rawValue
                case .authoritativeAbsence: ListReadiness.ready.rawValue
                case .unavailable: ListReadiness.blocked.rawValue
                case .retryable(cached: .some(let content)),
                     .requiredUpdate(cached: .some(let content)): content.readiness.rawValue
                case .retryable(cached: .none), .requiredUpdate(cached: .none):
                    ListReadiness.blocked.rawValue
                }
            }
        }
    }
}
