import Foundation

public enum ProjectNoteCreationFailure: Error, Equatable, Sendable {
    case invalidClientCreatedAt
    case draftAccountMismatch
    case draftActorMismatch
    case draftContractMismatch
    case draftPayloadMismatch
    case unexpectedPreconditions
    case parentProjectMismatch
    case fingerprintMismatch
    case receiptMismatch
    case localAcceptanceFailed
    case invalidEncodedCommand

    public var diagnosticCode: String {
        switch self {
        case .invalidClientCreatedAt:
            "project_note_creation_client_time_invalid"
        case .draftAccountMismatch:
            "project_note_creation_account_mismatch"
        case .draftActorMismatch:
            "project_note_creation_actor_mismatch"
        case .draftContractMismatch:
            "project_note_creation_contract_mismatch"
        case .draftPayloadMismatch:
            "project_note_creation_payload_mismatch"
        case .unexpectedPreconditions:
            "project_note_creation_preconditions_unexpected"
        case .parentProjectMismatch:
            "project_note_creation_parent_project_mismatch"
        case .fingerprintMismatch:
            "project_note_creation_fingerprint_mismatch"
        case .receiptMismatch:
            "project_note_creation_receipt_mismatch"
        case .localAcceptanceFailed:
            "project_note_creation_local_acceptance_failed"
        case .invalidEncodedCommand:
            "project_note_creation_command_encoding_invalid"
        }
    }
}

public struct ProjectNoteCreationDraft: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let actorPrincipalId: PrincipalID
    public let operationContractVersion: OperationContractVersion
    public let projectId: ProjectID
    public let noteId: ProjectNoteID
    public let text: ProjectNoteText
    public let requestedSource: ProjectNoteSource
    public let capturedAt: Date

    public init(
        accountId: AccountID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        projectId: ProjectID,
        noteId: ProjectNoteID,
        text: ProjectNoteText,
        requestedSource: ProjectNoteSource,
        capturedAt: Date
    ) throws {
        guard capturedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw ProjectNoteCreationFailure.invalidClientCreatedAt
        }
        self.accountId = accountId
        self.actorPrincipalId = actorPrincipalId
        self.operationContractVersion = operationContractVersion
        self.projectId = projectId
        self.noteId = noteId
        self.text = text
        self.requestedSource = requestedSource
        self.capturedAt = capturedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            accountId: container.decode(AccountID.self, forKey: .accountId),
            actorPrincipalId: container.decode(PrincipalID.self, forKey: .actorPrincipalId),
            operationContractVersion: container.decode(
                OperationContractVersion.self,
                forKey: .operationContractVersion
            ),
            projectId: container.decode(ProjectID.self, forKey: .projectId),
            noteId: container.decode(ProjectNoteID.self, forKey: .noteId),
            text: container.decode(ProjectNoteText.self, forKey: .text),
            requestedSource: container.decode(ProjectNoteSource.self, forKey: .requestedSource),
            capturedAt: container.decode(Date.self, forKey: .capturedAt)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case actorPrincipalId
        case operationContractVersion
        case projectId
        case noteId
        case text
        case requestedSource
        case capturedAt
    }
}

public struct AddProjectNotePayload: Codable, Equatable, Sendable {
    public let projectId: ProjectID
    public let noteId: ProjectNoteID
    public let text: ProjectNoteText
    public let requestedSource: ProjectNoteSource

    public init(
        projectId: ProjectID,
        noteId: ProjectNoteID,
        text: ProjectNoteText,
        requestedSource: ProjectNoteSource
    ) {
        self.projectId = projectId
        self.noteId = noteId
        self.text = text
        self.requestedSource = requestedSource
    }
}

public struct AddProjectNoteCommand: Codable, Equatable, Sendable {
    public let draft: ProjectNoteCreationDraft
    public let envelope: OperationEnvelope<AddProjectNotePayload>
    public let parentProject: LedgerEntityReference
    public let fingerprint: OperationFingerprint

