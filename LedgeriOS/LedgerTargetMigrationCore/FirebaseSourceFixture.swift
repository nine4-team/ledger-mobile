import CryptoKit
import Foundation

public enum FirebaseSourceFixtureFailure: Error, Equatable, Sendable {
    case manifestEnvelopeTooLarge, manifestContentTooLarge, componentTooLarge
    case aggregatePayloadTooLarge, sourceByteCountTooLarge, malformedManifest, noncanonicalManifest
    case unsupportedSchemaVersion, unsupportedFixtureVersion, unsupportedSanitizationVersion
    case invalidProvenance, invalidAuthorityDisposition, invalidLogicalPath, duplicateLogicalPath
    case logicalPathCaseCollision, fileSetMismatch, fileRoleMismatch, fileOrderMismatch
    case fileByteCountMismatch, fileDigestMismatch, malformedPayload, noncanonicalPayload
    case resourceKindMismatch, payloadRecordCountMismatch, duplicateRecordID, recordIDCaseCollision
    case duplicateEntity, entityOrderMismatch, entityCountMismatch, entityDigestMismatch
    case bundleDigestMismatch, reviewedCatalogMismatch, invalidCapturedAt, invalidAccountScope
    case invalidStableCode, unknownField, prohibitedField, duplicateMapKey, invalidValueKind, invalidInteger
    case invalidDoubleBits, invalidTimestamp, invalidGeoPoint, invalidBytes, invalidReference
    case stringTooLarge, keyTooLarge, collectionTooLarge, nestingTooDeep, tooManyValueNodes
    case arithmeticOverflow

    public var diagnosticCode: String {
        switch self {
        case .manifestEnvelopeTooLarge: "firebase_fixture_manifest_envelope_too_large"
        case .manifestContentTooLarge: "firebase_fixture_manifest_content_too_large"
        case .componentTooLarge: "firebase_fixture_component_too_large"
        case .aggregatePayloadTooLarge: "firebase_fixture_payloads_too_large"
        case .sourceByteCountTooLarge: "firebase_fixture_source_too_large"
        case .malformedManifest: "firebase_fixture_manifest_malformed"
        case .noncanonicalManifest: "firebase_fixture_manifest_noncanonical"
        case .unsupportedSchemaVersion: "firebase_fixture_schema_unsupported"
        case .unsupportedFixtureVersion: "firebase_fixture_version_unsupported"
        case .unsupportedSanitizationVersion: "firebase_fixture_sanitization_unsupported"
        case .invalidProvenance: "firebase_fixture_provenance_invalid"
        case .invalidAuthorityDisposition: "firebase_fixture_authority_invalid"
        case .invalidLogicalPath: "firebase_fixture_path_invalid"
        case .duplicateLogicalPath: "firebase_fixture_path_duplicate"
        case .logicalPathCaseCollision: "firebase_fixture_path_case_collision"
        case .fileSetMismatch: "firebase_fixture_file_set_mismatch"
        case .fileRoleMismatch: "firebase_fixture_file_role_mismatch"
        case .fileOrderMismatch: "firebase_fixture_file_order_mismatch"
        case .fileByteCountMismatch: "firebase_fixture_file_size_mismatch"
        case .fileDigestMismatch: "firebase_fixture_file_digest_mismatch"
        case .malformedPayload: "firebase_fixture_payload_malformed"
        case .noncanonicalPayload: "firebase_fixture_payload_noncanonical"
        case .resourceKindMismatch: "firebase_fixture_resource_kind_mismatch"
        case .payloadRecordCountMismatch: "firebase_fixture_record_count_mismatch"
        case .duplicateRecordID: "firebase_fixture_record_id_duplicate"
        case .recordIDCaseCollision: "firebase_fixture_record_id_case_collision"
        case .duplicateEntity: "firebase_fixture_entity_duplicate"
        case .entityOrderMismatch: "firebase_fixture_entity_order_mismatch"
        case .entityCountMismatch: "firebase_fixture_entity_count_mismatch"
        case .entityDigestMismatch: "firebase_fixture_entity_digest_mismatch"
        case .bundleDigestMismatch: "firebase_fixture_bundle_digest_mismatch"
        case .reviewedCatalogMismatch: "firebase_fixture_catalog_unreviewed"
        case .invalidCapturedAt: "firebase_fixture_capture_invalid"
        case .invalidAccountScope: "firebase_fixture_account_scope_invalid"
        case .invalidStableCode: "firebase_fixture_stable_code_invalid"
        case .unknownField: "firebase_fixture_field_unknown"
        case .prohibitedField: "firebase_fixture_field_prohibited"
        case .duplicateMapKey: "firebase_fixture_map_key_duplicate"
        case .invalidValueKind: "firebase_fixture_value_kind_invalid"
        case .invalidInteger: "firebase_fixture_integer_invalid"
        case .invalidDoubleBits: "firebase_fixture_double_bits_invalid"
        case .invalidTimestamp: "firebase_fixture_timestamp_invalid"
        case .invalidGeoPoint: "firebase_fixture_geopoint_invalid"
        case .invalidBytes: "firebase_fixture_bytes_invalid"
        case .invalidReference: "firebase_fixture_reference_invalid"
        case .stringTooLarge: "firebase_fixture_string_too_large"
        case .keyTooLarge: "firebase_fixture_key_too_large"
        case .collectionTooLarge: "firebase_fixture_collection_too_large"
        case .nestingTooDeep: "firebase_fixture_nesting_too_deep"
        case .tooManyValueNodes: "firebase_fixture_value_nodes_too_many"
        case .arithmeticOverflow: "firebase_fixture_arithmetic_overflow"
        }
    }
}

public struct FirebaseSourceFixtureFile: Equatable, Sendable {
    public let path: String
    public let bytes: Data
    public init(path: String, bytes: Data) { self.path = path; self.bytes = bytes }
}

