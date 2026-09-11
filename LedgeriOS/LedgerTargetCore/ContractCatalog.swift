import CryptoKit
import Foundation

public enum ContractCatalogFailure: Error, Equatable, Sendable {
    case duplicateEnum(String)
    case duplicateEnumValue(enumName: String, value: String)
    case duplicateAuthorizationPolicy(String)
    case duplicateTelemetryClass(String)
    case duplicateError(ApplicationErrorCode)
    case duplicateCapability(CapabilityID)
    case duplicateContract(ContractID)
    case duplicateDeprecation(ContractID)
    case unknownAuthorizationPolicy(entry: String, policy: AuthorizationPolicyID)
    case unknownTelemetryClass(entry: String, telemetryClass: TelemetryClassID)
    case unknownCapability(contract: ContractID, capability: CapabilityID)
    case unknownError(contract: ContractID, error: ApplicationErrorCode)
    case invalidDeprecation(ContractID)
    case catalogHashMismatch
}

public enum ContractIDTag: Sendable {}
public enum AuthorizationPolicyIDTag: Sendable {}
public enum TelemetryClassIDTag: Sendable {}
public enum ContractVersionTag: Sendable {}

public typealias ContractID = StableCode<ContractIDTag>
public typealias AuthorizationPolicyID = StableCode<AuthorizationPolicyIDTag>
public typealias TelemetryClassID = StableCode<TelemetryClassIDTag>
public typealias ContractVersion = LedgerIdentifier<ContractVersionTag>

public struct ContractCatalogVersions: Codable, Equatable, Sendable {
    public let catalog: ContractVersion
    public let schema: ContractVersion
    public let query: ContractVersion
    public let operation: ContractVersion
    public let sync: ContractVersion
}

public struct ContractEnumDefinition: Codable, Equatable, Sendable {
    public let name: String
    public let values: [String]
}

public struct AuthorizationPolicyDefinition: Codable, Equatable, Sendable {
    public let id: AuthorizationPolicyID
    public let description: String
}

public struct TelemetryClassDefinition: Codable, Equatable, Sendable {
    public let id: TelemetryClassID
    public let description: String
}

public struct ContractErrorDefinition: Codable, Equatable, Sendable {
    public let code: ApplicationErrorCode
    public let category: ApplicationErrorCategory
    public let retryDisposition: RetryDisposition
}

public enum CapabilityAvailability: String, Codable, CaseIterable, Sendable {
    case available
    case gated
    case deprecated
}

public struct ContractCapabilityDefinition: Codable, Equatable, Sendable {
    public let id: CapabilityID
    public let version: ContractVersion
    public let availability: CapabilityAvailability
    public let authorizationPolicy: AuthorizationPolicyID
    public let telemetryClass: TelemetryClassID
    public let testOwner: String
}

public enum ContractEntryKind: String, Codable, CaseIterable, Sendable {
    case operation
    case query
    case resource
}

public struct ContractDeprecationReference: Codable, Equatable, Sendable {
    public let replacement: ContractID?
    public let minimumClientVersion: ContractVersion
}

public struct ContractEntryDefinition: Codable, Equatable, Sendable {
    public let id: ContractID
    public let kind: ContractEntryKind
    public let version: ContractVersion
    public let capability: CapabilityID
    public let authorizationPolicy: AuthorizationPolicyID
    public let resultContract: String
    public let errorCodes: [ApplicationErrorCode]
    public let telemetryClass: TelemetryClassID
    public let testOwner: String
    public let deprecation: ContractDeprecationReference?
}

public struct ContractDeprecationDefinition: Codable, Equatable, Sendable {
    public let contract: ContractID
    public let replacement: ContractID?
    public let minimumClientVersion: ContractVersion
}

public struct VersionedContractCatalog: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let versions: ContractCatalogVersions
    public let enums: [ContractEnumDefinition]
    public let authorizationPolicies: [AuthorizationPolicyDefinition]
    public let telemetryClasses: [TelemetryClassDefinition]
    public let errors: [ContractErrorDefinition]
    public let capabilities: [ContractCapabilityDefinition]
    public let contracts: [ContractEntryDefinition]
    public let deprecations: [ContractDeprecationDefinition]
}

