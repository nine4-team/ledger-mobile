import CryptoKit
import Foundation
import LedgerTargetCore

public enum TargetCompositionFailure: Error, Equatable, Sendable {
    case invalidEnvironmentBinding
    case duplicateDependency(TargetCompositionDependencyKey)
    case missingDependency(TargetCompositionDependencyKey)
    case wrongDependencyKey(
        expected: TargetCompositionDependencyKey,
        actual: TargetCompositionDependencyKey
    )
    case dependencyBindingMismatch(TargetCompositionDependencyKey)
    case dependencyUseMismatch(TargetCompositionDependencyKey)
    case dependencyClassMismatch(TargetCompositionDependencyKey)
    case dependencyImplementationMismatch(TargetCompositionDependencyKey)
    case duplicateCapability(CapabilityID)
    case capabilityOwnershipMismatch(TargetCompositionDependencyKey)
    case catalogUnavailable
    case unsupportedCatalogSchema
    case contractVersionMismatch(field: String)
    case duplicateCatalogCapability(CapabilityID)
    case requiredCapabilityUnavailable(String)
    case availableCapabilityUnowned(CapabilityID)
    case invalidEvidence
    case nonCanonicalEvidence
    case evidenceDigestMismatch
    case evidenceTooLarge(actual: Int, maximum: Int)

    public var diagnosticCode: String {
        switch self {
        case .invalidEnvironmentBinding:
            "target_composition_environment_binding_invalid"
        case .duplicateDependency:
            "target_composition_dependency_duplicate"
        case .missingDependency:
            "target_composition_dependency_missing"
        case .wrongDependencyKey:
            "target_composition_dependency_key_mismatch"
        case .dependencyBindingMismatch:
            "target_composition_dependency_environment_mismatch"
        case .dependencyUseMismatch:
            "target_composition_dependency_use_mismatch"
        case .dependencyClassMismatch:
            "target_composition_dependency_class_mismatch"
        case .dependencyImplementationMismatch:
            "target_composition_dependency_implementation_mismatch"
        case .duplicateCapability:
            "target_composition_capability_duplicate"
        case .capabilityOwnershipMismatch:
            "target_composition_capability_ownership_mismatch"
        case .catalogUnavailable:
            "target_composition_catalog_unavailable"
        case .unsupportedCatalogSchema:
            "target_composition_catalog_schema_unsupported"
        case .contractVersionMismatch:
            "target_composition_contract_version_mismatch"
        case .duplicateCatalogCapability:
            "target_composition_catalog_capability_duplicate"
        case .requiredCapabilityUnavailable:
            "target_composition_required_capability_unavailable"
        case .availableCapabilityUnowned:
            "target_composition_available_capability_unowned"
        case .invalidEvidence:
            "target_composition_evidence_invalid"
        case .nonCanonicalEvidence:
            "target_composition_evidence_noncanonical"
        case .evidenceDigestMismatch:
            "target_composition_evidence_digest_mismatch"
        case .evidenceTooLarge:
            "target_composition_evidence_too_large"
        }
    }
}

public enum TargetCompositionUse: String, Codable, CaseIterable, Sendable {
    case testReference
    case applicationRuntime
}

public enum TargetDependencyImplementationClass: String, Codable, CaseIterable, Sendable {
    case referenceAdapter
    case runtimeAdapterCandidate
}

public enum TargetCompositionDependencyKey: String, Codable, CaseIterable, Sendable {
    case contractCatalog
    case operationQueries
    case syncHealth
}

public enum TargetCompositionAuthority: String, Codable, Sendable {
    case structuralOnly
}

public enum TargetDependencyImplementationIDTag: Sendable {}
public typealias TargetDependencyImplementationID = StableCode<TargetDependencyImplementationIDTag>

public struct TargetDependencyDescriptor: Codable, Equatable, Sendable {
    public let key: TargetCompositionDependencyKey
    public let implementationId: TargetDependencyImplementationID
    public let implementationClass: TargetDependencyImplementationClass
    public let use: TargetCompositionUse
    public let environmentBinding: LedgerEnvironmentPersistenceBinding
    public let capabilities: [CapabilityID]

