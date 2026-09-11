import CryptoKit
import Foundation
import LedgerTargetCore

public enum MigrationIntegrityFailure: Error, Equatable, Sendable {
    case invalidOpaqueIdentifier(String)
    case invalidStableCode(String)
    case invalidVersion(String)
    case invalidSHA256(String)
    case invalidSourceRevision
    case invalidTimestamp(String)
    case invalidByteCount(String)
    case invalidCount(String)
    case emptyMappingArtifacts
    case emptyEntityPlans
    case duplicateMappingArtifact(MigrationStableCode)
    case duplicateEntity(MigrationStableCode)
    case tooManyMappingArtifacts(maximum: Int)
    case tooManyEntityPlans(maximum: Int)
    case sourceEnvironmentNotAllowed
    case runModeNotAllowed
    case targetEnvironmentMismatch
    case targetBindingMismatch
    case contractVersionInvalid(String)
    case contractVersionMismatch(String)
    case migrationArtifactMismatch
    case mappingArtifactSetMismatch
    case sourceCapturedAfterPlan
    case planDigestMismatch
    case noncanonicalPlan
    case planTooLarge(actual: Int, maximum: Int)
    case malformedPlan
    case journalPlanMismatch
    case journalDigestMismatch
    case journalTooLarge(actual: Int, maximum: Int)
    case malformedJournal
    case noncanonicalJournal
    case tooManyJournalEvents(maximum: Int)
    case invalidEventSequence
    case eventReplayConflict(sequence: Int)
    case eventDigestMismatch(sequence: Int)
    case eventEntitySetMismatch(sequence: Int)
    case eventTimestampRegression(sequence: Int)
    case eventStageRegression(sequence: Int)
    case eventStageSkipped(sequence: Int)
    case illegalEventTransition(sequence: Int)
    case eventCountRegression(sequence: Int, entity: MigrationStableCode)
    case eventCountExceedsPlan(sequence: Int, entity: MigrationStableCode)
    case duplicateEventEntity(sequence: Int, entity: MigrationStableCode)
    case terminalJournal
    case emptyJournal
    case invalidReconciliationDifference(MigrationStableCode)
    case duplicateReconciliationRule(MigrationStableCode)
    case reconciliationRuleSetMismatch
    case terminalDispositionMismatch
    case terminalReasonMissing
    case terminalReasonUnexpected
    case incompleteEntityOutcome(MigrationStableCode)
    case dryRunAppliedCount(MigrationStableCode)
    case applyOutcomeMismatch(MigrationStableCode)
    case incompleteReconciliation(MigrationStableCode)
    case unexplainedReconciliation(MigrationStableCode)
    case manifestEndedBeforeJournal
    case manifestDigestMismatch
    case noncanonicalManifest
    case manifestTooLarge(actual: Int, maximum: Int)
    case malformedManifest

    public var diagnosticCode: String {
        switch self {
        case .invalidOpaqueIdentifier: return "migration_opaque_id_invalid"
        case .invalidStableCode: return "migration_stable_code_invalid"
        case .invalidVersion: return "migration_version_invalid"
        case .invalidSHA256: return "migration_sha256_invalid"
        case .invalidSourceRevision: return "migration_source_revision_invalid"
        case .invalidTimestamp: return "migration_timestamp_invalid"
        case .invalidByteCount: return "migration_byte_count_invalid"
        case .invalidCount: return "migration_count_invalid"
        case .emptyMappingArtifacts: return "migration_mapping_artifacts_empty"
        case .emptyEntityPlans: return "migration_entity_plans_empty"
        case .duplicateMappingArtifact: return "migration_mapping_artifact_duplicate"
        case .duplicateEntity: return "migration_entity_duplicate"
        case .tooManyMappingArtifacts: return "migration_mapping_artifacts_too_many"
        case .tooManyEntityPlans: return "migration_entity_plans_too_many"
        case .sourceEnvironmentNotAllowed: return "migration_source_environment_not_allowed"
        case .runModeNotAllowed: return "migration_run_mode_not_allowed"
        case .targetEnvironmentMismatch: return "migration_target_environment_mismatch"
        case .targetBindingMismatch: return "migration_target_binding_mismatch"
        case .contractVersionInvalid(let field): return "migration_contract_version_invalid_\(field)"
        case .contractVersionMismatch(let field): return "migration_contract_version_mismatch_\(field)"
        case .migrationArtifactMismatch: return "migration_artifact_mismatch"
        case .mappingArtifactSetMismatch: return "migration_mapping_artifact_set_mismatch"
        case .sourceCapturedAfterPlan: return "migration_source_captured_after_plan"
        case .planDigestMismatch: return "migration_plan_digest_mismatch"
        case .noncanonicalPlan: return "migration_plan_noncanonical"
        case .planTooLarge: return "migration_plan_too_large"
        case .malformedPlan: return "migration_plan_malformed"
        case .journalPlanMismatch: return "migration_journal_plan_mismatch"
        case .journalDigestMismatch: return "migration_journal_digest_mismatch"
        case .journalTooLarge: return "migration_journal_too_large"
        case .malformedJournal: return "migration_journal_malformed"
        case .noncanonicalJournal: return "migration_journal_noncanonical"
        case .tooManyJournalEvents: return "migration_journal_events_too_many"
        case .invalidEventSequence: return "migration_event_sequence_invalid"
        case .eventReplayConflict: return "migration_event_replay_conflict"
        case .eventDigestMismatch: return "migration_event_digest_mismatch"
        case .eventEntitySetMismatch: return "migration_event_entity_set_mismatch"
        case .eventTimestampRegression: return "migration_event_timestamp_regression"
        case .eventStageRegression: return "migration_event_stage_regression"
        case .eventStageSkipped: return "migration_event_stage_skipped"
        case .illegalEventTransition: return "migration_event_transition_illegal"
        case .eventCountRegression: return "migration_event_count_regression"
        case .eventCountExceedsPlan: return "migration_event_count_exceeds_plan"
        case .duplicateEventEntity: return "migration_event_entity_duplicate"
        case .terminalJournal: return "migration_journal_terminal"
        case .emptyJournal: return "migration_journal_empty"
        case .invalidReconciliationDifference: return "migration_reconciliation_difference_invalid"
        case .duplicateReconciliationRule: return "migration_reconciliation_rule_duplicate"
        case .reconciliationRuleSetMismatch: return "migration_reconciliation_rule_set_mismatch"
        case .terminalDispositionMismatch: return "migration_terminal_disposition_mismatch"
        case .terminalReasonMissing: return "migration_terminal_reason_missing"
        case .terminalReasonUnexpected: return "migration_terminal_reason_unexpected"
        case .incompleteEntityOutcome: return "migration_entity_outcome_incomplete"
        case .dryRunAppliedCount: return "migration_dry_run_applied_count"
        case .applyOutcomeMismatch: return "migration_apply_outcome_mismatch"
        case .incompleteReconciliation: return "migration_reconciliation_incomplete"
        case .unexplainedReconciliation: return "migration_reconciliation_unexplained"
        case .manifestEndedBeforeJournal: return "migration_manifest_ended_before_journal"
        case .manifestDigestMismatch: return "migration_manifest_digest_mismatch"
        case .noncanonicalManifest: return "migration_manifest_noncanonical"
        case .manifestTooLarge: return "migration_manifest_too_large"
        case .malformedManifest: return "migration_manifest_malformed"
        }
    }
}

