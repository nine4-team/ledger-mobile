import Foundation
import LedgerTargetCore
import PowerSync

public final class LedgerOfflineClientRuntime: @unchecked Sendable {
    private let database: any PowerSyncDatabaseProtocol
    private let creationStore: ClientCreationPowerSyncStore
    private let detailsQuery: ClientCoreDetailsPowerSyncQuery

    public init(
        absoluteDatabasePath: String,
        encryptionKey: LedgerPowerSyncEncryptionKey,
        now: @Sendable @escaping () -> Date = Date.init
    ) throws {
        let database = try LedgerPowerSyncDatabaseFactory.open(
            absolutePath: absoluteDatabasePath,
            encryptionKey: encryptionKey
        )
        self.database = database
        creationStore = ClientCreationPowerSyncStore(database: database, now: now)
        detailsQuery = ClientCoreDetailsPowerSyncQuery(database: database, now: now)
    }

    public func createClient(_ command: CreateClientCommand) async throws -> OperationReceipt {
        try await creationStore.create(command)
    }

    public func watchClient(
        _ request: ClientCoreDetailsRequest
    ) -> AsyncThrowingStream<ClientCoreDetailsUpdate, Error> {
        detailsQuery.watchClientCoreDetails(request)
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

    public func close(deleteDatabase: Bool = false) async throws {
        try await database.close(deleteDatabase: deleteDatabase)
    }
}

public enum LedgerPowerSyncLocalBootstrap {
    public static func open(
        localDataNamespacePrefix: String,
        principalId: PrincipalID,
        accountId: AccountID
    ) throws -> LedgerOfflineClientRuntime {
        let principalNamespace = "\(principalId.rawValue).\(accountId.rawValue)"
        let keychain = try LedgerPowerSyncKeychain(
            service: "\(localDataNamespacePrefix).powersync.database-key"
        )
        let key = try keychain.loadOrCreateKey(principalNamespace: principalNamespace)
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw LedgerPowerSyncDatabaseFailure.invalidDatabasePath
        }
        let directory = applicationSupport
            .appendingPathComponent(localDataNamespacePrefix, isDirectory: true)
            .appendingPathComponent(principalId.rawValue, isDirectory: true)
            .appendingPathComponent(accountId.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        return try LedgerOfflineClientRuntime(
            absoluteDatabasePath: directory.appendingPathComponent("ledger.sqlite").path,
            encryptionKey: key
        )
    }
}