public enum ContractCatalogValidator {
    public static func validate(
        _ catalog: VersionedContractCatalog,
        canonicalData: Data,
        expectedSHA256: String
    ) throws {
        let actualHash = SHA256.hash(data: canonicalData)
            .map { String(format: "%02x", $0) }
            .joined()
        guard actualHash == expectedSHA256 else {
            throw ContractCatalogFailure.catalogHashMismatch
        }

        try unique(catalog.enums.map(\.name)) {
            ContractCatalogFailure.duplicateEnum($0)
        }
        for enumDefinition in catalog.enums {
            try unique(enumDefinition.values) {
                ContractCatalogFailure.duplicateEnumValue(
                    enumName: enumDefinition.name,
                    value: $0
                )
            }
        }

        try unique(catalog.authorizationPolicies.map(\.id)) {
            ContractCatalogFailure.duplicateAuthorizationPolicy($0.rawValue)
        }
        try unique(catalog.telemetryClasses.map(\.id)) {
            ContractCatalogFailure.duplicateTelemetryClass($0.rawValue)
        }
        try unique(catalog.errors.map(\.code)) {
            ContractCatalogFailure.duplicateError($0)
        }
        try unique(catalog.capabilities.map(\.id)) {
            ContractCatalogFailure.duplicateCapability($0)
        }
        try unique(catalog.contracts.map(\.id)) {
            ContractCatalogFailure.duplicateContract($0)
        }
        try unique(catalog.deprecations.map(\.contract)) {
            ContractCatalogFailure.duplicateDeprecation($0)
        }

        let authorizationPolicyIDs = Set(catalog.authorizationPolicies.map(\.id))
        let telemetryClassIDs = Set(catalog.telemetryClasses.map(\.id))
        let errorCodes = Set(catalog.errors.map(\.code))
        let capabilityIDs = Set(catalog.capabilities.map(\.id))
        let contractIDs = Set(catalog.contracts.map(\.id))
        let deprecationsByContract = Dictionary(
            uniqueKeysWithValues: catalog.deprecations.map { ($0.contract, $0) }
        )

        for capability in catalog.capabilities {
            guard authorizationPolicyIDs.contains(capability.authorizationPolicy) else {
                throw ContractCatalogFailure.unknownAuthorizationPolicy(
                    entry: capability.id.rawValue,
                    policy: capability.authorizationPolicy
                )
            }
            guard telemetryClassIDs.contains(capability.telemetryClass) else {
                throw ContractCatalogFailure.unknownTelemetryClass(
                    entry: capability.id.rawValue,
                    telemetryClass: capability.telemetryClass
                )
            }
        }

        for contract in catalog.contracts {
            guard capabilityIDs.contains(contract.capability) else {
                throw ContractCatalogFailure.unknownCapability(
                    contract: contract.id,
                    capability: contract.capability
                )
            }
            guard authorizationPolicyIDs.contains(contract.authorizationPolicy) else {
                throw ContractCatalogFailure.unknownAuthorizationPolicy(
                    entry: contract.id.rawValue,
                    policy: contract.authorizationPolicy
                )
            }
            guard telemetryClassIDs.contains(contract.telemetryClass) else {
                throw ContractCatalogFailure.unknownTelemetryClass(
                    entry: contract.id.rawValue,
                    telemetryClass: contract.telemetryClass
                )
            }
            for errorCode in contract.errorCodes where !errorCodes.contains(errorCode) {
                throw ContractCatalogFailure.unknownError(
                    contract: contract.id,
                    error: errorCode
                )
            }
            let listedDeprecation = deprecationsByContract[contract.id]
            switch (contract.deprecation, listedDeprecation) {
            case (nil, nil):
                break
            case let (.some(deprecation), .some(listed)):
                guard deprecation.replacement != contract.id,
                      deprecation.replacement.map({ contractIDs.contains($0) }) ?? true,
                      deprecation.replacement == listed.replacement,
                      deprecation.minimumClientVersion == listed.minimumClientVersion else {
                    throw ContractCatalogFailure.invalidDeprecation(contract.id)
                }
            default:
                throw ContractCatalogFailure.invalidDeprecation(contract.id)
            }
        }

        for deprecation in catalog.deprecations {
            guard contractIDs.contains(deprecation.contract),
                  deprecation.replacement != deprecation.contract,
                  deprecation.replacement.map({ contractIDs.contains($0) }) ?? true else {
                throw ContractCatalogFailure.invalidDeprecation(deprecation.contract)
            }
        }
    }

    private static func unique<Value: Hashable>(
        _ values: [Value],
        failure: (Value) -> ContractCatalogFailure
    ) throws {
        var seen: Set<Value> = []
        for value in values where !seen.insert(value).inserted {
            throw failure(value)
        }
    }
}

public protocol ContractCatalogProviding: Sendable {
    func catalog() throws -> VersionedContractCatalog
}
