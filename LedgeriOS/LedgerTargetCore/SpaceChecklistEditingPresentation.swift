import CryptoKit
import Foundation

public enum SpaceChecklistEditingFailure: Error, Equatable, Sendable {
    case sourceNotEditable
    case checklistNotFound
    case checklistIdentityCollision
    case checklistOrderOverflow
    case itemNotFound
    case itemIdentityCollision
    case itemOrderOverflow
    case invalidItemPermutation
    case semanticBaseMismatch
    case invalidPresentationFingerprint
    case invalidSemanticBaseFingerprint
    case invalidDraftFingerprint
    case presentationFingerprintMismatch
    case semanticBaseFingerprintMismatch
    case draftFingerprintMismatch
    case invalidEncodedPresentation
    case invalidEncodedPreparation
    case invalidEncodedDraft

    public var diagnosticCode: String {
        switch self {
        case .sourceNotEditable: "space_checklist_editing_source_not_editable"
        case .checklistNotFound: "space_checklist_editing_checklist_not_found"
        case .checklistIdentityCollision: "space_checklist_editing_checklist_identity_collision"
        case .checklistOrderOverflow: "space_checklist_editing_checklist_order_overflow"
        case .itemNotFound: "space_checklist_editing_item_not_found"
        case .itemIdentityCollision: "space_checklist_editing_item_identity_collision"
        case .itemOrderOverflow: "space_checklist_editing_item_order_overflow"
        case .invalidItemPermutation: "space_checklist_editing_item_permutation_invalid"
        case .semanticBaseMismatch: "space_checklist_editing_semantic_base_mismatch"
        case .invalidPresentationFingerprint: "space_checklist_editing_presentation_fingerprint_invalid"
        case .invalidSemanticBaseFingerprint: "space_checklist_editing_semantic_base_fingerprint_invalid"
        case .invalidDraftFingerprint: "space_checklist_editing_draft_fingerprint_invalid"
        case .presentationFingerprintMismatch: "space_checklist_editing_presentation_fingerprint_mismatch"
        case .semanticBaseFingerprintMismatch: "space_checklist_editing_semantic_base_fingerprint_mismatch"
        case .draftFingerprintMismatch: "space_checklist_editing_draft_fingerprint_mismatch"
        case .invalidEncodedPresentation: "space_checklist_editing_presentation_encoding_invalid"
        case .invalidEncodedPreparation: "space_checklist_editing_preparation_encoding_invalid"
        case .invalidEncodedDraft: "space_checklist_editing_draft_encoding_invalid"
        }
    }
}

public struct SpaceChecklistEditingPresentationFingerprint: Codable, Equatable, Hashable, Sendable {
    public let sha256: String

    public init(validating sha256: String) throws {
        guard SpaceChecklistEditingDigest.isCanonicalSHA256(sha256) else {
            throw SpaceChecklistEditingFailure.invalidPresentationFingerprint
        }
        self.sha256 = sha256
    }

    public init(from decoder: Decoder) throws {
        do {
            try self.init(validating: decoder.singleValueContainer().decode(String.self))
        } catch let failure as SpaceChecklistEditingFailure {
            throw failure
        } catch {
            throw SpaceChecklistEditingFailure.invalidPresentationFingerprint
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(sha256)
    }
}

public struct SpaceChecklistEditingSemanticBaseFingerprint: Codable, Equatable, Hashable, Sendable {
    public let sha256: String

    public init(validating sha256: String) throws {
        guard SpaceChecklistEditingDigest.isCanonicalSHA256(sha256) else {
            throw SpaceChecklistEditingFailure.invalidSemanticBaseFingerprint
        }
        self.sha256 = sha256
    }

    public init(from decoder: Decoder) throws {
        do {
            try self.init(validating: decoder.singleValueContainer().decode(String.self))
        } catch let failure as SpaceChecklistEditingFailure {
            throw failure
        } catch {
            throw SpaceChecklistEditingFailure.invalidSemanticBaseFingerprint
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(sha256)
    }
}

public struct SpaceChecklistEditingDraftFingerprint: Codable, Equatable, Hashable, Sendable {
    public let sha256: String

    public init(validating sha256: String) throws {
        guard SpaceChecklistEditingDigest.isCanonicalSHA256(sha256) else {
            throw SpaceChecklistEditingFailure.invalidDraftFingerprint
        }
        self.sha256 = sha256
    }

    public init(from decoder: Decoder) throws {
        do {
            try self.init(validating: decoder.singleValueContainer().decode(String.self))
        } catch let failure as SpaceChecklistEditingFailure {
            throw failure
        } catch {
            throw SpaceChecklistEditingFailure.invalidDraftFingerprint
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(sha256)
    }
}

public enum SpaceChecklistEditingPresentationState: Codable, Equatable, Sendable {
    case editableCurrent
    case editableStale
    case waiting(ListReadiness)
    case incomplete(ListReadiness)
    case authoritativeAbsence
    case unavailable
    case requiredUpdate

    fileprivate var isEditable: Bool {
        self == .editableCurrent || self == .editableStale
    }

