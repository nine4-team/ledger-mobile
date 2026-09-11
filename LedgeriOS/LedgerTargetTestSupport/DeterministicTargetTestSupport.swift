import CryptoKit
import Foundation
import LedgerTargetCore

public enum DeterministicTargetTestFailure: Error, Equatable, Sendable {
    case productionEnvironment
    case unsafeFixtureEnvironment(field: String)
    case nonSyntheticIdentifier(kind: String)
    case invalidBaseTime
    case invalidValueSchedule(field: String)
    case valueScheduleExhausted(domain: String, index: UInt32)
    case arithmeticOverflow(field: String)
    case emptyScript(kind: String)
    case duplicateScript(kind: String)
    case missingScript(kind: String)
    case crossAccountAccess
    case invalidScript(kind: String)
    case nonMonotonicScript(kind: String)
    case scriptedFailure(ApplicationErrorSummary)
    case invalidEvidence
    case nonCanonicalEvidence
    case evidenceDigestMismatch
    case evidenceTooLarge(actual: Int, maximum: Int)

    public var diagnosticCode: String {
        switch self {
        case .productionEnvironment:
            "test_support_production_environment"
        case .unsafeFixtureEnvironment:
            "test_support_environment_unsafe"
        case .nonSyntheticIdentifier:
            "test_support_identity_not_synthetic"
        case .invalidBaseTime:
            "test_support_base_time_invalid"
        case .invalidValueSchedule:
            "test_support_schedule_invalid"
        case .valueScheduleExhausted:
            "test_support_schedule_exhausted"
        case .arithmeticOverflow:
            "test_support_arithmetic_overflow"
        case .emptyScript:
            "test_support_script_empty"
        case .duplicateScript:
            "test_support_script_duplicate"
        case .missingScript:
            "test_support_script_missing"
        case .crossAccountAccess:
            "test_support_account_mismatch"
        case .invalidScript:
            "test_support_script_invalid"
        case .nonMonotonicScript:
            "test_support_script_nonmonotonic"
        case .scriptedFailure(let error):
            "test_support_scripted_\(error.code.rawValue)"
        case .invalidEvidence:
            "test_support_evidence_invalid"
        case .nonCanonicalEvidence:
            "test_support_evidence_noncanonical"
        case .evidenceDigestMismatch:
            "test_support_evidence_digest_mismatch"
        case .evidenceTooLarge:
            "test_support_evidence_too_large"
        }
    }
}

public enum DeterministicTargetScenarioIDTag: Sendable {}
public enum DeterministicFixtureKeyTag: Sendable {}

public typealias DeterministicTargetScenarioID = LedgerIdentifier<DeterministicTargetScenarioIDTag>
public typealias DeterministicFixtureKey = StableCode<DeterministicFixtureKeyTag>

public struct DeterministicTargetTestContext: Codable, Equatable, Sendable {
    public let manifest: LedgerEnvironmentManifest
    public let principalId: PrincipalID
    public let accountId: AccountID
    public let scenarioId: DeterministicTargetScenarioID
    public let seed: UInt64
    public let baseTimeMilliseconds: Int64

    public init(
        environment: ValidatedLedgerEnvironment,
        principalId: PrincipalID,
        accountId: AccountID,
        scenarioId: DeterministicTargetScenarioID,
        seed: UInt64,
        baseTimeMilliseconds: Int64
    ) throws {
        let manifest = Self.normalized(environment.manifest)
        guard manifest.environment != .targetProduction else {
            throw DeterministicTargetTestFailure.productionEnvironment
        }
        try Self.validateFixtureEnvironment(manifest)
        guard principalId.rawValue.hasPrefix("test-principal-") else {
            throw DeterministicTargetTestFailure.nonSyntheticIdentifier(kind: "principal")
        }
        guard accountId.rawValue.hasPrefix("test-account-") else {
            throw DeterministicTargetTestFailure.nonSyntheticIdentifier(kind: "account")
        }
        guard scenarioId.rawValue.hasPrefix("test-scenario-") else {
            throw DeterministicTargetTestFailure.nonSyntheticIdentifier(kind: "scenario")
        }
        guard seed != 0 else {
            throw DeterministicTargetTestFailure.invalidValueSchedule(field: "seed")
        }
        guard (0...253_402_300_799_999).contains(baseTimeMilliseconds) else {
            throw DeterministicTargetTestFailure.invalidBaseTime
        }

        self.manifest = manifest
        self.principalId = principalId
        self.accountId = accountId
        self.scenarioId = scenarioId
        self.seed = seed
        self.baseTimeMilliseconds = baseTimeMilliseconds
    }

