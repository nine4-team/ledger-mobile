import Foundation

public enum SpaceDetailsUpdateFailure: Error, Equatable, Sendable {
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
            "space_details_update_captured_at_invalid"
        case .draftAccountMismatch:
            "space_details_update_account_mismatch"
        case .draftActorMismatch:
            "space_details_update_actor_mismatch"
        case .draftContractMismatch:
            "space_details_update_contract_mismatch"
        case .draftPayloadMismatch:
            "space_details_update_payload_mismatch"
        case .revisionPreconditionMismatch:
            "space_details_update_revision_precondition_mismatch"
        case .subjectMismatch:
            "space_details_update_subject_mismatch"
        case .fingerprintMismatch:
            "space_details_update_fingerprint_mismatch"
        case .receiptMismatch:
            "space_details_update_receipt_mismatch"
        case .localAcceptanceFailed:
            "space_details_update_local_acceptance_failed"
        case .invalidEncodedDraft:
            "space_details_update_draft_encoding_invalid"
        case .invalidEncodedCommand:
            "space_details_update_command_encoding_invalid"
        }
    }
}

public struct ExpectedSpaceRevision: Codable, Equatable, Hashable, Sendable {
    public let rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

public struct SpaceDetailsUpdateDraft: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let actorPrincipalId: PrincipalID
    public let operationContractVersion: OperationContractVersion
    public let spaceId: SpaceID
    public let displayName: SpaceDisplayName
    public let notes: SpaceCreationNotes
    public let expectedRevision: ExpectedSpaceRevision
    public let capturedAt: Date

    public init(
        accountId: AccountID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        spaceId: SpaceID,
        displayName: SpaceDisplayName,
        notes: SpaceCreationNotes,
        expectedRevision: ExpectedSpaceRevision,
        capturedAt: Date
    ) throws {
        guard capturedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw SpaceDetailsUpdateFailure.invalidCapturedAt
        }
        self.accountId = accountId
        self.actorPrincipalId = actorPrincipalId
        self.operationContractVersion = operationContractVersion
        self.spaceId = spaceId
        self.displayName = displayName
        self.notes = notes
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
                spaceId: container.decode(SpaceID.self, forKey: .spaceId),
                displayName: container.decode(SpaceDisplayName.self, forKey: .displayName),
                notes: container.decode(SpaceCreationNotes.self, forKey: .notes),
                expectedRevision: container.decode(
                    ExpectedSpaceRevision.self,
                    forKey: .expectedRevision
                ),
                capturedAt: container.decode(Date.self, forKey: .capturedAt)
            )
        } catch let failure as SpaceCreationFailure {
            throw failure
        } catch let failure as SpaceDetailsUpdateFailure {
            throw failure
        } catch {
            throw SpaceDetailsUpdateFailure.invalidEncodedDraft
        }
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case actorPrincipalId
        case operationContractVersion
        case spaceId
        case displayName
        case notes
        case expectedRevision
        case capturedAt
    }
}

public struct UpdateSpaceDetailsPayload: Codable, Equatable, Sendable {
    public let spaceId: SpaceID
    public let displayName: SpaceDisplayName
    public let notes: SpaceCreationNotes

    public init(
        spaceId: SpaceID,
        displayName: SpaceDisplayName,
        notes: SpaceCreationNotes
    ) {
        self.spaceId = spaceId
        self.displayName = displayName
        self.notes = notes
    }
}

public struct UpdateSpaceDetailsCommand: Codable, Equatable, Sendable {
    public let draft: SpaceDetailsUpdateDraft
    public let envelope: OperationEnvelope<UpdateSpaceDetailsPayload>
    public let subject: LedgerEntityReference
    public let fingerprint: OperationFingerprint

    public init(operationId: OperationID, draft: SpaceDetailsUpdateDraft) throws {
        let payload = Self.makePayload(from: draft)
        let subject = try Self.makeSubject(spaceId: draft.spaceId)
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
        draft: SpaceDetailsUpdateDraft,
        envelope: OperationEnvelope<UpdateSpaceDetailsPayload>,
        subject: LedgerEntityReference,
        fingerprint: OperationFingerprint
    ) throws {
        guard envelope.clientCreatedAt.timeIntervalSinceReferenceDate.isFinite,
              envelope.clientCreatedAt == draft.capturedAt else {
            throw SpaceDetailsUpdateFailure.invalidCapturedAt
        }
        guard envelope.accountId == draft.accountId else {
            throw SpaceDetailsUpdateFailure.draftAccountMismatch
        }
        guard envelope.actorPrincipalId == draft.actorPrincipalId else {
            throw SpaceDetailsUpdateFailure.draftActorMismatch
        }
        guard envelope.contractVersion == draft.operationContractVersion else {
            throw SpaceDetailsUpdateFailure.draftContractMismatch
        }
        guard envelope.payload == Self.makePayload(from: draft) else {
            throw SpaceDetailsUpdateFailure.draftPayloadMismatch
        }

        let expectedSubject = try Self.makeSubject(spaceId: draft.spaceId)
        let expectedPreconditions: [OperationPrecondition] = [
            .expectedRevision(
                subject: expectedSubject,
                revision: draft.expectedRevision.rawValue
            )
        ]
        guard envelope.preconditions == expectedPreconditions else {
            throw SpaceDetailsUpdateFailure.revisionPreconditionMismatch
        }
        guard subject == expectedSubject else {
            throw SpaceDetailsUpdateFailure.subjectMismatch
        }
        guard fingerprint == (try OperationFingerprint.make(for: envelope)) else {
            throw SpaceDetailsUpdateFailure.fingerprintMismatch
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
                draft: container.decode(SpaceDetailsUpdateDraft.self, forKey: .draft),
                envelope: container.decode(
                    OperationEnvelope<UpdateSpaceDetailsPayload>.self,
                    forKey: .envelope
                ),
                subject: container.decode(LedgerEntityReference.self, forKey: .subject),
                fingerprint: container.decode(OperationFingerprint.self, forKey: .fingerprint)
            )
        } catch let failure as SpaceCreationFailure {
            throw failure
        } catch let failure as SpaceDetailsUpdateFailure {
            throw failure
        } catch {
            throw SpaceDetailsUpdateFailure.invalidEncodedCommand
        }
    }

    public func validate(_ receipt: OperationReceipt) throws -> OperationReceipt {
        guard receipt.operationId == envelope.operationId else {
            throw SpaceDetailsUpdateFailure.receiptMismatch
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

    private static func makePayload(
        from draft: SpaceDetailsUpdateDraft
    ) -> UpdateSpaceDetailsPayload {
        UpdateSpaceDetailsPayload(
            spaceId: draft.spaceId,
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
            throw SpaceDetailsUpdateFailure.subjectMismatch
        }
    }

    private enum CodingKeys: String, CodingKey {
        case draft
        case envelope
        case subject
        case fingerprint
    }
}

public protocol SpaceDetailsUpdating: Sendable {
    func updateDetails(_ command: UpdateSpaceDetailsCommand) async throws -> OperationReceipt
}
