import CryptoKit
import Foundation

public enum ReleaseManifestFailure: Error, Equatable, Sendable {
    case invalidApplicationVersion
    case invalidSourceRevision
    case invalidSHA256
    case invalidArtifactID
    case invalidDependencyLockID
    case invalidBuildNumber
    case invalidContractVersion(String)
    case invalidProducedAt
    case invalidArtifactByteCount(ReleaseArtifactID)
    case invalidDependencyLockByteCount(ReleaseDependencyLockID)
    case duplicateArtifactRequirement(ReleaseArtifactID)
    case duplicateDependencyLockRequirement(ReleaseDependencyLockID)
    case duplicateArtifactEvidence(ReleaseArtifactID)
    case duplicateDependencyLockEvidence(ReleaseDependencyLockID)
    case missingArtifactEvidence(ReleaseArtifactID)
    case unexpectedArtifactEvidence(ReleaseArtifactID)
    case artifactRequirementMismatch(ReleaseArtifactID)
    case missingDependencyLockEvidence(ReleaseDependencyLockID)
    case unexpectedDependencyLockEvidence(ReleaseDependencyLockID)
    case dependencyLockRequirementMismatch(ReleaseDependencyLockID)
    case artifactByteCountMismatch(ReleaseArtifactID)
    case artifactHashMismatch(ReleaseArtifactID)
    case dependencyLockByteCountMismatch(ReleaseDependencyLockID)
    case dependencyLockHashMismatch(ReleaseDependencyLockID)
    case emptyArtifactRequirements
    case emptyDependencyLockRequirements
    case tooManyArtifactRequirements(maximum: Int)
    case tooManyDependencyLockRequirements(maximum: Int)
    case emptyAllowedChannels
    case environmentMismatch
    case buildProfileMismatch
    case channelNotAllowed(ReleaseChannel)
    case channelEnvironmentMismatch(ReleaseChannel)
    case contractVersionMismatch(String)
    case contractCatalogHashMismatch
    case schemaVersionMismatch
    case authorityDispositionMismatch
    case contentDigestMismatch
    case noncanonicalManifest
    case manifestTooLarge(actual: Int, maximum: Int)
    case malformedManifest

    public var diagnosticCode: String {
        switch self {
        case .invalidApplicationVersion: return "release_application_version_invalid"
        case .invalidSourceRevision: return "release_source_revision_invalid"
        case .invalidSHA256: return "release_sha256_invalid"
        case .invalidArtifactID: return "release_artifact_id_invalid"
        case .invalidDependencyLockID: return "release_dependency_lock_id_invalid"
        case .invalidBuildNumber: return "release_build_number_invalid"
        case .invalidContractVersion(let field): return "release_contract_version_invalid_\(field)"
        case .invalidProducedAt: return "release_produced_at_invalid"
        case .invalidArtifactByteCount: return "release_artifact_byte_count_invalid"
        case .invalidDependencyLockByteCount: return "release_dependency_lock_byte_count_invalid"
        case .duplicateArtifactRequirement: return "release_artifact_requirement_duplicate"
        case .duplicateDependencyLockRequirement: return "release_dependency_lock_requirement_duplicate"
        case .duplicateArtifactEvidence: return "release_artifact_evidence_duplicate"
        case .duplicateDependencyLockEvidence: return "release_dependency_lock_evidence_duplicate"
        case .missingArtifactEvidence: return "release_artifact_evidence_missing"
        case .unexpectedArtifactEvidence: return "release_artifact_evidence_unexpected"
        case .artifactRequirementMismatch: return "release_artifact_requirement_mismatch"
        case .missingDependencyLockEvidence: return "release_dependency_lock_evidence_missing"
        case .unexpectedDependencyLockEvidence: return "release_dependency_lock_evidence_unexpected"
        case .dependencyLockRequirementMismatch: return "release_dependency_lock_requirement_mismatch"
        case .artifactByteCountMismatch: return "release_artifact_byte_count_mismatch"
        case .artifactHashMismatch: return "release_artifact_hash_mismatch"
        case .dependencyLockByteCountMismatch: return "release_dependency_lock_byte_count_mismatch"
        case .dependencyLockHashMismatch: return "release_dependency_lock_hash_mismatch"
        case .emptyArtifactRequirements: return "release_artifact_requirements_empty"
        case .emptyDependencyLockRequirements: return "release_dependency_lock_requirements_empty"
        case .tooManyArtifactRequirements: return "release_artifact_requirements_too_many"
        case .tooManyDependencyLockRequirements: return "release_dependency_lock_requirements_too_many"
        case .emptyAllowedChannels: return "release_channels_empty"
        case .environmentMismatch: return "release_environment_mismatch"
        case .buildProfileMismatch: return "release_build_profile_mismatch"
        case .channelNotAllowed: return "release_channel_not_allowed"
        case .channelEnvironmentMismatch: return "release_channel_environment_mismatch"
        case .contractVersionMismatch(let field): return "release_contract_version_mismatch_\(field)"
        case .contractCatalogHashMismatch: return "release_contract_catalog_hash_mismatch"
        case .schemaVersionMismatch: return "release_manifest_schema_mismatch"
        case .authorityDispositionMismatch: return "release_authority_disposition_mismatch"
        case .contentDigestMismatch: return "release_content_digest_mismatch"
        case .noncanonicalManifest: return "release_manifest_noncanonical"
        case .manifestTooLarge: return "release_manifest_too_large"
        case .malformedManifest: return "release_manifest_malformed"
        }
    }
}

