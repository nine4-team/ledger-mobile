import Foundation
import LedgerTargetCore
import Observation

public struct SpaceBrowserStagingRuntime: Sendable {
    fileprivate let listQuery: any SpaceListQuerying
    fileprivate let detailQuery: any SpaceCoreDetailsQuerying

    public init(
        listQuery: any SpaceListQuerying,
        detailQuery: any SpaceCoreDetailsQuerying
    ) {
        self.listQuery = listQuery
        self.detailQuery = detailQuery
    }
}

public struct SpaceBrowserFailure: Equatable, Sendable {
    public let diagnosticCode: String

    fileprivate init(_ diagnosticCode: String) {
        self.diagnosticCode = diagnosticCode
    }
}

public enum SpaceBrowserDirectoryPresentation: Equatable, Sendable {
    case waiting(ListReadiness)
    case partial(ActiveSpaceDirectoryPresentationSnapshot)
    case stale(ActiveSpaceDirectoryPresentationSnapshot)
    case ready(ActiveSpaceDirectoryPresentationSnapshot)
    case authoritativeEmpty
    case failure(
        SpaceBrowserFailure,
        cached: ActiveSpaceDirectoryPresentationSnapshot?
    )
    case stopped

    public var snapshot: ActiveSpaceDirectoryPresentationSnapshot? {
        switch self {
        case .partial(let snapshot), .stale(let snapshot), .ready(let snapshot): snapshot
        case .failure(_, let cached): cached
        case .waiting, .authoritativeEmpty, .stopped: nil
        }
    }

    public var rows: [SpaceDirectoryRowPresentation] { snapshot?.rows ?? [] }
}

/// The selected detail is always the existing core-details presenter. This
/// wrapper only adds browser selection identity and an explicit unavailable
/// state; it does not project a second copy of detail evidence.
public enum SpaceBrowserDetailPresentation: Equatable, Sendable {
    case notSelected
    case selected(
        selection: SpaceDirectoryRowPresentation,
        presentation: SpaceCoreDetailsStagingPresentation
    )
    case unavailable(previousSelection: SpaceDirectoryRowPresentation?)
    case stopped

    public var selectedRow: SpaceDirectoryRowPresentation? {
        switch self {
        case .selected(let row, _): row
        case .unavailable(let row): row
        case .notSelected, .stopped: nil
        }
    }

    public var detail: SpaceCoreDetailsSnapshot? {
        guard case .selected(_, let presentation) = self else { return nil }
        return presentation.row
    }
}

@MainActor
@Observable
public final class SpaceBrowserStagingExercise {
    public private(set) var scope: SpaceCreationScope?
    public private(set) var directoryPresentation: SpaceBrowserDirectoryPresentation =
        .waiting(.notRequested)
    public let detailModel: SpaceCoreDetailsStagingExercise

    public var spaces: [SpaceDirectoryRowPresentation] { directoryPresentation.rows }
    public var detailPresentation: SpaceBrowserDetailPresentation {
        if isStopped { return .stopped }
        if isSelectionUnavailable {
            return .unavailable(previousSelection: unavailableSelection)
        }
        guard let selection else { return .notSelected }
        if detailModel.isAuthoritativelyEmpty {
            return .unavailable(previousSelection: selection.row)
        }
        return .selected(selection: selection.row, presentation: detailModel.presentation)
    }
    public var selectedSpace: SpaceDirectoryRowPresentation? {
        detailPresentation.selectedRow
    }
    public var selectedSpaceId: SpaceID? { selectedSpace?.id }
    public var detail: SpaceCoreDetailsSnapshot? { detailPresentation.detail }
    public var directoryDiagnostic: String? {
        guard case .failure(let failure, _) = directoryPresentation else { return nil }
        return failure.diagnosticCode
    }

    private let accountId: AccountID
    private var runtime: SpaceBrowserStagingRuntime?
    private var selection: SpaceBrowsingSelection?
    private var unavailableSelection: SpaceDirectoryRowPresentation?
    private var isSelectionUnavailable = false
    private var directoryTask: Task<Void, Never>?
    private var detailAdapter: SelectionBoundSpaceDetailsRuntime?
    private var directoryGeneration: UInt64 = 0
    private var selectionGeneration: UInt64 = 0
    private var isStopped = false