    public static func make(
        manifest: LedgerEnvironmentManifest,
        policy: LedgerEnvironmentPolicy,
        principalId: PrincipalID,
        accountId: AccountID,
        scenarioId: DeterministicTargetScenarioID,
        seed: UInt64,
        baseTimeMilliseconds: Int64
    ) throws -> Self {
        let validated = try LedgerEnvironmentValidator.validate(manifest, policy: policy)
        return try Self(
            environment: validated,
            principalId: principalId,
            accountId: accountId,
            scenarioId: scenarioId,
            seed: seed,
            baseTimeMilliseconds: baseTimeMilliseconds
        )
    }

    public var baseTime: Date {
        Date(timeIntervalSince1970: Double(baseTimeMilliseconds) / 1_000)
    }

    private static func normalized(
        _ manifest: LedgerEnvironmentManifest
    ) -> LedgerEnvironmentManifest {
        LedgerEnvironmentManifest(
            environment: manifest.environment,
            buildProfile: manifest.buildProfile,
            bundleIdentifier: manifest.bundleIdentifier,
            displayName: manifest.displayName,
            localDataNamespacePrefix: manifest.localDataNamespacePrefix,
            contractVersions: manifest.contractVersions,
            resources: manifest.resources.sorted {
                $0.component.rawValue < $1.component.rawValue
            }
        )
    }

    private static func validateFixtureEnvironment(
        _ manifest: LedgerEnvironmentManifest
    ) throws {
        let expectedMarkers: [String]
        switch manifest.environment {
        case .targetLocal:
            expectedMarkers = ["local", "test", "unprovisioned"]
        case .targetStaging:
            expectedMarkers = ["staging", "test", "unprovisioned"]
        case .targetProduction:
            throw DeterministicTargetTestFailure.productionEnvironment
        }

        let bundle = manifest.bundleIdentifier.lowercased()
        guard expectedMarkers.contains(where: bundle.contains) else {
            throw DeterministicTargetTestFailure.unsafeFixtureEnvironment(
                field: "bundle_identifier"
            )
        }

        for resource in manifest.resources {
            let identifier = resource.publicIdentifier.lowercased()
            guard expectedMarkers.contains(where: identifier.contains),
                  !Self.containsCredentialMaterial(identifier) else {
                throw DeterministicTargetTestFailure.unsafeFixtureEnvironment(
                    field: "resource_\(resource.component.rawValue)"
                )
            }
        }
    }

    private static func containsCredentialMaterial(_ value: String) -> Bool {
        ["access_token", "apikey=", "api_key=", "password=", "secret=", "service_role"]
            .contains(where: value.contains)
    }
}

public struct DeterministicTargetValueSource: Codable, Equatable, Sendable {
    public static let maximumAllowedIndex: UInt32 = 100_000

    public let context: DeterministicTargetTestContext
    public let maximumIndex: UInt32
    public let stepMilliseconds: Int64
    public let startingRevision: UInt64

    public init(
        context: DeterministicTargetTestContext,
        maximumIndex: UInt32,
        stepMilliseconds: Int64,
        startingRevision: UInt64
    ) throws {
        guard maximumIndex <= Self.maximumAllowedIndex else {
            throw DeterministicTargetTestFailure.invalidValueSchedule(
                field: "maximum_index"
            )
        }
        guard (1...86_400_000).contains(stepMilliseconds) else {
            throw DeterministicTargetTestFailure.invalidValueSchedule(
                field: "step_milliseconds"
            )
        }
        guard startingRevision > 0 else {
            throw DeterministicTargetTestFailure.invalidValueSchedule(
                field: "starting_revision"
            )
        }
        self.context = context
        self.maximumIndex = maximumIndex
        self.stepMilliseconds = stepMilliseconds
        self.startingRevision = startingRevision
    }