public enum ReleaseChannel: String, Codable, CaseIterable, Sendable {
    case localDevelopment = "local_development"
    case internalStaging = "internal_staging"
    case testFlightInternal = "testflight_internal"
    case testFlightExternal = "testflight_external"
    case macOSSignedUpdate = "macos_signed_update"
    case appStoreProduction = "app_store_production"

    fileprivate var environment: LedgerEnvironmentKind {
        switch self {
        case .localDevelopment:
            return .targetLocal
        case .internalStaging, .testFlightInternal:
            return .targetStaging
        case .testFlightExternal, .macOSSignedUpdate, .appStoreProduction:
            return .targetProduction
        }
    }
}

public enum ReleasePlatform: String, Codable, CaseIterable, Sendable {
    case iOS = "ios"
    case macOS = "macos"
    case universal
    case server
    case migration
}

public enum ReleaseArtifactKind: String, Codable, CaseIterable, Sendable {
    case applicationBundle = "application_bundle"
    case applicationArchive = "application_archive"
    case updateArchive = "update_archive"
    case diskImage = "disk_image"
    case contractCatalog = "contract_catalog"
    case softwareBillOfMaterials = "software_bill_of_materials"
    case migrationBundle = "migration_bundle"
}

public enum ReleaseDependencyEcosystem: String, Codable, CaseIterable, Sendable {
    case swiftPackageManager = "swift_package_manager"
    case npm
}

public enum ReleaseAuthorityDisposition: String, Codable, CaseIterable, Sendable {
    case evidenceOnly = "evidence_only"
}

public struct ReleaseApplicationVersion: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        guard ReleaseManifestValidation.isSafeToken(rawValue, maximumBytes: 32) else {
            throw ReleaseManifestFailure.invalidApplicationVersion
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(validating: container.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid release application version"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ReleaseSourceRevision: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        guard ReleaseManifestValidation.isLowercaseHex(rawValue, lengths: [40, 64]) else {
            throw ReleaseManifestFailure.invalidSourceRevision
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(validating: container.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid release source revision"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ReleaseSHA256: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        guard ReleaseManifestValidation.isLowercaseHex(rawValue, lengths: [64]) else {
            throw ReleaseManifestFailure.invalidSHA256
        }
        self.rawValue = rawValue
    }

