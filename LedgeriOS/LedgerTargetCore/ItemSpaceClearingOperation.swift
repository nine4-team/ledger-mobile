import Foundation

public enum ItemSpaceClearingFailure: Error, Equatable, Sendable {
    case emptyItemSelection
    case duplicateItemIdentity
    case invalidCapturedAt
    case draftAccountMismatch
    case draftActorMismatch
    case draftContractMismatch
    case draftPayloadMismatch
    case clearingPreconditionsMismatch
    case subjectMismatch
    case fingerprintMismatch
    case receiptMismatch
    case localAcceptanceFailed
    case invalidEncodedCandidate
    case invalidEncodedDraft
    case invalidEncodedCommand

    public var diagnosticCode: String {
        switch self {
        case .emptyItemSelection:
            "item_space_clearing_selection_empty"
        case .duplicateItemIdentity:
            "item_space_clearing_item_duplicate"
        case .invalidCapturedAt:
            "item_space_clearing_captured_at_invalid"
        case .draftAccountMismatch:
            "item_space_clearing_account_mismatch"
        case .draftActorMismatch:
            "item_space_clearing_actor_mismatch"
        case .draftContractMismatch:
            "item_space_clearing_contract_mismatch"
        case .draftPayloadMismatch:
            "item_space_clearing_payload_mismatch"
        case .clearingPreconditionsMismatch:
            "item_space_clearing_preconditions_mismatch"
        case .subjectMismatch:
            "item_space_clearing_subject_mismatch"
        case .fingerprintMismatch:
            "item_space_clearing_fingerprint_mismatch"
        case .receiptMismatch:
            "item_space_clearing_receipt_mismatch"
        case .localAcceptanceFailed:
            "item_space_clearing_local_acceptance_failed"
        case .invalidEncodedCandidate:
            "item_space_clearing_candidate_encoding_invalid"
        case .invalidEncodedDraft:
            "item_space_clearing_draft_encoding_invalid"
        case .invalidEncodedCommand:
            "item_space_clearing_command_encoding_invalid"
        }
    }
}

public struct ItemSpaceClearingCandidate: Codable, Equatable, Sendable {
    public let itemId: ItemID
    public let expectedRevision: ExpectedItemPlacementRevision
    public let currentSpaceId: SpaceID

    public init(
        itemId: ItemID,
        expectedRevision: ExpectedItemPlacementRevision,
        currentSpaceId: SpaceID
    ) {
        self.itemId = itemId
        self.expectedRevision = expectedRevision
        self.currentSpaceId = currentSpaceId
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                itemId: try container.decode(ItemID.self, forKey: .itemId),
                expectedRevision: try container.decode(
                    ExpectedItemPlacementRevision.self,
                    forKey: .expectedRevision
                ),
                currentSpaceId: try container.decode(SpaceID.self, forKey: .currentSpaceId)
            )
        } catch {
            throw ItemSpaceClearingFailure.invalidEncodedCandidate
        }
    }

    private enum CodingKeys: String, CodingKey {
        case itemId
        case expectedRevision
        case currentSpaceId
    }
}

public struct ItemSpaceClearingDraft: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let actorPrincipalId: PrincipalID
    public let operationContractVersion: OperationContractVersion
    public let scope: ItemPlacementScope
    public let items: [ItemSpaceClearingCandidate]
    public let capturedAt: Date

    public init(
        accountId: AccountID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        scope: ItemPlacementScope,
        items: [ItemSpaceClearingCandidate],
        capturedAt: Date
    ) throws {
        guard capturedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw ItemSpaceClearingFailure.invalidCapturedAt
        }
        guard !items.isEmpty else {
            throw ItemSpaceClearingFailure.emptyItemSelection
        }
        guard Set(items.map(\.itemId)).count == items.count else {
            throw ItemSpaceClearingFailure.duplicateItemIdentity
        }

        self.accountId = accountId
        self.actorPrincipalId = actorPrincipalId
        self.operationContractVersion = operationContractVersion
        self.scope = scope
        self.items = items.sorted { $0.itemId.rawValue < $1.itemId.rawValue }
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
                scope: container.decode(ItemPlacementScope.self, forKey: .scope),
                items: container.decode(
                    [ItemSpaceClearingCandidate].self,
                    forKey: .items
                ),
                capturedAt: container.decode(Date.self, forKey: .capturedAt)
            )
        } catch let failure as ItemSpaceClearingFailure {
            throw failure
        } catch {
            throw ItemSpaceClearingFailure.invalidEncodedDraft
        }
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case actorPrincipalId
        case operationContractVersion
        case scope
        case items
        case capturedAt
    }
}