public enum FirebaseSourceEvidenceKind: String, Codable, CaseIterable, Sendable {
    case record, malformed, unsupported, ambiguous, orphan
    case crossAccount = "cross_account"
}

public struct FirebaseSourceMapEntry: Codable, Equatable, Sendable {
    public let key: String
    public let value: FirebaseSourceValue
    public init(key: String, value: FirebaseSourceValue) { self.key = key; self.value = value }
}

public indirect enum FirebaseSourceValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case string(String)
    case integer(String)
    case double(bits: String)
    case timestamp(seconds: String, nanoseconds: Int)
    case reference(segments: [String])
    case geoPoint(latitudeBits: String, longitudeBits: String)
    case bytes(base64: String)
    case array([FirebaseSourceValue])
    case map([FirebaseSourceMapEntry])
    case unsupported(sourceKind: String, evidence: FirebaseSourceValue)
    case malformed(failureCode: String, evidence: FirebaseSourceValue)

    public func validated() throws -> Self {
        var nodes = 0
        try validate(depth: 1, nodes: &nodes)
        return self
    }

    fileprivate func validate(depth: Int, nodes: inout Int) throws {
        guard depth <= FirebaseSourceFixtureCatalog.maximumNestingDepth else { throw FirebaseSourceFixtureFailure.nestingTooDeep }
        let increment = nodes.addingReportingOverflow(1)
        guard !increment.overflow else { throw FirebaseSourceFixtureFailure.arithmeticOverflow }
        nodes = increment.partialValue
        guard nodes <= FirebaseSourceFixtureCatalog.maximumValueNodes else { throw FirebaseSourceFixtureFailure.tooManyValueNodes }
        switch self {
        case .null, .bool: break
        case .string(let value):
            guard value.utf8.count <= FirebaseSourceFixtureCatalog.maximumValueBytes else { throw FirebaseSourceFixtureFailure.stringTooLarge }
        case .integer(let value):
            guard Self.isCanonicalInteger(value), Int64(value) != nil else { throw FirebaseSourceFixtureFailure.invalidInteger }
        case .double(let bits):
            guard Self.decodeDouble(bits) != nil else { throw FirebaseSourceFixtureFailure.invalidDoubleBits }
        case .timestamp(let seconds, let nanos):
            guard Self.isCanonicalInteger(seconds), let decoded = Int64(seconds),
                  (-62_135_596_800...253_402_300_799).contains(decoded), (0...999_999_999).contains(nanos) else {
                throw FirebaseSourceFixtureFailure.invalidTimestamp
            }
        case .reference(let segments):
            guard (2...200).contains(segments.count), segments.count.isMultiple(of: 2) else { throw FirebaseSourceFixtureFailure.invalidReference }
            var joined = segments.count - 1
            for segment in segments {
                guard (1...1_500).contains(segment.utf8.count), segment != ".", segment != "..",
                      !segment.contains("/"), !segment.contains("\0") else { throw FirebaseSourceFixtureFailure.invalidReference }
                let sum = joined.addingReportingOverflow(segment.utf8.count)
                guard !sum.overflow else { throw FirebaseSourceFixtureFailure.arithmeticOverflow }
                joined = sum.partialValue
            }
            guard joined <= 6_144 else { throw FirebaseSourceFixtureFailure.invalidReference }
        case .geoPoint(let latitudeBits, let longitudeBits):
            guard let latitude = Self.decodeDouble(latitudeBits), latitude.isFinite,
                  let longitude = Self.decodeDouble(longitudeBits), longitude.isFinite,
                  (-90.0...90.0).contains(latitude), (-180.0...180.0).contains(longitude) else {
                throw FirebaseSourceFixtureFailure.invalidGeoPoint
            }
        case .bytes(let base64):
            guard let decoded = Data(base64Encoded: base64),
                  decoded.count <= FirebaseSourceFixtureCatalog.maximumValueBytes,
                  decoded.base64EncodedString() == base64 else { throw FirebaseSourceFixtureFailure.invalidBytes }
        case .array(let values):
            guard values.count <= FirebaseSourceFixtureCatalog.maximumCollectionEntries else { throw FirebaseSourceFixtureFailure.collectionTooLarge }
            for value in values { try value.validate(depth: depth + 1, nodes: &nodes) }
        case .map(let entries):
            guard entries.count <= FirebaseSourceFixtureCatalog.maximumCollectionEntries else { throw FirebaseSourceFixtureFailure.collectionTooLarge }
            var previous: Data?
            var keys: Set<Data> = []
            for entry in entries {
                guard !entry.key.isEmpty, entry.key.utf8.count <= FirebaseSourceFixtureCatalog.maximumMapKeyBytes else { throw FirebaseSourceFixtureFailure.keyTooLarge }
                let rawKey = Data(entry.key.utf8)
                guard keys.insert(rawKey).inserted else { throw FirebaseSourceFixtureFailure.duplicateMapKey }
                if let previous, !previous.lexicographicallyPrecedes(rawKey) { throw FirebaseSourceFixtureFailure.noncanonicalPayload }
                previous = rawKey
                try entry.value.validate(depth: depth + 1, nodes: &nodes)
            }
        case .unsupported(let code, let evidence), .malformed(let code, let evidence):
            guard Self.isStableCode(code) else { throw FirebaseSourceFixtureFailure.invalidStableCode }
            try evidence.validate(depth: depth + 1, nodes: &nodes)
        }
    }

    fileprivate static func rawUTF8Less(_ lhs: String, _ rhs: String) -> Bool { lhs.utf8.lexicographicallyPrecedes(rhs.utf8) }
    fileprivate static func isStableCode(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 64, let first = value.unicodeScalars.first, (97...122).contains(first.value) else { return false }
        return value.unicodeScalars.allSatisfy { (97...122).contains($0.value) || (48...57).contains($0.value) || $0.value == 95 }
    }
    private static func isCanonicalInteger(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        if value == "0" { return true }
        let scalars = value.unicodeScalars
        if scalars.first?.value == 45 {
            guard scalars.count > 1, scalars.dropFirst().first?.value != 48 else { return false }
            return scalars.dropFirst().allSatisfy { (48...57).contains($0.value) }
        }
        guard scalars.first?.value != 48 else { return false }
        return scalars.allSatisfy { (48...57).contains($0.value) }
    }
    private static func decodeDouble(_ value: String) -> Double? {
        guard value.utf8.count == 16,
              value.unicodeScalars.allSatisfy({ (48...57).contains($0.value) || (97...102).contains($0.value) }),
              let bits = UInt64(value, radix: 16) else { return nil }
        return Double(bitPattern: bits)
    }

    fileprivate func rejectMapKeys(_ prohibited: Set<String>) throws {
        switch self {
        case .array(let values):
            for value in values { try value.rejectMapKeys(prohibited) }
        case .map(let entries):
            for entry in entries {
                if prohibited.contains(entry.key.lowercased()) { throw FirebaseSourceFixtureFailure.prohibitedField }
                try entry.value.rejectMapKeys(prohibited)
            }
        case .unsupported(_, let evidence), .malformed(_, let evidence):
            try evidence.rejectMapKeys(prohibited)
        default: break
        }
    }
}

