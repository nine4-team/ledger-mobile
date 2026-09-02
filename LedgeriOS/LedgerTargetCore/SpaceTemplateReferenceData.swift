import Foundation

public enum SpaceTemplateReferenceFailure: Error, Equatable, Sendable {
    case invalidTemplateName
    case invalidChecklistName
    case invalidChecklistItemText
    case accountScopeMismatch
    case duplicateTemplateIdentity
    case duplicateTemplatePresentationOrder
    case duplicateChecklistIdentity
    case duplicateChecklistPresentationOrder
    case duplicateChecklistItemIdentity
    case duplicateChecklistItemPresentationOrder
    case visibleCountMismatch
    case invalidSnapshotAsOf
    case localReadFailed
    case invalidEncodedTemplateName
    case invalidEncodedChecklistName
    case invalidEncodedChecklistItemText
    case invalidEncodedChecklistItem
    case invalidEncodedChecklist
    case invalidEncodedTemplate
    case invalidEncodedSnapshot

    public var diagnosticCode: String {
        switch self {
        case .invalidTemplateName:
            "space_template_name_invalid"
        case .invalidChecklistName:
            "space_template_checklist_name_invalid"
        case .invalidChecklistItemText:
            "space_template_checklist_item_text_invalid"
        case .accountScopeMismatch:
            "space_template_account_scope_mismatch"
        case .duplicateTemplateIdentity:
            "space_template_identity_duplicate"
        case .duplicateTemplatePresentationOrder:
            "space_template_order_duplicate"
        case .duplicateChecklistIdentity:
            "space_template_checklist_identity_duplicate"
        case .duplicateChecklistPresentationOrder:
            "space_template_checklist_order_duplicate"
        case .duplicateChecklistItemIdentity:
            "space_template_checklist_item_identity_duplicate"
        case .duplicateChecklistItemPresentationOrder:
            "space_template_checklist_item_order_duplicate"
        case .visibleCountMismatch:
            "space_template_visible_count_mismatch"
        case .invalidSnapshotAsOf:
            "space_template_as_of_invalid"
        case .localReadFailed:
            "space_template_local_read_failed"
        case .invalidEncodedTemplateName:
            "space_template_name_encoding_invalid"
        case .invalidEncodedChecklistName:
            "space_template_checklist_name_encoding_invalid"
        case .invalidEncodedChecklistItemText:
            "space_template_checklist_item_text_encoding_invalid"
        case .invalidEncodedChecklistItem:
            "space_template_checklist_item_encoding_invalid"
        case .invalidEncodedChecklist:
            "space_template_checklist_encoding_invalid"
        case .invalidEncodedTemplate:
            "space_template_encoding_invalid"
        case .invalidEncodedSnapshot:
            "space_template_snapshot_encoding_invalid"
        }
    }
}

public enum SpaceTemplateIDTag: Sendable {}
public typealias SpaceTemplateID = DomainEntityIdentifier<SpaceTemplateIDTag>

public enum SpaceTemplateChecklistIDTag: Sendable {}
public typealias SpaceTemplateChecklistID = DomainEntityIdentifier<SpaceTemplateChecklistIDTag>

public enum SpaceTemplateChecklistItemIDTag: Sendable {}
public typealias SpaceTemplateChecklistItemID =
    DomainEntityIdentifier<SpaceTemplateChecklistItemIDTag>

