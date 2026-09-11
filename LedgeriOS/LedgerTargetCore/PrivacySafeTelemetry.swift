import CryptoKit
import Foundation

public enum TelemetryContractFailure: Error, Equatable, Sendable {
    case invalidApplicationVersion
    case invalidBuildNumber
    case invalidSourceRevision
    case invalidContractVersion(String)
    case invalidCorrelationKey
    case invalidCorrelationDigest
    case duplicateEvent(TelemetryEventID)
    case missingEvent(TelemetryEventID)
    case duplicateMetric(TelemetryMetricID)
    case missingMetric(TelemetryMetricID)
    case unknownTelemetryClass(signal: String, telemetryClass: TelemetryClassID)
    case tooManyDimensionRules(signal: String, maximum: Int)
    case duplicateDimensionRule(signal: String, key: TelemetryDimensionKey)
    case emptyDimensionAllowlist(signal: String, key: TelemetryDimensionKey)
    case duplicateDimensionValue(
        signal: String,
        key: TelemetryDimensionKey,
        value: TelemetryDimensionCode
    )
    case tooManyCorrelationKinds(signal: String, maximum: Int)
    case duplicateCorrelationKind(signal: String, kind: TelemetryCorrelationKind)
    case invalidMetricBounds(TelemetryMetricID)
    case invalidObservedAt
    case dimensionNotAllowed(signal: String, key: TelemetryDimensionKey)
    case dimensionValueNotAllowed(
        signal: String,
        key: TelemetryDimensionKey,
        value: TelemetryDimensionCode
    )
    case duplicateDimension(TelemetryDimensionKey)
    case correlationNotAllowed(signal: String, kind: TelemetryCorrelationKind)
    case duplicateCorrelation(TelemetryCorrelationKind)
    case correlationScopeMismatch(TelemetryCorrelationKind)
    case metricUnitMismatch(
        metric: TelemetryMetricID,
        expected: TelemetryMetricUnit,
        actual: TelemetryMetricUnit
    )
    case metricValueOutOfRange(metric: TelemetryMetricID, value: UInt64)
    case envelopeTooLarge(actual: Int, maximum: Int)
}

public enum TelemetryEventID: String, Codable, CaseIterable, Sendable {
    case environmentValidationCompleted = "target_environment_validation_completed"
    case contractReadCompleted = "target_contract_read_completed"
    case operationStatusObserved = "target_operation_status_observed"
    case syncHealthObserved = "target_sync_health_observed"
}

public enum TelemetryMetricID: String, Codable, CaseIterable, Sendable {
    case contractReadDurationMilliseconds = "target_contract_read_duration_ms"
    case operationStatusReadDurationMilliseconds = "target_operation_status_read_duration_ms"
    case syncLagMilliseconds = "target_sync_lag_ms"
    case pendingOperationCount = "target_pending_operation_count"
}

public enum TelemetryDimensionKey: String, Codable, CaseIterable, Sendable {
    case outcome
    case contractKind = "contract_kind"
    case operationPhase = "operation_phase"
    case errorCategory = "error_category"
    case retryDisposition = "retry_disposition"
    case connectivity
    case subscriptionReadiness = "subscription_readiness"
    case writeBlock = "write_block"
}

public enum TelemetryDimensionCodeTag: Sendable {}
public typealias TelemetryDimensionCode = StableCode<TelemetryDimensionCodeTag>

public enum TelemetryMetricUnit: String, Codable, CaseIterable, Sendable {
    case milliseconds
    case count
    case bytes
}

public enum TelemetryCorrelationKind: String, Codable, CaseIterable, Sendable {
    case session
    case principal
    case account
    case operation
    case entity
    case syncCheckpoint = "sync_checkpoint"
}

public enum TelemetrySessionIDTag: Sendable {}
public enum TelemetrySyncCheckpointIDTag: Sendable {}

public typealias TelemetrySessionID = LedgerIdentifier<TelemetrySessionIDTag>
public typealias TelemetrySyncCheckpointID = LedgerIdentifier<TelemetrySyncCheckpointIDTag>

public struct TelemetryApplicationVersion: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        guard Self.isSafeBuildToken(rawValue, maximumBytes: 32) else {
            throw TelemetryContractFailure.invalidApplicationVersion
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        do {
            try self.init(validating: value)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid telemetry application version"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    fileprivate static func isSafeBuildToken(
        _ value: String,
        maximumBytes: Int
    ) -> Bool {
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: ".-_"))
        return value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.isEmpty
            && value.utf8.count <= maximumBytes
            && value.unicodeScalars.allSatisfy(allowed.contains)
    }
}

