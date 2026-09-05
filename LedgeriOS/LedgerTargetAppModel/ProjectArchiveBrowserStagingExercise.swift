import Foundation
import LedgerTargetCore
import Observation

public struct ProjectArchiveBrowserEvidence: Equatable, Sendable {
    public let accountId: AccountID
    public let projectId: ProjectID
    public let expectedRevision: ExpectedProjectRevision
    public let selectionGeneration: UInt64

    public init(
        accountId: AccountID,
        projectId: ProjectID,
        expectedRevision: ExpectedProjectRevision,
        selectionGeneration: UInt64
    ) {
        self.accountId = accountId
        self.projectId = projectId
        self.expectedRevision = expectedRevision
        self.selectionGeneration = selectionGeneration
    }
}

public struct ProjectArchiveSubmissionIdentity: Equatable, Sendable {
    public let operationId: OperationID

    public init(operationId: OperationID) {
        self.operationId = operationId
    }
}

public struct ProjectArchiveBrowserStagingRuntime: ProjectArchiving, Sendable {
    public typealias Archive = @Sendable (ArchiveProjectCommand) async throws
        -> OperationReceipt
    public typealias OperationWatch = @Sendable (OperationID)
        -> AsyncThrowingStream<OperationSnapshot, Error>

    private let archiveOperation: Archive
    private let operationWatch: OperationWatch

    public init(
        archive: @escaping Archive,
        watchOperation: @escaping OperationWatch
    ) {
        archiveOperation = archive
        operationWatch = watchOperation
    }

    public func archive(_ command: ArchiveProjectCommand) async throws -> OperationReceipt {
        try await archiveOperation(command)
    }

    public func watchOperation(
        _ operationId: OperationID
    ) -> AsyncThrowingStream<OperationSnapshot, Error> {
        operationWatch(operationId)
    }
}

@MainActor
@Observable
public final class ProjectArchiveBrowserStagingExercise {
    public private(set) var isConfirmationPresented = false
    public private(set) var isSubmitting = false
    public private(set) var operationStateLabel = "not submitted"
    public private(set) var operationIdLabel: String?
    public private(set) var diagnostic: String?

    public var canRequestArchive: Bool {
        runtime != nil
            && !isSubmitting
            && activeSubmission == nil
            && currentArchiveEvidence != nil
    }

    public var canRetryAmbiguousAcceptance: Bool {
        runtime != nil
            && !isSubmitting
            && activeSubmission != nil
            && ambiguousSubmission != nil
    }

    public var canRetryRejectedArchive: Bool {
        guard runtime != nil, !isSubmitting,
              let rejectedSubmission,
              let evidence = browserArchiveEvidence else {
            return false
        }
        return evidence.accountId == rejectedSubmission.evidence.accountId
            && evidence.projectId == rejectedSubmission.evidence.projectId
            && evidence.expectedRevision != rejectedSubmission.evidence.expectedRevision
    }

    private let accountId: AccountID
    private let actorPrincipalId: PrincipalID
    private let operationContractVersion: OperationContractVersion
    private let browser: ProjectBrowsingStagingExercise
    private let makeIdentity: @MainActor () throws -> ProjectArchiveSubmissionIdentity
    private let now: @MainActor () -> Date
    private var runtime: ProjectArchiveBrowserStagingRuntime?
    private var confirmation: ProjectArchiveBrowserEvidence?
    private var activeSubmission: Submission?
    private var ambiguousSubmission: Submission?
    private var rejectedSubmission: Submission?
    private var appliedSubmission: Submission?
    private var acceptedSubmissions: [ArchiveKey: Submission] = [:]
    private var operationTask: Task<Void, Never>?
    private var lifecycleGeneration: UInt64 = 0
    private var observationGeneration: UInt64 = 0
    private var invalidatedBrowserSelectionGeneration: UInt64?

    private var browserArchiveEvidence: ProjectArchiveBrowserEvidence? {
        guard let evidence = browser.selectedProjectArchiveEvidence,
              evidence.selectionGeneration != invalidatedBrowserSelectionGeneration else {
            return nil
        }
        return evidence
    }