    public static func make(bytes: Data) throws -> Self {
        try Self(validating: ReleaseManifestValidation.sha256(bytes))
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(validating: container.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid SHA-256 digest"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ReleaseArtifactID: Codable, Equatable, Hashable, Sendable, Comparable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        guard ReleaseManifestValidation.isStableCode(rawValue) else {
            throw ReleaseManifestFailure.invalidArtifactID
        }
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(validating: container.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid release artifact identifier"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ReleaseDependencyLockID: Codable, Equatable, Hashable, Sendable, Comparable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        guard ReleaseManifestValidation.isStableCode(rawValue) else {
            throw ReleaseManifestFailure.invalidDependencyLockID
        }
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(validating: container.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid dependency lock identifier"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ReleaseBuildIdentity: Codable, Equatable, Sendable {
    public let environment: LedgerEnvironmentKind
    public let buildProfile: LedgerBuildProfile
    public let applicationVersion: ReleaseApplicationVersion
    public let buildNumber: UInt64
    public let sourceRevision: ReleaseSourceRevision
    public let contractVersions: LedgerContractVersions
    public let contractCatalogSHA256: ReleaseSHA256

    public init(
        validatedEnvironment: ValidatedLedgerEnvironment,
        applicationVersion: ReleaseApplicationVersion,
        buildNumber: UInt64,
        sourceRevision: ReleaseSourceRevision,
        contractCatalogSHA256: ReleaseSHA256
    ) throws {
        try self.init(
            environment: validatedEnvironment.manifest.environment,
            buildProfile: validatedEnvironment.manifest.buildProfile,
            applicationVersion: applicationVersion,
            buildNumber: buildNumber,
            sourceRevision: sourceRevision,
            contractVersions: validatedEnvironment.manifest.contractVersions,
            contractCatalogSHA256: contractCatalogSHA256
        )
    }

    private init(
        environment: LedgerEnvironmentKind,
        buildProfile: LedgerBuildProfile,
        applicationVersion: ReleaseApplicationVersion,
        buildNumber: UInt64,
        sourceRevision: ReleaseSourceRevision,
        contractVersions: LedgerContractVersions,
        contractCatalogSHA256: ReleaseSHA256
    ) throws {
        guard buildNumber > 0 else {
            throw ReleaseManifestFailure.invalidBuildNumber
        }
        guard buildProfile.environment == environment else {
            throw ReleaseManifestFailure.buildProfileMismatch
        }
        try ReleaseManifestValidation.validate(contractVersions: contractVersions)

        self.environment = environment
        self.buildProfile = buildProfile
        self.applicationVersion = applicationVersion
        self.buildNumber = buildNumber
        self.sourceRevision = sourceRevision
        self.contractVersions = contractVersions
        self.contractCatalogSHA256 = contractCatalogSHA256
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                environment: container.decode(LedgerEnvironmentKind.self, forKey: .environment),
                buildProfile: container.decode(LedgerBuildProfile.self, forKey: .buildProfile),
                applicationVersion: container.decode(
                    ReleaseApplicationVersion.self,
                    forKey: .applicationVersion
                ),
                buildNumber: container.decode(UInt64.self, forKey: .buildNumber),
                sourceRevision: container.decode(
                    ReleaseSourceRevision.self,
                    forKey: .sourceRevision
                ),
                contractVersions: container.decode(
                    LedgerContractVersions.self,
                    forKey: .contractVersions
                ),
                contractCatalogSHA256: container.decode(
                    ReleaseSHA256.self,
                    forKey: .contractCatalogSHA256
                )
            )
        } catch let failure as ReleaseManifestFailure {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid release build identity: \(failure)"
                )
            )
        }
    }
}

public struct ReleaseArtifactEvidence: Codable, Equatable, Sendable {
    public let id: ReleaseArtifactID
    public let kind: ReleaseArtifactKind
    public let platform: ReleasePlatform
    public let byteCount: UInt64
    public let sha256: ReleaseSHA256

    public static func make(
        id: ReleaseArtifactID,
        kind: ReleaseArtifactKind,
        platform: ReleasePlatform,
        bytes: Data
    ) throws -> Self {
        try Self(
            id: id,
            kind: kind,
            platform: platform,
            byteCount: UInt64(bytes.count),
            sha256: ReleaseSHA256.make(bytes: bytes)
        )
    }

    private init(
        id: ReleaseArtifactID,
        kind: ReleaseArtifactKind,
        platform: ReleasePlatform,
        byteCount: UInt64,
        sha256: ReleaseSHA256
    ) throws {
        guard byteCount > 0 else {
            throw ReleaseManifestFailure.invalidArtifactByteCount(id)
        }
        self.id = id
        self.kind = kind
        self.platform = platform
        self.byteCount = byteCount
        self.sha256 = sha256
    }

    public func verify(bytes: Data) throws {
        guard UInt64(bytes.count) == byteCount else {
            throw ReleaseManifestFailure.artifactByteCountMismatch(id)
        }
        guard try ReleaseSHA256.make(bytes: bytes) == sha256 else {
            throw ReleaseManifestFailure.artifactHashMismatch(id)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                id: container.decode(ReleaseArtifactID.self, forKey: .id),
                kind: container.decode(ReleaseArtifactKind.self, forKey: .kind),
                platform: container.decode(ReleasePlatform.self, forKey: .platform),
                byteCount: container.decode(UInt64.self, forKey: .byteCount),
                sha256: container.decode(ReleaseSHA256.self, forKey: .sha256)
            )
        } catch let failure as ReleaseManifestFailure {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid artifact evidence: \(failure)"
                )
            )
        }
    }
}