public struct MigrationOpaqueID: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String, field: String) throws {
        guard MigrationIntegrityValidation.isLowercaseHex(rawValue, lengths: [32]) else {
            throw MigrationIntegrityFailure.invalidOpaqueIdentifier(field)
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(validating: container.decode(String.self), field: "decoded")
        } catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid migration opaque identifier")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct MigrationStableCode: Codable, Equatable, Hashable, Sendable, Comparable {
    public let rawValue: String

    public init(validating rawValue: String, field: String) throws {
        guard MigrationIntegrityValidation.isStableCode(rawValue) else {
            throw MigrationIntegrityFailure.invalidStableCode(field)
        }
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(validating: container.decode(String.self), field: "decoded")
        } catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid migration stable code")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct MigrationVersion: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String, field: String) throws {
        guard MigrationIntegrityValidation.isVersion(rawValue) else {
            throw MigrationIntegrityFailure.invalidVersion(field)
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(validating: container.decode(String.self), field: "decoded")
        } catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid migration version")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct MigrationSHA256: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String, field: String) throws {
        guard MigrationIntegrityValidation.isLowercaseHex(rawValue, lengths: [64]) else {
            throw MigrationIntegrityFailure.invalidSHA256(field)
        }
        self.rawValue = rawValue
    }

    public static func make(bytes: Data) throws -> Self {
        try Self(validating: MigrationIntegrityValidation.sha256(bytes), field: "bytes")
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(validating: container.decode(String.self), field: "decoded")
        } catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid migration SHA-256")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct MigrationSourceRevision: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        guard MigrationIntegrityValidation.isLowercaseHex(rawValue, lengths: [40, 64]) else {
            throw MigrationIntegrityFailure.invalidSourceRevision
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(validating: container.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid migration source revision")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum MigrationSourceEnvironment: String, Codable, CaseIterable, Sendable {
    case sourceFixture = "source_fixture"
    case sourceProduction = "source_production"
}

public enum MigrationRunMode: String, Codable, CaseIterable, Sendable {
    case dryRun = "dry_run"
    case apply
}

public enum MigrationAuthorityDisposition: String, Codable, Sendable {
    case evidenceOnly = "evidence_only"
}

public struct MigrationSourceSnapshot: Codable, Equatable, Sendable {
    public let environment: MigrationSourceEnvironment
    public let exportID: MigrationOpaqueID
    public let capturedAtEpochMilliseconds: Int64
    public let byteCount: Int64
    public let sha256: MigrationSHA256