public struct TelemetrySourceRevision: Codable, Equatable, Hashable, Sendable {
    public let sha256OrGitSHA: String

    public init(validating sha256OrGitSHA: String) throws {
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        guard [40, 64].contains(sha256OrGitSHA.utf8.count),
              sha256OrGitSHA.unicodeScalars.allSatisfy(hexadecimal.contains) else {
            throw TelemetryContractFailure.invalidSourceRevision
        }
        self.sha256OrGitSHA = sha256OrGitSHA
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        do {
            try self.init(validating: value)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid telemetry source revision"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(sha256OrGitSHA)
    }
}

public struct TelemetryBuildScope: Codable, Equatable, Sendable {
    public let environment: LedgerEnvironmentKind
    public let buildProfile: LedgerBuildProfile
    public let applicationVersion: TelemetryApplicationVersion
    public let buildNumber: UInt64
    public let sourceRevision: TelemetrySourceRevision
    public let contractVersions: LedgerContractVersions

    public init(
        validatedEnvironment: ValidatedLedgerEnvironment,
        applicationVersion: TelemetryApplicationVersion,
        buildNumber: UInt64,
        sourceRevision: TelemetrySourceRevision
    ) throws {
        try self.init(
            environment: validatedEnvironment.manifest.environment,
            buildProfile: validatedEnvironment.manifest.buildProfile,
            applicationVersion: applicationVersion,
            buildNumber: buildNumber,
            sourceRevision: sourceRevision,
            contractVersions: validatedEnvironment.manifest.contractVersions
        )
    }