public struct ReleaseDependencyLockEvidence: Codable, Equatable, Sendable {
    public let id: ReleaseDependencyLockID
    public let ecosystem: ReleaseDependencyEcosystem
    public let byteCount: UInt64
    public let sha256: ReleaseSHA256

    public static func make(
        id: ReleaseDependencyLockID,
        ecosystem: ReleaseDependencyEcosystem,
        bytes: Data
    ) throws -> Self {
        try Self(
            id: id,
            ecosystem: ecosystem,
            byteCount: UInt64(bytes.count),
            sha256: ReleaseSHA256.make(bytes: bytes)
        )
    }

    private init(
        id: ReleaseDependencyLockID,
        ecosystem: ReleaseDependencyEcosystem,
        byteCount: UInt64,
        sha256: ReleaseSHA256
    ) throws {
        guard byteCount > 0 else {
            throw ReleaseManifestFailure.invalidDependencyLockByteCount(id)
        }
        self.id = id
        self.ecosystem = ecosystem
        self.byteCount = byteCount
        self.sha256 = sha256
    }

    public func verify(bytes: Data) throws {
        guard UInt64(bytes.count) == byteCount else {
            throw ReleaseManifestFailure.dependencyLockByteCountMismatch(id)
        }
        guard try ReleaseSHA256.make(bytes: bytes) == sha256 else {
            throw ReleaseManifestFailure.dependencyLockHashMismatch(id)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                id: container.decode(ReleaseDependencyLockID.self, forKey: .id),
                ecosystem: container.decode(
                    ReleaseDependencyEcosystem.self,
                    forKey: .ecosystem
                ),
                byteCount: container.decode(UInt64.self, forKey: .byteCount),
                sha256: container.decode(ReleaseSHA256.self, forKey: .sha256)
            )
        } catch let failure as ReleaseManifestFailure {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid dependency lock evidence: \(failure)"
                )
            )
        }
    }
}

public struct ReleaseArtifactRequirement: Codable, Equatable, Hashable, Sendable {
    public let id: ReleaseArtifactID
    public let kind: ReleaseArtifactKind
    public let platform: ReleasePlatform

    public init(id: ReleaseArtifactID, kind: ReleaseArtifactKind, platform: ReleasePlatform) {
        self.id = id
        self.kind = kind
        self.platform = platform
    }
}

public struct ReleaseDependencyLockRequirement: Codable, Equatable, Hashable, Sendable {
    public let id: ReleaseDependencyLockID
    public let ecosystem: ReleaseDependencyEcosystem

    public init(id: ReleaseDependencyLockID, ecosystem: ReleaseDependencyEcosystem) {
        self.id = id
        self.ecosystem = ecosystem
    }
}

public struct ReleaseCompatibilityPolicy: Equatable, Sendable {
    public static let maximumArtifactRequirements = 32
    public static let maximumDependencyLockRequirements = 8

    public let expectedEnvironment: LedgerEnvironmentKind
    public let expectedBuildProfile: LedgerBuildProfile
    public let expectedContractVersions: LedgerContractVersions
    public let expectedContractCatalogSHA256: ReleaseSHA256
    public let allowedChannels: [ReleaseChannel]
    public let requiredArtifacts: [ReleaseArtifactRequirement]
    public let requiredDependencyLocks: [ReleaseDependencyLockRequirement]

