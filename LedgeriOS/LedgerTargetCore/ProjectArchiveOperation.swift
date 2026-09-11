import Foundation

public enum ProjectArchiveFailure: Error, Equatable, Sendable {
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
            "project_archive_captured_at_invalid"
        case .draftAccountMismatch:
            "project_archive_account_mismatch"
        case .draftActorMismatch:
            "project_archive_actor_mismatch"
        case .draftContractMismatch:
            "project_archive_contract_mismatch"
        case .draftPayloadMismatch:
            "project_archive_payload_mismatch"
        case .revisionPreconditionMismatch:
            "project_archive_revision_precondition_mismatch"
        case .subjectMismatch:
            "project_archive_subject_mismatch"
        case .fingerprintMismatch:
            "project_archive_fingerprint_mismatch"
        case .receiptMismatch:
            "project_archive_receipt_mismatch"
        case .localAcceptanceFailed:
            "project_archive_local_acceptance_failed"
        case .invalidEncodedDraft:
            "project_archive_draft_encoding_invalid"
        case .invalidEncodedCommand:
            "project_archive_command_encoding_invalid"
        }
    }
}

public struct ExpectedProjectRevision: Codable, Equatable, Hashable, Sendable {
    public let rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

public struct ProjectArchiveDraft: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let actorPrincipalId: PrincipalID
    public let operationContractVersion: OperationContractVersion
    public let projectId: ProjectID
    public let expectedRevision: ExpectedProjectRevision
    public let capturedAt: Date

    public init(
        accountId: AccountID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        projectId: ProjectID,
        expectedRevision: ExpectedProjectRevision,
        capturedAt: Date
    ) throws {
        guard capturedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw ProjectArchiveFailure.invalidCapturedAt
        }
        self.accountId = accountId
        self.actorPrincipalId = actorPrincipalId
        self.operationContractVersion = operationContractVersion
        self.projectId = projectId
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
                expectedRevision: container.decode(
                    ExpectedProjectRevision.self,
                    forKey: .expectedRevision
                ),
                capturedAt: container.decode(Date.self, forKey: .capturedAt)
            )
        } catch let failure as ProjectArchiveFailure {
            throw failure
        } catch {
            throw ProjectArchiveFailure.invalidEncodedDraft
        }
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case actorPrincipalId
        case operationContractVersion
        case projectId
        case expectedRevision
        case capturedAt
    }
}

public struct ArchiveProjectPayload: Codable, Equatable, Sendable {
    public let projectId: ProjectID

    public init(projectId: ProjectID) {
        self.projectId = projectId
    }
}

public struct ArchiveProjectCommand: Codable, Equatable, Sendable {
    public let draft: ProjectArchiveDraft
    public let envelope: OperationEnvelope<ArchiveProjectPayload>
    public let subject: LedgerEntityReference
    public let fingerprint: OperationFingerprint

    public init(operationId: OperationID, draft: ProjectArchiveDraft) throws {
        let payload = ArchiveProjectPayload(projectId: draft.projectId)
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
        draft: ProjectArchiveDraft,
        envelope: OperationEnvelope<ArchiveProjectPayload>,
        subject: LedgerEntityReference,
        fingerprint: OperationFingerprint
    ) throws {
        guard envelope.clientCreatedAt.timeIntervalSinceReferenceDate.isFinite,
              envelope.clientCreatedAt == draft.capturedAt else {
            throw ProjectArchiveFailure.invalidCapturedAt
        }
        guard envelope.accountId == draft.accountId else {
            throw ProjectArchiveFailure.draftAccountMismatch
        }
        guard envelope.actorPrincipalId == draft.actorPrincipalId else {
            throw ProjectArchiveFailure.draftActorMismatch
        }
        guard envelope.contractVersion == draft.operationContractVersion else {
            throw ProjectArchiveFailure.draftContractMismatch
        }
        guard envelope.payload == ArchiveProjectPayload(projectId: draft.projectId) else {
            throw ProjectArchiveFailure.draftPayloadMismatch
        }

        let expectedSubject = try Self.makeSubject(projectId: draft.projectId)
        let expectedPreconditions: [OperationPrecondition] = [
            .expectedRevision(
                subject: expectedSubject,
                revision: draft.expectedRevision.rawValue
            )
        ]
        guard envelope.preconditions == expectedPreconditions else {
            throw ProjectArchiveFailure.revisionPreconditionMismatch
        }
        guard subject == expectedSubject else {
            throw ProjectArchiveFailure.subjectMismatch
        }
        guard fingerprint == (try OperationFingerprint.make(for: envelope)) else {
            throw ProjectArchiveFailure.fingerprintMismatch
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
                draft: container.decode(ProjectArchiveDraft.self, forKey: .draft),
                envelope: container.decode(
                    OperationEnvelope<ArchiveProjectPayload>.self,
                    forKey: .envelope
                ),
                subject: container.decode(LedgerEntityReference.self, forKey: .subject),
                fingerprint: container.decode(OperationFingerprint.self, forKey: .fingerprint)
            )
        } catch let failure as ProjectArchiveFailure {
            throw failure
        } catch {
            throw ProjectArchiveFailure.invalidEncodedCommand
        }
    }

    public func validate(_ receipt: OperationReceipt) throws -> OperationReceipt {
        guard receipt.operationId == envelope.operationId else {
            throw ProjectArchiveFailure.receiptMismatch
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
            throw ProjectArchiveFailure.subjectMismatch
        }
    }

    private enum CodingKeys: String, CodingKey {
        case draft
        case envelope
        case subject
        case fingerprint
    }
}

public protocol ProjectArchiving: Sendable {
    func archive(_ command: ArchiveProjectCommand) async throws -> OperationReceipt
}