    public init(
        key: TargetCompositionDependencyKey,
        implementationId: TargetDependencyImplementationID,
        implementationClass: TargetDependencyImplementationClass,
        use: TargetCompositionUse,
        environmentBinding: LedgerEnvironmentPersistenceBinding,
        capabilities: [CapabilityID]
    ) throws {
        var seen: Set<CapabilityID> = []
        for capability in capabilities where !seen.insert(capability).inserted {
            throw TargetCompositionFailure.duplicateCapability(capability)
        }
        self.key = key
        self.implementationId = implementationId
        self.implementationClass = implementationClass
        self.use = use
        self.environmentBinding = environmentBinding
        self.capabilities = capabilities.sorted { $0.rawValue < $1.rawValue }
    }

    fileprivate func revalidated() throws -> Self {
        try Self(
            key: key,
            implementationId: implementationId,
            implementationClass: implementationClass,
            use: use,
            environmentBinding: environmentBinding,
            capabilities: capabilities
        )
    }
}

public struct EnvironmentBoundTargetDependency<Value: Sendable>: Sendable {
    public let descriptor: TargetDependencyDescriptor
    public let value: Value

    public init(descriptor: TargetDependencyDescriptor, value: Value) {
        self.descriptor = descriptor
        self.value = value
    }
}

public struct TargetCompositionPlan: Equatable, Sendable {
    public let use: TargetCompositionUse
    public let environmentBinding: LedgerEnvironmentPersistenceBinding
    public let contractVersions: LedgerContractVersions
    public let expectedCatalogVersion: ContractVersion
    public let dependencies: [TargetDependencyDescriptor]

    public init(
        environment: ValidatedLedgerEnvironment,
        use: TargetCompositionUse,
        expectedCatalogVersion: ContractVersion,
        dependencies: [TargetDependencyDescriptor]
    ) throws {
        try self.init(
            use: use,
            environmentBinding: environment.persistenceBinding,
            contractVersions: environment.manifest.contractVersions,
            expectedCatalogVersion: expectedCatalogVersion,
            dependencies: dependencies
        )
    }

    fileprivate init(
        use: TargetCompositionUse,
        environmentBinding: LedgerEnvironmentPersistenceBinding,
        contractVersions: LedgerContractVersions,
        expectedCatalogVersion: ContractVersion,
        dependencies: [TargetDependencyDescriptor]
    ) throws {
        try Self.validateEnvironmentBinding(environmentBinding)
        try Self.validateContractVersions(contractVersions)

        var byKey: [TargetCompositionDependencyKey: TargetDependencyDescriptor] = [:]
        for descriptor in dependencies {
            let descriptor = try descriptor.revalidated()
            guard byKey[descriptor.key] == nil else {
                throw TargetCompositionFailure.duplicateDependency(descriptor.key)
            }
            guard descriptor.environmentBinding == environmentBinding else {
                throw TargetCompositionFailure.dependencyBindingMismatch(descriptor.key)
            }
            guard descriptor.use == use else {
                throw TargetCompositionFailure.dependencyUseMismatch(descriptor.key)
            }
            guard descriptor.implementationClass == Self.requiredClass(for: use) else {
                throw TargetCompositionFailure.dependencyClassMismatch(descriptor.key)
            }
            byKey[descriptor.key] = descriptor
        }

        for key in TargetCompositionDependencyKey.allCases where byKey[key] == nil {
            throw TargetCompositionFailure.missingDependency(key)
        }

        var owned: Set<CapabilityID> = []
        for descriptor in byKey.values {
            for capability in descriptor.capabilities where !owned.insert(capability).inserted {
                throw TargetCompositionFailure.duplicateCapability(capability)
            }
        }
        for descriptor in byKey.values {
            guard Set(descriptor.capabilities.map(\.rawValue)) ==
                    Self.requiredCapabilityNames(for: descriptor.key) else {
                throw TargetCompositionFailure.capabilityOwnershipMismatch(descriptor.key)
            }
        }

        self.use = use
        self.environmentBinding = environmentBinding
        self.contractVersions = contractVersions
        self.expectedCatalogVersion = expectedCatalogVersion
        self.dependencies = byKey.values.sorted { $0.key.rawValue < $1.key.rawValue }
    }

    public func descriptor(
        for key: TargetCompositionDependencyKey
    ) -> TargetDependencyDescriptor {
        // Validation proves the closed key set is complete.
        dependencies.first(where: { $0.key == key })!
    }