    public func timestamp(
        key: DeterministicFixtureKey,
        index: UInt32
    ) throws -> Date {
        try requireIndex(index, domain: "timestamp")
        let digest = digestBytes(domain: "timestamp", key: key, index: 0)
        let keyOffset = Int64((UInt16(digest[0]) << 8) | UInt16(digest[1]))
        let (indexedOffset, multipliedOverflow) = Int64(index)
            .multipliedReportingOverflow(by: stepMilliseconds)
        guard !multipliedOverflow else {
            throw DeterministicTargetTestFailure.arithmeticOverflow(field: "timestamp")
        }
        let (withIndex, indexOverflow) = context.baseTimeMilliseconds
            .addingReportingOverflow(indexedOffset)
        let (milliseconds, keyOverflow) = withIndex.addingReportingOverflow(keyOffset)
        guard !indexOverflow, !keyOverflow,
              (0...253_402_300_799_999).contains(milliseconds) else {
            throw DeterministicTargetTestFailure.arithmeticOverflow(field: "timestamp")
        }
        return Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }

    public func operationId(
        key: DeterministicFixtureKey,
        index: UInt32
    ) throws -> OperationID {
        try requireIndex(index, domain: "operation_id")
        return try OperationID(
            validating: "test-op-\(digestHex(domain: "operation_id", key: key, index: index).prefix(24))"
        )
    }

    public func entityId(
        key: DeterministicFixtureKey,
        index: UInt32
    ) throws -> EntityID {
        try requireIndex(index, domain: "entity_id")
        return try EntityID(
            validating: "test-entity-\(digestHex(domain: "entity_id", key: key, index: index).prefix(24))"
        )
    }

    public func revision(
        key: DeterministicFixtureKey,
        index: UInt32
    ) throws -> UInt64 {
        try requireIndex(index, domain: "revision")
        let digest = digestBytes(domain: "revision", key: key, index: 0)
        let keyOffset = (UInt64(digest[0]) << 8) | UInt64(digest[1])
        let (range, rangeOverflow) = UInt64(maximumIndex).addingReportingOverflow(1)
        let (keyRange, multiplyOverflow) = keyOffset.multipliedReportingOverflow(by: range)
        let (withKey, keyOverflow) = startingRevision.addingReportingOverflow(keyRange)
        let (revision, indexOverflow) = withKey.addingReportingOverflow(UInt64(index))
        guard !rangeOverflow, !multiplyOverflow, !keyOverflow, !indexOverflow else {
            throw DeterministicTargetTestFailure.arithmeticOverflow(field: "revision")
        }
        return revision
    }

    private func requireIndex(_ index: UInt32, domain: String) throws {
        guard index <= maximumIndex else {
            throw DeterministicTargetTestFailure.valueScheduleExhausted(
                domain: domain,
                index: index
            )
        }
    }

    private func digestBytes(
        domain: String,
        key: DeterministicFixtureKey,
        index: UInt32
    ) -> [UInt8] {
        let material = [
            "ledger-target-test-support-v1",
            domain,
            context.scenarioId.rawValue,
            String(context.seed),
            key.rawValue,
            String(index)
        ].joined(separator: "\u{1f}")
        return Array(SHA256.hash(data: Data(material.utf8)))
    }