    private var currentArchiveEvidence: ProjectArchiveBrowserEvidence? {
        guard let evidence = browserArchiveEvidence else { return nil }
        if let rejectedSubmission,
           evidence.accountId == rejectedSubmission.evidence.accountId,
           evidence.projectId == rejectedSubmission.evidence.projectId,
           evidence.expectedRevision == rejectedSubmission.evidence.expectedRevision {
            return nil
        }
        if let appliedSubmission,
           evidence.accountId == appliedSubmission.evidence.accountId,
           evidence.projectId == appliedSubmission.evidence.projectId,
           evidence.expectedRevision == appliedSubmission.evidence.expectedRevision {
            return nil
        }
        if acceptedSubmissions[ArchiveKey(evidence)] != nil {
            return nil
        }
        return evidence
    }

    public init(
        accountId: AccountID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        browser: ProjectBrowsingStagingExercise,
        makeIdentity: @escaping @MainActor () throws -> ProjectArchiveSubmissionIdentity,
        now: @escaping @MainActor () -> Date
    ) {
        self.accountId = accountId
        self.actorPrincipalId = actorPrincipalId
        self.operationContractVersion = operationContractVersion
        self.browser = browser
        self.makeIdentity = makeIdentity
        self.now = now
    }

    public func start(runtime: ProjectArchiveBrowserStagingRuntime) async {
        lifecycleGeneration &+= 1
        observationGeneration &+= 1
        let activeLifecycle = lifecycleGeneration
        let oldTask = operationTask
        operationTask = nil
        self.runtime = nil
        oldTask?.cancel()
        await oldTask?.value
        guard lifecycleGeneration == activeLifecycle else { return }

        self.runtime = runtime
        confirmation = nil
        activeSubmission = nil
        ambiguousSubmission = nil
        rejectedSubmission = nil
        appliedSubmission = nil
        acceptedSubmissions = [:]
        isConfirmationPresented = false
        isSubmitting = false
        operationStateLabel = "not submitted"
        operationIdLabel = nil
        diagnostic = nil
        invalidatedBrowserSelectionGeneration = nil
    }

    public func stop() async {
        lifecycleGeneration &+= 1
        observationGeneration &+= 1
        let activeLifecycle = lifecycleGeneration
        let oldTask = operationTask
        operationTask = nil
        runtime = nil
        confirmation = nil
        activeSubmission = nil
        ambiguousSubmission = nil
        rejectedSubmission = nil
        appliedSubmission = nil
        acceptedSubmissions = [:]
        isConfirmationPresented = false
        isSubmitting = false
        operationStateLabel = "stopped"
        operationIdLabel = nil
        diagnostic = nil
        invalidatedBrowserSelectionGeneration = nil
        oldTask?.cancel()
        await oldTask?.value
        guard lifecycleGeneration == activeLifecycle else { return }
    }

    public func selectionDidChange() async {
        invalidatedBrowserSelectionGeneration = browser.selectedProjectArchiveEvidence?
            .selectionGeneration
        confirmation = nil
        isConfirmationPresented = false
        observationGeneration &+= 1
        let activeObservation = observationGeneration
        let oldTask = operationTask
        operationTask = nil
        oldTask?.cancel()
        await oldTask?.value
        guard observationGeneration == activeObservation else { return }
        if ambiguousSubmission == nil {
            activeSubmission = nil
        }
    }

    public func selectionDidSettle() async {
        guard ambiguousSubmission == nil,
              let runtime,
              let evidence = browserArchiveEvidence,
              let submission = acceptedSubmissions[ArchiveKey(evidence)] else {
            return
        }
        do {
            let command = try submission.command(
                actorPrincipalId: actorPrincipalId,
                operationContractVersion: operationContractVersion
            )
            activeSubmission = submission
            operationIdLabel = command.envelope.operationId.rawValue
            await beginObservation(
                command: command,
                submission: submission,
                runtime: runtime,
                lifecycleGeneration: lifecycleGeneration,
                observationGeneration: observationGeneration
            )
        } catch {
            activeSubmission = nil
            diagnostic = "project_archive_operation_evidence_invalid"
        }
    }

    public func requestArchiveConfirmation() {
        guard runtime != nil, !isSubmitting,
              activeSubmission == nil,
              let evidence = currentArchiveEvidence,
              evidence.accountId == accountId else {
            confirmation = nil
            isConfirmationPresented = false
            diagnostic = "project_archive_current_evidence_required"
            return
        }
        confirmation = evidence
        isConfirmationPresented = true
        diagnostic = nil
    }

    public func requestRejectedRetryConfirmation() {
        guard canRetryRejectedArchive else {
            diagnostic = "project_archive_refreshed_evidence_required"
            return
        }
        requestArchiveConfirmation()
    }

    public func cancelConfirmation() {
        confirmation = nil
        isConfirmationPresented = false
    }