    fileprivate static func requiredClass(
        for use: TargetCompositionUse
    ) -> TargetDependencyImplementationClass {
        switch use {
        case .testReference:
            .referenceAdapter
        case .applicationRuntime:
            .runtimeAdapterCandidate
        }
    }

    fileprivate static func requiredCapabilityNames(
        for key: TargetCompositionDependencyKey
    ) -> Set<String> {
        switch key {
        case .contractCatalog:
            ["capability_manifest", "contract_catalog"]
        case .operationQueries:
            ["operation_status"]
        case .syncHealth:
            ["sync_health"]
        }
    }

    fileprivate static var allRequiredCapabilityNames: Set<String> {
        TargetCompositionDependencyKey.allCases.reduce(into: ["environment_manifest"]) {
            $0.formUnion(requiredCapabilityNames(for: $1))
        }
    }

    private static func validateEnvironmentBinding(
        _ binding: LedgerEnvironmentPersistenceBinding
    ) throws {
        let bundle = binding.bundleIdentifier
        let safeBundleCharacters = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-._"))
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        guard !bundle.isEmpty,
              bundle.utf8.count <= 128,
              bundle.unicodeScalars.allSatisfy(safeBundleCharacters.contains),
              binding.manifestDigest.utf8.count == 64,
              binding.manifestDigest.unicodeScalars.allSatisfy(hexadecimal.contains) else {
            throw TargetCompositionFailure.invalidEnvironmentBinding
        }
    }

    private static func validateContractVersions(
        _ versions: LedgerContractVersions
    ) throws {
        for value in [versions.schema, versions.query, versions.operation, versions.sync] {
            do {
                _ = try ContractVersion(validating: value)
            } catch {
                throw TargetCompositionFailure.contractVersionMismatch(field: "invalid")
            }
        }
    }
}

public struct ValidatedTargetComposition: Sendable {
    public let environment: ValidatedLedgerEnvironment
    public let plan: TargetCompositionPlan
    public let contractCatalog: any ContractCatalogProviding
    public let operationQueries: any OperationQuerying
    public let syncHealth: any SyncHealthProviding
    public let receipt: TargetCompositionReceipt

    fileprivate init(
        environment: ValidatedLedgerEnvironment,
        plan: TargetCompositionPlan,
        contractCatalog: any ContractCatalogProviding,
        operationQueries: any OperationQuerying,
        syncHealth: any SyncHealthProviding,
        receipt: TargetCompositionReceipt
    ) {
        self.environment = environment
        self.plan = plan
        self.contractCatalog = contractCatalog
        self.operationQueries = operationQueries
        self.syncHealth = syncHealth
        self.receipt = receipt
    }
}

public enum TargetCompositionAssembler {
    public static func assemble<Catalog, Operations, Health>(
        environment: ValidatedLedgerEnvironment,
        plan: TargetCompositionPlan,
        contractCatalog: EnvironmentBoundTargetDependency<Catalog>,
        operationQueries: EnvironmentBoundTargetDependency<Operations>,
        syncHealth: EnvironmentBoundTargetDependency<Health>
    ) throws -> ValidatedTargetComposition
    where Catalog: ContractCatalogProviding,
          Operations: OperationQuerying,
          Health: SyncHealthProviding {
        guard plan.environmentBinding == environment.persistenceBinding,
              plan.contractVersions == environment.manifest.contractVersions else {
            throw TargetCompositionFailure.invalidEnvironmentBinding
        }

        try validate(
            contractCatalog.descriptor,
            expected: .contractCatalog,
            plan: plan
        )
        try validate(
            operationQueries.descriptor,
            expected: .operationQueries,
            plan: plan
        )
        try validate(
            syncHealth.descriptor,
            expected: .syncHealth,
            plan: plan
        )

        let catalog: VersionedContractCatalog
        do {
            catalog = try contractCatalog.value.catalog()
        } catch {
            throw TargetCompositionFailure.catalogUnavailable
        }
        guard catalog.schemaVersion == 1 else {
            throw TargetCompositionFailure.unsupportedCatalogSchema
        }
        try validateVersions(catalog.versions, against: plan)
        let availableCapabilities = try validateCapabilities(catalog, plan: plan)
        let receipt = try TargetCompositionReceipt(
            plan: plan,
            availableCapabilities: availableCapabilities
        )

        return ValidatedTargetComposition(
            environment: environment,
            plan: plan,
            contractCatalog: contractCatalog.value,
            operationQueries: operationQueries.value,
            syncHealth: syncHealth.value,
            receipt: receipt
        )
    }

