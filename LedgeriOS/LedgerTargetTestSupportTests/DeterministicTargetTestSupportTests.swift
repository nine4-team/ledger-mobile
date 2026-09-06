import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetTestSupport

@Suite("Deterministic Target Test Support")
struct DeterministicTargetTestSupportTests {
    @Test("Synthetic context, values, and port adapters are exact")
    func deterministicContextValuesAndAdapters() async throws {
        let scenario = try Self.scenario()
        let key = try DeterministicFixtureKey(validating: "project_fixture")

        #expect(scenario.context.manifest.environment == .targetStaging)
        #expect(scenario.context.principalId.rawValue == "test-principal-a")
        #expect(
            try scenario.valueSource.timestamp(key: key, index: 2) ==
            scenario.valueSource.timestamp(key: key, index: 2)
        )
        #expect(
            try scenario.valueSource.operationId(key: key, index: 2) ==
            scenario.valueSource.operationId(key: key, index: 2)
        )
        #expect(
            try scenario.valueSource.operationId(key: key, index: 2).rawValue !=
            scenario.valueSource.entityId(key: key, index: 2).rawValue
        )
        #expect(
            try scenario.valueSource.revision(key: key, index: 2) <
            scenario.valueSource.revision(key: key, index: 3)
        )

        let operationValues = try await Self.collect(
            scenario.operationQueryAdapter().watchOperation(
                scenario.operationScripts[0].operationId
            )
        )
        let unresolvedValues = try await Self.collect(
            scenario.operationQueryAdapter().watchUnresolvedOperations(
                accountId: scenario.context.accountId
            )
        )
        let healthValues = await Self.collect(
            scenario.syncHealthAdapter().observeHealth()
        )

        #expect(operationValues == scenario.operationScripts[0].snapshots)
        #expect(unresolvedValues == scenario.unresolvedOperationScript.snapshots)
        #expect(healthValues == scenario.healthSnapshots)
        #expect(!healthValues[0].isOnline)
        #expect(healthValues[0].isSynchronized)
        #expect(healthValues[1].isOnline)
        #expect(!healthValues[1].isSynchronized)
        #expect(healthValues[1].writeBlock == .clientUpdateRequired)
        #expect(healthValues[2].writeBlock == .maintenance)

        try await scenario.syncHealthAdapter().waitForLocalDurability(
            of: scenario.operationScripts[0].operationId
        )
    }

    @Test("Canonical evidence survives restart and input reordering")
    func canonicalRestartAndReordering() async throws {
        let first = try Self.scenario(reverseTopLevelInput: false)
        let reordered = try Self.scenario(reverseTopLevelInput: true)
        let firstBytes = try first.canonicalEvidence()
        let reorderedBytes = try reordered.canonicalEvidence()
        let restored = try DeterministicTargetScenario.restore(
            from: firstBytes,
            policy: Self.stagingPolicy()
        )

        #expect(first == reordered)
        #expect(firstBytes == reorderedBytes)
        #expect(restored == first)
        #expect(try restored.canonicalEvidence() == firstBytes)

        let operationValues = try await Self.collect(
            restored.operationQueryAdapter().watchOperation(
                restored.operationScripts[0].operationId
            )
        )
        let healthValues = await Self.collect(
            restored.syncHealthAdapter().observeHealth()
        )
        #expect(operationValues == first.operationScripts[0].snapshots)
        #expect(healthValues == first.healthSnapshots)
    }

    @Test("Unsafe, ambiguous, exhausted, and tampered fixtures fail atomically")
    func rejectsUnsafeAndInvalidFixtures() async throws {
        let productionContextFailure = Self.captureFailure {
            _ = try DeterministicTargetTestContext.make(
                manifest: Self.manifest(environment: .targetProduction),
                policy: Self.policy(environment: .targetProduction),
                principalId: try PrincipalID(validating: "test-principal-a"),
                accountId: try AccountID(validating: "test-account-a"),
                scenarioId: try DeterministicTargetScenarioID(
                    validating: "test-scenario-production"
                ),
                seed: 7,
                baseTimeMilliseconds: Self.t0Milliseconds
            )
        }
        let nonSyntheticIdentityFailure = Self.captureFailure {
            _ = try DeterministicTargetTestContext.make(
                manifest: Self.stagingManifest(),
                policy: Self.stagingPolicy(),
                principalId: try PrincipalID(validating: "principal-user"),
                accountId: try AccountID(validating: "test-account-a"),
                scenarioId: try DeterministicTargetScenarioID(
                    validating: "test-scenario-main"
                ),
                seed: 7,
                baseTimeMilliseconds: Self.t0Milliseconds
            )
        }
        let unsafeResource = "https://mcp.test.staging.invalid?access_token=redacted"
        let unsafeManifest = Self.replacingResource(
            .mcp,
            in: Self.stagingManifest(),
            identifier: unsafeResource
        )
        let unsafePolicy = Self.policy(
            environment: .targetStaging,
            manifestOverride: unsafeManifest
        )
        let unsafeEnvironmentFailure = Self.captureEnvironmentFailure {
            _ = try DeterministicTargetTestContext.make(
                manifest: unsafeManifest,
                policy: unsafePolicy,
                principalId: try PrincipalID(validating: "test-principal-a"),
                accountId: try AccountID(validating: "test-account-a"),
                scenarioId: try DeterministicTargetScenarioID(
                    validating: "test-scenario-unsafe"
                ),
                seed: 7,
                baseTimeMilliseconds: Self.t0Milliseconds
            )
        }

        let scenario = try Self.scenario()
        let key = try DeterministicFixtureKey(validating: "project_fixture")
        let exhaustedFailure = Self.captureFailure {
            _ = try scenario.valueSource.operationId(key: key, index: 9)
        }
        let duplicateFailure = Self.captureFailure {
            _ = try DeterministicTargetScenario(
                context: scenario.context,
                valueSource: scenario.valueSource,
                operationScripts: [
                    scenario.operationScripts[0],
                    scenario.operationScripts[0]
                ],
                unresolvedOperationScript: scenario.unresolvedOperationScript,
                healthSnapshots: scenario.healthSnapshots,
                durabilityOutcomes: [
                    scenario.durabilityOutcomes[0],
                    scenario.durabilityOutcomes[0]
                ]
            )
        }
        let nonMonotonicFailure = Self.captureFailure {
            let source = scenario.operationScripts[0]
            _ = try ScriptedOperationSequence(
                operationId: source.operationId,
                accountId: source.accountId,
                snapshots: Array(source.snapshots.reversed())
            )
        }

        let bytes = try scenario.canonicalEvidence()
        let nonCanonicalFailure = Self.captureFailure {
            _ = try DeterministicTargetScenario.restore(
                from: bytes + Data(" ".utf8),
                policy: Self.stagingPolicy()
            )
        }
        var json = try #require(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        )
        json["contentDigest"] = String(repeating: "0", count: 64)
        let tampered = try JSONSerialization.data(
            withJSONObject: json,
            options: [.sortedKeys]
        )
        let tamperFailure = Self.captureFailure {
            _ = try DeterministicTargetScenario.restore(
                from: tampered,
                policy: Self.stagingPolicy()
            )
        }
        let oversizedFailure = Self.captureFailure {
            _ = try DeterministicTargetScenario.restore(
                from: Data(
                    repeating: 0,
                    count: DeterministicTargetScenario.maximumCanonicalEvidenceBytes + 1
                ),
                policy: Self.stagingPolicy()
            )
        }

        let otherAccount = try AccountID(validating: "test-account-b")
        let crossAccountFailure = await Self.captureAsyncFailure {
            _ = try await Self.collect(
                scenario.operationQueryAdapter().watchUnresolvedOperations(
                    accountId: otherAccount
                )
            )
        }

        #expect(productionContextFailure == .productionEnvironment)
        #expect(
            nonSyntheticIdentityFailure == .nonSyntheticIdentifier(kind: "principal")
        )
        #expect(unsafeEnvironmentFailure == .unsafeResourceIdentifier(.mcp))
        #expect(!(unsafeEnvironmentFailure?.diagnosticCode.contains("redacted") ?? true))
        #expect(
            exhaustedFailure == .valueScheduleExhausted(
                domain: "operation_id",
                index: 9
            )
        )
        #expect(duplicateFailure == .duplicateScript(kind: "operation"))
        #expect(
            nonMonotonicFailure == .nonMonotonicScript(kind: "operation_updates")
        )
        #expect(nonCanonicalFailure == .nonCanonicalEvidence)
        #expect(tamperFailure == .evidenceDigestMismatch)
        #expect(
            oversizedFailure == .evidenceTooLarge(
                actual: DeterministicTargetScenario.maximumCanonicalEvidenceBytes + 1,
                maximum: DeterministicTargetScenario.maximumCanonicalEvidenceBytes
            )
        )
        #expect(crossAccountFailure == .crossAccountAccess)
    }

    @Test("Finite scripts expose local, authoritative, retry, and rejection truth")
    func useCaseFailureAndReadinessStories() async throws {
        let scenario = try Self.scenario()
        let adapter = scenario.operationQueryAdapter()
        let rejectedScript = try #require(
            scenario.operationScripts.first(where: {
                if case .failure = $0.terminal { return true }
                return false
            })
        )

        var rejectedValues: [OperationSnapshot] = []
        var terminalFailure: DeterministicTargetTestFailure?
        do {
            for try await value in adapter.watchOperation(rejectedScript.operationId) {
                rejectedValues.append(value)
            }
        } catch let failure as DeterministicTargetTestFailure {
            terminalFailure = failure
        }

        let durabilityFailure = await Self.captureAsyncFailure {
            try await scenario.syncHealthAdapter().waitForLocalDurability(
                of: rejectedScript.operationId
            )
        }
        let missingFailure = await Self.captureAsyncFailure {
            _ = try await Self.collect(
                adapter.watchOperation(
                    try OperationID(validating: "test-op-missing")
                )
            )
        }

        #expect(rejectedValues == rejectedScript.snapshots)
        #expect(rejectedValues.first?.state.phase == .queued)
        #expect(rejectedValues.last?.state.phase == .rejected)
        #expect(terminalFailure?.diagnosticCode == "test_support_scripted_contract_conflict")
        #expect(durabilityFailure?.diagnosticCode == "test_support_scripted_local_write_failed")
        #expect(missingFailure == .missingScript(kind: "operation"))
        #expect(scenario.healthSnapshots.map(\.writeBlock) == [
            .none,
            .clientUpdateRequired,
            .maintenance
        ])
    }

    private static let t0Milliseconds: Int64 = 1_700_000_000_000
    private static let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private static let t1 = Date(timeIntervalSince1970: 1_700_000_001)
    private static let t2 = Date(timeIntervalSince1970: 1_700_000_002)
    private static let t3 = Date(timeIntervalSince1970: 1_700_000_003)

    private static func scenario(
        reverseTopLevelInput: Bool = false
    ) throws -> DeterministicTargetScenario {
        let context = try DeterministicTargetTestContext.make(
            manifest: Self.stagingManifest(resourcesReversed: reverseTopLevelInput),
            policy: Self.stagingPolicy(),
            principalId: try PrincipalID(validating: "test-principal-a"),
            accountId: try AccountID(validating: "test-account-a"),
            scenarioId: try DeterministicTargetScenarioID(
                validating: "test-scenario-main"
            ),
            seed: 42,
            baseTimeMilliseconds: Self.t0Milliseconds
        )
        let valueSource = try DeterministicTargetValueSource(
            context: context,
            maximumIndex: 8,
            stepMilliseconds: 1_000,
            startingRevision: 10
        )
        let contractVersion = try OperationContractVersion(
            validating: "operation-test-v1"
        )
        let appliedOperation = try OperationID(validating: "test-op-applied")
        let rejectedOperation = try OperationID(validating: "test-op-rejected")
        let appliedSnapshots = try Self.appliedSnapshots(
            operationId: appliedOperation,
            accountId: context.accountId,
            contractVersion: contractVersion
        )
        let rejectedSnapshots = try Self.rejectedSnapshots(
            operationId: rejectedOperation,
            accountId: context.accountId,
            contractVersion: contractVersion
        )
        let scripts = [
            try ScriptedOperationSequence(
                operationId: appliedOperation,
                accountId: context.accountId,
                snapshots: appliedSnapshots
            ),
            try ScriptedOperationSequence(
                operationId: rejectedOperation,
                accountId: context.accountId,
                snapshots: rejectedSnapshots,
                terminal: .failure(
                    try Self.error(
                        code: "contract_conflict",
                        category: .conflict,
                        retry: .afterUserCorrection
                    )
                )
            )
        ]
        let unresolved = try ScriptedUnresolvedOperationSequence(
            accountId: context.accountId,
            snapshots: [
                [appliedSnapshots[0]],
                [rejectedSnapshots[1]]
            ]
        )
        let durability = [
            ScriptedDurabilityOutcome(
                operationId: appliedOperation,
                result: .durable
            ),
            ScriptedDurabilityOutcome(
                operationId: rejectedOperation,
                result: .failure(
                    try Self.error(
                        code: "local_write_failed",
                        category: .transientInfrastructure,
                        retry: .automatic
                    )
                )
            )
        ]

        return try DeterministicTargetScenario(
            context: context,
            valueSource: valueSource,
            operationScripts: reverseTopLevelInput ? Array(scripts.reversed()) : scripts,
            unresolvedOperationScript: unresolved,
            healthSnapshots: try Self.healthSnapshots(),
            durabilityOutcomes: reverseTopLevelInput ? Array(durability.reversed()) : durability
        )
    }

    private static func appliedSnapshots(
        operationId: OperationID,
        accountId: AccountID,
        contractVersion: OperationContractVersion
    ) throws -> [OperationSnapshot] {
        let fingerprint = try OperationFingerprint(
            validating: String(repeating: "a", count: 64)
        )
        return [
            OperationSnapshot(
                operationId: operationId,
                accountId: accountId,
                contractVersion: contractVersion,
                fingerprint: fingerprint,
                acceptedAt: t0,
                updatedAt: t0,
                state: .queued(attemptCount: 0, lastTransientError: nil)
            ),
            OperationSnapshot(
                operationId: operationId,
                accountId: accountId,
                contractVersion: contractVersion,
                fingerprint: fingerprint,
                acceptedAt: t0,
                updatedAt: t1,
                state: .applying(attempt: 1, startedAt: t1)
            ),
            OperationSnapshot(
                operationId: operationId,
                accountId: accountId,
                contractVersion: contractVersion,
                fingerprint: fingerprint,
                acceptedAt: t0,
                updatedAt: t3,
                state: .applied(
                    AppliedOperationResult(
                        resultCode: try ApplicationResultCode(
                            validating: "project_updated"
                        ),
                        serverReceivedAt: t2,
                        completedAt: t3
                    )
                )
            )
        ]
    }

    private static func rejectedSnapshots(
        operationId: OperationID,
        accountId: AccountID,
        contractVersion: OperationContractVersion
    ) throws -> [OperationSnapshot] {
        let fingerprint = try OperationFingerprint(
            validating: String(repeating: "b", count: 64)
        )
        let rejection = OperationRejection(
            error: try Self.error(
                code: "authorization_denied",
                category: .authorization,
                retry: .never
            ),
            rejectedAt: t2
        )
        return [
            OperationSnapshot(
                operationId: operationId,
                accountId: accountId,
                contractVersion: contractVersion,
                fingerprint: fingerprint,
                acceptedAt: t1,
                updatedAt: t1,
                state: .queued(attemptCount: 0, lastTransientError: nil)
            ),
            OperationSnapshot(
                operationId: operationId,
                accountId: accountId,
                contractVersion: contractVersion,
                fingerprint: fingerprint,
                acceptedAt: t1,
                updatedAt: t1,
                state: .applying(attempt: 1, startedAt: t1)
            ),
            OperationSnapshot(
                operationId: operationId,
                accountId: accountId,
                contractVersion: contractVersion,
                fingerprint: fingerprint,
                acceptedAt: t1,
                updatedAt: t2,
                state: .rejected(rejection)
            )
        ]
    }

    private static func healthSnapshots() throws -> [SyncHealthSnapshot] {
        let requiredVersion = try OperationContractVersion(
            validating: "operation-test-v1"
        )
        let ready = SubscriptionReadinessSnapshot(
            capability: try CapabilityID(validating: "projects"),
            required: true,
            requiredContractVersion: requiredVersion,
            localContractVersion: requiredVersion,
            state: .ready
        )
        let loading = SubscriptionReadinessSnapshot(
            capability: try CapabilityID(validating: "projects"),
            required: true,
            requiredContractVersion: requiredVersion,
            localContractVersion: nil,
            state: .loading
        )
        return [
            try SyncHealthSnapshot(
                connectivity: .offline,
                authentication: .stale,
                subscriptions: [ready],
                lastSuccessfulCheckpointAt: t0,
                pendingOperationCount: 2,
                oldestPendingOperationAt: t0,
                pendingAttachmentCount: 0,
                oldestPendingAttachmentAt: nil,
                rejectedOperationCount: 1,
                transientError: nil,
                writeBlock: .none
            ),
            try SyncHealthSnapshot(
                connectivity: .online,
                authentication: .current,
                subscriptions: [loading],
                lastSuccessfulCheckpointAt: t1,
                pendingOperationCount: 1,
                oldestPendingOperationAt: t1,
                pendingAttachmentCount: 0,
                oldestPendingAttachmentAt: nil,
                rejectedOperationCount: 1,
                transientError: nil,
                writeBlock: .clientUpdateRequired
            ),
            try SyncHealthSnapshot(
                connectivity: .online,
                authentication: .current,
                subscriptions: [ready],
                lastSuccessfulCheckpointAt: t2,
                pendingOperationCount: 0,
                oldestPendingOperationAt: nil,
                pendingAttachmentCount: 0,
                oldestPendingAttachmentAt: nil,
                rejectedOperationCount: 0,
                transientError: nil,
                writeBlock: .maintenance
            )
        ]
    }

    private static func error(
        code: String,
        category: ApplicationErrorCategory,
        retry: RetryDisposition
    ) throws -> ApplicationErrorSummary {
        ApplicationErrorSummary(
            code: try ApplicationErrorCode(validating: code),
            category: category,
            retryDisposition: retry
        )
    }

    private static let contractVersions = LedgerContractVersions(
        schema: "test-v1",
        query: "test-v1",
        operation: "test-v1",
        sync: "test-v1"
    )

    private static func manifest(
        environment: LedgerEnvironmentKind,
        resourcesReversed: Bool = false
    ) -> LedgerEnvironmentManifest {
        let profile: LedgerBuildProfile
        let marker: String
        switch environment {
        case .targetLocal:
            profile = .targetLocalDevelopment
            marker = "local"
        case .targetStaging:
            profile = .targetStaging
            marker = "staging"
        case .targetProduction:
            profile = .targetProductionArchive
            marker = "production"
        }
        var resources = LedgerTargetComponent.allCases.map { component in
            LedgerEnvironmentResource(
                component: component,
                environment: environment,
                publicIdentifier: "test-\(component.rawValue)-\(marker)"
            )
        }
        if resourcesReversed {
            resources.reverse()
        }
        return LedgerEnvironmentManifest(
            environment: environment,
            buildProfile: profile,
            bundleIdentifier: "apps.nine4.ledger.test.\(marker)",
            displayName: environment == .targetStaging
                ? "Ledger Test STAGING"
                : "Ledger Test \(marker)",
            localDataNamespacePrefix: "apps.nine4.ledger.test",
            contractVersions: contractVersions,
            resources: resources
        )
    }

    private static func policy(
        environment: LedgerEnvironmentKind,
        manifestOverride: LedgerEnvironmentManifest? = nil
    ) -> LedgerEnvironmentPolicy {
        let manifest = manifestOverride ?? Self.manifest(environment: environment)
        return LedgerEnvironmentPolicy(
            expectedEnvironment: environment,
            expectedBuildProfile: manifest.buildProfile,
            expectedBundleIdentifier: manifest.bundleIdentifier,
            expectedContractVersions: contractVersions,
            allowedResourceIdentifiers: Dictionary(
                uniqueKeysWithValues: manifest.resources.map {
                    ($0.component, Set([$0.publicIdentifier]))
                }
            ),
            forbiddenResourceIdentifiers: [
                "ledger-nine4",
                "supabase-production",
                "powersync-production"
            ],
            forbiddenBundleIdentifiers: ["apps.nine4.ledger"]
        )
    }

    private static func stagingManifest(
        resourcesReversed: Bool = false
    ) -> LedgerEnvironmentManifest {
        manifest(
            environment: .targetStaging,
            resourcesReversed: resourcesReversed
        )
    }

    private static func stagingPolicy() -> LedgerEnvironmentPolicy {
        policy(environment: .targetStaging)
    }

    private static func replacingResource(
        _ component: LedgerTargetComponent,
        in manifest: LedgerEnvironmentManifest,
        identifier: String
    ) -> LedgerEnvironmentManifest {
        LedgerEnvironmentManifest(
            environment: manifest.environment,
            buildProfile: manifest.buildProfile,
            bundleIdentifier: manifest.bundleIdentifier,
            displayName: manifest.displayName,
            localDataNamespacePrefix: manifest.localDataNamespacePrefix,
            contractVersions: manifest.contractVersions,
            resources: manifest.resources.map { resource in
                guard resource.component == component else { return resource }
                return LedgerEnvironmentResource(
                    component: component,
                    environment: manifest.environment,
                    publicIdentifier: identifier
                )
            }
        )
    }

    private static func collect<Value: Sendable>(
        _ stream: AsyncThrowingStream<Value, Error>
    ) async throws -> [Value] {
        var values: [Value] = []
        for try await value in stream {
            values.append(value)
        }
        return values
    }

    private static func collect<Value: Sendable>(
        _ stream: AsyncStream<Value>
    ) async -> [Value] {
        var values: [Value] = []
        for await value in stream {
            values.append(value)
        }
        return values
    }

    private static func captureFailure(
        _ operation: () throws -> Void
    ) -> DeterministicTargetTestFailure? {
        do {
            try operation()
            return nil
        } catch let failure as DeterministicTargetTestFailure {
            return failure
        } catch {
            return nil
        }
    }

    private static func captureEnvironmentFailure(
        _ operation: () throws -> Void
    ) -> LedgerEnvironmentValidationFailure? {
        do {
            try operation()
            return nil
        } catch let failure as LedgerEnvironmentValidationFailure {
            return failure
        } catch {
            return nil
        }
    }

    private static func captureAsyncFailure(
        _ operation: () async throws -> Void
    ) async -> DeterministicTargetTestFailure? {
        do {
            try await operation()
            return nil
        } catch let failure as DeterministicTargetTestFailure {
            return failure
        } catch {
            return nil
        }
    }
}
