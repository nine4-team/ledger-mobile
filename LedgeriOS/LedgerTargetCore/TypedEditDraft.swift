import Foundation

public enum TypedEditContractFailure: Error, Equatable, Sendable {
    case duplicateValidationIssue(EditFieldID, EditValidationCode)
    case draftAccountMismatch
    case draftActorMismatch
    case draftContractMismatch
    case draftPayloadMismatch
    case missingExpectedRevision(LedgerEntityReference)
    case duplicateExpectedRevision(LedgerEntityReference)
    case expectedRevisionMismatch(expected: UInt64, actual: UInt64)
    case operationReceiptMismatch
    case operationAccountMismatch
    case operationContractMismatch
    case operationFingerprintMismatch
    case unacceptedOperationState
    case staleOperationReceipt
    case staleOperationSnapshot
    case conflictingOperationSnapshot
    case illegalOperationPresentationTransition(
        from: EditSubmissionPhase,
        to: EditSubmissionPhase
    )
}

public enum EditDraftIDTag: Sendable {}
public enum EditFieldIDTag: Sendable {}
public enum EditValidationCodeTag: Sendable {}

public typealias EditDraftID = LedgerIdentifier<EditDraftIDTag>
public typealias EditFieldID = StableCode<EditFieldIDTag>
public typealias EditValidationCode = StableCode<EditValidationCodeTag>

public enum EditFieldValue<Value>: Codable, Equatable, Sendable
where Value: Codable & Equatable & Sendable {
    case unchanged
    case set(Value)
    case clear

    public var isChanged: Bool {
        switch self {
        case .unchanged:
            false
        case .set, .clear:
            true
        }
    }

    public func applying(to currentValue: Value?) -> Value? {
        switch self {
        case .unchanged:
            currentValue
        case .set(let value):
            value
        case .clear:
            nil
        }
    }
}

public protocol TypedEditPayload: Codable, Equatable, Sendable {
    var hasChanges: Bool { get }
}

public struct TypedEditDraft<Payload>: Codable, Equatable, Sendable
where Payload: TypedEditPayload {
    public let draftId: EditDraftID
    public let accountId: AccountID
    public let actorPrincipalId: PrincipalID
    public let operationContractVersion: OperationContractVersion
    public let subject: LedgerEntityReference
    public let expectedRevision: UInt64
    public let localDataVersion: LocalDataVersion?
    public let capturedAt: Date
    public let payload: Payload

    public init(
        draftId: EditDraftID,
        accountId: AccountID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        subject: LedgerEntityReference,
        expectedRevision: UInt64,
        localDataVersion: LocalDataVersion?,
        capturedAt: Date,
        payload: Payload
    ) {
        self.draftId = draftId
        self.accountId = accountId
        self.actorPrincipalId = actorPrincipalId
        self.operationContractVersion = operationContractVersion
        self.subject = subject
        self.expectedRevision = expectedRevision
        self.localDataVersion = localDataVersion
        self.capturedAt = capturedAt
        self.payload = payload
    }
}

public struct EditDraftValidationIssue: Codable, Equatable, Hashable, Sendable {
    public let fieldId: EditFieldID?
    public let code: EditValidationCode

    public init(fieldId: EditFieldID?, code: EditValidationCode) {
        self.fieldId = fieldId
        self.code = code
    }
}

public struct ValidatedEditDraft<Payload>: Equatable, Sendable
where Payload: TypedEditPayload {
    public let draft: TypedEditDraft<Payload>

    fileprivate init(draft: TypedEditDraft<Payload>) {
        self.draft = draft
    }
}

public enum EditDraftValidationResult<Payload>: Equatable, Sendable
where Payload: TypedEditPayload {
    case unchanged(TypedEditDraft<Payload>)
    case invalid(TypedEditDraft<Payload>, issues: [EditDraftValidationIssue])
    case valid(ValidatedEditDraft<Payload>)
}

public enum EditDraftValidation {
    public static func evaluate<Payload>(
        _ draft: TypedEditDraft<Payload>,
        issues: [EditDraftValidationIssue]
    ) throws -> EditDraftValidationResult<Payload> where Payload: TypedEditPayload {
        let sortedIssues = issues.sorted {
            let lhsField = $0.fieldId?.rawValue ?? ""
            let rhsField = $1.fieldId?.rawValue ?? ""
            if lhsField != rhsField { return lhsField < rhsField }
            return $0.code.rawValue < $1.code.rawValue
        }
        var seen: Set<EditDraftValidationIssue> = []
        for issue in sortedIssues where !seen.insert(issue).inserted {
            let fieldId: EditFieldID
            if let issueFieldId = issue.fieldId {
                fieldId = issueFieldId
            } else {
                fieldId = try EditFieldID(validating: "whole_draft")
            }
            throw TypedEditContractFailure.duplicateValidationIssue(
                fieldId,
                issue.code
            )
        }
        guard sortedIssues.isEmpty else {
            return .invalid(draft, issues: sortedIssues)
        }
        guard draft.payload.hasChanges else {
            return .unchanged(draft)
        }
        return .valid(ValidatedEditDraft(draft: draft))
    }
}

