import Foundation

public enum SpaceCreationFailure: Error, Equatable, Sendable {
    case invalidDisplayName
    case invalidEncodedDisplayName
    case invalidEncodedNotes
    case invalidCreationScope
    case invalidCapturedAt
    case draftAccountMismatch
    case draftActorMismatch
    case draftContractMismatch
    case draftPayloadMismatch
    case unexpectedPreconditions
    case subjectMismatch
    case fingerprintMismatch
    case receiptMismatch
    case localAcceptanceFailed
    case invalidEncodedDraft
    case invalidEncodedCommand

    public var diagnosticCode: String {
        switch self {
        case .invalidDisplayName:
            "space_creation_display_name_invalid"
        case .invalidEncodedDisplayName:
            "space_creation_display_name_encoding_invalid"
        case .invalidEncodedNotes:
            "space_creation_notes_encoding_invalid"
        case .invalidCreationScope:
            "space_creation_scope_invalid"
        case .invalidCapturedAt:
            "space_creation_captured_at_invalid"
        case .draftAccountMismatch:
            "space_creation_account_mismatch"
        case .draftActorMismatch:
            "space_creation_actor_mismatch"
        case .draftContractMismatch:
            "space_creation_contract_mismatch"
        case .draftPayloadMismatch:
            "space_creation_payload_mismatch"
        case .unexpectedPreconditions:
            "space_creation_preconditions_unexpected"
        case .subjectMismatch:
            "space_creation_subject_mismatch"
        case .fingerprintMismatch:
            "space_creation_fingerprint_mismatch"
        case .receiptMismatch:
            "space_creation_receipt_mismatch"
        case .localAcceptanceFailed:
            "space_creation_local_acceptance_failed"
        case .invalidEncodedDraft:
            "space_creation_draft_encoding_invalid"
        case .invalidEncodedCommand:
            "space_creation_command_encoding_invalid"
        }
    }
}

public enum SpaceCreationScope: Codable, Equatable, Sendable {
    case project(ProjectID)
    case businessInventory

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(ScopeKind.self, forKey: .kind) {
            case .project:
                guard container.contains(.projectId) else {
                    throw SpaceCreationFailure.invalidCreationScope
                }
                self = .project(try container.decode(ProjectID.self, forKey: .projectId))
            case .businessInventory:
                guard !container.contains(.projectId) else {
                    throw SpaceCreationFailure.invalidCreationScope
                }
                self = .businessInventory
            }
        } catch let failure as SpaceCreationFailure {
            throw failure
        } catch {
            throw SpaceCreationFailure.invalidCreationScope
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .project(let projectId):
            try container.encode(ScopeKind.project, forKey: .kind)
            try container.encode(projectId, forKey: .projectId)
        case .businessInventory:
            try container.encode(ScopeKind.businessInventory, forKey: .kind)
        }
    }

    private enum ScopeKind: String, Codable {
        case project
        case businessInventory
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case projectId
    }
}

public struct SpaceDisplayName: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw SpaceCreationFailure.invalidDisplayName
        }
        self.rawValue = normalized
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            let canonical = try Self(validating: rawValue)
            guard canonical.rawValue == rawValue else {
                throw SpaceCreationFailure.invalidEncodedDisplayName
            }
            self = canonical
        } catch {
            throw SpaceCreationFailure.invalidEncodedDisplayName
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct SpaceCreationNotes: Codable, Equatable, Sendable {
    public let value: String?

    public init(_ rawValue: String?) {
        let normalized = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        value = normalized?.isEmpty == false ? normalized : nil
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard container.contains(.value) else {
                throw SpaceCreationFailure.invalidEncodedNotes
            }
            let rawValue = try container.decodeIfPresent(String.self, forKey: .value)
            let canonical = Self(rawValue)
            guard rawValue == canonical.value else {
                throw SpaceCreationFailure.invalidEncodedNotes
            }
            self = canonical
        } catch {
            throw SpaceCreationFailure.invalidEncodedNotes
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

public struct SpaceCreationDraft: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let actorPrincipalId: PrincipalID
    public let operationContractVersion: OperationContractVersion
    public let spaceId: SpaceID
    public let scope: SpaceCreationScope
    public let displayName: SpaceDisplayName
    public let notes: SpaceCreationNotes
    public let capturedAt: Date

    public init(
        accountId: AccountID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        spaceId: SpaceID,
        scope: SpaceCreationScope,
        displayName: SpaceDisplayName,
        notes: SpaceCreationNotes,
        capturedAt: Date
    ) throws {
        guard capturedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw SpaceCreationFailure.invalidCapturedAt
        }
        self.accountId = accountId
        self.actorPrincipalId = actorPrincipalId
        self.operationContractVersion = operationContractVersion
        self.spaceId = spaceId
        self.scope = scope
        self.displayName = displayName
        self.notes = notes
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
                spaceId: container.decode(SpaceID.self, forKey: .spaceId),
                scope: container.decode(SpaceCreationScope.self, forKey: .scope),
                displayName: container.decode(SpaceDisplayName.self, forKey: .displayName),
                notes: container.decode(SpaceCreationNotes.self, forKey: .notes),
                capturedAt: container.decode(Date.self, forKey: .capturedAt)
            )
        } catch let failure as SpaceCreationFailure {
            throw failure
        } catch {
            throw SpaceCreationFailure.invalidEncodedDraft
        }
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case actorPrincipalId
        case operationContractVersion
        case spaceId
        case scope
        case displayName
        case notes
        case capturedAt
    }
}

