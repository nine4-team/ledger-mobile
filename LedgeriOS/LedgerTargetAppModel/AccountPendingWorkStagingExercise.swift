import Foundation
import LedgerTargetCore
import Observation

public struct AccountPendingWorkStagingRuntime: Sendable {
    public typealias Summary = @Sendable () async throws -> PendingLocalWorkSummary

    private let summary: Summary

    public init(pendingWorkSummary: @escaping Summary) {
        summary = pendingWorkSummary
    }

    public func pendingWorkSummary() async throws -> PendingLocalWorkSummary {
        try await summary()
    }
}

public enum AccountPendingWorkStagingDiagnostic: String, Equatable, Sendable {
    case scopeMismatch = "account_pending_work_scope_mismatch"
    case sourceCancelled = "account_pending_work_local_read_cancelled"
    case localReadFailed = "account_pending_work_local_read_failed"
}

public enum AccountPendingWorkStagingPresentation: Equatable, Sendable {
    case notRequested
    case loading
    case clean(PendingLocalWorkSummary)
    case pending(PendingLocalWorkSummary)
    case failed(AccountPendingWorkStagingDiagnostic)

    public var summary: PendingLocalWorkSummary? {
        switch self {
        case .clean(let summary), .pending(let summary): summary
        case .notRequested, .loading, .failed: nil
        }
    }
}

@MainActor
@Observable
public final class AccountPendingWorkStagingExercise {
    public private(set) var presentation: AccountPendingWorkStagingPresentation = .notRequested

    public var statusLabel: String {
        switch presentation {
        case .notRequested: "Not requested"
        case .loading: "Reading local status"
        case .clean: "No pending local work"
        case .pending: "Pending local work"
        case .failed: "Local status unavailable"
        }
    }

    public var queuedOperationCountLabel: String { countLabel(\.queuedOperationCount) }
    public var applyingOperationCountLabel: String { countLabel(\.applyingOperationCount) }
    public var unresolvedRejectedOperationCountLabel: String {
        countLabel(\.unresolvedRejectedOperationCount)
    }
    public var unverifiedAttachmentCountLabel: String { countLabel(\.unverifiedAttachmentCount) }

    public var diagnosticCode: String? {
        guard case .failed(let diagnostic) = presentation else { return nil }
        return diagnostic.rawValue
    }

    public var canRefresh: Bool { !isStopped && runtime != nil }

    private let expectedEnvironment: LedgerEnvironmentKind
    private let expectedPrincipalId: PrincipalID
    private let expectedAccountId: AccountID
    private var runtime: AccountPendingWorkStagingRuntime?
    private var generationToken = UUID()
    private var isStopped = false
    private var admittedTasks: [UUID: Task<Void, Never>] = [:]

    public init(
        expectedEnvironment: LedgerEnvironmentKind,
        expectedPrincipalId: PrincipalID,
        expectedAccountId: AccountID,
        runtime: AccountPendingWorkStagingRuntime
    ) {
        self.expectedEnvironment = expectedEnvironment
        self.expectedPrincipalId = expectedPrincipalId
        self.expectedAccountId = expectedAccountId
        self.runtime = runtime
    }

    public func refresh() async {
        guard !isStopped, let runtime else { return }

        let activeGeneration = UUID()
        generationToken = activeGeneration
        presentation = .loading

        let retiredTasks = Array(admittedTasks.values)
        retiredTasks.forEach { $0.cancel() }

        let taskId = UUID()
        let task = Task { @MainActor [weak self] in
            for retiredTask in retiredTasks {
                await retiredTask.value
            }

            guard let self else { return }
            defer { self.admittedTasks[taskId] = nil }
            guard !Task.isCancelled,
                  !self.isStopped,
                  self.generationToken == activeGeneration else {
                return
            }
            await self.readSummary(runtime, generation: activeGeneration)
        }

        // MainActor serialization guarantees registration before the task can
        // begin, yield, finish, or be observed by replacement/stop.
        admittedTasks[taskId] = task
        await task.value
    }

    public func stop() async {
        guard !isStopped else {
            let tasks = Array(admittedTasks.values)
            for task in tasks {
                await task.value
            }
            admittedTasks.removeAll()
            return
        }

        isStopped = true
        generationToken = UUID()
        runtime = nil
        presentation = .notRequested

        let tasks = Array(admittedTasks.values)
        tasks.forEach { $0.cancel() }
        for task in tasks {
            await task.value
        }
        admittedTasks.removeAll()
    }

    private func readSummary(
        _ runtime: AccountPendingWorkStagingRuntime,
        generation: UUID
    ) async {
        do {
            let summary = try await runtime.pendingWorkSummary()
            guard !Task.isCancelled,
                  !isStopped,
                  self.generationToken == generation else {
                return
            }
            guard summary.environment == expectedEnvironment,
                  summary.principalId == expectedPrincipalId,
                  summary.accountId == expectedAccountId else {
                presentation = .failed(.scopeMismatch)
                return
            }
            presentation = summary.hasBlockingWork ? .pending(summary) : .clean(summary)
        } catch is CancellationError {
            guard !Task.isCancelled,
                  !isStopped,
                  self.generationToken == generation else {
                return
            }
            presentation = .failed(.sourceCancelled)
        } catch {
            guard !Task.isCancelled,
                  !isStopped,
                  self.generationToken == generation else {
                return
            }
            presentation = .failed(.localReadFailed)
        }
    }

    private func countLabel(
        _ keyPath: KeyPath<PendingLocalWorkSummary, UInt64>
    ) -> String {
        guard let summary = presentation.summary else { return "—" }
        return String(summary[keyPath: keyPath])
    }

    var admittedTaskCountForTesting: Int { admittedTasks.count }
    var isStoppedForTesting: Bool { isStopped }
}
