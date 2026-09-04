import Foundation
import Security

public enum LedgerPowerSyncKeychainFailure: Error, Equatable, Sendable {
    case invalidNamespace
    case invalidStoredKey
    case randomGenerationFailed(OSStatus)
    case keychainReadFailed(OSStatus)
    case keychainWriteFailed(OSStatus)
}

public struct LedgerPowerSyncKeychain: Sendable {
    private let service: String

    public init(service: String) throws {
        guard !service.isEmpty, service.utf8.count <= 200 else {
            throw LedgerPowerSyncKeychainFailure.invalidNamespace
        }
        self.service = service
    }

    public func loadOrCreateKey(principalNamespace: String) throws -> LedgerPowerSyncEncryptionKey {
        guard !principalNamespace.isEmpty, principalNamespace.utf8.count <= 256 else {
            throw LedgerPowerSyncKeychainFailure.invalidNamespace
        }
        if let existing = try read(principalNamespace: principalNamespace) {
            return try decode(existing)
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        let randomStatus = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard randomStatus == errSecSuccess else {
            throw LedgerPowerSyncKeychainFailure.randomGenerationFailed(randomStatus)
        }
        let data = Data(bytes)
        let addStatus = SecItemAdd(baseQuery(principalNamespace: principalNamespace)
            .merging([
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]) { _, replacement in replacement } as CFDictionary, nil)

        if addStatus == errSecDuplicateItem,
           let racedValue = try read(principalNamespace: principalNamespace) {
            return try decode(racedValue)
        }
        guard addStatus == errSecSuccess else {
            throw LedgerPowerSyncKeychainFailure.keychainWriteFailed(addStatus)
        }
        return try decode(data)
    }

    private func read(principalNamespace: String) throws -> Data? {
        var query = baseQuery(principalNamespace: principalNamespace)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw LedgerPowerSyncKeychainFailure.keychainReadFailed(status)
        }
        return data
    }

    private func decode(_ data: Data) throws -> LedgerPowerSyncEncryptionKey {
        guard data.count == 32 else {
            throw LedgerPowerSyncKeychainFailure.invalidStoredKey
        }
        return try LedgerPowerSyncEncryptionKey(
            hexadecimal: data.map { String(format: "%02x", $0) }.joined()
        )
    }

    private func baseQuery(principalNamespace: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: principalNamespace
        ]
    }
}
