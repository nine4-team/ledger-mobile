import Foundation

public enum SpaceChecklistRevisionFailure: Error, Equatable, Sendable {
    case invalidChecklistName
    case invalidChecklistItemText
    case duplicateChecklistIdentity
    case duplicateChecklistPresentationOrder
    case duplicateChecklistItemIdentity
    case duplicateChecklistItemPresentationOrder
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
    case invalidEncodedChecklistName
    case invalidEncodedChecklistItemText
    case invalidEncodedChecklistItem
    case invalidEncodedChecklist
    case invalidEncodedCollection
    case invalidEncodedDraft
    case invalidEncodedCommand

    public var diagnosticCode: String {
        switch self {
        case .invalidChecklistName: "space_checklist_name_invalid"
        case .invalidChecklistItemText: "space_checklist_item_text_invalid"
        case .duplicateChecklistIdentity: "space_checklist_identity_duplicate"
        case .duplicateChecklistPresentationOrder: "space_checklist_order_duplicate"
        case .duplicateChecklistItemIdentity: "space_checklist_item_identity_duplicate"
        case .duplicateChecklistItemPresentationOrder: "space_checklist_item_order_duplicate"
        case .invalidCapturedAt: "space_checklist_revision_captured_at_invalid"
        case .draftAccountMismatch: "space_checklist_revision_account_mismatch"
        case .draftActorMismatch: "space_checklist_revision_actor_mismatch"
        case .draftContractMismatch: "space_checklist_revision_contract_mismatch"
        case .draftPayloadMismatch: "space_checklist_revision_payload_mismatch"
        case .revisionPreconditionMismatch: "space_checklist_revision_precondition_mismatch"
        case .subjectMismatch: "space_checklist_revision_subject_mismatch"
        case .fingerprintMismatch: "space_checklist_revision_fingerprint_mismatch"
        case .receiptMismatch: "space_checklist_revision_receipt_mismatch"
        case .localAcceptanceFailed: "space_checklist_revision_local_acceptance_failed"
        case .invalidEncodedChecklistName: "space_checklist_name_encoding_invalid"
        case .invalidEncodedChecklistItemText: "space_checklist_item_text_encoding_invalid"
        case .invalidEncodedChecklistItem: "space_checklist_item_encoding_invalid"
        case .invalidEncodedChecklist: "space_checklist_encoding_invalid"
        case .invalidEncodedCollection: "space_checklist_collection_encoding_invalid"
        case .invalidEncodedDraft: "space_checklist_revision_draft_encoding_invalid"
        case .invalidEncodedCommand: "space_checklist_revision_command_encoding_invalid"
        }
    }
}

public enum SpaceChecklistIDTag: Sendable {}
public typealias SpaceChecklistID = DomainEntityIdentifier<SpaceChecklistIDTag>

public enum SpaceChecklistItemIDTag: Sendable {}
public typealias SpaceChecklistItemID = DomainEntityIdentifier<SpaceChecklistItemIDTag>

public struct SpaceChecklistName: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw SpaceChecklistRevisionFailure.invalidChecklistName
        }
        self.rawValue = normalized
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            let canonical = try Self(validating: rawValue)
            guard canonical.rawValue == rawValue else {
                throw SpaceChecklistRevisionFailure.invalidEncodedChecklistName
            }
            self = canonical
        } catch {
            throw SpaceChecklistRevisionFailure.invalidEncodedChecklistName
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct SpaceChecklistItemText: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw SpaceChecklistRevisionFailure.invalidChecklistItemText
        }
        self.rawValue = normalized
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            let canonical = try Self(validating: rawValue)
            guard canonical.rawValue == rawValue else {
                throw SpaceChecklistRevisionFailure.invalidEncodedChecklistItemText
            }
            self = canonical
        } catch {
            throw SpaceChecklistRevisionFailure.invalidEncodedChecklistItemText
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct SpaceChecklistItemState: Codable, Equatable, Sendable {
    public let id: SpaceChecklistItemID
    public let text: SpaceChecklistItemText
    public let isChecked: Bool
    public let presentationOrder: UInt32

    public init(
        id: SpaceChecklistItemID,
        text: SpaceChecklistItemText,
        isChecked: Bool,
        presentationOrder: UInt32
    ) {
        self.id = id
        self.text = text
        self.isChecked = isChecked
        self.presentationOrder = presentationOrder
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                id: try container.decode(SpaceChecklistItemID.self, forKey: .id),
                text: try container.decode(SpaceChecklistItemText.self, forKey: .text),
                isChecked: try container.decode(Bool.self, forKey: .isChecked),
                presentationOrder: try container.decode(
                    UInt32.self,
                    forKey: .presentationOrder
                )
            )
        } catch let failure as SpaceChecklistRevisionFailure {
            throw failure
        } catch {
            throw SpaceChecklistRevisionFailure.invalidEncodedChecklistItem
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case isChecked
        case presentationOrder
    }
}

