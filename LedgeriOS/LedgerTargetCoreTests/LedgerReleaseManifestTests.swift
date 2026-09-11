import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Reproducible Release Manifest and Artifact Integrity")
struct LedgerReleaseManifestTests {
    @Test("A complete release candidate normalizes to exact evidence-only identity")
    func completeReleaseCandidateIsCanonicalAndEvidenceOnly() throws {
        let fixture = try Self.fixture()
        let manifest = try fixture.validator.validate(
            fixture.draft(
                artifacts: fixture.artifacts.reversed(),
                dependencyLocks: fixture.dependencyLocks.reversed()
            )
        )

        #expect(manifest.schemaVersion == ReleaseManifestValidator.schemaVersion)
        #expect(manifest.build.environment == .targetStaging)
        #expect(manifest.build.buildProfile == .targetStaging)
        #expect(manifest.build.contractVersions == Self.contractVersions)
        #expect(manifest.build.contractCatalogSHA256.rawValue == GeneratedTargetContractCatalog.sha256)
        #expect(manifest.channel == .testFlightInternal)
        #expect(manifest.authorityDisposition == .evidenceOnly)
        #expect(manifest.artifacts.map(\.id.rawValue) == ["target_contract_catalog", "target_ios_app"])
        #expect(manifest.dependencyLocks.map(\.id.rawValue) == ["npm_package_lock", "swift_package_resolved"])
        #expect(manifest.contentDigest.rawValue.count == 64)

        let canonical = try fixture.validator.canonicalData(for: manifest)
        #expect(canonical.count <= ReleaseManifestValidator.maximumCanonicalManifestBytes)
        #expect(try fixture.validator.decodeAndValidate(canonical) == manifest)
    }

