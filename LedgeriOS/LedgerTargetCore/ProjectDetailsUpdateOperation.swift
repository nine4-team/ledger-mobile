import Foundation

public enum ProjectDetailsUpdateFailure: Error, Equatable, Sendable {
    case invalidCapturedAt
    case draftAccountMismatch
    case draftActorMismatch
    case draftContractMismatch
    case draftPayloadMismatch
    case revisionPreconditionMismatch
    case subjectMismatch
    case fingerprintMismatch
    case receiptMismatch
    case localAcceptanceFailed
    case invalidEncodedDescriptionReplacement
    case invalidEncodedDraft
    case invalidEncodedCommand

    public var diagnosticCode: String {
        switch self {
        case .invalidCapturedAt:
            "project_details_update_captured_at_invalid"
        case .draftAccountMismatch:
            "project_details_update_account_mismatch"
        case .draftActorMismatch:
            "project_details_update_actor_mismatch"
        case .draftContractMismatch:
            "project_details_update_contract_mismatch"
        case .draftPayloadMismatch:
            "project_details_update_payload_mismatch"
        case .revisionPreconditionMismatch:
            "project_details_update_revision_precondition_mismatch"
        case .subjectMismatch:
            "project_details_update_subject_mismatch"
        case .fingerprintMismatch:
            "project_details_update_fingerprint_mismatch"
        case .receiptMismatch:
            "project_details_update_receipt_mismatch"
        case .localAcceptanceFailed:
            "project_details_update_local_acceptance_failed"
        case .invalidEncodedDescriptionReplacement:
            "project_details_update_description_replacement_encoding_invalid"
        case .invalidEncodedDraft:
            "project_details_update_draft_encoding_invalid"
        case .invalidEncodedCommand:
            "project_details_update_command_encoding_invalid"
        }
    }
}

public struct ProjectDescriptionReplacement: Codable, Equatable, Sendable {
    public let value: String?

    public init(_ rawValue: String?) {
        let normalized = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        value = normalized?.isEmpty == false ? normalized : nil
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard container.contains(.value) else {
                throw ProjectDetailsUpdateFailure.invalidEncodedDescriptionReplacement
            }
            let rawValue = try container.decodeIfPresent(String.self, forKey: .value)
            let canonical = Self(rawValue)
            guard rawValue == canonical.value else {
                throw ProjectDetailsUpdateFailure.invalidEncodedDescriptionReplacement
            }
            self = canonical
        } catch let failure as ProjectDetailsUpdateFailure {
            throw failure
        } catch {
            throw ProjectDetailsUpdateFailure.invalidEncodedDescriptionReplacement
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let value {
            try container.encode(value, forKey: .value)
        } else {
            try container.encodeNil(forKey: .value)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case value
    }
}

public struct ProjectDetailsUpdateDraft: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let actorPrincipalId: PrincipalID
    public let operationContractVersion: OperationContractVersion
    public let projectId: ProjectID
    public let descriptionReplacement: ProjectDescriptionReplacement
    public let expectedRevision: ExpectedProjectRevision
    public let capturedAt: Date

    public init(
        accountId: AccountID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        projectId: ProjectID,
        descriptionReplacement: ProjectDescriptionReplacement,
        expectedRevision: ExpectedProjectRevision,
        capturedAt: Date
    ) throws {
        guard capturedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw ProjectDetailsUpdateFailure.invalidCapturedAt
        }
        self.accountId = accountId
        self.actorPrincipalId = actorPrincipalId
        self.operationContractVersion = operationContractVersion
        self.projectId = projectId
        self.descriptionReplacement = descriptionReplacement
        self.expectedRevision = expectedRevision
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
                descriptionReplacement: container.decode(
                    ProjectDescriptionReplacement.self,
                    forKey: .descriptionReplacement
                ),
                expectedRevision: container.decode(
                    ExpectedProjectRevision.self,
                    forKey: .expectedRevision
                ),
                capturedAt: container.decode(Date.self, forKey: .capturedAt)
            )
        } catch let failure as ProjectDetailsUpdateFailure {
            throw failure
        } catch {
            throw ProjectDetailsUpdateFailure.invalidEncodedDraft
        }
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case actorPrincipalId
        case operationContractVersion
        case projectId
        case descriptionReplacement
        case expectedRevision
        case capturedAt
    }
}

public struct UpdateProjectDetailsPayload: Codable, Equatable, Sendable {
    public let projectId: ProjectID
    public let descriptionReplacement: ProjectDescriptionReplacement

