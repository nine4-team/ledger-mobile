import CryptoKit
import Foundation
import LedgerTargetCore
import PowerSync

public enum LedgerPrincipalOfflineRuntimeFailure: Error, Equatable, Sendable {
    case invalidLocalDataNamespace
}

/// Owns the encrypted local bootstrap database for one compiled environment and
/// Principal. It intentionally exposes no Account activation or workspace data.
public final class LedgerPrincipalOfflineRuntime: AccountQuerying, @unchecked Sendable {
    private let database: any PowerSyncDatabaseProtocol
    private let query: AccountDiscoveryPowerSyncQuery
    private let environment: LedgerEnvironmentKind
    private let principalId: PrincipalID

    init(
        database: any PowerSyncDatabaseProtocol,
        environment: LedgerEnvironmentKind,
        principalId: PrincipalID,
        readinessObservation: @escaping AccountDiscoveryPowerSyncQuery.ReadinessObservation,
        now: @Sendable @escaping () -> Date = Date.init
    ) {
        self.database = database
        self.environment = environment
        self.principalId = principalId
        query = AccountDiscoveryPowerSyncQuery(
            database: database,
            environment: environment,
            principalId: principalId,
            readinessObservation: readinessObservation,
            now: now
        )
    }

    init(
        absoluteDatabasePath: String,
        encryptionKey: LedgerPowerSyncEncryptionKey,
        environment: LedgerEnvironmentKind,
        principalId: PrincipalID,
        readinessObservation: @escaping AccountDiscoveryPowerSyncQuery.ReadinessObservation,
        now: @Sendable @escaping () -> Date = Date.init
    ) throws {
        let database = try LedgerPowerSyncDatabaseFactory.open(
            absolutePath: absoluteDatabasePath,
            encryptionKey: encryptionKey
        )
        self.database = database
        self.environment = environment
        self.principalId = principalId
        query = AccountDiscoveryPowerSyncQuery(
            database: database,
            environment: environment,
            principalId: principalId,
            readinessObservation: readinessObservation,
            now: now
        )
    }

    public var accountQuery: any AccountQuerying {
        query
    }

    public func watchAuthorizedAccounts(
        environment: LedgerEnvironmentKind,
        principalId: PrincipalID
    ) -> AsyncThrowingStream<AuthorizedAccountDiscoveryUpdate, Error> {
        guard environment == self.environment,
              principalId == self.principalId else {
            return AsyncThrowingStream { continuation in
                continuation.yield(.failed(failure: .unavailable, cached: nil))
                continuation.finish()
            }
        }
        return query.watchAuthorizedAccounts(
            environment: environment,
            principalId: principalId
        )
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

    /// Closing preserves both the encrypted database and its key. Destructive
    /// session-ending behavior belongs to a later coordinated policy boundary.
    public func close() async throws {
        try await database.close(deleteDatabase: false)
    }
}

public enum LedgerPrincipalPowerSyncLocalBootstrap {
    public static func open(
        localDataNamespacePrefix: String,
        environment: LedgerEnvironmentKind,
        principalId: PrincipalID,
        readinessObservation: @escaping AccountDiscoveryPowerSyncQuery.ReadinessObservation
    ) throws -> LedgerPrincipalOfflineRuntime {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw LedgerPowerSyncDatabaseFailure.invalidDatabasePath
        }
        let directory = try bootstrapDirectory(
            applicationSupport: applicationSupport,
            localDataNamespacePrefix: localDataNamespacePrefix,
            environment: environment,
            principalId: principalId
        )
        let principalNamespace = "\(environment.rawValue).\(principalId.rawValue)"
        let keychain = try LedgerPowerSyncKeychain(
            service: "\(localDataNamespacePrefix).powersync.principal-database-key"
        )
        let key = try keychain.loadOrCreateKey(principalNamespace: principalNamespace)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        return try LedgerPrincipalOfflineRuntime(
            absoluteDatabasePath: directory.appendingPathComponent("ledger.sqlite").path,
            encryptionKey: key,
            environment: environment,
            principalId: principalId,
            readinessObservation: readinessObservation
        )
    }

    static func bootstrapDirectory(
        applicationSupport: URL,
        localDataNamespacePrefix: String,
        environment: LedgerEnvironmentKind,
        principalId: PrincipalID
    ) throws -> URL {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-_.")
        )
        let components = localDataNamespacePrefix.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard !localDataNamespacePrefix.isEmpty,
              localDataNamespacePrefix.utf8.count <= 120,
              !localDataNamespacePrefix.contains(".."),
              !localDataNamespacePrefix.contains("/"),
              !localDataNamespacePrefix.contains("\\"),
              localDataNamespacePrefix.unicodeScalars.allSatisfy(allowed.contains),
              components.allSatisfy({ !$0.isEmpty }) else {
            throw LedgerPrincipalOfflineRuntimeFailure.invalidLocalDataNamespace
        }

        let material = [
            "ledger-principal-bootstrap-v1",
            localDataNamespacePrefix,
            environment.rawValue,
            principalId.rawValue
        ].joined(separator: "\u{1f}")
        let digest = SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return applicationSupport
            .appendingPathComponent(localDataNamespacePrefix, isDirectory: true)
            .appendingPathComponent(environment.rawValue, isDirectory: true)
            .appendingPathComponent("principal-\(digest.prefix(32))", isDirectory: true)
            .appendingPathComponent("bootstrap", isDirectory: true)
    }
}