    public init(operationId: OperationID, draft: ProjectNoteCreationDraft) throws {
        let payload = Self.makePayload(from: draft)
        let envelope = OperationEnvelope(
            operationId: operationId,
            contractVersion: draft.operationContractVersion,
            accountId: draft.accountId,
            actorPrincipalId: draft.actorPrincipalId,
            clientCreatedAt: draft.capturedAt,
            payload: payload
        )
        let parentProject = try Self.makeParentProject(projectId: draft.projectId)
        let fingerprint = try OperationFingerprint.make(for: envelope)
        try self.init(
            draft: draft,
            envelope: envelope,
            parentProject: parentProject,
            fingerprint: fingerprint
        )
    }

    private init(
        draft: ProjectNoteCreationDraft,
        envelope: OperationEnvelope<AddProjectNotePayload>,
        parentProject: LedgerEntityReference,
        fingerprint: OperationFingerprint
    ) throws {
        guard envelope.clientCreatedAt.timeIntervalSinceReferenceDate.isFinite,
              envelope.clientCreatedAt == draft.capturedAt else {
            throw ProjectNoteCreationFailure.invalidClientCreatedAt
        }
        guard envelope.accountId == draft.accountId else {
            throw ProjectNoteCreationFailure.draftAccountMismatch
        }
        guard envelope.actorPrincipalId == draft.actorPrincipalId else {
            throw ProjectNoteCreationFailure.draftActorMismatch
        }
        guard envelope.contractVersion == draft.operationContractVersion else {
            throw ProjectNoteCreationFailure.draftContractMismatch
        }
        guard envelope.payload == Self.makePayload(from: draft) else {
            throw ProjectNoteCreationFailure.draftPayloadMismatch
        }
        guard envelope.preconditions.isEmpty else {
            throw ProjectNoteCreationFailure.unexpectedPreconditions
        }
        guard parentProject == (try Self.makeParentProject(projectId: draft.projectId)) else {
            throw ProjectNoteCreationFailure.parentProjectMismatch
        }
        guard fingerprint == (try OperationFingerprint.make(for: envelope)) else {
            throw ProjectNoteCreationFailure.fingerprintMismatch
        }

        self.draft = draft
        self.envelope = envelope
        self.parentProject = parentProject
        self.fingerprint = fingerprint
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                draft: container.decode(ProjectNoteCreationDraft.self, forKey: .draft),
                envelope: container.decode(
                    OperationEnvelope<AddProjectNotePayload>.self,
                    forKey: .envelope
                ),
                parentProject: container.decode(
                    LedgerEntityReference.self,
                    forKey: .parentProject
                ),
                fingerprint: container.decode(OperationFingerprint.self, forKey: .fingerprint)
            )
        } catch let failure as ProjectNoteCreationFailure {
            throw failure
        } catch {
            throw ProjectNoteCreationFailure.invalidEncodedCommand
        }
    }

    public func validate(_ receipt: OperationReceipt) throws -> OperationReceipt {
        guard receipt.operationId == envelope.operationId else {
            throw ProjectNoteCreationFailure.receiptMismatch
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
            lhs.parentProject == rhs.parentProject &&
            lhs.fingerprint == rhs.fingerprint
    }

    private static func makePayload(
        from draft: ProjectNoteCreationDraft
    ) -> AddProjectNotePayload {
        AddProjectNotePayload(
            projectId: draft.projectId,
            noteId: draft.noteId,
            text: draft.text,
            requestedSource: draft.requestedSource
        )
    }

    private static func makeParentProject(
        projectId: ProjectID
    ) throws -> LedgerEntityReference {
        do {
            return LedgerEntityReference(
                kind: .project,
                id: try EntityID(validating: projectId.rawValue)
            )
        } catch {
            throw ProjectNoteCreationFailure.parentProjectMismatch
        }
    }

    private enum CodingKeys: String, CodingKey {
        case draft
        case envelope
        case parentProject
        case fingerprint
    }
}

public protocol ProjectNoteCreating: Sendable {
    func add(_ command: AddProjectNoteCommand) async throws -> OperationReceipt
}