    public init(
        environment: MigrationSourceEnvironment,
        exportID: MigrationOpaqueID,
        capturedAtEpochMilliseconds: Int64,
        byteCount: Int64,
        sha256: MigrationSHA256
    ) throws {
        guard capturedAtEpochMilliseconds > 0 else {
            throw MigrationIntegrityFailure.invalidTimestamp("source_capture")
        }
        guard byteCount > 0 else {
            throw MigrationIntegrityFailure.invalidByteCount("source_export")
        }
        self.environment = environment
        self.exportID = exportID
        self.capturedAtEpochMilliseconds = capturedAtEpochMilliseconds
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

public struct MigrationTargetBinding: Codable, Equatable, Sendable {
    public let environment: LedgerEnvironmentKind
    public let environmentManifestSHA256: MigrationSHA256
    public let structuredDataResourceSHA256: MigrationSHA256
    public let storageResourceSHA256: MigrationSHA256

    private init(
        environment: LedgerEnvironmentKind,
        environmentManifestSHA256: MigrationSHA256,
        structuredDataResourceSHA256: MigrationSHA256,
        storageResourceSHA256: MigrationSHA256
    ) {
        self.environment = environment
        self.environmentManifestSHA256 = environmentManifestSHA256
        self.structuredDataResourceSHA256 = structuredDataResourceSHA256
        self.storageResourceSHA256 = storageResourceSHA256
    }

    public static func make(validatedEnvironment: ValidatedLedgerEnvironment) throws -> Self {
        let binding = validatedEnvironment.persistenceBinding
        let structuredData = validatedEnvironment.resource(.structuredData)
        let storage = validatedEnvironment.resource(.storage)
        return Self(
            environment: validatedEnvironment.manifest.environment,
            environmentManifestSHA256: try MigrationSHA256(
                validating: binding.manifestDigest,
                field: "target_environment_manifest"
            ),
            structuredDataResourceSHA256: try .make(bytes: Data(structuredData.publicIdentifier.utf8)),
            storageResourceSHA256: try .make(bytes: Data(storage.publicIdentifier.utf8))
        )
    }
}

public struct MigrationArtifactIdentity: Codable, Equatable, Sendable {
    public let id: MigrationStableCode
    public let version: MigrationVersion
    public let byteCount: Int64
    public let sha256: MigrationSHA256

    public init(
        id: MigrationStableCode,
        version: MigrationVersion,
        byteCount: Int64,
        sha256: MigrationSHA256
    ) throws {
        guard byteCount > 0 else {
            throw MigrationIntegrityFailure.invalidByteCount(id.rawValue)
        }
        self.id = id
        self.version = version
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

public struct MigrationEntityPlan: Codable, Equatable, Sendable {
    public let entity: MigrationStableCode
    public let plannedCount: Int64
    public let sourceSHA256: MigrationSHA256
    public let transformVersion: MigrationVersion

    public init(
        entity: MigrationStableCode,
        plannedCount: Int64,
        sourceSHA256: MigrationSHA256,
        transformVersion: MigrationVersion
    ) throws {
        guard plannedCount >= 0 else {
            throw MigrationIntegrityFailure.invalidCount(entity.rawValue)
        }
        self.entity = entity
        self.plannedCount = plannedCount
        self.sourceSHA256 = sourceSHA256
        self.transformVersion = transformVersion
    }
}

public struct MigrationRunPlanDraft: Sendable {
    public let runID: MigrationOpaqueID
    public let mode: MigrationRunMode
    public let source: MigrationSourceSnapshot
    public let target: MigrationTargetBinding
    public let accountScopeSHA256: MigrationSHA256
    public let repositoryRevision: MigrationSourceRevision
    public let contractVersions: LedgerContractVersions
    public let migrationArtifact: MigrationArtifactIdentity
    public let mappingArtifacts: [MigrationArtifactIdentity]
    public let entityPlans: [MigrationEntityPlan]
    public let createdAtEpochMilliseconds: Int64

    public init(
        runID: MigrationOpaqueID,
        mode: MigrationRunMode,
        source: MigrationSourceSnapshot,
        target: MigrationTargetBinding,
        accountScopeSHA256: MigrationSHA256,
        repositoryRevision: MigrationSourceRevision,
        contractVersions: LedgerContractVersions,
        migrationArtifact: MigrationArtifactIdentity,
        mappingArtifacts: [MigrationArtifactIdentity],
        entityPlans: [MigrationEntityPlan],
        createdAtEpochMilliseconds: Int64
    ) {
        self.runID = runID
        self.mode = mode
        self.source = source
        self.target = target
        self.accountScopeSHA256 = accountScopeSHA256
        self.repositoryRevision = repositoryRevision
        self.contractVersions = contractVersions
        self.migrationArtifact = migrationArtifact
        self.mappingArtifacts = mappingArtifacts
        self.entityPlans = entityPlans
        self.createdAtEpochMilliseconds = createdAtEpochMilliseconds
    }
}

public struct MigrationRunPlan: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let runID: MigrationOpaqueID
    public let mode: MigrationRunMode
    public let source: MigrationSourceSnapshot
    public let target: MigrationTargetBinding
    public let accountScopeSHA256: MigrationSHA256
    public let repositoryRevision: MigrationSourceRevision
    public let contractVersions: LedgerContractVersions
    public let migrationArtifact: MigrationArtifactIdentity
    public let mappingArtifacts: [MigrationArtifactIdentity]
    public let entityPlans: [MigrationEntityPlan]
    public let createdAtEpochMilliseconds: Int64
    public let authorityDisposition: MigrationAuthorityDisposition
    public let contentDigest: MigrationSHA256

    fileprivate var draft: MigrationRunPlanDraft {
        MigrationRunPlanDraft(
            runID: runID,
            mode: mode,
            source: source,
            target: target,
            accountScopeSHA256: accountScopeSHA256,
            repositoryRevision: repositoryRevision,
            contractVersions: contractVersions,
            migrationArtifact: migrationArtifact,
            mappingArtifacts: mappingArtifacts,
            entityPlans: entityPlans,
            createdAtEpochMilliseconds: createdAtEpochMilliseconds
        )
    }
}

public struct MigrationRunPlanPolicy: Sendable {
    public let expectedTarget: MigrationTargetBinding
    public let expectedContractVersions: LedgerContractVersions
    public let expectedMigrationArtifact: MigrationArtifactIdentity
    public let expectedMappingArtifacts: [MigrationArtifactIdentity]
    public let allowedSourceEnvironments: Set<MigrationSourceEnvironment>
    public let allowedModes: Set<MigrationRunMode>

    public init(
        expectedTarget: MigrationTargetBinding,
        expectedContractVersions: LedgerContractVersions,
        expectedMigrationArtifact: MigrationArtifactIdentity,
        expectedMappingArtifacts: [MigrationArtifactIdentity],
        allowedSourceEnvironments: Set<MigrationSourceEnvironment>,
        allowedModes: Set<MigrationRunMode>
    ) {
        self.expectedTarget = expectedTarget
        self.expectedContractVersions = expectedContractVersions
        self.expectedMigrationArtifact = expectedMigrationArtifact
        self.expectedMappingArtifacts = expectedMappingArtifacts
        self.allowedSourceEnvironments = allowedSourceEnvironments
        self.allowedModes = allowedModes
    }
}

public struct MigrationRunPlanValidator: Sendable {
    public static let schemaVersion = 1
    public static let maximumMappingArtifacts = 64
    public static let maximumEntityPlans = 256
    public static let maximumCanonicalPlanBytes = 32_768

    public let policy: MigrationRunPlanPolicy

    public init(policy: MigrationRunPlanPolicy) {
        self.policy = policy
    }

    public func validate(_ draft: MigrationRunPlanDraft) throws -> MigrationRunPlan {
        guard draft.createdAtEpochMilliseconds > 0 else {
            throw MigrationIntegrityFailure.invalidTimestamp("plan_created")
        }
        guard draft.source.capturedAtEpochMilliseconds > 0 else {
            throw MigrationIntegrityFailure.invalidTimestamp("source_capture")
        }
        guard draft.source.byteCount > 0 else {
            throw MigrationIntegrityFailure.invalidByteCount("source_export")
        }
        guard draft.source.capturedAtEpochMilliseconds <= draft.createdAtEpochMilliseconds else {
            throw MigrationIntegrityFailure.sourceCapturedAfterPlan
        }
        guard policy.allowedSourceEnvironments.contains(draft.source.environment) else {
            throw MigrationIntegrityFailure.sourceEnvironmentNotAllowed
        }
        guard policy.allowedModes.contains(draft.mode) else {
            throw MigrationIntegrityFailure.runModeNotAllowed
        }
        guard draft.target.environment == policy.expectedTarget.environment else {
            throw MigrationIntegrityFailure.targetEnvironmentMismatch
        }
        guard draft.target == policy.expectedTarget else {
            throw MigrationIntegrityFailure.targetBindingMismatch
        }
        try MigrationIntegrityValidation.validateContracts(draft.contractVersions)
        try MigrationIntegrityValidation.validateContracts(policy.expectedContractVersions)
        if let mismatch = MigrationIntegrityValidation.contractMismatch(
            draft.contractVersions,
            policy.expectedContractVersions
        ) {
            throw MigrationIntegrityFailure.contractVersionMismatch(mismatch)
        }
        guard draft.migrationArtifact == policy.expectedMigrationArtifact else {
            throw MigrationIntegrityFailure.migrationArtifactMismatch
        }
        guard draft.migrationArtifact.byteCount > 0 else {
            throw MigrationIntegrityFailure.invalidByteCount(draft.migrationArtifact.id.rawValue)
        }
        guard !draft.mappingArtifacts.isEmpty else {
            throw MigrationIntegrityFailure.emptyMappingArtifacts
        }
        guard draft.mappingArtifacts.count <= Self.maximumMappingArtifacts else {
            throw MigrationIntegrityFailure.tooManyMappingArtifacts(maximum: Self.maximumMappingArtifacts)
        }
        guard !draft.entityPlans.isEmpty else {
            throw MigrationIntegrityFailure.emptyEntityPlans
        }
        guard draft.entityPlans.count <= Self.maximumEntityPlans else {
            throw MigrationIntegrityFailure.tooManyEntityPlans(maximum: Self.maximumEntityPlans)
        }

        let mappings = try normalizeArtifacts(draft.mappingArtifacts)
        let expectedMappings = try normalizeArtifacts(policy.expectedMappingArtifacts)
        guard mappings == expectedMappings else {
            throw MigrationIntegrityFailure.mappingArtifactSetMismatch
        }
        let entities = try normalizeEntities(draft.entityPlans)

        let content = MigrationRunPlanContent(
            schemaVersion: Self.schemaVersion,
            runID: draft.runID,
            mode: draft.mode,
            source: draft.source,
            target: draft.target,
            accountScopeSHA256: draft.accountScopeSHA256,
            repositoryRevision: draft.repositoryRevision,
            contractVersions: draft.contractVersions,
            migrationArtifact: draft.migrationArtifact,
            mappingArtifacts: mappings,
            entityPlans: entities,
            createdAtEpochMilliseconds: draft.createdAtEpochMilliseconds,
            authorityDisposition: .evidenceOnly
        )
        let contentDigest = try MigrationSHA256.make(bytes: MigrationCanonical.encode(content))
        let plan = MigrationRunPlan(
            schemaVersion: content.schemaVersion,
            runID: content.runID,
            mode: content.mode,
            source: content.source,
            target: content.target,
            accountScopeSHA256: content.accountScopeSHA256,
            repositoryRevision: content.repositoryRevision,
            contractVersions: content.contractVersions,
            migrationArtifact: content.migrationArtifact,
            mappingArtifacts: content.mappingArtifacts,
            entityPlans: content.entityPlans,
            createdAtEpochMilliseconds: content.createdAtEpochMilliseconds,
            authorityDisposition: content.authorityDisposition,
            contentDigest: contentDigest
        )
        let canonical = try MigrationCanonical.encode(plan)
        guard canonical.count <= Self.maximumCanonicalPlanBytes else {
            throw MigrationIntegrityFailure.planTooLarge(
                actual: canonical.count,
                maximum: Self.maximumCanonicalPlanBytes
            )
        }
        return plan
    }

    public func canonicalData(for plan: MigrationRunPlan) throws -> Data {
        let validated = try validate(plan.draft)
        guard validated.contentDigest == plan.contentDigest else {
            throw MigrationIntegrityFailure.planDigestMismatch
        }
        guard validated == plan else {
            throw MigrationIntegrityFailure.noncanonicalPlan
        }
        return try MigrationCanonical.encode(validated)
    }

    public func decodeAndValidate(_ data: Data) throws -> MigrationRunPlan {
        guard data.count <= Self.maximumCanonicalPlanBytes else {
            throw MigrationIntegrityFailure.planTooLarge(
                actual: data.count,
                maximum: Self.maximumCanonicalPlanBytes
            )
        }
        let decoded: MigrationRunPlan
        do {
            decoded = try MigrationCanonical.decode(MigrationRunPlan.self, from: data)
        } catch {
            throw MigrationIntegrityFailure.malformedPlan
        }
        let validated = try validate(decoded.draft)
        guard validated.contentDigest == decoded.contentDigest else {
            throw MigrationIntegrityFailure.planDigestMismatch
        }
        guard validated == decoded, try MigrationCanonical.encode(validated) == data else {
            throw MigrationIntegrityFailure.noncanonicalPlan
        }
        return validated
    }

    private func normalizeArtifacts(
        _ artifacts: [MigrationArtifactIdentity]
    ) throws -> [MigrationArtifactIdentity] {
        var seen: Set<MigrationStableCode> = []
        for artifact in artifacts {
            guard artifact.byteCount > 0 else {
                throw MigrationIntegrityFailure.invalidByteCount(artifact.id.rawValue)
            }
            guard seen.insert(artifact.id).inserted else {
                throw MigrationIntegrityFailure.duplicateMappingArtifact(artifact.id)
            }
        }
        return artifacts.sorted { $0.id < $1.id }
    }

    private func normalizeEntities(_ entities: [MigrationEntityPlan]) throws -> [MigrationEntityPlan] {
        var seen: Set<MigrationStableCode> = []
        for entity in entities {
            guard entity.plannedCount >= 0 else {
                throw MigrationIntegrityFailure.invalidCount(entity.entity.rawValue)
            }
            guard seen.insert(entity.entity).inserted else {
                throw MigrationIntegrityFailure.duplicateEntity(entity.entity)
            }
        }
        return entities.sorted { $0.entity < $1.entity }
    }
}

private struct MigrationRunPlanContent: Codable {
    let schemaVersion: Int
    let runID: MigrationOpaqueID
    let mode: MigrationRunMode
    let source: MigrationSourceSnapshot
    let target: MigrationTargetBinding
    let accountScopeSHA256: MigrationSHA256
    let repositoryRevision: MigrationSourceRevision
    let contractVersions: LedgerContractVersions
    let migrationArtifact: MigrationArtifactIdentity
    let mappingArtifacts: [MigrationArtifactIdentity]
    let entityPlans: [MigrationEntityPlan]
    let createdAtEpochMilliseconds: Int64
    let authorityDisposition: MigrationAuthorityDisposition
}

public enum MigrationStage: String, Codable, CaseIterable, Sendable {
    case extract
    case normalize
    case transform
    case plan
    case load
    case verify
    case reconcile
    case finalize

    fileprivate var rank: Int {
        Self.allCases.firstIndex(of: self)!
    }
}

public enum MigrationJournalEventState: String, Codable, Sendable {
    case started
    case checkpoint
    case completed
    case interrupted
    case blocked
    case failed
}

public struct MigrationEntityOutcome: Codable, Equatable, Sendable {
    public let entity: MigrationStableCode
    public let examined: Int64
    public let applied: Int64
    public let skipped: Int64
    public let blocked: Int64
    public let failed: Int64

    public init(
        entity: MigrationStableCode,
        examined: Int64,
        applied: Int64,
        skipped: Int64,
        blocked: Int64,
        failed: Int64
    ) throws {
        for (field, value) in [
            ("examined", examined),
            ("applied", applied),
            ("skipped", skipped),
            ("blocked", blocked),
            ("failed", failed)
        ] where value < 0 {
            throw MigrationIntegrityFailure.invalidCount("\(entity.rawValue)_\(field)")
        }
        let outcomeTotal = try MigrationIntegrityValidation.sumCounts(
            [applied, skipped, blocked, failed],
            field: "\(entity.rawValue)_outcomes"
        )
        guard outcomeTotal <= examined else {
            throw MigrationIntegrityFailure.invalidCount("\(entity.rawValue)_outcomes")
        }
        self.entity = entity
        self.examined = examined
        self.applied = applied
        self.skipped = skipped
        self.blocked = blocked
        self.failed = failed
    }
}

public struct MigrationJournalEvent: Codable, Equatable, Sendable {
    public let planDigest: MigrationSHA256
    public let sequence: Int
    public let stage: MigrationStage
    public let state: MigrationJournalEventState
    public let occurredAtEpochMilliseconds: Int64
    public let outcomes: [MigrationEntityOutcome]
    public let eventDigest: MigrationSHA256

    public static func make(
        planDigest: MigrationSHA256,
        sequence: Int,
        stage: MigrationStage,
        state: MigrationJournalEventState,
        occurredAtEpochMilliseconds: Int64,
        outcomes: [MigrationEntityOutcome]
    ) throws -> Self {
        guard sequence > 0 else {
            throw MigrationIntegrityFailure.invalidEventSequence
        }
        guard occurredAtEpochMilliseconds > 0 else {
            throw MigrationIntegrityFailure.invalidTimestamp("journal_event")
        }
        var seen: Set<MigrationStableCode> = []
        for outcome in outcomes {
            guard seen.insert(outcome.entity).inserted else {
                throw MigrationIntegrityFailure.duplicateEventEntity(
                    sequence: sequence,
                    entity: outcome.entity
                )
            }
        }
        let sorted = outcomes.sorted { $0.entity < $1.entity }
        let content = MigrationJournalEventContent(
            planDigest: planDigest,
            sequence: sequence,
            stage: stage,
            state: state,
            occurredAtEpochMilliseconds: occurredAtEpochMilliseconds,
            outcomes: sorted
        )
        return Self(
            planDigest: planDigest,
            sequence: sequence,
            stage: stage,
            state: state,
            occurredAtEpochMilliseconds: occurredAtEpochMilliseconds,
            outcomes: sorted,
            eventDigest: try .make(bytes: MigrationCanonical.encode(content))
        )
    }

    fileprivate var content: MigrationJournalEventContent {
        MigrationJournalEventContent(
            planDigest: planDigest,
            sequence: sequence,
            stage: stage,
            state: state,
            occurredAtEpochMilliseconds: occurredAtEpochMilliseconds,
            outcomes: outcomes
        )
    }
}

private struct MigrationJournalEventContent: Codable {
    let planDigest: MigrationSHA256
    let sequence: Int
    let stage: MigrationStage
    let state: MigrationJournalEventState
    let occurredAtEpochMilliseconds: Int64
    let outcomes: [MigrationEntityOutcome]
}

public struct MigrationRunJournal: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let planDigest: MigrationSHA256
    public let events: [MigrationJournalEvent]
    public let resumeFingerprint: MigrationSHA256
    public let authorityDisposition: MigrationAuthorityDisposition
    public let contentDigest: MigrationSHA256
}

public struct MigrationRunJournalValidator: Sendable {
    public static let schemaVersion = 1
    public static let maximumEvents = 512
    public static let maximumCanonicalJournalBytes = 262_144

    public let planValidator: MigrationRunPlanValidator

    public init(planValidator: MigrationRunPlanValidator) {
        self.planValidator = planValidator
    }

    public func start(plan: MigrationRunPlan) throws -> MigrationRunJournal {
        let plan = try validatedPlan(plan)
        return try makeJournal(planDigest: plan.contentDigest, events: [])
    }

    public func appending(
        _ event: MigrationJournalEvent,
        to journal: MigrationRunJournal,
        plan: MigrationRunPlan
    ) throws -> MigrationRunJournal {
        let plan = try validatedPlan(plan)
        let rebuilt = try rebuild(journal.events, plan: plan)
        guard rebuilt.contentDigest == journal.contentDigest else {
            throw MigrationIntegrityFailure.journalDigestMismatch
        }
        guard rebuilt == journal else {
            throw MigrationIntegrityFailure.noncanonicalJournal
        }
        return try appendUnchecked(event, to: rebuilt, plan: plan)
    }

    public func canonicalData(
        for journal: MigrationRunJournal,
        plan: MigrationRunPlan
    ) throws -> Data {
        let plan = try validatedPlan(plan)
        let rebuilt = try rebuild(journal.events, plan: plan)
        guard rebuilt.contentDigest == journal.contentDigest else {
            throw MigrationIntegrityFailure.journalDigestMismatch
        }
        guard rebuilt == journal else {
            throw MigrationIntegrityFailure.noncanonicalJournal
        }
        return try MigrationCanonical.encode(rebuilt)
    }

    public func decodeAndValidate(
        _ data: Data,
        plan: MigrationRunPlan
    ) throws -> MigrationRunJournal {
        let plan = try validatedPlan(plan)
        guard data.count <= Self.maximumCanonicalJournalBytes else {
            throw MigrationIntegrityFailure.journalTooLarge(
                actual: data.count,
                maximum: Self.maximumCanonicalJournalBytes
            )
        }
        let decoded: MigrationRunJournal
        do {
            decoded = try MigrationCanonical.decode(MigrationRunJournal.self, from: data)
        } catch {
            throw MigrationIntegrityFailure.malformedJournal
        }
        let rebuilt = try rebuild(decoded.events, plan: plan)
        guard rebuilt.contentDigest == decoded.contentDigest else {
            throw MigrationIntegrityFailure.journalDigestMismatch
        }
        guard rebuilt == decoded, try MigrationCanonical.encode(rebuilt) == data else {
            throw MigrationIntegrityFailure.noncanonicalJournal
        }
        return rebuilt
    }

    fileprivate func validated(
        _ journal: MigrationRunJournal,
        plan: MigrationRunPlan
    ) throws -> MigrationRunJournal {
        let plan = try validatedPlan(plan)
        let rebuilt = try rebuild(journal.events, plan: plan)
        guard rebuilt.contentDigest == journal.contentDigest else {
            throw MigrationIntegrityFailure.journalDigestMismatch
        }
        guard rebuilt == journal else {
            throw MigrationIntegrityFailure.noncanonicalJournal
        }
        return rebuilt
    }

    private func rebuild(
        _ events: [MigrationJournalEvent],
        plan: MigrationRunPlan
    ) throws -> MigrationRunJournal {
        guard events.count <= Self.maximumEvents else {
            throw MigrationIntegrityFailure.tooManyJournalEvents(maximum: Self.maximumEvents)
        }
        var journal = try makeJournal(planDigest: plan.contentDigest, events: [])
        for event in events {
            journal = try appendUnchecked(event, to: journal, plan: plan)
        }
        return journal
    }

    private func validatedPlan(_ plan: MigrationRunPlan) throws -> MigrationRunPlan {
        let validated = try planValidator.validate(plan.draft)
        guard validated.contentDigest == plan.contentDigest else {
            throw MigrationIntegrityFailure.planDigestMismatch
        }
        guard validated == plan else {
            throw MigrationIntegrityFailure.noncanonicalPlan
        }
        return validated
    }

    private func appendUnchecked(
        _ event: MigrationJournalEvent,
        to journal: MigrationRunJournal,
        plan: MigrationRunPlan
    ) throws -> MigrationRunJournal {
        guard journal.planDigest == plan.contentDigest,
              event.planDigest == plan.contentDigest else {
            throw MigrationIntegrityFailure.journalPlanMismatch
        }
        let expectedEventDigest = try MigrationSHA256.make(
            bytes: MigrationCanonical.encode(event.content)
        )
        guard event.eventDigest == expectedEventDigest else {
            throw MigrationIntegrityFailure.eventDigestMismatch(sequence: event.sequence)
        }
        guard event.outcomes == event.outcomes.sorted(by: { $0.entity < $1.entity }) else {
            throw MigrationIntegrityFailure.noncanonicalJournal
        }
        if event.sequence <= journal.events.count {
            let existing = journal.events[event.sequence - 1]
            guard existing == event else {
                throw MigrationIntegrityFailure.eventReplayConflict(sequence: event.sequence)
            }
            return journal
        }
        guard event.sequence == journal.events.count + 1 else {
            throw MigrationIntegrityFailure.invalidEventSequence
        }
        guard journal.events.count < Self.maximumEvents else {
            throw MigrationIntegrityFailure.tooManyJournalEvents(maximum: Self.maximumEvents)
        }

        let planByEntity = Dictionary(uniqueKeysWithValues: plan.entityPlans.map { ($0.entity, $0) })
        var eventByEntity: [MigrationStableCode: MigrationEntityOutcome] = [:]
        for outcome in event.outcomes {
            guard eventByEntity[outcome.entity] == nil else {
                throw MigrationIntegrityFailure.duplicateEventEntity(
                    sequence: event.sequence,
                    entity: outcome.entity
                )
            }
            eventByEntity[outcome.entity] = outcome
        }
        guard Set(eventByEntity.keys) == Set(planByEntity.keys) else {
            throw MigrationIntegrityFailure.eventEntitySetMismatch(sequence: event.sequence)
        }

        if let prior = journal.events.last {
            guard event.occurredAtEpochMilliseconds >= prior.occurredAtEpochMilliseconds else {
                throw MigrationIntegrityFailure.eventTimestampRegression(sequence: event.sequence)
            }
            try validateTransition(from: prior, to: event)
            let priorByEntity = Dictionary(uniqueKeysWithValues: prior.outcomes.map { ($0.entity, $0) })
            for outcome in event.outcomes {
                let priorOutcome = priorByEntity[outcome.entity]!
                guard outcome.examined >= priorOutcome.examined,
                      outcome.applied >= priorOutcome.applied,
                      outcome.skipped >= priorOutcome.skipped,
                      outcome.blocked >= priorOutcome.blocked,
                      outcome.failed >= priorOutcome.failed else {
                    throw MigrationIntegrityFailure.eventCountRegression(
                        sequence: event.sequence,
                        entity: outcome.entity
                    )
                }
            }
        } else {
            guard event.stage == .extract, event.state == .started else {
                throw MigrationIntegrityFailure.illegalEventTransition(sequence: event.sequence)
            }
        }

        for outcome in event.outcomes {
            let planned = planByEntity[outcome.entity]!.plannedCount
            let outcomeTotal = try MigrationIntegrityValidation.sumCounts(
                [outcome.applied, outcome.skipped, outcome.blocked, outcome.failed],
                field: "\(outcome.entity.rawValue)_outcomes"
            )
            guard outcome.examined >= 0,
                  outcome.applied >= 0,
                  outcome.skipped >= 0,
                  outcome.blocked >= 0,
                  outcome.failed >= 0,
                  outcome.examined <= planned,
                  outcomeTotal <= outcome.examined else {
                throw MigrationIntegrityFailure.eventCountExceedsPlan(
                    sequence: event.sequence,
                    entity: outcome.entity
                )
            }
        }

        return try makeJournal(planDigest: plan.contentDigest, events: journal.events + [event])
    }

    private func validateTransition(
        from prior: MigrationJournalEvent,
        to next: MigrationJournalEvent
    ) throws {
        if prior.stage == .finalize, prior.state == .completed {
            throw MigrationIntegrityFailure.terminalJournal
        }
        if prior.state == .blocked || prior.state == .failed {
            throw MigrationIntegrityFailure.terminalJournal
        }
        if next.stage.rank < prior.stage.rank {
            throw MigrationIntegrityFailure.eventStageRegression(sequence: next.sequence)
        }
        if next.stage.rank > prior.stage.rank + 1 {
            throw MigrationIntegrityFailure.eventStageSkipped(sequence: next.sequence)
        }
        if next.stage.rank == prior.stage.rank + 1 {
            guard prior.state == .completed, next.state == .started else {
                throw MigrationIntegrityFailure.illegalEventTransition(sequence: next.sequence)
            }
            return
        }

        let legal: Bool
        switch prior.state {
        case .started:
            legal = next.state != .started
        case .checkpoint:
            legal = next.state != .started
        case .interrupted:
            legal = next.state == .started
        case .completed, .blocked, .failed:
            legal = false
        }
        guard legal else {
            throw MigrationIntegrityFailure.illegalEventTransition(sequence: next.sequence)
        }
    }

    private func makeJournal(
        planDigest: MigrationSHA256,
        events: [MigrationJournalEvent]
    ) throws -> MigrationRunJournal {
        let resumeMaterial = events.last?.eventDigest.rawValue ?? "start"
        let resumeFingerprint = try MigrationSHA256.make(
            bytes: Data("migration-resume-v1\u{1f}\(planDigest.rawValue)\u{1f}\(resumeMaterial)".utf8)
        )
        let content = MigrationRunJournalContent(
            schemaVersion: Self.schemaVersion,
            planDigest: planDigest,
            events: events,
            resumeFingerprint: resumeFingerprint,
            authorityDisposition: .evidenceOnly
        )
        let journal = MigrationRunJournal(
            schemaVersion: content.schemaVersion,
            planDigest: content.planDigest,
            events: content.events,
            resumeFingerprint: content.resumeFingerprint,
            authorityDisposition: content.authorityDisposition,
            contentDigest: try .make(bytes: MigrationCanonical.encode(content))
        )
        let canonical = try MigrationCanonical.encode(journal)
        guard canonical.count <= Self.maximumCanonicalJournalBytes else {
            throw MigrationIntegrityFailure.journalTooLarge(
                actual: canonical.count,
                maximum: Self.maximumCanonicalJournalBytes
            )
        }
        return journal
    }
}

private struct MigrationRunJournalContent: Codable {
    let schemaVersion: Int
    let planDigest: MigrationSHA256
    let events: [MigrationJournalEvent]
    let resumeFingerprint: MigrationSHA256
    let authorityDisposition: MigrationAuthorityDisposition
}

public enum MigrationReconciliationStatus: String, Codable, Sendable {
    case notRun = "not_run"
    case passed
    case explained
    case unexplained
    case failed
}

public struct MigrationReconciliationResult: Codable, Equatable, Sendable {
    public let rule: MigrationStableCode
    public let status: MigrationReconciliationStatus
    public let differenceCount: Int64
    public let evidenceSHA256: MigrationSHA256

    public init(
        rule: MigrationStableCode,
        status: MigrationReconciliationStatus,
        differenceCount: Int64,
        evidenceSHA256: MigrationSHA256
    ) throws {
        guard differenceCount >= 0 else {
            throw MigrationIntegrityFailure.invalidReconciliationDifference(rule)
        }
        if (status == .notRun || status == .passed), differenceCount != 0 {
            throw MigrationIntegrityFailure.invalidReconciliationDifference(rule)
        }
        if (status == .unexplained || status == .failed), differenceCount == 0 {
            throw MigrationIntegrityFailure.invalidReconciliationDifference(rule)
        }
        self.rule = rule
        self.status = status
        self.differenceCount = differenceCount
        self.evidenceSHA256 = evidenceSHA256
    }
}

public enum MigrationRunDisposition: String, Codable, Sendable {
    case completed
    case interrupted
    case blocked
    case aborted
}

public struct MigrationRunManifestDraft: Sendable {
    public let plan: MigrationRunPlan
    public let journal: MigrationRunJournal
    public let endedAtEpochMilliseconds: Int64
    public let disposition: MigrationRunDisposition
    public let reason: MigrationStableCode?
    public let reconciliation: [MigrationReconciliationResult]

    public init(
        plan: MigrationRunPlan,
        journal: MigrationRunJournal,
        endedAtEpochMilliseconds: Int64,
        disposition: MigrationRunDisposition,
        reason: MigrationStableCode?,
        reconciliation: [MigrationReconciliationResult]
    ) {
        self.plan = plan
        self.journal = journal
        self.endedAtEpochMilliseconds = endedAtEpochMilliseconds
        self.disposition = disposition
        self.reason = reason
        self.reconciliation = reconciliation
    }
}

public struct MigrationRunManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let plan: MigrationRunPlan
    public let journal: MigrationRunJournal
    public let endedAtEpochMilliseconds: Int64
    public let disposition: MigrationRunDisposition
    public let reason: MigrationStableCode?
    public let reconciliation: [MigrationReconciliationResult]
    public let authorityDisposition: MigrationAuthorityDisposition
    public let contentDigest: MigrationSHA256

    public var finalOutcomes: [MigrationEntityOutcome] {
        journal.events.last?.outcomes ?? []
    }

    fileprivate var draft: MigrationRunManifestDraft {
        MigrationRunManifestDraft(
            plan: plan,
            journal: journal,
            endedAtEpochMilliseconds: endedAtEpochMilliseconds,
            disposition: disposition,
            reason: reason,
            reconciliation: reconciliation
        )
    }
}

public struct MigrationRunManifestPolicy: Sendable {
    public let requiredReconciliationRules: Set<MigrationStableCode>