    public init(accountId: AccountID) {
        self.accountId = accountId
        detailModel = SpaceCoreDetailsStagingExercise(accountId: accountId)
    }

    public func start(
        scope: SpaceCreationScope,
        runtime: SpaceBrowserStagingRuntime
    ) async {
        directoryGeneration &+= 1
        selectionGeneration &+= 1
        let generation = directoryGeneration
        let oldDirectory = directoryTask
        let oldAdapter = detailAdapter

        directoryTask = nil
        detailAdapter = nil
        self.runtime = nil
        self.scope = scope
        selection = nil
        unavailableSelection = nil
        isSelectionUnavailable = false
        isStopped = false
        directoryPresentation = .waiting(.loading)
        oldDirectory?.cancel()
        await detailModel.clear()
        await oldAdapter?.cancelAndDrain()
        await oldDirectory?.value

        guard directoryGeneration == generation, self.scope == scope else { return }
        let request: SpaceListRequest
        do {
            request = try SpaceListRequest(accountId: accountId, scope: scope)
        } catch {
            directoryPresentation = .failure(
                SpaceBrowserFailure(SpaceListFailure.localReadFailed.diagnosticCode),
                cached: nil
            )
            return
        }
        self.runtime = runtime
        directoryTask = Task { [weak self] in
            await self?.observeDirectory(runtime, request: request, generation: generation)
        }
    }

    public func select(spaceId: SpaceID) async {
        let directoryGeneration = directoryGeneration
        let captured: Result<SpaceBrowsingSelection, Error> = Result {
            guard let directory = directoryPresentation.snapshot else {
                throw SpaceBrowserInternalFailure.notRepresented
            }
            return try SpaceBrowsingSelection(selecting: spaceId, in: directory)
        }

        selectionGeneration &+= 1
        let generation = selectionGeneration
        let oldAdapter = detailAdapter
        detailAdapter = nil
        selection = nil
        unavailableSelection = nil
        isSelectionUnavailable = false
        await detailModel.clear()
        await oldAdapter?.cancelAndDrain()

        guard self.directoryGeneration == directoryGeneration,
              selectionGeneration == generation,
              let runtime else { return }
        do {
            let selection = try captured.get()
            guard let currentDirectory = directoryPresentation.snapshot else {
                throw SpaceBrowserInternalFailure.notRepresented
            }
            _ = try selection.detailRequest(validating: currentDirectory)
            let adapter = SelectionBoundSpaceDetailsRuntime(
                selection: selection,
                query: runtime.detailQuery
            )
            self.selection = selection
            detailAdapter = adapter
            await detailModel.select(spaceId: selection.row.id, runtime: adapter)
        } catch {
            isSelectionUnavailable = true
            unavailableSelection = nil
        }
    }

    public func clearSelection() async {
        selectionGeneration &+= 1
        let oldAdapter = detailAdapter
        detailAdapter = nil
        selection = nil
        unavailableSelection = nil
        isSelectionUnavailable = false
        await detailModel.clear()
        await oldAdapter?.cancelAndDrain()
    }

    public func stop() async {
        directoryGeneration &+= 1
        selectionGeneration &+= 1
        let oldDirectory = directoryTask
        let oldAdapter = detailAdapter
        directoryTask = nil
        detailAdapter = nil
        runtime = nil
        scope = nil
        selection = nil
        unavailableSelection = nil
        isSelectionUnavailable = false
        isStopped = true
        directoryPresentation = .stopped
        oldDirectory?.cancel()
        await detailModel.stop()
        await oldAdapter?.cancelAndDrain()
        await oldDirectory?.value
    }