    public init(from decoder: Decoder) throws {
        do {
            let unbounded = try decoder.container(
                keyedBy: SpaceChecklistEditingCoding.AnyCodingKey.self
            )
            let keys = Set(unbounded.allKeys.map(\.stringValue))
            guard keys.count == 1, let kind = keys.first,
                  let key = SpaceChecklistEditingCoding.AnyCodingKey(stringValue: kind) else {
                throw SpaceChecklistEditingFailure.invalidEncodedPresentation
            }
            switch kind {
            case "editableCurrent", "editableStale", "authoritativeAbsence", "unavailable", "requiredUpdate":
                guard try unbounded.decode(Bool.self, forKey: key) else {
                    throw SpaceChecklistEditingFailure.invalidEncodedPresentation
                }
                switch kind {
                case "editableCurrent": self = .editableCurrent
                case "editableStale": self = .editableStale
                case "authoritativeAbsence": self = .authoritativeAbsence
                case "unavailable": self = .unavailable
                default: self = .requiredUpdate
                }
            case "waiting", "incomplete":
                let readiness = try unbounded.decode(ListReadiness.self, forKey: key)
                self = kind == "waiting" ? .waiting(readiness) : .incomplete(readiness)
            default:
                throw SpaceChecklistEditingFailure.invalidEncodedPresentation
            }
        } catch let failure as SpaceChecklistEditingFailure {
            throw failure
        } catch {
            throw SpaceChecklistEditingFailure.invalidEncodedPresentation
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: SpaceChecklistEditingCoding.AnyCodingKey.self)
        switch self {
        case .editableCurrent:
            try container.encode(true, forKey: .init(stringValue: "editableCurrent")!)
        case .editableStale:
            try container.encode(true, forKey: .init(stringValue: "editableStale")!)
        case .waiting(let readiness):
            try container.encode(readiness, forKey: .init(stringValue: "waiting")!)
        case .incomplete(let readiness):
            try container.encode(readiness, forKey: .init(stringValue: "incomplete")!)
        case .authoritativeAbsence:
            try container.encode(true, forKey: .init(stringValue: "authoritativeAbsence")!)
        case .unavailable:
            try container.encode(true, forKey: .init(stringValue: "unavailable")!)
        case .requiredUpdate:
            try container.encode(true, forKey: .init(stringValue: "requiredUpdate")!)
        }
    }
}

public struct SpaceChecklistEditingPresentation: Codable, Equatable, Sendable {
    public let update: SpaceCoreDetailsUpdate
    public let state: SpaceChecklistEditingPresentationState
    public let evidenceFingerprint: SpaceChecklistEditingPresentationFingerprint

    public init(projecting update: SpaceCoreDetailsUpdate) throws {
        let state = Self.projectState(update.state)
        try self.init(
            update: update,
            state: state,
            evidenceFingerprint: Self.makeFingerprint(update: update, state: state)
        )
    }

    private init(
        update: SpaceCoreDetailsUpdate,
        state: SpaceChecklistEditingPresentationState,
        evidenceFingerprint: SpaceChecklistEditingPresentationFingerprint
    ) throws {
        guard state == Self.projectState(update.state),
              evidenceFingerprint == (try Self.makeFingerprint(update: update, state: state)) else {
            throw SpaceChecklistEditingFailure.presentationFingerprintMismatch
        }
        self.update = update
        self.state = state
        self.evidenceFingerprint = evidenceFingerprint
    }

    public func prepare() throws -> SpaceChecklistEditingPreparation {
        guard state.isEditable, let row = Self.admittedRow(from: update.state) else {
            throw SpaceChecklistEditingFailure.sourceNotEditable
        }
        return try SpaceChecklistEditingPreparation(presentation: self, row: row)
    }

    public init(from decoder: Decoder) throws {
        do {
            try SpaceChecklistEditingCoding.requireExactKeys(
                decoder,
                allowed: CodingKeys.allCases.map(\.rawValue),
                failure: .invalidEncodedPresentation
            )
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                update: container.decode(StrictSpaceCoreDetailsUpdate.self, forKey: .update).value,
                state: container.decode(SpaceChecklistEditingPresentationState.self, forKey: .state),
                evidenceFingerprint: container.decode(
                    SpaceChecklistEditingPresentationFingerprint.self,
                    forKey: .evidenceFingerprint
                )
            )
        } catch let failure as SpaceChecklistEditingFailure {
            throw failure
        } catch {
            throw SpaceChecklistEditingFailure.invalidEncodedPresentation
        }
    }

    fileprivate static func projectState(
        _ updateState: SpaceCoreDetailsUpdateState
    ) -> SpaceChecklistEditingPresentationState {
        switch updateState {
        case .waiting(let readiness):
            .waiting(readiness)
        case .snapshot(let snapshot):
            if snapshot.local.quality == .ready,
               snapshot.local.isCompleteForQuery,
               snapshot.local.rows.count == 1 {
                .editableCurrent
            } else if snapshot.isAuthoritativeAbsence {
                .authoritativeAbsence
            } else {
                .incomplete(snapshot.local.quality.readiness)
            }
        case .failed(let failure, let cached):
            switch failure {
            case .unavailable:
                .unavailable
            case .requiredUpdate:
                .requiredUpdate
            case .retryable:
                if let cached,
                   cached.local.quality == .ready,
                   cached.local.isCompleteForQuery,
                   cached.local.rows.count == 1 {
                    .editableStale
                } else {
                    .incomplete(cached?.local.quality.readiness ?? .loading)
                }
            }
        }
    }

    fileprivate static func admittedRow(
        from state: SpaceCoreDetailsUpdateState
    ) -> SpaceCoreDetailsSnapshot? {
        switch state {
        case .snapshot(let snapshot): snapshot.row
        case .failed(.retryable, let cached): cached?.row
        case .waiting, .failed: nil
        }
    }

