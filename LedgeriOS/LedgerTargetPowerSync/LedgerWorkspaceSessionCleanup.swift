import Foundation
import LedgerTargetCore

/// Recoverable voluntary cleanup, separate from permanent membership removal.
/// Only the session-ending coordinator may invoke this after guarded shutdown.
enum LedgerWorkspaceSessionCleanup {
    enum Failure: Error, Equatable { case cleanupPending, intentMismatch, missingIntent }

    private struct Intent: Codable, Equatable {
        let request: SessionEndRequest
        let workspaceKey: String
        let workspaceDirectory: URL
    }

    private static func store() throws -> LedgerPowerSyncKeychain {
        try LedgerPowerSyncKeychain(service: "ledger.target.session-cleanup.v1")
    }

    private static func key(_ summary: PendingLocalWorkSummary) throws -> String {
        try LedgerWorkspaceRemovalRegistry.identity(environment: summary.environment,
            principalId: summary.principalId, accountId: summary.accountId)
    }

    static func requireNoPendingCleanup(
        environment: LedgerEnvironmentKind, principalId: PrincipalID, accountId: AccountID
    ) throws {
        let identity = try LedgerWorkspaceRemovalRegistry.identity(environment: environment,
            principalId: principalId, accountId: accountId)
        // Any record, including malformed bytes, denies reopening. Do not turn
        // failed decoding into permission to open or generate replacement keys.
        if try store().loadRecord(key: identity) != nil { throw Failure.cleanupPending }
    }

    static func begin(_ request: SessionEndRequest, location: LedgerWorkspaceRuntimeLocation) throws {
        let identity = try key(request.expectedSummary)
        guard identity == location.sessionScopeIdentity else { throw Failure.intentMismatch }
        let intent = Intent(request: request, workspaceKey: location.databaseKeychainAccount,
            workspaceDirectory: location.structuredDatabaseURL.deletingLastPathComponent())
        let storage = try store()
        if let saved = try storage.loadRecord(key: identity) {
            guard try JSONDecoder().decode(Intent.self, from: saved) == intent else {
                throw Failure.intentMismatch
            }
            return
        }
        try storage.storeRecord(key: identity, value: JSONEncoder().encode(intent))
    }

    /// Idempotent after any interruption. The opaque location must be resolved
    /// from the original validated environment, not from arbitrary persisted paths.
    /// Keep intent until offline admission and provider cleanup also succeed.
    static func removeLocalData(_ request: SessionEndRequest, location: LedgerWorkspaceRuntimeLocation) throws {
        try requireIntent(request, location: location)
        let directory = location.structuredDatabaseURL.deletingLastPathComponent()
        do { try FileManager.default.removeItem(at: directory) }
        catch let error as CocoaError where error.code == .fileNoSuchFile {
            // An earlier attempt already removed it.
        }
        try LedgerPowerSyncKeychain(service: location.databaseKeychainService)
            .removeRecord(key: location.databaseKeychainAccount)
        try LedgerPowerSyncKeychain(service: location.mediaKeychainService)
            .removeRecord(key: location.mediaKeychainAccount)
    }

    /// Call only after all local admission/cache and provider cleanup succeeds.
    /// Failure leaves bootstrap denied; it does not convert logout into revocation.
    static func complete(_ request: SessionEndRequest, location: LedgerWorkspaceRuntimeLocation) throws {
        try requireIntent(request, location: location)
        guard !FileManager.default.fileExists(atPath: location.structuredDatabaseURL.deletingLastPathComponent().path),
              try LedgerPowerSyncKeychain(service: location.databaseKeychainService)
                .loadRecord(key: location.databaseKeychainAccount) == nil,
              try LedgerPowerSyncKeychain(service: location.mediaKeychainService)
                .loadRecord(key: location.mediaKeychainAccount) == nil else {
            throw Failure.cleanupPending
        }
        try store().removeRecord(key: key(request.expectedSummary))
    }

    static func pendingRequest(location: LedgerWorkspaceRuntimeLocation) throws -> SessionEndRequest? {
        guard let saved = try store().loadRecord(key: location.sessionScopeIdentity) else { return nil }
        let intent = try JSONDecoder().decode(Intent.self, from: saved)
        guard intent.workspaceKey == location.databaseKeychainAccount,
              intent.workspaceDirectory == location.structuredDatabaseURL.deletingLastPathComponent(),
              try key(intent.request.expectedSummary) == location.sessionScopeIdentity else {
            throw Failure.intentMismatch
        }
        return intent.request
    }

    private static func requireIntent(_ request: SessionEndRequest, location: LedgerWorkspaceRuntimeLocation) throws {
        guard try key(request.expectedSummary) == location.sessionScopeIdentity else {
            throw Failure.intentMismatch
        }
        guard let saved = try store().loadRecord(key: key(request.expectedSummary)) else {
            throw Failure.missingIntent
        }
        guard try JSONDecoder().decode(Intent.self, from: saved) == Intent(
            request: request, workspaceKey: location.databaseKeychainAccount,
            workspaceDirectory: location.structuredDatabaseURL.deletingLastPathComponent()) else {
            throw Failure.intentMismatch
        }
    }
}
