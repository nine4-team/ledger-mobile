import CryptoKit
import Foundation

public enum ProjectPreferenceUpdateFailure: Error, Equatable, Sendable {
    case invalidCapturedAt
    case duplicatePinnedCategoryIdentity
    case draftAccountMismatch
    case draftActorMismatch
    case draftContractMismatch
    case draftPayloadMismatch
    case expectedStatePreconditionMismatch
    case subjectMismatch
    case fingerprintMismatch
    case receiptMismatch
    case localAcceptanceFailed
    case invalidEncodedDraft
    case invalidEncodedCommand

    public var diagnosticCode: String {
        switch self {
        case .invalidCapturedAt:
            "project_preference_update_captured_at_invalid"
        case .duplicatePinnedCategoryIdentity:
            "project_preference_update_pinned_category_duplicate"
        case .draftAccountMismatch:
            "project_preference_update_account_mismatch"
        case .draftActorMismatch:
            "project_preference_update_actor_mismatch"
        case .draftContractMismatch:
            "project_preference_update_contract_mismatch"
        case .draftPayloadMismatch:
            "project_preference_update_payload_mismatch"
        case .expectedStatePreconditionMismatch:
            "project_preference_update_precondition_mismatch"
        case .subjectMismatch:
            "project_preference_update_subject_mismatch"
        case .fingerprintMismatch:
            "project_preference_update_fingerprint_mismatch"
        case .receiptMismatch:
            "project_preference_update_receipt_mismatch"
        case .localAcceptanceFailed:
            "project_preference_update_local_acceptance_failed"
        case .invalidEncodedDraft:
            "project_preference_update_draft_encoding_invalid"
        case .invalidEncodedCommand:
            "project_preference_update_command_encoding_invalid"
        }
    }
}

public enum ProjectPreferenceExpectedState: Codable, Equatable, Sendable {
    case notStored
    case revision(UInt64)

    fileprivate func operationPrecondition(
        subject: LedgerEntityReference
    ) throws -> OperationPrecondition {
        switch self {
        case .notStored:
            return .expectedState(
                subject: subject,
                state: try EntityStateCode(validating: "not_stored")
            )
        case let .revision(revision):
            return .expectedRevision(subject: subject, revision: revision)
        }
    }
}

public struct ProjectPreferenceUpdateDraft: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let actorPrincipalId: PrincipalID
    public let operationContractVersion: OperationContractVersion
    public let projectId: ProjectID
    public let pinnedCategoryIds: [BudgetCategoryID]
    public let expectedState: ProjectPreferenceExpectedState
    public let capturedAt: Date

    public init(
        accountId: AccountID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        projectId: ProjectID,
        pinnedCategoryIds: [BudgetCategoryID],
        expectedState: ProjectPreferenceExpectedState,
        capturedAt: Date
    ) throws {
        guard capturedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw ProjectPreferenceUpdateFailure.invalidCapturedAt
        }
        guard Set(pinnedCategoryIds).count == pinnedCategoryIds.count else {
            throw ProjectPreferenceUpdateFailure.duplicatePinnedCategoryIdentity
        }
        self.accountId = accountId
        self.actorPrincipalId = actorPrincipalId
        self.operationContractVersion = operationContractVersion
        self.projectId = projectId
        self.pinnedCategoryIds = pinnedCategoryIds
        self.expectedState = expectedState
        self.capturedAt = capturedAt
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                accountId: container.decode(AccountID.self, forKey: .accountId),
                actorPrincipalId: container.decode(
                    PrincipalID.self,
                    forKey: .actorPrincipalId
                ),
                operationContractVersion: container.decode(
                    OperationContractVersion.self,
                    forKey: .operationContractVersion
                ),
                projectId: container.decode(ProjectID.self, forKey: .projectId),
                pinnedCategoryIds: container.decode(
                    [BudgetCategoryID].self,
                    forKey: .pinnedCategoryIds
                ),
                expectedState: container.decode(
                    ProjectPreferenceExpectedState.self,
                    forKey: .expectedState
                ),
                capturedAt: container.decode(Date.self, forKey: .capturedAt)
            )
        } catch let failure as ProjectPreferenceUpdateFailure {
            throw failure
        } catch {
            throw ProjectPreferenceUpdateFailure.invalidEncodedDraft
        }
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case actorPrincipalId
        case operationContractVersion
        case projectId
        case pinnedCategoryIds
        case expectedState
        case capturedAt
    }
}

public struct UpdateProjectPreferencesPayload: Codable, Equatable, Sendable {
    public let projectId: ProjectID
    public let pinnedCategoryIds: [BudgetCategoryID]

    public init(projectId: ProjectID, pinnedCategoryIds: [BudgetCategoryID]) {
        self.projectId = projectId
        self.pinnedCategoryIds = pinnedCategoryIds
    }
}

public struct UpdateProjectPreferencesCommand: Codable, Equatable, Sendable {
    public let draft: ProjectPreferenceUpdateDraft
    public let envelope: OperationEnvelope<UpdateProjectPreferencesPayload>
    public let subject: LedgerEntityReference
    public let fingerprint: OperationFingerprint