    private func digestHex(
        domain: String,
        key: DeterministicFixtureKey,
        index: UInt32
    ) -> String {
        digestBytes(domain: domain, key: key, index: index)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

public enum ScriptedAdapterTerminal: Codable, Equatable, Sendable {
    case finished
    case failure(ApplicationErrorSummary)
}

public struct ScriptedOperationSequence: Codable, Equatable, Sendable {
    public let operationId: OperationID
    public let accountId: AccountID
    public let snapshots: [OperationSnapshot]
    public let terminal: ScriptedAdapterTerminal

    public init(
        operationId: OperationID,
        accountId: AccountID,
        snapshots: [OperationSnapshot],
        terminal: ScriptedAdapterTerminal = .finished
    ) throws {
        guard !snapshots.isEmpty else {
            throw DeterministicTargetTestFailure.emptyScript(kind: "operation")
        }
        guard snapshots.allSatisfy({
            $0.operationId == operationId && $0.accountId == accountId
        }) else {
            throw DeterministicTargetTestFailure.invalidScript(kind: "operation_identity")
        }
        guard let first = snapshots.first,
              snapshots.allSatisfy({
                  $0.contractVersion == first.contractVersion &&
                  $0.fingerprint == first.fingerprint &&
                  $0.acceptedAt == first.acceptedAt
              }) else {
            throw DeterministicTargetTestFailure.invalidScript(kind: "operation_evidence")
        }
        try Self.requireMonotonic(
            snapshots.map(\.updatedAt),
            kind: "operation_updates"
        )
        guard snapshots.allSatisfy({ $0.acceptedAt <= $0.updatedAt }) else {
            throw DeterministicTargetTestFailure.invalidScript(kind: "operation_time")
        }
        for (prior, next) in zip(snapshots, snapshots.dropFirst()) {
            guard Self.isAllowedProgression(from: prior.state, to: next.state) else {
                throw DeterministicTargetTestFailure.invalidScript(
                    kind: "operation_lifecycle"
                )
            }
        }
        self.operationId = operationId
        self.accountId = accountId
        self.snapshots = snapshots
        self.terminal = terminal
    }

    fileprivate func revalidated() throws -> Self {
        try Self(
            operationId: operationId,
            accountId: accountId,
            snapshots: snapshots,
            terminal: terminal
        )
    }

    fileprivate static func requireMonotonic(
        _ timestamps: [Date],
        kind: String
    ) throws {
        for (prior, next) in zip(timestamps, timestamps.dropFirst()) where next < prior {
            throw DeterministicTargetTestFailure.nonMonotonicScript(kind: kind)
        }
    }

    private static func isAllowedProgression(
        from prior: OperationState,
        to next: OperationState
    ) -> Bool {
        if prior == next { return true }
        switch (prior.phase, next.phase) {
        case (.draft, .queued),
             (.queued, .applying),
             (.applying, .queued),
             (.applying, .applied),
             (.applying, .rejected),
             (.applied, .superseded),
             (.rejected, .resolved):
            return true
        default:
            return false
        }
    }
}

public struct ScriptedUnresolvedOperationSequence: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let snapshots: [[OperationSnapshot]]
    public let terminal: ScriptedAdapterTerminal

    public init(
        accountId: AccountID,
        snapshots: [[OperationSnapshot]],
        terminal: ScriptedAdapterTerminal = .finished
    ) throws {
        guard !snapshots.isEmpty else {
            throw DeterministicTargetTestFailure.emptyScript(kind: "unresolved_operations")
        }
        for batch in snapshots {
            guard batch.allSatisfy({
                $0.accountId == accountId && $0.state.isUnresolved
            }) else {
                throw DeterministicTargetTestFailure.invalidScript(
                    kind: "unresolved_operations"
                )
            }
            let canonical = batch.sorted(by: Self.operationOrder)
            guard canonical == batch,
                  Set(batch.map(\.operationId)).count == batch.count else {
                throw DeterministicTargetTestFailure.invalidScript(
                    kind: "unresolved_operation_order"
                )
            }
        }
        self.accountId = accountId
        self.snapshots = snapshots
        self.terminal = terminal
    }

    fileprivate func revalidated() throws -> Self {
        try Self(accountId: accountId, snapshots: snapshots, terminal: terminal)
    }

    private static func operationOrder(
        _ lhs: OperationSnapshot,
        _ rhs: OperationSnapshot
    ) -> Bool {
        if lhs.acceptedAt != rhs.acceptedAt {
            return lhs.acceptedAt < rhs.acceptedAt
        }
        return lhs.operationId.rawValue < rhs.operationId.rawValue
    }
}

public enum ScriptedDurabilityResult: Codable, Equatable, Sendable {
    case durable
    case failure(ApplicationErrorSummary)
}

public struct ScriptedDurabilityOutcome: Codable, Equatable, Sendable {
    public let operationId: OperationID
    public let result: ScriptedDurabilityResult