extension FirebaseSourceValue: Codable {
    private enum Keys: String, CodingKey, CaseIterable {
        case kind, value, bits, seconds, nanoseconds, segments, latitudeBits, longitudeBits
        case base64, values, entries, sourceKind, evidence, failureCode
    }
    private enum Kind: String { case null, bool, string, integer, double, timestamp, reference, geopoint, bytes, array, map, unsupported, malformed }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: AnyFixtureCodingKey.self)
        let known = Set(Keys.allCases.map(\.rawValue))
        guard Set(raw.allKeys.map(\.stringValue)).isSubset(of: known) else {
            throw FirebaseSourceFixtureFailure.unknownField
        }
        let c = try decoder.container(keyedBy: Keys.self)
        guard let kind = try Kind(rawValue: c.decode(String.self, forKey: .kind)) else { throw FirebaseSourceFixtureFailure.invalidValueKind }
        let allowed: Set<Keys>
        switch kind {
        case .null: allowed = [.kind]; self = .null
        case .bool: allowed = [.kind, .value]; self = .bool(try c.decode(Bool.self, forKey: .value))
        case .string: allowed = [.kind, .value]; self = .string(try c.decode(String.self, forKey: .value))
        case .integer: allowed = [.kind, .value]; self = .integer(try c.decode(String.self, forKey: .value))
        case .double: allowed = [.kind, .bits]; self = .double(bits: try c.decode(String.self, forKey: .bits))
        case .timestamp: allowed = [.kind, .seconds, .nanoseconds]; self = .timestamp(seconds: try c.decode(String.self, forKey: .seconds), nanoseconds: try c.decode(Int.self, forKey: .nanoseconds))
        case .reference: allowed = [.kind, .segments]; self = .reference(segments: try c.decode([String].self, forKey: .segments))
        case .geopoint: allowed = [.kind, .latitudeBits, .longitudeBits]; self = .geoPoint(latitudeBits: try c.decode(String.self, forKey: .latitudeBits), longitudeBits: try c.decode(String.self, forKey: .longitudeBits))
        case .bytes: allowed = [.kind, .base64]; self = .bytes(base64: try c.decode(String.self, forKey: .base64))
        case .array: allowed = [.kind, .values]; self = .array(try c.decode([FirebaseSourceValue].self, forKey: .values))
        case .map: allowed = [.kind, .entries]; self = .map(try c.decode([FirebaseSourceMapEntry].self, forKey: .entries))
        case .unsupported: allowed = [.kind, .sourceKind, .evidence]; self = .unsupported(sourceKind: try c.decode(String.self, forKey: .sourceKind), evidence: try c.decode(FirebaseSourceValue.self, forKey: .evidence))
        case .malformed: allowed = [.kind, .failureCode, .evidence]; self = .malformed(failureCode: try c.decode(String.self, forKey: .failureCode), evidence: try c.decode(FirebaseSourceValue.self, forKey: .evidence))
        }
        guard Set(c.allKeys) == allowed else { throw FirebaseSourceFixtureFailure.unknownField }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .null: try c.encode(Kind.null.rawValue, forKey: .kind)
        case .bool(let value): try c.encode(Kind.bool.rawValue, forKey: .kind); try c.encode(value, forKey: .value)
        case .string(let value): try c.encode(Kind.string.rawValue, forKey: .kind); try c.encode(value, forKey: .value)
        case .integer(let value): try c.encode(Kind.integer.rawValue, forKey: .kind); try c.encode(value, forKey: .value)
        case .double(let bits): try c.encode(Kind.double.rawValue, forKey: .kind); try c.encode(bits, forKey: .bits)
        case .timestamp(let seconds, let nanos): try c.encode(Kind.timestamp.rawValue, forKey: .kind); try c.encode(seconds, forKey: .seconds); try c.encode(nanos, forKey: .nanoseconds)
        case .reference(let segments): try c.encode(Kind.reference.rawValue, forKey: .kind); try c.encode(segments, forKey: .segments)
        case .geoPoint(let latitude, let longitude): try c.encode(Kind.geopoint.rawValue, forKey: .kind); try c.encode(latitude, forKey: .latitudeBits); try c.encode(longitude, forKey: .longitudeBits)
        case .bytes(let base64): try c.encode(Kind.bytes.rawValue, forKey: .kind); try c.encode(base64, forKey: .base64)
        case .array(let values): try c.encode(Kind.array.rawValue, forKey: .kind); try c.encode(values, forKey: .values)
        case .map(let entries): try c.encode(Kind.map.rawValue, forKey: .kind); try c.encode(entries, forKey: .entries)
        case .unsupported(let code, let evidence): try c.encode(Kind.unsupported.rawValue, forKey: .kind); try c.encode(code, forKey: .sourceKind); try c.encode(evidence, forKey: .evidence)
        case .malformed(let code, let evidence): try c.encode(Kind.malformed.rawValue, forKey: .kind); try c.encode(code, forKey: .failureCode); try c.encode(evidence, forKey: .evidence)
        }
    }
}

