import Foundation
import LedgerTargetCore

package enum MigrationPreflightCredentialDescriptor: String, Codable, Sendable {
    case none
    case present
}

package enum MigrationPreflightFailure: Error, Equatable, Sendable {
    case rawRequestTooLarge
    case canonicalRequestTooLarge
    case malformedRequest
    case unknownRequestField
    case duplicateRequestField
    case requestSchemaMismatch
    case planBase64Invalid
    case planTooLarge
    case planInvalid
    case planDigestMismatch
    case planNoncanonical
    case rawPolicyTooLarge
    case canonicalPolicyTooLarge
    case malformedPolicy
    case unknownPolicyField
    case duplicatePolicyField
    case policySchemaMismatch
    case policyDigestMismatch
    case policyInvalid
    case sourceMismatch
    case fixtureBundleMismatch
    case targetMismatch
    case accountScopeMismatch
    case repositoryRevisionMismatch
    case migrationArtifactMismatch
    case mappingArtifactSetMismatch
    case contractVersionMismatch
    case unsafeMode
    case credentialMismatch
    case rawReceiptTooLarge
    case canonicalReceiptTooLarge
    case malformedReceipt
    case unknownReceiptField
    case duplicateReceiptField
    case receiptSchemaMismatch
    case receiptDigestMismatch
    case receiptInvalid

    package var diagnosticCode: String {
        switch self {
        case .rawRequestTooLarge: "migration_preflight_request_raw_too_large"
        case .canonicalRequestTooLarge: "migration_preflight_request_canonical_too_large"
        case .malformedRequest: "migration_preflight_request_malformed"
        case .unknownRequestField: "migration_preflight_request_unknown_field"
        case .duplicateRequestField: "migration_preflight_request_duplicate_field"
        case .requestSchemaMismatch: "migration_preflight_request_schema_mismatch"
        case .planBase64Invalid: "migration_preflight_plan_base64_invalid"
        case .planTooLarge: "migration_preflight_plan_too_large"
        case .planInvalid: "migration_preflight_plan_invalid"
        case .planDigestMismatch: "migration_preflight_plan_digest_mismatch"
        case .planNoncanonical: "migration_preflight_plan_noncanonical"
        case .rawPolicyTooLarge: "migration_preflight_policy_raw_too_large"
        case .canonicalPolicyTooLarge: "migration_preflight_policy_canonical_too_large"
        case .malformedPolicy: "migration_preflight_policy_malformed"
        case .unknownPolicyField: "migration_preflight_policy_unknown_field"
        case .duplicatePolicyField: "migration_preflight_policy_duplicate_field"
        case .policySchemaMismatch: "migration_preflight_policy_schema_mismatch"
        case .policyDigestMismatch: "migration_preflight_policy_digest_mismatch"
        case .policyInvalid: "migration_preflight_policy_invalid"
        case .sourceMismatch: "migration_preflight_source_mismatch"
        case .fixtureBundleMismatch: "migration_preflight_fixture_bundle_mismatch"
        case .targetMismatch: "migration_preflight_target_mismatch"
        case .accountScopeMismatch: "migration_preflight_account_scope_mismatch"
        case .repositoryRevisionMismatch: "migration_preflight_repository_revision_mismatch"
        case .migrationArtifactMismatch: "migration_preflight_artifact_mismatch"
        case .mappingArtifactSetMismatch: "migration_preflight_mapping_artifact_set_mismatch"
        case .contractVersionMismatch: "migration_preflight_contract_version_mismatch"
        case .unsafeMode: "migration_preflight_mode_unsafe"
        case .credentialMismatch: "migration_preflight_credential_mismatch"
        case .rawReceiptTooLarge: "migration_preflight_receipt_raw_too_large"
        case .canonicalReceiptTooLarge: "migration_preflight_receipt_canonical_too_large"
        case .malformedReceipt: "migration_preflight_receipt_malformed"
        case .unknownReceiptField: "migration_preflight_receipt_unknown_field"
        case .duplicateReceiptField: "migration_preflight_receipt_duplicate_field"
        case .receiptSchemaMismatch: "migration_preflight_receipt_schema_mismatch"
        case .receiptDigestMismatch: "migration_preflight_receipt_digest_mismatch"
        case .receiptInvalid: "migration_preflight_receipt_invalid"
        }
    }
}