public struct EditSubmissionBinding: Equatable, Sendable {
    public let draftId: EditDraftID
    public let accountId: AccountID
    public let actorPrincipalId: PrincipalID
    public let subject: LedgerEntityReference
    public let expectedRevision: UInt64
    public let operationId: OperationID
    public let contractVersion: OperationContractVersion
    public let fingerprint: OperationFingerprint

    public static func bind<Payload>(
        _ validated: ValidatedEditDraft<Payload>,
        to envelope: OperationEnvelope<Payload>
    ) throws -> Self where Payload: TypedEditPayload {
        let draft = validated.draft
        guard envelope.accountId == draft.accountId else {
            throw TypedEditContractFailure.draftAccountMismatch
        }
        guard envelope.actorPrincipalId == draft.actorPrincipalId else {
            throw TypedEditContractFailure.draftActorMismatch
        }
        guard envelope.contractVersion == draft.operationContractVersion else {
            throw TypedEditContractFailure.draftContractMismatch
        }
        guard envelope.payload == draft.payload else {
            throw TypedEditContractFailure.draftPayloadMismatch
        }
        let revisionPreconditions = envelope.preconditions.compactMap { preconditionValue in
            switch preconditionValue {
            case .expectedRevision(let subject, let revision) where subject == draft.subject:
                (subject, revision)
            default:
                nil
            }
        }
        guard !revisionPreconditions.isEmpty else {
            throw TypedEditContractFailure.missingExpectedRevision(draft.subject)
        }
        guard revisionPreconditions.count == 1 else {
            throw TypedEditContractFailure.duplicateExpectedRevision(draft.subject)
        }
        let actualRevision = revisionPreconditions[0].1
        guard actualRevision == draft.expectedRevision else {
            throw TypedEditContractFailure.expectedRevisionMismatch(
                expected: draft.expectedRevision,
                actual: actualRevision
            )
        }
        return try Self(
            draftId: draft.draftId,
            accountId: draft.accountId,
            actorPrincipalId: draft.actorPrincipalId,
            subject: draft.subject,
            expectedRevision: draft.expectedRevision,
            operationId: envelope.operationId,
            contractVersion: envelope.contractVersion,
            fingerprint: OperationFingerprint.make(for: envelope)
        )
    }

    fileprivate init(
        draftId: EditDraftID,
        accountId: AccountID,
        actorPrincipalId: PrincipalID,
        subject: LedgerEntityReference,
        expectedRevision: UInt64,
        operationId: OperationID,
        contractVersion: OperationContractVersion,
        fingerprint: OperationFingerprint
    ) {
        self.draftId = draftId
        self.accountId = accountId
        self.actorPrincipalId = actorPrincipalId
        self.subject = subject
        self.expectedRevision = expectedRevision
        self.operationId = operationId
        self.contractVersion = contractVersion
        self.fingerprint = fingerprint
    }

    public func validate(_ receipt: OperationReceipt) throws {
        guard receipt.operationId == operationId else {
            throw TypedEditContractFailure.operationReceiptMismatch
        }
    }

    public func validate(_ snapshot: OperationSnapshot) throws {
        guard snapshot.operationId == operationId else {
            throw TypedEditContractFailure.operationReceiptMismatch
        }
        guard snapshot.accountId == accountId else {
            throw TypedEditContractFailure.operationAccountMismatch
        }
        guard snapshot.contractVersion == contractVersion else {
            throw TypedEditContractFailure.operationContractMismatch
        }
        guard snapshot.fingerprint == fingerprint else {
            throw TypedEditContractFailure.operationFingerprintMismatch
        }
    }
}

public enum EditSubmissionPhase: String, Codable, CaseIterable, Sendable {
    case locallyAccepted
    case queued
    case applying
    case applied
    case rejected
    case conflicted
    case retrying
    case unavailable
    case reauthenticate
    case requiredUpdate
    case superseded
    case resolved
}