    private init(
        environment: LedgerEnvironmentKind,
        buildProfile: LedgerBuildProfile,
        applicationVersion: TelemetryApplicationVersion,
        buildNumber: UInt64,
        sourceRevision: TelemetrySourceRevision,
        contractVersions: LedgerContractVersions
    ) throws {
        guard buildProfile.environment == environment, buildNumber > 0 else {
            throw TelemetryContractFailure.invalidBuildNumber
        }
        let versions = [
            ("schema", contractVersions.schema),
            ("query", contractVersions.query),
            ("operation", contractVersions.operation),
            ("sync", contractVersions.sync)
        ]
        for (name, version) in versions where
            !TelemetryApplicationVersion.isSafeBuildToken(version, maximumBytes: 32) {
            throw TelemetryContractFailure.invalidContractVersion(name)
        }

        self.environment = environment
        self.buildProfile = buildProfile
        self.applicationVersion = applicationVersion
        self.buildNumber = buildNumber
        self.sourceRevision = sourceRevision
        self.contractVersions = contractVersions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                environment: container.decode(LedgerEnvironmentKind.self, forKey: .environment),
                buildProfile: container.decode(LedgerBuildProfile.self, forKey: .buildProfile),
                applicationVersion: container.decode(
                    TelemetryApplicationVersion.self,
                    forKey: .applicationVersion
                ),
                buildNumber: container.decode(UInt64.self, forKey: .buildNumber),
                sourceRevision: container.decode(
                    TelemetrySourceRevision.self,
                    forKey: .sourceRevision
                ),
                contractVersions: container.decode(
                    LedgerContractVersions.self,
                    forKey: .contractVersions
                )
            )
        } catch let failure as TelemetryContractFailure {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid telemetry build scope: \(failure)"
                )
            )
        }
    }

    fileprivate var correlationScopeDigest: String {
        let material = [
            environment.rawValue,
            buildProfile.rawValue,
            applicationVersion.rawValue,
            String(buildNumber),
            sourceRevision.sha256OrGitSHA,
            contractVersions.schema,
            contractVersions.query,
            contractVersions.operation,
            contractVersions.sync
        ].joined(separator: "\u{1f}")
        return SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

public struct TelemetryCorrelationKey: Sendable {
    fileprivate let bytes: [UInt8]

    public init(validating data: Data) throws {
        let bytes = Array(data)
        guard bytes.count == 32, bytes.contains(where: { $0 != 0 }) else {
            throw TelemetryContractFailure.invalidCorrelationKey
        }
        self.bytes = bytes
    }
}

public struct TelemetryCorrelation: Encodable, Equatable, Hashable, Sendable {
    public let kind: TelemetryCorrelationKind
    public let digest: String
    fileprivate let scopeDigest: String

    fileprivate init(
        kind: TelemetryCorrelationKind,
        digest: String,
        scopeDigest: String
    ) throws {
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        guard digest.utf8.count == 64,
              digest.unicodeScalars.allSatisfy(hexadecimal.contains),
              scopeDigest.utf8.count == 64,
              scopeDigest.unicodeScalars.allSatisfy(hexadecimal.contains) else {
            throw TelemetryContractFailure.invalidCorrelationDigest
        }
        self.kind = kind
        self.digest = digest
        self.scopeDigest = scopeDigest
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case digest
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(digest, forKey: .digest)
    }
}

private struct TelemetryCorrelationWire: Decodable {
    let kind: TelemetryCorrelationKind
    let digest: String
}

public struct TelemetryCorrelationFactory: Sendable {
    private let key: TelemetryCorrelationKey
    private let scope: TelemetryBuildScope

    public init(key: TelemetryCorrelationKey, scope: TelemetryBuildScope) {
        self.key = key
        self.scope = scope
    }

    public func session(_ id: TelemetrySessionID) throws -> TelemetryCorrelation {
        try make(kind: .session, material: id.rawValue)
    }

    public func principal(_ id: PrincipalID) throws -> TelemetryCorrelation {
        try make(kind: .principal, material: id.rawValue)
    }

    public func account(_ id: AccountID) throws -> TelemetryCorrelation {
        try make(kind: .account, material: id.rawValue)
    }

    public func operation(_ id: OperationID) throws -> TelemetryCorrelation {
        try make(kind: .operation, material: id.rawValue)
    }

    public func entity(_ reference: LedgerEntityReference) throws -> TelemetryCorrelation {
        try make(
            kind: .entity,
            material: "\(reference.kind.rawValue)\u{1e}\(reference.id.rawValue)"
        )
    }

    public func syncCheckpoint(
        _ id: TelemetrySyncCheckpointID
    ) throws -> TelemetryCorrelation {
        try make(kind: .syncCheckpoint, material: id.rawValue)
    }

    private func make(
        kind: TelemetryCorrelationKind,
        material: String
    ) throws -> TelemetryCorrelation {
        let scopeDigest = scope.correlationScopeDigest
        let input = [
            "ledger-target-telemetry-v1",
            scopeDigest,
            kind.rawValue,
            material
        ].joined(separator: "\u{1f}")
        let authenticationCode = HMAC<SHA256>.authenticationCode(
            for: Data(input.utf8),
            using: SymmetricKey(data: key.bytes)
        )
        let digest = authenticationCode
            .map { String(format: "%02x", $0) }
            .joined()
        return try TelemetryCorrelation(
            kind: kind,
            digest: digest,
            scopeDigest: scopeDigest
        )
    }
}

public struct TelemetryDimension: Encodable, Equatable, Hashable, Sendable {
    public let key: TelemetryDimensionKey
    public let value: TelemetryDimensionCode

    public init(key: TelemetryDimensionKey, value: TelemetryDimensionCode) {
        self.key = key
        self.value = value
    }
}

private struct TelemetryDimensionWire: Decodable {
    let key: TelemetryDimensionKey
    let value: TelemetryDimensionCode
}

public struct TelemetryDimensionRule: Equatable, Sendable {
    public let key: TelemetryDimensionKey
    public let allowedValues: [TelemetryDimensionCode]

    public init(
        key: TelemetryDimensionKey,
        allowedValues: [TelemetryDimensionCode]
    ) {
        self.key = key
        self.allowedValues = allowedValues
    }
}

public struct TelemetryEventDefinition: Equatable, Sendable {
    public let id: TelemetryEventID
    public let telemetryClass: TelemetryClassID
    public let dimensionRules: [TelemetryDimensionRule]
    public let correlationKinds: [TelemetryCorrelationKind]

    public init(
        id: TelemetryEventID,
        telemetryClass: TelemetryClassID,
        dimensionRules: [TelemetryDimensionRule],
        correlationKinds: [TelemetryCorrelationKind]
    ) {
        self.id = id
        self.telemetryClass = telemetryClass
        self.dimensionRules = dimensionRules
        self.correlationKinds = correlationKinds
    }
}

public struct TelemetryMetricDefinition: Equatable, Sendable {
    public let id: TelemetryMetricID
    public let telemetryClass: TelemetryClassID
    public let unit: TelemetryMetricUnit
    public let minimumValue: UInt64
    public let maximumValue: UInt64
    public let dimensionRules: [TelemetryDimensionRule]
    public let correlationKinds: [TelemetryCorrelationKind]

    public init(
        id: TelemetryMetricID,
        telemetryClass: TelemetryClassID,
        unit: TelemetryMetricUnit,
        minimumValue: UInt64,
        maximumValue: UInt64,
        dimensionRules: [TelemetryDimensionRule],
        correlationKinds: [TelemetryCorrelationKind]
    ) {
        self.id = id
        self.telemetryClass = telemetryClass
        self.unit = unit
        self.minimumValue = minimumValue
        self.maximumValue = maximumValue
        self.dimensionRules = dimensionRules
        self.correlationKinds = correlationKinds
    }
}

public struct TelemetryEvent: Encodable, Equatable, Sendable {
    public let id: TelemetryEventID
    public let telemetryClass: TelemetryClassID
    public let scope: TelemetryBuildScope
    public let observedAt: Date
    public let dimensions: [TelemetryDimension]
    public let correlations: [TelemetryCorrelation]

    fileprivate init(
        id: TelemetryEventID,
        telemetryClass: TelemetryClassID,
        scope: TelemetryBuildScope,
        observedAt: Date,
        dimensions: [TelemetryDimension],
        correlations: [TelemetryCorrelation]
    ) {
        self.id = id
        self.telemetryClass = telemetryClass
        self.scope = scope
        self.observedAt = observedAt
        self.dimensions = dimensions
        self.correlations = correlations
    }
}

public struct TelemetryMetricSample: Encodable, Equatable, Sendable {
    public let id: TelemetryMetricID
    public let telemetryClass: TelemetryClassID
    public let scope: TelemetryBuildScope
    public let observedAt: Date
    public let unit: TelemetryMetricUnit
    public let value: UInt64
    public let dimensions: [TelemetryDimension]
    public let correlations: [TelemetryCorrelation]

    fileprivate init(
        id: TelemetryMetricID,
        telemetryClass: TelemetryClassID,
        scope: TelemetryBuildScope,
        observedAt: Date,
        unit: TelemetryMetricUnit,
        value: UInt64,
        dimensions: [TelemetryDimension],
        correlations: [TelemetryCorrelation]
    ) {
        self.id = id
        self.telemetryClass = telemetryClass
        self.scope = scope
        self.observedAt = observedAt
        self.unit = unit
        self.value = value
        self.dimensions = dimensions
        self.correlations = correlations
    }
}

private struct TelemetryEventWire: Decodable {
    let id: TelemetryEventID
    let telemetryClass: TelemetryClassID
    let scope: TelemetryBuildScope
    let observedAt: Date
    let dimensions: [TelemetryDimensionWire]
    let correlations: [TelemetryCorrelationWire]
}

private struct TelemetryMetricSampleWire: Decodable {
    let id: TelemetryMetricID
    let telemetryClass: TelemetryClassID
    let scope: TelemetryBuildScope
    let observedAt: Date
    let unit: TelemetryMetricUnit
    let value: UInt64
    let dimensions: [TelemetryDimensionWire]
    let correlations: [TelemetryCorrelationWire]
}

public struct TelemetrySignalCatalog: Sendable {
    public static let maximumDimensionRules = 8
    public static let maximumCorrelationKinds = 6
    public static let maximumCanonicalEnvelopeBytes = 1_536
    public static let maximumMetricValue: UInt64 = 1_000_000_000_000

    public let eventDefinitions: [TelemetryEventDefinition]
    public let metricDefinitions: [TelemetryMetricDefinition]

    private let eventsByID: [TelemetryEventID: TelemetryEventDefinition]
    private let metricsByID: [TelemetryMetricID: TelemetryMetricDefinition]

    public var eventIDs: Set<TelemetryEventID> { Set(eventsByID.keys) }
    public var metricIDs: Set<TelemetryMetricID> { Set(metricsByID.keys) }

    public init(
        contractCatalog: VersionedContractCatalog,
        eventDefinitions: [TelemetryEventDefinition],
        metricDefinitions: [TelemetryMetricDefinition]
    ) throws {
        let knownClasses = Set(contractCatalog.telemetryClasses.map(\.id))
        var eventsByID: [TelemetryEventID: TelemetryEventDefinition] = [:]
        for definition in eventDefinitions {
            guard eventsByID[definition.id] == nil else {
                throw TelemetryContractFailure.duplicateEvent(definition.id)
            }
            try Self.validateDefinition(
                signal: definition.id.rawValue,
                telemetryClass: definition.telemetryClass,
                dimensionRules: definition.dimensionRules,
                correlationKinds: definition.correlationKinds,
                knownClasses: knownClasses
            )
            eventsByID[definition.id] = definition
        }
        for id in TelemetryEventID.allCases where eventsByID[id] == nil {
            throw TelemetryContractFailure.missingEvent(id)
        }

        var metricsByID: [TelemetryMetricID: TelemetryMetricDefinition] = [:]
        for definition in metricDefinitions {
            guard metricsByID[definition.id] == nil else {
                throw TelemetryContractFailure.duplicateMetric(definition.id)
            }
            try Self.validateDefinition(
                signal: definition.id.rawValue,
                telemetryClass: definition.telemetryClass,
                dimensionRules: definition.dimensionRules,
                correlationKinds: definition.correlationKinds,
                knownClasses: knownClasses
            )
            guard definition.minimumValue <= definition.maximumValue,
                  definition.maximumValue <= Self.maximumMetricValue else {
                throw TelemetryContractFailure.invalidMetricBounds(definition.id)
            }
            metricsByID[definition.id] = definition
        }
        for id in TelemetryMetricID.allCases where metricsByID[id] == nil {
            throw TelemetryContractFailure.missingMetric(id)
        }

        self.eventDefinitions = eventDefinitions.sorted { $0.id.rawValue < $1.id.rawValue }
        self.metricDefinitions = metricDefinitions.sorted { $0.id.rawValue < $1.id.rawValue }
        self.eventsByID = eventsByID
        self.metricsByID = metricsByID
    }

    public func makeEvent(
        id: TelemetryEventID,
        scope: TelemetryBuildScope,
        observedAt: Date,
        dimensions: [TelemetryDimension] = [],
        correlations: [TelemetryCorrelation] = []
    ) throws -> TelemetryEvent {
        guard let definition = eventsByID[id] else {
            throw TelemetryContractFailure.missingEvent(id)
        }
        try Self.validateObservedAt(observedAt)
        let normalized = try Self.validateFields(
            signal: id.rawValue,
            scope: scope,
            dimensions: dimensions,
            correlations: correlations,
            rules: definition.dimensionRules,
            allowedCorrelationKinds: definition.correlationKinds
        )
        let event = TelemetryEvent(
            id: id,
            telemetryClass: definition.telemetryClass,
            scope: scope,
            observedAt: observedAt,
            dimensions: normalized.dimensions,
            correlations: normalized.correlations
        )
        try Self.validateCanonicalSize(event)
        return event
    }

    public func makeMetricSample(
        id: TelemetryMetricID,
        scope: TelemetryBuildScope,
        observedAt: Date,
        unit: TelemetryMetricUnit,
        value: UInt64,
        dimensions: [TelemetryDimension] = [],
        correlations: [TelemetryCorrelation] = []
    ) throws -> TelemetryMetricSample {
        guard let definition = metricsByID[id] else {
            throw TelemetryContractFailure.missingMetric(id)
        }
        guard unit == definition.unit else {
            throw TelemetryContractFailure.metricUnitMismatch(
                metric: id,
                expected: definition.unit,
                actual: unit
            )
        }
        guard (definition.minimumValue...definition.maximumValue).contains(value) else {
            throw TelemetryContractFailure.metricValueOutOfRange(metric: id, value: value)
        }
        try Self.validateObservedAt(observedAt)
        let normalized = try Self.validateFields(
            signal: id.rawValue,
            scope: scope,
            dimensions: dimensions,
            correlations: correlations,
            rules: definition.dimensionRules,
            allowedCorrelationKinds: definition.correlationKinds
        )
        let sample = TelemetryMetricSample(
            id: id,
            telemetryClass: definition.telemetryClass,
            scope: scope,
            observedAt: observedAt,
            unit: unit,
            value: value,
            dimensions: normalized.dimensions,
            correlations: normalized.correlations
        )
        try Self.validateCanonicalSize(sample)
        return sample
    }

    public func canonicalData(for event: TelemetryEvent) throws -> Data {
        let validated = try makeEvent(
            id: event.id,
            scope: event.scope,
            observedAt: event.observedAt,
            dimensions: event.dimensions,
            correlations: event.correlations
        )
        return try OperationContractCodec.encode(validated)
    }

    public func canonicalData(for sample: TelemetryMetricSample) throws -> Data {
        let validated = try makeMetricSample(
            id: sample.id,
            scope: sample.scope,
            observedAt: sample.observedAt,
            unit: sample.unit,
            value: sample.value,
            dimensions: sample.dimensions,
            correlations: sample.correlations
        )
        return try OperationContractCodec.encode(validated)
    }

    public func decodeEvent(from data: Data) throws -> TelemetryEvent {
        let wire = try OperationContractCodec.decode(TelemetryEventWire.self, from: data)
        guard eventsByID[wire.id]?.telemetryClass == wire.telemetryClass else {
            throw TelemetryContractFailure.unknownTelemetryClass(
                signal: wire.id.rawValue,
                telemetryClass: wire.telemetryClass
            )
        }
        return try makeEvent(
            id: wire.id,
            scope: wire.scope,
            observedAt: wire.observedAt,
            dimensions: wire.dimensions.map {
                TelemetryDimension(key: $0.key, value: $0.value)
            },
            correlations: try wire.correlations.map {
                try TelemetryCorrelation(
                    kind: $0.kind,
                    digest: $0.digest,
                    scopeDigest: wire.scope.correlationScopeDigest
                )
            }
        )
    }

    public func decodeMetricSample(from data: Data) throws -> TelemetryMetricSample {
        let wire = try OperationContractCodec.decode(
            TelemetryMetricSampleWire.self,
            from: data
        )
        guard metricsByID[wire.id]?.telemetryClass == wire.telemetryClass else {
            throw TelemetryContractFailure.unknownTelemetryClass(
                signal: wire.id.rawValue,
                telemetryClass: wire.telemetryClass
            )
        }
        return try makeMetricSample(
            id: wire.id,
            scope: wire.scope,
            observedAt: wire.observedAt,
            unit: wire.unit,
            value: wire.value,
            dimensions: wire.dimensions.map {
                TelemetryDimension(key: $0.key, value: $0.value)
            },
            correlations: try wire.correlations.map {
                try TelemetryCorrelation(
                    kind: $0.kind,
                    digest: $0.digest,
                    scopeDigest: wire.scope.correlationScopeDigest
                )
            }
        )
    }

    private static func validateDefinition(
        signal: String,
        telemetryClass: TelemetryClassID,
        dimensionRules: [TelemetryDimensionRule],
        correlationKinds: [TelemetryCorrelationKind],
        knownClasses: Set<TelemetryClassID>
    ) throws {
        guard knownClasses.contains(telemetryClass) else {
            throw TelemetryContractFailure.unknownTelemetryClass(
                signal: signal,
                telemetryClass: telemetryClass
            )
        }
        guard dimensionRules.count <= maximumDimensionRules else {
            throw TelemetryContractFailure.tooManyDimensionRules(
                signal: signal,
                maximum: maximumDimensionRules
            )
        }
        var ruleKeys: Set<TelemetryDimensionKey> = []
        for rule in dimensionRules {
            guard ruleKeys.insert(rule.key).inserted else {
                throw TelemetryContractFailure.duplicateDimensionRule(
                    signal: signal,
                    key: rule.key
                )
            }
            guard !rule.allowedValues.isEmpty else {
                throw TelemetryContractFailure.emptyDimensionAllowlist(
                    signal: signal,
                    key: rule.key
                )
            }
            var values: Set<TelemetryDimensionCode> = []
            for value in rule.allowedValues where !values.insert(value).inserted {
                throw TelemetryContractFailure.duplicateDimensionValue(
                    signal: signal,
                    key: rule.key,
                    value: value
                )
            }
        }
        guard correlationKinds.count <= maximumCorrelationKinds else {
            throw TelemetryContractFailure.tooManyCorrelationKinds(
                signal: signal,
                maximum: maximumCorrelationKinds
            )
        }
        var kinds: Set<TelemetryCorrelationKind> = []
        for kind in correlationKinds where !kinds.insert(kind).inserted {
            throw TelemetryContractFailure.duplicateCorrelationKind(
                signal: signal,
                kind: kind
            )
        }
    }

    private static func validateObservedAt(_ observedAt: Date) throws {
        let value = observedAt.timeIntervalSince1970
        guard value.isFinite, value >= 0 else {
            throw TelemetryContractFailure.invalidObservedAt
        }
    }

    private static func validateFields(
        signal: String,
        scope: TelemetryBuildScope,
        dimensions: [TelemetryDimension],
        correlations: [TelemetryCorrelation],
        rules: [TelemetryDimensionRule],
        allowedCorrelationKinds: [TelemetryCorrelationKind]
    ) throws -> (dimensions: [TelemetryDimension], correlations: [TelemetryCorrelation]) {
        let rulesByKey = Dictionary(
            uniqueKeysWithValues: rules.map { ($0.key, Set($0.allowedValues)) }
        )
        var seenKeys: Set<TelemetryDimensionKey> = []
        for dimension in dimensions {
            guard seenKeys.insert(dimension.key).inserted else {
                throw TelemetryContractFailure.duplicateDimension(dimension.key)
            }
            guard let allowed = rulesByKey[dimension.key] else {
                throw TelemetryContractFailure.dimensionNotAllowed(
                    signal: signal,
                    key: dimension.key
                )
            }
            guard allowed.contains(dimension.value) else {
                throw TelemetryContractFailure.dimensionValueNotAllowed(
                    signal: signal,
                    key: dimension.key,
                    value: dimension.value
                )
            }
        }

        let allowedKinds = Set(allowedCorrelationKinds)
        let scopeDigest = scope.correlationScopeDigest
        var seenKinds: Set<TelemetryCorrelationKind> = []
        for correlation in correlations {
            guard allowedKinds.contains(correlation.kind) else {
                throw TelemetryContractFailure.correlationNotAllowed(
                    signal: signal,
                    kind: correlation.kind
                )
            }
            guard seenKinds.insert(correlation.kind).inserted else {
                throw TelemetryContractFailure.duplicateCorrelation(correlation.kind)
            }
            guard correlation.scopeDigest == scopeDigest else {
                throw TelemetryContractFailure.correlationScopeMismatch(correlation.kind)
            }
        }

        return (
            dimensions.sorted { $0.key.rawValue < $1.key.rawValue },
            correlations.sorted { $0.kind.rawValue < $1.kind.rawValue }
        )
    }

    private static func validateCanonicalSize<Value: Encodable>(_ value: Value) throws {
        let size = try OperationContractCodec.encode(value).count
        guard size <= maximumCanonicalEnvelopeBytes else {
            throw TelemetryContractFailure.envelopeTooLarge(
                actual: size,
                maximum: maximumCanonicalEnvelopeBytes
            )
        }
    }
}

public enum TelemetryDataClass: String, Codable, CaseIterable, Sendable {
    case allowlistedDimension = "allowlisted_dimension"
    case opaqueCorrelation = "opaque_correlation"
    case accessToken = "access_token"
    case serviceKey = "service_key"
    case signedURL = "signed_url"
    case privateNote = "private_note"
    case media
    case financialValue = "financial_value"
    case commandPayload = "command_payload"
    case providerMessage = "provider_message"
    case rawIdentifier = "raw_identifier"
    case unclassified
}

public enum TelemetryRedactionCode: String, Codable, CaseIterable, Sendable {
    case credentialMaterialRedacted = "credential_material_redacted"
    case signedURLRedacted = "signed_url_redacted"
    case privateTextRedacted = "private_text_redacted"
    case mediaRedacted = "media_redacted"
    case financialValueRedacted = "financial_value_redacted"
    case commandPayloadRedacted = "command_payload_redacted"
    case providerMessageRedacted = "provider_message_redacted"
    case identifierRequiresOpaqueCorrelation = "identifier_requires_opaque_correlation"
    case unclassifiedValueRefused = "unclassified_value_refused"
}

public enum TelemetryFieldDisposition: Codable, Equatable, Sendable {
    case include
    case redact(TelemetryRedactionCode)
    case refuse(TelemetryRedactionCode)
}

public enum TelemetryRedactionPolicy {
    public static func disposition(
        for dataClass: TelemetryDataClass
    ) -> TelemetryFieldDisposition {
        switch dataClass {
        case .allowlistedDimension, .opaqueCorrelation:
            .include
        case .accessToken, .serviceKey:
            .redact(.credentialMaterialRedacted)
        case .signedURL:
            .redact(.signedURLRedacted)
        case .privateNote:
            .redact(.privateTextRedacted)
        case .media:
            .redact(.mediaRedacted)
        case .financialValue:
            .redact(.financialValueRedacted)
        case .commandPayload:
            .redact(.commandPayloadRedacted)
        case .providerMessage:
            .redact(.providerMessageRedacted)
        case .rawIdentifier:
            .refuse(.identifierRequiresOpaqueCorrelation)
        case .unclassified:
            .refuse(.unclassifiedValueRefused)
        }
    }
}

public enum TargetTelemetrySignalCatalog {
    public static func make(
        contractCatalog: VersionedContractCatalog
    ) throws -> TelemetrySignalCatalog {
        try TelemetrySignalCatalog(
            contractCatalog: contractCatalog,
            eventDefinitions: eventDefinitions(),
            metricDefinitions: metricDefinitions()
        )
    }

    public static func eventDefinitions() throws -> [TelemetryEventDefinition] {
        let acceptedRejected = try codes("accepted", "rejected")
        let operationOutcomes = try codes("accepted", "rejected", "required_update")
        let contractKinds = try codes(
            "capability_manifest",
            "contract_catalog",
            "environment_manifest",
            "operation_status",
            "sync_health"
        )
        return [
            TelemetryEventDefinition(
                id: .environmentValidationCompleted,
                telemetryClass: try telemetryClass("platform_environment_validation"),
                dimensionRules: [
                    TelemetryDimensionRule(key: .outcome, allowedValues: acceptedRejected)
                ],
                correlationKinds: [.session]
            ),
            TelemetryEventDefinition(
                id: .contractReadCompleted,
                telemetryClass: try telemetryClass("platform_contract_read"),
                dimensionRules: [
                    TelemetryDimensionRule(key: .outcome, allowedValues: acceptedRejected),
                    TelemetryDimensionRule(key: .contractKind, allowedValues: contractKinds)
                ],
                correlationKinds: [.session]
            ),
            TelemetryEventDefinition(
                id: .operationStatusObserved,
                telemetryClass: try telemetryClass("operation_status_read"),
                dimensionRules: [
                    TelemetryDimensionRule(key: .outcome, allowedValues: operationOutcomes),
                    TelemetryDimensionRule(
                        key: .operationPhase,
                        allowedValues: try codes(OperationPhase.allCases.map(\.rawValue))
                    ),
                    TelemetryDimensionRule(
                        key: .errorCategory,
                        allowedValues: try codes(
                            "validation",
                            "conflict",
                            "authorization",
                            "authentication",
                            "unsupported_contract",
                            "invariant",
                            "transient_infrastructure",
                            "required_update"
                        )
                    ),
                    TelemetryDimensionRule(
                        key: .retryDisposition,
                        allowedValues: try codes(
                            "never",
                            "automatic",
                            "after_user_correction",
                            "after_reauthentication",
                            "after_client_update"
                        )
                    )
                ],
                correlationKinds: [.session, .principal, .account, .operation, .entity]
            ),
            TelemetryEventDefinition(
                id: .syncHealthObserved,
                telemetryClass: try telemetryClass("local_sync_health_read"),
                dimensionRules: [
                    TelemetryDimensionRule(
                        key: .connectivity,
                        allowedValues: try codes(ConnectivityState.allCases.map(\.rawValue))
                    ),
                    TelemetryDimensionRule(
                        key: .subscriptionReadiness,
                        allowedValues: try codes(
                            "not_requested",
                            "loading",
                            "ready",
                            "stale",
                            "blocked"
                        )
                    ),
                    TelemetryDimensionRule(
                        key: .writeBlock,
                        allowedValues: try codes(
                            "none",
                            "maintenance",
                            "migration_required",
                            "client_update_required",
                            "authorization_expired",
                            "authorization_revoked"
                        )
                    )
                ],
                correlationKinds: [.session, .principal, .account, .syncCheckpoint]
            )
        ]
    }

    public static func metricDefinitions() throws -> [TelemetryMetricDefinition] {
        let acceptedRejected = try codes("accepted", "rejected")
        let readiness = try codes("not_requested", "loading", "ready", "stale", "blocked")
        return [
            TelemetryMetricDefinition(
                id: .contractReadDurationMilliseconds,
                telemetryClass: try telemetryClass("platform_contract_read"),
                unit: .milliseconds,
                minimumValue: 0,
                maximumValue: 600_000,
                dimensionRules: [
                    TelemetryDimensionRule(key: .outcome, allowedValues: acceptedRejected)
                ],
                correlationKinds: [.session]
            ),
            TelemetryMetricDefinition(
                id: .operationStatusReadDurationMilliseconds,
                telemetryClass: try telemetryClass("operation_status_read"),
                unit: .milliseconds,
                minimumValue: 0,
                maximumValue: 600_000,
                dimensionRules: [
                    TelemetryDimensionRule(key: .outcome, allowedValues: acceptedRejected)
                ],
                correlationKinds: [.session, .principal, .account, .operation]
            ),
            TelemetryMetricDefinition(
                id: .syncLagMilliseconds,
                telemetryClass: try telemetryClass("local_sync_health_read"),
                unit: .milliseconds,
                minimumValue: 0,
                maximumValue: 604_800_000,
                dimensionRules: [
                    TelemetryDimensionRule(
                        key: .subscriptionReadiness,
                        allowedValues: readiness
                    )
                ],
                correlationKinds: [.session, .principal, .account, .syncCheckpoint]
            ),
            TelemetryMetricDefinition(
                id: .pendingOperationCount,
                telemetryClass: try telemetryClass("operation_status_read"),
                unit: .count,
                minimumValue: 0,
                maximumValue: 1_000_000,
                dimensionRules: [
                    TelemetryDimensionRule(
                        key: .operationPhase,
                        allowedValues: try codes("queued", "applying")
                    )
                ],
                correlationKinds: [.session, .principal, .account]
            )
        ]
    }

    private static func telemetryClass(_ rawValue: String) throws -> TelemetryClassID {
        try TelemetryClassID(validating: rawValue)
    }

    private static func codes(_ rawValues: String...) throws -> [TelemetryDimensionCode] {
        try codes(rawValues)
    }

    private static func codes(_ rawValues: [String]) throws -> [TelemetryDimensionCode] {
        try rawValues.map(TelemetryDimensionCode.init(validating:))
    }
}