    public init(operationId: OperationID, draft: ProjectPreferenceUpdateDraft) throws {
        let payload = UpdateProjectPreferencesPayload(
            projectId: draft.projectId,
            pinnedCategoryIds: draft.pinnedCategoryIds
        )
        let subject = try Self.makeSubject(
            accountId: draft.accountId,
            principalId: draft.actorPrincipalId,
            projectId: draft.projectId
        )
        let envelope = OperationEnvelope(
            operationId: operationId,
            contractVersion: draft.operationContractVersion,
            accountId: draft.accountId,
            actorPrincipalId: draft.actorPrincipalId,
            clientCreatedAt: draft.capturedAt,
            payload: payload,
            preconditions: [
                try draft.expectedState.operationPrecondition(subject: subject)
            ]
        )
        let fingerprint = try OperationFingerprint.make(for: envelope)
        try self.init(
            draft: draft,
            envelope: envelope,
            subject: subject,
            fingerprint: fingerprint
        )
    }

    private init(
        draft: ProjectPreferenceUpdateDraft,
        envelope: OperationEnvelope<UpdateProjectPreferencesPayload>,
        subject: LedgerEntityReference,
        fingerprint: OperationFingerprint
    ) throws {
        guard envelope.clientCreatedAt.timeIntervalSinceReferenceDate.isFinite,
              envelope.clientCreatedAt == draft.capturedAt else {
            throw ProjectPreferenceUpdateFailure.invalidCapturedAt
        }
        guard envelope.accountId == draft.accountId else {
            throw ProjectPreferenceUpdateFailure.draftAccountMismatch
        }
        guard envelope.actorPrincipalId == draft.actorPrincipalId else {
            throw ProjectPreferenceUpdateFailure.draftActorMismatch
        }
        guard envelope.contractVersion == draft.operationContractVersion else {
            throw ProjectPreferenceUpdateFailure.draftContractMismatch
        }

        let expectedPayload = UpdateProjectPreferencesPayload(
            projectId: draft.projectId,
            pinnedCategoryIds: draft.pinnedCategoryIds
        )
        guard envelope.payload == expectedPayload else {
            throw ProjectPreferenceUpdateFailure.draftPayloadMismatch
        }

        let expectedSubject = try Self.makeSubject(
            accountId: draft.accountId,
            principalId: draft.actorPrincipalId,
            projectId: draft.projectId
        )
        let expectedPreconditions = [
            try draft.expectedState.operationPrecondition(subject: expectedSubject)
        ]
        guard envelope.preconditions == expectedPreconditions else {
            throw ProjectPreferenceUpdateFailure.expectedStatePreconditionMismatch
        }
        guard subject == expectedSubject else {
            throw ProjectPreferenceUpdateFailure.subjectMismatch
        }
        guard fingerprint == (try OperationFingerprint.make(for: envelope)) else {
            throw ProjectPreferenceUpdateFailure.fingerprintMismatch
        }

        self.draft = draft
        self.envelope = envelope
        self.subject = subject
        self.fingerprint = fingerprint
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                draft: container.decode(ProjectPreferenceUpdateDraft.self, forKey: .draft),
                envelope: container.decode(
                    OperationEnvelope<UpdateProjectPreferencesPayload>.self,
                    forKey: .envelope
                ),
                subject: container.decode(LedgerEntityReference.self, forKey: .subject),
                fingerprint: container.decode(OperationFingerprint.self, forKey: .fingerprint)
            )
        } catch let failure as ProjectPreferenceUpdateFailure {
            throw failure
        } catch {
            throw ProjectPreferenceUpdateFailure.invalidEncodedCommand
        }
    }

    public func validate(_ receipt: OperationReceipt) throws -> OperationReceipt {
        guard receipt.operationId == envelope.operationId else {
            throw ProjectPreferenceUpdateFailure.receiptMismatch
        }
        return receipt
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.draft == rhs.draft &&
            lhs.envelope.operationId == rhs.envelope.operationId &&
            lhs.envelope.contractVersion == rhs.envelope.contractVersion &&
            lhs.envelope.accountId == rhs.envelope.accountId &&
            lhs.envelope.actorPrincipalId == rhs.envelope.actorPrincipalId &&
            lhs.envelope.clientCreatedAt == rhs.envelope.clientCreatedAt &&
            lhs.envelope.payload == rhs.envelope.payload &&
            lhs.envelope.preconditions == rhs.envelope.preconditions &&
            lhs.subject == rhs.subject &&
            lhs.fingerprint == rhs.fingerprint
    }

    private static func makeSubject(
        accountId: AccountID,
        principalId: PrincipalID,
        projectId: ProjectID
    ) throws -> LedgerEntityReference {
        do {
            let basis = SubjectBasis(
                accountId: accountId,
                principalId: principalId,
                projectId: projectId
            )
            let bytes = try OperationContractCodec.encode(basis)
            let digest = SHA256.hash(data: bytes)
                .map { String(format: "%02x", $0) }
                .joined()
            return LedgerEntityReference(
                kind: .referenceData,
                id: try EntityID(validating: "project_preference:\(digest)")
            )
        } catch {
            throw ProjectPreferenceUpdateFailure.subjectMismatch
        }
    }

    private struct SubjectBasis: Codable {
        let accountId: AccountID
        let principalId: PrincipalID
        let projectId: ProjectID
    }

    private enum CodingKeys: String, CodingKey {
        case draft
        case envelope
        case subject
        case fingerprint
    }
}

public protocol ProjectPreferenceUpdating: Sendable {
    func updateProjectPreferences(
        _ command: UpdateProjectPreferencesCommand
    ) async throws -> OperationReceipt
}
