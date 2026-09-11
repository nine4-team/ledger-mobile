import Foundation

public enum ClientArchiveFailure: Error, Equatable, Sendable {
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
            "client_archive_captured_at_invalid"
        case .draftAccountMismatch:
            "client_archive_account_mismatch"
        case .draftActorMismatch:
            "client_archive_actor_mismatch"
        case .draftContractMismatch:
            "client_archive_contract_mismatch"
        case .draftPayloadMismatch:
            "client_archive_payload_mismatch"
        case .revisionPreconditionMismatch:
            "client_archive_revision_precondition_mismatch"
        case .subjectMismatch:
            "client_archive_subject_mismatch"
        case .fingerprintMismatch:
            "client_archive_fingerprint_mismatch"
        case .receiptMismatch:
            "client_archive_receipt_mismatch"
        case .localAcceptanceFailed:
            "client_archive_local_acceptance_failed"
        case .invalidEncodedDraft:
            "client_archive_draft_encoding_invalid"
        case .invalidEncodedCommand:
            "client_archive_command_encoding_invalid"
        }
    }
}

public struct ClientArchiveDraft: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let actorPrincipalId: PrincipalID
    public let operationContractVersion: OperationContractVersion
    public let clientId: ClientID
    public let expectedRevision: ExpectedClientRevision
    public let capturedAt: Date

    public init(
        accountId: AccountID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        clientId: ClientID,
        expectedRevision: ExpectedClientRevision,
        capturedAt: Date
    ) throws {
        guard capturedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw ClientArchiveFailure.invalidCapturedAt
        }
        self.accountId = accountId
        self.actorPrincipalId = actorPrincipalId
        self.operationContractVersion = operationContractVersion
        self.clientId = clientId
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
                expectedRevision: container.decode(
                    ExpectedClientRevision.self,
                    forKey: .expectedRevision
                ),
                capturedAt: container.decode(Date.self, forKey: .capturedAt)
            )
        } catch let failure as ClientArchiveFailure {
            throw failure
        } catch {
            throw ClientArchiveFailure.invalidEncodedDraft
        }
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case actorPrincipalId
        case operationContractVersion
        case clientId
        case expectedRevision
        case capturedAt
    }
}

public struct ArchiveClientPayload: Codable, Equatable, Sendable {
    public let clientId: ClientID

    public init(clientId: ClientID) {
        self.clientId = clientId
    }
}

public struct ArchiveClientCommand: Codable, Equatable, Sendable {
    public let draft: ClientArchiveDraft
    public let envelope: OperationEnvelope<ArchiveClientPayload>
    public let subject: LedgerEntityReference
    public let fingerprint: OperationFingerprint

    public init(operationId: OperationID, draft: ClientArchiveDraft) throws {
        let payload = ArchiveClientPayload(clientId: draft.clientId)
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
        draft: ClientArchiveDraft,
        envelope: OperationEnvelope<ArchiveClientPayload>,
        subject: LedgerEntityReference,
        fingerprint: OperationFingerprint
    ) throws {
        guard envelope.clientCreatedAt.timeIntervalSinceReferenceDate.isFinite,
              envelope.clientCreatedAt == draft.capturedAt else {
            throw ClientArchiveFailure.invalidCapturedAt
        }
        guard envelope.accountId == draft.accountId else {
            throw ClientArchiveFailure.draftAccountMismatch
        }
        guard envelope.actorPrincipalId == draft.actorPrincipalId else {
            throw ClientArchiveFailure.draftActorMismatch
        }
        guard envelope.contractVersion == draft.operationContractVersion else {
            throw ClientArchiveFailure.draftContractMismatch
        }
        guard envelope.payload == ArchiveClientPayload(clientId: draft.clientId) else {
            throw ClientArchiveFailure.draftPayloadMismatch
        }

        let expectedSubject = try Self.makeSubject(clientId: draft.clientId)
        let expectedPreconditions: [OperationPrecondition] = [
            .expectedRevision(
                subject: expectedSubject,
                revision: draft.expectedRevision.rawValue
            )
        ]
        guard envelope.preconditions == expectedPreconditions else {
            throw ClientArchiveFailure.revisionPreconditionMismatch
        }
        guard subject == expectedSubject else {
            throw ClientArchiveFailure.subjectMismatch
        }
        guard fingerprint == (try OperationFingerprint.make(for: envelope)) else {
            throw ClientArchiveFailure.fingerprintMismatch
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
                draft: container.decode(ClientArchiveDraft.self, forKey: .draft),
                envelope: container.decode(
                    OperationEnvelope<ArchiveClientPayload>.self,
                    forKey: .envelope
                ),
                subject: container.decode(LedgerEntityReference.self, forKey: .subject),
                fingerprint: container.decode(OperationFingerprint.self, forKey: .fingerprint)
            )
        } catch let failure as ClientArchiveFailure {
            throw failure
        } catch {
            throw ClientArchiveFailure.invalidEncodedCommand
        }
    }

    public func validate(_ receipt: OperationReceipt) throws -> OperationReceipt {
        guard receipt.operationId == envelope.operationId else {
            throw ClientArchiveFailure.receiptMismatch
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
            throw ClientArchiveFailure.subjectMismatch
        }
    }

    private enum CodingKeys: String, CodingKey {
        case draft
        case envelope
        case subject
        case fingerprint
    }
}

public protocol ClientArchiving: Sendable {
    func archive(_ command: ArchiveClientCommand) async throws -> OperationReceipt
}