public struct ValidatedFirebaseSourceFixture: Equatable, Sendable {
    public let sourceSnapshot: MigrationSourceSnapshot
    public let entityPlans: [MigrationEntityPlan]
    public let fixtureVersion: MigrationVersion
    public let sanitizationVersion: MigrationVersion
    package let accountScopeID: MigrationOpaqueID
    public let authorityDisposition: MigrationAuthorityDisposition
    public let privacyReviewEvidenceID: MigrationStableCode
}

public struct FirebaseSourceFixtureCatalog: Sendable {
    public static let schemaVersion = 1
    public static let maximumManifestEnvelopeBytes = 263_168
    public static let maximumManifestContentBytes = 262_144
    public static let maximumComponentBytes = 4_194_304
    public static let maximumAggregatePayloadBytes = 12_582_912
    public static let maximumSourceBytes = 12_845_056
    public static let maximumValueBytes = 1_048_487
    public static let maximumMapKeyBytes = 1_500
    public static let maximumCollectionEntries = 10_000
    public static let maximumNestingDepth = 20
    public static let maximumValueNodes = 50_000
    public static let payloadPaths = ["auth/identity-metadata.json", "firestore/documents.json", "storage/object-metadata.json"]

    private static let reviewedBundleSHA256 = "1ecd6b1ed0bfbe4b9e65d0c55e367562d761cbe00fd0f38cdb86111fd2b7f4a2"
    private static let reviewedPayloadSHA256 = [
        "auth/identity-metadata.json": "060cc947968cc135a533822ae071e17ca5f232fcf99e4a0d867ae42e53d73f74",
        "firestore/documents.json": "16f78cef5e69e720db2db9e70ec34c8ec02fe5f8e736d1139f3c08703e834d70",
        "storage/object-metadata.json": "9d10c8143c923cce031a318700a4787bd0624794633b5b85aeddbd35aaa06f3d"
    ]

    public init() {}

    package enum PayloadRole: String, CaseIterable, Sendable {
        case auth = "auth_identity_metadata"
        case firestore = "firestore_documents"
        case storage = "storage_object_metadata"
    }

    package static func validateEntryCount(_ count: Int, role: PayloadRole) throws {
        _ = role
        guard count >= 0, count <= maximumCollectionEntries else {
            throw FirebaseSourceFixtureFailure.collectionTooLarge
        }
    }

    package static func validateManifestEnvelopeSize(_ count: Int) throws {
        guard count >= 0, count <= maximumManifestEnvelopeBytes else {
            throw FirebaseSourceFixtureFailure.manifestEnvelopeTooLarge
        }
    }

    package static func validateManifestContentSize(_ count: Int) throws {
        guard count >= 0, count <= maximumManifestContentBytes else {
            throw FirebaseSourceFixtureFailure.manifestContentTooLarge
        }
    }

    package static func validateComponentSizes(_ counts: [Int]) throws {
        var aggregate = 0
        for count in counts {
            guard count >= 0, count <= maximumComponentBytes else {
                throw FirebaseSourceFixtureFailure.componentTooLarge
            }
            aggregate = try sum(aggregate, count)
        }
        guard aggregate <= maximumAggregatePayloadBytes else {
            throw FirebaseSourceFixtureFailure.aggregatePayloadTooLarge
        }
    }

    package static func validateSourceByteCount(_ count: Int) throws {
        guard count >= 0, count <= maximumSourceBytes else {
            throw FirebaseSourceFixtureFailure.sourceByteCountTooLarge
        }
    }

    package static func validateRawRecordIDs(_ ids: [String]) throws {
        var exact: Set<Data> = []
        var folded: Set<Data> = []
        for id in ids {
            guard validRecordID(id) else { throw FirebaseSourceFixtureFailure.invalidStableCode }
            let raw = Data(id.utf8)
            guard exact.insert(raw).inserted else { throw FirebaseSourceFixtureFailure.duplicateRecordID }
            let caseFolded = Data(id.lowercased().utf8)
            guard folded.insert(caseFolded).inserted else { throw FirebaseSourceFixtureFailure.recordIDCaseCollision }
        }
    }

    package static func validateReviewedComponent(path: String, bytes: Data) throws -> String {
        guard let reviewed = reviewedPayloadSHA256[path] else {
            throw FirebaseSourceFixtureFailure.fileSetMismatch
        }
        let digest = sha256(bytes)
        guard digest == reviewed else { throw FirebaseSourceFixtureFailure.reviewedCatalogMismatch }
        return digest
    }