    fileprivate static func semanticFingerprint(
        update: SpaceCoreDetailsUpdate
    ) throws -> SpaceChecklistEditingSemanticBaseFingerprint {
        let presentation = try Self(projecting: update)
        guard presentation.state.isEditable,
              let row = admittedRow(from: update.state) else {
            throw SpaceChecklistEditingFailure.sourceNotEditable
        }
        return try SpaceChecklistEditingSemanticBaseFingerprint(
            validating: SpaceChecklistEditingDigest.sha256(
                try OperationContractCodec.encode(SemanticBase(
                    contractVersion: "space-checklist-editing-semantic-base-v1",
                    accountId: update.request.accountId,
                    spaceId: update.request.spaceId,
                    scope: row.scope,
                    lifecycle: row.lifecycle,
                    revision: row.revision,
                    checklists: row.checklists
                ))
            )
        )
    }

    private static func makeFingerprint(
        update: SpaceCoreDetailsUpdate,
        state: SpaceChecklistEditingPresentationState
    ) throws -> SpaceChecklistEditingPresentationFingerprint {
        try SpaceChecklistEditingPresentationFingerprint(
            validating: SpaceChecklistEditingDigest.sha256(
                try OperationContractCodec.encode(PresentationBasis(
                    contractVersion: "space-checklist-editing-presentation-v1",
                    update: update,
                    state: state
                ))
            )
        )
    }

    private struct PresentationBasis: Codable {
        let contractVersion: String
        let update: SpaceCoreDetailsUpdate
        let state: SpaceChecklistEditingPresentationState
    }

    private struct SemanticBase: Codable {
        let contractVersion: String
        let accountId: AccountID
        let spaceId: SpaceID
        let scope: SpaceCreationScope
        let lifecycle: DirectoryLifecycleState
        let revision: UInt64
        let checklists: SpaceChecklistCollection
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case update
        case state
        case evidenceFingerprint
    }
}

public struct SpaceChecklistEditingPreparation: Codable, Equatable, Sendable {
    public let presentation: SpaceChecklistEditingPresentation
    public let semanticBaseFingerprint: SpaceChecklistEditingSemanticBaseFingerprint
    public let draft: SpaceChecklistEditingDraft

    fileprivate init(
        presentation: SpaceChecklistEditingPresentation,
        row: SpaceCoreDetailsSnapshot
    ) throws {
        let semantic = try SpaceChecklistEditingPresentation.semanticFingerprint(
            update: presentation.update
        )
        try self.init(
            presentation: presentation,
            semanticBaseFingerprint: semantic,
            draft: SpaceChecklistEditingDraft(
                accountId: row.accountId,
                spaceId: row.id,
                semanticBaseFingerprint: semantic,
                checklists: row.checklists.checklists.map(SpaceChecklistEditingChecklist.init)
            )
        )
    }

    private init(
        presentation: SpaceChecklistEditingPresentation,
        semanticBaseFingerprint: SpaceChecklistEditingSemanticBaseFingerprint,
        draft: SpaceChecklistEditingDraft
    ) throws {
        guard presentation.state.isEditable else {
            throw SpaceChecklistEditingFailure.sourceNotEditable
        }
        let expected = try SpaceChecklistEditingPresentation.semanticFingerprint(
            update: presentation.update
        )
        guard semanticBaseFingerprint == expected else {
            throw SpaceChecklistEditingFailure.semanticBaseFingerprintMismatch
        }
        guard draft.accountId == presentation.update.request.accountId,
              draft.spaceId == presentation.update.request.spaceId,
              draft.semanticBaseFingerprint == expected,
              let row = SpaceChecklistEditingPresentation.admittedRow(from: presentation.update.state),
              draft.checklists == row.checklists.checklists.map(SpaceChecklistEditingChecklist.init) else {
            throw SpaceChecklistEditingFailure.semanticBaseMismatch
        }
        self.presentation = presentation
        self.semanticBaseFingerprint = semanticBaseFingerprint
        self.draft = draft
    }

    public init(from decoder: Decoder) throws {
        do {
            try SpaceChecklistEditingCoding.requireExactKeys(
                decoder,
                allowed: CodingKeys.allCases.map(\.rawValue),
                failure: .invalidEncodedPreparation
            )
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                presentation: container.decode(
                    SpaceChecklistEditingPresentation.self,
                    forKey: .presentation
                ),
                semanticBaseFingerprint: container.decode(
                    SpaceChecklistEditingSemanticBaseFingerprint.self,
                    forKey: .semanticBaseFingerprint
                ),
                draft: container.decode(SpaceChecklistEditingDraft.self, forKey: .draft)
            )
        } catch let failure as SpaceChecklistEditingFailure {
            throw failure
        } catch {
            throw SpaceChecklistEditingFailure.invalidEncodedPreparation
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case presentation
        case semanticBaseFingerprint
        case draft
    }
}

public struct SpaceChecklistEditingItem: Codable, Equatable, Sendable {
    public let id: SpaceChecklistItemID
    public let text: String
    public let isChecked: Bool
    public let presentationOrder: UInt32

    public init(
        id: SpaceChecklistItemID,
        text: String,
        isChecked: Bool,
        presentationOrder: UInt32
    ) {
        self.id = id
        self.text = text
        self.isChecked = isChecked
        self.presentationOrder = presentationOrder
    }

    fileprivate init(_ source: SpaceChecklistItemState) {
        self.init(
            id: source.id,
            text: source.text.rawValue,
            isChecked: source.isChecked,
            presentationOrder: source.presentationOrder
        )
    }