    public init(requiredReconciliationRules: Set<MigrationStableCode>) {
        self.requiredReconciliationRules = requiredReconciliationRules
    }
}

public struct MigrationRunManifestValidator: Sendable {
    public static let schemaVersion = 1
    public static let maximumReconciliationRules = 256
    public static let maximumCanonicalManifestBytes = 524_288

    public let planValidator: MigrationRunPlanValidator
    public let policy: MigrationRunManifestPolicy
    private let journalValidator: MigrationRunJournalValidator

    public init(
        planValidator: MigrationRunPlanValidator,
        policy: MigrationRunManifestPolicy
    ) {
        self.planValidator = planValidator
        self.policy = policy
        self.journalValidator = MigrationRunJournalValidator(planValidator: planValidator)
    }

    public func validate(_ draft: MigrationRunManifestDraft) throws -> MigrationRunManifest {
        let plan = try planValidator.validate(draft.plan.draft)
        guard plan == draft.plan else {
            throw MigrationIntegrityFailure.noncanonicalPlan
        }
        let journal = try journalValidator.validated(draft.journal, plan: plan)
        guard let finalEvent = journal.events.last else {
            throw MigrationIntegrityFailure.emptyJournal
        }
        guard draft.endedAtEpochMilliseconds >= finalEvent.occurredAtEpochMilliseconds else {
            throw MigrationIntegrityFailure.manifestEndedBeforeJournal
        }
        guard draft.reconciliation.count <= Self.maximumReconciliationRules else {
            throw MigrationIntegrityFailure.reconciliationRuleSetMismatch
        }
        var seen: Set<MigrationStableCode> = []
        for result in draft.reconciliation {
            guard seen.insert(result.rule).inserted else {
                throw MigrationIntegrityFailure.duplicateReconciliationRule(result.rule)
            }
            if (result.status == .notRun || result.status == .passed),
               result.differenceCount != 0 {
                throw MigrationIntegrityFailure.invalidReconciliationDifference(result.rule)
            }
            if (result.status == .unexplained || result.status == .failed),
               result.differenceCount == 0 {
                throw MigrationIntegrityFailure.invalidReconciliationDifference(result.rule)
            }
        }
        guard seen == policy.requiredReconciliationRules else {
            throw MigrationIntegrityFailure.reconciliationRuleSetMismatch
        }
        try validateTerminal(
            disposition: draft.disposition,
            reason: draft.reason,
            finalEvent: finalEvent,
            plan: plan,
            reconciliation: draft.reconciliation
        )

        let sortedReconciliation = draft.reconciliation.sorted { $0.rule < $1.rule }
        let content = MigrationRunManifestContent(
            schemaVersion: Self.schemaVersion,
            plan: plan,
            journal: journal,
            endedAtEpochMilliseconds: draft.endedAtEpochMilliseconds,
            disposition: draft.disposition,
            reason: draft.reason,
            reconciliation: sortedReconciliation,
            authorityDisposition: .evidenceOnly
        )
        let manifest = MigrationRunManifest(
            schemaVersion: content.schemaVersion,
            plan: content.plan,
            journal: content.journal,
            endedAtEpochMilliseconds: content.endedAtEpochMilliseconds,
            disposition: content.disposition,
            reason: content.reason,
            reconciliation: content.reconciliation,
            authorityDisposition: content.authorityDisposition,
            contentDigest: try .make(bytes: MigrationCanonical.encode(content))
        )
        let canonical = try MigrationCanonical.encode(manifest)
        guard canonical.count <= Self.maximumCanonicalManifestBytes else {
            throw MigrationIntegrityFailure.manifestTooLarge(
                actual: canonical.count,
                maximum: Self.maximumCanonicalManifestBytes
            )
        }
        return manifest
    }

