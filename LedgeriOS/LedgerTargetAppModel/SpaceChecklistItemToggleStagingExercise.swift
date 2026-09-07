import Foundation
import LedgerTargetCore
import Observation

public struct SpaceChecklistItemToggleStagingRuntime: SpaceChecklistRevising, Sendable {
    public typealias Revise = @Sendable (ReviseSpaceChecklistsCommand) async throws
        -> OperationReceipt
    public typealias OperationWatch = @Sendable (OperationID)
        -> AsyncThrowingStream<OperationSnapshot, Error>

    private let reviseOperation: Revise
    private let operationWatch: OperationWatch

    public init(
        reviseChecklists: @escaping Revise,
        watchOperation: @escaping OperationWatch
    ) {
        reviseOperation = reviseChecklists
        operationWatch = watchOperation
    }

    public func reviseChecklists(
        _ command: ReviseSpaceChecklistsCommand
    ) async throws -> OperationReceipt {
        try await reviseOperation(command)
    }

    public func watchOperation(
        _ operationId: OperationID
    ) -> AsyncThrowingStream<OperationSnapshot, Error> {
        operationWatch(operationId)
    }
}

public struct SpaceChecklistItemToggleSubmissionIdentity: Equatable, Sendable {
    public let operationId: OperationID

    public init(operationId: OperationID) {
        self.operationId = operationId
    }
}

public enum SpaceChecklistRevisionSubmissionOutcome: Equatable, Sendable {
    case acceptedLocally
    case acceptanceUncertain
    case refused
}

public enum SpaceChecklistItemToggleAdmission: String, Equatable, Sendable {
    case waiting
    case incomplete
    case unavailable
    case authoritativeAbsence
    case archived
    case ready
    case retryableStale
    case stopped

    public var permitsToggle: Bool {
        self == .ready || self == .retryableStale
    }

    public var explanation: String {
        switch self {
        case .waiting:
            "Checklist evidence is still loading."
        case .incomplete:
            "Checklist evidence is incomplete, so changes are disabled."
        case .unavailable:
            "Checklist evidence is unavailable, so changes are disabled."
        case .authoritativeAbsence:
            "No Space exists for this exact selection."
        case .archived:
            "Archived Spaces are read-only in this workflow."
        case .ready:
            "Checklist evidence is current and complete."
        case .retryableStale:
            "Cached checklist evidence is complete; an offline change may conflict later."
        case .stopped:
            "Checklist editing is stopped."
        }
    }
}

@MainActor
@Observable
public final class SpaceChecklistItemToggleStagingExercise {
    public private(set) var selectedSpaceId: SpaceID?
    public private(set) var admission: SpaceChecklistItemToggleAdmission = .waiting
    public private(set) var operationState: LocalOperationState?
    public private(set) var operationIdLabel: String?
    public private(set) var diagnostic: String?
    public private(set) var isSubmitting = false
    public private(set) var optimisticCollection: SpaceChecklistCollection?

    public var displayedCollection: SpaceChecklistCollection? {
        optimisticCollection ?? Self.row(from: currentUpdate)?.checklists
    }

    public var completedItemCount: Int {
        displayedCollection?.completedItemCount ?? 0
    }

    public var totalItemCount: Int {
        displayedCollection?.totalItemCount ?? 0
    }

    public var isProgressOptimistic: Bool { optimisticCollection != nil }

    public var operationStatus: String {
        if isSubmitting {
            return "accepting locally"
        }
        guard let operationState else {
            return ambiguousSubmission == nil ? "not submitted" : "acceptance uncertain"
        }
        switch operationState {
        case .queued:
            return "queued — accepted locally"
        case .applying:
            return "applying — synchronization in progress"
        case .applied:
            return frozenSubmission == nil
                ? "applied — authoritative readback received"
                : "applied — awaiting authoritative readback"
        case .rejected:
            return frozenSubmission == nil
                ? "rejected — refreshed evidence is available"
                : "rejected — awaiting refreshed evidence"
        case .superseded:
            return "superseded — awaiting refreshed evidence"
        case .resolved:
            return "resolved — awaiting refreshed evidence"
        }
    }

    public var hasActiveSubmission: Bool {
        frozenSubmission != nil || ambiguousSubmission != nil || isSubmitting
    }

    public var canRetryAmbiguousAcceptance: Bool {
        runtime != nil && !isSubmitting && frozenSubmission == nil && ambiguousSubmission != nil
    }

