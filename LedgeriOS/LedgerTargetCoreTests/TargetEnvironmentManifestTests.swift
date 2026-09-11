import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Target Environment Isolation")
struct TargetEnvironmentManifestTests {
    @Test("A complete staging manifest validates and exposes only allowlisted identifiers")
    func validatesStagingManifest() throws {
        let validated = try LedgerEnvironmentValidator.validate(
            Self.stagingManifest(),
            policy: Self.stagingPolicy()
        )

        #expect(validated.manifest.environment == .targetStaging)
        #expect(validated.resource(.powerSync).publicIdentifier == "powersync-staging")
        #expect(validated.diagnostics.displayName == "Ledger STAGING")
        #expect(validated.diagnostics.publicResourceIdentifiers.count == LedgerTargetComponent.allCases.count)
    }

    @Test("A target manifest cannot decode a Firebase runtime kind")
    func firebaseRuntimeKindCannotDecode() {
        var rejected = false
        do {
            _ = try JSONDecoder().decode(
                LedgerEnvironmentKind.self,
                from: Data("\"firebaseProduction\"".utf8)
            )
        } catch {
            rejected = true
        }

        #expect(rejected)
    }

    @Test("A mixed PowerSync environment is rejected before dependencies open")
    func rejectsMixedPowerSyncEnvironmentBeforeBootstrap() {
        var manifest = Self.stagingManifest()
        manifest = Self.replacingResource(
            .powerSync,
            in: manifest,
            with: LedgerEnvironmentResource(
                component: .powerSync,
                environment: .targetProduction,
                publicIdentifier: "powersync-staging"
            )
        )
        var dependencyFactoryCalls = 0

        let failure = Self.captureFailure {
            _ = try TargetAppBootstrap.start(manifest: manifest, policy: Self.stagingPolicy()) {
                dependencyFactoryCalls += 1
                return TargetAppDependencies(environment: $0)
            }
        }

        #expect(failure == .mixedEnvironment(.powerSync))
        #expect(dependencyFactoryCalls == 0)
    }

    @Test("Staging refuses every known Firebase production identifier")
    func rejectsFirebaseProductionIdentifier() {
        var manifest = Self.stagingManifest()
        manifest = Self.replacingResource(
            .structuredData,
            in: manifest,
            with: LedgerEnvironmentResource(
                component: .structuredData,
                environment: .targetStaging,
                publicIdentifier: "ledger-nine4"
            )
        )

        let failure = Self.captureFailure {
            _ = try LedgerEnvironmentValidator.validate(manifest, policy: Self.stagingPolicy())
        }

        #expect(failure == .forbiddenResource(.structuredData))
        #expect(failure?.diagnosticCode == "target_resource_forbidden_structuredData")
        #expect(!(failure?.diagnosticCode.contains("ledger-nine4") ?? true))
    }

    @Test("Staging cannot reuse the production bundle identity")
    func rejectsProductionBundleIdentity() {
        let source = Self.stagingManifest()
        let manifest = LedgerEnvironmentManifest(
            environment: source.environment,
            buildProfile: source.buildProfile,
            bundleIdentifier: "apps.nine4.ledger",
            displayName: source.displayName,
            localDataNamespacePrefix: source.localDataNamespacePrefix,
            contractVersions: source.contractVersions,
            resources: source.resources
        )
        let policy = LedgerEnvironmentPolicy(
            expectedEnvironment: .targetStaging,
            expectedBuildProfile: .targetStaging,
            expectedBundleIdentifier: "apps.nine4.ledger",
            expectedContractVersions: Self.contractVersions,
            allowedResourceIdentifiers: Self.allowedResources,
            forbiddenResourceIdentifiers: Self.productionResourceIdentifiers,
            forbiddenBundleIdentifiers: ["apps.nine4.ledger"]
        )

        let failure = Self.captureFailure {
            _ = try LedgerEnvironmentValidator.validate(manifest, policy: policy)
        }

        #expect(failure == .forbiddenBundleIdentity)
    }