public struct SpaceChecklistState: Codable, Equatable, Sendable {
    public let id: SpaceChecklistID
    public let name: SpaceChecklistName
    public let presentationOrder: UInt32
    public let items: [SpaceChecklistItemState]

    public var completedItemCount: Int {
        items.lazy.filter(\.isChecked).count
    }

    public var totalItemCount: Int {
        items.count
    }

    public init(
        id: SpaceChecklistID,
        name: SpaceChecklistName,
        presentationOrder: UInt32,
        items: [SpaceChecklistItemState]
    ) throws {
        guard Self.firstDuplicate(items.map(\.id)) == nil else {
            throw SpaceChecklistRevisionFailure.duplicateChecklistItemIdentity
        }
        guard Self.firstDuplicate(items.map(\.presentationOrder)) == nil else {
            throw SpaceChecklistRevisionFailure.duplicateChecklistItemPresentationOrder
        }
        self.id = id
        self.name = name
        self.presentationOrder = presentationOrder
        self.items = items.sorted(by: Self.itemOrdering)
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let items = try container.decode(
                [SpaceChecklistItemState].self,
                forKey: .items
            )
            try self.init(
                id: container.decode(SpaceChecklistID.self, forKey: .id),
                name: container.decode(SpaceChecklistName.self, forKey: .name),
                presentationOrder: container.decode(
                    UInt32.self,
                    forKey: .presentationOrder
                ),
                items: items
            )
            guard self.items == items else {
                throw SpaceChecklistRevisionFailure.invalidEncodedChecklist
            }
        } catch let failure as SpaceChecklistRevisionFailure {
            throw failure
        } catch {
            throw SpaceChecklistRevisionFailure.invalidEncodedChecklist
        }
    }

    private static func itemOrdering(
        _ lhs: SpaceChecklistItemState,
        _ rhs: SpaceChecklistItemState
    ) -> Bool {
        if lhs.presentationOrder != rhs.presentationOrder {
            return lhs.presentationOrder < rhs.presentationOrder
        }
        return lhs.id.rawValue < rhs.id.rawValue
    }

    private static func firstDuplicate<Value: Hashable>(_ values: [Value]) -> Value? {
        var seen: Set<Value> = []
        return values.first { !seen.insert($0).inserted }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case presentationOrder
        case items
    }
}

public struct SpaceChecklistCollection: Codable, Equatable, Sendable {
    public let checklists: [SpaceChecklistState]

    public var completedItemCount: Int {
        checklists.reduce(into: 0) { $0 += $1.completedItemCount }
    }

    public var totalItemCount: Int {
        checklists.reduce(into: 0) { $0 += $1.totalItemCount }
    }

    public init(checklists: [SpaceChecklistState]) throws {
        guard Self.firstDuplicate(checklists.map(\.id)) == nil else {
            throw SpaceChecklistRevisionFailure.duplicateChecklistIdentity
        }
        guard Self.firstDuplicate(checklists.map(\.presentationOrder)) == nil else {
            throw SpaceChecklistRevisionFailure.duplicateChecklistPresentationOrder
        }
        self.checklists = checklists.sorted(by: Self.checklistOrdering)
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let checklists = try container.decode(
                [SpaceChecklistState].self,
                forKey: .checklists
            )
            try self.init(checklists: checklists)
            guard self.checklists == checklists else {
                throw SpaceChecklistRevisionFailure.invalidEncodedCollection
            }
        } catch let failure as SpaceChecklistRevisionFailure {
            throw failure
        } catch {
            throw SpaceChecklistRevisionFailure.invalidEncodedCollection
        }
    }

    private static func checklistOrdering(
        _ lhs: SpaceChecklistState,
        _ rhs: SpaceChecklistState
    ) -> Bool {
        if lhs.presentationOrder != rhs.presentationOrder {
            return lhs.presentationOrder < rhs.presentationOrder
        }
        return lhs.id.rawValue < rhs.id.rawValue
    }

    private static func firstDuplicate<Value: Hashable>(_ values: [Value]) -> Value? {
        var seen: Set<Value> = []
        return values.first { !seen.insert($0).inserted }
    }

    private enum CodingKeys: String, CodingKey {
        case checklists
    }
}

