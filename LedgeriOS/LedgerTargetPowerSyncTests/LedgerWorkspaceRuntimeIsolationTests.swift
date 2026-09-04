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
        #expect(first.databaseURL.standardizedFileURL.path.hasPrefix(
            root.standardizedFileURL.path + "/"
        ))
        #expect(first.databaseURL.lastPathComponent == "ledger.sqlite")
        #expect(first.databaseURL.deletingLastPathComponent().lastPathComponent.hasPrefix("workspace-"))
        #expect(!first.databaseURL.path.contains(principal.rawValue))
        #expect(!first.databaseURL.path.contains(account.rawValue))
        #expect(!first.keychainAccount.contains(principal.rawValue))
        #expect(!first.keychainAccount.contains(account.rawValue))
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
        #expect(otherPrincipal.databaseURL != baseline.databaseURL)
        #expect(otherAccount.databaseURL != baseline.databaseURL)
        #expect(
            otherPrincipal.keychainService != baseline.keychainService
                || otherPrincipal.keychainAccount != baseline.keychainAccount
        )
        #expect(
            otherAccount.keychainService != baseline.keychainService
                || otherAccount.keychainAccount != baseline.keychainAccount
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
        #expect(dottedFirst.databaseURL != dottedSecond.databaseURL)
        #expect(dottedFirst.keychainAccount != dottedSecond.keychainAccount)

        let displayOnly = try Self.location(
            Self.environment(displayName: "Cosmetic rename only"),
            principal: principal,
            account: account,
            root: root
        )
        #expect(displayOnly == baseline)
    }

    @Test("Invalid namespace fails before key or filesystem side effects")
    func invalidNamespaceFailsBeforeSideEffects() throws {
        let environment = try Self.environment(namespacePrefix: "../escaped")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "workspace-invalid-\(UUID().uuidString)",
            isDirectory: true
        )
        let recorder = SideEffectRecorder()

        #expect(throws: LedgerWorkspaceRuntimeIsolationFailure.invalidLocalDataNamespace) {
            try LedgerPowerSyncLocalBootstrap.open(
                validatedEnvironment: environment,
                principalId: Self.principalId,
                accountId: Self.accountId,
                applicationSupportDirectory: root,
                loadOrCreateKey: { _, _ in
                    recorder.keyLoads += 1
                    return try Self.key()
                },
                createDirectory: { _ in recorder.directoryCreates += 1 }
            )
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
        let openRuntime = {
            try LedgerPowerSyncLocalBootstrap.open(
                validatedEnvironment: environment,
                principalId: Self.principalId,
                accountId: Self.accountId,
                applicationSupportDirectory: root,
                loadOrCreateKey: { _, _ in try Self.key() },
                createDirectory: { directory in
                    try FileManager.default.createDirectory(
                        at: directory,
                        withIntermediateDirectories: true
                    )
                }
            )
        }

        let runtime = try openRuntime()
        _ = try await runtime.createClient(Self.clientCommand())
        #expect(try await runtime.pendingUploadCount() == 1)
        try await runtime.close()

        let location = try Self.location(
            environment,
            principal: Self.principalId,
            account: Self.accountId,
            root: root
        )
        #expect(FileManager.default.fileExists(atPath: location.databaseURL.path))

        let reopened = try openRuntime()
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
        #expect(changed.databaseURL != baseline.databaseURL)
        #expect(
            changed.keychainService != baseline.keychainService
                || changed.keychainAccount != baseline.keychainAccount
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