public struct CreateSpacePayload: Codable, Equatable, Sendable {
    public let spaceId: SpaceID
    public let scope: SpaceCreationScope
    public let displayName: SpaceDisplayName
    public let notes: SpaceCreationNotes

    public init(
        spaceId: SpaceID,
        scope: SpaceCreationScope,
        displayName: SpaceDisplayName,
        notes: SpaceCreationNotes
    ) {
        self.spaceId = spaceId
        self.scope = scope
        self.displayName = displayName
        self.notes = notes
    }
}

public struct CreateSpaceCommand: Codable, Equatable, Sendable {
    public let draft: SpaceCreationDraft
    public let envelope: OperationEnvelope<CreateSpacePayload>
    public let subject: LedgerEntityReference
    public let fingerprint: OperationFingerprint

    public init(operationId: OperationID, draft: SpaceCreationDraft) throws {
        let payload = Self.makePayload(from: draft)
        let envelope = OperationEnvelope(
            operationId: operationId,
            contractVersion: draft.operationContractVersion,
            accountId: draft.accountId,
            actorPrincipalId: draft.actorPrincipalId,
            clientCreatedAt: draft.capturedAt,
            payload: payload
        )
        let subject = try Self.makeSubject(spaceId: draft.spaceId)
        let fingerprint = try OperationFingerprint.make(for: envelope)
        try self.init(
            draft: draft,
            envelope: envelope,
            subject: subject,
            fingerprint: fingerprint
        )
    }

    private init(
        draft: SpaceCreationDraft,
        envelope: OperationEnvelope<CreateSpacePayload>,
        subject: LedgerEntityReference,
        fingerprint: OperationFingerprint
    ) throws {
        guard envelope.clientCreatedAt.timeIntervalSinceReferenceDate.isFinite,
              envelope.clientCreatedAt == draft.capturedAt else {
            throw SpaceCreationFailure.invalidCapturedAt
        }
        guard envelope.accountId == draft.accountId else {
            throw SpaceCreationFailure.draftAccountMismatch
        }
        guard envelope.actorPrincipalId == draft.actorPrincipalId else {
            throw SpaceCreationFailure.draftActorMismatch
        }
        guard envelope.contractVersion == draft.operationContractVersion else {
            throw SpaceCreationFailure.draftContractMismatch
        }
        guard envelope.payload == Self.makePayload(from: draft) else {
            throw SpaceCreationFailure.draftPayloadMismatch
        }
        guard envelope.preconditions.isEmpty else {
            throw SpaceCreationFailure.unexpectedPreconditions
        }
        guard subject == (try Self.makeSubject(spaceId: draft.spaceId)) else {
            throw SpaceCreationFailure.subjectMismatch
        }
        guard fingerprint == (try OperationFingerprint.make(for: envelope)) else {
            throw SpaceCreationFailure.fingerprintMismatch
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
                draft: container.decode(SpaceCreationDraft.self, forKey: .draft),
                envelope: container.decode(
                    OperationEnvelope<CreateSpacePayload>.self,
                    forKey: .envelope
                ),
                subject: container.decode(LedgerEntityReference.self, forKey: .subject),
                fingerprint: container.decode(OperationFingerprint.self, forKey: .fingerprint)
            )
        } catch let failure as SpaceCreationFailure {
            throw failure
        } catch {
            throw SpaceCreationFailure.invalidEncodedCommand
        }
    }

    public func validate(_ receipt: OperationReceipt) throws -> OperationReceipt {
        guard receipt.operationId == envelope.operationId else {
            throw SpaceCreationFailure.receiptMismatch
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

    private static func makePayload(from draft: SpaceCreationDraft) -> CreateSpacePayload {
        CreateSpacePayload(
            spaceId: draft.spaceId,
            scope: draft.scope,
            displayName: draft.displayName,
            notes: draft.notes
        )
    }

    private static func makeSubject(spaceId: SpaceID) throws -> LedgerEntityReference {
        do {
            return LedgerEntityReference(
                kind: .space,
                id: try EntityID(validating: spaceId.rawValue)
            )
        } catch {
            throw SpaceCreationFailure.subjectMismatch
        }
    }

    private enum CodingKeys: String, CodingKey {
        case draft
        case envelope
        case subject
        case fingerprint
    }
}

public protocol SpaceCreating: Sendable {
    func create(_ command: CreateSpaceCommand) async throws -> OperationReceipt
}
// Implementation is intentionally absent until the exact ready checkpoint passes.