    public var canSubmitCompleteDraft: Bool {
        runtime != nil
            && !isSubmitting
            && frozenSubmission == nil
            && ambiguousSubmission == nil
            && admission.permitsToggle
    }

    private let accountId: AccountID
    private let actorPrincipalId: PrincipalID
    private let operationContractVersion: OperationContractVersion
    private let makeIdentity: @MainActor () throws
        -> SpaceChecklistItemToggleSubmissionIdentity
    private let now: @MainActor () -> Date

    private var runtime: SpaceChecklistItemToggleStagingRuntime?
    private var currentUpdate: SpaceCoreDetailsUpdate?
    private var frozenSubmission: FrozenSubmission?
    private var ambiguousSubmission: FrozenSubmission?
    private var operationObservationTask: Task<Void, Never>?
    private var lifecycleGeneration = UUID()
    private var selectionGeneration = UUID()
    private var evidenceSequence: UInt64 = 0

    public init(
        accountId: AccountID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        makeIdentity: @escaping @MainActor () throws
            -> SpaceChecklistItemToggleSubmissionIdentity,
        now: @escaping @MainActor () -> Date
    ) {
        self.accountId = accountId
        self.actorPrincipalId = actorPrincipalId
        self.operationContractVersion = operationContractVersion
        self.makeIdentity = makeIdentity
        self.now = now
    }

    public func start(runtime: SpaceChecklistItemToggleStagingRuntime) async {
        lifecycleGeneration = UUID()
        selectionGeneration = UUID()
        let activeLifecycle = lifecycleGeneration
        let oldTask = operationObservationTask
        operationObservationTask = nil
        self.runtime = nil
        oldTask?.cancel()
        await oldTask?.value
        guard lifecycleGeneration == activeLifecycle else { return }

        self.runtime = runtime
        selectedSpaceId = nil
        currentUpdate = nil
        frozenSubmission = nil
        ambiguousSubmission = nil
        optimisticCollection = nil
        operationState = nil
        operationIdLabel = nil
        diagnostic = nil
        isSubmitting = false
        admission = .waiting
        evidenceSequence = 0
    }

    public func receiveDetailUpdate(
        _ update: SpaceCoreDetailsUpdate?,
        selectedSpaceId newSelection: SpaceID?
    ) async {
        if selectedSpaceId != newSelection {
            await replaceSelection(with: newSelection)
        }
        guard selectedSpaceId == newSelection else { return }

        evidenceSequence &+= 1
        guard let update else {
            currentUpdate = nil
            admission = newSelection == nil ? .waiting : .incomplete
            return
        }

        do {
            guard update.request.accountId == accountId,
                  update.request.spaceId == newSelection else {
                throw SpaceChecklistToggleFailure.invalidDetailEvidence
            }
            let request = try SpaceCoreDetailsRequest(
                accountId: accountId,
                spaceId: update.request.spaceId
            )
            currentUpdate = try update.validating(request: request)
            admission = try Self.projectAdmission(from: update)
        } catch let failure as SpaceCoreDetailsFailure {
            currentUpdate = nil
            admission = .unavailable
            diagnostic = failure.diagnosticCode
            return
        } catch {
            currentUpdate = nil
            admission = .unavailable
            diagnostic = SpaceChecklistToggleFailure.invalidDetailEvidence.diagnosticCode
            return
        }

        if frozenSubmission == nil,
           let projection = Self.checklistRevisionProjection(from: currentUpdate) {
            do {
                let recovered = try FrozenSubmission(
                    recovering: projection,
                    sourceUpdate: currentUpdate,
                    expectedAccountId: accountId,
                    expectedActorPrincipalId: actorPrincipalId,
                    expectedContractVersion: operationContractVersion,
                    settlementEvidenceSequence: evidenceSequence
                )
                frozenSubmission = recovered
                optimisticCollection = recovered.targetCollection
                operationState = projection.localState
                operationIdLabel = projection.operationId.rawValue
                if let runtime {
                    await beginOperationObservation(
                        submission: recovered,
                        runtime: runtime,
                        lifecycleGeneration: lifecycleGeneration,
                        selectionGeneration: selectionGeneration
                    )
                }
            } catch {
                currentUpdate = nil
                admission = .unavailable
                optimisticCollection = nil
                diagnostic = SpaceChecklistToggleFailure.invalidOperationEvidence.diagnosticCode
                return
            }
        }

        if let submission = frozenSubmission {
            if operationState == .applied,
               Self.isAuthoritativeReadback(
                   currentUpdate,
                   matching: submission
               ) {
                settleSubmission(clearDiagnostic: true)
                await cancelAndDrainOperationObservation()
            } else if Self.isRefreshTerminal(operationState),
                      evidenceSequence > submission.settlementEvidenceSequence,
                      Self.isSettledDetailEvidence(currentUpdate) {
                settleSubmission(clearDiagnostic: false)
                await cancelAndDrainOperationObservation()
            }
        }
    }