    public func confirmArchive() async {
        guard !isSubmitting, let runtime, let confirmation else { return }
        guard currentArchiveEvidence == confirmation else {
            self.confirmation = nil
            isConfirmationPresented = false
            diagnostic = "project_archive_confirmation_stale"
            return
        }

        do {
            let submission = try Submission(
                evidence: confirmation,
                identity: makeIdentity(),
                capturedAt: now()
            )
            self.confirmation = nil
            isConfirmationPresented = false
            await submit(submission, runtime: runtime, mayRetainAmbiguous: true)
        } catch let failure as ProjectArchiveFailure {
            diagnostic = failure.diagnosticCode
        } catch {
            diagnostic = "project_archive_submission_invalid"
        }
    }

    public func retryAmbiguousAcceptance() async {
        guard !isSubmitting, let runtime, let ambiguousSubmission else { return }
        await submit(ambiguousSubmission, runtime: runtime, mayRetainAmbiguous: true)
    }

    private func submit(
        _ submission: Submission,
        runtime: ProjectArchiveBrowserStagingRuntime,
        mayRetainAmbiguous: Bool
    ) async {
        let activeLifecycle = lifecycleGeneration
        let activeObservation = observationGeneration
        isSubmitting = true
        activeSubmission = submission
        diagnostic = nil
        defer {
            if lifecycleGeneration == activeLifecycle {
                isSubmitting = false
            }
        }
        do {
            let receipt = try await ProjectArchiveUseCase(archiver: runtime).execute(
                intent: submission.intent,
                operationId: submission.identity.operationId,
                actorPrincipalId: actorPrincipalId,
                operationContractVersion: operationContractVersion,
                capturedAt: submission.capturedAt
            )
            guard lifecycleGeneration == activeLifecycle,
                  observationGeneration == activeObservation else { return }
            let command = try submission.command(
                actorPrincipalId: actorPrincipalId,
                operationContractVersion: operationContractVersion
            )
            guard receipt.operationId == command.envelope.operationId else {
                throw ProjectArchiveFailure.receiptMismatch
            }
            ambiguousSubmission = nil
            rejectedSubmission = nil
            acceptedSubmissions[ArchiveKey(submission.evidence)] = submission
            operationIdLabel = receipt.operationId.rawValue
            operationStateLabel = receipt.localState.rawValue
            await beginObservation(
                command: command,
                submission: submission,
                runtime: runtime,
                lifecycleGeneration: activeLifecycle,
                observationGeneration: activeObservation
            )
        } catch is CancellationError {
            guard lifecycleGeneration == activeLifecycle,
                  observationGeneration == activeObservation else { return }
            ambiguousSubmission = submission
            diagnostic = "project_archive_cancelled"
        } catch let failure as ProjectArchiveFailure {
            guard lifecycleGeneration == activeLifecycle,
                  observationGeneration == activeObservation else { return }
            if mayRetainAmbiguous {
                ambiguousSubmission = submission
            }
            diagnostic = failure.diagnosticCode
        } catch {
            guard lifecycleGeneration == activeLifecycle,
                  observationGeneration == activeObservation else { return }
            if mayRetainAmbiguous {
                ambiguousSubmission = submission
            }
            diagnostic = "project_archive_local_failed"
        }
    }

    private func beginObservation(
        command: ArchiveProjectCommand,
        submission: Submission,
        runtime: ProjectArchiveBrowserStagingRuntime,
        lifecycleGeneration: UInt64,
        observationGeneration: UInt64
    ) async {
        let oldTask = operationTask
        operationTask = nil
        oldTask?.cancel()
        await oldTask?.value
        guard self.lifecycleGeneration == lifecycleGeneration,
              self.observationGeneration == observationGeneration else {
            return
        }
        operationTask = Task { [weak self] in
            await self?.observeOperation(
                command: command,
                submission: submission,
                runtime: runtime,
                lifecycleGeneration: lifecycleGeneration,
                observationGeneration: observationGeneration
            )
        }
    }