    public init(operationId: OperationID, result: ScriptedDurabilityResult) {
        self.operationId = operationId
        self.result = result
    }
}

public struct DeterministicTargetScenario: Equatable, Sendable {
    public static let maximumCanonicalEvidenceBytes = 131_072

    public let context: DeterministicTargetTestContext
    public let valueSource: DeterministicTargetValueSource
    public let operationScripts: [ScriptedOperationSequence]
    public let unresolvedOperationScript: ScriptedUnresolvedOperationSequence
    public let healthSnapshots: [SyncHealthSnapshot]
    public let durabilityOutcomes: [ScriptedDurabilityOutcome]

    public init(
        context: DeterministicTargetTestContext,
        valueSource: DeterministicTargetValueSource,
        operationScripts: [ScriptedOperationSequence],
        unresolvedOperationScript: ScriptedUnresolvedOperationSequence,
        healthSnapshots: [SyncHealthSnapshot],
        durabilityOutcomes: [ScriptedDurabilityOutcome]
    ) throws {
        guard valueSource.context == context else {
            throw DeterministicTargetTestFailure.invalidScript(kind: "value_context")
        }
        guard !operationScripts.isEmpty else {
            throw DeterministicTargetTestFailure.emptyScript(kind: "operations")
        }
        guard !healthSnapshots.isEmpty else {
            throw DeterministicTargetTestFailure.emptyScript(kind: "health")
        }
        guard operationScripts.allSatisfy({ $0.accountId == context.accountId }),
              unresolvedOperationScript.accountId == context.accountId else {
            throw DeterministicTargetTestFailure.crossAccountAccess
        }

        let operationIds = operationScripts.map(\.operationId)
        guard Set(operationIds).count == operationIds.count else {
            throw DeterministicTargetTestFailure.duplicateScript(kind: "operation")
        }
        let operationIdSet = Set(operationIds)
        guard unresolvedOperationScript.snapshots
            .flatMap({ $0 })
            .allSatisfy({ operationIdSet.contains($0.operationId) }) else {
            throw DeterministicTargetTestFailure.invalidScript(
                kind: "unresolved_operation_reference"
            )
        }

        let durabilityIds = durabilityOutcomes.map(\.operationId)
        guard Set(durabilityIds).count == durabilityIds.count else {
            throw DeterministicTargetTestFailure.duplicateScript(kind: "durability")
        }
        guard Set(durabilityIds) == operationIdSet else {
            throw DeterministicTargetTestFailure.invalidScript(
                kind: "durability_operation_reference"
            )
        }

        self.context = context
        self.valueSource = valueSource
        self.operationScripts = operationScripts.sorted {
            $0.operationId.rawValue < $1.operationId.rawValue
        }
        self.unresolvedOperationScript = unresolvedOperationScript
        self.healthSnapshots = healthSnapshots
        self.durabilityOutcomes = durabilityOutcomes.sorted {
            $0.operationId.rawValue < $1.operationId.rawValue
        }
    }

    public func operationQueryAdapter() -> ScriptedOperationQueryAdapter {
        ScriptedOperationQueryAdapter(scenario: self)
    }

    public func syncHealthAdapter() -> ScriptedSyncHealthAdapter {
        ScriptedSyncHealthAdapter(scenario: self)
    }