    public func canonicalData(for manifest: MigrationRunManifest) throws -> Data {
        let validated = try validate(manifest.draft)
        guard validated.contentDigest == manifest.contentDigest else {
            throw MigrationIntegrityFailure.manifestDigestMismatch
        }
        guard validated == manifest else {
            throw MigrationIntegrityFailure.noncanonicalManifest
        }
        return try MigrationCanonical.encode(validated)
    }

    public func decodeAndValidate(_ data: Data) throws -> MigrationRunManifest {
        guard data.count <= Self.maximumCanonicalManifestBytes else {
            throw MigrationIntegrityFailure.manifestTooLarge(
                actual: data.count,
                maximum: Self.maximumCanonicalManifestBytes
            )
        }
        let decoded: MigrationRunManifest
        do {
            decoded = try MigrationCanonical.decode(MigrationRunManifest.self, from: data)
        } catch {
            throw MigrationIntegrityFailure.malformedManifest
        }
        let validated = try validate(decoded.draft)
        guard validated.contentDigest == decoded.contentDigest else {
            throw MigrationIntegrityFailure.manifestDigestMismatch
        }
        guard validated == decoded, try MigrationCanonical.encode(validated) == data else {
            throw MigrationIntegrityFailure.noncanonicalManifest
        }
        return validated
    }