    @Test("Staging must be unmistakable in its compiled display identity")
    func requiresStagingDisplayIdentity() {
        let source = Self.stagingManifest()
        let manifest = LedgerEnvironmentManifest(
            environment: source.environment,
            buildProfile: source.buildProfile,
            bundleIdentifier: source.bundleIdentifier,
            displayName: "Ledger",
            localDataNamespacePrefix: source.localDataNamespacePrefix,
            contractVersions: source.contractVersions,
            resources: source.resources
        )

        let failure = Self.captureFailure {
            _ = try LedgerEnvironmentValidator.validate(manifest, policy: Self.stagingPolicy())
        }

        #expect(failure == .stagingIdentityMissing)
    }

    @Test("Contract version mismatch fails closed")
    func rejectsIncompatibleSyncContract() {
        let source = Self.stagingManifest()
        let manifest = LedgerEnvironmentManifest(
            environment: source.environment,
            buildProfile: source.buildProfile,
            bundleIdentifier: source.bundleIdentifier,
            displayName: source.displayName,
            localDataNamespacePrefix: source.localDataNamespacePrefix,
            contractVersions: LedgerContractVersions(
                schema: "1",
                query: "1",
                operation: "1",
                sync: "outdated"
            ),
            resources: source.resources
        )

        let failure = Self.captureFailure {
            _ = try LedgerEnvironmentValidator.validate(manifest, policy: Self.stagingPolicy())
        }

        #expect(failure == .incompatibleContract("sync"))
    }

    @Test("Unsafe resource identifiers never reach diagnostics")
    func rejectsSensitiveResourceIdentifier() {
        var manifest = Self.stagingManifest()
        manifest = Self.replacingResource(
            .mcp,
            in: manifest,
            with: LedgerEnvironmentResource(
                component: .mcp,
                environment: .targetStaging,
                publicIdentifier: "https://mcp.staging.invalid?access_token=do-not-log"
            )
        )

        let failure = Self.captureFailure {
            _ = try LedgerEnvironmentValidator.validate(manifest, policy: Self.stagingPolicy())
        }

        #expect(failure == .unsafeResourceIdentifier(.mcp))
        #expect(!(failure?.diagnosticCode.contains("do-not-log") ?? true))
    }

    @Test("Local state namespaces survive restart without sharing identities")
    func localNamespacesAreStableAndIsolated() throws {
        let validated = try LedgerEnvironmentValidator.validate(
            Self.stagingManifest(),
            policy: Self.stagingPolicy()
        )

        let first = try validated.localDataNamespace(principalID: "principal-a", accountID: "account-a")
        let afterRestart = try validated.localDataNamespace(principalID: "principal-a", accountID: "account-a")
        let otherPrincipal = try validated.localDataNamespace(principalID: "principal-b", accountID: "account-a")
        let otherAccount = try validated.localDataNamespace(principalID: "principal-a", accountID: "account-b")

        #expect(first == afterRestart)
        #expect(first != otherPrincipal)
        #expect(first != otherAccount)
        #expect(!first.root.contains("principal-a"))
        #expect(!first.root.contains("account-a"))
        #expect(Set(LocalDataStore.allCases.map(first.identifier(for:))).count == LocalDataStore.allCases.count)
    }

    @Test("Local namespace requires both principal and account")
    func localNamespaceRejectsMissingIdentity() throws {
        let validated = try LedgerEnvironmentValidator.validate(
            Self.stagingManifest(),
            policy: Self.stagingPolicy()
        )

        let principalFailure = Self.captureFailure {
            _ = try validated.localDataNamespace(principalID: " ", accountID: "account-a")
        }
        let accountFailure = Self.captureFailure {
            _ = try validated.localDataNamespace(principalID: "principal-a", accountID: "\n")
        }

        #expect(principalFailure == .missingPrincipal)
        #expect(accountFailure == .missingAccount)
    }

    @Test("A stale persisted environment is rejected without opening or changing local bytes")
    func stalePersistedEnvironmentPreservesLocalBytes() throws {
        let validated = try LedgerEnvironmentValidator.validate(
            Self.stagingManifest(),
            policy: Self.stagingPolicy()
        )
        let staleBinding = LedgerEnvironmentPersistenceBinding(
            environment: .targetProduction,
            bundleIdentifier: "apps.nine4.ledger",
            manifestDigest: validated.persistenceBinding.manifestDigest
        )
        let existingBytes = Data("retained-encrypted-local-state".utf8)
        var bytesAfterAttempt = existingBytes
        var openCalls = 0

        let failure = Self.captureFailure {
            _ = try TargetLocalStateBootstrap.open(
                manifest: Self.stagingManifest(),
                policy: Self.stagingPolicy(),
                persistedBinding: staleBinding
            ) { _, _ in
                openCalls += 1
                bytesAfterAttempt.removeAll()
                return "opened"
            }
        }

        #expect(failure == .persistedEnvironmentMismatch)
        #expect(failure?.diagnosticCode == "target_persisted_environment_mismatch")
        #expect(openCalls == 0)
        #expect(bytesAfterAttempt == existingBytes)
    }