package struct MigrationPreflightRequest: Codable, Equatable, Sendable {
    package let schemaVersion: Int
    package let canonicalPlanBase64: String
    package let sourceSnapshot: MigrationSourceSnapshot
    package let fixtureBundleSHA256: MigrationSHA256
    package let targetBinding: MigrationTargetBinding
    package let accountScopeSHA256: MigrationSHA256
    package let repositoryRevision: MigrationSourceRevision
    package let migrationArtifact: MigrationArtifactIdentity
    package let mappingArtifacts: [MigrationArtifactIdentity]
    package let contractVersions: LedgerContractVersions
    package let mode: MigrationRunMode
    package let sourceCredential: MigrationPreflightCredentialDescriptor
    package let targetCredential: MigrationPreflightCredentialDescriptor
    package let authorityDisposition: MigrationAuthorityDisposition

    package init(
        canonicalPlanData: Data,
        sourceSnapshot: MigrationSourceSnapshot,
        fixtureBundleSHA256: MigrationSHA256,
        targetBinding: MigrationTargetBinding,
        accountScopeSHA256: MigrationSHA256,
        repositoryRevision: MigrationSourceRevision,
        migrationArtifact: MigrationArtifactIdentity,
        mappingArtifacts: [MigrationArtifactIdentity],
        contractVersions: LedgerContractVersions,
        mode: MigrationRunMode = .dryRun,
        sourceCredential: MigrationPreflightCredentialDescriptor = .none,
        targetCredential: MigrationPreflightCredentialDescriptor = .none
    ) {
        schemaVersion = MigrationEnvironmentGuard.schemaVersion
        canonicalPlanBase64 = canonicalPlanData.base64EncodedString()
        self.sourceSnapshot = sourceSnapshot
        self.fixtureBundleSHA256 = fixtureBundleSHA256
        self.targetBinding = targetBinding
        self.accountScopeSHA256 = accountScopeSHA256
        self.repositoryRevision = repositoryRevision
        self.migrationArtifact = migrationArtifact
        self.mappingArtifacts = mappingArtifacts
        self.contractVersions = contractVersions
        self.mode = mode
        self.sourceCredential = sourceCredential
        self.targetCredential = targetCredential
        authorityDisposition = .evidenceOnly
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, canonicalPlanBase64, sourceSnapshot, fixtureBundleSHA256
        case targetBinding, accountScopeSHA256, repositoryRevision, migrationArtifact
        case mappingArtifacts, contractVersions, mode, sourceCredential, targetCredential
        case authorityDisposition
    }

    package init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        canonicalPlanBase64 = try values.decode(String.self, forKey: .canonicalPlanBase64)
        sourceSnapshot = try values.decode(MigrationSourceSnapshot.self, forKey: .sourceSnapshot)
        fixtureBundleSHA256 = try values.decode(MigrationSHA256.self, forKey: .fixtureBundleSHA256)
        targetBinding = try values.decode(MigrationTargetBinding.self, forKey: .targetBinding)
        accountScopeSHA256 = try values.decode(MigrationSHA256.self, forKey: .accountScopeSHA256)
        repositoryRevision = try values.decode(MigrationSourceRevision.self, forKey: .repositoryRevision)
        migrationArtifact = try values.decode(MigrationArtifactIdentity.self, forKey: .migrationArtifact)
        mappingArtifacts = try values.decode([MigrationArtifactIdentity].self, forKey: .mappingArtifacts)
        contractVersions = try values.decode(LedgerContractVersions.self, forKey: .contractVersions)
        mode = try values.decodeIfPresent(MigrationRunMode.self, forKey: .mode) ?? .dryRun
        sourceCredential = try values.decode(MigrationPreflightCredentialDescriptor.self, forKey: .sourceCredential)
        targetCredential = try values.decode(MigrationPreflightCredentialDescriptor.self, forKey: .targetCredential)
        authorityDisposition = try values.decode(MigrationAuthorityDisposition.self, forKey: .authorityDisposition)
    }
}

package struct MigrationPreflightPolicyContent: Codable, Equatable, Sendable {
    package let schemaVersion: Int
    package let sourceSnapshot: MigrationSourceSnapshot
    package let fixtureBundleSHA256: MigrationSHA256
    package let targetBinding: MigrationTargetBinding
    package let accountScopeSHA256: MigrationSHA256
    package let repositoryRevision: MigrationSourceRevision
    package let migrationArtifact: MigrationArtifactIdentity
    package let mappingArtifacts: [MigrationArtifactIdentity]
    package let contractVersions: LedgerContractVersions
    package let mode: MigrationRunMode
    package let sourceCredential: MigrationPreflightCredentialDescriptor
    package let targetCredential: MigrationPreflightCredentialDescriptor
    package let authorityDisposition: MigrationAuthorityDisposition
}

package struct MigrationPreflightPolicy: Codable, Equatable, Sendable {
    package let content: MigrationPreflightPolicyContent
    package let digest: MigrationSHA256

    private init(content: MigrationPreflightPolicyContent, digest: MigrationSHA256) {
        self.content = content
        self.digest = digest
    }

    fileprivate static func issue(
        content: MigrationPreflightPolicyContent,
        digest: MigrationSHA256
    ) -> Self {
        Self(content: content, digest: digest)
    }
}