    public func stop() async {
        lifecycleGeneration = UUID()
        selectionGeneration = UUID()
        runtime = nil
        selectedSpaceId = nil
        currentUpdate = nil
        frozenSubmission = nil
        ambiguousSubmission = nil
        optimisticCollection = nil
        operationState = nil
        operationIdLabel = nil
        diagnostic = nil
        isSubmitting = false
        admission = .stopped
        evidenceSequence = 0
        await cancelAndDrainOperationObservation()
    }

    public func canToggle(
        checklistId: SpaceChecklistID,
        itemId: SpaceChecklistItemID
    ) -> Bool {
        guard runtime != nil,
              !isSubmitting,
              frozenSubmission == nil,
              ambiguousSubmission == nil,
              admission.permitsToggle,
              let collection = displayedCollection,
              let checklist = collection.checklists.first(where: { $0.id == checklistId }) else {
            return false
        }
        return checklist.items.contains(where: { $0.id == itemId })
    }

    public func toggle(
        checklistId: SpaceChecklistID,
        itemId: SpaceChecklistItemID
    ) async {
        guard canToggle(checklistId: checklistId, itemId: itemId),
              let runtime,
              let currentUpdate,
              let row = Self.row(from: currentUpdate),
              row.lifecycle == .active else {
            diagnostic = SpaceChecklistToggleFailure.currentEvidenceRequired.diagnosticCode
            return
        }

        do {
            let presentation = try SpaceChecklistEditingPresentation(projecting: currentUpdate)
            let preparation = try presentation.prepare()
            guard let checklist = preparation.draft.checklists.first(where: {
                $0.id == checklistId
            }), let item = checklist.items.first(where: { $0.id == itemId }) else {
                throw SpaceChecklistEditingFailure.itemNotFound
            }
            let toggledDraft = try preparation.draft.settingItemChecked(
                checklistId: checklistId,
                itemId: itemId,
                isChecked: !item.isChecked
            )
            let capturedAt = try Self.canonicalTimestamp(now())
            let submission = try FrozenSubmission(
                sourceUpdate: currentUpdate,
                draft: toggledDraft,
                identity: makeIdentity(),
                capturedAt: capturedAt,
                targetCollection: toggledDraft.collection(),
                baseRevision: row.revision,
                settlementEvidenceSequence: evidenceSequence
            )
            frozenSubmission = submission
            diagnostic = nil
            _ = await submit(submission, runtime: runtime)
        } catch let failure as SpaceChecklistEditingFailure {
            diagnostic = failure.diagnosticCode
        } catch let failure as SpaceChecklistRevisionFailure {
            diagnostic = failure.diagnosticCode
        } catch let failure as SpaceChecklistToggleFailure {
            diagnostic = failure.diagnosticCode
        } catch {
            diagnostic = SpaceChecklistToggleFailure.submissionInvalid.diagnosticCode
        }
    }

    @discardableResult
    public func submitCompleteDraft(
        _ draft: SpaceChecklistEditingDraft,
        from sourceUpdate: SpaceCoreDetailsUpdate
    ) async -> SpaceChecklistRevisionSubmissionOutcome {
        guard canSubmitCompleteDraft,
              let runtime,
              selectedSpaceId == sourceUpdate.request.spaceId,
              sourceUpdate.request.accountId == accountId,
              let row = Self.row(from: sourceUpdate),
              row.lifecycle == .active else {
            diagnostic = SpaceChecklistToggleFailure.currentEvidenceRequired.diagnosticCode
            return .refused
        }

        do {
            _ = try SpaceChecklistEditingPresentation(projecting: sourceUpdate).prepare()
            let targetCollection = try draft.collection()
            let submission = try FrozenSubmission(
                sourceUpdate: sourceUpdate,
                draft: draft,
                identity: makeIdentity(),
                capturedAt: try Self.canonicalTimestamp(now()),
                targetCollection: targetCollection,
                baseRevision: row.revision,
                settlementEvidenceSequence: evidenceSequence
            )
            frozenSubmission = submission
            diagnostic = nil
            return await submit(submission, runtime: runtime)
        } catch let failure as SpaceChecklistEditingFailure {
            diagnostic = failure.diagnosticCode
        } catch let failure as SpaceChecklistRevisionFailure {
            diagnostic = failure.diagnosticCode
        } catch {
            diagnostic = SpaceChecklistToggleFailure.submissionInvalid.diagnosticCode
        }
        return .refused
    }

