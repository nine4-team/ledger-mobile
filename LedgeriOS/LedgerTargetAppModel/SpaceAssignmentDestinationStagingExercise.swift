import Foundation
import LedgerTargetCore
import Observation

public struct SpaceAssignmentDestinationStagingRuntime: Sendable {
    public typealias Watch = @Sendable (ItemPlacementScope)
        -> AsyncThrowingStream<SpaceAssignmentDestinationDirectorySnapshot, Error>
    private let watch: Watch
    public init(watch: @escaping Watch) { self.watch = watch }
    public func destinations(in scope: ItemPlacementScope)
        -> AsyncThrowingStream<SpaceAssignmentDestinationDirectorySnapshot, Error>
    { watch(scope) }
}

public enum SpaceAssignmentDestinationPresentation: Equatable, Sendable {
    case waiting
    case partial([SpaceAssignmentDestinationSnapshot])
    case stale([SpaceAssignmentDestinationSnapshot])
    case ready([SpaceAssignmentDestinationSnapshot])
    case authoritativeEmpty
    case failure(String)

    public var rows: [SpaceAssignmentDestinationSnapshot] {
        switch self {
        case .partial(let rows), .stale(let rows), .ready(let rows): rows
        default: []
        }
    }

    public var status: String {
        switch self {
        case .waiting: "waiting • completeness unknown"
        case .partial: "partial • local evidence"
        case .stale: "stale • local evidence"
        case .ready: "ready • local evidence complete"
        case .authoritativeEmpty: "empty • local evidence complete"
        case .failure: "failed • completeness unknown"
        }
    }
}

@MainActor
@Observable
public final class SpaceAssignmentDestinationStagingExercise {
    public private(set) var presentation: SpaceAssignmentDestinationPresentation = .waiting
    public var rows: [SpaceAssignmentDestinationSnapshot] { presentation.rows }
    public var status: String { presentation.status }
    public var diagnostic: String? {
        if case .failure(let code) = presentation { code } else { nil }
    }
    public var selectedSpaceId: SpaceID? {
        guard let selection,
              rows.contains(where: { $0.id == selection }) else { return nil }
        return selection
    }

    private let accountId: AccountID
    private var selection: SpaceID?
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0

    public init(accountId: AccountID) { self.accountId = accountId }

    public func open(
        scope: ItemPlacementScope,
        runtime: SpaceAssignmentDestinationStagingRuntime
    ) async {
        generation &+= 1
        let current = generation
        let old = task
        task = nil
        presentation = .waiting
        old?.cancel()
        await old?.value
        guard generation == current else { return }
        task = Task { [weak self] in
            await self?.observe(scope: scope, runtime: runtime, generation: current)
        }
    }

    public func stop() async {
        generation &+= 1
        let old = task
        task = nil
        old?.cancel()
        await old?.value
    }

    @discardableResult
    public func select(spaceId: SpaceID) -> Bool {
        guard rows.contains(where: { $0.id == spaceId }) else { return false }
        selection = spaceId
        return true
    }

    private func observe(
        scope: ItemPlacementScope,
        runtime: SpaceAssignmentDestinationStagingRuntime,
        generation: UInt64
    ) async {
        do {
            let expected = try SpaceAssignmentDestinationRequest(
                accountId: accountId, scope: scope
            )
            for try await directory in runtime.destinations(in: scope) {
                try Task.checkCancellation()
                guard directory.request == expected,
                      self.generation == generation else { return }
                presentation = Self.project(directory)
            }
            guard !Task.isCancelled, self.generation == generation else { return }
            presentation = .failure(SpaceAssignmentDestinationFailure.localReadFailed.diagnosticCode)
        } catch is CancellationError {
            return
        } catch let failure as SpaceAssignmentDestinationFailure {
            guard self.generation == generation else { return }
            presentation = .failure(failure.diagnosticCode)
        } catch {
            guard self.generation == generation else { return }
            presentation = .failure(SpaceAssignmentDestinationFailure.localReadFailed.diagnosticCode)
        }
    }

    private static func project(
        _ directory: SpaceAssignmentDestinationDirectorySnapshot
    ) -> SpaceAssignmentDestinationPresentation {
        let local = directory.local
        switch local.quality {
        case .partial: return .partial(local.rows)
        case .stale: return .stale(local.rows)
        case .ready:
            guard local.isCompleteForQuery else {
                return .failure(
                    SpaceAssignmentDestinationFailure.localReadFailed.diagnosticCode
                )
            }
            return local.rows.isEmpty ? .authoritativeEmpty : .ready(local.rows)
        }
    }
}