    private func validateTerminal(
        disposition: MigrationRunDisposition,
        reason: MigrationStableCode?,
        finalEvent: MigrationJournalEvent,
        plan: MigrationRunPlan,
        reconciliation: [MigrationReconciliationResult]
    ) throws {
        switch disposition {
        case .completed:
            guard finalEvent.stage == .finalize, finalEvent.state == .completed else {
                throw MigrationIntegrityFailure.terminalDispositionMismatch
            }
            guard reason == nil else {
                throw MigrationIntegrityFailure.terminalReasonUnexpected
            }
        case .interrupted:
            guard finalEvent.state == .interrupted else {
                throw MigrationIntegrityFailure.terminalDispositionMismatch
            }
            guard reason != nil else {
                throw MigrationIntegrityFailure.terminalReasonMissing
            }
        case .blocked:
            guard finalEvent.state == .blocked else {
                throw MigrationIntegrityFailure.terminalDispositionMismatch
            }
            guard reason != nil else {
                throw MigrationIntegrityFailure.terminalReasonMissing
            }
        case .aborted:
            guard finalEvent.state == .failed else {
                throw MigrationIntegrityFailure.terminalDispositionMismatch
            }
            guard reason != nil else {
                throw MigrationIntegrityFailure.terminalReasonMissing
            }
        }

        guard disposition == .completed else { return }
        let planByEntity = Dictionary(uniqueKeysWithValues: plan.entityPlans.map { ($0.entity, $0) })
        for outcome in finalEvent.outcomes {
            let planned = planByEntity[outcome.entity]!.plannedCount
            guard outcome.examined == planned, outcome.blocked == 0, outcome.failed == 0 else {
                throw MigrationIntegrityFailure.incompleteEntityOutcome(outcome.entity)
            }
            switch plan.mode {
            case .dryRun:
                guard outcome.applied == 0 else {
                    throw MigrationIntegrityFailure.dryRunAppliedCount(outcome.entity)
                }
            case .apply:
                let closedCount = try MigrationIntegrityValidation.sumCounts(
                    [outcome.applied, outcome.skipped],
                    field: "\(outcome.entity.rawValue)_apply_outcome"
                )
                guard closedCount == planned else {
                    throw MigrationIntegrityFailure.applyOutcomeMismatch(outcome.entity)
                }
            }
        }
        for result in reconciliation {
            switch result.status {
            case .notRun:
                throw MigrationIntegrityFailure.incompleteReconciliation(result.rule)
            case .unexplained, .failed:
                throw MigrationIntegrityFailure.unexplainedReconciliation(result.rule)
            case .passed, .explained:
                break
            }
        }
    }
}

private struct MigrationRunManifestContent: Codable {
    let schemaVersion: Int
    let plan: MigrationRunPlan
    let journal: MigrationRunJournal
    let endedAtEpochMilliseconds: Int64
    let disposition: MigrationRunDisposition
    let reason: MigrationStableCode?
    let reconciliation: [MigrationReconciliationResult]
    let authorityDisposition: MigrationAuthorityDisposition
}

private enum MigrationCanonical {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}

private enum MigrationIntegrityValidation {
    static func isLowercaseHex(_ value: String, lengths: Set<Int>) -> Bool {
        lengths.contains(value.count) && value.unicodeScalars.allSatisfy {
            (48...57).contains($0.value) || (97...102).contains($0.value)
        }
    }