    public func retryAmbiguousAcceptance() async {
        guard canRetryAmbiguousAcceptance,
              let runtime,
              let submission = ambiguousSubmission else { return }
        frozenSubmission = submission
        ambiguousSubmission = nil
        diagnostic = nil
        _ = await submit(submission, runtime: runtime)
    }

    private func submit(
        _ submission: FrozenSubmission,
        runtime: SpaceChecklistItemToggleStagingRuntime
    ) async -> SpaceChecklistRevisionSubmissionOutcome {
        let activeLifecycle = lifecycleGeneration
        let activeSelection = selectionGeneration
        isSubmitting = true
        defer {
            if lifecycleGeneration == activeLifecycle,
               selectionGeneration == activeSelection {
                isSubmitting = false
            }
        }

        do {
            guard let draft = submission.draft else {
                throw SpaceChecklistToggleFailure.submissionInvalid
            }
            let execution = try await SpaceChecklistRevisionUseCase(reviser: runtime).execute(
                draft: draft,
                currentUpdate: submission.sourceUpdate,
                operationId: submission.identity.operationId,
                actorPrincipalId: actorPrincipalId,
                operationContractVersion: operationContractVersion,
                capturedAt: submission.capturedAt
            )
            guard lifecycleGeneration == activeLifecycle,
                  selectionGeneration == activeSelection,
                  frozenSubmission == submission else { return .refused }

            let accepted = try submission.accepting(execution)
            frozenSubmission = accepted
            ambiguousSubmission = nil
            optimisticCollection = accepted.targetCollection
            operationState = execution.receipt.localState
            operationIdLabel = execution.receipt.operationId.rawValue
            await beginOperationObservation(
                submission: accepted,
                runtime: runtime,
                lifecycleGeneration: activeLifecycle,
                selectionGeneration: activeSelection
            )
            return .acceptedLocally
        } catch is CancellationError {
            guard lifecycleGeneration == activeLifecycle,
                  selectionGeneration == activeSelection else { return .refused }
            frozenSubmission = nil
            ambiguousSubmission = submission
            optimisticCollection = nil
            operationState = nil
            operationIdLabel = submission.identity.operationId.rawValue
            diagnostic = SpaceChecklistToggleFailure.localAcceptanceCancelled.diagnosticCode
            return .acceptanceUncertain
        } catch let failure as SpaceChecklistEditingFailure {
            guard lifecycleGeneration == activeLifecycle,
                  selectionGeneration == activeSelection else { return .refused }
            frozenSubmission = nil
            diagnostic = failure.diagnosticCode
            return .refused
        } catch let failure as SpaceChecklistRevisionFailure {
            guard lifecycleGeneration == activeLifecycle,
                  selectionGeneration == activeSelection else { return .refused }
            if failure == .localAcceptanceFailed {
                frozenSubmission = nil
                ambiguousSubmission = submission
                operationIdLabel = submission.identity.operationId.rawValue
            } else {
                frozenSubmission = nil
            }
            optimisticCollection = nil
            diagnostic = failure.diagnosticCode
            return failure == .localAcceptanceFailed ? .acceptanceUncertain : .refused
        } catch {
            guard lifecycleGeneration == activeLifecycle,
                  selectionGeneration == activeSelection else { return .refused }
            frozenSubmission = nil
            ambiguousSubmission = submission
            optimisticCollection = nil
            operationIdLabel = submission.identity.operationId.rawValue
            diagnostic = SpaceChecklistToggleFailure.localAcceptanceFailed.diagnosticCode
            return .acceptanceUncertain
        }
    }

