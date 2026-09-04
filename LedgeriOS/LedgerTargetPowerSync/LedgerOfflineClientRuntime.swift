import Foundation
import LedgerTargetCore
import PowerSync

public enum LedgerOfflineClientRuntimeFailure: Error, Equatable, Sendable {
    case accountScopeMismatch
    case principalScopeMismatch
}

public final class LedgerOfflineClientRuntime: @unchecked Sendable {
    private let database: any PowerSyncDatabaseProtocol
    private let creationStore: ClientCreationPowerSyncStore
    private let detailsQuery: ClientCoreDetailsPowerSyncQuery
    private let projectSetupStore: ProjectSetupPowerSyncStore
    private let projectDetailsQuery: ProjectCoreDetailsPowerSyncQuery
    private let directoryQuery: ClientProjectDirectoryPowerSyncQuery
    private let principalId: PrincipalID
    private let accountId: AccountID

    init(
        absoluteDatabasePath: String,
        encryptionKey: LedgerPowerSyncEncryptionKey,
        principalId: PrincipalID,
        accountId: AccountID,
        now: @Sendable @escaping () -> Date = Date.init
    ) throws {
        let database = try LedgerPowerSyncDatabaseFactory.open(
            absolutePath: absoluteDatabasePath,
            encryptionKey: encryptionKey
        )
        self.database = database
        creationStore = ClientCreationPowerSyncStore(database: database, now: now)
        detailsQuery = ClientCoreDetailsPowerSyncQuery(
            database: database,
            principalId: principalId,
            accountId: accountId,
            now: now
        )
        projectSetupStore = ProjectSetupPowerSyncStore(database: database, now: now)
        projectDetailsQuery = ProjectCoreDetailsPowerSyncQuery(
            database: database,
            principalId: principalId,
            accountId: accountId,
            now: now
        )
        directoryQuery = ClientProjectDirectoryPowerSyncQuery(
            database: database,
            principalId: principalId,
            accountId: accountId,
            now: now
        )
        self.principalId = principalId
        self.accountId = accountId
    }

    public func createClient(_ command: CreateClientCommand) async throws -> OperationReceipt {
        guard command.envelope.accountId == accountId else {
            throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
        }
        guard command.envelope.actorPrincipalId == principalId else {
            throw LedgerOfflineClientRuntimeFailure.principalScopeMismatch
        }
        return try await creationStore.create(command)
    }

    public func watchClient(
        _ request: ClientCoreDetailsRequest
    ) -> AsyncThrowingStream<ClientCoreDetailsUpdate, Error> {
        guard request.accountId == accountId else {
            return Self.failedStream(LedgerOfflineClientRuntimeFailure.accountScopeMismatch)
        }
        return detailsQuery.watchClientCoreDetails(request)
    }

    public func createProject(_ command: CreateProjectCommand) async throws -> OperationReceipt {
        guard command.envelope.accountId == accountId else {
            throw LedgerOfflineClientRuntimeFailure.accountScopeMismatch
        }
        guard command.envelope.actorPrincipalId == principalId else {
            throw LedgerOfflineClientRuntimeFailure.principalScopeMismatch
        }
        return try await projectSetupStore.create(command)
    }

    public func watchProject(
        _ request: ProjectCoreDetailsRequest
    ) -> AsyncThrowingStream<ProjectCoreDetailsUpdate, Error> {
        guard request.accountId == accountId else {
            return Self.failedStream(LedgerOfflineClientRuntimeFailure.accountScopeMismatch)
        }
        return projectDetailsQuery.watchProjectCoreDetails(request)
    }

    public func watchClients() -> AsyncThrowingStream<ClientListSnapshot, Error> {
        directoryQuery.watchClients(accountId: accountId)
    }

    public func watchProjects() -> AsyncThrowingStream<ProjectListSnapshot, Error> {
        directoryQuery.watchProjects(accountId: accountId)
    }

    public func pendingUploadCount() async throws -> Int64 {
        try await database.get("SELECT count(*) FROM ps_crud") { cursor in
            try cursor.getInt64(index: 0)
        }
    }

    public func encryptionCipher() async throws -> String {
        try await database.get("PRAGMA cipher") { cursor in
            try cursor.getString(index: 0)
        }
    }

    /// Ordinary close preserves the encrypted database and its Keychain key.
    /// Destructive cleanup belongs to the later session-ending coordinator.
    public func close() async throws {
        try await database.close(deleteDatabase: false)
    }

    private static func failedStream<Value: Sendable>(
        _ error: Error
    ) -> AsyncThrowingStream<Value, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }
}

public enum LedgerPowerSyncLocalBootstrap {
    public static func open(
        validatedEnvironment: ValidatedLedgerEnvironment,
        principalId: PrincipalID,
        accountId: AccountID
    ) throws -> LedgerOfflineClientRuntime {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw LedgerPowerSyncDatabaseFailure.invalidDatabasePath
        }
        return try open(
            validatedEnvironment: validatedEnvironment,
            principalId: principalId,
            accountId: accountId,
            applicationSupportDirectory: applicationSupport,
            loadOrCreateKey: { service, account in
                let keychain = try LedgerPowerSyncKeychain(service: service)
                return try keychain.loadOrCreateKey(principalNamespace: account)
            },
            createDirectory: { directory in
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.protectionKey: FileProtectionType.complete]
                )
            }
        )
    }

    static func open(
        validatedEnvironment: ValidatedLedgerEnvironment,
        principalId: PrincipalID,
        accountId: AccountID,
        applicationSupportDirectory: URL,
        loadOrCreateKey: (_ service: String, _ account: String) throws -> LedgerPowerSyncEncryptionKey,
        createDirectory: (_ directory: URL) throws -> Void
    ) throws -> LedgerOfflineClientRuntime {
        let location = try LedgerWorkspaceRuntimeIsolation.resolve(
            validatedEnvironment: validatedEnvironment,
            principalId: principalId,
            accountId: accountId,
            applicationSupportDirectory: applicationSupportDirectory
        )
        let key = try loadOrCreateKey(
            location.keychainService,
            location.keychainAccount
        )
        try createDirectory(location.databaseURL.deletingLastPathComponent())
        return try LedgerOfflineClientRuntime(
            absoluteDatabasePath: location.databaseURL.path,
            encryptionKey: key,
            principalId: principalId,
            accountId: accountId
        )
    }
}
