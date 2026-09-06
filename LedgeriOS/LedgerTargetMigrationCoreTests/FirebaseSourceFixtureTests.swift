import CryptoKit
import CoreFoundation
import Foundation
import Testing
@testable import LedgerTargetMigrationCore

@Suite("Firebase Source Fixture Catalog")
struct FirebaseSourceFixtureTests {
    @Test("FBSOURCEFIXTURE-TEST-001 closed tagged values preserve Firebase boundaries")
    func taggedValueBoundaries() throws {
        for integer in ["0", String(Int64.min), String(Int64.max)] {
            #expect(try FirebaseSourceValue.integer(integer).validated() == .integer(integer))
        }
        for integer in ["+1", "01", "-0", " 1", "9223372036854775808", "-9223372036854775809"] {
            #expect(Self.failure { try FirebaseSourceValue.integer(integer).validated() } == .invalidInteger)
        }

        for bits in [
            "0000000000000000", "8000000000000000", "3ff0000000000000",
            "7ff0000000000000", "fff0000000000000", "7ff8000000000001"
        ] {
            #expect(try FirebaseSourceValue.double(bits: bits).validated() == .double(bits: bits))
        }
        #expect(Self.failure { try FirebaseSourceValue.double(bits: "7FF8000000000001").validated() } == .invalidDoubleBits)
        #expect(Self.failure { try FirebaseSourceValue.double(bits: "0000").validated() } == .invalidDoubleBits)

        _ = try FirebaseSourceValue.timestamp(seconds: "-62135596800", nanoseconds: 0).validated()
        _ = try FirebaseSourceValue.timestamp(seconds: "253402300799", nanoseconds: 999_999_999).validated()
        for (seconds, nanos) in [("253402300800", 0), ("-62135596801", 0), ("01", 0), ("-0", 0), ("+1", 0), ("0", -1), ("0", 1_000_000_000)] {
            #expect(Self.failure { try FirebaseSourceValue.timestamp(seconds: seconds, nanoseconds: nanos).validated() } == .invalidTimestamp)
        }

        _ = try FirebaseSourceValue.geoPoint(latitudeBits: "4056800000000000", longitudeBits: "4066800000000000").validated()
        _ = try FirebaseSourceValue.geoPoint(latitudeBits: "c056800000000000", longitudeBits: "c066800000000000").validated()
        #expect(Self.failure { try FirebaseSourceValue.geoPoint(latitudeBits: "7ff0000000000000", longitudeBits: "0000000000000000").validated() } == .invalidGeoPoint)
        #expect(Self.failure { try FirebaseSourceValue.geoPoint(latitudeBits: "4056c00000000000", longitudeBits: "0000000000000000").validated() } == .invalidGeoPoint)
        #expect(Self.failure { try FirebaseSourceValue.geoPoint(latitudeBits: "0000000000000000", longitudeBits: "4066900000000000").validated() } == .invalidGeoPoint)
        #expect(Self.failure { try FirebaseSourceValue.geoPoint(latitudeBits: "7ff8000000000001", longitudeBits: "0000000000000000").validated() } == .invalidGeoPoint)

        let maximumBytes = Data(repeating: 0xab, count: FirebaseSourceFixtureCatalog.maximumValueBytes)
        _ = try FirebaseSourceValue.bytes(base64: maximumBytes.base64EncodedString()).validated()
        for invalid in ["AQ", "AQ=", "-_==", "AQ==\n", "%%%%"] {
            #expect(Self.failure { try FirebaseSourceValue.bytes(base64: invalid).validated() } == .invalidBytes)
        }
        #expect(Self.failure { try FirebaseSourceValue.bytes(base64: (maximumBytes + Data([0])).base64EncodedString()).validated() } == .invalidBytes)

        let maximumString = String(repeating: "x", count: FirebaseSourceFixtureCatalog.maximumValueBytes)
        _ = try FirebaseSourceValue.string(maximumString).validated()
        #expect(Self.failure { try FirebaseSourceValue.string(maximumString + "x").validated() } == .stringTooLarge)
        let maximumMultibyteString = String(repeating: "é", count: 524_243) + "a"
        #expect(maximumMultibyteString.utf8.count == FirebaseSourceFixtureCatalog.maximumValueBytes)
        _ = try FirebaseSourceValue.string(maximumMultibyteString).validated()
        #expect(Self.failure { try FirebaseSourceValue.string(maximumMultibyteString + "é").validated() } == .stringTooLarge)

        _ = try FirebaseSourceValue.reference(segments: [String(repeating: "a", count: 1_500), "b"]).validated()
        #expect(Self.failure {
            try FirebaseSourceValue.reference(
                segments: [String(repeating: "a", count: 1_501), "b"]
            ).validated()
        } == .invalidReference)
        let twoHundred = (0..<200).map { "s\($0)" }
        _ = try FirebaseSourceValue.reference(segments: twoHundred).validated()
        let reference6144 = [
            String(repeating: "a", count: 1_500), String(repeating: "b", count: 1_500),
            String(repeating: "c", count: 1_500), String(repeating: "d", count: 1_500),
            String(repeating: "e", count: 138), "f"
        ]
        _ = try FirebaseSourceValue.reference(segments: reference6144).validated()
        var reference6145 = reference6144
        reference6145[4].append("e")
        #expect(Self.failure { try FirebaseSourceValue.reference(segments: reference6145).validated() } == .invalidReference)
        for invalid in [["only"], ["a", "b", "c"], ["a", ".."], ["a", "b/c"], ["a", ""], ["a", "nul\0value"], Array(repeating: "x", count: 202)] {
            #expect(Self.failure { try FirebaseSourceValue.reference(segments: invalid).validated() } == .invalidReference)
        }

        _ = try FirebaseSourceValue.array(Array(repeating: .null, count: 10_000)).validated()
        #expect(Self.failure { try FirebaseSourceValue.array(Array(repeating: .null, count: 10_001)).validated() } == .collectionTooLarge)

        let entries = (0..<10_000).map {
            FirebaseSourceMapEntry(key: String(format: "k%05d", $0), value: .null)
        }
        _ = try FirebaseSourceValue.map(entries).validated()
        #expect(Self.failure { try FirebaseSourceValue.map(entries + [.init(key: "z", value: .null)]).validated() } == .collectionTooLarge)
        #expect(Self.failure { try FirebaseSourceValue.map([.init(key: "b", value: .null), .init(key: "a", value: .null)]).validated() } == .noncanonicalPayload)
        #expect(Self.failure {
            try FirebaseSourceValue.map([
                .init(key: "duplicate", value: .null),
                .init(key: "duplicate", value: .bool(true))
            ]).validated()
        } == .duplicateMapKey)
        _ = try FirebaseSourceValue.map([.init(key: String(repeating: "k", count: 1_500), value: .null)]).validated()
        #expect(Self.failure { try FirebaseSourceValue.map([.init(key: String(repeating: "k", count: 1_501), value: .null)]).validated() } == .keyTooLarge)
        let multibyteKey = String(repeating: "é", count: 750)
        #expect(multibyteKey.utf8.count == 1_500)
        _ = try FirebaseSourceValue.map([.init(key: multibyteKey, value: .null)]).validated()
        #expect(Self.failure { try FirebaseSourceValue.map([.init(key: multibyteKey + "a", value: .null)]).validated() } == .keyTooLarge)

        let decomposed = "e\u{301}"
        let precomposed = "é"
        #expect(decomposed == precomposed)
        #expect(Data(decomposed.utf8) != Data(precomposed.utf8))
        _ = try FirebaseSourceValue.map([
            .init(key: decomposed, value: .null),
            .init(key: precomposed, value: .null)
        ]).validated()
        #expect(Self.failure {
            try FirebaseSourceValue.map([
                .init(key: precomposed, value: .null),
                .init(key: decomposed, value: .null)
            ]).validated()
        } == .noncanonicalPayload)
        try FirebaseSourceFixtureCatalog.validateRawRecordIDs([decomposed, precomposed])
        #expect(Self.failure { try FirebaseSourceFixtureCatalog.validateRawRecordIDs(["same", "same"]) } == .duplicateRecordID)
        #expect(Self.failure { try FirebaseSourceFixtureCatalog.validateRawRecordIDs(["Record", "record"]) } == .recordIDCaseCollision)

        var depth: FirebaseSourceValue = .null
        for _ in 1..<20 { depth = .array([depth]) }
        _ = try depth.validated()
        depth = .array([depth])
        #expect(Self.failure { try depth.validated() } == .nestingTooDeep)

        let exactNodeLimit = FirebaseSourceValue.array([
            .array(Array(repeating: .null, count: 10_000)),
            .array(Array(repeating: .null, count: 10_000)),
            .array(Array(repeating: .null, count: 10_000)),
            .array(Array(repeating: .null, count: 10_000)),
            .array(Array(repeating: .null, count: 9_994))
        ])
        _ = try exactNodeLimit.validated()
        guard case .array(var groups) = exactNodeLimit else { return }
        groups[4] = .array(Array(repeating: .null, count: 9_995))
        #expect(Self.failure { try FirebaseSourceValue.array(groups).validated() } == .tooManyValueNodes)

        let unsupported = FirebaseSourceValue.unsupported(sourceKind: "vector_value", evidence: .bytes(base64: "AA=="))
        let malformed = FirebaseSourceValue.malformed(failureCode: "bad_integer", evidence: .string("01"))
        #expect(try FirebaseSourceFixtureCatalog.decodeValue(FirebaseSourceFixtureCatalog.canonicalData(for: unsupported)) == unsupported)
        #expect(try FirebaseSourceFixtureCatalog.decodeValue(FirebaseSourceFixtureCatalog.canonicalData(for: malformed)) == malformed)
        #expect(unsupported != malformed)
    }

    @Test("FBSOURCEFIXTURE-TEST-002 reviewed bundle is byte-stable across restart")
    func goldenBundleAndRestart() throws {
        let bytes = try Self.fixtureBytes()
        let first = try FirebaseSourceFixtureCatalog().validate(manifestEnvelope: bytes.manifest, files: bytes.files)
        let restarted = try FirebaseSourceFixtureCatalog().validate(manifestEnvelope: Data(bytes.manifest), files: bytes.files.map { .init(path: $0.path, bytes: Data($0.bytes)) })
        #expect(first == restarted)
        #expect(first.sourceSnapshot.environment == .sourceFixture)
        #expect(first.sourceSnapshot.exportID.rawValue == "1ecd6b1ed0bfbe4b9e65d0c55e367562")
        #expect(first.sourceSnapshot.sha256.rawValue == "1ecd6b1ed0bfbe4b9e65d0c55e367562d761cbe00fd0f38cdb86111fd2b7f4a2")
        #expect(first.sourceSnapshot.byteCount == 12_604)
        #expect(first.sourceSnapshot.capturedAtEpochMilliseconds == 1_704_067_200_000)
        #expect(first.fixtureVersion.rawValue == "firebase-source-v1")
        #expect(first.sanitizationVersion.rawValue == "synthetic-v1")
        #expect(first.accountScopeID.rawValue == "a11ce000000000000000000000000001")
        #expect(first.privacyReviewEvidenceID.rawValue == "synthetic_catalog_review_v1")

        let envelope = try #require(JSONSerialization.jsonObject(with: bytes.manifest) as? [String: Any])
        let contentObject = try #require(envelope["content"])
        let content = try Self.canonicalJSON(contentObject)
        #expect(content.count == 3_051)
        var preimage = Data("ledger.firebase-source-fixture.v1\0".utf8)
        Self.append(UInt64(content.count), to: &preimage)
        preimage.append(content)
        for file in bytes.files {
            Self.append(UInt32(file.path.utf8.count), to: &preimage)
            preimage.append(contentsOf: file.path.utf8)
            Self.append(UInt64(file.bytes.count), to: &preimage)
            preimage.append(file.bytes)
        }
        #expect(Self.sha256(preimage) == first.sourceSnapshot.sha256.rawValue)
        #expect(bytes.files.map { Self.sha256($0.bytes) } == [
            "060cc947968cc135a533822ae071e17ca5f232fcf99e4a0d867ae42e53d73f74",
            "16f78cef5e69e720db2db9e70ec34c8ec02fe5f8e736d1139f3c08703e834d70",
            "9d10c8143c923cce031a318700a4787bd0624794633b5b85aeddbd35aaa06f3d"
        ])
        #expect(FirebaseSourceFixtureCatalog.maximumAggregatePayloadBytes == FirebaseSourceFixtureCatalog.maximumComponentBytes * 3)
        #expect(FirebaseSourceFixtureCatalog.maximumSourceBytes == FirebaseSourceFixtureCatalog.maximumManifestContentBytes + FirebaseSourceFixtureCatalog.maximumAggregatePayloadBytes)
        #expect(String(decoding: bytes.manifest, as: UTF8.self).contains("\"reviewKind\":\"independent_agent_synthetic_review\""))
        #expect(!String(decoding: bytes.manifest, as: UTF8.self).contains("humanReviewed"))

        for role in FirebaseSourceFixtureCatalog.PayloadRole.allCases {
            try FirebaseSourceFixtureCatalog.validateEntryCount(10_000, role: role)
            #expect(Self.failure { try FirebaseSourceFixtureCatalog.validateEntryCount(10_001, role: role) } == .collectionTooLarge)
        }
        try FirebaseSourceFixtureCatalog.validateManifestEnvelopeSize(263_168)
        #expect(Self.failure { try FirebaseSourceFixtureCatalog.validateManifestEnvelopeSize(263_169) } == .manifestEnvelopeTooLarge)
        try FirebaseSourceFixtureCatalog.validateManifestContentSize(262_144)
        #expect(Self.failure { try FirebaseSourceFixtureCatalog.validateManifestContentSize(262_145) } == .manifestContentTooLarge)
        try FirebaseSourceFixtureCatalog.validateComponentSizes([4_194_304, 4_194_304, 4_194_304])
        #expect(Self.failure { try FirebaseSourceFixtureCatalog.validateComponentSizes([4_194_305]) } == .componentTooLarge)
        #expect(Self.failure { try FirebaseSourceFixtureCatalog.validateComponentSizes([3_145_729, 3_145_729, 3_145_729, 3_145_729]) } == .aggregatePayloadTooLarge)
        try FirebaseSourceFixtureCatalog.validateSourceByteCount(12_845_056)
        #expect(Self.failure { try FirebaseSourceFixtureCatalog.validateSourceByteCount(12_845_057) } == .sourceByteCountTooLarge)
        // Framing integer overflow is unreachable through the much smaller supported
        // path, manifest, component, aggregate, and source-size ceilings above.

        var oversizedComponent = bytes.files
        oversizedComponent[0] = .init(path: oversizedComponent[0].path, bytes: Data(repeating: 0x20, count: FirebaseSourceFixtureCatalog.maximumComponentBytes + 1))
        #expect(Self.failure { try FirebaseSourceFixtureCatalog().validate(manifestEnvelope: bytes.manifest, files: oversizedComponent) } == .componentTooLarge)
    }

    @Test("FBSOURCEFIXTURE-TEST-003 tamper paths schemas and noncanonical bytes fail closed")
    func tamperAndPathRejection() throws {
        let fixture = try Self.fixtureBytes()
        var tamperedFiles = fixture.files
        tamperedFiles[0] = .init(path: tamperedFiles[0].path, bytes: tamperedFiles[0].bytes + Data([0x20]))
        #expect(Self.failure { try FirebaseSourceFixtureCatalog().validate(manifestEnvelope: fixture.manifest, files: tamperedFiles) } == .fileByteCountMismatch)

        #expect(Self.failure {
            try FirebaseSourceFixtureCatalog().validate(manifestEnvelope: fixture.manifest, files: fixture.files + [fixture.files[0]])
        } == .duplicateLogicalPath)
        var caseCollision = fixture.files
        caseCollision.append(.init(path: "AUTH/IDENTITY-METADATA.JSON", bytes: fixture.files[0].bytes))
        #expect(Self.failure { try FirebaseSourceFixtureCatalog().validate(manifestEnvelope: fixture.manifest, files: caseCollision) } == .logicalPathCaseCollision)
        var escaping = fixture.files
        escaping[0] = .init(path: "../identity-metadata.json", bytes: escaping[0].bytes)
        #expect(Self.failure { try FirebaseSourceFixtureCatalog().validate(manifestEnvelope: fixture.manifest, files: escaping) } == .invalidLogicalPath)
        var absolute = fixture.files
        absolute[0] = .init(path: "/identity-metadata.json", bytes: absolute[0].bytes)
        #expect(Self.failure { try FirebaseSourceFixtureCatalog().validate(manifestEnvelope: fixture.manifest, files: absolute) } == .invalidLogicalPath)

        let oversized = Data(repeating: 0x20, count: FirebaseSourceFixtureCatalog.maximumManifestEnvelopeBytes + 1)
        #expect(Self.failure { try FirebaseSourceFixtureCatalog().validate(manifestEnvelope: oversized, files: fixture.files) } == .manifestEnvelopeTooLarge)
        #expect(Self.failure {
            try FirebaseSourceFixtureCatalog().validate(
                manifestEnvelope: fixture.manifest.dropLast(),
                files: fixture.files
            )
        } == .noncanonicalManifest)
        #expect(Self.failure { try FirebaseSourceFixtureCatalog().validate(manifestEnvelope: fixture.manifest + Data([0x20]), files: fixture.files) } == .noncanonicalManifest)

        #expect(Self.failure {
            try FirebaseSourceFixtureCatalog().validate(
                manifestEnvelope: try Self.mutatedManifest(fixture.manifest) { $0["unknown"] = true },
                files: fixture.files
            )
        } == .unknownField)
        #expect(Self.failure {
            try FirebaseSourceFixtureCatalog().validate(
                manifestEnvelope: try Self.mutatedManifest(fixture.manifest) { Self.mutateContent(&$0) { $0["schemaVersion"] = 2 } },
                files: fixture.files
            )
        } == .unsupportedSchemaVersion)
        #expect(Self.failure {
            try FirebaseSourceFixtureCatalog().validate(
                manifestEnvelope: try Self.mutatedManifest(fixture.manifest) { Self.mutateContent(&$0) { $0["fixtureVersion"] = "firebase-source-v2" } },
                files: fixture.files
            )
        } == .unsupportedFixtureVersion)
        #expect(Self.failure {
            try FirebaseSourceFixtureCatalog().validate(
                manifestEnvelope: try Self.mutatedManifest(fixture.manifest) { Self.mutateContent(&$0) { $0["sanitizationVersion"] = "synthetic-v2" } },
                files: fixture.files
            )
        } == .unsupportedSanitizationVersion)
        #expect(Self.failure {
            try FirebaseSourceFixtureCatalog().validate(
                manifestEnvelope: try Self.mutatedManifest(fixture.manifest) { Self.mutateContent(&$0) { $0["accountScopeID"] = "b22ce000000000000000000000000002" } },
                files: fixture.files
            )
        } == .invalidAccountScope)
        #expect(Self.failure {
            try FirebaseSourceFixtureCatalog().validate(
                manifestEnvelope: try Self.mutatedManifest(fixture.manifest) {
                    Self.mutateContent(&$0) { content in
                        content["files"] = Array((content["files"] as! [Any]).reversed())
                    }
                },
                files: fixture.files
            )
        } == .fileOrderMismatch)
        #expect(Self.failure {
            try FirebaseSourceFixtureCatalog().validate(
                manifestEnvelope: try Self.mutatedManifest(fixture.manifest) {
                    Self.mutateContent(&$0) { content in
                        var files = content["files"] as! [[String: Any]]
                        files[0]["recordCount"] = 3; content["files"] = files
                    }
                },
                files: fixture.files
            )
        } == .payloadRecordCountMismatch)
        #expect(Self.failure {
            try FirebaseSourceFixtureCatalog().validate(
                manifestEnvelope: try Self.mutatedManifest(fixture.manifest) {
                    Self.mutateContent(&$0) { content in
                        var files = content["files"] as! [[String: Any]]
                        files[0]["sha256"] = String(repeating: "0", count: 64); content["files"] = files
                    }
                },
                files: fixture.files
            )
        } == .fileDigestMismatch)
        #expect(Self.failure {
            try FirebaseSourceFixtureCatalog().validate(
                manifestEnvelope: try Self.mutatedManifest(fixture.manifest) {
                    Self.mutateContent(&$0) { content in
                        var files = content["files"] as! [[String: Any]]
                        files[0]["role"] = "firestore_documents"; content["files"] = files
                    }
                },
                files: fixture.files
            )
        } == .fileRoleMismatch)
        #expect(Self.failure {
            try FirebaseSourceFixtureCatalog().validate(
                manifestEnvelope: try Self.mutatedManifest(fixture.manifest) {
                    Self.mutateContent(&$0) { content in
                        var entities = content["entities"] as! [[String: Any]]
                        entities[0]["count"] = 2; content["entities"] = entities
                    }
                },
                files: fixture.files
            )
        } == .entityCountMismatch)
        #expect(Self.failure {
            try FirebaseSourceFixtureCatalog().validate(
                manifestEnvelope: try Self.mutatedManifest(fixture.manifest) {
                    Self.mutateContent(&$0) { content in
                        var entities = content["entities"] as! [[String: Any]]
                        entities[0]["sha256"] = String(repeating: "0", count: 64); content["entities"] = entities
                    }
                },
                files: fixture.files
            )
        } == .entityDigestMismatch)
        #expect(Self.failure {
            try FirebaseSourceFixtureCatalog().validate(
                manifestEnvelope: try Self.mutatedManifest(fixture.manifest) {
                    Self.mutateContent(&$0) { content in
                        var entities = content["entities"] as! [[String: Any]]
                        entities.swapAt(0, 1); content["entities"] = entities
                    }
                },
                files: fixture.files
            )
        } == .entityOrderMismatch)
        #expect(Self.failure {
            try FirebaseSourceFixtureCatalog().validate(
                manifestEnvelope: try Self.mutatedManifest(fixture.manifest) {
                    Self.mutateContent(&$0) { content in
                        var entities = content["entities"] as! [[String: Any]]
                        entities.insert(entities[0], at: 1); content["entities"] = entities
                    }
                },
                files: fixture.files
            )
        } == .duplicateEntity)
        #expect(Self.failure {
            try FirebaseSourceFixtureCatalog().validate(
                manifestEnvelope: try Self.mutatedManifest(fixture.manifest) { $0["bundleSHA256"] = String(repeating: "0", count: 64) },
                files: fixture.files
            )
        } == .bundleDigestMismatch)

        var object = try #require(JSONSerialization.jsonObject(with: fixture.files[0].bytes) as? [String: Any])
        object["email"] = "prohibited@example.invalid"
        let prohibited = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) + Data([0x0a])
        var prohibitedFiles = fixture.files
        prohibitedFiles[0] = .init(path: fixture.files[0].path, bytes: prohibited)
        #expect(Self.failure { try FirebaseSourceFixtureCatalog().validate(manifestEnvelope: fixture.manifest, files: prohibitedFiles) } == .fileByteCountMismatch)
        for (path, prohibitedField) in [
            ("auth/identity-metadata.json", "email"),
            ("firestore/documents.json", "credential"),
            ("storage/object-metadata.json", "downloadToken")
        ] {
            let prohibitedBytes = Data("{\"\(prohibitedField)\":\"synthetic\"}".utf8)
            #expect(Self.failure {
                try FirebaseSourceFixtureCatalog.validateNoProhibitedFields(
                    path: path,
                    bytes: prohibitedBytes
                )
            } == .prohibitedField)
        }

        var malformedSameLength = fixture.files
        var malformedBytes = malformedSameLength[0].bytes
        malformedBytes[malformedBytes.startIndex] = 0x21
        malformedSameLength[0] = .init(path: malformedSameLength[0].path, bytes: malformedBytes)
        #expect(Self.failure {
            try FirebaseSourceFixtureCatalog().validate(manifestEnvelope: fixture.manifest, files: malformedSameLength)
        } == .fileDigestMismatch)
        #expect(Self.failure {
            try FirebaseSourceFixtureCatalog.validateReviewedComponent(path: fixture.files[0].path, bytes: malformedBytes)
        } == .reviewedCatalogMismatch)

        var authObject = try #require(JSONSerialization.jsonObject(with: fixture.files[0].bytes) as? [String: Any])
        authObject["unknown"] = true
        var unknownPayloadFiles = fixture.files
        unknownPayloadFiles[0] = .init(path: fixture.files[0].path, bytes: try Self.canonicalJSON(authObject) + Data([0x0a]))
        #expect(Self.failure {
            try FirebaseSourceFixtureCatalog().validate(manifestEnvelope: fixture.manifest, files: unknownPayloadFiles)
        } == .fileByteCountMismatch)
        authObject.removeValue(forKey: "unknown")
        authObject["schemaVersion"] = 2
        var wrongVersionFiles = fixture.files
        wrongVersionFiles[0] = .init(path: fixture.files[0].path, bytes: try Self.canonicalJSON(authObject) + Data([0x0a]))
        #expect(wrongVersionFiles[0].bytes.count == fixture.files[0].bytes.count)
        #expect(Self.failure {
            try FirebaseSourceFixtureCatalog().validate(manifestEnvelope: fixture.manifest, files: wrongVersionFiles)
        } == .fileDigestMismatch)

        let unknownValue = Data(#"{"kind":"integer","unknown":true,"value":"1"}"#.utf8)
        #expect(Self.failure { try FirebaseSourceFixtureCatalog.decodeValue(unknownValue) } == .unknownField)
        let unknownKind = Data(#"{"kind":"server_timestamp"}"#.utf8)
        #expect(Self.failure { try FirebaseSourceFixtureCatalog.decodeValue(unknownKind) } == .invalidValueKind)
        let malformedTaggedValue = Data(#"{"failureCode":"bad_integer","kind":"malformed"}"#.utf8)
        #expect(Self.failure { try FirebaseSourceFixtureCatalog.decodeValue(malformedTaggedValue) } == .malformedPayload)
        let unsupportedWithInvalidCode = Data(#"{"evidence":{"kind":"null"},"kind":"unsupported","sourceKind":"Vector"}"#.utf8)
        #expect(Self.failure { try FirebaseSourceFixtureCatalog.decodeValue(unsupportedWithInvalidCode) } == .invalidStableCode)
    }

    @Test("FBSOURCEFIXTURE-TEST-004 media fixtures are metadata-only fault evidence")
    func mediaMetadataIsSyntheticAndNonOperational() throws {
        let fixture = try Self.fixtureBytes()
        let storage = String(decoding: fixture.files[2].bytes, as: UTF8.self)
        for marker in ["referenced", "missing", "duplicate", "cross_namespace", "thumbnail", "placeholderContentSHA256"] {
            #expect(storage.contains(marker))
        }
        for forbidden in ["https://", "gs://", "downloadToken", "access_token", "service_role", "ledger-nine4", "bucket", "objectName"] {
            #expect(!storage.localizedCaseInsensitiveContains(forbidden))
        }
        _ = try FirebaseSourceFixtureCatalog().validate(manifestEnvelope: fixture.manifest, files: fixture.files)
    }

    @Test("FBSOURCEFIXTURE-TEST-005 snapshot and entity plans fit migration integrity values")
    func migrationIdentityCompatibility() throws {
        let fixture = try Self.fixtureBytes()
        let validated = try FirebaseSourceFixtureCatalog().validate(manifestEnvelope: fixture.manifest, files: fixture.files)
        let codes = validated.entityPlans.map(\.entity.rawValue)
        #expect(codes == codes.sorted())
        #expect(Set(codes).count == codes.count)
        #expect(validated.entityPlans.allSatisfy { $0.plannedCount >= 0 })
        #expect(validated.entityPlans.allSatisfy { $0.transformVersion == validated.fixtureVersion })
        #expect(validated.entityPlans.first(where: { $0.entity.rawValue == "invoices" })?.plannedCount == 2)
        #expect(validated.entityPlans.first(where: { $0.entity.rawValue == "storage_metadata" })?.plannedCount == 5)
        #expect(validated.entityPlans.first(where: { $0.entity.rawValue == "malformed_records" })?.plannedCount == 1)
        #expect(validated.entityPlans.first(where: { $0.entity.rawValue == "ambiguous_records" })?.plannedCount == 1)
        #expect(validated.entityPlans.first(where: { $0.entity.rawValue == "invoices" })?.sourceSHA256.rawValue == "798775b7b635ce5c977e404404ec3355c65622aa0fddc0fe572d568cb2dfb939")

        var recordsByEntity: [String: [(id: String, bytes: Data)]] = [:]
        for file in fixture.files {
            let payload = try #require(JSONSerialization.jsonObject(with: file.bytes) as? [String: Any])
            for record in try #require(payload["entries"] as? [[String: Any]]) {
                let entity = try #require(record["entityCode"] as? String)
                let id = try #require(record["sourceRecordID"] as? String)
                recordsByEntity[entity, default: []].append((id, try Self.canonicalJSON(record)))
            }
        }
        let independentlyHashed = Dictionary(uniqueKeysWithValues: recordsByEntity.map { entity, records in
            var preimage = Data("ledger.firebase-source-fixture.entity.v1\0".utf8)
            Self.append(UInt32(entity.utf8.count), to: &preimage)
            preimage.append(contentsOf: entity.utf8)
            for record in records.sorted(by: { Data($0.id.utf8).lexicographicallyPrecedes(Data($1.id.utf8)) }) {
                Self.append(UInt32(record.id.utf8.count), to: &preimage)
                preimage.append(contentsOf: record.id.utf8)
                Self.append(UInt64(record.bytes.count), to: &preimage)
                preimage.append(record.bytes)
            }
            return (entity, Self.sha256(preimage))
        })
        #expect(independentlyHashed == Dictionary(uniqueKeysWithValues: validated.entityPlans.map { ($0.entity.rawValue, $0.sourceSHA256.rawValue) }))
    }

    @Test("FBSOURCEFIXTURE-TEST-006 every source entry is counted exactly once")
    func reconciliationCoverageIsExactAndBounded() throws {
        let fixture = try Self.fixtureBytes()
        let validated = try FirebaseSourceFixtureCatalog().validate(manifestEnvelope: fixture.manifest, files: fixture.files)
        #expect(validated.entityPlans.reduce(Int64(0)) { $0 + $1.plannedCount } == 21)
        #expect(validated.entityPlans.count == 15)
        let manifest = String(decoding: fixture.manifest, as: UTF8.self)
        #expect(manifest.contains("curated_shapes_not_production_complete"))
        #expect(manifest.contains("no_target_transform_or_reconciliation_claim"))
        #expect(!manifest.contains("\"productionRepresentative\":true"))
        #expect(!manifest.contains("\"reconciliationComplete\":true"))
    }

    @Test("FBSOURCEFIXTURE-TEST-007 catalog exposes evidence only and performs no provider work")
    func evidenceOnlyNonAuthority() throws {
        let fixture = try Self.fixtureBytes()
        let validated = try FirebaseSourceFixtureCatalog().validate(manifestEnvelope: fixture.manifest, files: fixture.files)
        #expect(validated.authorityDisposition == .evidenceOnly)
        let source = try String(contentsOf: #require(Self.sourceURL()), encoding: .utf8)
        for forbidden in ["FirebaseCore", "FirebaseAuth", "FirebaseFirestore", "FirebaseStorage", "Supabase", "PowerSync", "URLSession", "FileManager", "ProcessInfo"] {
            #expect(!source.contains(forbidden))
        }
    }

    private static func fixtureBytes() throws -> (manifest: Data, files: [FirebaseSourceFixtureFile]) {
        let root = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
            .appending(path: "FirebaseSource/v1", directoryHint: .isDirectory)
        let manifest = try Data(contentsOf: root.appending(path: "manifest.json"))
        let files = try FirebaseSourceFixtureCatalog.payloadPaths.map { path in
            FirebaseSourceFixtureFile(path: path, bytes: try Data(contentsOf: root.appending(path: path)))
        }
        return (manifest, files)
    }

    private static func sourceURL() -> URL? {
        let test = URL(fileURLWithPath: #filePath)
        return test.deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "LedgerTargetMigrationCore/FirebaseSourceFixture.swift")
    }

    private static func failure<T>(_ operation: () throws -> T) -> FirebaseSourceFixtureFailure? {
        do { _ = try operation(); return nil }
        catch let failure as FirebaseSourceFixtureFailure { return failure }
        catch { Issue.record("Unexpected failure type: \(error)"); return nil }
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func mutatedManifest(
        _ data: Data,
        mutate: (inout [String: Any]) -> Void
    ) throws -> Data {
        var envelope = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        mutate(&envelope)
        return try canonicalJSON(envelope) + Data([0x0a])
    }

    private static func mutateContent(
        _ envelope: inout [String: Any],
        mutate: (inout [String: Any]) -> Void
    ) {
        var content = envelope["content"] as! [String: Any]
        mutate(&content)
        envelope["content"] = content
    }

    private static func canonicalJSON(_ value: Any) throws -> Data {
        if value is NSNull { return Data("null".utf8) }
        if let value = value as? String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            return try encoder.encode(value)
        }
        if let value = value as? [Any] {
            var result = Data("[".utf8)
            for (index, item) in value.enumerated() {
                if index > 0 { result.append(0x2c) }
                result.append(try canonicalJSON(item))
            }
            result.append(0x5d)
            return result
        }
        if let value = value as? [String: Any] {
            var result = Data("{".utf8)
            let keys = value.keys.sorted { Data($0.utf8).lexicographicallyPrecedes(Data($1.utf8)) }
            for (index, key) in keys.enumerated() {
                if index > 0 { result.append(0x2c) }
                result.append(try canonicalJSON(key))
                result.append(0x3a)
                result.append(try canonicalJSON(value[key]!))
            }
            result.append(0x7d)
            return result
        }
        if let value = value as? NSNumber {
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return Data((value.boolValue ? "true" : "false").utf8)
            }
            return Data(value.stringValue.utf8)
        }
        throw FirebaseSourceFixtureFailure.malformedPayload
    }
}
