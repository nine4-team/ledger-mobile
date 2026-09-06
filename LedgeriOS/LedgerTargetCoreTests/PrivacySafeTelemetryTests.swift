import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Privacy-Safe Telemetry and Correlation")
struct PrivacySafeTelemetryTests {
    @Test("The target catalog owns every stable signal and enforces exact bounds")
    func catalogOwnsStableSignalsAndBounds() throws {
        let contractCatalog = try GeneratedTargetContractCatalog.load()
        let catalog = try TargetTelemetrySignalCatalog.make(contractCatalog: contractCatalog)
        let scope = try Self.scope()
        let factory = try Self.factory(scope: scope)
        let session = try factory.session(TelemetrySessionID(validating: "session-private"))

        #expect(catalog.eventIDs == Set(TelemetryEventID.allCases))
        #expect(catalog.metricIDs == Set(TelemetryMetricID.allCases))
        #expect(
            Set(catalog.eventDefinitions.map(\.telemetryClass))
                .isSubset(of: Set(contractCatalog.telemetryClasses.map(\.id)))
        )
        #expect(
            Set(catalog.metricDefinitions.map(\.telemetryClass))
                .isSubset(of: Set(contractCatalog.telemetryClasses.map(\.id)))
        )

        let event = try catalog.makeEvent(
            id: .contractReadCompleted,
            scope: scope,
            observedAt: Self.observedAt,
            dimensions: [
                try Self.dimension(.outcome, "accepted"),
                try Self.dimension(.contractKind, "contract_catalog")
            ],
            correlations: [session]
        )
        #expect(event.id == .contractReadCompleted)
        #expect(event.dimensions.map(\.key) == [.contractKind, .outcome])
        #expect(try catalog.canonicalData(for: event).count <= TelemetrySignalCatalog.maximumCanonicalEnvelopeBytes)

        let metric = try catalog.makeMetricSample(
            id: .syncLagMilliseconds,
            scope: scope,
            observedAt: Self.observedAt,
            unit: .milliseconds,
            value: 42,
            dimensions: [try Self.dimension(.subscriptionReadiness, "ready")],
            correlations: []
        )
        #expect(metric.value == 42)
        #expect(try catalog.decodeMetricSample(from: catalog.canonicalData(for: metric)) == metric)

        var duplicateEvents = try TargetTelemetrySignalCatalog.eventDefinitions()
        duplicateEvents.append(duplicateEvents[0])
        #expect(Self.captureFailure {
            try TelemetrySignalCatalog(
                contractCatalog: contractCatalog,
                eventDefinitions: duplicateEvents,
                metricDefinitions: try TargetTelemetrySignalCatalog.metricDefinitions()
            )
        } == .duplicateEvent(duplicateEvents[0].id))

        var unknownClassEvents = try TargetTelemetrySignalCatalog.eventDefinitions()
        let original = unknownClassEvents[0]
        let unknownClass = try TelemetryClassID(validating: "unknown_telemetry_class")
        unknownClassEvents[0] = TelemetryEventDefinition(
            id: original.id,
            telemetryClass: unknownClass,
            dimensionRules: original.dimensionRules,
            correlationKinds: original.correlationKinds
        )
        #expect(Self.captureFailure {
            try TelemetrySignalCatalog(
                contractCatalog: contractCatalog,
                eventDefinitions: unknownClassEvents,
                metricDefinitions: try TargetTelemetrySignalCatalog.metricDefinitions()
            )
        } == .unknownTelemetryClass(signal: original.id.rawValue, telemetryClass: unknownClass))

        #expect(Self.captureFailure {
            try catalog.makeMetricSample(
                id: .syncLagMilliseconds,
                scope: scope,
                observedAt: Self.observedAt,
                unit: .count,
                value: 1
            )
        } == .metricUnitMismatch(
            metric: .syncLagMilliseconds,
            expected: .milliseconds,
            actual: .count
        ))
        #expect(Self.captureFailure {
            try catalog.makeMetricSample(
                id: .pendingOperationCount,
                scope: scope,
                observedAt: Self.observedAt,
                unit: .count,
                value: 1_000_001
            )
        } == .metricValueOutOfRange(metric: .pendingOperationCount, value: 1_000_001))
    }

    @Test("Canonical envelopes and opaque correlations survive restart without raw identity")
    func canonicalRestartAndOpaqueCorrelation() throws {
        let catalog = try TargetTelemetrySignalCatalog.make(
            contractCatalog: GeneratedTargetContractCatalog.load()
        )
        let scope = try Self.scope()
        let factory = try Self.factory(scope: scope)
        let sessionID = try TelemetrySessionID(validating: "session-private")
        let principalID = try PrincipalID(validating: "principal-private")
        let accountID = try AccountID(validating: "account-private")
        let operationID = try OperationID(validating: "operation-private")
        let entity = LedgerEntityReference(
            kind: .project,
            id: try EntityID(validating: "entity-private")
        )
        let correlations = [
            try factory.operation(operationID),
            try factory.session(sessionID),
            try factory.entity(entity),
            try factory.account(accountID),
            try factory.principal(principalID)
        ]
        let dimensions = [
            try Self.dimension(.operationPhase, "queued"),
            try Self.dimension(.outcome, "accepted")
        ]

        let first = try catalog.makeEvent(
            id: .operationStatusObserved,
            scope: scope,
            observedAt: Self.observedAt,
            dimensions: dimensions,
            correlations: correlations
        )
        let reordered = try catalog.makeEvent(
            id: .operationStatusObserved,
            scope: scope,
            observedAt: Self.observedAt,
            dimensions: dimensions.reversed(),
            correlations: correlations.reversed()
        )
        let firstData = try catalog.canonicalData(for: first)
        let reorderedData = try catalog.canonicalData(for: reordered)
        let restored = try catalog.decodeEvent(from: firstData)

        #expect(first == reordered)
        #expect(firstData == reorderedData)
        #expect(restored == first)
        #expect(first.correlations.map(\.kind) == [.account, .entity, .operation, .principal, .session])

        let encoded = String(decoding: firstData, as: UTF8.self)
        for rawValue in [
            sessionID.rawValue,
            principalID.rawValue,
            accountID.rawValue,
            operationID.rawValue,
            entity.id.rawValue
        ] {
            #expect(!encoded.contains(rawValue))
        }
        #expect(first.correlations.allSatisfy { $0.digest.count == 64 })

        let sameRawSession = try factory.session(TelemetrySessionID(validating: "same-private"))
        let sameRawPrincipal = try factory.principal(PrincipalID(validating: "same-private"))
        let otherKeyFactory = try Self.factory(scope: scope, keyByte: 0x22)
        let otherKeySession = try otherKeyFactory.session(sessionID)
        let otherBuildScope = try Self.scope(buildNumber: 85)
        let otherBuildSession = try Self.factory(scope: otherBuildScope).session(sessionID)
        let localScope = try Self.scope(environment: .targetLocal)
        let localSession = try Self.factory(scope: localScope).session(sessionID)

        #expect(sameRawSession.digest != sameRawPrincipal.digest)
        #expect(try factory.session(sessionID).digest == factory.session(sessionID).digest)
        #expect(otherKeySession.digest != first.correlations.first { $0.kind == .session }?.digest)
        #expect(otherBuildSession.digest != first.correlations.first { $0.kind == .session }?.digest)
        #expect(localSession.digest != first.correlations.first { $0.kind == .session }?.digest)

        #expect(Self.captureFailure {
            try catalog.makeEvent(
                id: .contractReadCompleted,
                scope: scope,
                observedAt: Self.observedAt,
                dimensions: [try Self.dimension(.outcome, "accepted")],
                correlations: [otherBuildSession]
            )
        } == .correlationScopeMismatch(.session))
    }

    @Test("Protected data redacts and disallowed candidates fail without partial envelopes")
    func redactionAndRefusalFailClosed() throws {
        let expected: [(TelemetryDataClass, TelemetryFieldDisposition)] = [
            (.allowlistedDimension, .include),
            (.opaqueCorrelation, .include),
            (.accessToken, .redact(.credentialMaterialRedacted)),
            (.serviceKey, .redact(.credentialMaterialRedacted)),
            (.signedURL, .redact(.signedURLRedacted)),
            (.privateNote, .redact(.privateTextRedacted)),
            (.media, .redact(.mediaRedacted)),
            (.financialValue, .redact(.financialValueRedacted)),
            (.commandPayload, .redact(.commandPayloadRedacted)),
            (.providerMessage, .redact(.providerMessageRedacted)),
            (.rawIdentifier, .refuse(.identifierRequiresOpaqueCorrelation)),
            (.unclassified, .refuse(.unclassifiedValueRefused))
        ]
        for (dataClass, disposition) in expected {
            #expect(TelemetryRedactionPolicy.disposition(for: dataClass) == disposition)
        }

        let contractCatalog = try GeneratedTargetContractCatalog.load()
        let catalog = try TargetTelemetrySignalCatalog.make(contractCatalog: contractCatalog)
        let scope = try Self.scope()
        let factory = try Self.factory(scope: scope)
        let session = try factory.session(TelemetrySessionID(validating: "session-private"))
        let account = try factory.account(AccountID(validating: "account-private"))

        let outcome = try Self.dimension(.outcome, "accepted")
        #expect(Self.captureFailure {
            try catalog.makeEvent(
                id: .contractReadCompleted,
                scope: scope,
                observedAt: Self.observedAt,
                dimensions: [outcome, outcome]
            )
        } == .duplicateDimension(.outcome))
        #expect(Self.captureFailure {
            try catalog.makeEvent(
                id: .contractReadCompleted,
                scope: scope,
                observedAt: Self.observedAt,
                dimensions: [try Self.dimension(.writeBlock, "none")]
            )
        } == .dimensionNotAllowed(
            signal: TelemetryEventID.contractReadCompleted.rawValue,
            key: .writeBlock
        ))
        let unknownOutcome = try Self.dimension(.outcome, "unknown_outcome")
        #expect(Self.captureFailure {
            try catalog.makeEvent(
                id: .contractReadCompleted,
                scope: scope,
                observedAt: Self.observedAt,
                dimensions: [unknownOutcome]
            )
        } == .dimensionValueNotAllowed(
            signal: TelemetryEventID.contractReadCompleted.rawValue,
            key: .outcome,
            value: unknownOutcome.value
        ))
        #expect(Self.captureFailure {
            try catalog.makeEvent(
                id: .contractReadCompleted,
                scope: scope,
                observedAt: Self.observedAt,
                correlations: [account]
            )
        } == .correlationNotAllowed(
            signal: TelemetryEventID.contractReadCompleted.rawValue,
            kind: .account
        ))
        #expect(Self.captureFailure {
            try catalog.makeEvent(
                id: .contractReadCompleted,
                scope: scope,
                observedAt: Self.observedAt,
                correlations: [session, session]
            )
        } == .duplicateCorrelation(.session))
        #expect(Self.captureFailure {
            try catalog.makeEvent(
                id: .contractReadCompleted,
                scope: scope,
                observedAt: Date(timeIntervalSince1970: -1)
            )
        } == .invalidObservedAt)

        var largeEvents = try TargetTelemetrySignalCatalog.eventDefinitions()
        let longCode = try TelemetryDimensionCode(
            validating: "v" + String(repeating: "x", count: 79)
        )
        let operationIndex = try #require(
            largeEvents.firstIndex { $0.id == .operationStatusObserved }
        )
        let operationDefinition = largeEvents[operationIndex]
        largeEvents[operationIndex] = TelemetryEventDefinition(
            id: operationDefinition.id,
            telemetryClass: operationDefinition.telemetryClass,
            dimensionRules: TelemetryDimensionKey.allCases.map {
                TelemetryDimensionRule(key: $0, allowedValues: [longCode])
            },
            correlationKinds: TelemetryCorrelationKind.allCases
        )
        let largeCatalog = try TelemetrySignalCatalog(
            contractCatalog: contractCatalog,
            eventDefinitions: largeEvents,
            metricDefinitions: try TargetTelemetrySignalCatalog.metricDefinitions()
        )
        let largeDimensions = TelemetryDimensionKey.allCases.map {
            TelemetryDimension(key: $0, value: longCode)
        }
        let largeCorrelations = [
            try factory.session(TelemetrySessionID(validating: "session-private")),
            try factory.principal(PrincipalID(validating: "principal-private")),
            try factory.account(AccountID(validating: "account-private")),
            try factory.operation(OperationID(validating: "operation-private")),
            try factory.entity(LedgerEntityReference(
                kind: .item,
                id: EntityID(validating: "entity-private")
            )),
            try factory.syncCheckpoint(
                TelemetrySyncCheckpointID(validating: "checkpoint-private")
            )
        ]
        let largeFailure = Self.captureFailure {
            try largeCatalog.makeEvent(
                id: .operationStatusObserved,
                scope: scope,
                observedAt: Self.observedAt,
                dimensions: largeDimensions,
                correlations: largeCorrelations
            )
        }
        guard case .envelopeTooLarge(let actual, let maximum) = largeFailure else {
            Issue.record("A maximum-shape candidate should exceed the canonical envelope bound")
            return
        }
        #expect(actual > maximum)
        #expect(maximum == TelemetrySignalCatalog.maximumCanonicalEnvelopeBytes)
    }

    @Test("Build and correlation material fail closed before any emittable value exists")
    func buildAndCorrelationMaterialFailClosed() throws {
        #expect(Self.captureFailure {
            try TelemetryApplicationVersion(validating: " https://private.invalid ")
        } == .invalidApplicationVersion)
        #expect(Self.captureFailure {
            try TelemetrySourceRevision(validating: String(repeating: "A", count: 40))
        } == .invalidSourceRevision)
        #expect(Self.captureFailure {
            try TelemetryCorrelationKey(validating: Data(repeating: 0x11, count: 31))
        } == .invalidCorrelationKey)
        #expect(Self.captureFailure {
            try TelemetryCorrelationKey(validating: Data(repeating: 0, count: 32))
        } == .invalidCorrelationKey)

        let validated = try Self.validatedEnvironment()
        #expect(Self.captureFailure {
            try TelemetryBuildScope(
                validatedEnvironment: validated,
                applicationVersion: TelemetryApplicationVersion(validating: "2.0.0"),
                buildNumber: 0,
                sourceRevision: TelemetrySourceRevision(
                    validating: String(repeating: "a", count: 40)
                )
            )
        } == .invalidBuildNumber)

        let unsafeValidated = try Self.validatedEnvironment(
            contractVersions: LedgerContractVersions(
                schema: "1",
                query: "1",
                operation: "access_token=private",
                sync: "1"
            )
        )
        #expect(Self.captureFailure {
            try TelemetryBuildScope(
                validatedEnvironment: unsafeValidated,
                applicationVersion: TelemetryApplicationVersion(validating: "2.0.0"),
                buildNumber: 84,
                sourceRevision: TelemetrySourceRevision(
                    validating: String(repeating: "a", count: 40)
                )
            )
        } == .invalidContractVersion("operation"))
    }

    private static let observedAt = Date(timeIntervalSince1970: 1_788_000_000)

    private static func dimension(
        _ key: TelemetryDimensionKey,
        _ value: String
    ) throws -> TelemetryDimension {
        TelemetryDimension(
            key: key,
            value: try TelemetryDimensionCode(validating: value)
        )
    }

    private static func factory(
        scope: TelemetryBuildScope,
        keyByte: UInt8 = 0x11
    ) throws -> TelemetryCorrelationFactory {
        TelemetryCorrelationFactory(
            key: try TelemetryCorrelationKey(
                validating: Data(repeating: keyByte, count: 32)
            ),
            scope: scope
        )
    }

    private static func scope(
        environment: LedgerEnvironmentKind = .targetStaging,
        buildNumber: UInt64 = 84
    ) throws -> TelemetryBuildScope {
        try TelemetryBuildScope(
            validatedEnvironment: validatedEnvironment(environment: environment),
            applicationVersion: TelemetryApplicationVersion(validating: "2.0.0-beta"),
            buildNumber: buildNumber,
            sourceRevision: TelemetrySourceRevision(
                validating: String(repeating: "a", count: 40)
            )
        )
    }

    private static func validatedEnvironment(
        environment: LedgerEnvironmentKind = .targetStaging,
        contractVersions: LedgerContractVersions = LedgerContractVersions(
            schema: "1",
            query: "1",
            operation: "1",
            sync: "1"
        )
    ) throws -> ValidatedLedgerEnvironment {
        let buildProfile: LedgerBuildProfile = switch environment {
        case .targetLocal:
            .targetLocalDevelopment
        case .targetStaging:
            .targetStaging
        case .targetProduction:
            .targetProductionArchive
        }
        let suffix: String = switch environment {
        case .targetLocal:
            "local"
        case .targetStaging:
            "staging"
        case .targetProduction:
            "production"
        }
        let bundleIdentifier = "apps.nine4.ledger.\(suffix)"
        let displayName = environment == .targetStaging ? "Ledger STAGING" : "Ledger \(suffix.uppercased())"
        let resources = LedgerTargetComponent.allCases.map {
            LedgerEnvironmentResource(
                component: $0,
                environment: environment,
                publicIdentifier: "\($0.rawValue)-\(suffix)"
            )
        }
        let allowedResources = Dictionary(
            uniqueKeysWithValues: resources.map {
                ($0.component, Set([$0.publicIdentifier]))
            }
        )
        let manifest = LedgerEnvironmentManifest(
            environment: environment,
            buildProfile: buildProfile,
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            localDataNamespacePrefix: "ledger-target-\(suffix)",
            contractVersions: contractVersions,
            resources: resources
        )
        let policy = LedgerEnvironmentPolicy(
            expectedEnvironment: environment,
            expectedBuildProfile: buildProfile,
            expectedBundleIdentifier: bundleIdentifier,
            expectedContractVersions: contractVersions,
            allowedResourceIdentifiers: allowedResources,
            forbiddenResourceIdentifiers: [],
            forbiddenBundleIdentifiers: []
        )
        return try LedgerEnvironmentValidator.validate(manifest, policy: policy)
    }

    private static func captureFailure<Value>(
        _ operation: () throws -> Value
    ) -> TelemetryContractFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as TelemetryContractFailure {
            return failure
        } catch {
            return nil
        }
    }
}