    @Test("Canonical evidence survives restart and verifies immutable bytes")
    func canonicalRestartAndPureByteVerification() throws {
        let fixture = try Self.fixture()
        let first = try fixture.validator.validate(fixture.draft())
        let reordered = try fixture.validator.validate(
            fixture.draft(
                artifacts: fixture.artifacts.reversed(),
                dependencyLocks: fixture.dependencyLocks.reversed()
            )
        )
        let firstData = try fixture.validator.canonicalData(for: first)
        let reorderedData = try fixture.validator.canonicalData(for: reordered)

        #expect(first == reordered)
        #expect(firstData == reorderedData)
        #expect(try fixture.validator.decodeAndValidate(firstData) == first)

        try fixture.artifacts[0].verify(bytes: Self.applicationBytes)
        try fixture.dependencyLocks[0].verify(bytes: Self.swiftLockBytes)
        #expect(Self.captureFailure {
            try fixture.artifacts[0].verify(bytes: Self.applicationBytes + Data([0x00]))
        } == .artifactByteCountMismatch(fixture.artifacts[0].id))
        #expect(Self.captureFailure {
            try fixture.artifacts[0].verify(bytes: Data("ios-app-v2".utf8))
        } == .artifactHashMismatch(fixture.artifacts[0].id))
        #expect(Self.captureFailure {
            try fixture.dependencyLocks[0].verify(bytes: Data("swift-lock-v2".utf8))
        } == .dependencyLockHashMismatch(fixture.dependencyLocks[0].id))
    }

    @Test("Compatibility, completeness, tamper, and canonical bounds fail closed")
    func incompatibleAndTamperedCandidatesFailClosed() throws {
        let fixture = try Self.fixture()

        #expect(Self.captureFailure {
            try fixture.validator.validate(fixture.draft(channel: .appStoreProduction))
        } == .channelEnvironmentMismatch(.appStoreProduction))

        let localBuild = try Self.build(environment: .targetLocal)
        #expect(Self.captureFailure {
            try fixture.validator.validate(fixture.draft(build: localBuild))
        } == .environmentMismatch)

        let mismatchedContracts = LedgerContractVersions(
            schema: "2",
            query: "1",
            operation: "1",
            sync: "1"
        )
        let contractBuild = try Self.build(contractVersions: mismatchedContracts)
        #expect(Self.captureFailure {
            try fixture.validator.validate(fixture.draft(build: contractBuild))
        } == .contractVersionMismatch("schema"))

        let catalogBuild = try Self.build(
            catalogSHA256: ReleaseSHA256(validating: String(repeating: "b", count: 64))
        )
        #expect(Self.captureFailure {
            try fixture.validator.validate(fixture.draft(build: catalogBuild))
        } == .contractCatalogHashMismatch)

        #expect(Self.captureFailure {
            try fixture.validator.validate(
                fixture.draft(artifacts: fixture.artifacts + [fixture.artifacts[0]])
            )
        } == .duplicateArtifactEvidence(fixture.artifacts[0].id))
        #expect(Self.captureFailure {
            try fixture.validator.validate(
                fixture.draft(artifacts: Array(fixture.artifacts.dropLast()))
            )
        } == .missingArtifactEvidence(fixture.artifacts[1].id))
        #expect(Self.captureFailure {
            try fixture.validator.validate(
                fixture.draft(dependencyLocks: Array(fixture.dependencyLocks.dropLast()))
            )
        } == .missingDependencyLockEvidence(fixture.dependencyLocks[1].id))

        let valid = try fixture.validator.validate(fixture.draft())
        let canonical = try fixture.validator.canonicalData(for: valid)
        var object = try #require(
            JSONSerialization.jsonObject(with: canonical) as? [String: Any]
        )
        object["contentDigest"] = String(repeating: "b", count: 64)
        let digestTamper = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        #expect(Self.captureFailure {
            try fixture.validator.decodeAndValidate(digestTamper)
        } == .contentDigestMismatch)

        #expect(Self.captureFailure {
            try fixture.validator.decodeAndValidate(canonical + Data([0x0a]))
        } == .noncanonicalManifest)

        let oversizedBytes = Data(
            repeating: 0x20,
            count: ReleaseManifestValidator.maximumCanonicalManifestBytes + 1
        )
        guard case .manifestTooLarge(let actual, let maximum) = Self.captureFailure({
            try fixture.validator.decodeAndValidate(oversizedBytes)
        }) else {
            Issue.record("Oversized canonical input should fail before decoding")
            return
        }
        #expect(actual == oversizedBytes.count)
        #expect(maximum == ReleaseManifestValidator.maximumCanonicalManifestBytes)

        let maximumFixture = try Self.maximumShapeFixture()
        guard case .manifestTooLarge(let actual, let maximum) = Self.captureFailure({
            try maximumFixture.validator.validate(maximumFixture.draft())
        }) else {
            Issue.record("A maximum-count, maximum-ID candidate should exceed the size ceiling")
            return
        }
        #expect(actual > maximum)
    }

    @Test("Unsafe build identity is refused and production-shaped proof grants no authority")
    func identitySafetyAndProductionNonAuthority() throws {
        #expect(Self.captureFailure {
            try ReleaseApplicationVersion(validating: " https://private.invalid ")
        } == .invalidApplicationVersion)
        #expect(Self.captureFailure {
            try ReleaseSourceRevision(validating: String(repeating: "A", count: 40))
        } == .invalidSourceRevision)
        #expect(Self.captureFailure {
            try ReleaseSHA256(validating: String(repeating: "g", count: 64))
        } == .invalidSHA256)
        #expect(Self.captureFailure {
            try Self.build(buildNumber: 0)
        } == .invalidBuildNumber)

        let unsafeContracts = LedgerContractVersions(
            schema: "1",
            query: "1",
            operation: "access_token=private",
            sync: "1"
        )
        #expect(Self.captureFailure {
            try Self.build(contractVersions: unsafeContracts)
        } == .invalidContractVersion("operation"))

        let productionFixture = try Self.fixture(
            environment: .targetProduction,
            allowedChannels: [.appStoreProduction]
        )
        let productionManifest = try productionFixture.validator.validate(
            productionFixture.draft(channel: .appStoreProduction)
        )
        #expect(productionManifest.build.environment == .targetProduction)
        #expect(productionManifest.authorityDisposition == .evidenceOnly)

        let encoded = String(
            decoding: try productionFixture.validator.canonicalData(for: productionManifest),
            as: UTF8.self
        )
        for forbidden in [
            "/Users/private",
            "file://",
            "https://",
            "access_token",
            "service_role",
            "firebase",
            "supabase",
            "powersync",
            "principal-private",
            "account-private"
        ] {
            #expect(!encoded.localizedCaseInsensitiveContains(forbidden))
        }
    }

    private static let contractVersions = LedgerContractVersions(
        schema: "1",
        query: "1",
        operation: "1",
        sync: "1"
    )
    private static let producedAt = Date(timeIntervalSince1970: 1_788_000_000)
    private static let applicationBytes = Data("ios-app-v1".utf8)
    private static let contractCatalogBytes = Data("contract-catalog-v1".utf8)
    private static let swiftLockBytes = Data("swift-lock-v1".utf8)
    private static let npmLockBytes = Data("npm-lock-v1".utf8)

    private struct Fixture {
        let validator: ReleaseManifestValidator
        let build: ReleaseBuildIdentity
        let artifacts: [ReleaseArtifactEvidence]
        let dependencyLocks: [ReleaseDependencyLockEvidence]

        func draft(
            build: ReleaseBuildIdentity? = nil,
            channel: ReleaseChannel = .testFlightInternal,
            artifacts: [ReleaseArtifactEvidence]? = nil,
            dependencyLocks: [ReleaseDependencyLockEvidence]? = nil
        ) -> LedgerReleaseManifestDraft {
            LedgerReleaseManifestDraft(
                build: build ?? self.build,
                channel: channel,
                producedAt: LedgerReleaseManifestTests.producedAt,
                artifacts: artifacts ?? self.artifacts,
                dependencyLocks: dependencyLocks ?? self.dependencyLocks
            )
        }
    }

    private static func fixture(
        environment: LedgerEnvironmentKind = .targetStaging,
        allowedChannels: [ReleaseChannel] = [.internalStaging, .testFlightInternal]
    ) throws -> Fixture {
        let artifacts = [
            try ReleaseArtifactEvidence.make(
                id: ReleaseArtifactID(validating: "target_ios_app"),
                kind: .applicationArchive,
                platform: .iOS,
                bytes: applicationBytes
            ),
            try ReleaseArtifactEvidence.make(
                id: ReleaseArtifactID(validating: "target_contract_catalog"),
                kind: .contractCatalog,
                platform: .universal,
                bytes: contractCatalogBytes
            )
        ]
        let dependencyLocks = [
            try ReleaseDependencyLockEvidence.make(
                id: ReleaseDependencyLockID(validating: "swift_package_resolved"),
                ecosystem: .swiftPackageManager,
                bytes: swiftLockBytes
            ),
            try ReleaseDependencyLockEvidence.make(
                id: ReleaseDependencyLockID(validating: "npm_package_lock"),
                ecosystem: .npm,
                bytes: npmLockBytes
            )
        ]
        let validatedEnvironment = try validatedEnvironment(environment: environment)
        let catalogSHA = try ReleaseSHA256(validating: GeneratedTargetContractCatalog.sha256)
        let policy = try ReleaseCompatibilityPolicy(
            validatedEnvironment: validatedEnvironment,
            expectedContractCatalogSHA256: catalogSHA,
            allowedChannels: allowedChannels,
            requiredArtifacts: artifacts.map {
                ReleaseArtifactRequirement(id: $0.id, kind: $0.kind, platform: $0.platform)
            },
            requiredDependencyLocks: dependencyLocks.map {
                ReleaseDependencyLockRequirement(id: $0.id, ecosystem: $0.ecosystem)
            }
        )
        return Fixture(
            validator: ReleaseManifestValidator(policy: policy),
            build: try build(environment: environment),
            artifacts: artifacts,
            dependencyLocks: dependencyLocks
        )
    }

    private static func maximumShapeFixture() throws -> Fixture {
        let validatedEnvironment = try validatedEnvironment()
        let artifacts = try (0..<ReleaseCompatibilityPolicy.maximumArtifactRequirements).map {
            let id = try ReleaseArtifactID(
                validating: String(format: "artifact_%02d_", $0) + String(repeating: "x", count: 66)
            )
            return try ReleaseArtifactEvidence.make(
                id: id,
                kind: .applicationArchive,
                platform: .iOS,
                bytes: Data([UInt8($0)])
            )
        }
        let dependencyLocks = try (0..<ReleaseCompatibilityPolicy.maximumDependencyLockRequirements).map {
            let id = try ReleaseDependencyLockID(
                validating: String(format: "lock_%02d_", $0) + String(repeating: "y", count: 70)
            )
            return try ReleaseDependencyLockEvidence.make(
                id: id,
                ecosystem: $0.isMultiple(of: 2) ? .swiftPackageManager : .npm,
                bytes: Data([UInt8($0 + 1)])
            )
        }
        let catalogSHA = try ReleaseSHA256(validating: GeneratedTargetContractCatalog.sha256)
        let policy = try ReleaseCompatibilityPolicy(
            validatedEnvironment: validatedEnvironment,
            expectedContractCatalogSHA256: catalogSHA,
            allowedChannels: [.testFlightInternal],
            requiredArtifacts: artifacts.map {
                ReleaseArtifactRequirement(id: $0.id, kind: $0.kind, platform: $0.platform)
            },
            requiredDependencyLocks: dependencyLocks.map {
                ReleaseDependencyLockRequirement(id: $0.id, ecosystem: $0.ecosystem)
            }
        )
        return Fixture(
            validator: ReleaseManifestValidator(policy: policy),
            build: try build(),
            artifacts: artifacts,
            dependencyLocks: dependencyLocks
        )
    }

    private static func build(
        environment: LedgerEnvironmentKind = .targetStaging,
        contractVersions: LedgerContractVersions = contractVersions,
        buildNumber: UInt64 = 84,
        catalogSHA256: ReleaseSHA256? = nil
    ) throws -> ReleaseBuildIdentity {
        try ReleaseBuildIdentity(
            validatedEnvironment: validatedEnvironment(
                environment: environment,
                contractVersions: contractVersions
            ),
            applicationVersion: ReleaseApplicationVersion(validating: "2.0.0-beta"),
            buildNumber: buildNumber,
            sourceRevision: ReleaseSourceRevision(
                validating: String(repeating: "a", count: 40)
            ),
            contractCatalogSHA256: catalogSHA256
                ?? ReleaseSHA256(validating: GeneratedTargetContractCatalog.sha256)
        )
    }

    private static func validatedEnvironment(
        environment: LedgerEnvironmentKind = .targetStaging,
        contractVersions: LedgerContractVersions = contractVersions
    ) throws -> ValidatedLedgerEnvironment {
        let buildProfile: LedgerBuildProfile = switch environment {
        case .targetLocal:
            .targetLocalDevelopment
        case .targetStaging:
            .targetStaging
        case .targetProduction:
            .targetProductionArchive
        }
        let suffix: String = switch environment {
        case .targetLocal:
            "local"
        case .targetStaging:
            "staging"
        case .targetProduction:
            "production"
        }
        let bundleIdentifier = "apps.nine4.ledger.\(suffix)"
        let resources = LedgerTargetComponent.allCases.map {
            LedgerEnvironmentResource(
                component: $0,
                environment: environment,
                publicIdentifier: "\($0.rawValue)-\(suffix)"
            )
        }
        let manifest = LedgerEnvironmentManifest(
            environment: environment,
            buildProfile: buildProfile,
            bundleIdentifier: bundleIdentifier,
            displayName: environment == .targetStaging
                ? "Ledger STAGING"
                : "Ledger \(suffix.uppercased())",
            localDataNamespacePrefix: "ledger-target-\(suffix)",
            contractVersions: contractVersions,
            resources: resources
        )
        return try LedgerEnvironmentValidator.validate(
            manifest,
            policy: LedgerEnvironmentPolicy(
                expectedEnvironment: environment,
                expectedBuildProfile: buildProfile,
                expectedBundleIdentifier: bundleIdentifier,
                expectedContractVersions: contractVersions,
                allowedResourceIdentifiers: Dictionary(
                    uniqueKeysWithValues: resources.map {
                        ($0.component, Set([$0.publicIdentifier]))
                    }
                ),
                forbiddenResourceIdentifiers: [],
                forbiddenBundleIdentifiers: []
            )
        )
    }

    private static func captureFailure<Value>(
        _ operation: () throws -> Value
    ) -> ReleaseManifestFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as ReleaseManifestFailure {
            return failure
        } catch {
            return nil
        }
    }
}