    static func isStableCode(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 64 else { return false }
        guard let first = value.unicodeScalars.first,
              (97...122).contains(first.value) else { return false }
        return value.unicodeScalars.allSatisfy {
            (97...122).contains($0.value) ||
                (48...57).contains($0.value) ||
                $0.value == 95
        }
    }

    static func isVersion(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 64 else { return false }
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.contains("/"),
              !value.contains("\\"),
              !value.contains(":"),
              !value.contains("="),
              !value.contains(" ") else { return false }
        return value.unicodeScalars.allSatisfy {
            (65...90).contains($0.value) ||
                (97...122).contains($0.value) ||
                (48...57).contains($0.value) ||
                [45, 46, 95].contains($0.value)
        }
    }

    static func validateContracts(_ versions: LedgerContractVersions) throws {
        for (field, value) in [
            ("schema", versions.schema),
            ("query", versions.query),
            ("operation", versions.operation),
            ("sync", versions.sync)
        ] where !isVersion(value) {
            throw MigrationIntegrityFailure.contractVersionInvalid(field)
        }
    }

    static func contractMismatch(
        _ actual: LedgerContractVersions,
        _ expected: LedgerContractVersions
    ) -> String? {
        if actual.schema != expected.schema { return "schema" }
        if actual.query != expected.query { return "query" }
        if actual.operation != expected.operation { return "operation" }
        if actual.sync != expected.sync { return "sync" }
        return nil
    }

    static func sumCounts(_ values: [Int64], field: String) throws -> Int64 {
        var result: Int64 = 0
        for value in values {
            guard value >= 0 else {
                throw MigrationIntegrityFailure.invalidCount(field)
            }
            let addition = result.addingReportingOverflow(value)
            guard !addition.overflow else {
                throw MigrationIntegrityFailure.invalidCount(field)
            }
            result = addition.partialValue
        }
        return result
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