public struct SpaceChecklistRevisionDraft: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let actorPrincipalId: PrincipalID
    public let operationContractVersion: OperationContractVersion
    public let spaceId: SpaceID
    public let collection: SpaceChecklistCollection
    public let expectedRevision: ExpectedSpaceRevision
    public let capturedAt: Date

    public init(
        accountId: AccountID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        spaceId: SpaceID,
        collection: SpaceChecklistCollection,
        expectedRevision: ExpectedSpaceRevision,
        capturedAt: Date
    ) throws {
        guard capturedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw SpaceChecklistRevisionFailure.invalidCapturedAt
        }
        self.accountId = accountId
        self.actorPrincipalId = actorPrincipalId
        self.operationContractVersion = operationContractVersion
        self.spaceId = spaceId
        self.collection = collection
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
                collection: container.decode(
                    SpaceChecklistCollection.self,
                    forKey: .collection
                ),
                expectedRevision: container.decode(
                    ExpectedSpaceRevision.self,
                    forKey: .expectedRevision
                ),
                capturedAt: container.decode(Date.self, forKey: .capturedAt)
            )
        } catch let failure as SpaceChecklistRevisionFailure {
            throw failure
        } catch {
            throw SpaceChecklistRevisionFailure.invalidEncodedDraft
        }
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case actorPrincipalId
        case operationContractVersion
        case spaceId
        case collection
        case expectedRevision
        case capturedAt
    }
}

public struct ReviseSpaceChecklistsPayload: Codable, Equatable, Sendable {
    public let spaceId: SpaceID
    public let collection: SpaceChecklistCollection

    public init(spaceId: SpaceID, collection: SpaceChecklistCollection) {
        self.spaceId = spaceId
        self.collection = collection
    }
}

public struct ReviseSpaceChecklistsCommand: Codable, Equatable, Sendable {
    public let draft: SpaceChecklistRevisionDraft
    public let envelope: OperationEnvelope<ReviseSpaceChecklistsPayload>
    public let subject: LedgerEntityReference
    public let fingerprint: OperationFingerprint

    public init(operationId: OperationID, draft: SpaceChecklistRevisionDraft) throws {
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
        draft: SpaceChecklistRevisionDraft,
        envelope: OperationEnvelope<ReviseSpaceChecklistsPayload>,
        subject: LedgerEntityReference,
        fingerprint: OperationFingerprint
    ) throws {
        guard envelope.clientCreatedAt.timeIntervalSinceReferenceDate.isFinite,
              envelope.clientCreatedAt == draft.capturedAt else {
            throw SpaceChecklistRevisionFailure.invalidCapturedAt
        }
        guard envelope.accountId == draft.accountId else {
            throw SpaceChecklistRevisionFailure.draftAccountMismatch
        }
        guard envelope.actorPrincipalId == draft.actorPrincipalId else {
            throw SpaceChecklistRevisionFailure.draftActorMismatch
        }
        guard envelope.contractVersion == draft.operationContractVersion else {
            throw SpaceChecklistRevisionFailure.draftContractMismatch
        }
        guard envelope.payload == Self.makePayload(from: draft) else {
            throw SpaceChecklistRevisionFailure.draftPayloadMismatch
        }

        let expectedSubject = try Self.makeSubject(spaceId: draft.spaceId)
        let expectedPreconditions: [OperationPrecondition] = [
            .expectedRevision(
                subject: expectedSubject,
                revision: draft.expectedRevision.rawValue
            )
        ]
        guard envelope.preconditions == expectedPreconditions else {
            throw SpaceChecklistRevisionFailure.revisionPreconditionMismatch
        }
        guard subject == expectedSubject else {
            throw SpaceChecklistRevisionFailure.subjectMismatch
        }
        guard fingerprint == (try OperationFingerprint.make(for: envelope)) else {
            throw SpaceChecklistRevisionFailure.fingerprintMismatch
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
                draft: container.decode(SpaceChecklistRevisionDraft.self, forKey: .draft),
                envelope: container.decode(
                    OperationEnvelope<ReviseSpaceChecklistsPayload>.self,
                    forKey: .envelope
                ),
                subject: container.decode(LedgerEntityReference.self, forKey: .subject),
                fingerprint: container.decode(OperationFingerprint.self, forKey: .fingerprint)
            )
        } catch let failure as SpaceChecklistRevisionFailure {
            throw failure
        } catch {
            throw SpaceChecklistRevisionFailure.invalidEncodedCommand
        }
    }

    public func validate(_ receipt: OperationReceipt) throws -> OperationReceipt {
        guard receipt.operationId == envelope.operationId else {
            throw SpaceChecklistRevisionFailure.receiptMismatch
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
        from draft: SpaceChecklistRevisionDraft
    ) -> ReviseSpaceChecklistsPayload {
        ReviseSpaceChecklistsPayload(
            spaceId: draft.spaceId,
            collection: draft.collection
        )
    }

    private static func makeSubject(spaceId: SpaceID) throws -> LedgerEntityReference {
        do {
            return LedgerEntityReference(
                kind: .space,
                id: try EntityID(validating: spaceId.rawValue)
            )
        } catch {
            throw SpaceChecklistRevisionFailure.subjectMismatch
        }
    }

    private enum CodingKeys: String, CodingKey {
        case draft
        case envelope
        case subject
        case fingerprint
    }
}

public protocol SpaceChecklistRevising: Sendable {
    func reviseChecklists(
        _ command: ReviseSpaceChecklistsCommand
    ) async throws -> OperationReceipt
}
