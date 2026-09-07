import CryptoKit
import Foundation
import LedgerTargetCore
import Security

enum LedgerWorkspaceRemovalFailure: Error {
    case removed
    case unavailable
}

/// Device-local, monotonic denial outside the Account databases. There is no
/// clearing API: cached membership and normal bootstrap cannot undo removal.
enum LedgerWorkspaceRemovalRegistry {
    static func identity(
        environment: LedgerEnvironmentKind, principalId: PrincipalID, accountId: AccountID
    ) throws -> String {
        // Do not include a manifest digest or database path: a configuration
        // update must not make the same removed Account reopenable.
        let bytes = try JSONEncoder().encode([
            environment.rawValue, principalId.rawValue, accountId.rawValue
        ])
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    static func requireNotRemoved(
        environment: LedgerEnvironmentKind, principalId: PrincipalID, accountId: AccountID
    ) throws {
        let key = try identity(environment: environment, principalId: principalId, accountId: accountId)
        if try contains(key) { throw LedgerWorkspaceRemovalFailure.removed }
    }

    static func recordRemoval(
        environment: LedgerEnvironmentKind, principalId: PrincipalID, accountId: AccountID
    ) throws {
        let key = try identity(environment: environment, principalId: principalId, accountId: accountId)
        var query = baseQuery(key)
        query[kSecValueData as String] = marker
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem, try contains(key) { return }
        guard status == errSecSuccess else { throw LedgerWorkspaceRemovalFailure.unavailable }
    }

    private static let marker = Data("ledger-account-removed-v1".utf8)

    private static func contains(_ key: String) throws -> Bool {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess, let value = result as? Data, value == marker else {
            throw LedgerWorkspaceRemovalFailure.unavailable
        }
        return true
    }

    private static func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ledger.target.workspace-removal.v1",
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: false
        ]
    }
}
