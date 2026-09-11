import CryptoKit
import Foundation

public enum LedgerEnvironmentKind: String, Codable, CaseIterable, Sendable {
    case targetLocal
    case targetStaging
    case targetProduction
}

public enum LedgerBuildProfile: String, Codable, Sendable {
    case targetLocalDevelopment
    case targetStaging
    case targetProductionArchive

    public var environment: LedgerEnvironmentKind {
        switch self {
        case .targetLocalDevelopment:
            return .targetLocal
        case .targetStaging:
            return .targetStaging
        case .targetProductionArchive:
            return .targetProduction
        }
    }
}

public enum LedgerTargetComponent: String, Codable, CaseIterable, Sendable {
    case auth
    case structuredData
    case powerSync
    case storage
    case mcp
    case telemetry
    case externalRoutes
    case updateFeed
}

public struct LedgerEnvironmentResource: Codable, Equatable, Sendable {
    public let component: LedgerTargetComponent
    public let environment: LedgerEnvironmentKind
    public let publicIdentifier: String

    public init(
        component: LedgerTargetComponent,
        environment: LedgerEnvironmentKind,
        publicIdentifier: String
    ) {
        self.component = component
        self.environment = environment
        self.publicIdentifier = publicIdentifier
    }
}

public struct LedgerContractVersions: Codable, Equatable, Sendable {
    public let schema: String
    public let query: String
    public let operation: String
    public let sync: String

    public init(schema: String, query: String, operation: String, sync: String) {
        self.schema = schema
        self.query = query
        self.operation = operation
        self.sync = sync
    }

    fileprivate func firstMismatch(comparedWith expected: Self) -> String? {
        if schema != expected.schema { return "schema" }
        if query != expected.query { return "query" }
        if operation != expected.operation { return "operation" }
        if sync != expected.sync { return "sync" }
        return nil
    }
}

public struct LedgerEnvironmentManifest: Codable, Equatable, Sendable {
    public let environment: LedgerEnvironmentKind
    public let buildProfile: LedgerBuildProfile
    public let bundleIdentifier: String
    public let displayName: String
    public let localDataNamespacePrefix: String
    public let contractVersions: LedgerContractVersions
    public let resources: [LedgerEnvironmentResource]

    public init(
        environment: LedgerEnvironmentKind,
        buildProfile: LedgerBuildProfile,
        bundleIdentifier: String,
        displayName: String,
        localDataNamespacePrefix: String,
        contractVersions: LedgerContractVersions,
        resources: [LedgerEnvironmentResource]
    ) {
        self.environment = environment
        self.buildProfile = buildProfile
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.localDataNamespacePrefix = localDataNamespacePrefix
        self.contractVersions = contractVersions
        self.resources = resources
    }
}

public struct LedgerEnvironmentPolicy: Sendable {
    public let expectedEnvironment: LedgerEnvironmentKind
    public let expectedBuildProfile: LedgerBuildProfile
    public let expectedBundleIdentifier: String
    public let expectedContractVersions: LedgerContractVersions
    public let allowedResourceIdentifiers: [LedgerTargetComponent: Set<String>]
    public let forbiddenResourceIdentifiers: Set<String>
    public let forbiddenBundleIdentifiers: Set<String>

    public init(
        expectedEnvironment: LedgerEnvironmentKind,
        expectedBuildProfile: LedgerBuildProfile,
        expectedBundleIdentifier: String,
        expectedContractVersions: LedgerContractVersions,
        allowedResourceIdentifiers: [LedgerTargetComponent: Set<String>],
        forbiddenResourceIdentifiers: Set<String>,
        forbiddenBundleIdentifiers: Set<String>
    ) {
        self.expectedEnvironment = expectedEnvironment
        self.expectedBuildProfile = expectedBuildProfile
        self.expectedBundleIdentifier = expectedBundleIdentifier
        self.expectedContractVersions = expectedContractVersions
        self.allowedResourceIdentifiers = allowedResourceIdentifiers
        self.forbiddenResourceIdentifiers = Set(forbiddenResourceIdentifiers.map(Self.normalize))
        self.forbiddenBundleIdentifiers = Set(forbiddenBundleIdentifiers.map(Self.normalize))
    }

