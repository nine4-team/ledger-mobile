import Foundation

public enum ItemSpaceAssignmentFailure: Error, Equatable, Sendable {
    case emptyItemSelection
    case duplicateItemIdentity
    case invalidCapturedAt
    case draftAccountMismatch
    case draftActorMismatch
    case draftContractMismatch
    case draftPayloadMismatch
    case assignmentPreconditionsMismatch
    case subjectMismatch
    case fingerprintMismatch
    case receiptMismatch
    case localAcceptanceFailed
    case invalidEncodedScope
    case invalidEncodedCandidate
    case invalidEncodedDraft
    case invalidEncodedCommand

    public var diagnosticCode: String {
        switch self {
        case .emptyItemSelection:
            "item_space_assignment_selection_empty"
        case .duplicateItemIdentity:
            "item_space_assignment_item_duplicate"
        case .invalidCapturedAt:
            "item_space_assignment_captured_at_invalid"
        case .draftAccountMismatch:
            "item_space_assignment_account_mismatch"
        case .draftActorMismatch:
            "item_space_assignment_actor_mismatch"
        case .draftContractMismatch:
            "item_space_assignment_contract_mismatch"
        case .draftPayloadMismatch:
            "item_space_assignment_payload_mismatch"
        case .assignmentPreconditionsMismatch:
            "item_space_assignment_preconditions_mismatch"
        case .subjectMismatch:
            "item_space_assignment_subject_mismatch"
        case .fingerprintMismatch:
            "item_space_assignment_fingerprint_mismatch"
        case .receiptMismatch:
            "item_space_assignment_receipt_mismatch"
        case .localAcceptanceFailed:
            "item_space_assignment_local_acceptance_failed"
        case .invalidEncodedScope:
            "item_space_assignment_scope_encoding_invalid"
        case .invalidEncodedCandidate:
            "item_space_assignment_candidate_encoding_invalid"
        case .invalidEncodedDraft:
            "item_space_assignment_draft_encoding_invalid"
        case .invalidEncodedCommand:
            "item_space_assignment_command_encoding_invalid"
        }
    }
}

