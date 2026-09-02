import Foundation

public enum ProjectCategoryConfigurationFailure: Error, Equatable, Sendable {
    case negativeAllocation
    case categoryAccountScopeMismatch
    case duplicateCategoryIdentity
    case duplicateCategoryName
    case duplicatePresentationOrder
    case visibleCountMismatch
    case relationshipCompletenessMismatch
    case invalidSnapshotAsOf
    case requestAccountMismatch
    case requestProjectMismatch
    case localReadFailed
    case invalidEncodedState
    case invalidEncodedRow
    case invalidEncodedSnapshot

    public var diagnosticCode: String {
        switch self {
        case .negativeAllocation:
            "project_category_configuration_allocation_negative"
        case .categoryAccountScopeMismatch:
            "project_category_configuration_category_account_mismatch"
        case .duplicateCategoryIdentity:
            "project_category_configuration_identity_duplicate"
        case .duplicateCategoryName:
            "project_category_configuration_name_duplicate"
        case .duplicatePresentationOrder:
            "project_category_configuration_order_duplicate"
        case .visibleCountMismatch:
            "project_category_configuration_visible_count_mismatch"
        case .relationshipCompletenessMismatch:
            "project_category_configuration_relationship_completeness_mismatch"
        case .invalidSnapshotAsOf:
            "project_category_configuration_as_of_invalid"
        case .requestAccountMismatch:
            "project_category_configuration_request_account_mismatch"
        case .requestProjectMismatch:
            "project_category_configuration_request_project_mismatch"
        case .localReadFailed:
            "project_category_configuration_local_read_failed"
        case .invalidEncodedState:
            "project_category_configuration_state_encoding_invalid"
        case .invalidEncodedRow:
            "project_category_configuration_row_encoding_invalid"
        case .invalidEncodedSnapshot:
            "project_category_configuration_snapshot_encoding_invalid"
        }
    }
}

public enum ProjectCategoryConfigurationState: Codable, Equatable, Sendable {
    case noRelationship
    case enabledWithoutAllocation
    case enabledWithAllocation(Money)
    case relationshipEvidenceIncomplete

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(StateKind.self, forKey: .kind)
            switch kind {
            case .noRelationship:
                guard !container.contains(.allocation) else {
                    throw ProjectCategoryConfigurationFailure.invalidEncodedState
                }
                self = .noRelationship
            case .enabledWithoutAllocation:
                guard !container.contains(.allocation) else {
                    throw ProjectCategoryConfigurationFailure.invalidEncodedState
                }
                self = .enabledWithoutAllocation
            case .enabledWithAllocation:
                let allocation = try container.decode(Money.self, forKey: .allocation)
                guard allocation.minorUnits >= 0 else {
                    throw ProjectCategoryConfigurationFailure.negativeAllocation
                }
                self = .enabledWithAllocation(allocation)
            case .relationshipEvidenceIncomplete:
                guard !container.contains(.allocation) else {
                    throw ProjectCategoryConfigurationFailure.invalidEncodedState
                }
                self = .relationshipEvidenceIncomplete
            }
        } catch let failure as ProjectCategoryConfigurationFailure {
            throw failure
        } catch {
            throw ProjectCategoryConfigurationFailure.invalidEncodedState
        }
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .noRelationship:
            try container.encode(StateKind.noRelationship, forKey: .kind)
        case .enabledWithoutAllocation:
            try container.encode(StateKind.enabledWithoutAllocation, forKey: .kind)
        case .enabledWithAllocation(let allocation):
            try container.encode(StateKind.enabledWithAllocation, forKey: .kind)
            try container.encode(allocation, forKey: .allocation)
        case .relationshipEvidenceIncomplete:
            try container.encode(StateKind.relationshipEvidenceIncomplete, forKey: .kind)
        }
    }

    fileprivate func validate() throws {
        if case .enabledWithAllocation(let allocation) = self,
           allocation.minorUnits < 0 {
            throw ProjectCategoryConfigurationFailure.negativeAllocation
        }
    }

    private enum StateKind: String, Codable {
        case noRelationship
        case enabledWithoutAllocation
        case enabledWithAllocation
        case relationshipEvidenceIncomplete
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case allocation
    }
}