    public func validate(manifestEnvelope: Data, files: [FirebaseSourceFixtureFile]) throws -> ValidatedFirebaseSourceFixture {
        try Self.validateManifestEnvelopeSize(manifestEnvelope.count)
        let envelope: ManifestEnvelope
        do { envelope = try Self.decode(ManifestEnvelope.self, manifestEnvelope) }
        catch let failure as FirebaseSourceFixtureFailure { throw failure }
        catch { throw FirebaseSourceFixtureFailure.malformedManifest }
        let canonicalEnvelope = try Self.encode(envelope)
        guard manifestEnvelope == canonicalEnvelope + Data([0x0a]) else {
            throw FirebaseSourceFixtureFailure.noncanonicalManifest
        }
        try validateHeader(envelope.content)
        let contentBytes = try Self.encode(envelope.content)
        try Self.validateManifestContentSize(contentBytes.count)

        let files = try normalize(files)
        guard files.map(\.path) == Self.payloadPaths else { throw FirebaseSourceFixtureFailure.fileSetMismatch }
        try Self.validateComponentSizes(files.map { $0.bytes.count })
        var payloadByteCount = 0
        for file in files { payloadByteCount = try Self.sum(payloadByteCount, file.bytes.count) }
        let sourceByteCount = try Self.sum(contentBytes.count, payloadByteCount)
        try Self.validateSourceByteCount(sourceByteCount)
        guard envelope.content.files.map(\.path) == Self.payloadPaths else { throw FirebaseSourceFixtureFailure.fileOrderMismatch }

        var records: [EntityRecord] = []
        for (descriptor, file) in zip(envelope.content.files, files) {
            guard descriptor.path == file.path else { throw FirebaseSourceFixtureFailure.fileSetMismatch }
            guard descriptor.byteCount == file.bytes.count else { throw FirebaseSourceFixtureFailure.fileByteCountMismatch }
            let digest = Self.sha256(file.bytes)
            guard descriptor.sha256 == digest else { throw FirebaseSourceFixtureFailure.fileDigestMismatch }
            guard try Self.validateReviewedComponent(path: file.path, bytes: file.bytes) == digest else {
                throw FirebaseSourceFixtureFailure.reviewedCatalogMismatch
            }
            try Self.validateNoProhibitedFields(path: file.path, bytes: file.bytes)
            let payload = try decodePayload(file, manifestAccountScopeID: envelope.content.accountScopeID)
            guard descriptor.role == payload.role else { throw FirebaseSourceFixtureFailure.fileRoleMismatch }
            guard descriptor.recordCount == payload.records.count else { throw FirebaseSourceFixtureFailure.payloadRecordCountMismatch }
            records += payload.records
        }

        let entities = try entityIdentities(records)
        try compare(entities, envelope.content.entities)
        let bundleDigest = Self.sha256(try Self.bundlePreimage(contentBytes, files))
        guard envelope.bundleSHA256 == bundleDigest else { throw FirebaseSourceFixtureFailure.bundleDigestMismatch }
        guard bundleDigest == Self.reviewedBundleSHA256 else { throw FirebaseSourceFixtureFailure.reviewedCatalogMismatch }
        guard envelope.content.privacyReview.reviewedPayloadSHA256 == Self.payloadPaths.map({ Self.reviewedPayloadSHA256[$0]! }) else {
            throw FirebaseSourceFixtureFailure.reviewedCatalogMismatch
        }

        let snapshot = try MigrationSourceSnapshot(
            environment: .sourceFixture,
            exportID: MigrationOpaqueID(validating: String(bundleDigest.prefix(32)), field: "fixture_export"),
            capturedAtEpochMilliseconds: envelope.content.capturedAtEpochMilliseconds,
            byteCount: Int64(sourceByteCount),
            sha256: MigrationSHA256(validating: bundleDigest, field: "fixture_bundle")
        )
        let plans = try entities.map {
            try MigrationEntityPlan(
                entity: MigrationStableCode(validating: $0.entityCode, field: "fixture_entity"),
                plannedCount: Int64($0.count),
                sourceSHA256: MigrationSHA256(validating: $0.sha256, field: "fixture_entity"),
                transformVersion: MigrationVersion(validating: envelope.content.fixtureVersion, field: "fixture_transform")
            )
        }
        return ValidatedFirebaseSourceFixture(
            sourceSnapshot: snapshot,
            entityPlans: plans,
            fixtureVersion: try MigrationVersion(validating: envelope.content.fixtureVersion, field: "fixture"),
            sanitizationVersion: try MigrationVersion(validating: envelope.content.sanitizationVersion, field: "sanitization"),
            accountScopeID: try MigrationOpaqueID(validating: envelope.content.accountScopeID, field: "fixture_account"),
            authorityDisposition: .evidenceOnly,
            privacyReviewEvidenceID: try MigrationStableCode(validating: envelope.content.privacyReview.evidenceID, field: "privacy_review")
        )
    }

    public static func canonicalData(for value: FirebaseSourceValue) throws -> Data { _ = try value.validated(); return try encode(value) }
    public static func decodeValue(_ bytes: Data) throws -> FirebaseSourceValue {
        let value: FirebaseSourceValue
        do { value = try decode(FirebaseSourceValue.self, bytes) }
        catch let failure as FirebaseSourceFixtureFailure { throw failure }
        catch { throw FirebaseSourceFixtureFailure.malformedPayload }
        _ = try value.validated()
        guard try encode(value) == bytes else { throw FirebaseSourceFixtureFailure.noncanonicalPayload }
        return value
    }

    private func validateHeader(_ content: ManifestContent) throws {
        guard content.schemaVersion == 1 else { throw FirebaseSourceFixtureFailure.unsupportedSchemaVersion }
        guard content.fixtureVersion == "firebase-source-v1" else { throw FirebaseSourceFixtureFailure.unsupportedFixtureVersion }
        guard content.sanitizationVersion == "synthetic-v1" else { throw FirebaseSourceFixtureFailure.unsupportedSanitizationVersion }
        guard content.provenance == "synthetic_only" else { throw FirebaseSourceFixtureFailure.invalidProvenance }
        guard content.authorityDisposition == "evidence_only" else { throw FirebaseSourceFixtureFailure.invalidAuthorityDisposition }
        guard content.capturedAtEpochMilliseconds > 0 else { throw FirebaseSourceFixtureFailure.invalidCapturedAt }
        guard Self.lowerHex(content.accountScopeID, 32) else { throw FirebaseSourceFixtureFailure.invalidAccountScope }
        guard FirebaseSourceValue.isStableCode(content.privacyReview.evidenceID),
              content.privacyReview.reviewKind == "independent_agent_synthetic_review",
              content.privacyReview.reviewed else { throw FirebaseSourceFixtureFailure.invalidStableCode }
        guard content.coverageLimits == ["curated_shapes_not_production_complete", "metadata_only_no_media_bytes", "no_target_transform_or_reconciliation_claim"] else { throw FirebaseSourceFixtureFailure.reviewedCatalogMismatch }
    }