package struct MigrationPreflightReceiptContent: Codable, Equatable, Sendable {
    package let schemaVersion: Int
    package let planDigest: MigrationSHA256
    package let policyDigest: MigrationSHA256
    package let fixtureBundleDigest: MigrationSHA256
    package let targetManifestDigest: MigrationSHA256
    package let accountScopeSHA256: MigrationSHA256
    package let sourceEnvironment: MigrationSourceEnvironment
    package let targetEnvironment: LedgerEnvironmentKind
    package let mode: MigrationRunMode
    package let sourceCredential: MigrationPreflightCredentialDescriptor
    package let targetCredential: MigrationPreflightCredentialDescriptor
    package let authorityDisposition: MigrationAuthorityDisposition
}

package struct MigrationPreflightReceipt: Codable, Equatable, Sendable {
    package let content: MigrationPreflightReceiptContent
    package let digest: MigrationSHA256
}

package struct MigrationPreflightConsistencyToken: Equatable, Sendable {
    package let planDigest: MigrationSHA256
    package let policyDigest: MigrationSHA256
    package let receiptDigest: MigrationSHA256
    package let fixtureBundleDigest: MigrationSHA256
    package let targetManifestDigest: MigrationSHA256
    package let accountScopeSHA256: MigrationSHA256

    private init(
        planDigest: MigrationSHA256,
        policyDigest: MigrationSHA256,
        receiptDigest: MigrationSHA256,
        fixtureBundleDigest: MigrationSHA256,
        targetManifestDigest: MigrationSHA256,
        accountScopeSHA256: MigrationSHA256
    ) {
        self.planDigest = planDigest
        self.policyDigest = policyDigest
        self.receiptDigest = receiptDigest
        self.fixtureBundleDigest = fixtureBundleDigest
        self.targetManifestDigest = targetManifestDigest
        self.accountScopeSHA256 = accountScopeSHA256
    }

    fileprivate static func issue(receipt: MigrationPreflightReceipt) -> Self {
        Self(
            planDigest: receipt.content.planDigest,
            policyDigest: receipt.content.policyDigest,
            receiptDigest: receipt.digest,
            fixtureBundleDigest: receipt.content.fixtureBundleDigest,
            targetManifestDigest: receipt.content.targetManifestDigest,
            accountScopeSHA256: receipt.content.accountScopeSHA256
        )
    }
}

package struct MigrationPreflightResult: Sendable {
    package let receipt: MigrationPreflightReceipt
    package let token: MigrationPreflightConsistencyToken
}

package enum MigrationPreflightAccountScope {
    /// The schema-v1 Account-scope digest is the direct SHA-256 of the
    /// authenticated opaque Account identifier's UTF-8 bytes.
    package static func sha256(
        authenticatedAccountScopeID: MigrationOpaqueID
    ) throws -> MigrationSHA256 {
        try MigrationSHA256.make(bytes: Data(authenticatedAccountScopeID.rawValue.utf8))
    }
}

package enum MigrationPreflightInitialPolicyFactory {
    package static func make(
        fixture: ValidatedFirebaseSourceFixture,
        target: ValidatedLedgerEnvironment,
        repositoryRevision: MigrationSourceRevision,
        migrationArtifact: MigrationArtifactIdentity,
        mappingArtifacts: [MigrationArtifactIdentity]
    ) throws -> MigrationPreflightPolicy {
        guard fixture.sourceSnapshot.environment == .sourceFixture,
              fixture.authorityDisposition == .evidenceOnly,
              target.manifest.environment == .targetLocal else {
            throw MigrationPreflightFailure.policyInvalid
        }
        let content = MigrationPreflightPolicyContent(
            schemaVersion: MigrationEnvironmentGuard.schemaVersion,
            sourceSnapshot: fixture.sourceSnapshot,
            fixtureBundleSHA256: fixture.sourceSnapshot.sha256,
            targetBinding: try MigrationTargetBinding.make(validatedEnvironment: target),
            accountScopeSHA256: try MigrationPreflightAccountScope.sha256(
                authenticatedAccountScopeID: fixture.accountScopeID
            ),
            repositoryRevision: repositoryRevision,
            migrationArtifact: migrationArtifact,
            mappingArtifacts: try MigrationEnvironmentGuard.sortedUniqueMappings(mappingArtifacts),
            contractVersions: target.manifest.contractVersions,
            mode: .dryRun,
            sourceCredential: .none,
            targetCredential: .none,
            authorityDisposition: .evidenceOnly
        )
        return try MigrationEnvironmentGuard.makePolicy(content: content)
    }
}

