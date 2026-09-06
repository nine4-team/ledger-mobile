import Foundation
import LedgerTargetCore
import LedgerTargetTestSupport
import Testing
@testable import LedgerTargetComposition

@Suite("Validated Target Composition")
struct ValidatedTargetCompositionTests {
    @Test("A complete reference plan composes only its explicit typed ports")
    func completeReferenceComposition() async throws {
        let fixture = try Self.fixture()
        let composition = try Self.assemble(fixture)

        #expect(composition.plan == fixture.plan)
        #expect(composition.receipt.authority == .structuralOnly)
        #expect(
            composition.receipt.availableCapabilities.map(\.rawValue) == [
                "capability_manifest",
                "contract_catalog",
                "environment_manifest",
                "operation_status",
                "sync_health"
            ]
        )
        #expect(
            try composition.contractCatalog.catalog() ==
                GeneratedTargetContractCatalog.load()
        )

        let operationValues = try await Self.collect(
            composition.operationQueries.watchOperation(fixture.operationId)
        )
        let healthValues = await Self.collect(composition.syncHealth.observeHealth())
        #expect(operationValues == fixture.scenario.operationScripts[0].snapshots)
        #expect(healthValues == fixture.scenario.healthSnapshots)
        try await composition.syncHealth.waitForLocalDurability(of: fixture.operationId)
    }

    @Test("Canonical structural receipts survive offline restart and reordering")
    func canonicalReceiptRestart() throws {
        let fixture = try Self.fixture()
        let reorderedPlan = try TargetCompositionPlan(
            environment: fixture.environment,
            use: .testReference,
            expectedCatalogVersion: try ContractVersion(validating: "1"),
            dependencies: fixture.plan.dependencies.reversed()
        )
        let reorderedFixture = Fixture(
            environment: fixture.environment,
            plan: reorderedPlan,
            scenario: fixture.scenario,
            operationId: fixture.operationId
        )

        let first = try Self.assemble(fixture).receipt
        let reordered = try Self.assemble(reorderedFixture).receipt
        let bytes = try first.canonicalEvidence()
        let restored = try TargetCompositionReceipt.restore(from: bytes)

        #expect(first == reordered)
        #expect(try reordered.canonicalEvidence() == bytes)
        #expect(restored == first)
        #expect(try restored.canonicalEvidence() == bytes)
    }

    @Test("Incomplete, mixed, incompatible, and tampered composition fails atomically")
    func rejectsInvalidComposition() throws {
        let fixture = try Self.fixture()
        let descriptors = fixture.plan.dependencies

        let duplicateFailure = Self.captureFailure {
            _ = try TargetCompositionPlan(
                environment: fixture.environment,
                use: .testReference,
                expectedCatalogVersion: try ContractVersion(validating: "1"),
                dependencies: descriptors + [descriptors[0]]
            )
        }
        let missingFailure = Self.captureFailure {
            _ = try TargetCompositionPlan(
                environment: fixture.environment,
                use: .testReference,
                expectedCatalogVersion: try ContractVersion(validating: "1"),
                dependencies: Array(descriptors.dropLast())
            )
        }
        let runtimeReferenceFailure = Self.captureFailure {
            _ = try TargetCompositionPlan(
                environment: fixture.environment,
                use: .applicationRuntime,
                expectedCatalogVersion: try ContractVersion(validating: "1"),
                dependencies: try Self.descriptors(
                    environment: fixture.environment,
                    use: .applicationRuntime,
                    implementationClass: .referenceAdapter
                )
            )
        }

        let otherEnvironment = try Self.environment(suffix: "other")
        let crossBound = try TargetDependencyDescriptor(
            key: .operationQueries,
            implementationId: try TargetDependencyImplementationID(
                validating: "scripted_operation_reference"
            ),
            implementationClass: .referenceAdapter,
            use: .testReference,
            environmentBinding: otherEnvironment.persistenceBinding,
            capabilities: [try CapabilityID(validating: "operation_status")]
        )
        let crossEnvironmentFailure = Self.captureFailure {
            _ = try TargetCompositionPlan(
                environment: fixture.environment,
                use: .testReference,
                expectedCatalogVersion: try ContractVersion(validating: "1"),
                dependencies: descriptors.map {
                    $0.key == .operationQueries ? crossBound : $0
                }
            )
        }

        let wrongOwnership = try TargetDependencyDescriptor(
            key: .operationQueries,
            implementationId: try TargetDependencyImplementationID(
                validating: "scripted_operation_reference"
            ),
            implementationClass: .referenceAdapter,
            use: .testReference,
            environmentBinding: fixture.environment.persistenceBinding,
            capabilities: [try CapabilityID(validating: "wrong_capability")]
        )
        let ownershipFailure = Self.captureFailure {
            _ = try TargetCompositionPlan(
                environment: fixture.environment,
                use: .testReference,
                expectedCatalogVersion: try ContractVersion(validating: "1"),
                dependencies: descriptors.map {
                    $0.key == .operationQueries ? wrongOwnership : $0
                }
            )
        }

        let multiplyOwned = try TargetDependencyDescriptor(
            key: .operationQueries,
            implementationId: try TargetDependencyImplementationID(
                validating: "scripted_operation_reference"
            ),
            implementationClass: .referenceAdapter,
            use: .testReference,
            environmentBinding: fixture.environment.persistenceBinding,
            capabilities: [
                try CapabilityID(validating: "operation_status"),
                try CapabilityID(validating: "sync_health")
            ]
        )
        let multiplyOwnedFailure = Self.captureFailure {
            _ = try TargetCompositionPlan(
                environment: fixture.environment,
                use: .testReference,
                expectedCatalogVersion: try ContractVersion(validating: "1"),
                dependencies: descriptors.map {
                    $0.key == .operationQueries ? multiplyOwned : $0
                }
            )
        }

        let otherImplementation = try TargetDependencyDescriptor(
            key: .operationQueries,
            implementationId: try TargetDependencyImplementationID(
                validating: "other_operation_reference"
            ),
            implementationClass: .referenceAdapter,
            use: .testReference,
            environmentBinding: fixture.environment.persistenceBinding,
            capabilities: [try CapabilityID(validating: "operation_status")]
        )
        let implementationFailure = Self.captureFailure {
            _ = try TargetCompositionAssembler.assemble(
                environment: fixture.environment,
                plan: fixture.plan,
                contractCatalog: EnvironmentBoundTargetDependency(
                    descriptor: fixture.plan.descriptor(for: .contractCatalog),
                    value: GeneratedCatalogProvider()
                ),
                operationQueries: EnvironmentBoundTargetDependency(
                    descriptor: otherImplementation,
                    value: fixture.scenario.operationQueryAdapter()
                ),
                syncHealth: EnvironmentBoundTargetDependency(
                    descriptor: fixture.plan.descriptor(for: .syncHealth),
                    value: fixture.scenario.syncHealthAdapter()
                )
            )
        }

        let wrongKeyFailure = Self.captureFailure {
            _ = try TargetCompositionAssembler.assemble(
                environment: fixture.environment,
                plan: fixture.plan,
                contractCatalog: EnvironmentBoundTargetDependency(
                    descriptor: fixture.plan.descriptor(for: .operationQueries),
                    value: GeneratedCatalogProvider()
                ),
                operationQueries: EnvironmentBoundTargetDependency(
                    descriptor: fixture.plan.descriptor(for: .operationQueries),
                    value: fixture.scenario.operationQueryAdapter()
                ),
                syncHealth: EnvironmentBoundTargetDependency(
                    descriptor: fixture.plan.descriptor(for: .syncHealth),
                    value: fixture.scenario.syncHealthAdapter()
                )
            )
        }

        let versionFixture = try Self.fixture(version: "2")
        let versionFailure = Self.captureFailure {
            _ = try Self.assemble(versionFixture)
        }
        let catalogFailure = Self.captureFailure {
            _ = try Self.assemble(fixture, catalog: FailingCatalogProvider())
        }

        let gatedCatalog = try Self.catalog { capabilities in
            let index = try #require(
                capabilities.firstIndex(where: { $0["id"] as? String == "sync_health" })
            )
            capabilities[index]["availability"] = "gated"
        }
        let gatedFailure = Self.captureFailure {
            _ = try Self.assemble(
                fixture,
                catalog: StaticCatalogProvider(value: gatedCatalog)
            )
        }

        let deprecatedCatalog = try Self.catalog { capabilities in
            let index = try #require(
                capabilities.firstIndex(where: { $0["id"] as? String == "sync_health" })
            )
            capabilities[index]["availability"] = "deprecated"
        }
        let deprecatedFailure = Self.captureFailure {
            _ = try Self.assemble(
                fixture,
                catalog: StaticCatalogProvider(value: deprecatedCatalog)
            )
        }

        let duplicatedCatalog = try Self.catalog { capabilities in
            capabilities.append(try #require(capabilities.first))
        }
        let duplicatedCatalogCapability = try #require(
            duplicatedCatalog.capabilities.first?.id
        )
        let duplicatedCatalogFailure = Self.captureFailure {
            _ = try Self.assemble(
                fixture,
                catalog: StaticCatalogProvider(value: duplicatedCatalog)
            )
        }

        let extraCapability = try CapabilityID(validating: "unexpected_available")
        let expandedCatalog = try Self.catalog { capabilities in
            var extra = try #require(capabilities.first)
            extra["id"] = extraCapability.rawValue
            capabilities.append(extra)
        }
        let expandedFailure = Self.captureFailure {
            _ = try Self.assemble(
                fixture,
                catalog: StaticCatalogProvider(value: expandedCatalog)
            )
        }

        let receipt = try Self.assemble(fixture).receipt
        let bytes = try receipt.canonicalEvidence()
        let nonCanonicalFailure = Self.captureFailure {
            _ = try TargetCompositionReceipt.restore(from: bytes + Data(" ".utf8))
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
            _ = try TargetCompositionReceipt.restore(from: tampered)
        }
        var unsafeDescriptorJSON = try #require(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        )
        var unsafeContent = try #require(
            unsafeDescriptorJSON["content"] as? [String: Any]
        )
        var unsafeDependencies = try #require(
            unsafeContent["dependencies"] as? [[String: Any]]
        )
        unsafeDependencies[0]["implementationId"] = "unsafe implementation"
        unsafeContent["dependencies"] = unsafeDependencies
        unsafeDescriptorJSON["content"] = unsafeContent
        let unsafeDescriptorBytes = try JSONSerialization.data(
            withJSONObject: unsafeDescriptorJSON,
            options: [.sortedKeys]
        )
        let unsafeDescriptorFailure = Self.captureFailure {
            _ = try TargetCompositionReceipt.restore(from: unsafeDescriptorBytes)
        }
        let oversizedFailure = Self.captureFailure {
            _ = try TargetCompositionReceipt.restore(
                from: Data(
                    repeating: 0,
                    count: TargetCompositionReceipt.maximumCanonicalEvidenceBytes + 1
                )
            )
        }

        #expect(duplicateFailure == .duplicateDependency(.contractCatalog))
        #expect(missingFailure == .missingDependency(.syncHealth))
        #expect(runtimeReferenceFailure == .dependencyClassMismatch(.contractCatalog))
        #expect(crossEnvironmentFailure == .dependencyBindingMismatch(.operationQueries))
        #expect(ownershipFailure == .capabilityOwnershipMismatch(.operationQueries))
        #expect(
            multiplyOwnedFailure == .duplicateCapability(
                try CapabilityID(validating: "sync_health")
            )
        )
        #expect(
            implementationFailure == .dependencyImplementationMismatch(.operationQueries)
        )
        #expect(
            wrongKeyFailure == .wrongDependencyKey(
                expected: .contractCatalog,
                actual: .operationQueries
            )
        )
        #expect(versionFailure == .contractVersionMismatch(field: "schema"))
        #expect(catalogFailure == .catalogUnavailable)
        #expect(gatedFailure == .requiredCapabilityUnavailable("sync_health"))
        #expect(deprecatedFailure == .requiredCapabilityUnavailable("sync_health"))
        #expect(
            duplicatedCatalogFailure ==
                .duplicateCatalogCapability(duplicatedCatalogCapability)
        )
        #expect(expandedFailure == .availableCapabilityUnowned(extraCapability))
        #expect(nonCanonicalFailure == .nonCanonicalEvidence)
        #expect(tamperFailure == .evidenceDigestMismatch)
        #expect(unsafeDescriptorFailure == .invalidEvidence)
        #expect(
            oversizedFailure == .evidenceTooLarge(
                actual: TargetCompositionReceipt.maximumCanonicalEvidenceBytes + 1,
                maximum: TargetCompositionReceipt.maximumCanonicalEvidenceBytes
            )
        )
        #expect(duplicateFailure?.diagnosticCode == "target_composition_dependency_duplicate")
    }

    private struct Fixture {
        let environment: ValidatedLedgerEnvironment
        let plan: TargetCompositionPlan
        let scenario: DeterministicTargetScenario
        let operationId: OperationID
    }

    private struct GeneratedCatalogProvider: ContractCatalogProviding {
        func catalog() throws -> VersionedContractCatalog {
            try GeneratedTargetContractCatalog.load()
        }
    }

    private struct StaticCatalogProvider: ContractCatalogProviding {
        let value: VersionedContractCatalog

        func catalog() throws -> VersionedContractCatalog {
            value
        }
    }

    private enum FixtureCatalogFailure: Error {
        case unavailable
    }

    private struct FailingCatalogProvider: ContractCatalogProviding {
        func catalog() throws -> VersionedContractCatalog {
            throw FixtureCatalogFailure.unavailable
        }
    }

    private static func fixture(version: String = "1") throws -> Fixture {
        let environment = try environment(version: version)
        let context = try DeterministicTargetTestContext(
            environment: environment,
            principalId: try PrincipalID(validating: "test-principal-composition"),
            accountId: try AccountID(validating: "test-account-composition"),
            scenarioId: try DeterministicTargetScenarioID(
                validating: "test-scenario-composition"
            ),
            seed: 47,
            baseTimeMilliseconds: 1_767_225_600_000
        )
        let values = try DeterministicTargetValueSource(
            context: context,
            maximumIndex: 2,
            stepMilliseconds: 1_000,
            startingRevision: 1
        )
        let key = try DeterministicFixtureKey(validating: "composition_fixture")
        let operationId = try values.operationId(key: key, index: 0)
        let timestamp = try values.timestamp(key: key, index: 0)
        let snapshot = OperationSnapshot(
            operationId: operationId,
            accountId: context.accountId,
            contractVersion: try OperationContractVersion(validating: version),
            fingerprint: try OperationFingerprint(
                validating: String(repeating: "a", count: 64)
            ),
            acceptedAt: timestamp,
            updatedAt: timestamp,
            state: .queued(attemptCount: 0, lastTransientError: nil)
        )
        let operationScript = try ScriptedOperationSequence(
            operationId: operationId,
            accountId: context.accountId,
            snapshots: [snapshot]
        )
        let unresolved = try ScriptedUnresolvedOperationSequence(
            accountId: context.accountId,
            snapshots: [[snapshot]]
        )
        let health = try SyncHealthSnapshot(
            connectivity: .offline,
            authentication: .unavailable,
            subscriptions: [],
            lastSuccessfulCheckpointAt: nil,
            pendingOperationCount: 1,
            oldestPendingOperationAt: timestamp,
            pendingAttachmentCount: 0,
            oldestPendingAttachmentAt: nil,
            rejectedOperationCount: 0,
            transientError: nil,
            writeBlock: .none
        )
        let scenario = try DeterministicTargetScenario(
            context: context,
            valueSource: values,
            operationScripts: [operationScript],
            unresolvedOperationScript: unresolved,
            healthSnapshots: [health],
            durabilityOutcomes: [
                ScriptedDurabilityOutcome(
                    operationId: operationId,
                    result: .durable
                )
            ]
        )
        let plan = try TargetCompositionPlan(
            environment: environment,
            use: .testReference,
            expectedCatalogVersion: try ContractVersion(validating: "1"),
            dependencies: try descriptors(environment: environment)
        )
        return Fixture(
            environment: environment,
            plan: plan,
            scenario: scenario,
            operationId: operationId
        )
    }

    private static func descriptors(
        environment: ValidatedLedgerEnvironment,
        use: TargetCompositionUse = .testReference,
        implementationClass: TargetDependencyImplementationClass = .referenceAdapter
    ) throws -> [TargetDependencyDescriptor] {
        let binding = environment.persistenceBinding
        return [
            try TargetDependencyDescriptor(
                key: .contractCatalog,
                implementationId: try TargetDependencyImplementationID(
                    validating: "generated_catalog_reference"
                ),
                implementationClass: implementationClass,
                use: use,
                environmentBinding: binding,
                capabilities: [
                    try CapabilityID(validating: "contract_catalog"),
                    try CapabilityID(validating: "capability_manifest")
                ]
            ),
            try TargetDependencyDescriptor(
                key: .operationQueries,
                implementationId: try TargetDependencyImplementationID(
                    validating: "scripted_operation_reference"
                ),
                implementationClass: implementationClass,
                use: use,
                environmentBinding: binding,
                capabilities: [try CapabilityID(validating: "operation_status")]
            ),
            try TargetDependencyDescriptor(
                key: .syncHealth,
                implementationId: try TargetDependencyImplementationID(
                    validating: "scripted_sync_reference"
                ),
                implementationClass: implementationClass,
                use: use,
                environmentBinding: binding,
                capabilities: [try CapabilityID(validating: "sync_health")]
            )
        ]
    }

    private static func environment(
        version: String = "1",
        suffix: String = "primary"
    ) throws -> ValidatedLedgerEnvironment {
        let versions = LedgerContractVersions(
            schema: version,
            query: version,
            operation: version,
            sync: version
        )
        let resources = Dictionary(
            uniqueKeysWithValues: LedgerTargetComponent.allCases.map {
                ($0, "test-\($0.rawValue)-local-\(suffix)")
            }
        )
        let manifest = LedgerEnvironmentManifest(
            environment: .targetLocal,
            buildProfile: .targetLocalDevelopment,
            bundleIdentifier: "apps.nine4.ledger.target.test.\(suffix)",
            displayName: "Ledger Target Test",
            localDataNamespacePrefix: "apps.nine4.ledger.target.test",
            contractVersions: versions,
            resources: LedgerTargetComponent.allCases.map {
                LedgerEnvironmentResource(
                    component: $0,
                    environment: .targetLocal,
                    publicIdentifier: resources[$0]!
                )
            }
        )
        let policy = LedgerEnvironmentPolicy(
            expectedEnvironment: .targetLocal,
            expectedBuildProfile: .targetLocalDevelopment,
            expectedBundleIdentifier: manifest.bundleIdentifier,
            expectedContractVersions: versions,
            allowedResourceIdentifiers: resources.mapValues { [$0] },
            forbiddenResourceIdentifiers: [],
            forbiddenBundleIdentifiers: []
        )
        return try LedgerEnvironmentValidator.validate(manifest, policy: policy)
    }

    private static func assemble<Catalog: ContractCatalogProviding>(
        _ fixture: Fixture,
        catalog: Catalog
    ) throws -> ValidatedTargetComposition {
        try TargetCompositionAssembler.assemble(
            environment: fixture.environment,
            plan: fixture.plan,
            contractCatalog: EnvironmentBoundTargetDependency(
                descriptor: fixture.plan.descriptor(for: .contractCatalog),
                value: catalog
            ),
            operationQueries: EnvironmentBoundTargetDependency(
                descriptor: fixture.plan.descriptor(for: .operationQueries),
                value: fixture.scenario.operationQueryAdapter()
            ),
            syncHealth: EnvironmentBoundTargetDependency(
                descriptor: fixture.plan.descriptor(for: .syncHealth),
                value: fixture.scenario.syncHealthAdapter()
            )
        )
    }

    private static func assemble(
        _ fixture: Fixture
    ) throws -> ValidatedTargetComposition {
        try assemble(fixture, catalog: GeneratedCatalogProvider())
    }

    private static func catalog(
        mutate: (inout [[String: Any]]) throws -> Void
    ) throws -> VersionedContractCatalog {
        let source = try GeneratedTargetContractCatalog.load()
        let bytes = try OperationContractCodec.encode(source)
        var object = try #require(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        )
        var capabilities = try #require(
            object["capabilities"] as? [[String: Any]]
        )
        try mutate(&capabilities)
        object["capabilities"] = capabilities
        let changed = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        return try OperationContractCodec.decode(
            VersionedContractCatalog.self,
            from: changed
        )
    }

    private static func captureFailure(
        _ body: () throws -> Void
    ) -> TargetCompositionFailure? {
        do {
            try body()
            return nil
        } catch let failure as TargetCompositionFailure {
            return failure
        } catch {
            return nil
        }
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
}