    private func normalize(_ files: [FirebaseSourceFixtureFile]) throws -> [FirebaseSourceFixtureFile] {
        var exact: Set<Data> = [], folded: Set<Data> = []
        for file in files {
            guard Self.validPath(file.path) else { throw FirebaseSourceFixtureFailure.invalidLogicalPath }
            guard exact.insert(Data(file.path.utf8)).inserted else { throw FirebaseSourceFixtureFailure.duplicateLogicalPath }
            guard folded.insert(Data(file.path.lowercased().utf8)).inserted else { throw FirebaseSourceFixtureFailure.logicalPathCaseCollision }
        }
        return files.sorted { Self.less($0.path, $1.path) }
    }

    private func decodePayload(_ file: FirebaseSourceFixtureFile, manifestAccountScopeID: String) throws -> DecodedPayload {
        do {
            switch file.path {
            case "auth/identity-metadata.json":
                let p = try Self.decodeCanonical(AuthPayload.self, file.bytes)
                guard p.schemaVersion == 1, p.resourceKind == "auth_identity_metadata", p.authorityDisposition == "evidence_only" else { throw FirebaseSourceFixtureFailure.resourceKindMismatch }
                try Self.validateEntryCount(p.entries.count, role: .auth)
                var nodes = 0
                return try DecodedPayload(role: "auth_identity_metadata", records: p.entries.map { try $0.entityRecord(manifestAccountScopeID: manifestAccountScopeID, nodes: &nodes) })
            case "firestore/documents.json":
                let p = try Self.decodeCanonical(FirestorePayload.self, file.bytes)
                guard p.schemaVersion == 1, p.resourceKind == "firestore_documents", p.authorityDisposition == "evidence_only" else { throw FirebaseSourceFixtureFailure.resourceKindMismatch }
                try Self.validateEntryCount(p.entries.count, role: .firestore)
                var nodes = 0
                return try DecodedPayload(role: "firestore_documents", records: p.entries.map { try $0.entityRecord(manifestAccountScopeID: manifestAccountScopeID, nodes: &nodes) })
            case "storage/object-metadata.json":
                let p = try Self.decodeCanonical(StoragePayload.self, file.bytes)
                guard p.schemaVersion == 1, p.resourceKind == "storage_object_metadata", p.authorityDisposition == "evidence_only" else { throw FirebaseSourceFixtureFailure.resourceKindMismatch }
                try Self.validateEntryCount(p.entries.count, role: .storage)
                var nodes = 0
                return try DecodedPayload(role: "storage_object_metadata", records: p.entries.map { try $0.entityRecord(manifestAccountScopeID: manifestAccountScopeID, nodes: &nodes) })
            default: throw FirebaseSourceFixtureFailure.invalidLogicalPath
            }
        } catch let failure as FirebaseSourceFixtureFailure { throw failure }
        catch { throw FirebaseSourceFixtureFailure.malformedPayload }
    }

    private func entityIdentities(_ records: [EntityRecord]) throws -> [ManifestEntity] {
        try Self.validateRawRecordIDs(records.map(\.sourceRecordID))
        guard records.allSatisfy({ FirebaseSourceValue.isStableCode($0.entityCode) }) else {
            throw FirebaseSourceFixtureFailure.invalidStableCode
        }
        let grouped = Dictionary(grouping: records, by: \.entityCode)
        return try grouped.keys.sorted(by: Self.less).map { code in
            let records = grouped[code]!.sorted { Self.less($0.sourceRecordID, $1.sourceRecordID) }
            var preimage = Data("ledger.firebase-source-fixture.entity.v1\0".utf8)
            try Self.append32(code.utf8.count, &preimage); preimage.append(contentsOf: code.utf8)
            for record in records {
                try Self.append32(record.sourceRecordID.utf8.count, &preimage); preimage.append(contentsOf: record.sourceRecordID.utf8)
                try Self.append64(record.canonicalRecord.count, &preimage); preimage.append(record.canonicalRecord)
            }
            return ManifestEntity(count: records.count, entityCode: code, sha256: Self.sha256(preimage))
        }
    }

    private func compare(_ actual: [ManifestEntity], _ declared: [ManifestEntity]) throws {
        let codes = declared.map(\.entityCode)
        guard codes == codes.sorted(by: Self.less) else { throw FirebaseSourceFixtureFailure.entityOrderMismatch }
        guard Set(codes).count == codes.count else { throw FirebaseSourceFixtureFailure.duplicateEntity }
        guard actual.map(\.entityCode) == codes else { throw FirebaseSourceFixtureFailure.entityCountMismatch }
        for (a, d) in zip(actual, declared) {
            guard a.count == d.count else { throw FirebaseSourceFixtureFailure.entityCountMismatch }
            guard a.sha256 == d.sha256 else { throw FirebaseSourceFixtureFailure.entityDigestMismatch }
        }
    }