    public init(from decoder: Decoder) throws {
        do {
            try SpaceChecklistEditingCoding.requireExactKeys(
                decoder,
                allowed: CodingKeys.allCases.map(\.rawValue),
                failure: .invalidEncodedDraft
            )
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                id: try container.decode(SpaceChecklistItemID.self, forKey: .id),
                text: try container.decode(String.self, forKey: .text),
                isChecked: try container.decode(Bool.self, forKey: .isChecked),
                presentationOrder: try container.decode(UInt32.self, forKey: .presentationOrder)
            )
        } catch let failure as SpaceChecklistEditingFailure {
            throw failure
        } catch {
            throw SpaceChecklistEditingFailure.invalidEncodedDraft
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case text
        case isChecked
        case presentationOrder
    }
}

public struct SpaceChecklistEditingChecklist: Codable, Equatable, Sendable {
    public let id: SpaceChecklistID
    public let name: String
    public let presentationOrder: UInt32
    public let items: [SpaceChecklistEditingItem]

    public init(
        id: SpaceChecklistID,
        name: String,
        presentationOrder: UInt32,
        items: [SpaceChecklistEditingItem]
    ) {
        self.id = id
        self.name = name
        self.presentationOrder = presentationOrder
        self.items = items
    }

    fileprivate init(_ source: SpaceChecklistState) {
        self.init(
            id: source.id,
            name: source.name.rawValue,
            presentationOrder: source.presentationOrder,
            items: source.items.map(SpaceChecklistEditingItem.init)
        )
    }

    public init(from decoder: Decoder) throws {
        do {
            try SpaceChecklistEditingCoding.requireExactKeys(
                decoder,
                allowed: CodingKeys.allCases.map(\.rawValue),
                failure: .invalidEncodedDraft
            )
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                id: try container.decode(SpaceChecklistID.self, forKey: .id),
                name: try container.decode(String.self, forKey: .name),
                presentationOrder: try container.decode(UInt32.self, forKey: .presentationOrder),
                items: try container.decode([SpaceChecklistEditingItem].self, forKey: .items)
            )
        } catch let failure as SpaceChecklistEditingFailure {
            throw failure
        } catch {
            throw SpaceChecklistEditingFailure.invalidEncodedDraft
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case name
        case presentationOrder
        case items
    }
}

public struct SpaceChecklistEditingDraft: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let spaceId: SpaceID
    public let semanticBaseFingerprint: SpaceChecklistEditingSemanticBaseFingerprint
    public let checklists: [SpaceChecklistEditingChecklist]
    public let draftFingerprint: SpaceChecklistEditingDraftFingerprint

    fileprivate init(
        accountId: AccountID,
        spaceId: SpaceID,
        semanticBaseFingerprint: SpaceChecklistEditingSemanticBaseFingerprint,
        checklists: [SpaceChecklistEditingChecklist]
    ) throws {
        try Self.validateRepresentedIdentities(checklists)
        self.accountId = accountId
        self.spaceId = spaceId
        self.semanticBaseFingerprint = semanticBaseFingerprint
        self.checklists = checklists
        draftFingerprint = try Self.makeFingerprint(
            accountId: accountId,
            spaceId: spaceId,
            semanticBaseFingerprint: semanticBaseFingerprint,
            checklists: checklists
        )
    }

    private init(
        accountId: AccountID,
        spaceId: SpaceID,
        semanticBaseFingerprint: SpaceChecklistEditingSemanticBaseFingerprint,
        checklists: [SpaceChecklistEditingChecklist],
        draftFingerprint: SpaceChecklistEditingDraftFingerprint
    ) throws {
        try Self.validateRepresentedIdentities(checklists)
        guard draftFingerprint == (try Self.makeFingerprint(
            accountId: accountId,
            spaceId: spaceId,
            semanticBaseFingerprint: semanticBaseFingerprint,
            checklists: checklists
        )) else {
            throw SpaceChecklistEditingFailure.draftFingerprintMismatch
        }
        self.accountId = accountId
        self.spaceId = spaceId
        self.semanticBaseFingerprint = semanticBaseFingerprint
        self.checklists = checklists
        self.draftFingerprint = draftFingerprint
    }

    public func appendingChecklist(id: SpaceChecklistID, name: String) throws -> Self {
        guard !checklists.contains(where: { $0.id == id }) else {
            throw SpaceChecklistEditingFailure.checklistIdentityCollision
        }
        let order = try Self.appendOrder(
            checklists.map(\.presentationOrder),
            overflow: .checklistOrderOverflow
        )
        return try replacing(checklists + [SpaceChecklistEditingChecklist(
            id: id,
            name: name,
            presentationOrder: order,
            items: []
        )])
    }

    public func removingChecklist(id: SpaceChecklistID) throws -> Self {
        guard checklists.contains(where: { $0.id == id }) else {
            throw SpaceChecklistEditingFailure.checklistNotFound
        }
        return try replacing(checklists.filter { $0.id != id })
    }

    public func renamingChecklist(id: SpaceChecklistID, name: String) throws -> Self {
        try mapChecklist(id: id) {
            SpaceChecklistEditingChecklist(
                id: $0.id,
                name: name,
                presentationOrder: $0.presentationOrder,
                items: $0.items
            )
        }
    }

    public func clearingChecklists() throws -> Self {
        try replacing([])
    }

