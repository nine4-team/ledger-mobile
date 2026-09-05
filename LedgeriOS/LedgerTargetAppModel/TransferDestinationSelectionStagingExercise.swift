import Foundation
import LedgerTargetCore
import Observation

public struct TransferDestinationSelectionStagingRuntime: Sendable {
    public typealias Watch = @Sendable (ProjectSummary)
        -> AsyncThrowingStream<TransferDestinationSelectionSnapshot, Error>

    private let watch: Watch

    public init(watch: @escaping Watch) {
        self.watch = watch
    }

    public func destinations(
        for source: ProjectSummary
    ) -> AsyncThrowingStream<TransferDestinationSelectionSnapshot, Error> {
        watch(source)
    }
}

public enum TransferDestinationSelectionPresentation: Equatable, Sendable {
    case waiting
    case partial([TransferDestinationCandidate])
    case stale([TransferDestinationCandidate])
    case ready([TransferDestinationCandidate])
    case partialEmpty
    case staleEmpty
    case authoritativeEmpty
    case failure(String)

    public var rows: [TransferDestinationCandidate] {
        switch self {
        case .partial(let rows), .stale(let rows), .ready(let rows):
            rows
        default:
            []
        }
    }

    public var status: String {
        switch self {
        case .waiting: "waiting • completeness unknown"
        case .partial: "partial • local destinations"
        case .stale: "stale • local destinations"
        case .ready: "ready • local destinations complete"
        case .partialEmpty: "partial empty • completeness unknown"
        case .staleEmpty: "stale empty • completeness unknown"
        case .authoritativeEmpty: "empty • local destinations complete"
        case .failure: "failed • completeness unknown"
        }
    }
}

@MainActor
@Observable
public final class TransferDestinationSelectionStagingExercise {
    public private(set) var presentation: TransferDestinationSelectionPresentation = .waiting

    public var rows: [TransferDestinationCandidate] { presentation.rows }
    public var status: String { presentation.status }
    public var diagnostic: String? {
        if case .failure(let code) = presentation { code } else { nil }
    }
    public var selectedProjectId: ProjectID? {
        guard let selection,
              rows.contains(where: { $0.destination.id == selection }) else {
            return nil
        }
        return selection
    }

    private let accountId: AccountID
    private var selection: ProjectID?
    private var lastRepresentedSourceClientId: ClientID?
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0

    public init(accountId: AccountID) {
        self.accountId = accountId
    }

    public func open(
        source: ProjectSummary,
        runtime: TransferDestinationSelectionStagingRuntime
    ) async {
        generation &+= 1
        let current = generation
        let old = task
        task = nil
        selection = nil
        lastRepresentedSourceClientId = nil
        presentation = .waiting
        old?.cancel()
        await old?.value
        guard generation == current else { return }
        task = Task { [weak self] in
            await self?.observe(source: source, runtime: runtime, generation: current)
        }
    }

    public func stop() async {
        generation &+= 1
        let old = task
        task = nil
        old?.cancel()
        await old?.value
        selection = nil
        lastRepresentedSourceClientId = nil
    }

    @discardableResult
    public func select(projectId: ProjectID) -> Bool {
        guard rows.contains(where: { $0.destination.id == projectId }) else {
            return false
        }
        selection = projectId
        return true
    }

    private func observe(
        source: ProjectSummary,
        runtime: TransferDestinationSelectionStagingRuntime,
        generation: UInt64
    ) async {
        do {
            guard source.accountId == accountId else {
                throw TransferDestinationSelectionFailure.sourceDirectoryAccountMismatch
            }
            for try await snapshot in runtime.destinations(for: source) {
                try Task.checkCancellation()
                guard self.generation == generation else { return }
                guard snapshot.accountId == accountId,
                      snapshot.source.id == source.id else {
                    throw TransferDestinationSelectionFailure.sourceDirectoryAccountMismatch
                }

                if let previous = lastRepresentedSourceClientId,
                   previous != snapshot.source.clientId {
                    selection = nil
                }
                lastRepresentedSourceClientId = snapshot.source.clientId
                if let selection,
                   !snapshot.candidates.contains(where: {
                       $0.destination.id == selection
                   }) {
                    self.selection = nil
                }
                presentation = try Self.project(snapshot)
            }
            guard !Task.isCancelled, self.generation == generation else { return }
            presentation = .failure(Self.localReadFailureCode)
            selection = nil
        } catch is CancellationError {
            return
        } catch let failure as TransferDestinationSelectionFailure {
            guard self.generation == generation else { return }
            presentation = .failure(failure.diagnosticCode)
            selection = nil
        } catch {
            guard self.generation == generation else { return }
            presentation = .failure(Self.localReadFailureCode)
            selection = nil
        }
    }

    private static func project(
        _ snapshot: TransferDestinationSelectionSnapshot
    ) throws -> TransferDestinationSelectionPresentation {
        switch snapshot.quality {
        case .partial:
            return snapshot.candidates.isEmpty
                ? .partialEmpty
                : .partial(snapshot.candidates)
        case .stale:
            return snapshot.candidates.isEmpty
                ? .staleEmpty
                : .stale(snapshot.candidates)
        case .ready:
            guard snapshot.isCompleteForSelection else {
                throw TransferDestinationSelectionFailure.invalidSelectionCompleteness
            }
            return snapshot.candidates.isEmpty
                ? .authoritativeEmpty
                : .ready(snapshot.candidates)
        }
    }

    private static let localReadFailureCode = "transfer_destination_local_read_failed"
}