public struct EditSubmissionPresentation: Codable, Equatable, Sendable {
    public let operationId: OperationID
    public let phase: EditSubmissionPhase
    public let updatedAt: Date?

    public init(
        operationId: OperationID,
        phase: EditSubmissionPhase,
        updatedAt: Date?
    ) {
        self.operationId = operationId
        self.phase = phase
        self.updatedAt = updatedAt
    }
}

public struct EditSubmissionReducer: Sendable {
    public let binding: EditSubmissionBinding
    public private(set) var presentation: EditSubmissionPresentation?

    public init(binding: EditSubmissionBinding) {
        self.binding = binding
        presentation = nil
    }

    @discardableResult
    public mutating func apply(
        _ receipt: OperationReceipt
    ) throws -> EditSubmissionPresentation {
        try binding.validate(receipt)
        guard presentation?.updatedAt == nil else {
            throw TypedEditContractFailure.staleOperationReceipt
        }
        let phase = Self.phase(for: receipt.localState)
        try Self.validateTransition(from: presentation?.phase, to: phase)
        let next = EditSubmissionPresentation(
            operationId: binding.operationId,
            phase: phase,
            updatedAt: nil
        )
        presentation = next
        return next
    }

    @discardableResult
    public mutating func apply(
        _ snapshot: OperationSnapshot
    ) throws -> EditSubmissionPresentation {
        try binding.validate(snapshot)
        let phase = try Self.phase(for: snapshot.state)
        if let currentTimestamp = presentation?.updatedAt {
            guard snapshot.updatedAt >= currentTimestamp else {
                throw TypedEditContractFailure.staleOperationSnapshot
            }
            if snapshot.updatedAt == currentTimestamp,
               presentation?.phase != phase {
                throw TypedEditContractFailure.conflictingOperationSnapshot
            }
        }
        try Self.validateTransition(from: presentation?.phase, to: phase)
        let next = EditSubmissionPresentation(
            operationId: binding.operationId,
            phase: phase,
            updatedAt: snapshot.updatedAt
        )
        presentation = next
        return next
    }

    private static func phase(for state: OperationState) throws -> EditSubmissionPhase {
        switch state {
        case .draft:
            throw TypedEditContractFailure.unacceptedOperationState
        case .queued(_, let lastTransientError):
            return lastTransientError == nil ? .queued : .retrying
        case .applying:
            return .applying
        case .applied:
            return .applied
        case .rejected(let rejection):
            return rejectionPhase(for: rejection.error.category)
        case .superseded:
            return .superseded
        case .resolved:
            return .resolved
        }
    }

    private static func phase(for state: LocalOperationState) -> EditSubmissionPhase {
        switch state {
        case .queued:
            .locallyAccepted
        case .applying:
            .applying
        case .applied:
            .applied
        case .rejected:
            .rejected
        case .superseded:
            .superseded
        case .resolved:
            .resolved
        }
    }

    private static func rejectionPhase(
        for category: ApplicationErrorCategory
    ) -> EditSubmissionPhase {
        switch category {
        case .validation:
            .rejected
        case .conflict:
            .conflicted
        case .authorization, .invariant:
            .unavailable
        case .authentication:
            .reauthenticate
        case .unsupportedContract, .requiredUpdate:
            .requiredUpdate
        case .transientInfrastructure:
            .retrying
        }
    }

    private static func validateTransition(
        from current: EditSubmissionPhase?,
        to next: EditSubmissionPhase
    ) throws {
        guard let current, current != next else { return }
        let isAllowed: Bool
        switch current {
        case .locallyAccepted:
            isAllowed = true
        case .queued:
            isAllowed = [
                .applying,
                .applied,
                .rejected,
                .conflicted,
                .retrying,
                .unavailable,
                .reauthenticate,
                .requiredUpdate
            ].contains(next)
        case .applying:
            isAllowed = [
                .applied,
                .rejected,
                .conflicted,
                .retrying,
                .unavailable,
                .reauthenticate,
                .requiredUpdate
            ].contains(next)
        case .retrying:
            isAllowed = [
                .queued,
                .applying,
                .applied,
                .rejected,
                .conflicted,
                .unavailable,
                .reauthenticate,
                .requiredUpdate,
                .resolved
            ].contains(next)
        case .applied:
            isAllowed = next == .superseded
        case .rejected, .conflicted, .unavailable, .reauthenticate, .requiredUpdate:
            isAllowed = next == .resolved
        case .superseded, .resolved:
            isAllowed = false
        }
        guard isAllowed else {
            throw TypedEditContractFailure.illegalOperationPresentationTransition(
                from: current,
                to: next
            )
        }
    }
}