    private func beginOperationObservation(
        submission: FrozenSubmission,
        runtime: SpaceChecklistItemToggleStagingRuntime,
        lifecycleGeneration: UUID,
        selectionGeneration: UUID
    ) async {
        await cancelAndDrainOperationObservation()
        guard self.lifecycleGeneration == lifecycleGeneration,
              self.selectionGeneration == selectionGeneration,
              frozenSubmission == submission else { return }
        operationObservationTask = Task { [weak self] in
            await self?.observeOperation(
                submission: submission,
                runtime: runtime,
                lifecycleGeneration: lifecycleGeneration,
                selectionGeneration: selectionGeneration
            )
        }
    }

    private func observeOperation(
        submission: FrozenSubmission,
        runtime: SpaceChecklistItemToggleStagingRuntime,
        lifecycleGeneration: UUID,
        selectionGeneration: UUID
    ) async {
        guard let expectation = submission.operationExpectation else { return }
        var iterator = runtime.watchOperation(expectation.operationId).makeAsyncIterator()
        defer {
            if self.lifecycleGeneration == lifecycleGeneration,
               self.selectionGeneration == selectionGeneration {
                operationObservationTask = nil
            }
        }
        do {
            while let snapshot = try await iterator.next() {
                try Task.checkCancellation()
                guard self.lifecycleGeneration == lifecycleGeneration,
                      self.selectionGeneration == selectionGeneration,
                      frozenSubmission == submission else { return }
                guard Self.validates(
                    snapshot,
                    expectation: expectation
                ),
                      Self.validTransition(
                          from: operationState,
                          to: snapshot.state.localState
                      ),
                      let localState = snapshot.state.localState else {
                    operationObservationTask?.cancel()
                    _ = try? await iterator.next()
                    guard self.lifecycleGeneration == lifecycleGeneration,
                          self.selectionGeneration == selectionGeneration else { return }
                    diagnostic = SpaceChecklistToggleFailure.invalidOperationEvidence
                        .diagnosticCode
                    return
                }
                operationState = localState
                operationIdLabel = snapshot.operationId.rawValue
                switch localState {
                case .queued, .applying:
                    break
                case .applied:
                    if Self.isAuthoritativeReadback(
                        currentUpdate,
                        matching: submission
                    ) {
                        settleSubmission(clearDiagnostic: true)
                        return
                    }
                case .rejected:
                    diagnostic = Self.rejectionDiagnostic(snapshot)
                    if evidenceSequence > submission.settlementEvidenceSequence,
                       Self.isSettledDetailEvidence(currentUpdate) {
                        settleSubmission(clearDiagnostic: false)
                        return
                    }
                case .superseded:
                    diagnostic = SpaceChecklistToggleFailure.operationSuperseded
                        .diagnosticCode
                    if evidenceSequence > submission.settlementEvidenceSequence,
                       Self.isSettledDetailEvidence(currentUpdate) {
                        settleSubmission(clearDiagnostic: false)
                        return
                    }
                case .resolved:
                    diagnostic = SpaceChecklistToggleFailure.operationResolved
                        .diagnosticCode
                    if evidenceSequence > submission.settlementEvidenceSequence,
                       Self.isSettledDetailEvidence(currentUpdate) {
                        settleSubmission(clearDiagnostic: false)
                        return
                    }
                }
            }
            guard !Task.isCancelled,
                  self.lifecycleGeneration == lifecycleGeneration,
                  self.selectionGeneration == selectionGeneration else { return }
            diagnostic = SpaceChecklistToggleFailure.operationSourceCompleted.diagnosticCode
        } catch is CancellationError {
            guard !Task.isCancelled,
                  self.lifecycleGeneration == lifecycleGeneration,
                  self.selectionGeneration == selectionGeneration else { return }
            diagnostic = SpaceChecklistToggleFailure.operationSourceCancelled.diagnosticCode
        } catch {
            guard self.lifecycleGeneration == lifecycleGeneration,
                  self.selectionGeneration == selectionGeneration else { return }
            diagnostic = SpaceChecklistToggleFailure.operationWatchFailed.diagnosticCode
        }
    }

    private func replaceSelection(with newSelection: SpaceID?) async {
        selectionGeneration = UUID()
        selectedSpaceId = newSelection
        currentUpdate = nil
        frozenSubmission = nil
        ambiguousSubmission = nil
        optimisticCollection = nil
        operationState = nil
        operationIdLabel = nil
        diagnostic = nil
        admission = newSelection == nil ? .waiting : .incomplete
        evidenceSequence = 0
        await cancelAndDrainOperationObservation()
    }