    fileprivate static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public enum LedgerEnvironmentValidationFailure: Error, Equatable, Sendable {
    case manifestEnvironmentMismatch
    case buildProfileMismatch
    case bundleIdentityMismatch
    case forbiddenBundleIdentity
    case stagingIdentityMissing
    case missingNamespacePrefix
    case duplicateResource(LedgerTargetComponent)
    case missingResource(LedgerTargetComponent)
    case mixedEnvironment(LedgerTargetComponent)
    case unsafeResourceIdentifier(LedgerTargetComponent)
    case forbiddenResource(LedgerTargetComponent)
    case unexpectedResource(LedgerTargetComponent)
    case policyMissingAllowlist(LedgerTargetComponent)
    case incompatibleContract(String)
    case persistedEnvironmentMismatch
    case missingPrincipal
    case missingAccount

    public var diagnosticCode: String {
        switch self {
        case .manifestEnvironmentMismatch:
            return "target_environment_mismatch"
        case .buildProfileMismatch:
            return "target_build_profile_mismatch"
        case .bundleIdentityMismatch:
            return "target_bundle_identity_mismatch"
        case .forbiddenBundleIdentity:
            return "target_bundle_identity_forbidden"
        case .stagingIdentityMissing:
            return "target_staging_identity_missing"
        case .missingNamespacePrefix:
            return "target_local_namespace_missing"
        case .duplicateResource(let component):
            return "target_resource_duplicate_\(component.rawValue)"
        case .missingResource(let component):
            return "target_resource_missing_\(component.rawValue)"
        case .mixedEnvironment(let component):
            return "target_resource_environment_mismatch_\(component.rawValue)"
        case .unsafeResourceIdentifier(let component):
            return "target_resource_identifier_unsafe_\(component.rawValue)"
        case .forbiddenResource(let component):
            return "target_resource_forbidden_\(component.rawValue)"
        case .unexpectedResource(let component):
            return "target_resource_unexpected_\(component.rawValue)"
        case .policyMissingAllowlist(let component):
            return "target_policy_allowlist_missing_\(component.rawValue)"
        case .incompatibleContract(let contract):
            return "target_contract_incompatible_\(contract)"
        case .persistedEnvironmentMismatch:
            return "target_persisted_environment_mismatch"
        case .missingPrincipal:
            return "target_local_namespace_principal_missing"
        case .missingAccount:
            return "target_local_namespace_account_missing"
        }
    }
}

public struct LedgerEnvironmentDiagnostics: Equatable, Sendable {
    public let environment: LedgerEnvironmentKind
    public let buildProfile: LedgerBuildProfile
    public let bundleIdentifier: String
    public let displayName: String
    public let contractVersions: LedgerContractVersions
    public let publicResourceIdentifiers: [LedgerTargetComponent: String]
}

public struct ValidatedLedgerEnvironment: Sendable {
    public let manifest: LedgerEnvironmentManifest
    private let resourcesByComponent: [LedgerTargetComponent: LedgerEnvironmentResource]

    fileprivate init(
        manifest: LedgerEnvironmentManifest,
        resourcesByComponent: [LedgerTargetComponent: LedgerEnvironmentResource]
    ) {
        self.manifest = manifest
        self.resourcesByComponent = resourcesByComponent
    }

    public var diagnostics: LedgerEnvironmentDiagnostics {
        LedgerEnvironmentDiagnostics(
            environment: manifest.environment,
            buildProfile: manifest.buildProfile,
            bundleIdentifier: manifest.bundleIdentifier,
            displayName: manifest.displayName,
            contractVersions: manifest.contractVersions,
            publicResourceIdentifiers: resourcesByComponent.mapValues(\.publicIdentifier)
        )
    }

    public func resource(_ component: LedgerTargetComponent) -> LedgerEnvironmentResource {
        // Validation proves that every closed component is present exactly once.
        resourcesByComponent[component]!
    }

