import CryptoKit
import Foundation
import LedgerTargetCore

public enum LedgerWorkspaceRuntimeIsolationFailure: Error, Equatable, Sendable {
    case invalidLocalDataNamespace
    case invalidApplicationSupportDirectory
}

public struct LedgerWorkspaceRuntimeLocation: Equatable, Sendable {
    public let databaseURL: URL
    public let keychainService: String
    public let keychainAccount: String

    fileprivate init(
        databaseURL: URL,
        keychainService: String,
        keychainAccount: String
    ) {
        self.databaseURL = databaseURL
        self.keychainService = keychainService
        self.keychainAccount = keychainAccount
    }
}

public enum LedgerWorkspaceRuntimeIsolation {
    public static func resolve(
        validatedEnvironment: ValidatedLedgerEnvironment,
        principalId: PrincipalID,
        accountId: AccountID,
        applicationSupportDirectory: URL
    ) throws -> LedgerWorkspaceRuntimeLocation {
        let prefix = validatedEnvironment.manifest.localDataNamespacePrefix
        try validate(namespacePrefix: prefix)

        let root = applicationSupportDirectory.standardizedFileURL
        guard root.isFileURL, root.path.hasPrefix("/") else {
            throw LedgerWorkspaceRuntimeIsolationFailure.invalidApplicationSupportDirectory
        }

        let namespace = try validatedEnvironment.localDataNamespace(
            principalID: principalId.rawValue,
            accountID: accountId.rawValue
        )
        let binding = validatedEnvironment.persistenceBinding
        let material = [
            "ledger-account-workspace-v1",
            namespace.identifier(for: .database),
            binding.environment.rawValue,
            binding.bundleIdentifier,
            binding.manifestDigest,
            principalId.rawValue,
            accountId.rawValue
        ].joined(separator: "\u{1f}")
        let digest = SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let opaqueComponent = "workspace-\(digest.prefix(40))"
        let directory = root
            .appendingPathComponent("LedgerTarget", isDirectory: true)
            .appendingPathComponent(opaqueComponent, isDirectory: true)
            .standardizedFileURL
        guard directory.path.hasPrefix(root.path + "/") else {
            throw LedgerWorkspaceRuntimeIsolationFailure.invalidApplicationSupportDirectory
        }

        return LedgerWorkspaceRuntimeLocation(
            databaseURL: directory.appendingPathComponent("ledger.sqlite"),
            keychainService: "ledger.target.powersync.workspace-key.v1",
            keychainAccount: opaqueComponent
        )
    }

    private static func validate(namespacePrefix: String) throws {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-_.")
        )
        let components = namespacePrefix.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard namespacePrefix == namespacePrefix.trimmingCharacters(
            in: .whitespacesAndNewlines
        ),
        !namespacePrefix.isEmpty,
        namespacePrefix.utf8.count <= 120,
        !namespacePrefix.contains(".."),
        !namespacePrefix.contains("/"),
        !namespacePrefix.contains("\\"),
        namespacePrefix.unicodeScalars.allSatisfy(allowed.contains),
        components.allSatisfy({ !$0.isEmpty }) else {
            throw LedgerWorkspaceRuntimeIsolationFailure.invalidLocalDataNamespace
        }
    }
}