    public func canonicalEvidence() throws -> Data {
        let content = EvidenceContent(scenario: self)
        let contentBytes = try CanonicalCodec.encode(content)
        let envelope = EvidenceEnvelope(
            schemaVersion: 1,
            content: content,
            contentDigest: try CanonicalCodec.digest(contentBytes)
        )
        let data = try CanonicalCodec.encode(envelope)
        guard data.count <= Self.maximumCanonicalEvidenceBytes else {
            throw DeterministicTargetTestFailure.evidenceTooLarge(
                actual: data.count,
                maximum: Self.maximumCanonicalEvidenceBytes
            )
        }
        return data
    }

    public static func restore(
        from data: Data,
        policy: LedgerEnvironmentPolicy
    ) throws -> Self {
        guard data.count <= Self.maximumCanonicalEvidenceBytes else {
            throw DeterministicTargetTestFailure.evidenceTooLarge(
                actual: data.count,
                maximum: Self.maximumCanonicalEvidenceBytes
            )
        }

        let envelope: EvidenceEnvelope
        do {
            envelope = try CanonicalCodec.decode(EvidenceEnvelope.self, from: data)
        } catch {
            throw DeterministicTargetTestFailure.invalidEvidence
        }
        guard envelope.schemaVersion == 1 else {
            throw DeterministicTargetTestFailure.invalidEvidence
        }

        let contentBytes = try CanonicalCodec.encode(envelope.content)
        guard try CanonicalCodec.digest(contentBytes) == envelope.contentDigest else {
            throw DeterministicTargetTestFailure.evidenceDigestMismatch
        }

        let decodedContext = envelope.content.context
        let context = try DeterministicTargetTestContext.make(
            manifest: decodedContext.manifest,
            policy: policy,
            principalId: decodedContext.principalId,
            accountId: decodedContext.accountId,
            scenarioId: decodedContext.scenarioId,
            seed: decodedContext.seed,
            baseTimeMilliseconds: decodedContext.baseTimeMilliseconds
        )
        let decodedSource = envelope.content.valueSource
        let valueSource = try DeterministicTargetValueSource(
            context: context,
            maximumIndex: decodedSource.maximumIndex,
            stepMilliseconds: decodedSource.stepMilliseconds,
            startingRevision: decodedSource.startingRevision
        )
        let scenario = try Self(
            context: context,
            valueSource: valueSource,
            operationScripts: try envelope.content.operationScripts.map {
                try $0.revalidated()
            },
            unresolvedOperationScript: try envelope.content
                .unresolvedOperationScript.revalidated(),
            healthSnapshots: try envelope.content.healthSnapshots.map {
                try Self.revalidatedHealth($0)
            },
            durabilityOutcomes: envelope.content.durabilityOutcomes
        )

        guard try scenario.canonicalEvidence() == data else {
            throw DeterministicTargetTestFailure.nonCanonicalEvidence
        }
        return scenario
    }

    private static func revalidatedHealth(
        _ snapshot: SyncHealthSnapshot
    ) throws -> SyncHealthSnapshot {
        try SyncHealthSnapshot(
            connectivity: snapshot.connectivity,
            authentication: snapshot.authentication,
            subscriptions: snapshot.subscriptions,
            lastSuccessfulCheckpointAt: snapshot.lastSuccessfulCheckpointAt,
            pendingOperationCount: snapshot.pendingOperationCount,
            oldestPendingOperationAt: snapshot.oldestPendingOperationAt,
            pendingAttachmentCount: snapshot.pendingAttachmentCount,
            oldestPendingAttachmentAt: snapshot.oldestPendingAttachmentAt,
            rejectedOperationCount: snapshot.rejectedOperationCount,
            transientError: snapshot.transientError,
            writeBlock: snapshot.writeBlock
        )
    }

    private struct EvidenceContent: Codable, Equatable, Sendable {
        let context: DeterministicTargetTestContext
        let valueSource: DeterministicTargetValueSource
        let operationScripts: [ScriptedOperationSequence]
        let unresolvedOperationScript: ScriptedUnresolvedOperationSequence
        let healthSnapshots: [SyncHealthSnapshot]
        let durabilityOutcomes: [ScriptedDurabilityOutcome]