    private static func bundlePreimage(_ content: Data, _ files: [FirebaseSourceFixtureFile]) throws -> Data {
        var result = Data("ledger.firebase-source-fixture.v1\0".utf8)
        try append64(content.count, &result); result.append(content)
        for file in files {
            try append32(file.path.utf8.count, &result); result.append(contentsOf: file.path.utf8)
            try append64(file.bytes.count, &result); result.append(file.bytes)
        }
        return result
    }
    private static func append32(_ value: Int, _ data: inout Data) throws {
        guard let value = UInt32(exactly: value) else { throw FirebaseSourceFixtureFailure.arithmeticOverflow }
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }
    private static func append64(_ value: Int, _ data: inout Data) throws {
        guard let value = UInt64(exactly: value) else { throw FirebaseSourceFixtureFailure.arithmeticOverflow }
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }
    private static func sum(_ lhs: Int, _ rhs: Int) throws -> Int {
        // Supported Data/Array instances cannot practically approach Int.max;
        // this checked addition is defense in depth, not claimed overflow evidence.
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else { throw FirebaseSourceFixtureFailure.arithmeticOverflow }
        return result.partialValue
    }
    private static func decodeCanonical<T: Codable>(_ type: T.Type, _ data: Data) throws -> T {
        let value = try decode(type, data)
        let canonical = try encode(value)
        guard data == canonical + Data([0x0a]) else { throw FirebaseSourceFixtureFailure.noncanonicalPayload }
        return value
    }
    fileprivate static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return try encoder.encode(value)
    }
    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T { try JSONDecoder().decode(type, from: data) }
    private static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func less(_ lhs: String, _ rhs: String) -> Bool { lhs.utf8.lexicographicallyPrecedes(rhs.utf8) }
    private static func lowerHex(_ value: String, _ count: Int) -> Bool {
        value.utf8.count == count && value.unicodeScalars.allSatisfy { (48...57).contains($0.value) || (97...102).contains($0.value) }
    }
    private static func validPath(_ path: String) -> Bool {
        guard !path.isEmpty, path.utf8.count <= 6_144, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else { return false }
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        return segments.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    private static func validRecordID(_ id: String) -> Bool { !id.isEmpty && id.utf8.count <= 1_500 && !id.contains("\0") }

    package static func validateNoProhibitedFields(path: String, bytes: Data) throws {
        let prohibited: Set<String>
        switch path {
        case "auth/identity-metadata.json":
            prohibited = ["email", "phone", "phonenumber", "passwordhash", "passwordsalt", "providertoken", "accesstoken", "refreshtoken", "credential", "claims", "customclaims"]
        case "storage/object-metadata.json":
            prohibited = ["bucket", "objectname", "url", "downloadurl", "downloadtoken", "token", "mediabytes", "userdata"]
        case "firestore/documents.json":
            prohibited = ["credential", "accesstoken", "refreshtoken", "passwordhash", "mediabytes", "productionidentifier"]
        default: throw FirebaseSourceFixtureFailure.invalidLogicalPath
        }
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: bytes) }
        catch { throw FirebaseSourceFixtureFailure.malformedPayload }
        func inspect(_ value: Any) throws {
            if let dictionary = value as? [String: Any] {
                for (key, child) in dictionary {
                    if prohibited.contains(key.lowercased()) { throw FirebaseSourceFixtureFailure.prohibitedField }
                    try inspect(child)
                }
            } else if let array = value as? [Any] {
                for child in array { try inspect(child) }
            }
        }
        try inspect(object)
    }
}

private struct ManifestEnvelope: Codable, Equatable {
    let bundleSHA256: String; let content: ManifestContent
    enum CodingKeys: String, CodingKey, CaseIterable { case bundleSHA256, content }
    init(from decoder: Decoder) throws { let c = try decoder.strict(CodingKeys.self); bundleSHA256 = try c.decode(String.self, forKey: .bundleSHA256); content = try c.decode(ManifestContent.self, forKey: .content) }
}
private struct ManifestContent: Codable, Equatable {
    let accountScopeID: String; let authorityDisposition: String; let capturedAtEpochMilliseconds: Int64
    let coverageLimits: [String]; let entities: [ManifestEntity]; let files: [ManifestFile]
    let fixtureVersion: String; let privacyReview: PrivacyReview; let provenance: String
    let sanitizationVersion: String; let schemaVersion: Int
    enum CodingKeys: String, CodingKey, CaseIterable { case accountScopeID, authorityDisposition, capturedAtEpochMilliseconds, coverageLimits, entities, files, fixtureVersion, privacyReview, provenance, sanitizationVersion, schemaVersion }
    init(from decoder: Decoder) throws {
        let c = try decoder.strict(CodingKeys.self)
        accountScopeID = try c.decode(String.self, forKey: .accountScopeID); authorityDisposition = try c.decode(String.self, forKey: .authorityDisposition)
        capturedAtEpochMilliseconds = try c.decode(Int64.self, forKey: .capturedAtEpochMilliseconds); coverageLimits = try c.decode([String].self, forKey: .coverageLimits)
        entities = try c.decode([ManifestEntity].self, forKey: .entities); files = try c.decode([ManifestFile].self, forKey: .files)
        fixtureVersion = try c.decode(String.self, forKey: .fixtureVersion); privacyReview = try c.decode(PrivacyReview.self, forKey: .privacyReview)
        provenance = try c.decode(String.self, forKey: .provenance); sanitizationVersion = try c.decode(String.self, forKey: .sanitizationVersion)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
    }
}
private struct ManifestFile: Codable, Equatable { let byteCount: Int; let path: String; let recordCount: Int; let role: String; let sha256: String }
private struct ManifestEntity: Codable, Equatable { let count: Int; let entityCode: String; let sha256: String }
private struct PrivacyReview: Codable, Equatable {
    let evidenceID: String
    let reviewKind: String
    let reviewed: Bool
    let reviewedPayloadSHA256: [String]
}
private struct DecodedPayload { let role: String; let records: [EntityRecord] }
private struct EntityRecord { let sourceRecordID: String; let entityCode: String; let canonicalRecord: Data }