public struct ProjectCategoryConfigurationRow: Codable, Equatable, Sendable {
    public let category: BudgetCategoryDefinitionSnapshot
    public let state: ProjectCategoryConfigurationState

    public init(
        category: BudgetCategoryDefinitionSnapshot,
        state: ProjectCategoryConfigurationState
    ) throws {
        try state.validate()
        self.category = category
        self.state = state
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                category: container.decode(
                    BudgetCategoryDefinitionSnapshot.self,
                    forKey: .category
                ),
                state: container.decode(
                    ProjectCategoryConfigurationState.self,
                    forKey: .state
                )
            )
        } catch let failure as ProjectCategoryConfigurationFailure {
            throw failure
        } catch {
            throw ProjectCategoryConfigurationFailure.invalidEncodedRow
        }
    }

    private enum CodingKeys: String, CodingKey {
        case category
        case state
    }
}

public struct ProjectCategoryConfigurationSnapshot: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let projectId: ProjectID
    public let configurationRevision: UInt64
    public let local: ListLocalSnapshot<ProjectCategoryConfigurationRow>

    public init(
        accountId: AccountID,
        projectId: ProjectID,
        configurationRevision: UInt64,
        local: ListLocalSnapshot<ProjectCategoryConfigurationRow>
    ) throws {
        guard local.asOf.timeIntervalSinceReferenceDate.isFinite else {
            throw ProjectCategoryConfigurationFailure.invalidSnapshotAsOf
        }
        guard local.rows.allSatisfy({ $0.category.accountId == accountId }) else {
            throw ProjectCategoryConfigurationFailure.categoryAccountScopeMismatch
        }
        guard local.visibleRowCountBeforeFiltering == local.rows.count else {
            throw ProjectCategoryConfigurationFailure.visibleCountMismatch
        }
        guard Self.firstDuplicate(local.rows.map { $0.category.id }) == nil else {
            throw ProjectCategoryConfigurationFailure.duplicateCategoryIdentity
        }
        guard Self.firstDuplicate(
            local.rows.map { $0.category.name.rawValue.lowercased() }
        ) == nil else {
            throw ProjectCategoryConfigurationFailure.duplicateCategoryName
        }
        guard Self.firstDuplicate(
            local.rows.map { $0.category.presentationOrder }
        ) == nil else {
            throw ProjectCategoryConfigurationFailure.duplicatePresentationOrder
        }

        if local.isCompleteForQuery {
            guard !local.rows.contains(where: {
                $0.state == .relationshipEvidenceIncomplete
            }) else {
                throw ProjectCategoryConfigurationFailure.relationshipCompletenessMismatch
            }
        } else {
            guard !local.rows.contains(where: { $0.state == .noRelationship }) else {
                throw ProjectCategoryConfigurationFailure.relationshipCompletenessMismatch
            }
        }

        let rows = local.rows.sorted {
            if $0.category.presentationOrder != $1.category.presentationOrder {
                return $0.category.presentationOrder < $1.category.presentationOrder
            }
            return $0.category.id.rawValue < $1.category.id.rawValue
        }
        self.accountId = accountId
        self.projectId = projectId
        self.configurationRevision = configurationRevision
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
                projectId: container.decode(ProjectID.self, forKey: .projectId),
                configurationRevision: container.decode(
                    UInt64.self,
                    forKey: .configurationRevision
                ),
                local: container.decode(
                    ListLocalSnapshot<ProjectCategoryConfigurationRow>.self,
                    forKey: .local
                )
            )
        } catch let failure as ProjectCategoryConfigurationFailure {
            throw failure
        } catch {
            throw ProjectCategoryConfigurationFailure.invalidEncodedSnapshot
        }
    }

    private static func firstDuplicate<Value: Hashable>(_ values: [Value]) -> Value? {
        var seen: Set<Value> = []
        return values.first { !seen.insert($0).inserted }
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case projectId
        case configurationRevision
        case local
    }
}

public protocol ProjectCategoryConfigurationQuerying: Sendable {
    func watchProjectCategoryConfiguration(
        accountId: AccountID,
        projectId: ProjectID
    ) -> AsyncThrowingStream<ProjectCategoryConfigurationSnapshot, Error>
}
