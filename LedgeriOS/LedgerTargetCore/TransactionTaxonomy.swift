import Foundation

public enum TransactionTaxonomyFailure: Error, Equatable, Sendable {
    case invalidEncodedTransactionType
    case invalidEncodedScopeOwner
    case invalidTransactionScope
    case invalidEncodedRecordRole
    case invalidEncodedClassification
    case incompatibleRecordRole
    case transferRequiresProjectScope
    case transferRouteRequiresProjectScopes
    case transferRouteAccountMismatch
    case transferRouteClientMismatch
    case transferRouteSameProject
    case transferDestinationArchived
    case invalidEncodedTransferRoute
    case duplicateTransferRecordIdentity
    case invalidEncodedTransferPair

    public var diagnosticCode: String {
        switch self {
        case .invalidEncodedTransactionType:
            "transaction_taxonomy_type_invalid"
        case .invalidEncodedScopeOwner:
            "transaction_taxonomy_scope_owner_invalid"
        case .invalidTransactionScope:
            "transaction_taxonomy_scope_invalid"
        case .invalidEncodedRecordRole:
            "transaction_taxonomy_record_role_invalid"
        case .invalidEncodedClassification:
            "transaction_taxonomy_classification_encoding_invalid"
        case .incompatibleRecordRole:
            "transaction_taxonomy_record_role_incompatible"
        case .transferRequiresProjectScope:
            "transaction_taxonomy_transfer_project_scope_required"
        case .transferRouteRequiresProjectScopes:
            "transaction_taxonomy_route_project_scope_required"
        case .transferRouteAccountMismatch:
            "transaction_taxonomy_route_account_mismatch"
        case .transferRouteClientMismatch:
            "transaction_taxonomy_route_client_mismatch"
        case .transferRouteSameProject:
            "transaction_taxonomy_route_same_project"
        case .transferDestinationArchived:
            "transaction_taxonomy_route_destination_archived"
        case .invalidEncodedTransferRoute:
            "transaction_taxonomy_route_encoding_invalid"
        case .duplicateTransferRecordIdentity:
            "transaction_taxonomy_pair_record_duplicate"
        case .invalidEncodedTransferPair:
            "transaction_taxonomy_pair_encoding_invalid"
        }
    }
}

public enum LedgerTransactionType: String, CaseIterable, Sendable {
    case purchase
    case `return`
    case transfer
}

extension LedgerTransactionType: Codable {
    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            guard let value = Self(rawValue: rawValue) else {
                throw TransactionTaxonomyFailure.invalidEncodedTransactionType
            }
            self = value
        } catch let failure as TransactionTaxonomyFailure {
            throw failure
        } catch {
            throw TransactionTaxonomyFailure.invalidEncodedTransactionType
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum TransactionScopeOwnerKind: String, CaseIterable, Sendable {
    case businessInventory
    case project
}

extension TransactionScopeOwnerKind: Codable {
    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            guard let value = Self(rawValue: rawValue) else {
                throw TransactionTaxonomyFailure.invalidEncodedScopeOwner
            }
            self = value
        } catch let failure as TransactionTaxonomyFailure {
            throw failure
        } catch {
            throw TransactionTaxonomyFailure.invalidEncodedScopeOwner
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct TransactionScope: Codable, Equatable, Sendable {
    public let ownerKind: TransactionScopeOwnerKind
    public let accountId: AccountID
    public let projectId: ProjectID?
    public let clientId: ClientID?

    public init(
        ownerKind: TransactionScopeOwnerKind,
        accountId: AccountID,
        projectId: ProjectID?,
        clientId: ClientID?
    ) throws {
        switch ownerKind {
        case .businessInventory:
            guard projectId == nil, clientId == nil else {
                throw TransactionTaxonomyFailure.invalidTransactionScope
            }
        case .project:
            guard projectId != nil, clientId != nil else {
                throw TransactionTaxonomyFailure.invalidTransactionScope
            }
        }
        self.ownerKind = ownerKind
        self.accountId = accountId
        self.projectId = projectId
        self.clientId = clientId
    }

    public static func businessInventory(accountId: AccountID) -> Self {
        Self(
            validatedOwnerKind: .businessInventory,
            accountId: accountId,
            projectId: nil,
            clientId: nil
        )
    }

    public static func project(
        accountId: AccountID,
        projectId: ProjectID,
        clientId: ClientID
    ) -> Self {
        Self(
            validatedOwnerKind: .project,
            accountId: accountId,
            projectId: projectId,
            clientId: clientId
        )
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                ownerKind: container.decode(
                    TransactionScopeOwnerKind.self,
                    forKey: .ownerKind
                ),
                accountId: container.decode(AccountID.self, forKey: .accountId),
                projectId: container.decodeIfPresent(ProjectID.self, forKey: .projectId),
                clientId: container.decodeIfPresent(ClientID.self, forKey: .clientId)
            )
        } catch let failure as TransactionTaxonomyFailure {
            throw failure
        } catch {
            throw TransactionTaxonomyFailure.invalidTransactionScope
        }
    }

    private init(
        validatedOwnerKind ownerKind: TransactionScopeOwnerKind,
        accountId: AccountID,
        projectId: ProjectID?,
        clientId: ClientID?
    ) {
        self.ownerKind = ownerKind
        self.accountId = accountId
        self.projectId = projectId
        self.clientId = clientId
    }

    private enum CodingKeys: String, CodingKey {
        case ownerKind
        case accountId
        case projectId
        case clientId
    }
}

public enum TransactionRecordRole: String, CaseIterable, Sendable {
    case standalone
    case transferSource
    case transferDestination
}

