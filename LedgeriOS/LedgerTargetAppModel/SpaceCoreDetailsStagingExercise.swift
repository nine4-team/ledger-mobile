import Foundation
import LedgerTargetCore
import Observation

public protocol SpaceCoreDetailsStagingRuntime: Sendable {
    func watchSpaceCoreDetails(
        spaceId: SpaceID
    ) -> AsyncThrowingStream<SpaceCoreDetailsUpdate, Error>
}

public struct SpaceCoreDetailsStagingFailure: Equatable, Sendable {
    public let diagnosticCode: String
    public let cached: SpaceCoreDetailsLocalSnapshot?

    fileprivate init(
        diagnosticCode: String,
        cached: SpaceCoreDetailsLocalSnapshot?
    ) {
        self.diagnosticCode = diagnosticCode
        self.cached = cached
    }
}

public enum SpaceCoreDetailsStagingPresentation: Equatable, Sendable {
    case waiting(ListReadiness)
    case partial(SpaceCoreDetailsSnapshot?)
    case stale(SpaceCoreDetailsSnapshot?)
    case ready(SpaceCoreDetailsSnapshot)
    case authoritativeEmpty
    case failure(SpaceCoreDetailsStagingFailure)

    public var row: SpaceCoreDetailsSnapshot? {
        switch self {
        case .partial(let row), .stale(let row): row
        case .ready(let row): row
        case .failure(let failure): failure.cached?.row
        case .waiting, .authoritativeEmpty: nil
        }
    }

    public var status: String {
        switch self {
        case .waiting(let readiness):
            "\(readiness.rawValue) • completeness unknown"
        case .partial(let row):
            row == nil ? "partial empty • completeness unknown" : "partial • local evidence"
        case .stale(let row):
            row == nil ? "stale empty • completeness unknown" : "stale • local evidence"
        case .ready:
            "ready • local evidence complete"
        case .authoritativeEmpty:
            "authoritative empty • local evidence complete"
        case .failure:
            "failed • completeness unknown"
        }
    }
}

@MainActor
@Observable
public final class SpaceCoreDetailsStagingExercise {
    public private(set) var presentation: SpaceCoreDetailsStagingPresentation =
        .waiting(.notRequested)
    public private(set) var selectedSpaceId: SpaceID?

    public var row: SpaceCoreDetailsSnapshot? { presentation.row }
    public var status: String { presentation.status }
    public var diagnostic: String? {
        guard case .failure(let failure) = presentation else { return nil }
        return failure.diagnosticCode
    }
    public var isAuthoritativelyEmpty: Bool {
        presentation == .authoritativeEmpty
    }
    public var progressCountsAreAuthoritative: Bool {
        switch presentation {
        case .ready:
            true
        case .failure(let failure):
            failure.cached?.progressCountsAreAuthoritative == true
        default:
            false
        }
    }
    public var completedItemCount: Int { row?.completedItemCount ?? 0 }
    public var totalItemCount: Int { row?.totalItemCount ?? 0 }

    private let accountId: AccountID
    private var observationTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    public init(accountId: AccountID) {
        self.accountId = accountId
    }

    public func select(
        spaceId: SpaceID,
        runtime: any SpaceCoreDetailsStagingRuntime
    ) async {
        generation &+= 1
        let activeGeneration = generation
        let oldTask = observationTask
        observationTask = nil
        selectedSpaceId = spaceId
        presentation = .waiting(.loading)
        oldTask?.cancel()
        await oldTask?.value

        guard generation == activeGeneration,
              selectedSpaceId == spaceId else { return }
        let request: SpaceCoreDetailsRequest
        do {
            request = try SpaceCoreDetailsRequest(accountId: accountId, spaceId: spaceId)
        } catch let failure as SpaceCoreDetailsFailure {
            failClosed(failure.diagnosticCode)
            return
        } catch {
            failClosed(SpaceCoreDetailsFailure.localReadFailed.diagnosticCode)
            return
        }
        observationTask = Task { [weak self] in
            await self?.observe(
                request: request,
                runtime: runtime,
                generation: activeGeneration
            )
        }
    }

    public func clear() async {
        generation &+= 1
        let oldTask = observationTask
        observationTask = nil
        selectedSpaceId = nil
        presentation = .waiting(.notRequested)
        oldTask?.cancel()
        await oldTask?.value
    }

    public func stop() async {
        generation &+= 1
        let oldTask = observationTask
        observationTask = nil
        selectedSpaceId = nil
        presentation = .waiting(.blocked)
        oldTask?.cancel()
        await oldTask?.value
    }

    private func observe(
        request: SpaceCoreDetailsRequest,
        runtime: any SpaceCoreDetailsStagingRuntime,
        generation: UInt64
    ) async {
        do {
            for try await update in runtime.watchSpaceCoreDetails(spaceId: request.spaceId) {
                try Task.checkCancellation()
                guard self.generation == generation,
                      selectedSpaceId == request.spaceId else { return }
                let validated = try update.validating(request: request)
                presentation = try Self.project(validated.state)
            }
            guard !Task.isCancelled,
                  self.generation == generation,
                  selectedSpaceId == request.spaceId else { return }
            failClosed(Self.sourceCompletedCode)
        } catch is CancellationError {
            guard !Task.isCancelled,
                  self.generation == generation,
                  selectedSpaceId == request.spaceId else { return }
            failClosed(Self.sourceCancelledCode)
        } catch let failure as SpaceCoreDetailsFailure {
            guard self.generation == generation,
                  selectedSpaceId == request.spaceId else { return }
            failClosed(failure.diagnosticCode)
        } catch {
            guard self.generation == generation,
                  selectedSpaceId == request.spaceId else { return }
            failClosed(SpaceCoreDetailsFailure.localReadFailed.diagnosticCode)
        }
    }

    private static func project(
        _ state: SpaceCoreDetailsUpdateState
    ) throws -> SpaceCoreDetailsStagingPresentation {
        switch state {
        case .waiting(let readiness):
            return .waiting(readiness)
        case .snapshot(let snapshot):
            switch snapshot.local.quality {
            case .partial:
                return .partial(snapshot.row)
            case .stale:
                return .stale(snapshot.row)
            case .ready:
                guard snapshot.local.isCompleteForQuery else {
                    throw SpaceCoreDetailsFailure.invalidCompleteness
                }
                return snapshot.row.map(Self.ready) ?? .authoritativeEmpty
            }
        case .failed(let failure, let cached):
            return .failure(SpaceCoreDetailsStagingFailure(
                diagnosticCode: "space_core_details_\(failure.rawValue)",
                cached: cached
            ))
        }
    }

    private static func ready(
        _ row: SpaceCoreDetailsSnapshot
    ) -> SpaceCoreDetailsStagingPresentation {
        .ready(row)
    }

    private func failClosed(_ diagnosticCode: String) {
        presentation = .failure(SpaceCoreDetailsStagingFailure(
            diagnosticCode: diagnosticCode,
            cached: nil
        ))
    }

    private static let sourceCompletedCode = "space_core_details_source_completed"
    private static let sourceCancelledCode = "space_core_details_source_cancelled"
}