    public func localDataNamespace(
        principalID: String,
        accountID: String
    ) throws -> LocalDataNamespace {
        let principal = principalID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !principal.isEmpty else {
            throw LedgerEnvironmentValidationFailure.missingPrincipal
        }

        let account = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty else {
            throw LedgerEnvironmentValidationFailure.missingAccount
        }

        let material = [
            manifest.bundleIdentifier,
            manifest.environment.rawValue,
            principal,
            account
        ].joined(separator: "\u{1f}")
        let digest = SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return LocalDataNamespace(
            root: "\(manifest.localDataNamespacePrefix).\(manifest.environment.rawValue).\(digest.prefix(32))"
        )
    }

    public var persistenceBinding: LedgerEnvironmentPersistenceBinding {
        let resourceMaterial = LedgerTargetComponent.allCases.map { component in
            let resource = self.resource(component)
            return [
                component.rawValue,
                resource.environment.rawValue,
                resource.publicIdentifier
            ].joined(separator: "\u{1e}")
        }
        let material = [
            manifest.environment.rawValue,
            manifest.buildProfile.rawValue,
            manifest.bundleIdentifier,
            manifest.localDataNamespacePrefix,
            manifest.contractVersions.schema,
            manifest.contractVersions.query,
            manifest.contractVersions.operation,
            manifest.contractVersions.sync
        ] + resourceMaterial
        let digest = SHA256.hash(data: Data(material.joined(separator: "\u{1f}").utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return LedgerEnvironmentPersistenceBinding(
            environment: manifest.environment,
            bundleIdentifier: manifest.bundleIdentifier,
            manifestDigest: digest
        )
    }
}

public enum LedgerEnvironmentValidator {
    public static func validate(
        _ manifest: LedgerEnvironmentManifest,
        policy: LedgerEnvironmentPolicy
    ) throws -> ValidatedLedgerEnvironment {
        guard manifest.environment == policy.expectedEnvironment else {
            throw LedgerEnvironmentValidationFailure.manifestEnvironmentMismatch
        }
        guard manifest.buildProfile == policy.expectedBuildProfile,
              manifest.buildProfile.environment == manifest.environment else {
            throw LedgerEnvironmentValidationFailure.buildProfileMismatch
        }
        guard manifest.bundleIdentifier == policy.expectedBundleIdentifier else {
            throw LedgerEnvironmentValidationFailure.bundleIdentityMismatch
        }

        let normalizedBundleIdentifier = LedgerEnvironmentPolicy.normalize(manifest.bundleIdentifier)
        guard !policy.forbiddenBundleIdentifiers.contains(normalizedBundleIdentifier) else {
            throw LedgerEnvironmentValidationFailure.forbiddenBundleIdentity
        }

        if manifest.environment == .targetStaging {
            guard manifest.displayName.localizedCaseInsensitiveContains("STAGING") else {
                throw LedgerEnvironmentValidationFailure.stagingIdentityMissing
            }
        }

        guard !manifest.localDataNamespacePrefix
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty else {
            throw LedgerEnvironmentValidationFailure.missingNamespacePrefix
        }

        if let mismatch = manifest.contractVersions.firstMismatch(
            comparedWith: policy.expectedContractVersions
        ) {
            throw LedgerEnvironmentValidationFailure.incompatibleContract(mismatch)
        }

        var resourcesByComponent: [LedgerTargetComponent: LedgerEnvironmentResource] = [:]
        for resource in manifest.resources {
            guard resourcesByComponent[resource.component] == nil else {
                throw LedgerEnvironmentValidationFailure.duplicateResource(resource.component)
            }
            resourcesByComponent[resource.component] = resource
        }

        for component in LedgerTargetComponent.allCases {
            guard let resource = resourcesByComponent[component] else {
                throw LedgerEnvironmentValidationFailure.missingResource(component)
            }
            guard resource.environment == manifest.environment else {
                throw LedgerEnvironmentValidationFailure.mixedEnvironment(component)
            }

            let identifier = resource.publicIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !identifier.isEmpty else {
                throw LedgerEnvironmentValidationFailure.missingResource(component)
            }
            guard isSafePublicIdentifier(identifier) else {
                throw LedgerEnvironmentValidationFailure.unsafeResourceIdentifier(component)
            }

            let normalizedIdentifier = LedgerEnvironmentPolicy.normalize(identifier)
            guard !policy.forbiddenResourceIdentifiers.contains(normalizedIdentifier) else {
                throw LedgerEnvironmentValidationFailure.forbiddenResource(component)
            }
            guard let allowed = policy.allowedResourceIdentifiers[component] else {
                throw LedgerEnvironmentValidationFailure.policyMissingAllowlist(component)
            }
            guard allowed.contains(identifier) else {
                throw LedgerEnvironmentValidationFailure.unexpectedResource(component)
            }
        }

        return ValidatedLedgerEnvironment(
            manifest: manifest,
            resourcesByComponent: resourcesByComponent
        )
    }

    private static func isSafePublicIdentifier(_ identifier: String) -> Bool {
        guard !identifier.contains("?"),
              !identifier.contains("#"),
              !identifier.contains("@") else {
            return false
        }

        let lowercase = identifier.lowercased()
        let secretMarkers = ["access_token", "apikey=", "api_key=", "password=", "secret="]
        return !secretMarkers.contains { lowercase.contains($0) }
    }
}

public enum LocalDataStore: String, CaseIterable, Sendable {
    case database
    case encryptionKey
    case operationQueue
    case attachmentCache
    case keychain
}

public struct LocalDataNamespace: Equatable, Sendable {
    public let root: String

    public func identifier(for store: LocalDataStore) -> String {
        "\(root).\(store.rawValue)"
    }
}

public struct LedgerEnvironmentPersistenceBinding: Codable, Equatable, Sendable {
    public let environment: LedgerEnvironmentKind
    public let bundleIdentifier: String
    public let manifestDigest: String

    public init(
        environment: LedgerEnvironmentKind,
        bundleIdentifier: String,
        manifestDigest: String
    ) {
        self.environment = environment
        self.bundleIdentifier = bundleIdentifier
        self.manifestDigest = manifestDigest
    }
}

public struct PowerSyncEnvironmentDescriptor: Equatable, Sendable {
    public let environment: LedgerEnvironmentKind
    public let publicIdentifier: String
    public let syncContractVersion: String

    public init(validatedEnvironment: ValidatedLedgerEnvironment) {
        let resource = validatedEnvironment.resource(.powerSync)
        environment = resource.environment
        publicIdentifier = resource.publicIdentifier
        syncContractVersion = validatedEnvironment.manifest.contractVersions.sync
    }
}

public struct TargetAppDependencies: Sendable {
    public let environment: ValidatedLedgerEnvironment
    public let powerSync: PowerSyncEnvironmentDescriptor

    public init(environment: ValidatedLedgerEnvironment) {
        self.environment = environment
        powerSync = PowerSyncEnvironmentDescriptor(validatedEnvironment: environment)
    }
}

public enum TargetAppBootstrap {
    public static func start<Dependencies>(
        manifest: LedgerEnvironmentManifest,
        policy: LedgerEnvironmentPolicy,
        makeDependencies: (ValidatedLedgerEnvironment) throws -> Dependencies
    ) throws -> Dependencies {
        let environment = try LedgerEnvironmentValidator.validate(manifest, policy: policy)
        return try makeDependencies(environment)
    }
}

public enum TargetLocalStateBootstrap {
    public static func open<State>(
        manifest: LedgerEnvironmentManifest,
        policy: LedgerEnvironmentPolicy,
        persistedBinding: LedgerEnvironmentPersistenceBinding?,
        openState: (
            ValidatedLedgerEnvironment,
            LedgerEnvironmentPersistenceBinding
        ) throws -> State
    ) throws -> State {
        let environment = try LedgerEnvironmentValidator.validate(
            manifest,
            policy: policy
        )
        let currentBinding = environment.persistenceBinding
        if let persistedBinding, persistedBinding != currentBinding {
            throw LedgerEnvironmentValidationFailure.persistedEnvironmentMismatch
        }
        return try openState(environment, currentBinding)
    }
}