extension TransactionRecordRole: Codable {
    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            guard let value = Self(rawValue: rawValue) else {
                throw TransactionTaxonomyFailure.invalidEncodedRecordRole
            }
            self = value
        } catch let failure as TransactionTaxonomyFailure {
            throw failure
        } catch {
            throw TransactionTaxonomyFailure.invalidEncodedRecordRole
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum TransactionEconomicMeaning: String, Codable, CaseIterable, Sendable {
    case scopeOwnerPaid
    case scopeOwnerReceivedMoneyBack
    case nonCashSameClientReallocation
}

public struct TransactionClassification: Codable, Equatable, Sendable {
    public let type: LedgerTransactionType
    public let scope: TransactionScope
    public let role: TransactionRecordRole

    public var economicMeaning: TransactionEconomicMeaning {
        switch type {
        case .purchase:
            .scopeOwnerPaid
        case .return:
            .scopeOwnerReceivedMoneyBack
        case .transfer:
            .nonCashSameClientReallocation
        }
    }

    public init(
        type: LedgerTransactionType,
        scope: TransactionScope,
        role: TransactionRecordRole
    ) throws {
        switch type {
        case .purchase, .return:
            guard role == .standalone else {
                throw TransactionTaxonomyFailure.incompatibleRecordRole
            }
        case .transfer:
            guard scope.ownerKind == .project else {
                throw TransactionTaxonomyFailure.transferRequiresProjectScope
            }
            guard role == .transferSource || role == .transferDestination else {
                throw TransactionTaxonomyFailure.incompatibleRecordRole
            }
        }
        self.type = type
        self.scope = scope
        self.role = role
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                type: container.decode(LedgerTransactionType.self, forKey: .type),
                scope: container.decode(TransactionScope.self, forKey: .scope),
                role: container.decode(TransactionRecordRole.self, forKey: .role)
            )
        } catch let failure as TransactionTaxonomyFailure {
            throw failure
        } catch {
            throw TransactionTaxonomyFailure.invalidEncodedClassification
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case scope
        case role
    }
}

public struct ProjectTransferRoute: Codable, Equatable, Sendable {
    public let source: TransactionScope
    public let destination: TransactionScope
    public let destinationLifecycle: DirectoryLifecycleState

    public init(source: ProjectSummary, destination: ProjectSummary) throws {
        try self.init(
            source: .project(
                accountId: source.accountId,
                projectId: source.id,
                clientId: source.clientId
            ),
            destination: .project(
                accountId: destination.accountId,
                projectId: destination.id,
                clientId: destination.clientId
            ),
            destinationLifecycle: destination.lifecycle
        )
    }

    public init(
        source: TransactionScope,
        destination: TransactionScope,
        destinationLifecycle: DirectoryLifecycleState
    ) throws {
        guard source.ownerKind == .project,
              destination.ownerKind == .project,
              let sourceProjectId = source.projectId,
              let destinationProjectId = destination.projectId,
              let sourceClientId = source.clientId,
              let destinationClientId = destination.clientId else {
            throw TransactionTaxonomyFailure.transferRouteRequiresProjectScopes
        }
        guard source.accountId == destination.accountId else {
            throw TransactionTaxonomyFailure.transferRouteAccountMismatch
        }
        guard sourceClientId == destinationClientId else {
            throw TransactionTaxonomyFailure.transferRouteClientMismatch
        }
        guard sourceProjectId != destinationProjectId else {
            throw TransactionTaxonomyFailure.transferRouteSameProject
        }
        guard destinationLifecycle == .active else {
            throw TransactionTaxonomyFailure.transferDestinationArchived
        }
        self.source = source
        self.destination = destination
        self.destinationLifecycle = destinationLifecycle
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                source: container.decode(TransactionScope.self, forKey: .source),
                destination: container.decode(TransactionScope.self, forKey: .destination),
                destinationLifecycle: container.decode(
                    DirectoryLifecycleState.self,
                    forKey: .destinationLifecycle
                )
            )
        } catch let failure as TransactionTaxonomyFailure {
            throw failure
        } catch {
            throw TransactionTaxonomyFailure.invalidEncodedTransferRoute
        }
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case destination
        case destinationLifecycle
    }
}

public struct TransferPairIdentity: Codable, Equatable, Sendable {
    public let operationId: OperationID
    public let route: ProjectTransferRoute
    public let sourceTransactionId: TransactionID
    public let destinationTransactionId: TransactionID

    public init(
        operationId: OperationID,
        route: ProjectTransferRoute,
        sourceTransactionId: TransactionID,
        destinationTransactionId: TransactionID
    ) throws {
        guard sourceTransactionId != destinationTransactionId else {
            throw TransactionTaxonomyFailure.duplicateTransferRecordIdentity
        }
        self.operationId = operationId
        self.route = route
        self.sourceTransactionId = sourceTransactionId
        self.destinationTransactionId = destinationTransactionId
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                operationId: container.decode(OperationID.self, forKey: .operationId),
                route: container.decode(ProjectTransferRoute.self, forKey: .route),
                sourceTransactionId: container.decode(
                    TransactionID.self,
                    forKey: .sourceTransactionId
                ),
                destinationTransactionId: container.decode(
                    TransactionID.self,
                    forKey: .destinationTransactionId
                )
            )
        } catch let failure as TransactionTaxonomyFailure {
            throw failure
        } catch {
            throw TransactionTaxonomyFailure.invalidEncodedTransferPair
        }
    }

    private enum CodingKeys: String, CodingKey {
        case operationId
        case route
        case sourceTransactionId
        case destinationTransactionId
    }
}
