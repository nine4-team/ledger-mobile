import CryptoKit
import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetMigrationCore

@Suite("Migration Environment Guard")
struct MigrationEnvironmentGuardTests {
    @Test("MIGENVGUARD-TEST-001 exact local dry-run tuple and omitted mode")
    func exactTupleAndOmittedMode() throws {
        let fixture = try Self.fixture()
        let requestData = try MigrationEnvironmentGuard.canonicalRequestData(for: fixture.request)
        let reconstructedRequest = try JSONDecoder().decode(
            MigrationPreflightRequest.self,
            from: requestData
        )
        #expect(
            try MigrationEnvironmentGuard.canonicalRequestData(for: reconstructedRequest)
                == requestData
        )
        let result = try MigrationEnvironmentGuard.validate(
            requestData: requestData,
            policy: fixture.policy
        )

        #expect(result.receipt.content.planDigest == fixture.plan.contentDigest)
        #expect(result.receipt.content.policyDigest == fixture.policy.digest)
        #expect(result.receipt.content.fixtureBundleDigest == fixture.source.sourceSnapshot.sha256)
        #expect(result.receipt.content.targetEnvironment == .targetLocal)
        #expect(result.receipt.content.mode == .dryRun)
        #expect(result.receipt.content.sourceCredential == .none)
        #expect(result.receipt.content.targetCredential == .none)
        #expect(result.receipt.content.authorityDisposition == .evidenceOnly)
        #expect(result.token.planDigest == result.receipt.content.planDigest)
        #expect(result.token.policyDigest == result.receipt.content.policyDigest)
        #expect(result.token.receiptDigest == result.receipt.digest)
        #expect(!((result.token as Any) is any Encodable))
        #expect(!((result.token as Any) is any Decodable))
        #expect(
            fixture.policy.content.accountScopeSHA256.rawValue
                == "8cbab43dfd8e69379b761694cea3fd33f3fb9d4f29bf73a6a79b21fbac9cc9ed"
        )
        #expect(
            try MigrationPreflightAccountScope.sha256(
                authenticatedAccountScopeID: fixture.source.accountScopeID
            ) == fixture.policy.content.accountScopeSHA256
        )

        let withoutMode = try Self.mutatingObject(requestData) { $0.removeValue(forKey: "mode") }
        let defaulted = try MigrationEnvironmentGuard.validate(
            requestData: withoutMode,
            policy: fixture.policy
        )
        #expect(defaulted.receipt == result.receipt)
        #expect(defaulted.token == result.token)
    }

    @Test("MIGENVGUARD-TEST-002 canonical policy and receipt restart evidence")
    func canonicalDigestsAndRestart() throws {
        let fixture = try Self.fixture()
        let request = try MigrationEnvironmentGuard.canonicalRequestData(for: fixture.request)
        let result = try MigrationEnvironmentGuard.validate(requestData: request, policy: fixture.policy)

        let policyContent = try MigrationEnvironmentGuard.canonicalPolicyContentData(
            for: fixture.policy
        )
        #expect(Self.sha256(request) == "971815767f061ea9764b1eb4b28d8749b49968f92e818281c78b395f5c5d249e")
        #expect(Self.sha256(policyContent) == "bfb999c72f2104fa60b3bb81d9f25b9bef3b1436bb6c9693bdbf4e163f717d48")
        #expect(fixture.policy.digest.rawValue == "91ba4bf8765756a395693f9fdb34230145fe24373b4c984816ce3e54fa07cd3c")
        #expect(
            fixture.policy.digest.rawValue == Self.digest(
                domain: "ledger.migration-preflight-policy.v1\0",
                content: policyContent
            )
        )
        let policyEnvelope = try MigrationEnvironmentGuard.canonicalPolicyEnvelopeData(
            for: fixture.policy
        )
        let reorderedPolicy = try Self.reordered(policyEnvelope)
        let restoredPolicy = try MigrationEnvironmentGuard.decodePolicyEnvelope(reorderedPolicy)
        #expect(restoredPolicy == fixture.policy)
        #expect(
            try MigrationEnvironmentGuard.canonicalPolicyEnvelopeData(for: restoredPolicy)
                == policyEnvelope
        )

        let receiptEnvelope = try MigrationEnvironmentGuard.canonicalReceiptEnvelopeData(
            for: result.receipt
        )
        let receiptObject = try #require(
            JSONSerialization.jsonObject(with: receiptEnvelope) as? [String: Any]
        )
        let receiptContentObject = try #require(receiptObject["content"])
        let independentlyCanonicalReceiptContent = try JSONSerialization.data(
            withJSONObject: receiptContentObject,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        #expect(
            Self.sha256(independentlyCanonicalReceiptContent)
                == "b37594d96e319c02382b5b59ae543fe7decc7c434683ac88d70af9e343b37d3f"
        )
        #expect(result.receipt.digest.rawValue == "9d6e5fbe9330696be4fa5387f9fb2ddc86a0c1fb44fc4d08c4456af1398807eb")
        #expect(
            result.receipt.digest.rawValue == Self.digest(
                domain: "ledger.migration-preflight-receipt.v1\0",
                content: independentlyCanonicalReceiptContent
            )
        )
        let restoredReceipt = try MigrationEnvironmentGuard.decodeReceiptEnvelope(
            try Self.reordered(receiptEnvelope)
        )
        #expect(restoredReceipt == result.receipt)
        #expect(
            try MigrationEnvironmentGuard.canonicalReceiptEnvelopeData(for: restoredReceipt)
                == receiptEnvelope
        )

        // Durable receipt evidence has no API that can reconstruct the process-local token.
        #expect(!((restoredReceipt as Any) is MigrationPreflightConsistencyToken))
    }

    @Test("MIGENVGUARD-TEST-003 every independently supplied identity fails closed")
    func singleMismatchMatrix() throws {
        let fixture = try Self.fixture()
        let otherSource = try MigrationSourceSnapshot(
            environment: .sourceFixture,
            exportID: MigrationOpaqueID(
                validating: String(repeating: "9", count: 32),
                field: "other_export"
            ),
            capturedAtEpochMilliseconds: fixture.source.sourceSnapshot.capturedAtEpochMilliseconds,
            byteCount: fixture.source.sourceSnapshot.byteCount,
            sha256: fixture.source.sourceSnapshot.sha256
        )
        let otherBundle = try MigrationSHA256.make(bytes: Data("other-bundle".utf8))
        let otherTarget = try MigrationTargetBinding.make(
            validatedEnvironment: Self.environment(seed: "other", kind: .targetLocal)
        )
        let otherAccount = try MigrationSHA256.make(bytes: Data("other-account".utf8))
        let otherRevision = try MigrationSourceRevision(
            validating: String(repeating: "b", count: 40)
        )
        let otherArtifact = try Self.artifact(id: "migration_bundle", bytes: "other")
        let otherMapping = try Self.artifact(id: "other_mapping", bytes: "other-map")
        var cases: [(MigrationPreflightRequest, MigrationPreflightFailure)] = [
            (fixture.request(replacingSource: otherSource), .sourceMismatch),
            (fixture.request(replacingBundle: otherBundle), .fixtureBundleMismatch),
            (fixture.request(replacingTarget: otherTarget), .targetMismatch),
            (fixture.request(replacingAccount: otherAccount), .accountScopeMismatch),
            (fixture.request(replacingRevision: otherRevision), .repositoryRevisionMismatch),
            (fixture.request(replacingArtifact: otherArtifact), .migrationArtifactMismatch),
            (fixture.request(replacingMappings: [otherMapping]), .mappingArtifactSetMismatch),
            (fixture.request(mode: .apply), .unsafeMode),
            (fixture.request(sourceCredential: .present), .credentialMismatch),
            (fixture.request(targetCredential: .present), .credentialMismatch)
        ]
        for contracts in [
            LedgerContractVersions(schema: "2", query: "1", operation: "1", sync: "1"),
            LedgerContractVersions(schema: "1", query: "2", operation: "1", sync: "1"),
            LedgerContractVersions(schema: "1", query: "1", operation: "2", sync: "1"),
            LedgerContractVersions(schema: "1", query: "1", operation: "1", sync: "2")
        ] {
            cases.append((fixture.request(replacingContracts: contracts), .contractVersionMismatch))
        }
        for (request, expected) in cases {
            #expect(
                Self.guardFailure(
                    requestData: try MigrationEnvironmentGuard.canonicalRequestData(for: request),
                    policy: fixture.policy
                ) == expected
            )
        }

        // The run-plan validator intentionally does not bind these three fields to its
        // caller-selected policy. The guard must therefore compare them independently.
        let planOnlyCases: [(Data, MigrationPreflightFailure)] = [
            (try fixture.planData(replacingSource: otherSource), .sourceMismatch),
            (try fixture.planData(replacingAccount: otherAccount), .accountScopeMismatch),
            (try fixture.planData(replacingRevision: otherRevision), .repositoryRevisionMismatch)
        ]
        for (planData, expected) in planOnlyCases {
            #expect(
                Self.guardFailure(
                    requestData: try MigrationEnvironmentGuard.canonicalRequestData(
                        for: fixture.request(replacingPlan: planData)
                    ),
                    policy: fixture.policy
                ) == expected
            )
        }

        let productionSource = try MigrationSourceSnapshot(
            environment: .sourceProduction,
            exportID: fixture.source.sourceSnapshot.exportID,
            capturedAtEpochMilliseconds: fixture.source.sourceSnapshot.capturedAtEpochMilliseconds,
            byteCount: fixture.source.sourceSnapshot.byteCount,
            sha256: fixture.source.sourceSnapshot.sha256
        )
        #expect(
            Self.guardFailure(
                requestData: try MigrationEnvironmentGuard.canonicalRequestData(
                    for: fixture.request(replacingSource: productionSource)
                ),
                policy: fixture.policy
            ) == .sourceMismatch
        )
        let stagingTarget = try MigrationTargetBinding.make(
            validatedEnvironment: Self.environment(seed: "staging", kind: .targetStaging)
        )
        #expect(
            Self.guardFailure(
                requestData: try MigrationEnvironmentGuard.canonicalRequestData(
                    for: fixture.request(replacingTarget: stagingTarget)
                ),
                policy: fixture.policy
            ) == .targetMismatch
        )
        let productionTarget = try MigrationTargetBinding.make(
            validatedEnvironment: Self.environment(seed: "production", kind: .targetProduction)
        )
        #expect(
            Self.guardFailure(
                requestData: try MigrationEnvironmentGuard.canonicalRequestData(
                    for: fixture.request(replacingTarget: productionTarget)
                ),
                policy: fixture.policy
            ) == .targetMismatch
        )

        let canonicalRequest = try MigrationEnvironmentGuard.canonicalRequestData(for: fixture.request)
        for targetHash in [
            "environmentManifestSHA256", "structuredDataResourceSHA256", "storageResourceSHA256"
        ] {
            let changed = try Self.mutatingObject(canonicalRequest) {
                var target = $0["targetBinding"] as! [String: Any]
                target[targetHash] = String(repeating: "f", count: 64)
                $0["targetBinding"] = target
            }
            #expect(Self.guardFailure(requestData: changed, policy: fixture.policy) == .targetMismatch)
        }
    }

    @Test("MIGENVGUARD-TEST-003 policy content is independently authenticated and fail closed")
    func policyMismatchMatrix() throws {
        let fixture = try Self.fixture()
        let request = try MigrationEnvironmentGuard.canonicalRequestData(for: fixture.request)

        let validMismatchCases: [
            ((inout [String: Any]) throws -> Void, MigrationPreflightFailure)
        ] = [
            ({ content in
                var source = content["sourceSnapshot"] as! [String: Any]
                source["exportID"] = String(repeating: "9", count: 32)
                content["sourceSnapshot"] = source
            }, .sourceMismatch),
            ({ content in
                var target = content["targetBinding"] as! [String: Any]
                target["environmentManifestSHA256"] = String(repeating: "f", count: 64)
                content["targetBinding"] = target
            }, .targetMismatch),
            ({ content in
                var target = content["targetBinding"] as! [String: Any]
                target["structuredDataResourceSHA256"] = String(repeating: "f", count: 64)
                content["targetBinding"] = target
            }, .targetMismatch),
            ({ content in
                var target = content["targetBinding"] as! [String: Any]
                target["storageResourceSHA256"] = String(repeating: "f", count: 64)
                content["targetBinding"] = target
            }, .targetMismatch),
            ({ $0["accountScopeSHA256"] = String(repeating: "f", count: 64) }, .accountScopeMismatch),
            ({ $0["repositoryRevision"] = String(repeating: "b", count: 40) }, .repositoryRevisionMismatch),
            ({ content in
                var artifact = content["migrationArtifact"] as! [String: Any]
                artifact["sha256"] = String(repeating: "f", count: 64)
                content["migrationArtifact"] = artifact
            }, .migrationArtifactMismatch),
            ({ content in
                var mappings = content["mappingArtifacts"] as! [[String: Any]]
                mappings[0]["sha256"] = String(repeating: "f", count: 64)
                content["mappingArtifacts"] = mappings
            }, .mappingArtifactSetMismatch)
        ]
        for (mutation, expected) in validMismatchCases {
            let policy = try MigrationEnvironmentGuard.decodePolicyEnvelope(
                Self.resignedPolicyEnvelope(fixture.policy, mutate: mutation)
            )
            #expect(Self.guardFailure(requestData: request, policy: policy) == expected)
        }

        for contractField in ["schema", "query", "operation", "sync"] {
            let policy = try MigrationEnvironmentGuard.decodePolicyEnvelope(
                Self.resignedPolicyEnvelope(fixture.policy) { content in
                    var contracts = content["contractVersions"] as! [String: Any]
                    contracts[contractField] = "2"
                    content["contractVersions"] = contracts
                }
            )
            #expect(
                Self.guardFailure(requestData: request, policy: policy)
                    == .contractVersionMismatch
            )
        }

        let unsafePolicyMutations: [(inout [String: Any]) throws -> Void] = [
            { $0["mode"] = "apply" },
            { $0["sourceCredential"] = "present" },
            { $0["targetCredential"] = "present" },
            { content in
                var source = content["sourceSnapshot"] as! [String: Any]
                source["environment"] = "source_production"
                content["sourceSnapshot"] = source
            },
            { content in
                var target = content["targetBinding"] as! [String: Any]
                target["environment"] = "targetStaging"
                content["targetBinding"] = target
            },
            { content in
                var target = content["targetBinding"] as! [String: Any]
                target["environment"] = "targetProduction"
                content["targetBinding"] = target
            }
        ]
        for mutation in unsafePolicyMutations {
            #expect(Self.failure {
                try MigrationEnvironmentGuard.decodePolicyEnvelope(
                    Self.resignedPolicyEnvelope(fixture.policy, mutate: mutation)
                )
            } == .policyInvalid)
        }

        let sourceStaging = try Self.resignedPolicyEnvelope(fixture.policy) { content in
            var source = content["sourceSnapshot"] as! [String: Any]
            source["environment"] = "source_staging"
            content["sourceSnapshot"] = source
        }
        #expect(Self.failure {
            try MigrationEnvironmentGuard.decodePolicyEnvelope(sourceStaging)
        } == .malformedPolicy)
    }

    @Test("MIGENVGUARD-TEST-004 malformed, noncanonical, and unknown evidence is refused")
    func tamperAndUnknownFieldsFailClosed() throws {
        let fixture = try Self.fixture()
        let request = try MigrationEnvironmentGuard.canonicalRequestData(for: fixture.request)

        let duplicateRequestRoot = try Self.insertingRootField(
            into: request,
            escapedName: "m\\u006fde",
            jsonValue: "\"dry_run\""
        )
        #expect(
            Self.guardFailure(requestData: duplicateRequestRoot, policy: fixture.policy)
                == .duplicateRequestField
        )
        let duplicateRequestNested = try Self.insertingNestedField(
            into: request,
            objectPrefix: "\"sourceSnapshot\":{",
            escapedName: "environm\\u0065nt",
            jsonValue: "\"source_fixture\""
        )
        #expect(
            Self.guardFailure(requestData: duplicateRequestNested, policy: fixture.policy)
                == .duplicateRequestField
        )

        let unknownRequest = try Self.mutatingObject(request) { $0["provider"] = "default" }
        #expect(Self.guardFailure(requestData: unknownRequest, policy: fixture.policy) == .unknownRequestField)
        let nestedUnknown = try Self.mutatingObject(request) {
            var source = $0["sourceSnapshot"] as! [String: Any]
            source["path"] = "/private/source"
            $0["sourceSnapshot"] = source
        }
        #expect(Self.guardFailure(requestData: nestedUnknown, policy: fixture.policy) == .unknownRequestField)
        let nullMode = try Self.mutatingObject(request) { $0["mode"] = NSNull() }
        #expect(Self.guardFailure(requestData: nullMode, policy: fixture.policy) == .malformedRequest)
        let sourceStaging = try Self.mutatingObject(request) {
            var source = $0["sourceSnapshot"] as! [String: Any]
            source["environment"] = "source_staging"
            $0["sourceSnapshot"] = source
        }
        #expect(
            Self.guardFailure(requestData: sourceStaging, policy: fixture.policy)
                == .malformedRequest
        )
        let missingCredential = try Self.mutatingObject(request) {
            $0.removeValue(forKey: "sourceCredential")
        }
        #expect(
            Self.guardFailure(requestData: missingCredential, policy: fixture.policy)
                == .malformedRequest
        )
        let unknownCredential = try Self.mutatingObject(request) {
            $0["targetCredential"] = "environment_default"
        }
        #expect(
            Self.guardFailure(requestData: unknownCredential, policy: fixture.policy)
                == .malformedRequest
        )
        let unknownMode = try Self.mutatingObject(request) { $0["mode"] = "commit" }
        #expect(
            Self.guardFailure(requestData: unknownMode, policy: fixture.policy)
                == .malformedRequest
        )
        let wrongRequestSchema = try Self.mutatingObject(request) { $0["schemaVersion"] = 2 }
        #expect(
            Self.guardFailure(requestData: wrongRequestSchema, policy: fixture.policy)
                == .requestSchemaMismatch
        )
        let malformedBase64 = try Self.mutatingObject(request) {
            $0["canonicalPlanBase64"] = "not/base64"
        }
        #expect(
            Self.guardFailure(requestData: malformedBase64, policy: fixture.policy)
                == .planBase64Invalid
        )

        let planWithTrailingNewline = fixture.planData + Data([0x0a])
        let noncanonicalPlan = fixture.request(replacingPlan: planWithTrailingNewline)
        #expect(
            Self.guardFailure(
                requestData: try MigrationEnvironmentGuard.canonicalRequestData(for: noncanonicalPlan),
                policy: fixture.policy
            ) == .planNoncanonical
        )
        let tamperedPlan = try Self.mutatingObject(fixture.planData) {
            $0["contentDigest"] = String(repeating: "f", count: 64)
        }
        #expect(
            Self.guardFailure(
                requestData: try MigrationEnvironmentGuard.canonicalRequestData(
                    for: fixture.request(replacingPlan: tamperedPlan)
                ),
                policy: fixture.policy
            ) == .planDigestMismatch
        )

        let policyEnvelope = try MigrationEnvironmentGuard.canonicalPolicyEnvelopeData(
            for: fixture.policy
        )
        let duplicatePolicyRoot = try Self.insertingRootField(
            into: policyEnvelope,
            escapedName: "dige\\u0073t",
            jsonValue: "\"\(fixture.policy.digest.rawValue)\""
        )
        #expect(Self.failure {
            try MigrationEnvironmentGuard.decodePolicyEnvelope(duplicatePolicyRoot)
        } == .duplicatePolicyField)
        let duplicatePolicyNested = try Self.insertingNestedField(
            into: policyEnvelope,
            objectPrefix: "\"content\":{",
            escapedName: "m\\u006fde",
            jsonValue: "\"dry_run\""
        )
        #expect(Self.failure {
            try MigrationEnvironmentGuard.decodePolicyEnvelope(duplicatePolicyNested)
        } == .duplicatePolicyField)
        let unknownPolicy = try Self.mutatingObject(policyEnvelope) { $0["trusted"] = true }
        #expect(Self.failure {
            try MigrationEnvironmentGuard.decodePolicyEnvelope(unknownPolicy)
        } == .unknownPolicyField)
        let missingPolicyField = try Self.mutatingObject(policyEnvelope) {
            var content = $0["content"] as! [String: Any]
            content.removeValue(forKey: "sourceCredential")
            $0["content"] = content
        }
        #expect(Self.failure {
            try MigrationEnvironmentGuard.decodePolicyEnvelope(missingPolicyField)
        } == .malformedPolicy)
        let tamperedPolicy = try Self.mutatingObject(policyEnvelope) {
            $0["digest"] = String(repeating: "f", count: 64)
        }
        #expect(Self.failure {
            try MigrationEnvironmentGuard.decodePolicyEnvelope(tamperedPolicy)
        } == .policyDigestMismatch)
        let wrongPolicySchema = try Self.mutatingObject(policyEnvelope) {
            var content = $0["content"] as! [String: Any]
            content["schemaVersion"] = 2
            $0["content"] = content
        }
        #expect(Self.failure {
            try MigrationEnvironmentGuard.decodePolicyEnvelope(wrongPolicySchema)
        } == .policySchemaMismatch)

        let result = try MigrationEnvironmentGuard.validate(
            requestData: request,
            policy: fixture.policy
        )
        let receipt = try MigrationEnvironmentGuard.canonicalReceiptEnvelopeData(for: result.receipt)
        let duplicateReceiptRoot = try Self.insertingRootField(
            into: receipt,
            escapedName: "dige\\u0073t",
            jsonValue: "\"\(result.receipt.digest.rawValue)\""
        )
        #expect(Self.failure {
            try MigrationEnvironmentGuard.decodeReceiptEnvelope(duplicateReceiptRoot)
        } == .duplicateReceiptField)
        let duplicateReceiptNested = try Self.insertingNestedField(
            into: receipt,
            objectPrefix: "\"content\":{",
            escapedName: "m\\u006fde",
            jsonValue: "\"dry_run\""
        )
        #expect(Self.failure {
            try MigrationEnvironmentGuard.decodeReceiptEnvelope(duplicateReceiptNested)
        } == .duplicateReceiptField)
        let unknownReceipt = try Self.mutatingObject(receipt) {
            var content = $0["content"] as! [String: Any]
            content["operator"] = "nobody"
            $0["content"] = content
        }
        #expect(Self.failure {
            try MigrationEnvironmentGuard.decodeReceiptEnvelope(unknownReceipt)
        } == .unknownReceiptField)
        let missingReceiptField = try Self.mutatingObject(receipt) {
            var content = $0["content"] as! [String: Any]
            content.removeValue(forKey: "sourceCredential")
            $0["content"] = content
        }
        #expect(Self.failure {
            try MigrationEnvironmentGuard.decodeReceiptEnvelope(missingReceiptField)
        } == .malformedReceipt)
        let tamperedReceipt = try Self.mutatingObject(receipt) {
            $0["digest"] = String(repeating: "f", count: 64)
        }
        #expect(Self.failure {
            try MigrationEnvironmentGuard.decodeReceiptEnvelope(tamperedReceipt)
        } == .receiptDigestMismatch)
        let wrongReceiptSchema = try Self.mutatingObject(receipt) {
            var content = $0["content"] as! [String: Any]
            content["schemaVersion"] = 2
            $0["content"] = content
        }
        #expect(Self.failure {
            try MigrationEnvironmentGuard.decodeReceiptEnvelope(wrongReceiptSchema)
        } == .receiptSchemaMismatch)
    }

    @Test("MIGENVGUARD-TEST-005 size gates precede decoding and canonical output is bounded")
    func exactSizeGates() throws {
        let fixture = try Self.fixture()
        let request = try MigrationEnvironmentGuard.canonicalRequestData(for: fixture.request)
        #expect(request.count <= MigrationEnvironmentGuard.maximumCanonicalRequestBytes)
        #expect(
            try MigrationEnvironmentGuard.canonicalPolicyContentData(for: fixture.policy).count
                <= MigrationEnvironmentGuard.maximumCanonicalPolicyContentBytes
        )
        let result = try MigrationEnvironmentGuard.validate(requestData: request, policy: fixture.policy)
        let receipt = try MigrationEnvironmentGuard.canonicalReceiptEnvelopeData(for: result.receipt)
        #expect(receipt.count <= MigrationEnvironmentGuard.maximumRawReceiptEnvelopeBytes)

        let exactRawRequest = request + Data(
            repeating: 0x20,
            count: MigrationEnvironmentGuard.maximumRawRequestBytes - request.count
        )
        #expect(
            try MigrationEnvironmentGuard.validate(
                requestData: exactRawRequest,
                policy: fixture.policy
            ).receipt == result.receipt
        )
        let policyEnvelope = try MigrationEnvironmentGuard.canonicalPolicyEnvelopeData(
            for: fixture.policy
        )
        let exactRawPolicy = policyEnvelope + Data(
            repeating: 0x20,
            count: MigrationEnvironmentGuard.maximumRawPolicyEnvelopeBytes - policyEnvelope.count
        )
        #expect(
            try MigrationEnvironmentGuard.decodePolicyEnvelope(exactRawPolicy) == fixture.policy
        )
        let exactRawReceipt = receipt + Data(
            repeating: 0x20,
            count: MigrationEnvironmentGuard.maximumRawReceiptEnvelopeBytes - receipt.count
        )
        #expect(
            try MigrationEnvironmentGuard.decodeReceiptEnvelope(exactRawReceipt) == result.receipt
        )

        try MigrationEnvironmentGuard.enforceCanonicalRequestByteCount(
            MigrationEnvironmentGuard.maximumCanonicalRequestBytes
        )
        try MigrationEnvironmentGuard.enforceCanonicalPolicyContentByteCount(
            MigrationEnvironmentGuard.maximumCanonicalPolicyContentBytes
        )
        try MigrationEnvironmentGuard.enforceCanonicalReceiptContentByteCount(
            MigrationEnvironmentGuard.maximumCanonicalReceiptContentBytes
        )
        #expect(Self.failure {
            try MigrationEnvironmentGuard.enforceCanonicalRequestByteCount(
                MigrationEnvironmentGuard.maximumCanonicalRequestBytes + 1
            )
        } == .canonicalRequestTooLarge)
        #expect(Self.failure {
            try MigrationEnvironmentGuard.enforceCanonicalPolicyContentByteCount(
                MigrationEnvironmentGuard.maximumCanonicalPolicyContentBytes + 1
            )
        } == .canonicalPolicyTooLarge)
        #expect(Self.failure {
            try MigrationEnvironmentGuard.enforceCanonicalReceiptContentByteCount(
                MigrationEnvironmentGuard.maximumCanonicalReceiptContentBytes + 1
            )
        } == .canonicalReceiptTooLarge)

        #expect(
            Self.guardFailure(
                requestData: Data(
                    repeating: 0x20,
                    count: MigrationEnvironmentGuard.maximumRawRequestBytes + 1
                ),
                policy: fixture.policy
            ) == .rawRequestTooLarge
        )
        #expect(Self.failure {
            try MigrationEnvironmentGuard.decodePolicyEnvelope(
                Data(
                    repeating: 0x20,
                    count: MigrationEnvironmentGuard.maximumRawPolicyEnvelopeBytes + 1
                )
            )
        } == .rawPolicyTooLarge)
        #expect(Self.failure {
            try MigrationEnvironmentGuard.decodeReceiptEnvelope(
                Data(
                    repeating: 0x20,
                    count: MigrationEnvironmentGuard.maximumRawReceiptEnvelopeBytes + 1
                )
            )
        } == .rawReceiptTooLarge)

        let planOneByteTooLarge = fixture.request(
            replacingPlan: Data(
                repeating: 0x20,
                count: MigrationRunPlanValidator.maximumCanonicalPlanBytes + 1
            )
        )
        #expect(
            Self.guardFailure(
                requestData: try MigrationEnvironmentGuard.canonicalRequestData(
                    for: planOneByteTooLarge
                ),
                policy: fixture.policy
            ) == .planTooLarge
        )

        let oversizedCanonicalRequest = fixture.request(
            replacingPlan: Data(repeating: 0x20, count: 37_000)
        )
        #expect(Self.failure {
            try MigrationEnvironmentGuard.canonicalRequestData(for: oversizedCanonicalRequest)
        } == .canonicalRequestTooLarge)
    }

    @Test("MIGENVGUARD-TEST-006 evidence exposes no provider or authority material")
    func evidenceIsProviderFreeAndNonAuthoritative() throws {
        let fixture = try Self.fixture()
        let result = try MigrationEnvironmentGuard.validate(
            requestData: MigrationEnvironmentGuard.canonicalRequestData(for: fixture.request),
            policy: fixture.policy
        )
        let evidence = String(
            decoding: try MigrationEnvironmentGuard.canonicalReceiptEnvelopeData(
                for: result.receipt
            ),
            as: UTF8.self
        )
        for forbidden in [
            "path", "url", "provider", "credentialId", "secret", "token", "operator",
            "approval", "production", "hosted", "firebase", "supabase", "powersync"
        ] {
            #expect(!evidence.localizedCaseInsensitiveContains(forbidden))
        }
        #expect(evidence.contains("evidence_only"))
        #expect(result.receipt.content.mode == .dryRun)
    }

    private static let contracts = LedgerContractVersions(
        schema: "1", query: "1", operation: "1", sync: "1"
    )
    private static let createdAt: Int64 = 1_788_000_000_000

    private struct Fixture {
        let source: ValidatedFirebaseSourceFixture
        let target: MigrationTargetBinding
        let policy: MigrationPreflightPolicy
        let plan: MigrationRunPlan
        let planValidator: MigrationRunPlanValidator
        let planData: Data
        let request: MigrationPreflightRequest

        func request(
            replacingPlan: Data? = nil,
            replacingSource: MigrationSourceSnapshot? = nil,
            replacingBundle: MigrationSHA256? = nil,
            replacingTarget: MigrationTargetBinding? = nil,
            replacingAccount: MigrationSHA256? = nil,
            replacingRevision: MigrationSourceRevision? = nil,
            replacingArtifact: MigrationArtifactIdentity? = nil,
            replacingMappings: [MigrationArtifactIdentity]? = nil,
            replacingContracts: LedgerContractVersions? = nil,
            mode: MigrationRunMode = .dryRun,
            sourceCredential: MigrationPreflightCredentialDescriptor = .none,
            targetCredential: MigrationPreflightCredentialDescriptor = .none
        ) -> MigrationPreflightRequest {
            MigrationPreflightRequest(
                canonicalPlanData: replacingPlan ?? planData,
                sourceSnapshot: replacingSource ?? request.sourceSnapshot,
                fixtureBundleSHA256: replacingBundle ?? request.fixtureBundleSHA256,
                targetBinding: replacingTarget ?? request.targetBinding,
                accountScopeSHA256: replacingAccount ?? request.accountScopeSHA256,
                repositoryRevision: replacingRevision ?? request.repositoryRevision,
                migrationArtifact: replacingArtifact ?? request.migrationArtifact,
                mappingArtifacts: replacingMappings ?? request.mappingArtifacts,
                contractVersions: replacingContracts ?? request.contractVersions,
                mode: mode,
                sourceCredential: sourceCredential,
                targetCredential: targetCredential
            )
        }

        func planData(
            replacingSource: MigrationSourceSnapshot? = nil,
            replacingAccount: MigrationSHA256? = nil,
            replacingRevision: MigrationSourceRevision? = nil
        ) throws -> Data {
            let changed = try planValidator.validate(
                MigrationRunPlanDraft(
                    runID: plan.runID,
                    mode: plan.mode,
                    source: replacingSource ?? plan.source,
                    target: plan.target,
                    accountScopeSHA256: replacingAccount ?? plan.accountScopeSHA256,
                    repositoryRevision: replacingRevision ?? plan.repositoryRevision,
                    contractVersions: plan.contractVersions,
                    migrationArtifact: plan.migrationArtifact,
                    mappingArtifacts: plan.mappingArtifacts,
                    entityPlans: plan.entityPlans,
                    createdAtEpochMilliseconds: plan.createdAtEpochMilliseconds
                )
            )
            return try planValidator.canonicalData(for: changed)
        }
    }

    private static func fixture() throws -> Fixture {
        let source = try validatedFixtureFromBundle()
        let sourceSnapshot = source.sourceSnapshot
        let entityPlans = source.entityPlans
        let environment = try Self.environment(seed: "local", kind: .targetLocal)
        let target = try MigrationTargetBinding.make(validatedEnvironment: environment)
        let migrationArtifact = try artifact(id: "migration_bundle", bytes: "migration-v1")
        let mappings = [
            try artifact(id: "account_mapping", bytes: "account-map"),
            try artifact(id: "schema_mapping", bytes: "schema-map")
        ]
        let revision = try MigrationSourceRevision(validating: String(repeating: "a", count: 40))
        let policy = try MigrationPreflightInitialPolicyFactory.make(
            fixture: source,
            target: environment,
            repositoryRevision: revision,
            migrationArtifact: migrationArtifact,
            mappingArtifacts: mappings.reversed()
        )
        let planValidator = MigrationRunPlanValidator(
            policy: MigrationRunPlanPolicy(
                expectedTarget: target,
                expectedContractVersions: contracts,
                expectedMigrationArtifact: migrationArtifact,
                expectedMappingArtifacts: mappings,
                allowedSourceEnvironments: [.sourceFixture],
                allowedModes: [.dryRun]
            )
        )
        let plan = try planValidator.validate(
            MigrationRunPlanDraft(
                runID: try MigrationOpaqueID(
                    validating: String(repeating: "1", count: 32),
                    field: "run"
                ),
                mode: .dryRun,
                source: sourceSnapshot,
                target: target,
                accountScopeSHA256: policy.content.accountScopeSHA256,
                repositoryRevision: revision,
                contractVersions: contracts,
                migrationArtifact: migrationArtifact,
                mappingArtifacts: mappings.reversed(),
                entityPlans: entityPlans,
                createdAtEpochMilliseconds: createdAt
            )
        )
        let planData = try planValidator.canonicalData(for: plan)
        let request = MigrationPreflightRequest(
            canonicalPlanData: planData,
            sourceSnapshot: sourceSnapshot,
            fixtureBundleSHA256: sourceSnapshot.sha256,
            targetBinding: target,
            accountScopeSHA256: policy.content.accountScopeSHA256,
            repositoryRevision: revision,
            migrationArtifact: migrationArtifact,
            mappingArtifacts: mappings,
            contractVersions: contracts
        )
        return Fixture(
            source: source,
            target: target,
            policy: policy,
            plan: plan,
            planValidator: planValidator,
            planData: planData,
            request: request
        )
    }

    private static func validatedFixtureFromBundle() throws -> ValidatedFirebaseSourceFixture {
        let root = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
            .appending(path: "FirebaseSource/v1", directoryHint: .isDirectory)
        let manifest = try Data(contentsOf: root.appending(path: "manifest.json"))
        let files = try FirebaseSourceFixtureCatalog.payloadPaths.map { path in
            FirebaseSourceFixtureFile(
                path: path,
                bytes: try Data(contentsOf: root.appending(path: path))
            )
        }
        return try FirebaseSourceFixtureCatalog().validate(
            manifestEnvelope: manifest,
            files: files
        )
    }

    private static func environment(
        seed: String,
        kind: LedgerEnvironmentKind
    ) throws -> ValidatedLedgerEnvironment {
        let profile: LedgerBuildProfile
        switch kind {
        case .targetLocal: profile = .targetLocalDevelopment
        case .targetStaging: profile = .targetStaging
        case .targetProduction: profile = .targetProductionArchive
        }
        let resources = LedgerTargetComponent.allCases.map {
            LedgerEnvironmentResource(
                component: $0,
                environment: kind,
                publicIdentifier: "\(seed)-\($0.rawValue.lowercased())"
            )
        }
        let manifest = LedgerEnvironmentManifest(
            environment: kind,
            buildProfile: profile,
            bundleIdentifier: "apps.nine4.ledger.\(seed)",
            displayName: kind == .targetStaging ? "Ledger STAGING" : "Ledger Target",
            localDataNamespacePrefix: "ledger.\(seed)",
            contractVersions: contracts,
            resources: resources
        )
        return try LedgerEnvironmentValidator.validate(
            manifest,
            policy: LedgerEnvironmentPolicy(
                expectedEnvironment: kind,
                expectedBuildProfile: profile,
                expectedBundleIdentifier: manifest.bundleIdentifier,
                expectedContractVersions: contracts,
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

    private static func artifact(id: String, bytes: String) throws -> MigrationArtifactIdentity {
        let data = Data(bytes.utf8)
        return try MigrationArtifactIdentity(
            id: MigrationStableCode(validating: id, field: "artifact"),
            version: MigrationVersion(validating: "1", field: "artifact"),
            byteCount: Int64(data.count),
            sha256: .make(bytes: data)
        )
    }

    private static func mutatingObject(
        _ data: Data,
        mutate: (inout [String: Any]) throws -> Void
    ) throws -> Data {
        var object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        try mutate(&object)
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    private static func reordered(_ data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data)
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
    }

    private static func resignedPolicyEnvelope(
        _ policy: MigrationPreflightPolicy,
        mutate: (inout [String: Any]) throws -> Void
    ) throws -> Data {
        let envelope = try MigrationEnvironmentGuard.canonicalPolicyEnvelopeData(for: policy)
        var object = try #require(
            JSONSerialization.jsonObject(with: envelope) as? [String: Any]
        )
        var content = try #require(object["content"] as? [String: Any])
        try mutate(&content)
        object["content"] = content
        let contentData = try JSONSerialization.data(
            withJSONObject: content,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        object["digest"] = Self.digest(
            domain: "ledger.migration-preflight-policy.v1\0",
            content: contentData
        )
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    private static func insertingRootField(
        into data: Data,
        escapedName: String,
        jsonValue: String
    ) throws -> Data {
        let source = String(decoding: data, as: UTF8.self)
        guard source.first == "{" else { throw TestMutationFailure.markerMissing }
        return Data("{\"\(escapedName)\":\(jsonValue),\(source.dropFirst())".utf8)
    }

    private static func insertingNestedField(
        into data: Data,
        objectPrefix: String,
        escapedName: String,
        jsonValue: String
    ) throws -> Data {
        var source = String(decoding: data, as: UTF8.self)
        guard let range = source.range(of: objectPrefix) else {
            throw TestMutationFailure.markerMissing
        }
        source.replaceSubrange(
            range,
            with: "\(objectPrefix)\"\(escapedName)\":\(jsonValue),"
        )
        return Data(source.utf8)
    }

    private enum TestMutationFailure: Error {
        case markerMissing
    }

    private static func digest(domain: String, content: Data) -> String {
        var preimage = Data(domain.utf8)
        var count = UInt64(content.count).bigEndian
        withUnsafeBytes(of: &count) { preimage.append(contentsOf: $0) }
        preimage.append(content)
        return SHA256.hash(data: preimage).map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func failure<T>(
        _ operation: () throws -> T
    ) -> MigrationPreflightFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as MigrationPreflightFailure {
            return failure
        } catch {
            Issue.record("Unexpected error: \(error)")
            return nil
        }
    }

    private static func guardFailure(
        requestData: Data,
        policy: MigrationPreflightPolicy
    ) -> MigrationPreflightFailure? {
        var token: MigrationPreflightConsistencyToken?
        do {
            token = try MigrationEnvironmentGuard.validate(
                requestData: requestData,
                policy: policy
            ).token
            Issue.record("Rejected preflight unexpectedly issued a consistency token")
            return nil
        } catch let failure as MigrationPreflightFailure {
            #expect(token == nil)
            return failure
        } catch {
            #expect(token == nil)
            Issue.record("Unexpected error: \(error)")
            return nil
        }
    }
}
