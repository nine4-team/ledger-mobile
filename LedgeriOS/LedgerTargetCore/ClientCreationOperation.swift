import Foundation

public enum ClientCreationFailure: Error, Equatable, Sendable {
    case invalidClientCreatedAt
    case draftAccountMismatch
    case draftActorMismatch
    case draftContractMismatch
    case draftPayloadMismatch
    case unexpectedPreconditions
    case subjectMismatch
    case fingerprintMismatch
    case receiptMismatch
    case localAcceptanceFailed
    case invalidEncodedCommand

    public var diagnosticCode: String {
        switch self {
        case .invalidClientCreatedAt:
            "client_creation_created_at_invalid"
        case .draftAccountMismatch:
            "client_creation_account_mismatch"
        case .draftActorMismatch:
            "client_creation_actor_mismatch"
        case .draftContractMismatch:
            "client_creation_contract_mismatch"
        case .draftPayloadMismatch:
            "client_creation_payload_mismatch"
        case .unexpectedPreconditions:
            "client_creation_preconditions_unexpected"
        case .subjectMismatch:
            "client_creation_subject_mismatch"
        case .fingerprintMismatch:
            "client_creation_fingerprint_mismatch"
        case .receiptMismatch:
            "client_creation_receipt_mismatch"
        case .localAcceptanceFailed:
            "client_creation_local_acceptance_failed"
        case .invalidEncodedCommand:
            "client_creation_command_encoding_invalid"
        }
    }
}

public struct ClientCreationDraft: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let actorPrincipalId: PrincipalID
    public let operationContractVersion: OperationContractVersion
    public let clientId: ClientID
    public let displayName: ClientDisplayName
    public let capturedAt: Date

    public init(
        accountId: AccountID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        clientId: ClientID,
        displayName: ClientDisplayName,
        capturedAt: Date
    ) throws {
        guard capturedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw ClientCreationFailure.invalidClientCreatedAt
        }
        self.accountId = accountId
        self.actorPrincipalId = actorPrincipalId
        self.operationContractVersion = operationContractVersion
        self.clientId = clientId
        self.displayName = displayName
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
            clientId: container.decode(ClientID.self, forKey: .clientId),
            displayName: container.decode(ClientDisplayName.self, forKey: .displayName),
            capturedAt: container.decode(Date.self, forKey: .capturedAt)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case actorPrincipalId
        case operationContractVersion
        case clientId
        case displayName
        case capturedAt
    }
}

public struct CreateClientPayload: Codable, Equatable, Sendable {
    public let clientId: ClientID
    public let displayName: ClientDisplayName

    public init(clientId: ClientID, displayName: ClientDisplayName) {
        self.clientId = clientId
        self.displayName = displayName
    }
}

public struct CreateClientCommand: Codable, Equatable, Sendable {
    public let draft: ClientCreationDraft
    public let envelope: OperationEnvelope<CreateClientPayload>
    public let subject: LedgerEntityReference
    public let fingerprint: OperationFingerprint

    public init(operationId: OperationID, draft: ClientCreationDraft) throws {
        let payload = CreateClientPayload(
            clientId: draft.clientId,
            displayName: draft.displayName
        )
        let envelope = OperationEnvelope(
            operationId: operationId,
            contractVersion: draft.operationContractVersion,
            accountId: draft.accountId,
            actorPrincipalId: draft.actorPrincipalId,
            clientCreatedAt: draft.capturedAt,
            payload: payload
        )
        let subject = try Self.makeSubject(clientId: draft.clientId)
        let fingerprint = try OperationFingerprint.make(for: envelope)
        try self.init(
            draft: draft,
            envelope: envelope,
            subject: subject,
            fingerprint: fingerprint
        )
    }

    private init(
        draft: ClientCreationDraft,
        envelope: OperationEnvelope<CreateClientPayload>,
        subject: LedgerEntityReference,
        fingerprint: OperationFingerprint
    ) throws {
        guard envelope.clientCreatedAt.timeIntervalSinceReferenceDate.isFinite,
              envelope.clientCreatedAt == draft.capturedAt else {
            throw ClientCreationFailure.invalidClientCreatedAt
        }
        guard envelope.accountId == draft.accountId else {
            throw ClientCreationFailure.draftAccountMismatch
        }
        guard envelope.actorPrincipalId == draft.actorPrincipalId else {
            throw ClientCreationFailure.draftActorMismatch
        }
        guard envelope.contractVersion == draft.operationContractVersion else {
            throw ClientCreationFailure.draftContractMismatch
        }
        let expectedPayload = CreateClientPayload(
            clientId: draft.clientId,
            displayName: draft.displayName
        )
        guard envelope.payload == expectedPayload else {
            throw ClientCreationFailure.draftPayloadMismatch
        }
        guard envelope.preconditions.isEmpty else {
            throw ClientCreationFailure.unexpectedPreconditions
        }
        guard subject == (try Self.makeSubject(clientId: draft.clientId)) else {
            throw ClientCreationFailure.subjectMismatch
        }
        guard fingerprint == (try OperationFingerprint.make(for: envelope)) else {
            throw ClientCreationFailure.fingerprintMismatch
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
                draft: container.decode(ClientCreationDraft.self, forKey: .draft),
                envelope: container.decode(
                    OperationEnvelope<CreateClientPayload>.self,
                    forKey: .envelope
                ),
                subject: container.decode(LedgerEntityReference.self, forKey: .subject),
                fingerprint: container.decode(OperationFingerprint.self, forKey: .fingerprint)
            )
        } catch let failure as ClientCreationFailure {
            throw failure
        } catch {
            throw ClientCreationFailure.invalidEncodedCommand
        }
    }

    public func validate(_ receipt: OperationReceipt) throws -> OperationReceipt {
        guard receipt.operationId == envelope.operationId else {
            throw ClientCreationFailure.receiptMismatch
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
            throw ClientCreationFailure.subjectMismatch
        }
    }

    private enum CodingKeys: String, CodingKey {
        case draft
        case envelope
        case subject
        case fingerprint
    }
}

public protocol ClientCreationOperating: Sendable {
    func create(_ command: CreateClientCommand) async throws -> OperationReceipt
}