    private func observeDirectory(
        _ runtime: SpaceBrowserStagingRuntime,
        request: SpaceListRequest,
        generation: UInt64
    ) async {
        do {
            for try await update in runtime.listQuery.watchSpaces(request) {
                try Task.checkCancellation()
                let validated = try update.validating(request: request)
                let projected = try Self.projectDirectory(validated)
                guard directoryGeneration == generation else { return }
                directoryPresentation = projected
                await reconcileSelection(with: projected, generation: generation)
            }
            guard !Task.isCancelled, directoryGeneration == generation else { return }
            directoryPresentation = .failure(
                SpaceBrowserFailure(Self.directorySourceCompleted), cached: nil
            )
        } catch is CancellationError {
            guard !Task.isCancelled, directoryGeneration == generation else { return }
            directoryPresentation = .failure(
                SpaceBrowserFailure(Self.directorySourceCancelled), cached: nil
            )
        } catch let failure as SpaceListFailure {
            guard directoryGeneration == generation else { return }
            directoryPresentation = .failure(SpaceBrowserFailure(failure.diagnosticCode), cached: nil)
        } catch {
            guard directoryGeneration == generation else { return }
            directoryPresentation = .failure(
                SpaceBrowserFailure(SpaceListFailure.localReadFailed.diagnosticCode), cached: nil
            )
        }
    }

    private static func projectDirectory(
        _ update: SpaceListUpdate
    ) throws -> SpaceBrowserDirectoryPresentation {
        switch try update.presentingActiveDirectory() {
        case .waiting(let readiness):
            return .waiting(readiness)
        case .snapshot(let snapshot):
            switch snapshot.quality {
            case .partial: return .partial(snapshot)
            case .stale: return .stale(snapshot)
            case .ready:
                guard snapshot.isCompleteForQuery else {
                    throw SpaceListFailure.invalidCompleteness
                }
                return snapshot.isAuthoritativeEmpty ? .authoritativeEmpty : .ready(snapshot)
            }
        case .failed(let failure, let cached):
            return .failure(
                SpaceBrowserFailure("space_list_\(failure.rawValue)"),
                cached: cached
            )
        }
    }

    private func reconcileSelection(
        with presentation: SpaceBrowserDirectoryPresentation,
        generation: UInt64
    ) async {
        guard directoryGeneration == generation, let oldSelection = selection else { return }
        if let directory = presentation.snapshot,
           directory.rows.contains(where: { $0.id == oldSelection.row.id }) {
            do {
                selection = try SpaceBrowsingSelection(
                    selecting: oldSelection.row.id,
                    in: directory
                )
            } catch {
                await makeSelectionUnavailable(oldSelection.row)
            }
            return
        }

        await makeSelectionUnavailable(oldSelection.row)
    }

    private func makeSelectionUnavailable(
        _ oldSelection: SpaceDirectoryRowPresentation
    ) async {
        selectionGeneration &+= 1
        let oldAdapter = detailAdapter
        detailAdapter = nil
        selection = nil
        unavailableSelection = oldSelection
        isSelectionUnavailable = true
        await detailModel.clear()
        await oldAdapter?.cancelAndDrain()
    }

    private static let directorySourceCompleted = "space_list_source_completed"
    private static let directorySourceCancelled = "space_list_source_cancelled"
}