        init(scenario: DeterministicTargetScenario) {
            context = scenario.context
            valueSource = scenario.valueSource
            operationScripts = scenario.operationScripts
            unresolvedOperationScript = scenario.unresolvedOperationScript
            healthSnapshots = scenario.healthSnapshots
            durabilityOutcomes = scenario.durabilityOutcomes
        }
    }

    private struct EvidenceEnvelope: Codable, Equatable, Sendable {
        let schemaVersion: Int
        let content: EvidenceContent
        let contentDigest: OperationFingerprint
    }
}

public struct ScriptedOperationQueryAdapter: OperationQuerying, Sendable {
    private let context: DeterministicTargetTestContext
    private let operationScripts: [OperationID: ScriptedOperationSequence]
    private let unresolvedScript: ScriptedUnresolvedOperationSequence

    fileprivate init(scenario: DeterministicTargetScenario) {
        context = scenario.context
        operationScripts = Dictionary(
            uniqueKeysWithValues: scenario.operationScripts.map {
                ($0.operationId, $0)
            }
        )
        unresolvedScript = scenario.unresolvedOperationScript
    }

    public func watchOperation(
        _ id: OperationID
    ) -> AsyncThrowingStream<OperationSnapshot, Error> {
        guard let script = operationScripts[id] else {
            return Self.failedStream(.missingScript(kind: "operation"))
        }
        return Self.stream(values: script.snapshots, terminal: script.terminal)
    }

    public func watchUnresolvedOperations(
        accountId: AccountID
    ) -> AsyncThrowingStream<[OperationSnapshot], Error> {
        guard accountId == context.accountId,
              unresolvedScript.accountId == context.accountId else {
            return Self.failedStream(.crossAccountAccess)
        }
        return Self.stream(
            values: unresolvedScript.snapshots,
            terminal: unresolvedScript.terminal
        )
    }

    private static func stream<Value: Sendable>(
        values: [Value],
        terminal: ScriptedAdapterTerminal
    ) -> AsyncThrowingStream<Value, Error> {
        AsyncThrowingStream { continuation in
            for value in values {
                continuation.yield(value)
            }
            switch terminal {
            case .finished:
                continuation.finish()
            case .failure(let error):
                continuation.finish(
                    throwing: DeterministicTargetTestFailure.scriptedFailure(error)
                )
            }
        }
    }

    private static func failedStream<Value: Sendable>(
        _ failure: DeterministicTargetTestFailure
    ) -> AsyncThrowingStream<Value, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: failure)
        }
    }
}

public struct ScriptedSyncHealthAdapter: SyncHealthProviding, Sendable {
    private let healthSnapshots: [SyncHealthSnapshot]
    private let durabilityOutcomes: [OperationID: ScriptedDurabilityResult]

    fileprivate init(scenario: DeterministicTargetScenario) {
        healthSnapshots = scenario.healthSnapshots
        durabilityOutcomes = Dictionary(
            uniqueKeysWithValues: scenario.durabilityOutcomes.map {
                ($0.operationId, $0.result)
            }
        )
    }

    public func observeHealth() -> AsyncStream<SyncHealthSnapshot> {
        AsyncStream { continuation in
            for snapshot in healthSnapshots {
                continuation.yield(snapshot)
            }
            continuation.finish()
        }
    }

    public func waitForLocalDurability(of operationId: OperationID) async throws {
        guard let outcome = durabilityOutcomes[operationId] else {
            throw DeterministicTargetTestFailure.missingScript(kind: "durability")
        }
        switch outcome {
        case .durable:
            return
        case .failure(let error):
            throw DeterministicTargetTestFailure.scriptedFailure(error)
        }
    }
}

private enum CanonicalCodec {
    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(value)
    }

    static func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data
    ) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: data)
    }

    static func digest(_ data: Data) throws -> OperationFingerprint {
        let value = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        return try OperationFingerprint(validating: value)
    }
}