    public func appendingItem(
        checklistId: SpaceChecklistID,
        id: SpaceChecklistItemID,
        text: String,
        isChecked: Bool = false
    ) throws -> Self {
        try mapChecklist(id: checklistId) { checklist in
            guard !checklist.items.contains(where: { $0.id == id }) else {
                throw SpaceChecklistEditingFailure.itemIdentityCollision
            }
            let order = try Self.appendOrder(
                checklist.items.map(\.presentationOrder),
                overflow: .itemOrderOverflow
            )
            return SpaceChecklistEditingChecklist(
                id: checklist.id,
                name: checklist.name,
                presentationOrder: checklist.presentationOrder,
                items: checklist.items + [SpaceChecklistEditingItem(
                    id: id,
                    text: text,
                    isChecked: isChecked,
                    presentationOrder: order
                )]
            )
        }
    }

    public func removingItem(
        checklistId: SpaceChecklistID,
        itemId: SpaceChecklistItemID
    ) throws -> Self {
        try mapItem(checklistId: checklistId, itemId: itemId) { _ in nil }
    }

    public func editingItemText(
        checklistId: SpaceChecklistID,
        itemId: SpaceChecklistItemID,
        text: String
    ) throws -> Self {
        try mapItem(checklistId: checklistId, itemId: itemId) {
            SpaceChecklistEditingItem(
                id: $0.id,
                text: text,
                isChecked: $0.isChecked,
                presentationOrder: $0.presentationOrder
            )
        }
    }

    public func settingItemChecked(
        checklistId: SpaceChecklistID,
        itemId: SpaceChecklistItemID,
        isChecked: Bool
    ) throws -> Self {
        try mapItem(checklistId: checklistId, itemId: itemId) {
            SpaceChecklistEditingItem(
                id: $0.id,
                text: $0.text,
                isChecked: isChecked,
                presentationOrder: $0.presentationOrder
            )
        }
    }

    public func reorderingItems(
        checklistId: SpaceChecklistID,
        itemIds: [SpaceChecklistItemID]
    ) throws -> Self {
        try mapChecklist(id: checklistId) { checklist in
            let existingIDs = checklist.items.map(\.id)
            guard itemIds.count == existingIDs.count,
                  Set(itemIds).count == itemIds.count,
                  Set(itemIds) == Set(existingIDs) else {
                throw SpaceChecklistEditingFailure.invalidItemPermutation
            }
            let tokens = checklist.items.map(\.presentationOrder).sorted()
            let itemByID = Dictionary(uniqueKeysWithValues: checklist.items.map { ($0.id, $0) })
            let reordered = itemIds.enumerated().map { index, id in
                let item = itemByID[id]!
                return SpaceChecklistEditingItem(
                    id: item.id,
                    text: item.text,
                    isChecked: item.isChecked,
                    presentationOrder: tokens[index]
                )
            }
            return SpaceChecklistEditingChecklist(
                id: checklist.id,
                name: checklist.name,
                presentationOrder: checklist.presentationOrder,
                items: reordered
            )
        }
    }

    public func collection() throws -> SpaceChecklistCollection {
        try SpaceChecklistCollection(checklists: checklists.map { checklist in
            try SpaceChecklistState(
                id: checklist.id,
                name: SpaceChecklistName(validating: checklist.name),
                presentationOrder: checklist.presentationOrder,
                items: checklist.items.map { item in
                    SpaceChecklistItemState(
                        id: item.id,
                        text: try SpaceChecklistItemText(validating: item.text),
                        isChecked: item.isChecked,
                        presentationOrder: item.presentationOrder
                    )
                }
            )
        })
    }

    public func command(
        validating currentUpdate: SpaceCoreDetailsUpdate,
        operationId: OperationID,
        actorPrincipalId: PrincipalID,
        operationContractVersion: OperationContractVersion,
        capturedAt: Date
    ) throws -> ReviseSpaceChecklistsCommand {
        try validateFingerprint()
        let currentPresentation = try SpaceChecklistEditingPresentation(projecting: currentUpdate)
        guard currentPresentation.state.isEditable else {
            throw SpaceChecklistEditingFailure.sourceNotEditable
        }
        let currentSemantic = try SpaceChecklistEditingPresentation.semanticFingerprint(
            update: currentUpdate
        )
        guard accountId == currentUpdate.request.accountId,
              spaceId == currentUpdate.request.spaceId,
              semanticBaseFingerprint == currentSemantic,
              let currentRow = SpaceChecklistEditingPresentation.admittedRow(from: currentUpdate.state),
              currentRow.accountId == accountId,
              currentRow.id == spaceId else {
            throw SpaceChecklistEditingFailure.semanticBaseMismatch
        }
        return try ReviseSpaceChecklistsCommand(
            operationId: operationId,
            draft: SpaceChecklistRevisionDraft(
                accountId: accountId,
                actorPrincipalId: actorPrincipalId,
                operationContractVersion: operationContractVersion,
                spaceId: spaceId,
                collection: collection(),
                expectedRevision: ExpectedSpaceRevision(currentRow.revision),
                capturedAt: capturedAt
            )
        )
    }