package enum MigrationEnvironmentGuard {
    package static let schemaVersion = 1
    package static let maximumRawRequestBytes = 65_536
    package static let maximumCanonicalRequestBytes = 49_152
    package static let maximumRawPolicyEnvelopeBytes = 33_024
    package static let maximumCanonicalPolicyContentBytes = 32_768
    package static let maximumRawReceiptEnvelopeBytes = 4_352
    package static let maximumCanonicalReceiptContentBytes = 4_096

    private static let policyDigestDomain = Data(
        "ledger.migration-preflight-policy.v1\0".utf8
    )
    private static let receiptDigestDomain = Data(
        "ledger.migration-preflight-receipt.v1\0".utf8
    )

    package static func canonicalRequestData(
        for request: MigrationPreflightRequest
    ) throws -> Data {
        let data = try canonicalEncode(request)
        try enforceCanonicalRequestByteCount(data.count)
        return data
    }

    package static func canonicalPolicyContentData(
        for policy: MigrationPreflightPolicy
    ) throws -> Data {
        let data = try canonicalEncode(policy.content)
        try enforceCanonicalPolicyContentByteCount(data.count)
        return data
    }

    package static func canonicalPolicyEnvelopeData(
        for policy: MigrationPreflightPolicy
    ) throws -> Data {
        _ = try validatePolicy(policy)
        let data = try canonicalEncode(policy)
        guard data.count <= maximumRawPolicyEnvelopeBytes else {
            throw MigrationPreflightFailure.rawPolicyTooLarge
        }
        return data
    }

    package static func decodePolicyEnvelope(
        _ data: Data
    ) throws -> MigrationPreflightPolicy {
        guard data.count <= maximumRawPolicyEnvelopeBytes else {
            throw MigrationPreflightFailure.rawPolicyTooLarge
        }
        try validateJSONShape(data, kind: .policy)
        let policy: MigrationPreflightPolicy
        do {
            policy = try JSONDecoder().decode(MigrationPreflightPolicy.self, from: data)
        } catch {
            throw MigrationPreflightFailure.malformedPolicy
        }
        _ = try validatePolicy(policy)
        return policy
    }

    package static func canonicalReceiptEnvelopeData(
        for receipt: MigrationPreflightReceipt
    ) throws -> Data {
        _ = try validateReceipt(receipt)
        let data = try canonicalEncode(receipt)
        guard data.count <= maximumRawReceiptEnvelopeBytes else {
            throw MigrationPreflightFailure.rawReceiptTooLarge
        }
        return data
    }

    package static func enforceCanonicalRequestByteCount(_ byteCount: Int) throws {
        guard byteCount >= 0, byteCount <= maximumCanonicalRequestBytes else {
            throw MigrationPreflightFailure.canonicalRequestTooLarge
        }
    }

    package static func enforceCanonicalPolicyContentByteCount(_ byteCount: Int) throws {
        guard byteCount >= 0, byteCount <= maximumCanonicalPolicyContentBytes else {
            throw MigrationPreflightFailure.canonicalPolicyTooLarge
        }
    }

    package static func enforceCanonicalReceiptContentByteCount(_ byteCount: Int) throws {
        guard byteCount >= 0, byteCount <= maximumCanonicalReceiptContentBytes else {
            throw MigrationPreflightFailure.canonicalReceiptTooLarge
        }
    }

    package static func decodeReceiptEnvelope(
        _ data: Data
    ) throws -> MigrationPreflightReceipt {
        guard data.count <= maximumRawReceiptEnvelopeBytes else {
            throw MigrationPreflightFailure.rawReceiptTooLarge
        }
        try validateJSONShape(data, kind: .receipt)
        let receipt: MigrationPreflightReceipt
        do {
            receipt = try JSONDecoder().decode(MigrationPreflightReceipt.self, from: data)
        } catch {
            throw MigrationPreflightFailure.malformedReceipt
        }
        _ = try validateReceipt(receipt)
        return receipt
    }

    package static func validate(
        requestData: Data,
        policy: MigrationPreflightPolicy
    ) throws -> MigrationPreflightResult {
        guard requestData.count <= maximumRawRequestBytes else {
            throw MigrationPreflightFailure.rawRequestTooLarge
        }
        try validateJSONShape(requestData, kind: .request)

        let request: MigrationPreflightRequest
        do {
            request = try JSONDecoder().decode(MigrationPreflightRequest.self, from: requestData)
        } catch {
            throw MigrationPreflightFailure.malformedRequest
        }
        guard request.schemaVersion == schemaVersion else {
            throw MigrationPreflightFailure.requestSchemaMismatch
        }
        _ = try canonicalRequestData(for: request)
        let policyContent = try validatePolicy(policy)

        guard request.sourceSnapshot.environment == .sourceFixture,
              policyContent.sourceSnapshot.environment == .sourceFixture else {
            throw MigrationPreflightFailure.sourceMismatch
        }
        guard request.targetBinding.environment == .targetLocal,
              policyContent.targetBinding.environment == .targetLocal else {
            throw MigrationPreflightFailure.targetMismatch
        }
        guard request.mode == .dryRun, policyContent.mode == .dryRun else {
            throw MigrationPreflightFailure.unsafeMode
        }
        guard request.sourceCredential == .none,
              request.targetCredential == .none,
              policyContent.sourceCredential == .none,
              policyContent.targetCredential == .none else {
            throw MigrationPreflightFailure.credentialMismatch
        }
        guard request.authorityDisposition == .evidenceOnly else {
            throw MigrationPreflightFailure.policyInvalid
        }

        guard request.sourceSnapshot == policyContent.sourceSnapshot else {
            throw MigrationPreflightFailure.sourceMismatch
        }
        guard request.fixtureBundleSHA256 == request.sourceSnapshot.sha256,
              request.fixtureBundleSHA256 == policyContent.fixtureBundleSHA256 else {
            throw MigrationPreflightFailure.fixtureBundleMismatch
        }
        guard request.targetBinding == policyContent.targetBinding else {
            throw MigrationPreflightFailure.targetMismatch
        }
        guard request.accountScopeSHA256 == policyContent.accountScopeSHA256 else {
            throw MigrationPreflightFailure.accountScopeMismatch
        }
        guard request.repositoryRevision == policyContent.repositoryRevision else {
            throw MigrationPreflightFailure.repositoryRevisionMismatch
        }
        guard request.migrationArtifact == policyContent.migrationArtifact else {
            throw MigrationPreflightFailure.migrationArtifactMismatch
        }
        guard request.mappingArtifacts == policyContent.mappingArtifacts else {
            throw MigrationPreflightFailure.mappingArtifactSetMismatch
        }
        guard request.contractVersions == policyContent.contractVersions else {
            throw MigrationPreflightFailure.contractVersionMismatch
        }

        guard let planData = strictBase64Data(request.canonicalPlanBase64) else {
            throw MigrationPreflightFailure.planBase64Invalid
        }
        guard planData.count <= MigrationRunPlanValidator.maximumCanonicalPlanBytes else {
            throw MigrationPreflightFailure.planTooLarge
        }
        let planValidator = MigrationRunPlanValidator(
            policy: MigrationRunPlanPolicy(
                expectedTarget: policyContent.targetBinding,
                expectedContractVersions: policyContent.contractVersions,
                expectedMigrationArtifact: policyContent.migrationArtifact,
                expectedMappingArtifacts: policyContent.mappingArtifacts,
                allowedSourceEnvironments: [.sourceFixture],
                allowedModes: [.dryRun]
            )
        )
        let plan: MigrationRunPlan
        do {
            plan = try planValidator.decodeAndValidate(planData)
        } catch let failure as MigrationIntegrityFailure {
            throw mapPlanFailure(failure)
        } catch {
            throw MigrationPreflightFailure.planInvalid
        }

        guard plan.source == request.sourceSnapshot else {
            throw MigrationPreflightFailure.sourceMismatch
        }
        guard plan.target == request.targetBinding else {
            throw MigrationPreflightFailure.targetMismatch
        }
        guard plan.accountScopeSHA256 == request.accountScopeSHA256 else {
            throw MigrationPreflightFailure.accountScopeMismatch
        }
        guard plan.repositoryRevision == request.repositoryRevision else {
            throw MigrationPreflightFailure.repositoryRevisionMismatch
        }
        guard plan.migrationArtifact == request.migrationArtifact else {
            throw MigrationPreflightFailure.migrationArtifactMismatch
        }
        guard plan.mappingArtifacts == request.mappingArtifacts else {
            throw MigrationPreflightFailure.mappingArtifactSetMismatch
        }
        guard plan.contractVersions == request.contractVersions else {
            throw MigrationPreflightFailure.contractVersionMismatch
        }
        guard plan.mode == request.mode else {
            throw MigrationPreflightFailure.unsafeMode
        }

        let receiptContent = MigrationPreflightReceiptContent(
            schemaVersion: schemaVersion,
            planDigest: plan.contentDigest,
            policyDigest: policy.digest,
            fixtureBundleDigest: request.fixtureBundleSHA256,
            targetManifestDigest: request.targetBinding.environmentManifestSHA256,
            accountScopeSHA256: request.accountScopeSHA256,
            sourceEnvironment: .sourceFixture,
            targetEnvironment: .targetLocal,
            mode: .dryRun,
            sourceCredential: .none,
            targetCredential: .none,
            authorityDisposition: .evidenceOnly
        )
        let contentData = try canonicalEncode(receiptContent)
        try enforceCanonicalReceiptContentByteCount(contentData.count)
        let receipt = MigrationPreflightReceipt(
            content: receiptContent,
            digest: try digest(domain: receiptDigestDomain, canonicalContent: contentData)
        )
        return MigrationPreflightResult(receipt: receipt, token: .issue(receipt: receipt))
    }

    fileprivate static func makePolicy(
        content: MigrationPreflightPolicyContent
    ) throws -> MigrationPreflightPolicy {
        let data = try canonicalEncode(content)
        try enforceCanonicalPolicyContentByteCount(data.count)
        let policy = MigrationPreflightPolicy.issue(
            content: content,
            digest: try digest(domain: policyDigestDomain, canonicalContent: data)
        )
        _ = try validatePolicy(policy)
        return policy
    }

    fileprivate static func sortedUniqueMappings(
        _ mappings: [MigrationArtifactIdentity]
    ) throws -> [MigrationArtifactIdentity] {
        guard !mappings.isEmpty,
              mappings.count <= MigrationRunPlanValidator.maximumMappingArtifacts else {
            throw MigrationPreflightFailure.policyInvalid
        }
        let sorted = mappings.sorted { $0.id < $1.id }
        guard Set(sorted.map(\.id)).count == sorted.count,
              sorted.allSatisfy({ $0.byteCount > 0 }) else {
            throw MigrationPreflightFailure.policyInvalid
        }
        return sorted
    }

    private static func validatePolicy(
        _ policy: MigrationPreflightPolicy
    ) throws -> MigrationPreflightPolicyContent {
        let content = policy.content
        guard content.schemaVersion == schemaVersion else {
            throw MigrationPreflightFailure.policySchemaMismatch
        }
        guard content.sourceSnapshot.environment == .sourceFixture,
              content.sourceSnapshot.capturedAtEpochMilliseconds > 0,
              content.sourceSnapshot.byteCount > 0,
              content.fixtureBundleSHA256 == content.sourceSnapshot.sha256,
              content.targetBinding.environment == .targetLocal,
              content.mode == .dryRun,
              content.sourceCredential == .none,
              content.targetCredential == .none,
              content.authorityDisposition == .evidenceOnly,
              content.migrationArtifact.byteCount > 0 else {
            throw MigrationPreflightFailure.policyInvalid
        }
        guard try sortedUniqueMappings(content.mappingArtifacts) == content.mappingArtifacts else {
            throw MigrationPreflightFailure.policyInvalid
        }
        do {
            _ = try MigrationVersion(validating: content.contractVersions.schema, field: "schema")
            _ = try MigrationVersion(validating: content.contractVersions.query, field: "query")
            _ = try MigrationVersion(validating: content.contractVersions.operation, field: "operation")
            _ = try MigrationVersion(validating: content.contractVersions.sync, field: "sync")
        } catch {
            throw MigrationPreflightFailure.policyInvalid
        }
        let data = try canonicalPolicyContentData(for: policy)
        guard policy.digest == (try digest(domain: policyDigestDomain, canonicalContent: data)) else {
            throw MigrationPreflightFailure.policyDigestMismatch
        }
        return content
    }

    private static func validateReceipt(
        _ receipt: MigrationPreflightReceipt
    ) throws -> MigrationPreflightReceiptContent {
        let content = receipt.content
        guard content.schemaVersion == schemaVersion else {
            throw MigrationPreflightFailure.receiptSchemaMismatch
        }
        guard content.sourceEnvironment == .sourceFixture,
              content.targetEnvironment == .targetLocal,
              content.mode == .dryRun,
              content.sourceCredential == .none,
              content.targetCredential == .none,
              content.authorityDisposition == .evidenceOnly else {
            throw MigrationPreflightFailure.receiptInvalid
        }
        let data = try canonicalEncode(content)
        try enforceCanonicalReceiptContentByteCount(data.count)
        guard receipt.digest == (try digest(domain: receiptDigestDomain, canonicalContent: data)) else {
            throw MigrationPreflightFailure.receiptDigestMismatch
        }
        return content
    }

    private static func strictBase64Data(_ value: String) -> Data? {
        guard !value.isEmpty,
              value.utf8.count.isMultiple(of: 4),
              let data = Data(base64Encoded: value),
              data.base64EncodedString() == value else {
            return nil
        }
        return data
    }

    private static func mapPlanFailure(
        _ failure: MigrationIntegrityFailure
    ) -> MigrationPreflightFailure {
        switch failure {
        case .planDigestMismatch: .planDigestMismatch
        case .noncanonicalPlan: .planNoncanonical
        case .planTooLarge: .planTooLarge
        case .sourceEnvironmentNotAllowed: .sourceMismatch
        case .runModeNotAllowed: .unsafeMode
        case .targetEnvironmentMismatch, .targetBindingMismatch: .targetMismatch
        case .contractVersionInvalid, .contractVersionMismatch: .contractVersionMismatch
        case .migrationArtifactMismatch: .migrationArtifactMismatch
        case .mappingArtifactSetMismatch: .mappingArtifactSetMismatch
        default: .planInvalid
        }
    }

    private static func canonicalEncode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func digest(
        domain: Data,
        canonicalContent: Data
    ) throws -> MigrationSHA256 {
        var preimage = domain
        var count = UInt64(canonicalContent.count).bigEndian
        withUnsafeBytes(of: &count) { preimage.append(contentsOf: $0) }
        preimage.append(canonicalContent)
        return try MigrationSHA256.make(bytes: preimage)
    }

    private enum JSONShape {
        case request
        case policy
        case receipt
    }

    private enum JSONShapeFailure: Error {
        case unknown
        case duplicate
        case malformed
    }

    private static func validateJSONShape(_ data: Data, kind: JSONShape) throws {
        do {
            var scanner = DuplicateAwareJSONScanner(data: data)
            try scanner.validate()
        } catch JSONShapeFailure.duplicate {
            switch kind {
            case .request: throw MigrationPreflightFailure.duplicateRequestField
            case .policy: throw MigrationPreflightFailure.duplicatePolicyField
            case .receipt: throw MigrationPreflightFailure.duplicateReceiptField
            }
        } catch {
            throw malformedFailure(for: kind)
        }

        let root: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw JSONShapeFailure.malformed
            }
            root = object
        } catch {
            throw malformedFailure(for: kind)
        }

        do {
            switch kind {
            case .request:
                try requireKeys(
                    root,
                    required: [
                        "schemaVersion", "canonicalPlanBase64", "sourceSnapshot",
                        "fixtureBundleSHA256", "targetBinding", "accountScopeSHA256",
                        "repositoryRevision", "migrationArtifact", "mappingArtifacts",
                        "contractVersions", "sourceCredential", "targetCredential",
                        "authorityDisposition"
                    ],
                    optional: ["mode"]
                )
                try validateEvidenceShapes(root)
                if let mode = root["mode"], !(mode is String) {
                    throw JSONShapeFailure.malformed
                }
            case .policy:
                try requireKeys(root, required: ["content", "digest"])
                guard let content = root["content"] as? [String: Any] else {
                    throw JSONShapeFailure.malformed
                }
                try requireKeys(
                    content,
                    required: [
                        "schemaVersion", "sourceSnapshot", "fixtureBundleSHA256",
                        "targetBinding", "accountScopeSHA256", "repositoryRevision",
                        "migrationArtifact", "mappingArtifacts", "contractVersions", "mode",
                        "sourceCredential", "targetCredential", "authorityDisposition"
                    ]
                )
                try validateEvidenceShapes(content)
            case .receipt:
                try requireKeys(root, required: ["content", "digest"])
                guard let content = root["content"] as? [String: Any] else {
                    throw JSONShapeFailure.malformed
                }
                try requireKeys(
                    content,
                    required: [
                        "schemaVersion", "planDigest", "policyDigest", "fixtureBundleDigest",
                        "targetManifestDigest", "accountScopeSHA256", "sourceEnvironment",
                        "targetEnvironment", "mode", "sourceCredential", "targetCredential",
                        "authorityDisposition"
                    ]
                )
            }
        } catch JSONShapeFailure.unknown {
            switch kind {
            case .request: throw MigrationPreflightFailure.unknownRequestField
            case .policy: throw MigrationPreflightFailure.unknownPolicyField
            case .receipt: throw MigrationPreflightFailure.unknownReceiptField
            }
        } catch {
            throw malformedFailure(for: kind)
        }
    }

    private static func requireKeys(
        _ object: [String: Any],
        required: Set<String>,
        optional: Set<String> = []
    ) throws {
        let actual = Set(object.keys)
        guard actual.isSubset(of: required.union(optional)) else {
            throw JSONShapeFailure.unknown
        }
        guard required.isSubset(of: actual) else {
            throw JSONShapeFailure.malformed
        }
    }

    private static func validateEvidenceShapes(_ object: [String: Any]) throws {
        guard let source = object["sourceSnapshot"] as? [String: Any],
              let target = object["targetBinding"] as? [String: Any],
              let artifact = object["migrationArtifact"] as? [String: Any],
              let mappings = object["mappingArtifacts"] as? [[String: Any]],
              let contracts = object["contractVersions"] as? [String: Any] else {
            throw JSONShapeFailure.malformed
        }
        try requireKeys(
            source,
            required: ["environment", "exportID", "capturedAtEpochMilliseconds", "byteCount", "sha256"]
        )
        try requireKeys(
            target,
            required: [
                "environment", "environmentManifestSHA256", "structuredDataResourceSHA256",
                "storageResourceSHA256"
            ]
        )
        try requireKeys(artifact, required: ["id", "version", "byteCount", "sha256"])
        for mapping in mappings {
            try requireKeys(mapping, required: ["id", "version", "byteCount", "sha256"])
        }
        try requireKeys(contracts, required: ["schema", "query", "operation", "sync"])
    }

    private static func malformedFailure(for kind: JSONShape) -> MigrationPreflightFailure {
        switch kind {
        case .request: .malformedRequest
        case .policy: .malformedPolicy
        case .receipt: .malformedReceipt
        }
    }

    private struct DuplicateAwareJSONScanner {
        private static let maximumDepth = 64

        private let bytes: [UInt8]
        private var index = 0

        init(data: Data) {
            bytes = Array(data)
        }

        mutating func validate() throws {
            skipWhitespace()
            try parseValue(depth: 0)
            skipWhitespace()
            guard index == bytes.count else { throw JSONShapeFailure.malformed }
        }

        private mutating func parseValue(depth: Int) throws {
            guard depth <= Self.maximumDepth, index < bytes.count else {
                throw JSONShapeFailure.malformed
            }
            switch bytes[index] {
            case 0x7b: try parseObject(depth: depth + 1) // {
            case 0x5b: try parseArray(depth: depth + 1) // [
            case 0x22: _ = try parseString()
            case 0x74: try consume("true")
            case 0x66: try consume("false")
            case 0x6e: try consume("null")
            case 0x2d, 0x30...0x39: try parseNumber()
            default: throw JSONShapeFailure.malformed
            }
        }

        private mutating func parseObject(depth: Int) throws {
            index += 1
            skipWhitespace()
            if consumeIf(0x7d) { return }

            var keys: Set<String> = []
            while true {
                guard index < bytes.count, bytes[index] == 0x22 else {
                    throw JSONShapeFailure.malformed
                }
                let key = try parseString()
                guard keys.insert(key).inserted else {
                    throw JSONShapeFailure.duplicate
                }
                skipWhitespace()
                guard consumeIf(0x3a) else { throw JSONShapeFailure.malformed } // :
                skipWhitespace()
                try parseValue(depth: depth)
                skipWhitespace()
                if consumeIf(0x7d) { return }
                guard consumeIf(0x2c) else { throw JSONShapeFailure.malformed } // ,
                skipWhitespace()
            }
        }

        private mutating func parseArray(depth: Int) throws {
            index += 1
            skipWhitespace()
            if consumeIf(0x5d) { return }
            while true {
                try parseValue(depth: depth)
                skipWhitespace()
                if consumeIf(0x5d) { return }
                guard consumeIf(0x2c) else { throw JSONShapeFailure.malformed }
                skipWhitespace()
            }
        }

        private mutating func parseString() throws -> String {
            let start = index
            index += 1
            var escaped = false
            while index < bytes.count {
                let byte = bytes[index]
                if escaped {
                    if byte == 0x75 { // u
                        guard index + 4 < bytes.count else {
                            throw JSONShapeFailure.malformed
                        }
                        for offset in 1...4 where !Self.isHex(bytes[index + offset]) {
                            throw JSONShapeFailure.malformed
                        }
                        index += 5
                    } else {
                        guard [0x22, 0x5c, 0x2f, 0x62, 0x66, 0x6e, 0x72, 0x74].contains(byte) else {
                            throw JSONShapeFailure.malformed
                        }
                        index += 1
                    }
                    escaped = false
                    continue
                }
                if byte == 0x5c {
                    escaped = true
                    index += 1
                    continue
                }
                if byte == 0x22 {
                    index += 1
                    let literal = Data(bytes[start..<index])
                    do {
                        return try JSONDecoder().decode(String.self, from: literal)
                    } catch {
                        throw JSONShapeFailure.malformed
                    }
                }
                guard byte >= 0x20 else { throw JSONShapeFailure.malformed }
                index += 1
            }
            throw JSONShapeFailure.malformed
        }

        private mutating func parseNumber() throws {
            if consumeIf(0x2d), index == bytes.count { throw JSONShapeFailure.malformed }
            if consumeIf(0x30) {
                if index < bytes.count, (0x30...0x39).contains(bytes[index]) {
                    throw JSONShapeFailure.malformed
                }
            } else {
                guard index < bytes.count, (0x31...0x39).contains(bytes[index]) else {
                    throw JSONShapeFailure.malformed
                }
                repeat { index += 1 } while index < bytes.count && (0x30...0x39).contains(bytes[index])
            }
            if consumeIf(0x2e) {
                guard index < bytes.count, (0x30...0x39).contains(bytes[index]) else {
                    throw JSONShapeFailure.malformed
                }
                repeat { index += 1 } while index < bytes.count && (0x30...0x39).contains(bytes[index])
            }
            if index < bytes.count && (bytes[index] == 0x65 || bytes[index] == 0x45) {
                index += 1
                if index < bytes.count && (bytes[index] == 0x2b || bytes[index] == 0x2d) {
                    index += 1
                }
                guard index < bytes.count, (0x30...0x39).contains(bytes[index]) else {
                    throw JSONShapeFailure.malformed
                }
                repeat { index += 1 } while index < bytes.count && (0x30...0x39).contains(bytes[index])
            }
        }

        private mutating func consume(_ literal: StaticString) throws {
            let expected = Array(String(describing: literal).utf8)
            guard index + expected.count <= bytes.count,
                  Array(bytes[index..<(index + expected.count)]) == expected else {
                throw JSONShapeFailure.malformed
            }
            index += expected.count
        }

        private mutating func consumeIf(_ byte: UInt8) -> Bool {
            guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1
            return true
        }

        private mutating func skipWhitespace() {
            while index < bytes.count,
                  bytes[index] == 0x20 || bytes[index] == 0x09 ||
                  bytes[index] == 0x0a || bytes[index] == 0x0d {
                index += 1
            }
        }

        private static func isHex(_ byte: UInt8) -> Bool {
            (0x30...0x39).contains(byte) ||
                (0x41...0x46).contains(byte) ||
                (0x61...0x66).contains(byte)
        }
    }
}
