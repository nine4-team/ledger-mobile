import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetPowerSync

@Suite("Account workspace runtime isolation", .serialized)
struct LedgerWorkspaceRuntimeIsolationTests {
    @Test("Identical validated scope resolves to one stable opaque location")
    func identicalScopeIsStableAndOpaque() throws {
        let environment = try Self.environment()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workspace-location-root", isDirectory: true)
        let principal = try PrincipalID(validating: "..")
        let account = try AccountID(validating: "account:adversarial..")

        let first = try LedgerWorkspaceRuntimeIsolation.resolve(
            validatedEnvironment: environment,
            principalId: principal,
            accountId: account,
            applicationSupportDirectory: root
        )
        let second = try LedgerWorkspaceRuntimeIsolation.resolve(
            validatedEnvironment: environment,
            principalId: principal,
            accountId: account,
            applicationSupportDirectory: root
        )

        #expect(first == second)
        #expect(first.structuredDatabaseURL.standardizedFileURL.path.hasPrefix(
            root.standardizedFileURL.path + "/"
        ))
        #expect(first.structuredDatabaseURL.lastPathComponent == "ledger.sqlite")
        #expect(first.attachmentDatabaseURL.lastPathComponent == "attachments.sqlite")
        #expect(first.mediaVaultRootURL.lastPathComponent == "media")
        #expect(
            first.structuredDatabaseURL.deletingLastPathComponent().lastPathComponent
                .hasPrefix("workspace-")
        )
        #expect(
            first.structuredDatabaseURL.deletingLastPathComponent()
                == first.attachmentDatabaseURL.deletingLastPathComponent()
        )
        #expect(
            first.mediaVaultRootURL.deletingLastPathComponent()
                == first.structuredDatabaseURL.deletingLastPathComponent()
        )
        #expect(!first.structuredDatabaseURL.path.contains(principal.rawValue))
        #expect(!first.structuredDatabaseURL.path.contains(account.rawValue))
        #expect(!first.databaseKeychainAccount.contains(principal.rawValue))
        #expect(!first.databaseKeychainAccount.contains(account.rawValue))
        #expect(!first.mediaKeychainAccount.contains(principal.rawValue))
        #expect(!first.mediaKeychainAccount.contains(account.rawValue))
        #expect(
            first.databaseKeychainService != first.mediaKeychainService
                || first.databaseKeychainAccount != first.mediaKeychainAccount
        )
    }

    @Test("Every persistence-relevant binding and scope change is isolated")
    func persistenceRelevantChangesAreIsolated() throws {
        let root = FileManager.default.temporaryDirectory
        let principal = try PrincipalID(validating: "principal-one")
        let account = try AccountID(validating: "account-one")
        let baselineEnvironment = try Self.environment()
        let baseline = try Self.location(
            baselineEnvironment, principal: principal, account: account, root: root
        )
        let baselineVersions = Self.contractVersions()
        let variations = try [
            Self.environment(environment: .targetStaging),
            Self.environment(bundleIdentifier: "apps.nine4.ledger.alternate"),
            Self.environment(namespacePrefix: "apps.nine4.ledger.target.alternate"),
            Self.environment(contractVersions: LedgerContractVersions(
                schema: "schema-v2",
                query: baselineVersions.query,
                operation: baselineVersions.operation,
                sync: baselineVersions.sync
            )),
            Self.environment(contractVersions: LedgerContractVersions(
                schema: baselineVersions.schema,
                query: "query-v2",
                operation: baselineVersions.operation,
                sync: baselineVersions.sync
            )),
            Self.environment(contractVersions: LedgerContractVersions(
                schema: baselineVersions.schema,
                query: baselineVersions.query,
                operation: "operation-v2",
                sync: baselineVersions.sync
            )),
            Self.environment(contractVersions: LedgerContractVersions(
                schema: baselineVersions.schema,
                query: baselineVersions.query,
                operation: baselineVersions.operation,
                sync: "sync-v2"
            ))
        ]
        for environment in variations {
            try Self.expectIsolated(
                environment, principal: principal, account: account, root: root
            )
        }
        for component in LedgerTargetComponent.allCases {
            let environment = try Self.environment(
                resourceOverrides: [component: "\(component.rawValue)-alternate"]
            )
            try Self.expectIsolated(
                environment, principal: principal, account: account, root: root
            )
        }

        let otherPrincipal = try Self.location(
            baselineEnvironment,
            principal: PrincipalID(validating: "principal-two"),
            account: account,
            root: root
        )
        let otherAccount = try Self.location(
            baselineEnvironment,
            principal: principal,
            account: AccountID(validating: "account-two"),
            root: root
        )
        #expect(otherPrincipal.structuredDatabaseURL != baseline.structuredDatabaseURL)
        #expect(otherAccount.structuredDatabaseURL != baseline.structuredDatabaseURL)
        #expect(otherPrincipal.attachmentDatabaseURL != baseline.attachmentDatabaseURL)
        #expect(otherAccount.attachmentDatabaseURL != baseline.attachmentDatabaseURL)
        #expect(otherPrincipal.mediaVaultRootURL != baseline.mediaVaultRootURL)
        #expect(otherAccount.mediaVaultRootURL != baseline.mediaVaultRootURL)
        #expect(
            otherPrincipal.databaseKeychainService != baseline.databaseKeychainService
                || otherPrincipal.databaseKeychainAccount != baseline.databaseKeychainAccount
        )
        #expect(
            otherAccount.databaseKeychainService != baseline.databaseKeychainService
                || otherAccount.databaseKeychainAccount != baseline.databaseKeychainAccount
        )
        #expect(
            otherPrincipal.mediaKeychainService != baseline.mediaKeychainService
                || otherPrincipal.mediaKeychainAccount != baseline.mediaKeychainAccount
        )
        #expect(
            otherAccount.mediaKeychainService != baseline.mediaKeychainService
                || otherAccount.mediaKeychainAccount != baseline.mediaKeychainAccount
        )

        let dottedFirst = try Self.location(
            baselineEnvironment,
            principal: PrincipalID(validating: "a.b"),
            account: AccountID(validating: "c"),
            root: root
        )
        let dottedSecond = try Self.location(
            baselineEnvironment,
            principal: PrincipalID(validating: "a"),
            account: AccountID(validating: "b.c"),
            root: root
        )
        #expect(dottedFirst.structuredDatabaseURL != dottedSecond.structuredDatabaseURL)
        #expect(dottedFirst.databaseKeychainAccount != dottedSecond.databaseKeychainAccount)
        #expect(dottedFirst.mediaKeychainAccount != dottedSecond.mediaKeychainAccount)

        let displayOnly = try Self.location(
            Self.environment(displayName: "Cosmetic rename only"),
            principal: principal,
            account: account,
            root: root
        )
        #expect(displayOnly == baseline)
    }

    @Test("Invalid namespace fails before key or filesystem side effects")
    func invalidNamespaceFailsBeforeSideEffects() async throws {
        let environment = try Self.environment(namespacePrefix: "../escaped")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "workspace-invalid-\(UUID().uuidString)",
            isDirectory: true
        )
        let recorder = SideEffectRecorder()
        var dependencies = LedgerPowerSyncLocalBootstrapDependencies.live
        dependencies.loadDatabaseKey = { _, _ in
            recorder.keyLoads += 1
            return try Self.key()
        }
        dependencies.loadMediaKeyBytes = { _, _ in
            recorder.keyLoads += 1
            return Data(repeating: 0x6b, count: 32)
        }
        dependencies.createDirectory = { _ in recorder.directoryCreates += 1 }

        do {
            _ = try await LedgerPowerSyncLocalBootstrap.open(
                validatedEnvironment: environment,
                principalId: Self.principalId,
                accountId: Self.accountId,
                applicationSupportDirectory: root,
                dependencies: dependencies
            )
            Issue.record("Expected invalid namespace to refuse bootstrap")
        } catch let failure as LedgerPowerSyncLocalBootstrapFailure {
            #expect(failure.stage == .workspaceLocationResolution)
            #expect(failure.attachmentDatabaseCleanup == .notOpened)
            #expect(failure.structuredDatabaseCleanup == .notOpened)
        }
        #expect(recorder.keyLoads == 0)
        #expect(recorder.directoryCreates == 0)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test("Ordinary close preserves encrypted queued evidence for restart")
    func closeAndRestartPreserveEvidence() async throws {
        let environment = try Self.environment()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "workspace-restart-\(UUID().uuidString)",
            isDirectory: true
        )
        var dependencies = LedgerPowerSyncLocalBootstrapDependencies.live
        dependencies.loadDatabaseKey = { _, _ in try Self.key() }
        dependencies.loadMediaKeyBytes = { _, _ in Data(repeating: 0x6b, count: 32) }
        dependencies.createDirectory = { directory in
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let openRuntime: () async throws -> LedgerOfflineClientRuntime = {
            try await LedgerPowerSyncLocalBootstrap.open(
                validatedEnvironment: environment,
                principalId: Self.principalId,
                accountId: Self.accountId,
                applicationSupportDirectory: root,
                dependencies: dependencies
            )
        }

        let runtime = try await openRuntime()
        _ = try await runtime.createClient(Self.clientCommand())
        #expect(try await runtime.pendingUploadCount() == 1)
        try await runtime.close()

        let location = try Self.location(
            environment,
            principal: Self.principalId,
            account: Self.accountId,
            root: root
        )
        #expect(FileManager.default.fileExists(atPath: location.structuredDatabaseURL.path))
        #expect(FileManager.default.fileExists(atPath: location.attachmentDatabaseURL.path))

        let reopened = try await openRuntime()
        #expect(try await reopened.pendingUploadCount() == 1)
        #expect(!(try await reopened.encryptionCipher()).isEmpty)
        try await reopened.close()
        try FileManager.default.removeItem(at: root)
    }

    private static let principalId = try! PrincipalID(validating: "principal-owner")
    private static let accountId = try! AccountID(validating: "account-primary")

    private static func location(
        _ environment: ValidatedLedgerEnvironment,
        principal: PrincipalID,
        account: AccountID,
        root: URL
    ) throws -> LedgerWorkspaceRuntimeLocation {
        try LedgerWorkspaceRuntimeIsolation.resolve(
            validatedEnvironment: environment,
            principalId: principal,
            accountId: account,
            applicationSupportDirectory: root
        )
    }

    private static func expectIsolated(
        _ changedEnvironment: ValidatedLedgerEnvironment,
        principal: PrincipalID,
        account: AccountID,
        root: URL
    ) throws {
        let baseline = try location(
            Self.environment(), principal: principal, account: account, root: root
        )
        let changed = try location(
            changedEnvironment, principal: principal, account: account, root: root
        )
        #expect(changed.structuredDatabaseURL != baseline.structuredDatabaseURL)
        #expect(changed.attachmentDatabaseURL != baseline.attachmentDatabaseURL)
        #expect(changed.mediaVaultRootURL != baseline.mediaVaultRootURL)
        #expect(
            changed.databaseKeychainService != baseline.databaseKeychainService
                || changed.databaseKeychainAccount != baseline.databaseKeychainAccount
        )
        #expect(
            changed.mediaKeychainService != baseline.mediaKeychainService
                || changed.mediaKeychainAccount != baseline.mediaKeychainAccount
        )
    }

    private static func key() throws -> LedgerPowerSyncEncryptionKey {
        try LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "7a", count: 32))
    }

    private static func clientCommand() throws -> CreateClientCommand {
        try CreateClientCommand(
            operationId: OperationID(validating: "operation-workspace-restart"),
            draft: ClientCreationDraft(
                accountId: accountId,
                actorPrincipalId: principalId,
                operationContractVersion: OperationContractVersion(
                    validating: "client-create-v1"
                ),
                clientId: ClientID(validating: "client-workspace-restart"),
                displayName: ClientDisplayName(validating: "Restart Client"),
                capturedAt: Date(timeIntervalSince1970: 1_788_600_000)
            )
        )
    }

    private static func environment(
        environment: LedgerEnvironmentKind = .targetLocal,
        bundleIdentifier: String = "apps.nine4.ledger.target.local",
        displayName: String = "Ledger Target Local",
        namespacePrefix: String = "apps.nine4.ledger.target",
        contractVersions: LedgerContractVersions? = nil,
        resourceOverrides: [LedgerTargetComponent: String] = [:]
    ) throws -> ValidatedLedgerEnvironment {
        let buildProfile: LedgerBuildProfile = switch environment {
        case .targetLocal: .targetLocalDevelopment
        case .targetStaging: .targetStaging
        case .targetProduction: .targetProductionArchive
        }
        let effectiveDisplayName = environment == .targetStaging
            ? "Ledger STAGING"
            : displayName
        let effectiveContractVersions = contractVersions ?? Self.contractVersions()
        let resourceIdentifiers = Dictionary(
            uniqueKeysWithValues: LedgerTargetComponent.allCases.map {
                ($0, resourceOverrides[$0] ?? "\($0.rawValue)-baseline")
            }
        )
        let manifest = LedgerEnvironmentManifest(
            environment: environment,
            buildProfile: buildProfile,
            bundleIdentifier: bundleIdentifier,
            displayName: effectiveDisplayName,
            localDataNamespacePrefix: namespacePrefix,
            contractVersions: effectiveContractVersions,
            resources: LedgerTargetComponent.allCases.map { component in
                LedgerEnvironmentResource(
                    component: component,
                    environment: environment,
                    publicIdentifier: resourceIdentifiers[component]!
                )
            }
        )
        return try LedgerEnvironmentValidator.validate(
            manifest,
            policy: LedgerEnvironmentPolicy(
                expectedEnvironment: environment,
                expectedBuildProfile: buildProfile,
                expectedBundleIdentifier: bundleIdentifier,
                expectedContractVersions: effectiveContractVersions,
                allowedResourceIdentifiers: resourceIdentifiers.mapValues { [$0] },
                forbiddenResourceIdentifiers: [],
                forbiddenBundleIdentifiers: []
            )
        )
    }

    private static func contractVersions() -> LedgerContractVersions {
        LedgerContractVersions(
            schema: "schema-v1",
            query: "query-v1",
            operation: "operation-v1",
            sync: "sync-v1"
        )
    }
}

private final class SideEffectRecorder: @unchecked Sendable {
    var keyLoads = 0
    var directoryCreates = 0
}