public enum ItemPlacementScope: Codable, Equatable, Sendable {
    case project(ProjectID)
    case businessInventory

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(ScopeKind.self, forKey: .kind) {
            case .project:
                guard container.contains(.projectId) else {
                    throw ItemSpaceAssignmentFailure.invalidEncodedScope
                }
                self = .project(try container.decode(ProjectID.self, forKey: .projectId))
            case .businessInventory:
                guard !container.contains(.projectId) else {
                    throw ItemSpaceAssignmentFailure.invalidEncodedScope
                }
                self = .businessInventory
            }
        } catch let failure as ItemSpaceAssignmentFailure {
            throw failure
        } catch {
            throw ItemSpaceAssignmentFailure.invalidEncodedScope
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

    fileprivate func targetReference(accountId: AccountID) throws -> LedgerEntityReference {
        do {
            switch self {
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
            throw ItemSpaceAssignmentFailure.assignmentPreconditionsMismatch
        }
    }

    fileprivate func relationCode() throws -> EntityStateCode {
        do {
            switch self {
            case .project:
                return try EntityStateCode(validating: "belongs_to_project")
            case .businessInventory:
                return try EntityStateCode(validating: "belongs_to_business_inventory")
            }
        } catch {
            throw ItemSpaceAssignmentFailure.assignmentPreconditionsMismatch
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

public struct ExpectedItemPlacementRevision: Codable, Equatable, Hashable, Sendable {
    public let rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

public struct ItemSpaceAssignmentCandidate: Codable, Equatable, Sendable {
    public let itemId: ItemID
    public let expectedRevision: ExpectedItemPlacementRevision

    public init(itemId: ItemID, expectedRevision: ExpectedItemPlacementRevision) {
        self.itemId = itemId
        self.expectedRevision = expectedRevision
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                itemId: try container.decode(ItemID.self, forKey: .itemId),
                expectedRevision: try container.decode(
                    ExpectedItemPlacementRevision.self,
                    forKey: .expectedRevision
                )
            )
        } catch {
            throw ItemSpaceAssignmentFailure.invalidEncodedCandidate
        }
    }

    private enum CodingKeys: String, CodingKey {
        case itemId
        case expectedRevision
    }
}

public struct ItemSpaceAssignmentDraft: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let actorPrincipalId: PrincipalID
    public let operationContractVersion: OperationContractVersion
    public let destinationSpaceId: SpaceID
    public let scope: ItemPlacementScope
    public let expectedSpaceRevision: ExpectedSpaceRevision
    public let items: [ItemSpaceAssignmentCandidate]
    public let capturedAt: Date

    public init(
        accountId: AccountID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        destinationSpaceId: SpaceID,
        scope: ItemPlacementScope,
        expectedSpaceRevision: ExpectedSpaceRevision,
        items: [ItemSpaceAssignmentCandidate],
        capturedAt: Date
    ) throws {
        guard capturedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw ItemSpaceAssignmentFailure.invalidCapturedAt
        }
        guard !items.isEmpty else {
            throw ItemSpaceAssignmentFailure.emptyItemSelection
        }
        guard Set(items.map(\.itemId)).count == items.count else {
            throw ItemSpaceAssignmentFailure.duplicateItemIdentity
        }

        self.accountId = accountId
        self.actorPrincipalId = actorPrincipalId
        self.operationContractVersion = operationContractVersion
        self.destinationSpaceId = destinationSpaceId
        self.scope = scope
        self.expectedSpaceRevision = expectedSpaceRevision
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
                destinationSpaceId: container.decode(
                    SpaceID.self,
                    forKey: .destinationSpaceId
                ),
                scope: container.decode(ItemPlacementScope.self, forKey: .scope),
                expectedSpaceRevision: container.decode(
                    ExpectedSpaceRevision.self,
                    forKey: .expectedSpaceRevision
                ),
                items: container.decode(
                    [ItemSpaceAssignmentCandidate].self,
                    forKey: .items
                ),
                capturedAt: container.decode(Date.self, forKey: .capturedAt)
            )
        } catch let failure as ItemSpaceAssignmentFailure {
            throw failure
        } catch {
            throw ItemSpaceAssignmentFailure.invalidEncodedDraft
        }
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case actorPrincipalId
        case operationContractVersion
        case destinationSpaceId
        case scope
        case expectedSpaceRevision
        case items
        case capturedAt
    }
}

public struct AssignItemsToSpacePayload: Codable, Equatable, Sendable {
    public let destinationSpaceId: SpaceID
    public let scope: ItemPlacementScope
    public let itemIds: [ItemID]

    public init(
        destinationSpaceId: SpaceID,
        scope: ItemPlacementScope,
        itemIds: [ItemID]
    ) {
        self.destinationSpaceId = destinationSpaceId
        self.scope = scope
        self.itemIds = itemIds
    }
}

public struct AssignItemsToSpaceCommand: Codable, Equatable, Sendable {
    public let draft: ItemSpaceAssignmentDraft
    public let envelope: OperationEnvelope<AssignItemsToSpacePayload>
    public let subject: LedgerEntityReference
    public let fingerprint: OperationFingerprint

    public init(operationId: OperationID, draft: ItemSpaceAssignmentDraft) throws {
        let payload = Self.makePayload(from: draft)
        let subject = try Self.makeReference(kind: .space, rawValue: draft.destinationSpaceId.rawValue)
        let envelope = OperationEnvelope(
            operationId: operationId,
            contractVersion: draft.operationContractVersion,
            accountId: draft.accountId,
            actorPrincipalId: draft.actorPrincipalId,
            clientCreatedAt: draft.capturedAt,
            payload: payload,
            preconditions: try Self.makePreconditions(draft: draft, subject: subject)
        )
        try self.init(
            draft: draft,
            envelope: envelope,
            subject: subject,
            fingerprint: OperationFingerprint.make(for: envelope)
        )
    }

