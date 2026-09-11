import Foundation

public enum BudgetCategoryReferenceFailure: Error, Equatable, Sendable {
    case invalidName
    case accountScopeMismatch
    case duplicateCategoryIdentity
    case duplicateCategoryName
    case duplicatePresentationOrder
    case visibleCountMismatch
    case invalidSnapshotAsOf
    case localReadFailed
    case invalidEncodedDefinition
    case invalidEncodedSnapshot

    public var diagnosticCode: String {
        switch self {
        case .invalidName:
            "budget_category_reference_name_invalid"
        case .accountScopeMismatch:
            "budget_category_reference_account_mismatch"
        case .duplicateCategoryIdentity:
            "budget_category_reference_identity_duplicate"
        case .duplicateCategoryName:
            "budget_category_reference_name_duplicate"
        case .duplicatePresentationOrder:
            "budget_category_reference_order_duplicate"
        case .visibleCountMismatch:
            "budget_category_reference_visible_count_mismatch"
        case .invalidSnapshotAsOf:
            "budget_category_reference_as_of_invalid"
        case .localReadFailed:
            "budget_category_reference_local_read_failed"
        case .invalidEncodedDefinition:
            "budget_category_reference_definition_encoding_invalid"
        case .invalidEncodedSnapshot:
            "budget_category_reference_snapshot_encoding_invalid"
        }
    }
}

public struct BudgetCategoryName: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasControl = trimmed.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
        }
        guard !trimmed.isEmpty,
              trimmed.count <= 100,
              !hasControl else {
            throw BudgetCategoryReferenceFailure.invalidName
        }
        self.rawValue = trimmed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(validating: container.decode(String.self))
        } catch let failure as BudgetCategoryReferenceFailure {
            throw failure
        } catch {
            throw BudgetCategoryReferenceFailure.invalidName
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    fileprivate var comparisonKey: String {
        rawValue.lowercased()
    }
}

public enum BudgetCategoryKind: String, Codable, CaseIterable, Sendable {
    case general
    case itemized
    case fee
}

public struct BudgetCategoryDefinitionSnapshot: Codable, Equatable, Sendable {
    public let id: BudgetCategoryID
    public let accountId: AccountID
    public let name: BudgetCategoryName
    public let kind: BudgetCategoryKind
    public let lifecycle: DirectoryLifecycleState
    public let isSystem: Bool
    public let excludesFromOverallBudget: Bool
    public let presentationOrder: UInt32
    public let revision: UInt64

    public var isSelectableForProjectConfiguration: Bool {
        lifecycle == .active && !isSystem
    }

    public var isSelectableForItemizedProjectWorkflow: Bool {
        isSelectableForProjectConfiguration && kind == .itemized
    }

    public init(
        id: BudgetCategoryID,
        accountId: AccountID,
        name: BudgetCategoryName,
        kind: BudgetCategoryKind,
        lifecycle: DirectoryLifecycleState,
        isSystem: Bool,
        excludesFromOverallBudget: Bool,
        presentationOrder: UInt32,
        revision: UInt64
    ) {
        self.id = id
        self.accountId = accountId
        self.name = name
        self.kind = kind
        self.lifecycle = lifecycle
        self.isSystem = isSystem
        self.excludesFromOverallBudget = excludesFromOverallBudget
        self.presentationOrder = presentationOrder
        self.revision = revision
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                id: try container.decode(BudgetCategoryID.self, forKey: .id),
                accountId: try container.decode(AccountID.self, forKey: .accountId),
                name: try container.decode(BudgetCategoryName.self, forKey: .name),
                kind: try container.decode(BudgetCategoryKind.self, forKey: .kind),
                lifecycle: try container.decode(
                    DirectoryLifecycleState.self,
                    forKey: .lifecycle
                ),
                isSystem: try container.decode(Bool.self, forKey: .isSystem),
                excludesFromOverallBudget: try container.decode(
                    Bool.self,
                    forKey: .excludesFromOverallBudget
                ),
                presentationOrder: try container.decode(
                    UInt32.self,
                    forKey: .presentationOrder
                ),
                revision: try container.decode(UInt64.self, forKey: .revision)
            )
        } catch let failure as BudgetCategoryReferenceFailure {
            throw failure
        } catch {
            throw BudgetCategoryReferenceFailure.invalidEncodedDefinition
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case accountId
        case name
        case kind
        case lifecycle
        case isSystem
        case excludesFromOverallBudget
        case presentationOrder
        case revision
    }
}

public struct BudgetCategoryReferenceSnapshot: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let local: ListLocalSnapshot<BudgetCategoryDefinitionSnapshot>

    public init(
        accountId: AccountID,
        local: ListLocalSnapshot<BudgetCategoryDefinitionSnapshot>
    ) throws {
        guard local.asOf.timeIntervalSinceReferenceDate.isFinite else {
            throw BudgetCategoryReferenceFailure.invalidSnapshotAsOf
        }
        guard local.rows.allSatisfy({ $0.accountId == accountId }) else {
            throw BudgetCategoryReferenceFailure.accountScopeMismatch
        }
        guard local.visibleRowCountBeforeFiltering == local.rows.count else {
            throw BudgetCategoryReferenceFailure.visibleCountMismatch
        }
        guard Self.firstDuplicate(local.rows.map(\.id)) == nil else {
            throw BudgetCategoryReferenceFailure.duplicateCategoryIdentity
        }
        guard Self.firstDuplicate(local.rows.map { $0.name.comparisonKey }) == nil else {
            throw BudgetCategoryReferenceFailure.duplicateCategoryName
        }
        guard Self.firstDuplicate(local.rows.map(\.presentationOrder)) == nil else {
            throw BudgetCategoryReferenceFailure.duplicatePresentationOrder
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
                    ListLocalSnapshot<BudgetCategoryDefinitionSnapshot>.self,
                    forKey: .local
                )
            )
        } catch let failure as BudgetCategoryReferenceFailure {
            throw failure
        } catch {
            throw BudgetCategoryReferenceFailure.invalidEncodedSnapshot
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

public protocol BudgetCategoryReferenceQuerying: Sendable {
    func watchBudgetCategories(
        accountId: AccountID
    ) -> AsyncThrowingStream<BudgetCategoryReferenceSnapshot, Error>
}
