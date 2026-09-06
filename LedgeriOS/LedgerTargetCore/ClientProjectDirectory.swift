import Foundation

public enum ClientProjectDirectoryFailure: Error, Equatable, Sendable {
    case invalidClientDisplayName
    case invalidProjectDisplayName
    case invalidClientAuditOrder
    case accountScopeMismatch
    case clientRelationshipMismatch
    case duplicateClientIdentity
    case duplicateProjectIdentity

    public var diagnosticCode: String {
        switch self {
        case .invalidClientDisplayName:
            "client_directory_client_name_invalid"
        case .invalidProjectDisplayName:
            "client_directory_project_name_invalid"
        case .invalidClientAuditOrder:
            "client_directory_client_audit_order_invalid"
        case .accountScopeMismatch:
            "client_directory_account_scope_mismatch"
        case .clientRelationshipMismatch:
            "client_directory_relationship_mismatch"
        case .duplicateClientIdentity:
            "client_directory_client_identity_duplicate"
        case .duplicateProjectIdentity:
            "client_directory_project_identity_duplicate"
        }
    }
}

public struct ClientDisplayName: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClientProjectDirectoryFailure.invalidClientDisplayName
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(validating: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ProjectDisplayName: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClientProjectDirectoryFailure.invalidProjectDisplayName
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(validating: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum DirectoryLifecycleState: String, Codable, CaseIterable, Sendable {
    case active
    case archived
}

public struct ClientSummary: Codable, Equatable, Sendable {
    public let id: ClientID
    public let accountId: AccountID
    public let displayName: ClientDisplayName
    public let lifecycle: DirectoryLifecycleState
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: ClientID,
        accountId: AccountID,
        displayName: ClientDisplayName,
        lifecycle: DirectoryLifecycleState,
        createdAt: Date,
        updatedAt: Date
    ) throws {
        guard createdAt.timeIntervalSinceReferenceDate.isFinite,
              updatedAt.timeIntervalSinceReferenceDate.isFinite,
              createdAt <= updatedAt else {
            throw ClientProjectDirectoryFailure.invalidClientAuditOrder
        }
        self.id = id
        self.accountId = accountId
        self.displayName = displayName
        self.lifecycle = lifecycle
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(ClientID.self, forKey: .id),
            accountId: container.decode(AccountID.self, forKey: .accountId),
            displayName: container.decode(ClientDisplayName.self, forKey: .displayName),
            lifecycle: container.decode(DirectoryLifecycleState.self, forKey: .lifecycle),
            createdAt: container.decode(Date.self, forKey: .createdAt),
            updatedAt: container.decode(Date.self, forKey: .updatedAt)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case accountId
        case displayName
        case lifecycle
        case createdAt
        case updatedAt
    }
}

public struct ProjectSummary: Codable, Equatable, Sendable {
    public let id: ProjectID
    public let accountId: AccountID
    public let clientId: ClientID
    public let client: ClientSummary
    public let displayName: ProjectDisplayName
    public let description: String?
    public let lifecycle: DirectoryLifecycleState

    public init(
        id: ProjectID,
        accountId: AccountID,
        clientId: ClientID,
        client: ClientSummary,
        displayName: ProjectDisplayName,
        description: String?,
        lifecycle: DirectoryLifecycleState
    ) throws {
        guard accountId == client.accountId else {
            throw ClientProjectDirectoryFailure.accountScopeMismatch
        }
        guard clientId == client.id else {
            throw ClientProjectDirectoryFailure.clientRelationshipMismatch
        }
        self.id = id
        self.accountId = accountId
        self.clientId = clientId
        self.client = client
        self.displayName = displayName
        self.description = description
        self.lifecycle = lifecycle
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(ProjectID.self, forKey: .id),
            accountId: container.decode(AccountID.self, forKey: .accountId),
            clientId: container.decode(ClientID.self, forKey: .clientId),
            client: container.decode(ClientSummary.self, forKey: .client),
            displayName: container.decode(ProjectDisplayName.self, forKey: .displayName),
            description: container.decodeIfPresent(String.self, forKey: .description),
            lifecycle: container.decode(DirectoryLifecycleState.self, forKey: .lifecycle)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case accountId
        case clientId
        case client
        case displayName
        case description
        case lifecycle
    }
}

public struct ClientListSnapshot: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let local: ListLocalSnapshot<ClientSummary>

    public init(accountId: AccountID, local: ListLocalSnapshot<ClientSummary>) throws {
        guard local.rows.allSatisfy({ $0.accountId == accountId }) else {
            throw ClientProjectDirectoryFailure.accountScopeMismatch
        }
        guard Self.hasUniqueIdentities(local.rows.map(\.id)) else {
            throw ClientProjectDirectoryFailure.duplicateClientIdentity
        }
        self.accountId = accountId
        self.local = local
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            accountId: container.decode(AccountID.self, forKey: .accountId),
            local: container.decode(
                ListLocalSnapshot<ClientSummary>.self,
                forKey: .local
            )
        )
    }

    private static func hasUniqueIdentities<Value: Hashable>(_ values: [Value]) -> Bool {
        Set(values).count == values.count
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case local
    }
}

public struct ProjectListSnapshot: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let local: ListLocalSnapshot<ProjectSummary>

    public init(accountId: AccountID, local: ListLocalSnapshot<ProjectSummary>) throws {
        guard local.rows.allSatisfy({
            $0.accountId == accountId && $0.client.accountId == accountId
        }) else {
            throw ClientProjectDirectoryFailure.accountScopeMismatch
        }
        guard Self.hasUniqueIdentities(local.rows.map(\.id)) else {
            throw ClientProjectDirectoryFailure.duplicateProjectIdentity
        }
        self.accountId = accountId
        self.local = local
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            accountId: container.decode(AccountID.self, forKey: .accountId),
            local: container.decode(
                ListLocalSnapshot<ProjectSummary>.self,
                forKey: .local
            )
        )
    }

    private static func hasUniqueIdentities<Value: Hashable>(_ values: [Value]) -> Bool {
        Set(values).count == values.count
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case local
    }
}

public protocol ClientProjectDirectoryQuerying: Sendable {
    func watchClients(
        accountId: AccountID
    ) -> AsyncThrowingStream<ClientListSnapshot, Error>

    func watchProjects(
        accountId: AccountID
    ) -> AsyncThrowingStream<ProjectListSnapshot, Error>
}