public struct SpaceTemplateName: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpaceTemplateReferenceFailure.invalidTemplateName
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            try self.init(validating: container.decode(String.self))
        } catch let failure as SpaceTemplateReferenceFailure {
            throw failure
        } catch {
            throw SpaceTemplateReferenceFailure.invalidEncodedTemplateName
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct SpaceTemplateChecklistName: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpaceTemplateReferenceFailure.invalidChecklistName
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            try self.init(validating: container.decode(String.self))
        } catch let failure as SpaceTemplateReferenceFailure {
            throw failure
        } catch {
            throw SpaceTemplateReferenceFailure.invalidEncodedChecklistName
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct SpaceTemplateChecklistItemText: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpaceTemplateReferenceFailure.invalidChecklistItemText
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            try self.init(validating: container.decode(String.self))
        } catch let failure as SpaceTemplateReferenceFailure {
            throw failure
        } catch {
            throw SpaceTemplateReferenceFailure.invalidEncodedChecklistItemText
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct SpaceTemplateChecklistItemDefinition: Codable, Equatable, Sendable {
    public let id: SpaceTemplateChecklistItemID
    public let text: SpaceTemplateChecklistItemText
    public let presentationOrder: UInt32

    public init(
        id: SpaceTemplateChecklistItemID,
        text: SpaceTemplateChecklistItemText,
        presentationOrder: UInt32
    ) {
        self.id = id
        self.text = text
        self.presentationOrder = presentationOrder
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                id: try container.decode(SpaceTemplateChecklistItemID.self, forKey: .id),
                text: try container.decode(
                    SpaceTemplateChecklistItemText.self,
                    forKey: .text
                ),
                presentationOrder: try container.decode(
                    UInt32.self,
                    forKey: .presentationOrder
                )
            )
        } catch let failure as SpaceTemplateReferenceFailure {
            throw failure
        } catch {
            throw SpaceTemplateReferenceFailure.invalidEncodedChecklistItem
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case presentationOrder
    }
}

public struct SpaceTemplateChecklistDefinition: Codable, Equatable, Sendable {
    public let id: SpaceTemplateChecklistID
    public let name: SpaceTemplateChecklistName
    public let presentationOrder: UInt32
    public let items: [SpaceTemplateChecklistItemDefinition]

    public init(
        id: SpaceTemplateChecklistID,
        name: SpaceTemplateChecklistName,
        presentationOrder: UInt32,
        items: [SpaceTemplateChecklistItemDefinition]
    ) throws {
        guard Self.firstDuplicate(items.map(\.id)) == nil else {
            throw SpaceTemplateReferenceFailure.duplicateChecklistItemIdentity
        }
        guard Self.firstDuplicate(items.map(\.presentationOrder)) == nil else {
            throw SpaceTemplateReferenceFailure.duplicateChecklistItemPresentationOrder
        }
        self.id = id
        self.name = name
        self.presentationOrder = presentationOrder
        self.items = items.sorted {
            if $0.presentationOrder != $1.presentationOrder {
                return $0.presentationOrder < $1.presentationOrder
            }
            return $0.id.rawValue < $1.id.rawValue
        }
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                id: container.decode(SpaceTemplateChecklistID.self, forKey: .id),
                name: container.decode(SpaceTemplateChecklistName.self, forKey: .name),
                presentationOrder: container.decode(
                    UInt32.self,
                    forKey: .presentationOrder
                ),
                items: container.decode(
                    [SpaceTemplateChecklistItemDefinition].self,
                    forKey: .items
                )
            )
        } catch let failure as SpaceTemplateReferenceFailure {
            throw failure
        } catch {
            throw SpaceTemplateReferenceFailure.invalidEncodedChecklist
        }
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

public struct SpaceTemplateSnapshot: Codable, Equatable, Sendable {
    public let id: SpaceTemplateID
    public let accountId: AccountID
    public let name: SpaceTemplateName
    public let notes: String?
    public let checklists: [SpaceTemplateChecklistDefinition]
    public let lifecycle: DirectoryLifecycleState
    public let presentationOrder: UInt32
    public let revision: UInt64

    public var isSelectable: Bool {
        lifecycle == .active
    }