public struct ClearItemSpaceAssignmentsPayload: Codable, Equatable, Sendable {
    public let scope: ItemPlacementScope
    public let itemIds: [ItemID]

    public init(scope: ItemPlacementScope, itemIds: [ItemID]) {
        self.scope = scope
        self.itemIds = itemIds
    }
}

public struct ClearItemSpaceAssignmentsCommand: Codable, Equatable, Sendable {
    public let draft: ItemSpaceClearingDraft
    public let envelope: OperationEnvelope<ClearItemSpaceAssignmentsPayload>
    public let subject: LedgerEntityReference
    public let fingerprint: OperationFingerprint

    public init(operationId: OperationID, draft: ItemSpaceClearingDraft) throws {
        let payload = Self.makePayload(from: draft)
        let subject = try Self.makeScopeReference(
            draft.scope,
            accountId: draft.accountId,
            failure: .subjectMismatch
        )
        let envelope = OperationEnvelope(
            operationId: operationId,
            contractVersion: draft.operationContractVersion,
            accountId: draft.accountId,
            actorPrincipalId: draft.actorPrincipalId,
            clientCreatedAt: draft.capturedAt,
            payload: payload,
            preconditions: try Self.makePreconditions(draft: draft)
        )
        try self.init(
            draft: draft,
            envelope: envelope,
            subject: subject,
            fingerprint: OperationFingerprint.make(for: envelope)
        )
    }