    public init(from decoder: Decoder) throws {
        do {
            try SpaceChecklistEditingCoding.requireExactKeys(
                decoder,
                allowed: CodingKeys.allCases.map(\.rawValue),
                failure: .invalidEncodedDraft
            )
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                accountId: container.decode(AccountID.self, forKey: .accountId),
                spaceId: container.decode(SpaceID.self, forKey: .spaceId),
                semanticBaseFingerprint: container.decode(
                    SpaceChecklistEditingSemanticBaseFingerprint.self,
                    forKey: .semanticBaseFingerprint
                ),
                checklists: container.decode([SpaceChecklistEditingChecklist].self, forKey: .checklists),
                draftFingerprint: container.decode(
                    SpaceChecklistEditingDraftFingerprint.self,
                    forKey: .draftFingerprint
                )
            )
        } catch let failure as SpaceChecklistEditingFailure {
            throw failure
        } catch {
            throw SpaceChecklistEditingFailure.invalidEncodedDraft
        }
    }

    private func replacing(_ checklists: [SpaceChecklistEditingChecklist]) throws -> Self {
        try Self(
            accountId: accountId,
            spaceId: spaceId,
            semanticBaseFingerprint: semanticBaseFingerprint,
            checklists: checklists
        )
    }

    private func mapChecklist(
        id: SpaceChecklistID,
        transform: (SpaceChecklistEditingChecklist) throws -> SpaceChecklistEditingChecklist
    ) throws -> Self {
        guard let index = checklists.firstIndex(where: { $0.id == id }) else {
            throw SpaceChecklistEditingFailure.checklistNotFound
        }
        var copy = checklists
        copy[index] = try transform(copy[index])
        return try replacing(copy)
    }

    private func mapItem(
        checklistId: SpaceChecklistID,
        itemId: SpaceChecklistItemID,
        transform: (SpaceChecklistEditingItem) throws -> SpaceChecklistEditingItem?
    ) throws -> Self {
        try mapChecklist(id: checklistId) { checklist in
            guard let index = checklist.items.firstIndex(where: { $0.id == itemId }) else {
                throw SpaceChecklistEditingFailure.itemNotFound
            }
            var items = checklist.items
            if let replacement = try transform(items[index]) {
                items[index] = replacement
            } else {
                items.remove(at: index)
            }
            return SpaceChecklistEditingChecklist(
                id: checklist.id,
                name: checklist.name,
                presentationOrder: checklist.presentationOrder,
                items: items
            )
        }
    }

    private func validateFingerprint() throws {
        guard draftFingerprint == (try Self.makeFingerprint(
            accountId: accountId,
            spaceId: spaceId,
            semanticBaseFingerprint: semanticBaseFingerprint,
            checklists: checklists
        )) else {
            throw SpaceChecklistEditingFailure.draftFingerprintMismatch
        }
    }

    private static func validateRepresentedIdentities(
        _ checklists: [SpaceChecklistEditingChecklist]
    ) throws {
        guard Set(checklists.map(\.id)).count == checklists.count else {
            throw SpaceChecklistEditingFailure.checklistIdentityCollision
        }
        for checklist in checklists {
            guard Set(checklist.items.map(\.id)).count == checklist.items.count else {
                throw SpaceChecklistEditingFailure.itemIdentityCollision
            }
        }
    }

    private static func appendOrder(
        _ orders: [UInt32],
        overflow: SpaceChecklistEditingFailure
    ) throws -> UInt32 {
        guard let maximum = orders.max() else { return 0 }
        guard maximum < .max else { throw overflow }
        return maximum + 1
    }

    private static func makeFingerprint(
        accountId: AccountID,
        spaceId: SpaceID,
        semanticBaseFingerprint: SpaceChecklistEditingSemanticBaseFingerprint,
        checklists: [SpaceChecklistEditingChecklist]
    ) throws -> SpaceChecklistEditingDraftFingerprint {
        try SpaceChecklistEditingDraftFingerprint(
            validating: SpaceChecklistEditingDigest.sha256(
                try OperationContractCodec.encode(DraftBasis(
                    contractVersion: "space-checklist-editing-draft-v1",
                    accountId: accountId,
                    spaceId: spaceId,
                    semanticBaseFingerprint: semanticBaseFingerprint,
                    checklists: checklists
                ))
            )
        )
    }

    private struct DraftBasis: Codable {
        let contractVersion: String
        let accountId: AccountID
        let spaceId: SpaceID
        let semanticBaseFingerprint: SpaceChecklistEditingSemanticBaseFingerprint
        let checklists: [SpaceChecklistEditingChecklist]
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case accountId
        case spaceId
        case semanticBaseFingerprint
        case checklists
        case draftFingerprint
    }
}

private struct StrictSpaceCoreDetailsUpdate: Decodable {
    let value: SpaceCoreDetailsUpdate

    init(from decoder: Decoder) throws {
        try SpaceChecklistEditingCoding.requireExactKeys(
            decoder,
            allowed: ["request", "state"],
            failure: .invalidEncodedPresentation
        )
        let container = try decoder.container(keyedBy: Keys.self)
        value = try SpaceCoreDetailsUpdate(
            request: container.decode(StrictSpaceCoreDetailsRequest.self, forKey: .request).value,
            state: container.decode(StrictSpaceCoreDetailsUpdateState.self, forKey: .state).value
        )
    }

    private enum Keys: String, CodingKey { case request, state }
}

private struct StrictSpaceCoreDetailsRequest: Decodable {
    let value: SpaceCoreDetailsRequest

    init(from decoder: Decoder) throws {
        try SpaceChecklistEditingCoding.requireExactKeys(
            decoder,
            allowed: ["accountId", "spaceId", "queryFingerprint"],
            failure: .invalidEncodedPresentation
        )
        value = try SpaceCoreDetailsRequest(from: decoder)
    }
}

