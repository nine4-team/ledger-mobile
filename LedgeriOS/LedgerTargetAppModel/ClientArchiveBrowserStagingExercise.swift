import Foundation
import LedgerTargetCore
import Observation

public struct ClientArchiveBrowserEvidence: Equatable, Sendable {
    public let accountId: AccountID
    public let clientId: ClientID
    public let expectedRevision: ExpectedClientRevision
    public let selectionGeneration: UInt64

    public init(
        accountId: AccountID,
        clientId: ClientID,
        expectedRevision: ExpectedClientRevision,
        selectionGeneration: UInt64
    ) {
        self.accountId = accountId
        self.clientId = clientId
        self.expectedRevision = expectedRevision
        self.selectionGeneration = selectionGeneration
    }
}

public struct ClientArchiveSubmissionIdentity: Equatable, Sendable {
    public let operationId: OperationID
    public init(operationId: OperationID) { self.operationId = operationId }
}

public struct ClientArchiveBrowserStagingRuntime: ClientArchiving, Sendable {
    public typealias Archive = @Sendable (ArchiveClientCommand) async throws
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

    public func archive(_ command: ArchiveClientCommand) async throws -> OperationReceipt {
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
public final class ClientArchiveBrowserStagingExercise {
    public private(set) var isConfirmationPresented = false
    public private(set) var isSubmitting = false
    public private(set) var operationStateLabel = "not submitted"
    public private(set) var operationIdLabel: String?
    public private(set) var diagnostic: String?

    public var canRequestArchive: Bool {
        runtime != nil && !isSubmitting && activeSubmission == nil
            && currentArchiveEvidence != nil
    }

    public var canRetryAmbiguousAcceptance: Bool {
        runtime != nil && !isSubmitting && activeSubmission != nil
            && ambiguousSubmission != nil
    }

    public var canRetryRejectedArchive: Bool {
        guard runtime != nil, !isSubmitting, let rejectedSubmission,
              let evidence = browserEvidence else { return false }
        return evidence.accountId == rejectedSubmission.evidence.accountId
            && evidence.clientId == rejectedSubmission.evidence.clientId
            && evidence.expectedRevision != rejectedSubmission.evidence.expectedRevision
    }

    private let accountId: AccountID
    private let actorPrincipalId: PrincipalID
    private let operationContractVersion: OperationContractVersion
    private let browser: ClientBrowsingStagingExercise
    private let makeIdentity: @MainActor () throws -> ClientArchiveSubmissionIdentity
    private let now: @MainActor () -> Date
    private var runtime: ClientArchiveBrowserStagingRuntime?
    private var confirmation: ClientArchiveBrowserEvidence?
    private var activeSubmission: Submission?
    private var ambiguousSubmission: Submission?
    private var rejectedSubmission: Submission?
    private var appliedSubmission: Submission?
    private var accepted: [ArchiveKey: Submission] = [:]
    private var operationTask: Task<Void, Never>?
    private var lifecycleGeneration: UInt64 = 0
    private var observationGeneration: UInt64 = 0
    private var invalidatedSelectionGeneration: UInt64?

    private var browserEvidence: ClientArchiveBrowserEvidence? {
        guard let evidence = browser.selectedClientArchiveEvidence,
              evidence.selectionGeneration != invalidatedSelectionGeneration else {
            return nil
        }
        return evidence
    }

    private var currentArchiveEvidence: ClientArchiveBrowserEvidence? {
        guard let evidence = browserEvidence else { return nil }
        if let rejectedSubmission,
           ArchiveKey(evidence) == ArchiveKey(rejectedSubmission.evidence) { return nil }
        if let appliedSubmission,
           ArchiveKey(evidence) == ArchiveKey(appliedSubmission.evidence) { return nil }
        guard accepted[ArchiveKey(evidence)] == nil else { return nil }
        return evidence
    }

    public init(
        accountId: AccountID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        browser: ClientBrowsingStagingExercise,
        makeIdentity: @escaping @MainActor () throws -> ClientArchiveSubmissionIdentity,
        now: @escaping @MainActor () -> Date
    ) {
        self.accountId = accountId
        self.actorPrincipalId = actorPrincipalId
        self.operationContractVersion = operationContractVersion
        self.browser = browser
        self.makeIdentity = makeIdentity
        self.now = now
    }

    public func start(runtime: ClientArchiveBrowserStagingRuntime) async {
        lifecycleGeneration &+= 1
        observationGeneration &+= 1
        let generation = lifecycleGeneration
        let oldTask = operationTask
        operationTask = nil
        self.runtime = nil
        oldTask?.cancel()
        await oldTask?.value
        guard lifecycleGeneration == generation else { return }
        self.runtime = runtime
        confirmation = nil
        activeSubmission = nil
        ambiguousSubmission = nil
        rejectedSubmission = nil
        appliedSubmission = nil
        accepted = [:]
        isConfirmationPresented = false
        isSubmitting = false
        operationStateLabel = "not submitted"
        operationIdLabel = nil
        diagnostic = nil
        invalidatedSelectionGeneration = nil
    }

    public func stop() async {
        lifecycleGeneration &+= 1
        observationGeneration &+= 1
        let generation = lifecycleGeneration
        let oldTask = operationTask
        operationTask = nil
        runtime = nil
        confirmation = nil
        activeSubmission = nil
        ambiguousSubmission = nil
        rejectedSubmission = nil
        appliedSubmission = nil
        accepted = [:]
        isConfirmationPresented = false
        isSubmitting = false
        operationStateLabel = "stopped"
        operationIdLabel = nil
        diagnostic = nil
        invalidatedSelectionGeneration = nil
        oldTask?.cancel()
        await oldTask?.value
        guard lifecycleGeneration == generation else { return }
    }

    public func selectionDidChange() async {
        invalidatedSelectionGeneration = browser.selectedClientArchiveEvidence?
            .selectionGeneration
        confirmation = nil
        isConfirmationPresented = false
        observationGeneration &+= 1
        let generation = observationGeneration
        let oldTask = operationTask
        operationTask = nil
        oldTask?.cancel()
        await oldTask?.value
        guard observationGeneration == generation else { return }
        if ambiguousSubmission == nil { activeSubmission = nil }
    }

    public func selectionDidSettle() async {
        guard ambiguousSubmission == nil, let runtime, let evidence = browserEvidence,
              let submission = accepted[ArchiveKey(evidence)] else { return }
        do {
            let command = try submission.command(
                actorPrincipalId: actorPrincipalId,
                operationContractVersion: operationContractVersion
            )
            activeSubmission = submission
            operationIdLabel = command.envelope.operationId.rawValue
            await beginObservation(command: command, submission: submission, runtime: runtime)
        } catch { diagnostic = "client_archive_operation_evidence_invalid" }
    }

    public func requestArchiveConfirmation() {
        guard runtime != nil, !isSubmitting, activeSubmission == nil,
              let evidence = currentArchiveEvidence, evidence.accountId == accountId else {
            confirmation = nil
            isConfirmationPresented = false
            diagnostic = "client_archive_current_evidence_required"
            return
        }
        confirmation = evidence
        isConfirmationPresented = true
        diagnostic = nil
    }

    public func requestRejectedRetryConfirmation() {
        guard canRetryRejectedArchive else {
            diagnostic = "client_archive_refreshed_evidence_required"
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
            diagnostic = "client_archive_confirmation_stale"
            return
        }
        do {
            let submission = try Submission(
                evidence: confirmation, identity: makeIdentity(), capturedAt: now()
            )
            self.confirmation = nil
            isConfirmationPresented = false
            await submit(submission, runtime: runtime)
        } catch let failure as ClientArchiveFailure {
            diagnostic = failure.diagnosticCode
        } catch { diagnostic = "client_archive_submission_invalid" }
    }

    public func retryAmbiguousAcceptance() async {
        guard !isSubmitting, let runtime, let ambiguousSubmission else { return }
        await submit(ambiguousSubmission, runtime: runtime)
    }

    private func submit(
        _ submission: Submission,
        runtime: ClientArchiveBrowserStagingRuntime
    ) async {
        let lifecycle = lifecycleGeneration
        isSubmitting = true
        activeSubmission = submission
        diagnostic = nil
        do {
            let receipt = try await ClientArchiveUseCase(archiver: runtime).execute(
                intent: submission.intent,
                operationId: submission.identity.operationId,
                actorPrincipalId: actorPrincipalId,
                operationContractVersion: operationContractVersion,
                capturedAt: submission.capturedAt
            )
            guard lifecycleGeneration == lifecycle else { return }
            let command = try submission.command(
                actorPrincipalId: actorPrincipalId,
                operationContractVersion: operationContractVersion
            )
            guard receipt.operationId == command.envelope.operationId else {
                throw ClientArchiveFailure.receiptMismatch
            }
            ambiguousSubmission = nil
            rejectedSubmission = nil
            accepted[ArchiveKey(submission.evidence)] = submission
            operationIdLabel = receipt.operationId.rawValue
            operationStateLabel = receipt.localState.rawValue
            await beginObservation(command: command, submission: submission, runtime: runtime)
        } catch is CancellationError {
            guard lifecycleGeneration == lifecycle else { return }
            ambiguousSubmission = submission
            diagnostic = "client_archive_cancelled"
        } catch let failure as ClientArchiveFailure {
            guard lifecycleGeneration == lifecycle else { return }
            ambiguousSubmission = submission
            diagnostic = failure.diagnosticCode
        } catch {
            guard lifecycleGeneration == lifecycle else { return }
            ambiguousSubmission = submission
            diagnostic = "client_archive_local_failed"
        }
        guard lifecycleGeneration == lifecycle else { return }
        isSubmitting = false
    }

    private func beginObservation(
        command: ArchiveClientCommand,
        submission: Submission,
        runtime: ClientArchiveBrowserStagingRuntime
    ) async {
        observationGeneration &+= 1
        let observation = observationGeneration
        let lifecycle = lifecycleGeneration
        let oldTask = operationTask
        operationTask = nil
        oldTask?.cancel()
        await oldTask?.value
        guard lifecycleGeneration == lifecycle,
              observationGeneration == observation else { return }
        operationTask = Task { [weak self] in
            await self?.observeOperation(
                command: command, submission: submission, runtime: runtime,
                lifecycle: lifecycle, observation: observation
            )
        }
    }

    private func observeOperation(
        command: ArchiveClientCommand,
        submission: Submission,
        runtime: ClientArchiveBrowserStagingRuntime,
        lifecycle: UInt64,
        observation: UInt64
    ) async {
        var iterator = runtime.watchOperation(command.envelope.operationId).makeAsyncIterator()
        defer {
            if lifecycleGeneration == lifecycle, observationGeneration == observation {
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
                      lifecycleGeneration == lifecycle,
                      observationGeneration == observation else {
                    operationTask?.cancel()
                    _ = try? await iterator.next()
                    guard lifecycleGeneration == lifecycle,
                          observationGeneration == observation else { return }
                    diagnostic = "client_archive_operation_evidence_invalid"
                    return
                }
                operationStateLabel = localState.rawValue
                switch localState {
                case .rejected:
                    activeSubmission = nil
                    rejectedSubmission = submission
                    accepted.removeValue(forKey: ArchiveKey(submission.evidence))
                case .applied:
                    activeSubmission = nil
                    appliedSubmission = submission
                    rejectedSubmission = nil
                case .superseded, .resolved:
                    activeSubmission = nil
                    rejectedSubmission = nil
                    accepted.removeValue(forKey: ArchiveKey(submission.evidence))
                case .queued, .applying: break
                }
            }
            guard !Task.isCancelled, lifecycleGeneration == lifecycle,
                  observationGeneration == observation else { return }
            diagnostic = "client_archive_operation_source_completed"
        } catch is CancellationError {
            guard !Task.isCancelled, lifecycleGeneration == lifecycle,
                  observationGeneration == observation else { return }
            diagnostic = "client_archive_operation_source_cancelled"
        } catch {
            guard lifecycleGeneration == lifecycle,
                  observationGeneration == observation else { return }
            diagnostic = "client_archive_operation_local_failed"
        }
    }
}

private extension ClientArchiveBrowserStagingExercise {
    struct ArchiveKey: Hashable, Sendable {
        let accountId: AccountID
        let clientId: ClientID
        let expectedRevision: ExpectedClientRevision
        init(_ evidence: ClientArchiveBrowserEvidence) {
            accountId = evidence.accountId
            clientId = evidence.clientId
            expectedRevision = evidence.expectedRevision
        }
    }

    struct Submission: Equatable, Sendable {
        let evidence: ClientArchiveBrowserEvidence
        let identity: ClientArchiveSubmissionIdentity
        let capturedAt: Date

        init(
            evidence: ClientArchiveBrowserEvidence,
            identity: ClientArchiveSubmissionIdentity,
            capturedAt: Date
        ) throws {
            let value = capturedAt.timeIntervalSince1970 * 1_000
            guard value.isFinite,
                  let milliseconds = Int64(exactly: value.rounded(.towardZero)),
                  milliseconds >= 0 else { throw ClientArchiveFailure.invalidCapturedAt }
            self.evidence = evidence
            self.identity = identity
            self.capturedAt = Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
        }

        var intent: ClientArchiveIntent {
            ClientArchiveIntent(
                accountId: evidence.accountId,
                clientId: evidence.clientId,
                expectedRevision: evidence.expectedRevision
            )
        }

        func command(
            actorPrincipalId: PrincipalID,
            operationContractVersion: OperationContractVersion
        ) throws -> ArchiveClientCommand {
            try ArchiveClientCommand(
                operationId: identity.operationId,
                draft: ClientArchiveDraft(
                    accountId: evidence.accountId,
                    actorPrincipalId: actorPrincipalId,
                    operationContractVersion: operationContractVersion,
                    clientId: evidence.clientId,
                    expectedRevision: evidence.expectedRevision,
                    capturedAt: capturedAt
                )
            )
        }
    }
}
