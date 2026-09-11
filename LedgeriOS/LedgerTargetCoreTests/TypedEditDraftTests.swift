import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Typed Edit Draft and Submission")
struct TypedEditDraftTests {
    @Test("Typed fields and validation preserve unchanged, set, and clear intent")
    func fieldIntentAndValidationAreTyped() throws {
        let fields: [EditFieldValue<String>] = [
            .unchanged,
            .set(""),
            .set("Walnut"),
            .clear
        ]
        let restored = try OperationContractCodec.decode(
            [EditFieldValue<String>].self,
            from: OperationContractCodec.encode(fields)
        )
        #expect(restored == fields)
        #expect(fields.map(\.isChanged) == [false, true, true, true])
        #expect(fields[0].applying(to: "Existing") == "Existing")
        #expect(fields[1].applying(to: "Existing") == "")
        #expect(fields[3].applying(to: "Existing") == nil)

        let unchangedDraft = try Self.draft(payload: FixturePayload(
            name: .unchanged,
            note: .unchanged,
            quantity: .unchanged
        ))
        #expect(try EditDraftValidation.evaluate(unchangedDraft, issues: []) == .unchanged(unchangedDraft))

        let changedDraft = try Self.draft(payload: FixturePayload(
            name: .set("Walnut desk"),
            note: .clear,
            quantity: .set(0)
        ))
        let nameField = try EditFieldID(validating: "name")
        let requiredCode = try EditValidationCode(validating: "required_value")
        let invalidCode = try EditValidationCode(validating: "invalid_value")
        let issues = [
            EditDraftValidationIssue(fieldId: nameField, code: requiredCode),
            EditDraftValidationIssue(fieldId: nil, code: invalidCode)
        ]
        let restoredIssues = try OperationContractCodec.decode(
            [EditDraftValidationIssue].self,
            from: OperationContractCodec.encode(issues)
        )
        #expect(restoredIssues == issues)
        #expect(try EditDraftValidation.evaluate(changedDraft, issues: issues) == .invalid(
            changedDraft,
            issues: [issues[1], issues[0]]
        ))
        #expect(Self.captureFailure {
            _ = try EditDraftValidation.evaluate(changedDraft, issues: [issues[0], issues[0]])
        } == .duplicateValidationIssue(nameField, requiredCode))

        guard case .valid(let validated) = try EditDraftValidation.evaluate(
            changedDraft,
            issues: []
        ) else {
            Issue.record("Changed draft should validate")
            return
        }
        #expect(validated.draft == changedDraft)
        #expect(changedDraft.payload.quantity.applying(to: 4) == 0)
        #expect(changedDraft.payload.note.applying(to: "Existing note") == nil)
    }

    @Test("Draft and accepted submission binding survive restart without claiming server apply")
    func restartPreservesDraftAndBinding() throws {
        let payload = FixturePayload.changed(name: "Restarted")
        let draft = try Self.draft(payload: payload)
        let validated = try Self.validated(draft)
        let envelope = try Self.envelope(payload: payload)
        let binding = try EditSubmissionBinding.bind(validated, to: envelope)
        let fixture = RestartFixture(
            draft: draft,
            envelopeData: try OperationContractCodec.encode(envelope)
        )
        let restored = try OperationContractCodec.decode(
            RestartFixture.self,
            from: OperationContractCodec.encode(fixture)
        )
        let restoredEnvelope = try OperationContractCodec.decode(
            OperationEnvelope<FixturePayload>.self,
            from: restored.envelopeData
        )
        let restoredBinding = try EditSubmissionBinding.bind(
            Self.validated(restored.draft),
            to: restoredEnvelope
        )
        let expectedFingerprint = try OperationFingerprint.make(for: envelope)

        #expect(restored == fixture)
        #expect(restoredBinding == binding)
        #expect(restoredBinding.expectedRevision == draft.expectedRevision)
        #expect(restoredBinding.subject == draft.subject)
        #expect(restoredBinding.fingerprint == expectedFingerprint)

        var journal = OperationJournal()
        let receipt = try journal.accept(envelope, at: Self.t0)
        var reducer = EditSubmissionReducer(binding: restoredBinding)
        let accepted = try reducer.apply(receipt)
        #expect(accepted.phase == .locallyAccepted)
        #expect(accepted.updatedAt == nil)
        #expect(journal.snapshot(for: envelope.operationId)?.state.phase == .queued)
        #expect(accepted.phase != .applied)
    }

    @Test("Submission binding and presentation reject stale or mismatched operations")
    func submissionBindingFailsClosed() throws {
        let payload = FixturePayload.changed(name: "Bound")
        let draft = try Self.draft(payload: payload)
        let validated = try Self.validated(draft)
        let envelope = try Self.envelope(payload: payload)
        let binding = try EditSubmissionBinding.bind(validated, to: envelope)

        #expect(Self.captureFailure {
            _ = try EditSubmissionBinding.bind(
                validated,
                to: Self.envelope(payload: payload, account: "account-b")
            )
        } == .draftAccountMismatch)
        #expect(Self.captureFailure {
            _ = try EditSubmissionBinding.bind(
                validated,
                to: Self.envelope(payload: payload, actor: "principal-b")
            )
        } == .draftActorMismatch)
        #expect(Self.captureFailure {
            _ = try EditSubmissionBinding.bind(
                validated,
                to: Self.envelope(payload: payload, contract: "operation-v2")
            )
        } == .draftContractMismatch)
        #expect(Self.captureFailure {
            _ = try EditSubmissionBinding.bind(
                validated,
                to: Self.envelope(payload: .changed(name: "Different"))
            )
        } == .draftPayloadMismatch)
        #expect(Self.captureFailure {
            _ = try EditSubmissionBinding.bind(
                validated,
                to: Self.envelope(payload: payload, revisionPreconditions: [])
            )
        } == .missingExpectedRevision(draft.subject))
        #expect(Self.captureFailure {
            _ = try EditSubmissionBinding.bind(
                validated,
                to: Self.envelope(payload: payload, revisionSubjectId: "project-other")
            )
        } == .missingExpectedRevision(draft.subject))
        #expect(Self.captureFailure {
            _ = try EditSubmissionBinding.bind(
                validated,
                to: Self.envelope(payload: payload, revisionPreconditions: [7, 7])
            )
        } == .duplicateExpectedRevision(draft.subject))
        #expect(Self.captureFailure {
            _ = try EditSubmissionBinding.bind(
                validated,
                to: Self.envelope(payload: payload, revisionPreconditions: [8])
            )
        } == .expectedRevisionMismatch(expected: 7, actual: 8))

        var reducer = EditSubmissionReducer(binding: binding)
        _ = try reducer.apply(OperationReceipt(operationId: binding.operationId, localState: .queued))
        let before = reducer.presentation
        let mismatches: [(OperationSnapshot, TypedEditContractFailure)] = try [
            (
                Self.snapshot(
                    binding: binding,
                    operationId: OperationID(validating: "operation-other"),
                    state: .queued(attemptCount: 0, lastTransientError: nil)
                ),
                .operationReceiptMismatch
            ),
            (
                Self.snapshot(
                    binding: binding,
                    accountId: AccountID(validating: "account-b"),
                    state: .queued(attemptCount: 0, lastTransientError: nil)
                ),
                .operationAccountMismatch
            ),
            (
                Self.snapshot(
                    binding: binding,
                    contractVersion: OperationContractVersion(validating: "operation-v2"),
                    state: .queued(attemptCount: 0, lastTransientError: nil)
                ),
                .operationContractMismatch
            ),
            (
                Self.snapshot(
                    binding: binding,
                    fingerprint: OperationFingerprint(validating: String(repeating: "0", count: 64)),
                    state: .queued(attemptCount: 0, lastTransientError: nil)
                ),
                .operationFingerprintMismatch
            )
        ]
        for (snapshot, expectedFailure) in mismatches {
            #expect(Self.captureFailure { _ = try reducer.apply(snapshot) } == expectedFailure)
            #expect(reducer.presentation == before)
        }

        #expect(Self.captureFailure {
            _ = try reducer.apply(Self.snapshot(binding: binding, state: .draft))
        } == .unacceptedOperationState)
        #expect(reducer.presentation == before)

        let appliedResult = AppliedOperationResult(
            resultCode: try ApplicationResultCode(validating: "project_updated"),
            serverReceivedAt: Self.t1,
            completedAt: Self.t2
        )
        _ = try reducer.apply(Self.snapshot(
            binding: binding,
            updatedAt: Self.t3,
            state: .applied(appliedResult)
        ))
        let afterApplied = reducer.presentation
        #expect(Self.captureFailure {
            _ = try reducer.apply(OperationReceipt(
                operationId: binding.operationId,
                localState: .queued
            ))
        } == .staleOperationReceipt)
        #expect(reducer.presentation == afterApplied)
        #expect(Self.captureFailure {
            _ = try reducer.apply(Self.snapshot(
                binding: binding,
                updatedAt: Self.t2,
                state: .queued(attemptCount: 0, lastTransientError: nil)
            ))
        } == .staleOperationSnapshot)
        #expect(reducer.presentation == afterApplied)
        #expect(Self.captureFailure {
            _ = try reducer.apply(Self.snapshot(
                binding: binding,
                updatedAt: Self.t3,
                state: .queued(attemptCount: 0, lastTransientError: nil)
            ))
        } == .conflictingOperationSnapshot)
        #expect(reducer.presentation == afterApplied)
        #expect(Self.captureFailure {
            _ = try reducer.apply(Self.snapshot(
                binding: binding,
                updatedAt: Self.t4,
                state: .queued(attemptCount: 0, lastTransientError: nil)
            ))
        } == .illegalOperationPresentationTransition(from: .applied, to: .queued))
        #expect(reducer.presentation == afterApplied)
    }

    @Test("Shared operation lifecycle maps to stable edit submission presentation")
    func operationStatesMapToPresentation() throws {
        let payload = FixturePayload.changed(name: "Presentation")
        let draft = try Self.draft(payload: payload)
        let binding = try EditSubmissionBinding.bind(
            Self.validated(draft),
            to: Self.envelope(payload: payload)
        )
        let applied = AppliedOperationResult(
            resultCode: try ApplicationResultCode(validating: "project_updated"),
            serverReceivedAt: Self.t1,
            completedAt: Self.t2
        )
        let rejectionResolution = RejectionResolution(
            code: try ResolutionCode(validating: "corrected_input"),
            resolvedAt: Self.t3
        )
        let correction = CorrectionReference(
            operationId: try OperationID(validating: "operation-correction"),
            correctedAt: Self.t3
        )

        let states: [(OperationState, EditSubmissionPhase)] = try [
            (.queued(attemptCount: 0, lastTransientError: nil), .queued),
            (
                .queued(
                    attemptCount: 1,
                    lastTransientError: Self.error(
                        code: "transport_unavailable",
                        category: .transientInfrastructure,
                        retry: .automatic
                    )
                ),
                .retrying
            ),
            (.applying(attempt: 1, startedAt: Self.t1), .applying),
            (.applied(applied), .applied),
            (.rejected(Self.rejection(.validation)), .rejected),
            (.rejected(Self.rejection(.conflict)), .conflicted),
            (.rejected(Self.rejection(.authorization)), .unavailable),
            (.rejected(Self.rejection(.invariant)), .unavailable),
            (.rejected(Self.rejection(.authentication)), .reauthenticate),
            (.rejected(Self.rejection(.unsupportedContract)), .requiredUpdate),
            (.rejected(Self.rejection(.requiredUpdate)), .requiredUpdate),
            (.rejected(Self.rejection(.transientInfrastructure)), .retrying),
            (.superseded(original: applied, correction: correction), .superseded),
            (
                .resolved(
                    rejection: Self.rejection(.validation),
                    resolution: rejectionResolution
                ),
                .resolved
            )
        ]
        for (state, expectedPhase) in states {
            var reducer = EditSubmissionReducer(binding: binding)
            let presentation = try reducer.apply(Self.snapshot(binding: binding, state: state))
            #expect(presentation.phase == expectedPhase)
            #expect(presentation.operationId == binding.operationId)
            #expect(presentation.updatedAt == Self.t3)
        }

        for (localState, expectedPhase) in [
            (LocalOperationState.queued, EditSubmissionPhase.locallyAccepted),
            (.applying, .applying),
            (.applied, .applied),
            (.rejected, .rejected),
            (.superseded, .superseded),
            (.resolved, .resolved)
        ] {
            var reducer = EditSubmissionReducer(binding: binding)
            let presentation = try reducer.apply(OperationReceipt(
                operationId: binding.operationId,
                localState: localState
            ))
            #expect(presentation.phase == expectedPhase)
            #expect(presentation.updatedAt == nil)
        }
    }

    private static let t0 = Date(timeIntervalSince1970: 1_800_200_000)
    private static let t1 = Date(timeIntervalSince1970: 1_800_200_001)
    private static let t2 = Date(timeIntervalSince1970: 1_800_200_002)
    private static let t3 = Date(timeIntervalSince1970: 1_800_200_003)
    private static let t4 = Date(timeIntervalSince1970: 1_800_200_004)

    private static func draft(
        payload: FixturePayload
    ) throws -> TypedEditDraft<FixturePayload> {
        TypedEditDraft(
            draftId: try EditDraftID(validating: "draft-001"),
            accountId: try AccountID(validating: "account-a"),
            actorPrincipalId: try PrincipalID(validating: "principal-a"),
            operationContractVersion: try OperationContractVersion(validating: "operation-v1"),
            subject: LedgerEntityReference(
                kind: .project,
                id: try EntityID(validating: "project-001")
            ),
            expectedRevision: 7,
            localDataVersion: try LocalDataVersion(validating: "local-7"),
            capturedAt: t0,
            payload: payload
        )
    }

    private static func validated(
        _ draft: TypedEditDraft<FixturePayload>
    ) throws -> ValidatedEditDraft<FixturePayload> {
        guard case .valid(let validated) = try EditDraftValidation.evaluate(draft, issues: []) else {
            throw TypedEditContractFailure.draftPayloadMismatch
        }
        return validated
    }

    private static func envelope(
        payload: FixturePayload,
        account: String = "account-a",
        actor: String = "principal-a",
        contract: String = "operation-v1",
        revisionSubjectId: String = "project-001",
        revisionPreconditions: [UInt64] = [7]
    ) throws -> OperationEnvelope<FixturePayload> {
        let subject = LedgerEntityReference(
            kind: .project,
            id: try EntityID(validating: revisionSubjectId)
        )
        return OperationEnvelope(
            operationId: try OperationID(validating: "operation-edit-001"),
            contractVersion: try OperationContractVersion(validating: contract),
            accountId: try AccountID(validating: account),
            actorPrincipalId: try PrincipalID(validating: actor),
            clientCreatedAt: t0,
            payload: payload,
            preconditions: revisionPreconditions.map {
                .expectedRevision(subject: subject, revision: $0)
            }
        )
    }

    private static func snapshot(
        binding: EditSubmissionBinding,
        operationId: OperationID? = nil,
        accountId: AccountID? = nil,
        contractVersion: OperationContractVersion? = nil,
        fingerprint: OperationFingerprint? = nil,
        updatedAt: Date = t3,
        state: OperationState
    ) -> OperationSnapshot {
        OperationSnapshot(
            operationId: operationId ?? binding.operationId,
            accountId: accountId ?? binding.accountId,
            contractVersion: contractVersion ?? binding.contractVersion,
            fingerprint: fingerprint ?? binding.fingerprint,
            acceptedAt: t0,
            updatedAt: updatedAt,
            state: state
        )
    }

    private static func error(
        code: String,
        category: ApplicationErrorCategory,
        retry: RetryDisposition
    ) throws -> ApplicationErrorSummary {
        ApplicationErrorSummary(
            code: try ApplicationErrorCode(validating: code),
            category: category,
            retryDisposition: retry
        )
    }

    private static func rejection(
        _ category: ApplicationErrorCategory
    ) throws -> OperationRejection {
        let retry: RetryDisposition
        switch category {
        case .transientInfrastructure:
            retry = .automatic
        case .validation, .conflict:
            retry = .afterUserCorrection
        case .authentication:
            retry = .afterReauthentication
        case .unsupportedContract, .requiredUpdate:
            retry = .afterClientUpdate
        case .authorization, .invariant:
            retry = .never
        }
        return OperationRejection(
            error: try error(
                code: "edit_\(category.rawValue.lowercased())",
                category: category,
                retry: retry
            ),
            rejectedAt: t2
        )
    }

    private static func captureFailure(
        _ operation: () throws -> Void
    ) -> TypedEditContractFailure? {
        do {
            try operation()
            return nil
        } catch let failure as TypedEditContractFailure {
            return failure
        } catch {
            return nil
        }
    }

    private struct FixturePayload: TypedEditPayload {
        let name: EditFieldValue<String>
        let note: EditFieldValue<String>
        let quantity: EditFieldValue<Int>

        var hasChanges: Bool {
            name.isChanged || note.isChanged || quantity.isChanged
        }

        static func changed(name: String) -> Self {
            Self(name: .set(name), note: .unchanged, quantity: .unchanged)
        }
    }

    private struct RestartFixture: Codable, Equatable, Sendable {
        let draft: TypedEditDraft<FixturePayload>
        let envelopeData: Data
    }
}