private struct StrictSpaceCoreDetailsUpdateState: Decodable {
    let value: SpaceCoreDetailsUpdateState

    init(from decoder: Decoder) throws {
        let unbounded = try decoder.container(keyedBy: SpaceChecklistEditingCoding.AnyCodingKey.self)
        let keys = Set(unbounded.allKeys.map(\.stringValue))
        guard keys.count == 1, let kind = keys.first,
              let dynamicKey = SpaceChecklistEditingCoding.AnyCodingKey(stringValue: kind) else {
            throw SpaceChecklistEditingFailure.invalidEncodedPresentation
        }
        let nested = try unbounded.superDecoder(forKey: dynamicKey)
        switch kind {
        case "waiting":
            try SpaceChecklistEditingCoding.requireExactKeys(
                nested,
                allowed: ["_0"],
                failure: .invalidEncodedPresentation
            )
            let container = try nested.container(keyedBy: PositionalKey.self)
            value = .waiting(try container.decode(ListReadiness.self, forKey: .value))
        case "snapshot":
            try SpaceChecklistEditingCoding.requireExactKeys(
                nested,
                allowed: ["_0"],
                failure: .invalidEncodedPresentation
            )
            let container = try nested.container(keyedBy: PositionalKey.self)
            value = .snapshot(
                try container.decode(StrictSpaceCoreDetailsLocalSnapshot.self, forKey: .value).value
            )
        case "failed":
            let failureShape = try nested.container(
                keyedBy: SpaceChecklistEditingCoding.AnyCodingKey.self
            )
            let failureKeys = Set(failureShape.allKeys.map(\.stringValue))
            guard failureKeys == ["failure"] || failureKeys == ["failure", "cached"] else {
                throw SpaceChecklistEditingFailure.invalidEncodedPresentation
            }
            let container = try nested.container(keyedBy: FailureKeys.self)
            let cached: SpaceCoreDetailsLocalSnapshot?
            if failureKeys.contains("cached") {
                guard try !container.decodeNil(forKey: .cached) else {
                    throw SpaceChecklistEditingFailure.invalidEncodedPresentation
                }
                cached = try container.decode(
                    StrictSpaceCoreDetailsLocalSnapshot.self,
                    forKey: .cached
                ).value
            } else {
                cached = nil
            }
            value = .failed(
                failure: try container.decode(ListFailureState.self, forKey: .failure),
                cached: cached
            )
        default:
            throw SpaceChecklistEditingFailure.invalidEncodedPresentation
        }
    }

    private enum PositionalKey: String, CodingKey { case value = "_0" }
    private enum FailureKeys: String, CodingKey { case failure, cached }
}

private struct StrictSpaceCoreDetailsLocalSnapshot: Decodable {
    let value: SpaceCoreDetailsLocalSnapshot

    init(from decoder: Decoder) throws {
        try SpaceChecklistEditingCoding.requireExactKeys(
            decoder,
            allowed: ["request", "local"],
            failure: .invalidEncodedPresentation
        )
        let container = try decoder.container(keyedBy: Keys.self)
        value = try SpaceCoreDetailsLocalSnapshot(
            request: container.decode(StrictSpaceCoreDetailsRequest.self, forKey: .request).value,
            local: container.decode(StrictSpaceCoreLocalList.self, forKey: .local).value
        )
    }

    private enum Keys: String, CodingKey { case request, local }
}

private struct StrictSpaceCoreLocalList: Decodable {
    let value: ListLocalSnapshot<SpaceCoreDetailsSnapshot>

    init(from decoder: Decoder) throws {
        try SpaceChecklistEditingCoding.requireExactKeys(
            decoder,
            allowed: [
                "queryFingerprint", "rows", "visibleRowCountBeforeFiltering",
                "isCompleteForQuery", "quality", "localDataVersion", "asOf"
            ],
            failure: .invalidEncodedPresentation
        )
        let container = try decoder.container(keyedBy: Keys.self)
        value = try ListLocalSnapshot(
            queryFingerprint: container.decode(ListQueryFingerprint.self, forKey: .queryFingerprint),
            rows: container.decode([StrictSpaceCoreDetailsRow].self, forKey: .rows).map(\.value),
            visibleRowCountBeforeFiltering: container.decode(
                Int.self,
                forKey: .visibleRowCountBeforeFiltering
            ),
            isCompleteForQuery: container.decode(Bool.self, forKey: .isCompleteForQuery),
            quality: container.decode(ListSnapshotQuality.self, forKey: .quality),
            localDataVersion: container.decode(LocalDataVersion.self, forKey: .localDataVersion),
            asOf: container.decode(Date.self, forKey: .asOf)
        )
    }

    private enum Keys: String, CodingKey {
        case queryFingerprint
        case rows
        case visibleRowCountBeforeFiltering
        case isCompleteForQuery
        case quality
        case localDataVersion
        case asOf
    }
}

private struct StrictSpaceCoreDetailsRow: Decodable {
    let value: SpaceCoreDetailsSnapshot