    public init(
        validatedEnvironment: ValidatedLedgerEnvironment,
        expectedContractCatalogSHA256: ReleaseSHA256,
        allowedChannels: [ReleaseChannel],
        requiredArtifacts: [ReleaseArtifactRequirement],
        requiredDependencyLocks: [ReleaseDependencyLockRequirement]
    ) throws {
        let environment = validatedEnvironment.manifest.environment
        guard !allowedChannels.isEmpty else {
            throw ReleaseManifestFailure.emptyAllowedChannels
        }
        for channel in allowedChannels where channel.environment != environment {
            throw ReleaseManifestFailure.channelEnvironmentMismatch(channel)
        }
        guard !requiredArtifacts.isEmpty else {
            throw ReleaseManifestFailure.emptyArtifactRequirements
        }
        guard requiredArtifacts.count <= Self.maximumArtifactRequirements else {
            throw ReleaseManifestFailure.tooManyArtifactRequirements(
                maximum: Self.maximumArtifactRequirements
            )
        }
        guard !requiredDependencyLocks.isEmpty else {
            throw ReleaseManifestFailure.emptyDependencyLockRequirements
        }
        guard requiredDependencyLocks.count <= Self.maximumDependencyLockRequirements else {
            throw ReleaseManifestFailure.tooManyDependencyLockRequirements(
                maximum: Self.maximumDependencyLockRequirements
            )
        }
        try ReleaseManifestValidation.requireUnique(
            requiredArtifacts.map(\.id),
            failure: ReleaseManifestFailure.duplicateArtifactRequirement
        )
        try ReleaseManifestValidation.requireUnique(
            requiredDependencyLocks.map(\.id),
            failure: ReleaseManifestFailure.duplicateDependencyLockRequirement
        )

        expectedEnvironment = environment
        expectedBuildProfile = validatedEnvironment.manifest.buildProfile
        expectedContractVersions = validatedEnvironment.manifest.contractVersions
        self.expectedContractCatalogSHA256 = expectedContractCatalogSHA256
        self.allowedChannels = Array(Set(allowedChannels)).sorted { $0.rawValue < $1.rawValue }
        self.requiredArtifacts = requiredArtifacts.sorted { $0.id < $1.id }
        self.requiredDependencyLocks = requiredDependencyLocks.sorted { $0.id < $1.id }
    }
}

public struct LedgerReleaseManifestDraft: Sendable {
    public let build: ReleaseBuildIdentity
    public let channel: ReleaseChannel
    public let producedAt: Date
    public let artifacts: [ReleaseArtifactEvidence]
    public let dependencyLocks: [ReleaseDependencyLockEvidence]

    public init(
        build: ReleaseBuildIdentity,
        channel: ReleaseChannel,
        producedAt: Date,
        artifacts: [ReleaseArtifactEvidence],
        dependencyLocks: [ReleaseDependencyLockEvidence]
    ) {
        self.build = build
        self.channel = channel
        self.producedAt = producedAt
        self.artifacts = artifacts
        self.dependencyLocks = dependencyLocks
    }
}

public struct LedgerReleaseManifest: Encodable, Equatable, Sendable {
    public let schemaVersion: UInt16
    public let build: ReleaseBuildIdentity
    public let channel: ReleaseChannel
    public let producedAt: Date
    public let artifacts: [ReleaseArtifactEvidence]
    public let dependencyLocks: [ReleaseDependencyLockEvidence]
    public let authorityDisposition: ReleaseAuthorityDisposition
    public let contentDigest: ReleaseSHA256

    fileprivate init(
        schemaVersion: UInt16,
        build: ReleaseBuildIdentity,
        channel: ReleaseChannel,
        producedAt: Date,
        artifacts: [ReleaseArtifactEvidence],
        dependencyLocks: [ReleaseDependencyLockEvidence],
        authorityDisposition: ReleaseAuthorityDisposition,
        contentDigest: ReleaseSHA256
    ) {
        self.schemaVersion = schemaVersion
        self.build = build
        self.channel = channel
        self.producedAt = producedAt
        self.artifacts = artifacts
        self.dependencyLocks = dependencyLocks
        self.authorityDisposition = authorityDisposition
        self.contentDigest = contentDigest
    }
}

private struct ReleaseManifestContent: Encodable {
    let schemaVersion: UInt16
    let build: ReleaseBuildIdentity
    let channel: ReleaseChannel
    let producedAt: Date
    let artifacts: [ReleaseArtifactEvidence]
    let dependencyLocks: [ReleaseDependencyLockEvidence]
    let authorityDisposition: ReleaseAuthorityDisposition
}

private struct ReleaseManifestWire: Codable {
    let schemaVersion: UInt16
    let build: ReleaseBuildIdentity
    let channel: ReleaseChannel
    let producedAt: Date
    let artifacts: [ReleaseArtifactEvidence]
    let dependencyLocks: [ReleaseDependencyLockEvidence]
    let authorityDisposition: ReleaseAuthorityDisposition
    let contentDigest: ReleaseSHA256
}