    private static func validate(
        _ descriptor: TargetDependencyDescriptor,
        expected key: TargetCompositionDependencyKey,
        plan: TargetCompositionPlan
    ) throws {
        let descriptor = try descriptor.revalidated()
        guard descriptor.key == key else {
            throw TargetCompositionFailure.wrongDependencyKey(
                expected: key,
                actual: descriptor.key
            )
        }
        guard descriptor == plan.descriptor(for: key) else {
            if descriptor.environmentBinding != plan.environmentBinding {
                throw TargetCompositionFailure.dependencyBindingMismatch(key)
            }
            if descriptor.use != plan.use {
                throw TargetCompositionFailure.dependencyUseMismatch(key)
            }
            if descriptor.implementationClass !=
                TargetCompositionPlan.requiredClass(for: plan.use) {
                throw TargetCompositionFailure.dependencyClassMismatch(key)
            }
            if descriptor.implementationId != plan.descriptor(for: key).implementationId {
                throw TargetCompositionFailure.dependencyImplementationMismatch(key)
            }
            throw TargetCompositionFailure.capabilityOwnershipMismatch(key)
        }
    }

    private static func validateVersions(
        _ versions: ContractCatalogVersions,
        against plan: TargetCompositionPlan
    ) throws {
        let expected = plan.contractVersions
        guard versions.catalog == plan.expectedCatalogVersion else {
            throw TargetCompositionFailure.contractVersionMismatch(field: "catalog")
        }
        guard versions.schema.rawValue == expected.schema else {
            throw TargetCompositionFailure.contractVersionMismatch(field: "schema")
        }
        guard versions.query.rawValue == expected.query else {
            throw TargetCompositionFailure.contractVersionMismatch(field: "query")
        }
        guard versions.operation.rawValue == expected.operation else {
            throw TargetCompositionFailure.contractVersionMismatch(field: "operation")
        }
        guard versions.sync.rawValue == expected.sync else {
            throw TargetCompositionFailure.contractVersionMismatch(field: "sync")
        }
    }

    private static func validateCapabilities(
        _ catalog: VersionedContractCatalog,
        plan: TargetCompositionPlan
    ) throws -> [CapabilityID] {
        var catalogByID: [CapabilityID: ContractCapabilityDefinition] = [:]
        for capability in catalog.capabilities {
            guard catalogByID[capability.id] == nil else {
                throw TargetCompositionFailure.duplicateCatalogCapability(capability.id)
            }
            catalogByID[capability.id] = capability
        }

        let available = catalog.capabilities.filter {
            $0.availability == .available
        }
        let availableNames = Set(available.map(\.id.rawValue))
        let expectedNames = TargetCompositionPlan.allRequiredCapabilityNames

        for required in expectedNames where !availableNames.contains(required) {
            throw TargetCompositionFailure.requiredCapabilityUnavailable(required)
        }
        if let unowned = available.first(where: {
            !expectedNames.contains($0.id.rawValue)
        }) {
            throw TargetCompositionFailure.availableCapabilityUnowned(unowned.id)
        }

        for descriptor in plan.dependencies {
            for capability in descriptor.capabilities {
                guard catalogByID[capability]?.availability == .available else {
                    throw TargetCompositionFailure.requiredCapabilityUnavailable(
                        capability.rawValue
                    )
                }
            }
        }

        return available.map(\.id).sorted { $0.rawValue < $1.rawValue }
    }
}

public struct TargetCompositionReceipt: Equatable, Sendable {
    public static let maximumCanonicalEvidenceBytes = 32_768

    public let use: TargetCompositionUse
    public let environmentBinding: LedgerEnvironmentPersistenceBinding
    public let contractVersions: LedgerContractVersions
    public let expectedCatalogVersion: ContractVersion
    public let dependencies: [TargetDependencyDescriptor]
    public let availableCapabilities: [CapabilityID]
    public let authority: TargetCompositionAuthority

