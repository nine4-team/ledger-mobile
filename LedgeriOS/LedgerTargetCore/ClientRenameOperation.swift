import Foundation

public enum ClientRenameFailure: Error, Equatable, Sendable {
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
            "client_rename_captured_at_invalid"
        case .draftAccountMismatch:
            "client_rename_account_mismatch"
        case .draftActorMismatch:
            "client_rename_actor_mismatch"
        case .draftContractMismatch:
            "client_rename_contract_mismatch"
        case .draftPayloadMismatch:
            "client_rename_payload_mismatch"
        case .revisionPreconditionMismatch:
            "client_rename_revision_precondition_mismatch"
        case .subjectMismatch:
            "client_rename_subject_mismatch"
        case .fingerprintMismatch:
            "client_rename_fingerprint_mismatch"
        case .receiptMismatch:
            "client_rename_receipt_mismatch"
        case .localAcceptanceFailed:
            "client_rename_local_acceptance_failed"
        case .invalidEncodedDraft:
            "client_rename_draft_encoding_invalid"
        case .invalidEncodedCommand:
            "client_rename_command_encoding_invalid"
        }
    }
}

public struct ExpectedClientRevision: Codable, Equatable, Hashable, Sendable {
    public let rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

public struct ClientRenameDraft: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let actorPrincipalId: PrincipalID
    public let operationContractVersion: OperationContractVersion
    public let clientId: ClientID
    public let newDisplayName: ClientDisplayName
    public let expectedRevision: ExpectedClientRevision
    public let capturedAt: Date

    public init(
        accountId: AccountID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        clientId: ClientID,
        newDisplayName: ClientDisplayName,
        expectedRevision: ExpectedClientRevision,
        capturedAt: Date
    ) throws {
        guard capturedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw ClientRenameFailure.invalidCapturedAt
        }
        self.accountId = accountId
        self.actorPrincipalId = actorPrincipalId
        self.operationContractVersion = operationContractVersion
        self.clientId = clientId
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
                clientId: container.decode(ClientID.self, forKey: .clientId),
                newDisplayName: container.decode(
                    ClientDisplayName.self,
                    forKey: .newDisplayName
                ),
                expectedRevision: container.decode(
                    ExpectedClientRevision.self,
                    forKey: .expectedRevision
                ),
                capturedAt: container.decode(Date.self, forKey: .capturedAt)
            )
        } catch let failure as ClientRenameFailure {
            throw failure
        } catch {
            throw ClientRenameFailure.invalidEncodedDraft
        }
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case actorPrincipalId
        case operationContractVersion
        case clientId
        case newDisplayName
        case expectedRevision
        case capturedAt
    }
}

public struct RenameClientPayload: Codable, Equatable, Sendable {
    public let clientId: ClientID
    public let displayName: ClientDisplayName

    public init(clientId: ClientID, displayName: ClientDisplayName) {
        self.clientId = clientId
        self.displayName = displayName
    }
}

public struct RenameClientCommand: Codable, Equatable, Sendable {
    public let draft: ClientRenameDraft
    public let envelope: OperationEnvelope<RenameClientPayload>
    public let subject: LedgerEntityReference
    public let fingerprint: OperationFingerprint

    public init(operationId: OperationID, draft: ClientRenameDraft) throws {
        let payload = RenameClientPayload(
            clientId: draft.clientId,
            displayName: draft.newDisplayName
        )
        let subject = try Self.makeSubject(clientId: draft.clientId)
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
        draft: ClientRenameDraft,
        envelope: OperationEnvelope<RenameClientPayload>,
        subject: LedgerEntityReference,
        fingerprint: OperationFingerprint
    ) throws {
        guard envelope.clientCreatedAt.timeIntervalSinceReferenceDate.isFinite,
              envelope.clientCreatedAt == draft.capturedAt else {
            throw ClientRenameFailure.invalidCapturedAt
        }
        guard envelope.accountId == draft.accountId else {
            throw ClientRenameFailure.draftAccountMismatch
        }
        guard envelope.actorPrincipalId == draft.actorPrincipalId else {
            throw ClientRenameFailure.draftActorMismatch
        }
        guard envelope.contractVersion == draft.operationContractVersion else {
            throw ClientRenameFailure.draftContractMismatch
        }
        let expectedPayload = RenameClientPayload(
            clientId: draft.clientId,
            displayName: draft.newDisplayName
        )
        guard envelope.payload == expectedPayload else {
            throw ClientRenameFailure.draftPayloadMismatch
        }

        let expectedSubject = try Self.makeSubject(clientId: draft.clientId)
        let expectedPreconditions: [OperationPrecondition] = [
            .expectedRevision(
                subject: expectedSubject,
                revision: draft.expectedRevision.rawValue
            )
        ]
        guard envelope.preconditions == expectedPreconditions else {
            throw ClientRenameFailure.revisionPreconditionMismatch
        }
        guard subject == expectedSubject else {
            throw ClientRenameFailure.subjectMismatch
        }
        guard fingerprint == (try OperationFingerprint.make(for: envelope)) else {
            throw ClientRenameFailure.fingerprintMismatch
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
                draft: container.decode(ClientRenameDraft.self, forKey: .draft),
                envelope: container.decode(
                    OperationEnvelope<RenameClientPayload>.self,
                    forKey: .envelope
                ),
                subject: container.decode(LedgerEntityReference.self, forKey: .subject),
                fingerprint: container.decode(OperationFingerprint.self, forKey: .fingerprint)
            )
        } catch let failure as ClientRenameFailure {
            throw failure
        } catch {
            throw ClientRenameFailure.invalidEncodedCommand
        }
    }

    public func validate(_ receipt: OperationReceipt) throws -> OperationReceipt {
        guard receipt.operationId == envelope.operationId else {
            throw ClientRenameFailure.receiptMismatch
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

    private static func makeSubject(clientId: ClientID) throws -> LedgerEntityReference {
        do {
            return LedgerEntityReference(
                kind: .client,
                id: try EntityID(validating: clientId.rawValue)
            )
        } catch {
            throw ClientRenameFailure.subjectMismatch
        }
    }

    private enum CodingKeys: String, CodingKey {
        case draft
        case envelope
        case subject
        case fingerprint
    }
}

public protocol ClientRenaming: Sendable {
    func rename(_ command: RenameClientCommand) async throws -> OperationReceipt
}
