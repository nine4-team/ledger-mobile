import Foundation

public enum ProjectRenameFailure: Error, Equatable, Sendable {
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
    case invalidEncodedDraft
    case invalidEncodedCommand

    public var diagnosticCode: String {
        switch self {
        case .invalidCapturedAt:
            "project_rename_captured_at_invalid"
        case .draftAccountMismatch:
            "project_rename_account_mismatch"
        case .draftActorMismatch:
            "project_rename_actor_mismatch"
        case .draftContractMismatch:
            "project_rename_contract_mismatch"
        case .draftPayloadMismatch:
            "project_rename_payload_mismatch"
        case .revisionPreconditionMismatch:
            "project_rename_revision_precondition_mismatch"
        case .subjectMismatch:
            "project_rename_subject_mismatch"
        case .fingerprintMismatch:
            "project_rename_fingerprint_mismatch"
        case .receiptMismatch:
            "project_rename_receipt_mismatch"
        case .localAcceptanceFailed:
            "project_rename_local_acceptance_failed"
        case .invalidEncodedDraft:
            "project_rename_draft_encoding_invalid"
        case .invalidEncodedCommand:
            "project_rename_command_encoding_invalid"
        }
    }
}

public struct ProjectRenameDraft: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let actorPrincipalId: PrincipalID
    public let operationContractVersion: OperationContractVersion
    public let projectId: ProjectID
    public let newDisplayName: ProjectDisplayName
    public let expectedRevision: ExpectedProjectRevision
    public let capturedAt: Date

    public init(
        accountId: AccountID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        projectId: ProjectID,
        newDisplayName: ProjectDisplayName,
        expectedRevision: ExpectedProjectRevision,
        capturedAt: Date
    ) throws {
        guard capturedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw ProjectRenameFailure.invalidCapturedAt
        }
        self.accountId = accountId
        self.actorPrincipalId = actorPrincipalId
        self.operationContractVersion = operationContractVersion
        self.projectId = projectId
        self.newDisplayName = newDisplayName
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
                newDisplayName: container.decode(
                    ProjectDisplayName.self,
                    forKey: .newDisplayName
                ),
                expectedRevision: container.decode(
                    ExpectedProjectRevision.self,
                    forKey: .expectedRevision
                ),
                capturedAt: container.decode(Date.self, forKey: .capturedAt)
            )
        } catch let failure as ProjectRenameFailure {
            throw failure
        } catch {
            throw ProjectRenameFailure.invalidEncodedDraft
        }
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case actorPrincipalId
        case operationContractVersion
        case projectId
        case newDisplayName
        case expectedRevision
        case capturedAt
    }
}

public struct RenameProjectPayload: Codable, Equatable, Sendable {
    public let projectId: ProjectID
    public let displayName: ProjectDisplayName

    public init(projectId: ProjectID, displayName: ProjectDisplayName) {
        self.projectId = projectId
        self.displayName = displayName
    }
}

public struct RenameProjectCommand: Codable, Equatable, Sendable {
    public let draft: ProjectRenameDraft
    public let envelope: OperationEnvelope<RenameProjectPayload>
    public let subject: LedgerEntityReference
    public let fingerprint: OperationFingerprint

    public init(operationId: OperationID, draft: ProjectRenameDraft) throws {
        let payload = RenameProjectPayload(
            projectId: draft.projectId,
            displayName: draft.newDisplayName
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
        draft: ProjectRenameDraft,
        envelope: OperationEnvelope<RenameProjectPayload>,
        subject: LedgerEntityReference,
        fingerprint: OperationFingerprint
    ) throws {
        guard envelope.clientCreatedAt.timeIntervalSinceReferenceDate.isFinite,
              envelope.clientCreatedAt == draft.capturedAt else {
            throw ProjectRenameFailure.invalidCapturedAt
        }
        guard envelope.accountId == draft.accountId else {
            throw ProjectRenameFailure.draftAccountMismatch
        }
        guard envelope.actorPrincipalId == draft.actorPrincipalId else {
            throw ProjectRenameFailure.draftActorMismatch
        }
        guard envelope.contractVersion == draft.operationContractVersion else {
            throw ProjectRenameFailure.draftContractMismatch
        }
        let expectedPayload = RenameProjectPayload(
            projectId: draft.projectId,
            displayName: draft.newDisplayName
        )
        guard envelope.payload == expectedPayload else {
            throw ProjectRenameFailure.draftPayloadMismatch
        }

        let expectedSubject = try Self.makeSubject(projectId: draft.projectId)
        let expectedPreconditions: [OperationPrecondition] = [
            .expectedRevision(
                subject: expectedSubject,
                revision: draft.expectedRevision.rawValue
            )
        ]
        guard envelope.preconditions == expectedPreconditions else {
            throw ProjectRenameFailure.revisionPreconditionMismatch
        }
        guard subject == expectedSubject else {
            throw ProjectRenameFailure.subjectMismatch
        }
        guard fingerprint == (try OperationFingerprint.make(for: envelope)) else {
            throw ProjectRenameFailure.fingerprintMismatch
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
                draft: container.decode(ProjectRenameDraft.self, forKey: .draft),
                envelope: container.decode(
                    OperationEnvelope<RenameProjectPayload>.self,
                    forKey: .envelope
                ),
                subject: container.decode(LedgerEntityReference.self, forKey: .subject),
                fingerprint: container.decode(OperationFingerprint.self, forKey: .fingerprint)
            )
        } catch let failure as ProjectRenameFailure {
            throw failure
        } catch {
            throw ProjectRenameFailure.invalidEncodedCommand
        }
    }

    public func validate(_ receipt: OperationReceipt) throws -> OperationReceipt {
        guard receipt.operationId == envelope.operationId else {
            throw ProjectRenameFailure.receiptMismatch
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
            throw ProjectRenameFailure.subjectMismatch
        }
    }

    private enum CodingKeys: String, CodingKey {
        case draft
        case envelope
        case subject
        case fingerprint
    }
}

public protocol ProjectRenaming: Sendable {
    func rename(_ command: RenameProjectCommand) async throws -> OperationReceipt
}