public struct ReleaseManifestValidator: Sendable {
    public static let schemaVersion: UInt16 = 1
    public static let maximumCanonicalManifestBytes = 4_096

    public let policy: ReleaseCompatibilityPolicy

    public init(policy: ReleaseCompatibilityPolicy) {
        self.policy = policy
    }

    public func validate(_ draft: LedgerReleaseManifestDraft) throws -> LedgerReleaseManifest {
        try validate(build: draft.build, channel: draft.channel)
        try ReleaseManifestValidation.validate(producedAt: draft.producedAt)
        try validate(artifacts: draft.artifacts)
        try validate(dependencyLocks: draft.dependencyLocks)

        let artifacts = draft.artifacts.sorted { $0.id < $1.id }
        let dependencyLocks = draft.dependencyLocks.sorted { $0.id < $1.id }
        let content = ReleaseManifestContent(
            schemaVersion: Self.schemaVersion,
            build: draft.build,
            channel: draft.channel,
            producedAt: draft.producedAt,
            artifacts: artifacts,
            dependencyLocks: dependencyLocks,
            authorityDisposition: .evidenceOnly
        )
        let contentDigest = try ReleaseSHA256.make(bytes: Self.encode(content))
        let manifest = LedgerReleaseManifest(
            schemaVersion: Self.schemaVersion,
            build: draft.build,
            channel: draft.channel,
            producedAt: draft.producedAt,
            artifacts: artifacts,
            dependencyLocks: dependencyLocks,
            authorityDisposition: .evidenceOnly,
            contentDigest: contentDigest
        )
        _ = try canonicalData(for: manifest)
        return manifest
    }

    public func canonicalData(for manifest: LedgerReleaseManifest) throws -> Data {
        let data = try Self.encode(manifest)
        guard data.count <= Self.maximumCanonicalManifestBytes else {
            throw ReleaseManifestFailure.manifestTooLarge(
                actual: data.count,
                maximum: Self.maximumCanonicalManifestBytes
            )
        }
        return data
    }

    public func decodeAndValidate(_ data: Data) throws -> LedgerReleaseManifest {
        guard data.count <= Self.maximumCanonicalManifestBytes else {
            throw ReleaseManifestFailure.manifestTooLarge(
                actual: data.count,
                maximum: Self.maximumCanonicalManifestBytes
            )
        }

        let wire: ReleaseManifestWire
        do {
            wire = try Self.decode(ReleaseManifestWire.self, from: data)
        } catch {
            throw ReleaseManifestFailure.malformedManifest
        }
        guard wire.schemaVersion == Self.schemaVersion else {
            throw ReleaseManifestFailure.schemaVersionMismatch
        }
        guard wire.authorityDisposition == .evidenceOnly else {
            throw ReleaseManifestFailure.authorityDispositionMismatch
        }

        let validated = try validate(
            LedgerReleaseManifestDraft(
                build: wire.build,
                channel: wire.channel,
                producedAt: wire.producedAt,
                artifacts: wire.artifacts,
                dependencyLocks: wire.dependencyLocks
            )
        )
        guard validated.contentDigest == wire.contentDigest else {
            throw ReleaseManifestFailure.contentDigestMismatch
        }
        guard try canonicalData(for: validated) == data else {
            throw ReleaseManifestFailure.noncanonicalManifest
        }
        return validated
    }

    private func validate(build: ReleaseBuildIdentity, channel: ReleaseChannel) throws {
        guard build.environment == policy.expectedEnvironment else {
            throw ReleaseManifestFailure.environmentMismatch
        }
        guard build.buildProfile == policy.expectedBuildProfile else {
            throw ReleaseManifestFailure.buildProfileMismatch
        }
        guard channel.environment == build.environment else {
            throw ReleaseManifestFailure.channelEnvironmentMismatch(channel)
        }
        guard policy.allowedChannels.contains(channel) else {
            throw ReleaseManifestFailure.channelNotAllowed(channel)
        }
        if let mismatch = ReleaseManifestValidation.firstContractMismatch(
            build.contractVersions,
            policy.expectedContractVersions
        ) {
            throw ReleaseManifestFailure.contractVersionMismatch(mismatch)
        }
        guard build.contractCatalogSHA256 == policy.expectedContractCatalogSHA256 else {
            throw ReleaseManifestFailure.contractCatalogHashMismatch
        }
    }