    private func observeOperation(
        command: ArchiveProjectCommand,
        submission: Submission,
        runtime: ProjectArchiveBrowserStagingRuntime,
        lifecycleGeneration: UInt64,
        observationGeneration: UInt64
    ) async {
        var iterator = runtime.watchOperation(command.envelope.operationId).makeAsyncIterator()
        defer {
            if self.lifecycleGeneration == lifecycleGeneration,
               self.observationGeneration == observationGeneration {
                operationTask = nil
            }
        }
        do {
            while let snapshot = try await iterator.next() {
                guard !Task.isCancelled else { return }
                guard snapshot.operationId == command.envelope.operationId,
                      snapshot.accountId == accountId,
                      snapshot.contractVersion == operationContractVersion,
                      snapshot.fingerprint == command.fingerprint,
                      snapshot.acceptedAt.timeIntervalSinceReferenceDate.isFinite,
                      snapshot.updatedAt.timeIntervalSinceReferenceDate.isFinite,
                      snapshot.updatedAt >= snapshot.acceptedAt,
                      let localState = snapshot.state.localState,
                      self.lifecycleGeneration == lifecycleGeneration,
                      self.observationGeneration == observationGeneration else {
                    operationTask?.cancel()
                    _ = try? await iterator.next()
                    guard self.lifecycleGeneration == lifecycleGeneration,
                          self.observationGeneration == observationGeneration else {
                        return
                    }
                    diagnostic = "project_archive_operation_evidence_invalid"
                    return
                }
                operationStateLabel = localState.rawValue
                if localState == .rejected {
                    activeSubmission = nil
                    rejectedSubmission = submission
                    acceptedSubmissions.removeValue(forKey: ArchiveKey(submission.evidence))
                } else if localState == .applied {
                    activeSubmission = nil
                    appliedSubmission = submission
                    rejectedSubmission = nil
                } else if localState == .superseded || localState == .resolved {
                    activeSubmission = nil
                    rejectedSubmission = nil
                    acceptedSubmissions.removeValue(forKey: ArchiveKey(submission.evidence))
                } else if localState != .queued && localState != .applying {
                    rejectedSubmission = nil
                }
            }
            guard !Task.isCancelled,
                  self.lifecycleGeneration == lifecycleGeneration,
                  self.observationGeneration == observationGeneration else {
                return
            }
            diagnostic = "project_archive_operation_source_completed"
        } catch is CancellationError {
            guard !Task.isCancelled,
                  self.lifecycleGeneration == lifecycleGeneration,
                  self.observationGeneration == observationGeneration else {
                return
            }
            diagnostic = "project_archive_operation_source_cancelled"
        } catch {
            guard self.lifecycleGeneration == lifecycleGeneration,
                  self.observationGeneration == observationGeneration else {
                return
            }
            diagnostic = "project_archive_operation_local_failed"
        }
    }

}

private extension ProjectArchiveBrowserStagingExercise {
    struct ArchiveKey: Hashable, Sendable {
        let accountId: AccountID
        let projectId: ProjectID
        let expectedRevision: ExpectedProjectRevision

        init(_ evidence: ProjectArchiveBrowserEvidence) {
            accountId = evidence.accountId
            projectId = evidence.projectId
            expectedRevision = evidence.expectedRevision
        }
    }

    struct Submission: Equatable, Sendable {
        let evidence: ProjectArchiveBrowserEvidence
        let identity: ProjectArchiveSubmissionIdentity
        let capturedAt: Date

        init(
            evidence: ProjectArchiveBrowserEvidence,
            identity: ProjectArchiveSubmissionIdentity,
            capturedAt: Date
        ) throws {
            let rawMilliseconds = capturedAt.timeIntervalSince1970 * 1_000
            guard rawMilliseconds.isFinite,
                  let milliseconds = Int64(exactly: rawMilliseconds.rounded(.towardZero)),
                  milliseconds >= 0 else {
                throw ProjectArchiveFailure.invalidCapturedAt
            }
            self.evidence = evidence
            self.identity = identity
            self.capturedAt = Date(
                timeIntervalSince1970: Double(milliseconds) / 1_000
            )
        }

        var intent: ProjectArchiveIntent {
            ProjectArchiveIntent(
                accountId: evidence.accountId,
                projectId: evidence.projectId,
                expectedRevision: evidence.expectedRevision
            )
        }

        func command(
            actorPrincipalId: PrincipalID,
            operationContractVersion: OperationContractVersion
        ) throws -> ArchiveProjectCommand {
            try ArchiveProjectCommand(
                operationId: identity.operationId,
                draft: ProjectArchiveDraft(
                    accountId: evidence.accountId,
                    actorPrincipalId: actorPrincipalId,
                    operationContractVersion: operationContractVersion,
                    projectId: evidence.projectId,
                    expectedRevision: evidence.expectedRevision,
                    capturedAt: capturedAt
                )
            )
        }
    }
}