    private init(
        draft: ItemSpaceAssignmentDraft,
        envelope: OperationEnvelope<AssignItemsToSpacePayload>,
        subject: LedgerEntityReference,
        fingerprint: OperationFingerprint
    ) throws {
        guard envelope.clientCreatedAt.timeIntervalSinceReferenceDate.isFinite,
              envelope.clientCreatedAt == draft.capturedAt else {
            throw ItemSpaceAssignmentFailure.invalidCapturedAt
        }
        guard envelope.accountId == draft.accountId else {
            throw ItemSpaceAssignmentFailure.draftAccountMismatch
        }
        guard envelope.actorPrincipalId == draft.actorPrincipalId else {
            throw ItemSpaceAssignmentFailure.draftActorMismatch
        }
        guard envelope.contractVersion == draft.operationContractVersion else {
            throw ItemSpaceAssignmentFailure.draftContractMismatch
        }
        guard envelope.payload == Self.makePayload(from: draft) else {
            throw ItemSpaceAssignmentFailure.draftPayloadMismatch
        }

        let expectedSubject = try Self.makeReference(
            kind: .space,
            rawValue: draft.destinationSpaceId.rawValue
        )
        guard envelope.preconditions == (try Self.makePreconditions(
            draft: draft,
            subject: expectedSubject
        )) else {
            throw ItemSpaceAssignmentFailure.assignmentPreconditionsMismatch
        }
        guard subject == expectedSubject else {
            throw ItemSpaceAssignmentFailure.subjectMismatch
        }
        guard fingerprint == (try OperationFingerprint.make(for: envelope)) else {
            throw ItemSpaceAssignmentFailure.fingerprintMismatch
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
                draft: container.decode(ItemSpaceAssignmentDraft.self, forKey: .draft),
                envelope: container.decode(
                    OperationEnvelope<AssignItemsToSpacePayload>.self,
                    forKey: .envelope
                ),
                subject: container.decode(LedgerEntityReference.self, forKey: .subject),
                fingerprint: container.decode(OperationFingerprint.self, forKey: .fingerprint)
            )
        } catch let failure as ItemSpaceAssignmentFailure {
            throw failure
        } catch {
            throw ItemSpaceAssignmentFailure.invalidEncodedCommand
        }
    }

    public func validate(_ receipt: OperationReceipt) throws -> OperationReceipt {
        guard receipt.operationId == envelope.operationId else {
            throw ItemSpaceAssignmentFailure.receiptMismatch
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
        from draft: ItemSpaceAssignmentDraft
    ) -> AssignItemsToSpacePayload {
        AssignItemsToSpacePayload(
            destinationSpaceId: draft.destinationSpaceId,
            scope: draft.scope,
            itemIds: draft.items.map(\.itemId)
        )
    }

    private static func makePreconditions(
        draft: ItemSpaceAssignmentDraft,
        subject: LedgerEntityReference
    ) throws -> [OperationPrecondition] {
        let scopeTarget = try draft.scope.targetReference(accountId: draft.accountId)
        let relation = try draft.scope.relationCode()
        let active = try EntityStateCode(validating: "active")
        var preconditions: [OperationPrecondition] = [
            .expectedState(subject: subject, state: active),
            .expectedRevision(
                subject: subject,
                revision: draft.expectedSpaceRevision.rawValue
            ),
            .expectedRelationship(
                subject: subject,
                relation: relation,
                target: scopeTarget
            )
        ]
        for item in draft.items {
            let itemSubject = try makeReference(kind: .item, rawValue: item.itemId.rawValue)
            preconditions.append(.expectedRevision(
                subject: itemSubject,
                revision: item.expectedRevision.rawValue
            ))
            preconditions.append(.expectedRelationship(
                subject: itemSubject,
                relation: relation,
                target: scopeTarget
            ))
        }
        return preconditions
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
            throw ItemSpaceAssignmentFailure.subjectMismatch
        }
    }

    private enum CodingKeys: String, CodingKey {
        case draft
        case envelope
        case subject
        case fingerprint
    }
}

public protocol ItemSpaceAssigning: Sendable {
    func assignItemsToSpace(
        _ command: AssignItemsToSpaceCommand
    ) async throws -> OperationReceipt
}