    private func settleSubmission(clearDiagnostic: Bool) {
        frozenSubmission = nil
        ambiguousSubmission = nil
        optimisticCollection = nil
        if clearDiagnostic {
            diagnostic = nil
        }
    }

    private func cancelAndDrainOperationObservation() async {
        let oldTask = operationObservationTask
        operationObservationTask = nil
        oldTask?.cancel()
        await oldTask?.value
    }
}

private extension SpaceChecklistItemToggleStagingExercise {
    struct FrozenSubmission: Equatable, Sendable {
        let sourceUpdate: SpaceCoreDetailsUpdate
        let draft: SpaceChecklistEditingDraft?
        let identity: SpaceChecklistItemToggleSubmissionIdentity
        let capturedAt: Date
        let targetCollection: SpaceChecklistCollection
        let baseRevision: UInt64
        let execution: SpaceChecklistRevisionExecutionResult?
        let operationExpectation: OperationExpectation?
        let settlementEvidenceSequence: UInt64

        init(
            sourceUpdate: SpaceCoreDetailsUpdate,
            draft: SpaceChecklistEditingDraft,
            identity: SpaceChecklistItemToggleSubmissionIdentity,
            capturedAt: Date,
            targetCollection: SpaceChecklistCollection,
            baseRevision: UInt64,
            execution: SpaceChecklistRevisionExecutionResult? = nil,
            operationExpectation: OperationExpectation? = nil,
            settlementEvidenceSequence: UInt64
        ) throws {
            guard sourceUpdate.request.accountId == draft.accountId,
                  sourceUpdate.request.spaceId == draft.spaceId else {
                throw SpaceChecklistToggleFailure.invalidDetailEvidence
            }
            self.sourceUpdate = sourceUpdate
            self.draft = draft
            self.identity = identity
            self.capturedAt = capturedAt
            self.targetCollection = targetCollection
            self.baseRevision = baseRevision
            self.execution = execution
            self.operationExpectation = operationExpectation
            self.settlementEvidenceSequence = settlementEvidenceSequence
        }

        init(
            recovering projection: SpaceChecklistRevisionLocalProjection,
            sourceUpdate: SpaceCoreDetailsUpdate?,
            expectedAccountId: AccountID,
            expectedActorPrincipalId: PrincipalID,
            expectedContractVersion: OperationContractVersion,
            settlementEvidenceSequence: UInt64
        ) throws {
            guard let sourceUpdate,
                  projection.accountId == expectedAccountId,
                  projection.actorPrincipalId == expectedActorPrincipalId,
                  projection.contractVersion == expectedContractVersion,
                  sourceUpdate.request.accountId == projection.accountId,
                  sourceUpdate.request.spaceId == projection.spaceId else {
                throw SpaceChecklistToggleFailure.invalidOperationEvidence
            }
            self.sourceUpdate = sourceUpdate
            draft = nil
            identity = SpaceChecklistItemToggleSubmissionIdentity(
                operationId: projection.operationId
            )
            capturedAt = projection.acceptedAt
            targetCollection = projection.collection
            baseRevision = projection.expectedRevision
            execution = nil
            operationExpectation = try OperationExpectation(projection: projection)
            self.settlementEvidenceSequence = settlementEvidenceSequence
        }

        func accepting(
            _ execution: SpaceChecklistRevisionExecutionResult
        ) throws -> Self {
            guard let draft else {
                throw SpaceChecklistToggleFailure.submissionInvalid
            }
            return try Self(
                sourceUpdate: sourceUpdate,
                draft: draft,
                identity: identity,
                capturedAt: capturedAt,
                targetCollection: targetCollection,
                baseRevision: baseRevision,
                execution: execution,
                operationExpectation: OperationExpectation(command: execution.command),
                settlementEvidenceSequence: settlementEvidenceSequence
            )
        }
    }

    struct OperationExpectation: Equatable, Sendable {
        let operationId: OperationID
        let accountId: AccountID
        let contractVersion: OperationContractVersion
        let fingerprint: OperationFingerprint
        let subject: LedgerEntityReference
        let baseRevision: UInt64

        init(command: ReviseSpaceChecklistsCommand) {
            operationId = command.envelope.operationId
            accountId = command.envelope.accountId
            contractVersion = command.envelope.contractVersion
            fingerprint = command.fingerprint
            subject = command.subject
            baseRevision = command.draft.expectedRevision.rawValue
        }

