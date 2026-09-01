import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Generated Target Contract Catalog")
struct GeneratedContractCatalogTests {
    @Test("Generated catalog loads with one validated canonical hash")
    func generatedCatalogLoads() throws {
        let catalog = try GeneratedTargetContractCatalog.load()

        #expect(catalog.schemaVersion == 1)
        #expect(GeneratedTargetContractCatalog.sha256.count == 64)
        #expect(catalog.versions.catalog.rawValue == "1")
        #expect(catalog.versions.schema.rawValue == "1")
        #expect(catalog.versions.query.rawValue == "1")
        #expect(catalog.versions.operation.rawValue == "1")
        #expect(catalog.versions.sync.rawValue == "1")
        #expect(!catalog.capabilities.isEmpty)
        #expect(!catalog.contracts.isEmpty)
    }

    @Test("Generated enum registries exactly match runtime contracts")
    func enumRegistryMatchesRuntime() throws {
        let catalog = try GeneratedTargetContractCatalog.load()

        try Self.expectValues(
            "LedgerEnvironmentKind",
            equal: LedgerEnvironmentKind.allCases.map(\.rawValue),
            in: catalog
        )
        try Self.expectValues(
            "OperationPhase",
            equal: OperationPhase.allCases.map(\.rawValue),
            in: catalog
        )
        try Self.expectValues(
            "ApplicationErrorCategory",
            equal: ApplicationErrorCategory.allCases.map(\.rawValue),
            in: catalog
        )
        try Self.expectValues(
            "RetryDisposition",
            equal: RetryDisposition.allCases.map(\.rawValue),
            in: catalog
        )
        try Self.expectValues(
            "ConnectivityState",
            equal: ConnectivityState.allCases.map(\.rawValue),
            in: catalog
        )
        try Self.expectValues(
            "AuthenticationRefreshState",
            equal: AuthenticationRefreshState.allCases.map(\.rawValue),
            in: catalog
        )
        try Self.expectValues(
            "SubscriptionReadinessState",
            equal: SubscriptionReadinessState.allCases.map(\.rawValue),
            in: catalog
        )
        try Self.expectValues(
            "SyncWriteBlock",
            equal: SyncWriteBlock.allCases.map(\.rawValue),
            in: catalog
        )
    }

    @Test("Every advertised contract has explicit security, error, telemetry, version, and test ownership")
    func registrationIsComplete() throws {
        let catalog = try GeneratedTargetContractCatalog.load()
        let policies = Set(catalog.authorizationPolicies.map(\.id))
        let telemetryClasses = Set(catalog.telemetryClasses.map(\.id))
        let capabilities = Set(catalog.capabilities.map(\.id))
        let errorCodes = Set(catalog.errors.map(\.code))

        for capability in catalog.capabilities {
            #expect(policies.contains(capability.authorizationPolicy))
            #expect(telemetryClasses.contains(capability.telemetryClass))
            #expect(!capability.testOwner.isEmpty)
        }

        for contract in catalog.contracts {
            #expect(capabilities.contains(contract.capability))
            #expect(policies.contains(contract.authorizationPolicy))
            #expect(telemetryClasses.contains(contract.telemetryClass))
            #expect(!contract.errorCodes.isEmpty)
            #expect(contract.errorCodes.allSatisfy(errorCodes.contains))
            #expect(!contract.resultContract.isEmpty)
            #expect(!contract.testOwner.isEmpty)
        }
    }

    @Test("The initial catalog advertises only implemented platform capabilities")
    func catalogDoesNotAdvertiseUnapprovedProductCommands() throws {
        let catalog = try GeneratedTargetContractCatalog.load()
        let capabilityIDs = Set(catalog.capabilities.map(\.id.rawValue))
        let contractIDs = Set(catalog.contracts.map(\.id.rawValue))

        #expect(capabilityIDs == [
            "capability_manifest",
            "contract_catalog",
            "environment_manifest",
            "operation_status",
            "sync_health"
        ])
        #expect(contractIDs == [
            "get_capabilities",
            "get_contract_catalog",
            "observe_sync_health",
            "validate_environment_manifest",
            "watch_operation",
            "watch_unresolved_operations"
        ])
        #expect(catalog.deprecations.isEmpty)
    }

    @Test("Catalog metadata contains no provider, credential, or persistence schema leakage")
    func catalogMetadataIsBounded() throws {
        let catalog = try GeneratedTargetContractCatalog.load()
        let data = try OperationContractCodec.encode(catalog)
        let text = String(decoding: data, as: UTF8.self).lowercased()
        let forbidden = [
            "firebase",
            "firestore",
            "supabase",
            "powersync",
            "postgres",
            "service_role",
            "api_key",
            "password",
            "access_token",
            "refresh_token"
        ]

        #expect(forbidden.allSatisfy { !text.contains($0) })
        #expect(data.count < 64 * 1024)
    }

    @Test("A noncanonical catalog hash fails closed")
    func hashMismatchFailsClosed() throws {
        let catalog = try GeneratedTargetContractCatalog.load()
        let noncanonicalData = try OperationContractCodec.encode(catalog)
        let failure = Self.captureFailure {
            try ContractCatalogValidator.validate(
                catalog,
                canonicalData: noncanonicalData,
                expectedSHA256: GeneratedTargetContractCatalog.sha256
            )
        }

        #expect(failure == .catalogHashMismatch)
    }

    private static func expectValues(
        _ enumName: String,
        equal expected: [String],
        in catalog: VersionedContractCatalog
    ) throws {
        let definition = try #require(catalog.enums.first { $0.name == enumName })
        #expect(definition.values == expected)
    }

    private static func captureFailure(
        _ operation: () throws -> Void
    ) -> ContractCatalogFailure? {
        do {
            try operation()
            return nil
        } catch let failure as ContractCatalogFailure {
            return failure
        } catch {
            return nil
        }
    }
}