    fileprivate init(
        plan: TargetCompositionPlan,
        availableCapabilities: [CapabilityID]
    ) throws {
        let normalizedCapabilities = availableCapabilities.sorted {
            $0.rawValue < $1.rawValue
        }
        guard Set(normalizedCapabilities.map(\.rawValue)) ==
                TargetCompositionPlan.allRequiredCapabilityNames,
              Set(normalizedCapabilities).count == normalizedCapabilities.count else {
            if let unowned = normalizedCapabilities.first(where: {
                !TargetCompositionPlan.allRequiredCapabilityNames.contains($0.rawValue)
            }) {
                throw TargetCompositionFailure.availableCapabilityUnowned(unowned)
            }
            throw TargetCompositionFailure.requiredCapabilityUnavailable("receipt")
        }
        use = plan.use
        environmentBinding = plan.environmentBinding
        contractVersions = plan.contractVersions
        expectedCatalogVersion = plan.expectedCatalogVersion
        dependencies = plan.dependencies
        self.availableCapabilities = normalizedCapabilities
        authority = .structuralOnly
    }

    public func canonicalEvidence() throws -> Data {
        let content = Content(receipt: self)
        let contentBytes = try CanonicalCompositionCodec.encode(content)
        let envelope = Envelope(
            schemaVersion: 1,
            content: content,
            contentDigest: try CanonicalCompositionCodec.digest(contentBytes)
        )
        let data = try CanonicalCompositionCodec.encode(envelope)
        guard data.count <= Self.maximumCanonicalEvidenceBytes else {
            throw TargetCompositionFailure.evidenceTooLarge(
                actual: data.count,
                maximum: Self.maximumCanonicalEvidenceBytes
            )
        }
        return data
    }

    public static func restore(from data: Data) throws -> Self {
        guard data.count <= Self.maximumCanonicalEvidenceBytes else {
            throw TargetCompositionFailure.evidenceTooLarge(
                actual: data.count,
                maximum: Self.maximumCanonicalEvidenceBytes
            )
        }

        let envelope: Envelope
        do {
            envelope = try CanonicalCompositionCodec.decode(Envelope.self, from: data)
        } catch {
            throw TargetCompositionFailure.invalidEvidence
        }
        guard envelope.schemaVersion == 1,
              envelope.content.authority == .structuralOnly else {
            throw TargetCompositionFailure.invalidEvidence
        }
        let contentBytes = try CanonicalCompositionCodec.encode(envelope.content)
        guard try CanonicalCompositionCodec.digest(contentBytes) ==
                envelope.contentDigest else {
            throw TargetCompositionFailure.evidenceDigestMismatch
        }

        let plan = try TargetCompositionPlan(
            use: envelope.content.use,
            environmentBinding: envelope.content.environmentBinding,
            contractVersions: envelope.content.contractVersions,
            expectedCatalogVersion: envelope.content.expectedCatalogVersion,
            dependencies: envelope.content.dependencies
        )
        let receipt = try Self(
            plan: plan,
            availableCapabilities: envelope.content.availableCapabilities
        )
        guard try receipt.canonicalEvidence() == data else {
            throw TargetCompositionFailure.nonCanonicalEvidence
        }
        return receipt
    }

    private struct Content: Codable, Equatable, Sendable {
        let use: TargetCompositionUse
        let environmentBinding: LedgerEnvironmentPersistenceBinding
        let contractVersions: LedgerContractVersions
        let expectedCatalogVersion: ContractVersion
        let dependencies: [TargetDependencyDescriptor]
        let availableCapabilities: [CapabilityID]
        let authority: TargetCompositionAuthority

        init(receipt: TargetCompositionReceipt) {
            use = receipt.use
            environmentBinding = receipt.environmentBinding
            contractVersions = receipt.contractVersions
            expectedCatalogVersion = receipt.expectedCatalogVersion
            dependencies = receipt.dependencies
            availableCapabilities = receipt.availableCapabilities
            authority = receipt.authority
        }
    }

    private struct Envelope: Codable, Equatable, Sendable {
        let schemaVersion: Int
        let content: Content
        let contentDigest: OperationFingerprint
    }
}

private enum CanonicalCompositionCodec {
    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    static func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data
    ) throws -> Value {
        try JSONDecoder().decode(type, from: data)
    }

    static func digest(_ data: Data) throws -> OperationFingerprint {
        let value = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        return try OperationFingerprint(validating: value)
    }
}