        init(projection: SpaceChecklistRevisionLocalProjection) throws {
            operationId = projection.operationId
            accountId = projection.accountId
            contractVersion = projection.contractVersion
            fingerprint = projection.fingerprint
            subject = LedgerEntityReference(
                kind: .space,
                id: try EntityID(validating: projection.spaceId.rawValue)
            )
            baseRevision = projection.expectedRevision
        }
    }

    enum SpaceChecklistToggleFailure: Error {
        case invalidDetailEvidence
        case currentEvidenceRequired
        case submissionInvalid
        case localAcceptanceCancelled
        case localAcceptanceFailed
        case invalidOperationEvidence
        case operationSuperseded
        case operationResolved
        case operationSourceCompleted
        case operationSourceCancelled
        case operationWatchFailed

        var diagnosticCode: String {
            switch self {
            case .invalidDetailEvidence: "space_checklist_toggle_detail_evidence_invalid"
            case .currentEvidenceRequired: "space_checklist_toggle_current_evidence_required"
            case .submissionInvalid: "space_checklist_toggle_submission_invalid"
            case .localAcceptanceCancelled: "space_checklist_toggle_local_acceptance_cancelled"
            case .localAcceptanceFailed: "space_checklist_toggle_local_acceptance_failed"
            case .invalidOperationEvidence: "space_checklist_toggle_operation_evidence_invalid"
            case .operationSuperseded: "space_checklist_toggle_operation_superseded"
            case .operationResolved: "space_checklist_toggle_operation_resolved"
            case .operationSourceCompleted: "space_checklist_toggle_operation_source_completed"
            case .operationSourceCancelled: "space_checklist_toggle_operation_source_cancelled"
            case .operationWatchFailed: "space_checklist_toggle_operation_watch_failed"
            }
        }
    }

    static func projectAdmission(
        from update: SpaceCoreDetailsUpdate
    ) throws -> SpaceChecklistItemToggleAdmission {
        let presentation = try SpaceChecklistEditingPresentation(projecting: update)
        if let row = row(from: update), row.lifecycle == .archived {
            return .archived
        }
        switch presentation.state {
        case .editableCurrent:
            return .ready
        case .editableStale:
            return .retryableStale
        case .waiting:
            return .waiting
        case .authoritativeAbsence:
            return .authoritativeAbsence
        case .unavailable, .requiredUpdate:
            return .unavailable
        case .incomplete:
            return .incomplete
        }
    }

    static func row(
        from update: SpaceCoreDetailsUpdate?
    ) -> SpaceCoreDetailsSnapshot? {
        guard let update else { return nil }
        switch update.state {
        case .snapshot(let snapshot):
            return snapshot.row
        case .failed(.retryable, let cached):
            return cached?.row
        case .waiting, .failed:
            return nil
        }
    }

    static func checklistRevisionProjection(
        from update: SpaceCoreDetailsUpdate?
    ) -> SpaceChecklistRevisionLocalProjection? {
        guard let update else { return nil }
        switch update.state {
        case .snapshot(let snapshot):
            return snapshot.checklistRevisionProjection
        case .failed(.retryable, let cached):
            return cached?.checklistRevisionProjection
        case .waiting, .failed:
            return nil
        }
    }

    static func canonicalTimestamp(_ timestamp: Date) throws -> Date {
        let rawMilliseconds = timestamp.timeIntervalSince1970 * 1_000
        guard rawMilliseconds.isFinite,
              let milliseconds = Int64(exactly: rawMilliseconds.rounded(.towardZero)),
              milliseconds >= 0 else {
            throw SpaceChecklistRevisionFailure.invalidCapturedAt
        }
        return Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }

    static func validates(
        _ snapshot: OperationSnapshot,
        expectation: OperationExpectation
    ) -> Bool {
        guard snapshot.operationId == expectation.operationId,
              snapshot.accountId == expectation.accountId,
              snapshot.contractVersion == expectation.contractVersion,
              snapshot.fingerprint == expectation.fingerprint,
              snapshot.acceptedAt.timeIntervalSinceReferenceDate.isFinite,
              snapshot.updatedAt.timeIntervalSinceReferenceDate.isFinite,
              snapshot.updatedAt >= snapshot.acceptedAt else {
            return false
        }
        switch snapshot.state {
        case .applying(_, let startedAt):
            return startedAt.timeIntervalSinceReferenceDate.isFinite
                && startedAt >= snapshot.acceptedAt
                && startedAt <= snapshot.updatedAt
        case .applied(let result):
            return valid(
                result,
                through: snapshot.updatedAt,
                subject: expectation.subject,
                after: expectation.baseRevision
            )
        case .rejected(let rejection):
            return rejection.rejectedAt.timeIntervalSinceReferenceDate.isFinite
                && rejection.rejectedAt >= snapshot.acceptedAt
                && rejection.rejectedAt <= snapshot.updatedAt
        case .superseded(let original, let correction):
            return valid(
                original,
                through: snapshot.updatedAt,
                subject: expectation.subject,
                after: expectation.baseRevision
            )
                && correction.operationId != snapshot.operationId
                && correction.correctedAt.timeIntervalSinceReferenceDate.isFinite
                && correction.correctedAt >= original.completedAt
                && correction.correctedAt <= snapshot.updatedAt
        case .resolved(let rejection, let resolution):
            return rejection.rejectedAt.timeIntervalSinceReferenceDate.isFinite
                && resolution.resolvedAt.timeIntervalSinceReferenceDate.isFinite
                && rejection.rejectedAt >= snapshot.acceptedAt
                && resolution.resolvedAt >= rejection.rejectedAt
                && resolution.resolvedAt <= snapshot.updatedAt
        case .queued:
            return true
        case .draft:
            return false
        }
    }

    static func valid(
        _ result: AppliedOperationResult,
        through updatedAt: Date,
        subject: LedgerEntityReference,
        after baseRevision: UInt64
    ) -> Bool {
        let matching = result.affectedRevisions.filter { $0.entity == subject }
        return result.serverReceivedAt.timeIntervalSinceReferenceDate.isFinite
            && result.completedAt.timeIntervalSinceReferenceDate.isFinite
            && result.completedAt >= result.serverReceivedAt
            && result.completedAt <= updatedAt
            && result.affectedRevisions.count == 1
            && matching.count == 1
            && matching[0].revision > baseRevision
    }

    static func validTransition(
        from current: LocalOperationState?,
        to next: LocalOperationState?
    ) -> Bool {
        guard let next else { return false }
        guard let current else { return true }
        switch (current, next) {
        case (.queued, .queued), (.queued, .applying), (.queued, .applied),
             (.queued, .rejected), (.queued, .superseded), (.queued, .resolved),
             (.applying, .applying), (.applying, .applied), (.applying, .rejected),
             (.applying, .superseded), (.applying, .resolved),
             (.applied, .applied), (.applied, .superseded),
             (.rejected, .rejected), (.rejected, .resolved),
             (.superseded, .superseded), (.resolved, .resolved):
            return true
        default:
            return false
        }
    }

    static func isAuthoritativeReadback(
        _ update: SpaceCoreDetailsUpdate?,
        matching submission: FrozenSubmission
    ) -> Bool {
        guard let update,
              case .snapshot(let snapshot) = update.state,
              snapshot.local.quality == .ready,
              snapshot.local.isCompleteForQuery,
              snapshot.checklistRevisionProjection == nil,
              let readbackRow = snapshot.row,
              let sourceRow = row(from: submission.sourceUpdate),
              readbackRow.revision > submission.baseRevision,
              readbackRow.updatedAt > sourceRow.updatedAt,
              readbackRow.checklists == submission.targetCollection else {
            return false
        }
        return true
    }

    static func isRefreshTerminal(_ state: LocalOperationState?) -> Bool {
        state == .rejected || state == .superseded || state == .resolved
    }

    static func isSettledDetailEvidence(_ update: SpaceCoreDetailsUpdate?) -> Bool {
        guard let update else { return false }
        switch update.state {
        case .snapshot(let snapshot):
            return snapshot.local.quality == .ready
                && snapshot.local.isCompleteForQuery
                && snapshot.checklistRevisionProjection == nil
        case .failed(.retryable, _):
            return false
        case .waiting, .failed:
            return false
        }
    }

    static func rejectionDiagnostic(_ snapshot: OperationSnapshot) -> String {
        guard case .rejected(let rejection) = snapshot.state else {
            return "space_checklist_toggle_rejected"
        }
        return "space_checklist_toggle_rejected_\(rejection.error.code.rawValue)"
    }
}