    private func validate(artifacts: [ReleaseArtifactEvidence]) throws {
        try ReleaseManifestValidation.requireUnique(
            artifacts.map(\.id),
            failure: ReleaseManifestFailure.duplicateArtifactEvidence
        )
        let requirements = Dictionary(
            uniqueKeysWithValues: policy.requiredArtifacts.map { ($0.id, $0) }
        )
        let evidence = Dictionary(uniqueKeysWithValues: artifacts.map { ($0.id, $0) })

        for requirement in policy.requiredArtifacts {
            guard let artifact = evidence[requirement.id] else {
                throw ReleaseManifestFailure.missingArtifactEvidence(requirement.id)
            }
            guard artifact.kind == requirement.kind,
                  artifact.platform == requirement.platform else {
                throw ReleaseManifestFailure.artifactRequirementMismatch(requirement.id)
            }
        }
        for artifact in artifacts where requirements[artifact.id] == nil {
            throw ReleaseManifestFailure.unexpectedArtifactEvidence(artifact.id)
        }
    }

    private func validate(dependencyLocks: [ReleaseDependencyLockEvidence]) throws {
        try ReleaseManifestValidation.requireUnique(
            dependencyLocks.map(\.id),
            failure: ReleaseManifestFailure.duplicateDependencyLockEvidence
        )
        let requirements = Dictionary(
            uniqueKeysWithValues: policy.requiredDependencyLocks.map { ($0.id, $0) }
        )
        let evidence = Dictionary(uniqueKeysWithValues: dependencyLocks.map { ($0.id, $0) })

        for requirement in policy.requiredDependencyLocks {
            guard let lock = evidence[requirement.id] else {
                throw ReleaseManifestFailure.missingDependencyLockEvidence(requirement.id)
            }
            guard lock.ecosystem == requirement.ecosystem else {
                throw ReleaseManifestFailure.dependencyLockRequirementMismatch(requirement.id)
            }
        }
        for lock in dependencyLocks where requirements[lock.id] == nil {
            throw ReleaseManifestFailure.unexpectedDependencyLockEvidence(lock.id)
        }
    }

    private static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(value)
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data
    ) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: data)
    }
}

private enum ReleaseManifestValidation {
    static func isSafeToken(_ value: String, maximumBytes: Int) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.isEmpty
            && value.utf8.count <= maximumBytes
            && value.unicodeScalars.allSatisfy(allowed.contains)
    }

    static func isLowercaseHex(_ value: String, lengths: Set<Int>) -> Bool {
        let allowed = CharacterSet(charactersIn: "0123456789abcdef")
        return lengths.contains(value.utf8.count)
            && value.unicodeScalars.allSatisfy(allowed.contains)
    }

    static func isStableCode(_ value: String) -> Bool {
        let allowed = CharacterSet.lowercaseLetters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: "_"))
        return value.utf8.count >= 3
            && value.utf8.count <= 80
            && value.first?.isLetter == true
            && value.unicodeScalars.allSatisfy(allowed.contains)
    }

    static func validate(contractVersions: LedgerContractVersions) throws {
        let versions = [
            ("schema", contractVersions.schema),
            ("query", contractVersions.query),
            ("operation", contractVersions.operation),
            ("sync", contractVersions.sync)
        ]
        for (name, value) in versions where !isSafeToken(value, maximumBytes: 32) {
            throw ReleaseManifestFailure.invalidContractVersion(name)
        }
    }

    static func validate(producedAt: Date) throws {
        let milliseconds = producedAt.timeIntervalSince1970 * 1_000
        guard milliseconds.isFinite,
              milliseconds >= 0,
              milliseconds.rounded(.towardZero) == milliseconds else {
            throw ReleaseManifestFailure.invalidProducedAt
        }
    }

    static func firstContractMismatch(
        _ actual: LedgerContractVersions,
        _ expected: LedgerContractVersions
    ) -> String? {
        if actual.schema != expected.schema { return "schema" }
        if actual.query != expected.query { return "query" }
        if actual.operation != expected.operation { return "operation" }
        if actual.sync != expected.sync { return "sync" }
        return nil
    }

    static func requireUnique<Value: Hashable>(
        _ values: [Value],
        failure: (Value) -> ReleaseManifestFailure
    ) throws {
        var seen: Set<Value> = []
        for value in values where !seen.insert(value).inserted {
            throw failure(value)
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