    private init(
        draft: ItemSpaceClearingDraft,
        envelope: OperationEnvelope<ClearItemSpaceAssignmentsPayload>,
        subject: LedgerEntityReference,
        fingerprint: OperationFingerprint
    ) throws {
        guard envelope.clientCreatedAt.timeIntervalSinceReferenceDate.isFinite,
              envelope.clientCreatedAt == draft.capturedAt else {
            throw ItemSpaceClearingFailure.invalidCapturedAt
        }
        guard envelope.accountId == draft.accountId else {
            throw ItemSpaceClearingFailure.draftAccountMismatch
        }
        guard envelope.actorPrincipalId == draft.actorPrincipalId else {
            throw ItemSpaceClearingFailure.draftActorMismatch
        }
        guard envelope.contractVersion == draft.operationContractVersion else {
            throw ItemSpaceClearingFailure.draftContractMismatch
        }
        guard envelope.payload == Self.makePayload(from: draft) else {
            throw ItemSpaceClearingFailure.draftPayloadMismatch
        }
        guard envelope.preconditions == (try Self.makePreconditions(draft: draft)) else {
            throw ItemSpaceClearingFailure.clearingPreconditionsMismatch
        }

        let expectedSubject = try Self.makeScopeReference(
            draft.scope,
            accountId: draft.accountId,
            failure: .subjectMismatch
        )
        guard subject == expectedSubject else {
            throw ItemSpaceClearingFailure.subjectMismatch
        }
        guard fingerprint == (try OperationFingerprint.make(for: envelope)) else {
            throw ItemSpaceClearingFailure.fingerprintMismatch
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
                draft: container.decode(ItemSpaceClearingDraft.self, forKey: .draft),
                envelope: container.decode(
                    OperationEnvelope<ClearItemSpaceAssignmentsPayload>.self,
                    forKey: .envelope
                ),
                subject: container.decode(LedgerEntityReference.self, forKey: .subject),
                fingerprint: container.decode(OperationFingerprint.self, forKey: .fingerprint)
            )
        } catch let failure as ItemSpaceClearingFailure {
            throw failure
        } catch {
            throw ItemSpaceClearingFailure.invalidEncodedCommand
        }
    }

    public func validate(_ receipt: OperationReceipt) throws -> OperationReceipt {
        guard receipt.operationId == envelope.operationId else {
            throw ItemSpaceClearingFailure.receiptMismatch
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
        from draft: ItemSpaceClearingDraft
    ) -> ClearItemSpaceAssignmentsPayload {
        ClearItemSpaceAssignmentsPayload(
            scope: draft.scope,
            itemIds: draft.items.map(\.itemId)
        )
    }

    private static func makePreconditions(
        draft: ItemSpaceClearingDraft
    ) throws -> [OperationPrecondition] {
        let scopeTarget = try makeScopeReference(
            draft.scope,
            accountId: draft.accountId,
            failure: .clearingPreconditionsMismatch
        )
        let scopeRelation = try makeScopeRelation(draft.scope)
        let assignedToSpace: EntityStateCode
        do {
            assignedToSpace = try EntityStateCode(validating: "assigned_to_space")
        } catch {
            throw ItemSpaceClearingFailure.clearingPreconditionsMismatch
        }

        var preconditions: [OperationPrecondition] = []
        let currentSpaces = Set(draft.items.map(\.currentSpaceId)).sorted {
            $0.rawValue < $1.rawValue
        }
        for spaceId in currentSpaces {
            preconditions.append(.expectedRelationship(
                subject: try makeReference(kind: .space, rawValue: spaceId.rawValue),
                relation: scopeRelation,
                target: scopeTarget
            ))
        }
        for item in draft.items {
            let itemSubject = try makeReference(kind: .item, rawValue: item.itemId.rawValue)
            preconditions.append(.expectedRevision(
                subject: itemSubject,
                revision: item.expectedRevision.rawValue
            ))
            preconditions.append(.expectedRelationship(
                subject: itemSubject,
                relation: scopeRelation,
                target: scopeTarget
            ))
            preconditions.append(.expectedRelationship(
                subject: itemSubject,
                relation: assignedToSpace,
                target: try makeReference(
                    kind: .space,
                    rawValue: item.currentSpaceId.rawValue
                )
            ))
        }
        return preconditions
    }

    private static func makeScopeReference(
        _ scope: ItemPlacementScope,
        accountId: AccountID,
        failure: ItemSpaceClearingFailure
    ) throws -> LedgerEntityReference {
        do {
            switch scope {
            case .project(let projectId):
                return LedgerEntityReference(
                    kind: .project,
                    id: try EntityID(validating: projectId.rawValue)
                )
            case .businessInventory:
                return LedgerEntityReference(
                    kind: .account,
                    id: try EntityID(validating: accountId.rawValue)
                )
            }
        } catch {
            throw failure
        }
    }

    private static func makeScopeRelation(
        _ scope: ItemPlacementScope
    ) throws -> EntityStateCode {
        do {
            switch scope {
            case .project:
                return try EntityStateCode(validating: "belongs_to_project")
            case .businessInventory:
                return try EntityStateCode(validating: "belongs_to_business_inventory")
            }
        } catch {
            throw ItemSpaceClearingFailure.clearingPreconditionsMismatch
        }
    }

    private static func makeReference(
        kind: LedgerEntityKind,
        rawValue: String
    ) throws -> LedgerEntityReference {
        do {
            return LedgerEntityReference(
                kind: kind,
                id: try EntityID(validating: rawValue)
            )
        } catch {
            throw ItemSpaceClearingFailure.clearingPreconditionsMismatch
        }
    }

    private enum CodingKeys: String, CodingKey {
        case draft
        case envelope
        case subject
        case fingerprint
    }
}

public protocol ItemSpaceAssignmentClearing: Sendable {
    func clearItemSpaceAssignments(
        _ command: ClearItemSpaceAssignmentsCommand
    ) async throws -> OperationReceipt
}