    public init(
        projectId: ProjectID,
        descriptionReplacement: ProjectDescriptionReplacement
    ) {
        self.projectId = projectId
        self.descriptionReplacement = descriptionReplacement
    }
}

public struct UpdateProjectDetailsCommand: Codable, Equatable, Sendable {
    public let draft: ProjectDetailsUpdateDraft
    public let envelope: OperationEnvelope<UpdateProjectDetailsPayload>
    public let subject: LedgerEntityReference
    public let fingerprint: OperationFingerprint

    public init(operationId: OperationID, draft: ProjectDetailsUpdateDraft) throws {
        let payload = UpdateProjectDetailsPayload(
            projectId: draft.projectId,
            descriptionReplacement: draft.descriptionReplacement
        )
        let subject = try Self.makeSubject(projectId: draft.projectId)
        let envelope = OperationEnvelope(
            operationId: operationId,
            contractVersion: draft.operationContractVersion,
            accountId: draft.accountId,
            actorPrincipalId: draft.actorPrincipalId,
            clientCreatedAt: draft.capturedAt,
            payload: payload,
            preconditions: [
                .expectedRevision(
                    subject: subject,
                    revision: draft.expectedRevision.rawValue
                )
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
        draft: ProjectDetailsUpdateDraft,
        envelope: OperationEnvelope<UpdateProjectDetailsPayload>,
        subject: LedgerEntityReference,
        fingerprint: OperationFingerprint
    ) throws {
        guard envelope.clientCreatedAt.timeIntervalSinceReferenceDate.isFinite,
              envelope.clientCreatedAt == draft.capturedAt else {
            throw ProjectDetailsUpdateFailure.invalidCapturedAt
        }
        guard envelope.accountId == draft.accountId else {
            throw ProjectDetailsUpdateFailure.draftAccountMismatch
        }
        guard envelope.actorPrincipalId == draft.actorPrincipalId else {
            throw ProjectDetailsUpdateFailure.draftActorMismatch
        }
        guard envelope.contractVersion == draft.operationContractVersion else {
            throw ProjectDetailsUpdateFailure.draftContractMismatch
        }
        let expectedPayload = UpdateProjectDetailsPayload(
            projectId: draft.projectId,
            descriptionReplacement: draft.descriptionReplacement
        )
        guard envelope.payload == expectedPayload else {
            throw ProjectDetailsUpdateFailure.draftPayloadMismatch
        }

        let expectedSubject = try Self.makeSubject(projectId: draft.projectId)
        let expectedPreconditions: [OperationPrecondition] = [
            .expectedRevision(
                subject: expectedSubject,
                revision: draft.expectedRevision.rawValue
            )
        ]
        guard envelope.preconditions == expectedPreconditions else {
            throw ProjectDetailsUpdateFailure.revisionPreconditionMismatch
        }
        guard subject == expectedSubject else {
            throw ProjectDetailsUpdateFailure.subjectMismatch
        }
        guard fingerprint == (try OperationFingerprint.make(for: envelope)) else {
            throw ProjectDetailsUpdateFailure.fingerprintMismatch
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
                draft: container.decode(ProjectDetailsUpdateDraft.self, forKey: .draft),
                envelope: container.decode(
                    OperationEnvelope<UpdateProjectDetailsPayload>.self,
                    forKey: .envelope
                ),
                subject: container.decode(LedgerEntityReference.self, forKey: .subject),
                fingerprint: container.decode(OperationFingerprint.self, forKey: .fingerprint)
            )
        } catch let failure as ProjectDetailsUpdateFailure {
            throw failure
        } catch {
            throw ProjectDetailsUpdateFailure.invalidEncodedCommand
        }
    }

    public func validate(_ receipt: OperationReceipt) throws -> OperationReceipt {
        guard receipt.operationId == envelope.operationId else {
            throw ProjectDetailsUpdateFailure.receiptMismatch
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

    private static func makeSubject(projectId: ProjectID) throws -> LedgerEntityReference {
        do {
            return LedgerEntityReference(
                kind: .project,
                id: try EntityID(validating: projectId.rawValue)
            )
        } catch {
            throw ProjectDetailsUpdateFailure.subjectMismatch
        }
    }

    private enum CodingKeys: String, CodingKey {
        case draft
        case envelope
        case subject
        case fingerprint
    }
}

public protocol ProjectDetailsUpdating: Sendable {
    func updateDetails(_ command: UpdateProjectDetailsCommand) async throws -> OperationReceipt
}