    @Test("The matching persisted binding reopens the same isolated state")
    func matchingPersistedEnvironmentReopensState() throws {
        let validated = try LedgerEnvironmentValidator.validate(
            Self.stagingManifest(),
            policy: Self.stagingPolicy()
        )
        var openedBinding: LedgerEnvironmentPersistenceBinding?

        let result = try TargetLocalStateBootstrap.open(
            manifest: Self.stagingManifest(),
            policy: Self.stagingPolicy(),
            persistedBinding: validated.persistenceBinding
        ) { environment, binding in
            openedBinding = binding
            return environment.manifest.displayName
        }

        #expect(result == "Ledger STAGING")
        #expect(openedBinding == validated.persistenceBinding)
    }

    private static let contractVersions = LedgerContractVersions(
        schema: "1",
        query: "1",
        operation: "1",
        sync: "1"
    )

    private static let allowedResources: [LedgerTargetComponent: Set<String>] = [
        .auth: ["auth-staging"],
        .structuredData: ["supabase-staging"],
        .powerSync: ["powersync-staging"],
        .storage: ["storage-staging"],
        .mcp: ["mcp-staging"],
        .telemetry: ["telemetry-staging"],
        .externalRoutes: ["routes-staging"],
        .updateFeed: ["updates-staging"]
    ]

    private static let productionResourceIdentifiers: Set<String> = [
        "ledger-nine4",
        "ledger-nine4.firebasestorage.app",
        "supabase-production",
        "powersync-production",
        "storage-production",
        "mcp-production"
    ]

    private static func stagingManifest() -> LedgerEnvironmentManifest {
        LedgerEnvironmentManifest(
            environment: .targetStaging,
            buildProfile: .targetStaging,
            bundleIdentifier: "apps.nine4.ledger.staging",
            displayName: "Ledger STAGING",
            localDataNamespacePrefix: "apps.nine4.ledger.target",
            contractVersions: contractVersions,
            resources: LedgerTargetComponent.allCases.map { component in
                LedgerEnvironmentResource(
                    component: component,
                    environment: .targetStaging,
                    publicIdentifier: allowedResources[component]!.first!
                )
            }
        )
    }

    private static func stagingPolicy() -> LedgerEnvironmentPolicy {
        LedgerEnvironmentPolicy(
            expectedEnvironment: .targetStaging,
            expectedBuildProfile: .targetStaging,
            expectedBundleIdentifier: "apps.nine4.ledger.staging",
            expectedContractVersions: contractVersions,
            allowedResourceIdentifiers: allowedResources,
            forbiddenResourceIdentifiers: productionResourceIdentifiers,
            forbiddenBundleIdentifiers: ["apps.nine4.ledger"]
        )
    }

    private static func replacingResource(
        _ component: LedgerTargetComponent,
        in manifest: LedgerEnvironmentManifest,
        with replacement: LedgerEnvironmentResource
    ) -> LedgerEnvironmentManifest {
        LedgerEnvironmentManifest(
            environment: manifest.environment,
            buildProfile: manifest.buildProfile,
            bundleIdentifier: manifest.bundleIdentifier,
            displayName: manifest.displayName,
            localDataNamespacePrefix: manifest.localDataNamespacePrefix,
            contractVersions: manifest.contractVersions,
            resources: manifest.resources.map { resource in
                resource.component == component ? replacement : resource
            }
        )
    }

    private static func captureFailure(_ operation: () throws -> Void) -> LedgerEnvironmentValidationFailure? {
        do {
            try operation()
            return nil
        } catch let failure as LedgerEnvironmentValidationFailure {
            return failure
        } catch {
            return nil
        }
    }
}