private protocol FixtureRecord: Codable {
    var accountScopeID: String { get }; var entityCode: String { get }; var evidenceKind: FirebaseSourceEvidenceKind { get }; var sourceRecordID: String { get }
    func validateValue(nodes: inout Int) throws
}
private extension FixtureRecord {
    func entityRecord(manifestAccountScopeID: String, nodes: inout Int) throws -> EntityRecord {
        let isOpaque = accountScopeID.utf8.count == 32 && accountScopeID.unicodeScalars.allSatisfy { (48...57).contains($0.value) || (97...102).contains($0.value) }
        guard isOpaque, evidenceKind == .crossAccount || accountScopeID == manifestAccountScopeID else {
            throw FirebaseSourceFixtureFailure.invalidAccountScope
        }
        try validateValue(nodes: &nodes)
        return EntityRecord(sourceRecordID: sourceRecordID, entityCode: entityCode, canonicalRecord: try FirebaseSourceFixtureCatalog.encode(self))
    }
}

private struct FirestorePayload: Codable { let authorityDisposition: String; let entries: [FirestoreRecord]; let resourceKind: String; let schemaVersion: Int }
private struct FirestoreRecord: FixtureRecord {
    let accountScopeID: String; let documentPathSegments: [String]; let entityCode: String; let evidenceKind: FirebaseSourceEvidenceKind; let fields: FirebaseSourceValue; let sourceRecordID: String
    func validateValue(nodes: inout Int) throws {
        _ = try FirebaseSourceValue.reference(segments: documentPathSegments).validated()
        guard case .map = fields else { throw FirebaseSourceFixtureFailure.invalidValueKind }
        try fields.validate(depth: 1, nodes: &nodes)
        try fields.rejectMapKeys(["credential", "accesstoken", "refreshtoken", "passwordhash", "mediabytes", "productionidentifier"])
    }
}
private struct AuthPayload: Codable { let authorityDisposition: String; let entries: [AuthRecord]; let resourceKind: String; let schemaVersion: Int }
private struct AuthRecord: FixtureRecord {
    let accountScopeID: String; let entityCode: String; let evidenceKind: FirebaseSourceEvidenceKind; let identityClass: String; let metadata: FirebaseSourceValue; let sourceRecordID: String
    func validateValue(nodes: inout Int) throws {
        guard FirebaseSourceValue.isStableCode(identityClass), case .map = metadata else { throw FirebaseSourceFixtureFailure.prohibitedField }
        try metadata.validate(depth: 1, nodes: &nodes)
        try metadata.rejectMapKeys(["email", "phone", "phonenumber", "passwordhash", "passwordsalt", "providertoken", "accesstoken", "refreshtoken", "credential", "claims", "customclaims"])
    }
}
private struct StoragePayload: Codable { let authorityDisposition: String; let entries: [StorageRecord]; let resourceKind: String; let schemaVersion: Int }
private struct StorageRecord: FixtureRecord {
    let accountScopeID: String; let attachmentReferenceID: String; let entityCode: String; let evidenceKind: FirebaseSourceEvidenceKind
    let isThumbnail: Bool; let metadata: FirebaseSourceValue; let namespaceClass: String; let objectState: String
    let placeholderContentSHA256: String?; let sourceRecordID: String
    enum CodingKeys: String, CodingKey {
        case accountScopeID, attachmentReferenceID, entityCode, evidenceKind, isThumbnail, metadata
        case namespaceClass, objectState, placeholderContentSHA256, sourceRecordID
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(accountScopeID, forKey: .accountScopeID); try c.encode(attachmentReferenceID, forKey: .attachmentReferenceID)
        try c.encode(entityCode, forKey: .entityCode); try c.encode(evidenceKind, forKey: .evidenceKind)
        try c.encode(isThumbnail, forKey: .isThumbnail); try c.encode(metadata, forKey: .metadata)
        try c.encode(namespaceClass, forKey: .namespaceClass); try c.encode(objectState, forKey: .objectState)
        try c.encode(placeholderContentSHA256, forKey: .placeholderContentSHA256); try c.encode(sourceRecordID, forKey: .sourceRecordID)
    }
    func validateValue(nodes: inout Int) throws {
        guard FirebaseSourceValue.isStableCode(attachmentReferenceID), FirebaseSourceValue.isStableCode(namespaceClass),
              FirebaseSourceValue.isStableCode(objectState), case .map = metadata else { throw FirebaseSourceFixtureFailure.prohibitedField }
        if let digest = placeholderContentSHA256,
           !(digest.utf8.count == 64 && digest.unicodeScalars.allSatisfy({ (48...57).contains($0.value) || (97...102).contains($0.value) })) {
            throw FirebaseSourceFixtureFailure.prohibitedField
        }
        try metadata.validate(depth: 1, nodes: &nodes)
        try metadata.rejectMapKeys(["bucket", "objectname", "url", "downloadurl", "downloadtoken", "token", "mediabytes", "userdata"])
    }
}

private extension Decoder {
    func strict<K: CodingKey & CaseIterable>(_ type: K.Type) throws -> KeyedDecodingContainer<K> where K.AllCases: Collection {
        let raw = try self.container(keyedBy: AnyFixtureCodingKey.self)
        let container = try self.container(keyedBy: K.self)
        let allowed = Set(K.allCases.map(\.stringValue))
        guard Set(raw.allKeys.map(\.stringValue)) == allowed else { throw FirebaseSourceFixtureFailure.unknownField }
        return container
    }
}

private struct AnyFixtureCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
    init?(intValue: Int) { self.intValue = intValue; stringValue = String(intValue) }
}