private final class SelectionBoundSpaceDetailsRuntime: @unchecked Sendable,
    SpaceCoreDetailsStagingRuntime {
    private let selection: SpaceBrowsingSelection
    private let query: any SpaceCoreDetailsQuerying
    private let tasks = SelectionBoundTaskRegistry()

    init(selection: SpaceBrowsingSelection, query: any SpaceCoreDetailsQuerying) {
        self.selection = selection
        self.query = query
    }

    func watchSpaceCoreDetails(
        spaceId: SpaceID
    ) -> AsyncThrowingStream<SpaceCoreDetailsUpdate, Error> {
        guard spaceId == selection.row.id,
              let request = try? SpaceCoreDetailsRequest(
                accountId: selection.accountId,
                spaceId: spaceId
              ) else {
            return AsyncThrowingStream { $0.finish(throwing: SpaceListFailure.detailIdentityMismatch) }
        }
        let source = query.watchSpaceCoreDetails(request)
        return AsyncThrowingStream { continuation in
            let id = UUID()
            let handle = SelectionBoundTaskHandle()
            let registration = Task { await tasks.register(id: id, handle: handle) }
            let task = Task {
                let admitted = await registration.value
                guard admitted, !Task.isCancelled else {
                    continuation.finish()
                    if admitted { await tasks.finished(id: id) }
                    return
                }
                do {
                    for try await update in source {
                        try Task.checkCancellation()
                        let validated = try update.validating(request: request)
                        let result = try Self.validate(validated, selection: selection)
                        continuation.yield(result.update)
                        if result.terminatesObservation {
                            // Keep unavailable stable until explicit browser replacement.
                            await SelectionBoundCancellationGate().wait()
                            try Task.checkCancellation()
                            return
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                await tasks.finished(id: id)
            }
            handle.install(task)
            continuation.onTermination = { _ in handle.cancel() }
        }
    }

    func cancelAndDrain() async {
        await tasks.cancelAndDrain()
    }

    private static func validate(
        _ update: SpaceCoreDetailsUpdate,
        selection: SpaceBrowsingSelection
    ) throws -> SelectionBoundValidationResult {
        switch update.state {
        case .waiting:
            return SelectionBoundValidationResult(update: update, terminatesObservation: false)
        case .snapshot(let snapshot):
            guard let detail = snapshot.row else {
                return SelectionBoundValidationResult(update: update, terminatesObservation: false)
            }
            guard detail.lifecycle == .active else {
                return try unavailableResult(for: update.request, asOf: snapshot.local.asOf)
            }
            do {
                try selection.validateDetail(detail)
                return SelectionBoundValidationResult(update: update, terminatesObservation: false)
            } catch {
                return try unavailableResult(for: update.request, asOf: snapshot.local.asOf)
            }
        case .failed(_, let cached):
            guard let detail = cached?.row else {
                return SelectionBoundValidationResult(update: update, terminatesObservation: false)
            }
            guard detail.lifecycle == .active else {
                return try unavailableResult(for: update.request, asOf: cached!.local.asOf)
            }
            do {
                try selection.validateDetail(detail)
                return SelectionBoundValidationResult(update: update, terminatesObservation: false)
            } catch {
                return try unavailableResult(for: update.request, asOf: cached!.local.asOf)
            }
        }
    }

    private static func unavailableResult(
        for request: SpaceCoreDetailsRequest,
        asOf: Date
    ) throws -> SelectionBoundValidationResult {
        let snapshot = try SpaceCoreDetailsLocalSnapshot(
            request: request,
            rows: [],
            visibleRowCountBeforeFiltering: 0,
            isCompleteForQuery: true,
            quality: .ready,
            localDataVersion: LocalDataVersion(validating: "selection-unavailable"),
            asOf: asOf
        )
        return SelectionBoundValidationResult(
            update: try SpaceCoreDetailsUpdate(request: request, state: .snapshot(snapshot)),
            terminatesObservation: true
        )
    }
}

private struct SelectionBoundValidationResult {
    let update: SpaceCoreDetailsUpdate
    let terminatesObservation: Bool
}

private final class SelectionBoundTaskHandle: @unchecked Sendable {
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

private actor SelectionBoundTaskRegistry {
    private var handles: [UUID: SelectionBoundTaskHandle] = [:]
    private var closing = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func register(id: UUID, handle: SelectionBoundTaskHandle) -> Bool {
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
        let admitted = waiters
        waiters.removeAll()
        admitted.forEach { $0.resume() }
    }

    func cancelAndDrain() async {
        closing = true
        handles.values.forEach { $0.cancel() }
        guard !handles.isEmpty else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private final class SelectionBoundCancellationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var cancelled = false

    func wait() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let resumeImmediately = lock.withLock {
                    if cancelled || Task.isCancelled { return true }
                    self.continuation = continuation
                    return false
                }
                if resumeImmediately { continuation.resume() }
            }
        } onCancel: {
            cancel()
        }
    }

    private func cancel() {
        let continuation = lock.withLock {
            cancelled = true
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume()
    }
}

private enum SpaceBrowserInternalFailure: Error {
    case notRepresented
}