    init(from decoder: Decoder) throws {
        try SpaceChecklistEditingCoding.requireExactKeys(
            decoder,
            allowed: [
                "id", "accountId", "scope", "displayName", "notes", "lifecycle",
                "revision", "createdAt", "updatedAt", "checklists"
            ],
            failure: .invalidEncodedPresentation
        )
        let container = try decoder.container(keyedBy: Keys.self)
        value = try SpaceCoreDetailsSnapshot(
            id: container.decode(SpaceID.self, forKey: .id),
            accountId: container.decode(AccountID.self, forKey: .accountId),
            scope: container.decode(StrictSpaceCreationScope.self, forKey: .scope).value,
            displayName: container.decode(SpaceDisplayName.self, forKey: .displayName),
            notes: container.decode(StrictSpaceCreationNotes.self, forKey: .notes).value,
            lifecycle: container.decode(DirectoryLifecycleState.self, forKey: .lifecycle),
            revision: container.decode(UInt64.self, forKey: .revision),
            createdAt: container.decode(Date.self, forKey: .createdAt),
            updatedAt: container.decode(Date.self, forKey: .updatedAt),
            checklists: container.decode(StrictChecklistCollection.self, forKey: .checklists).value
        )
    }

    private enum Keys: String, CodingKey {
        case id
        case accountId
        case scope
        case displayName
        case notes
        case lifecycle
        case revision
        case createdAt
        case updatedAt
        case checklists
    }
}

private struct StrictSpaceCreationScope: Decodable {
    let value: SpaceCreationScope

    init(from decoder: Decoder) throws {
        let unbounded = try decoder.container(keyedBy: SpaceChecklistEditingCoding.AnyCodingKey.self)
        let keys = Set(unbounded.allKeys.map(\.stringValue))
        let container = try decoder.container(keyedBy: Keys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "project":
            guard keys == ["kind", "projectId"] else {
                throw SpaceChecklistEditingFailure.invalidEncodedPresentation
            }
            value = .project(try container.decode(ProjectID.self, forKey: .projectId))
        case "businessInventory":
            guard keys == ["kind"] else {
                throw SpaceChecklistEditingFailure.invalidEncodedPresentation
            }
            value = .businessInventory
        default:
            throw SpaceChecklistEditingFailure.invalidEncodedPresentation
        }
    }

    private enum Keys: String, CodingKey { case kind, projectId }
}

private struct StrictSpaceCreationNotes: Decodable {
    let value: SpaceCreationNotes

    init(from decoder: Decoder) throws {
        try SpaceChecklistEditingCoding.requireExactKeys(
            decoder,
            allowed: ["value"],
            failure: .invalidEncodedPresentation
        )
        value = try SpaceCreationNotes(from: decoder)
    }
}

private struct StrictChecklistCollection: Decodable {
    let value: SpaceChecklistCollection

    init(from decoder: Decoder) throws {
        try SpaceChecklistEditingCoding.requireExactKeys(
            decoder,
            allowed: ["checklists"],
            failure: .invalidEncodedPresentation
        )
        let container = try decoder.container(keyedBy: Keys.self)
        let checklists = try container.decode([StrictChecklist].self, forKey: .checklists).map(\.value)
        let canonical = try SpaceChecklistCollection(checklists: checklists)
        guard canonical.checklists == checklists else {
            throw SpaceChecklistEditingFailure.invalidEncodedPresentation
        }
        value = canonical
    }

    private enum Keys: String, CodingKey { case checklists }
}

private struct StrictChecklist: Decodable {
    let value: SpaceChecklistState

    init(from decoder: Decoder) throws {
        try SpaceChecklistEditingCoding.requireExactKeys(
            decoder,
            allowed: ["id", "name", "presentationOrder", "items"],
            failure: .invalidEncodedPresentation
        )
        let container = try decoder.container(keyedBy: Keys.self)
        let items = try container.decode([StrictChecklistItem].self, forKey: .items).map(\.value)
        let canonical = try SpaceChecklistState(
            id: container.decode(SpaceChecklistID.self, forKey: .id),
            name: container.decode(SpaceChecklistName.self, forKey: .name),
            presentationOrder: container.decode(UInt32.self, forKey: .presentationOrder),
            items: items
        )
        guard canonical.items == items else {
            throw SpaceChecklistEditingFailure.invalidEncodedPresentation
        }
        value = canonical
    }

    private enum Keys: String, CodingKey { case id, name, presentationOrder, items }
}

private struct StrictChecklistItem: Decodable {
    let value: SpaceChecklistItemState

    init(from decoder: Decoder) throws {
        try SpaceChecklistEditingCoding.requireExactKeys(
            decoder,
            allowed: ["id", "text", "isChecked", "presentationOrder"],
            failure: .invalidEncodedPresentation
        )
        let container = try decoder.container(keyedBy: Keys.self)
        value = SpaceChecklistItemState(
            id: try container.decode(SpaceChecklistItemID.self, forKey: .id),
            text: try container.decode(SpaceChecklistItemText.self, forKey: .text),
            isChecked: try container.decode(Bool.self, forKey: .isChecked),
            presentationOrder: try container.decode(UInt32.self, forKey: .presentationOrder)
        )
    }

    private enum Keys: String, CodingKey { case id, text, isChecked, presentationOrder }
}

private enum SpaceChecklistEditingDigest {
    static func isCanonicalSHA256(_ value: String) -> Bool {
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        return value.utf8.count == 64 && value.unicodeScalars.allSatisfy(hexadecimal.contains)
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private enum SpaceChecklistEditingCoding {
    static func requireExactKeys(
        _ decoder: Decoder,
        allowed: [String],
        failure: SpaceChecklistEditingFailure
    ) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        guard Set(container.allKeys.map(\.stringValue)) == Set(allowed) else {
            throw failure
        }
    }

    struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        init?(intValue: Int) {
            stringValue = String(intValue)
            self.intValue = intValue
        }
    }
}