    public init(
        id: SpaceTemplateID,
        accountId: AccountID,
        name: SpaceTemplateName,
        notes: String?,
        checklists: [SpaceTemplateChecklistDefinition],
        lifecycle: DirectoryLifecycleState,
        presentationOrder: UInt32,
        revision: UInt64
    ) throws {
        guard Self.firstDuplicate(checklists.map(\.id)) == nil else {
            throw SpaceTemplateReferenceFailure.duplicateChecklistIdentity
        }
        guard Self.firstDuplicate(checklists.map(\.presentationOrder)) == nil else {
            throw SpaceTemplateReferenceFailure.duplicateChecklistPresentationOrder
        }
        self.id = id
        self.accountId = accountId
        self.name = name
        self.notes = notes
        self.checklists = checklists.sorted {
            if $0.presentationOrder != $1.presentationOrder {
                return $0.presentationOrder < $1.presentationOrder
            }
            return $0.id.rawValue < $1.id.rawValue
        }
        self.lifecycle = lifecycle
        self.presentationOrder = presentationOrder
        self.revision = revision
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                id: container.decode(SpaceTemplateID.self, forKey: .id),
                accountId: container.decode(AccountID.self, forKey: .accountId),
                name: container.decode(SpaceTemplateName.self, forKey: .name),
                notes: container.decodeIfPresent(String.self, forKey: .notes),
                checklists: container.decode(
                    [SpaceTemplateChecklistDefinition].self,
                    forKey: .checklists
                ),
                lifecycle: container.decode(
                    DirectoryLifecycleState.self,
                    forKey: .lifecycle
                ),
                presentationOrder: container.decode(
                    UInt32.self,
                    forKey: .presentationOrder
                ),
                revision: container.decode(UInt64.self, forKey: .revision)
            )
        } catch let failure as SpaceTemplateReferenceFailure {
            throw failure
        } catch {
            throw SpaceTemplateReferenceFailure.invalidEncodedTemplate
        }
    }

    private static func firstDuplicate<Value: Hashable>(_ values: [Value]) -> Value? {
        var seen: Set<Value> = []
        return values.first { !seen.insert($0).inserted }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case accountId
        case name
        case notes
        case checklists
        case lifecycle
        case presentationOrder
        case revision
    }
}

public struct SpaceTemplateReferenceSnapshot: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let local: ListLocalSnapshot<SpaceTemplateSnapshot>

    public var selectableTemplates: [SpaceTemplateSnapshot] {
        local.rows.filter(\.isSelectable)
    }

    public init(
        accountId: AccountID,
        local: ListLocalSnapshot<SpaceTemplateSnapshot>
    ) throws {
        guard local.asOf.timeIntervalSinceReferenceDate.isFinite else {
            throw SpaceTemplateReferenceFailure.invalidSnapshotAsOf
        }
        guard local.rows.allSatisfy({ $0.accountId == accountId }) else {
            throw SpaceTemplateReferenceFailure.accountScopeMismatch
        }
        guard local.visibleRowCountBeforeFiltering == local.rows.count else {
            throw SpaceTemplateReferenceFailure.visibleCountMismatch
        }
        guard Self.firstDuplicate(local.rows.map(\.id)) == nil else {
            throw SpaceTemplateReferenceFailure.duplicateTemplateIdentity
        }
        guard Self.firstDuplicate(local.rows.map(\.presentationOrder)) == nil else {
            throw SpaceTemplateReferenceFailure.duplicateTemplatePresentationOrder
        }

        let rows = local.rows.sorted {
            if $0.presentationOrder != $1.presentationOrder {
                return $0.presentationOrder < $1.presentationOrder
            }
            return $0.id.rawValue < $1.id.rawValue
        }
        self.accountId = accountId
        self.local = try ListLocalSnapshot(
            queryFingerprint: local.queryFingerprint,
            rows: rows,
            visibleRowCountBeforeFiltering: local.visibleRowCountBeforeFiltering,
            isCompleteForQuery: local.isCompleteForQuery,
            quality: local.quality,
            localDataVersion: local.localDataVersion,
            asOf: local.asOf
        )
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                accountId: container.decode(AccountID.self, forKey: .accountId),
                local: container.decode(
                    ListLocalSnapshot<SpaceTemplateSnapshot>.self,
                    forKey: .local
                )
            )
        } catch let failure as SpaceTemplateReferenceFailure {
            throw failure
        } catch {
            throw SpaceTemplateReferenceFailure.invalidEncodedSnapshot
        }
    }

    private static func firstDuplicate<Value: Hashable>(_ values: [Value]) -> Value? {
        var seen: Set<Value> = []
        return values.first { !seen.insert($0).inserted }
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case local
    }
}

public protocol SpaceTemplateQuerying: Sendable {
    func watchSpaceTemplates(
        accountId: AccountID
    ) -> AsyncThrowingStream<SpaceTemplateReferenceSnapshot, Error>
}
