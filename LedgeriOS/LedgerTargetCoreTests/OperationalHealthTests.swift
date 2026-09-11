import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Operational Health and Objective Registry")
struct OperationalHealthTests {
    @Test("Registry and health preserve exact operational truth")
    func registryAndHealthPreserveExactTruth() throws {
        let registryValidator = OperationalControlRegistryValidator()
        let registry = try TargetOperationalControlRegistry.make()

        #expect(registry.schemaVersion == OperationalControlRegistryValidator.schemaVersion)
        #expect(registry.measurements.count == OperationalMeasurementID.allCases.count)
        #expect(registry.objectives.count == ServiceObjectiveID.allCases.count)
        #expect(registry.alerts.count == AlertCandidateID.allCases.count)
        #expect(registry.runbooks.count == OperationalRunbookID.allCases.count)
        #expect(registry.performanceBudgets.count == ProvisionalPerformanceBudgetID.allCases.count)
        #expect(Set(registry.measurements.map(\.id)) == Set(OperationalMeasurementID.allCases))
        #expect(Set(registry.objectives.map(\.id)) == Set(ServiceObjectiveID.allCases))
        #expect(Set(registry.alerts.map(\.id)) == Set(AlertCandidateID.allCases))
        #expect(Set(registry.runbooks.map(\.id)) == Set(OperationalRunbookID.allCases))
        #expect(Set(registry.performanceBudgets.map(\.id)) == Set(ProvisionalPerformanceBudgetID.allCases))
        #expect(registry.policyAuthority == .candidateOnly)
        #expect(registry.authorityDisposition == .evidenceOnly)
        #expect(registry.alerts.allSatisfy { $0.authority == .candidateOnly })
        #expect(registry.objectives.allSatisfy { $0.threshold == .exactZero })
        #expect(registry.objectives.allSatisfy { objective in
            registry.alerts.contains { $0.objectives.contains(objective.id) }
        })
        #expect(registry.performanceBudgets.allSatisfy { $0.status == .pendingVerticalSpike })
        #expect(registry.runbooks.allSatisfy(Self.runbookIsComplete))

        let measurements = Dictionary(uniqueKeysWithValues: registry.measurements.map {
            ($0.id, $0)
        })
        #expect(measurements[.failedAttachmentCount]?.collectionState == .planned)
        #expect(measurements[.authRefreshFailureCount]?.collectionState == .planned)
        #expect(measurements[.postgresCPUUtilization]?.unit == .basisPoints)
        #expect(measurements[.postgresConnectionCount]?.unit == .count)
        #expect(measurements[.postgresDiskBytes]?.unit == .bytes)
        #expect(measurements[.postgresIOBytes]?.unit == .bytes)
        #expect(measurements[.targetDatabaseAvailabilityState]?.unit == .state)
        #expect(measurements[.targetStorageAvailabilityState]?.unit == .state)

        let unassessed = try registryValidator.unassessedObjectives(in: registry)
        #expect(unassessed.count == ServiceObjectiveID.allCases.count)
        #expect(unassessed.allSatisfy { $0.status == .notEvaluated })
        #expect(unassessed.allSatisfy { $0.evidence.isEmpty && $0.evidenceDigest == nil })
        #expect(unassessed.allSatisfy { !$0.missingMeasurements.isEmpty })

        let zeroEvidence = try Self.evidence(
            measurement: .lostAcceptedOperationCount,
            observedValue: 0
        )
        let satisfied = try registryValidator.evaluate(
            .durability,
            evidence: [zeroEvidence],
            in: registry
        )
        #expect(satisfied.status == .satisfied)
        #expect(satisfied.missingMeasurements.isEmpty)
        #expect(satisfied.evidenceDigest != nil)

        let nonzeroEvidence = try Self.evidence(
            measurement: .lostAcceptedOperationCount,
            observedValue: 1
        )
        let violated = try registryValidator.evaluate(
            .durability,
            evidence: [nonzeroEvidence],
            in: registry
        )
        #expect(violated.status == .violated)

        let healthValidator = OperationalHealthValidator()
        let offline = try healthValidator.validate(
            OperationalHealthDraft(
                syncHealth: Self.syncHealth(
                    connectivity: .offline,
                    subscriptionState: .ready,
                    checkpoint: Self.observedAt.addingTimeInterval(-30),
                    pendingOperationCount: 1,
                    oldestPendingOperationAt: Self.observedAt.addingTimeInterval(-20),
                    pendingAttachmentCount: 1,
                    oldestPendingAttachmentAt: Self.observedAt.addingTimeInterval(-10)
                ),
                observedAt: Self.observedAt
            )
        )
        #expect(offline.isOnline == false)
        #expect(offline.isSynchronized == true)
        #expect(offline.overallState == .readyOffline)
        #expect(offline.lastCheckpointAgeMilliseconds == 30_000)
        #expect(offline.oldestPendingOperationAgeMilliseconds == 20_000)
        #expect(offline.oldestPendingAttachmentAgeMilliseconds == 10_000)
        #expect(offline.authorityDisposition == .evidenceOnly)
        #expect(Self.component(.connectivity, in: offline)?.state == .offline)
        #expect(Self.component(.connectivity, in: offline)?.action == .continueOffline)
        #expect(Self.component(.operationQueue, in: offline)?.state == .waiting)

        let onlineUnsynchronized = try healthValidator.validate(
            OperationalHealthDraft(
                syncHealth: Self.syncHealth(
                    connectivity: .online,
                    subscriptionState: .loading,
                    checkpoint: nil
                ),
                observedAt: Self.observedAt
            )
        )
        #expect(onlineUnsynchronized.isOnline == true)
        #expect(onlineUnsynchronized.isSynchronized == false)
        #expect(onlineUnsynchronized.overallState == .synchronizing)
        #expect(Self.component(.connectivity, in: onlineUnsynchronized)?.state == .healthy)
        #expect(Self.component(.subscriptions, in: onlineUnsynchronized)?.state == .synchronizing)
        #expect(Self.component(.replicationCheckpoint, in: onlineUnsynchronized)?.state == .unavailable)
    }

    @Test("Canonical health and registry evidence restore offline")
    func canonicalEvidenceRestoresOffline() throws {
        let registryValidator = OperationalControlRegistryValidator()
        let originalDraft = try TargetOperationalControlRegistry.draft()
        let firstRegistry = try registryValidator.validate(originalDraft)
        let reorderedRegistry = try registryValidator.validate(
            OperationalControlRegistryDraft(
                measurements: originalDraft.measurements.reversed(),
                objectives: originalDraft.objectives.reversed(),
                alerts: originalDraft.alerts.reversed(),
                runbooks: originalDraft.runbooks.reversed(),
                performanceBudgets: originalDraft.performanceBudgets.reversed()
            )
        )
        let firstRegistryData = try registryValidator.canonicalData(for: firstRegistry)
        let reorderedRegistryData = try registryValidator.canonicalData(for: reorderedRegistry)
        #expect(firstRegistry == reorderedRegistry)
        #expect(firstRegistryData == reorderedRegistryData)
        #expect(try registryValidator.decodeAndValidate(firstRegistryData) == firstRegistry)

        let healthValidator = OperationalHealthValidator()
        let offline = try healthValidator.validate(
            OperationalHealthDraft(
                syncHealth: Self.syncHealth(
                    connectivity: .offline,
                    subscriptionState: .ready,
                    checkpoint: Self.observedAt.addingTimeInterval(-60)
                ),
                observedAt: Self.observedAt
            )
        )
        let offlineData = try healthValidator.canonicalData(for: offline)
        #expect(try healthValidator.decodeAndValidate(offlineData) == offline)

        let onlineUnsynchronized = try healthValidator.validate(
            OperationalHealthDraft(
                syncHealth: Self.syncHealth(
                    connectivity: .online,
                    subscriptionState: .loading,
                    checkpoint: nil
                ),
                observedAt: Self.observedAt
            )
        )
        let onlineData = try healthValidator.canonicalData(for: onlineUnsynchronized)
        #expect(try healthValidator.decodeAndValidate(onlineData) == onlineUnsynchronized)

        let fractionalObservedAt = Date(timeIntervalSince1970: 1_788_100_000.123_456)
        let normalizedHealth = try healthValidator.validate(
            OperationalHealthDraft(
                syncHealth: Self.syncHealth(
                    connectivity: .offline,
                    subscriptionState: .ready,
                    checkpoint: fractionalObservedAt.addingTimeInterval(-1)
                ),
                observedAt: fractionalObservedAt
            )
        )
        #expect(
            normalizedHealth.observedAt
                == Date(timeIntervalSince1970: 1_788_100_000.123)
        )
        let normalizedHealthData = try healthValidator.canonicalData(for: normalizedHealth)
        #expect(
            try healthValidator.decodeAndValidate(normalizedHealthData) == normalizedHealth
        )

        let encoded = String(decoding: firstRegistryData + offlineData + onlineData, as: UTF8.self)
        for forbidden in [
            "https://",
            "access_token",
            "service_role",
            "signed_url",
            "firebase",
            "supabase",
            "powersync",
            "principal-private",
            "account-private"
        ] {
            #expect(!encoded.localizedCaseInsensitiveContains(forbidden))
        }
    }

    @Test("Invalid timing, registry references, evidence, tamper, and bounds fail closed")
    func invalidCandidatesFailClosed() throws {
        let healthValidator = OperationalHealthValidator()
        let futureCheckpoint = try Self.syncHealth(
            connectivity: .online,
            subscriptionState: .ready,
            checkpoint: Self.observedAt.addingTimeInterval(1)
        )
        #expect(Self.captureOperationalFailure {
            try healthValidator.validate(
                OperationalHealthDraft(
                    syncHealth: futureCheckpoint,
                    observedAt: Self.observedAt
                )
            )
        } == .sourceTimeAfterObservation("last_checkpoint"))

        let duplicateSubscription = try Self.syncHealth(
            connectivity: .online,
            subscriptionState: .ready,
            checkpoint: Self.observedAt,
            subscriptions: [Self.subscription(state: .ready), Self.subscription(state: .ready)]
        )
        #expect(Self.captureOperationalFailure {
            try healthValidator.validate(
                OperationalHealthDraft(
                    syncHealth: duplicateSubscription,
                    observedAt: Self.observedAt
                )
            )
        } == .duplicateSubscription(try Self.capability()))

        #expect(Self.captureOperationFailure {
            try SyncHealthSnapshot(
                connectivity: .offline,
                authentication: .current,
                subscriptions: [],
                lastSuccessfulCheckpointAt: nil,
                pendingOperationCount: -1,
                oldestPendingOperationAt: nil,
                pendingAttachmentCount: 0,
                oldestPendingAttachmentAt: nil,
                rejectedOperationCount: 0,
                transientError: nil,
                writeBlock: .none
            )
        } == .invalidCount(field: "pending_operations"))

        let registryValidator = OperationalControlRegistryValidator()
        let draft = try TargetOperationalControlRegistry.draft()
        #expect(Self.captureOperationalFailure {
            try registryValidator.validate(
                OperationalControlRegistryDraft(
                    measurements: Array(draft.measurements.dropLast()),
                    objectives: draft.objectives,
                    alerts: draft.alerts,
                    runbooks: draft.runbooks,
                    performanceBudgets: draft.performanceBudgets
                )
            )
        } == .missingMeasurement(draft.measurements.last!.id))

        #expect(Self.captureOperationalFailure {
            try registryValidator.validate(
                OperationalControlRegistryDraft(
                    measurements: draft.measurements,
                    objectives: draft.objectives,
                    alerts: draft.alerts + [draft.alerts[0]],
                    runbooks: draft.runbooks,
                    performanceBudgets: draft.performanceBudgets
                )
            )
        } == .duplicateAlert(draft.alerts[0].id))

        let invalidAlert = AlertCandidateDefinition(
            id: draft.alerts[0].id,
            severity: draft.alerts[0].severity,
            condition: draft.alerts[0].condition,
            measurements: draft.alerts[0].measurements,
            objectives: draft.alerts[0].objectives,
            runbook: draft.alerts[0].runbook,
            groupingWindowSeconds: 0,
            maximumNotificationsPerHour: 0
        )
        var invalidAlerts = draft.alerts
        invalidAlerts[0] = invalidAlert
        #expect(Self.captureOperationalFailure {
            try registryValidator.validate(
                OperationalControlRegistryDraft(
                    measurements: draft.measurements,
                    objectives: draft.objectives,
                    alerts: invalidAlerts,
                    runbooks: draft.runbooks,
                    performanceBudgets: draft.performanceBudgets
                )
            )
        } == .invalidAlertPolicy(invalidAlert.id))

        let idempotencyAlertIndex = try #require(
            draft.alerts.firstIndex { $0.objectives.contains(.idempotency) }
        )
        let idempotencyAlert = draft.alerts[idempotencyAlertIndex]
        var alertsWithoutIdempotency = draft.alerts
        alertsWithoutIdempotency[idempotencyAlertIndex] = AlertCandidateDefinition(
            id: idempotencyAlert.id,
            severity: idempotencyAlert.severity,
            condition: idempotencyAlert.condition,
            measurements: idempotencyAlert.measurements,
            objectives: idempotencyAlert.objectives.filter { $0 != .idempotency },
            runbook: idempotencyAlert.runbook,
            groupingWindowSeconds: idempotencyAlert.groupingWindowSeconds,
            maximumNotificationsPerHour: idempotencyAlert.maximumNotificationsPerHour
        )
        #expect(Self.captureOperationalFailure {
            try registryValidator.validate(
                OperationalControlRegistryDraft(
                    measurements: draft.measurements,
                    objectives: draft.objectives,
                    alerts: alertsWithoutIdempotency,
                    runbooks: draft.runbooks,
                    performanceBudgets: draft.performanceBudgets
                )
            )
        } == .objectiveWithoutAlert(.idempotency))

        let repeatedReference = try OperationalReferenceCode(validating: "repeated_reference")
        let runbook = draft.runbooks[0]
        let invalidRunbook = OperationalRunbookDefinition(
            id: runbook.id,
            detection: repeatedReference,
            impact: repeatedReference,
            firstSafeAction: runbook.firstSafeAction,
            evidenceToPreserve: runbook.evidenceToPreserve,
            rollbackBoundary: runbook.rollbackBoundary,
            escalationOwner: runbook.escalationOwner,
            recoveryVerification: runbook.recoveryVerification
        )
        var invalidRunbooks = draft.runbooks
        invalidRunbooks[0] = invalidRunbook
        #expect(Self.captureOperationalFailure {
            try registryValidator.validate(
                OperationalControlRegistryDraft(
                    measurements: draft.measurements,
                    objectives: draft.objectives,
                    alerts: draft.alerts,
                    runbooks: invalidRunbooks,
                    performanceBudgets: draft.performanceBudgets
                )
            )
        } == .invalidRunbook(invalidRunbook.id))

        let registry = try registryValidator.validate(draft)
        #expect(Self.captureOperationalFailure {
            try registryValidator.evaluate(.durability, evidence: [], in: registry)
        } == .incompleteObjectiveEvidence(.durability))

        let expectedEvidence = try Self.evidence(
            measurement: .lostAcceptedOperationCount,
            observedValue: 0
        )
        let unexpectedEvidence = try Self.evidence(
            measurement: .duplicateAuthoritativeEffectCount,
            observedValue: 0
        )
        #expect(Self.captureOperationalFailure {
            try registryValidator.evaluate(
                .durability,
                evidence: [expectedEvidence, unexpectedEvidence],
                in: registry
            )
        } == .unexpectedObjectiveEvidence(.durability, .duplicateAuthoritativeEffectCount))
        #expect(Self.captureOperationalFailure {
            try registryValidator.evaluate(
                .durability,
                evidence: [expectedEvidence, expectedEvidence],
                in: registry
            )
        } == .duplicateObjectiveEvidence(.lostAcceptedOperationCount))
        #expect(Self.captureOperationalFailure {
            try ServiceObjectiveEvidence(
                measurement: .lostAcceptedOperationCount,
                observedValue: 0,
                sampleCount: 0,
                evidenceDigest: try Self.digest()
            )
        } == .invalidEvidenceSample(.lostAcceptedOperationCount))

        let canonicalRegistry = try registryValidator.canonicalData(for: registry)
        let tamperedRegistry = try Self.replacingDigest(in: canonicalRegistry)
        #expect(Self.captureOperationalFailure {
            try registryValidator.decodeAndValidate(tamperedRegistry)
        } == .registryDigestMismatch)
        #expect(Self.captureOperationalFailure {
            try registryValidator.decodeAndValidate(canonicalRegistry + Data([0x0a]))
        } == .noncanonicalRegistry)

        let validHealth = try healthValidator.validate(
            OperationalHealthDraft(
                syncHealth: Self.syncHealth(
                    connectivity: .offline,
                    subscriptionState: .ready,
                    checkpoint: Self.observedAt
                ),
                observedAt: Self.observedAt
            )
        )
        let canonicalHealth = try healthValidator.canonicalData(for: validHealth)
        let tamperedHealth = try Self.replacingDigest(in: canonicalHealth)
        #expect(Self.captureOperationalFailure {
            try healthValidator.decodeAndValidate(tamperedHealth)
        } == .healthDigestMismatch)
        #expect(Self.captureOperationalFailure {
            try healthValidator.decodeAndValidate(canonicalHealth + Data([0x0a]))
        } == .noncanonicalHealth)

        let oversizedRegistry = Data(
            repeating: 0x20,
            count: OperationalControlRegistryValidator.maximumCanonicalBytes + 1
        )
        guard case .registryTooLarge(let actualRegistrySize, let maximumRegistrySize) =
                Self.captureOperationalFailure({
                    try registryValidator.decodeAndValidate(oversizedRegistry)
                }) else {
            Issue.record("Oversized registry input should fail before decoding")
            return
        }
        #expect(actualRegistrySize == oversizedRegistry.count)
        #expect(maximumRegistrySize == OperationalControlRegistryValidator.maximumCanonicalBytes)

        let oversizedHealth = Data(
            repeating: 0x20,
            count: OperationalHealthValidator.maximumCanonicalBytes + 1
        )
        guard case .healthTooLarge(let actualHealthSize, let maximumHealthSize) =
                Self.captureOperationalFailure({
                    try healthValidator.decodeAndValidate(oversizedHealth)
                }) else {
            Issue.record("Oversized health input should fail before decoding")
            return
        }
        #expect(actualHealthSize == oversizedHealth.count)
        #expect(maximumHealthSize == OperationalHealthValidator.maximumCanonicalBytes)
    }

    @Test("Candidate registry cannot claim operational activation or numeric budgets")
    func registryCannotClaimActivationOrNumericBudgets() throws {
        let registry = try TargetOperationalControlRegistry.make()
        let registryData = try OperationalControlRegistryValidator().canonicalData(for: registry)
        let encoded = String(decoding: registryData, as: UTF8.self)

        #expect(OperationalPolicyAuthority.allCases == [.candidateOnly])
        #expect(OperationalAuthorityDisposition.allCases == [.evidenceOnly])
        #expect(ServiceObjectiveThreshold.allCases == [.exactZero])
        #expect(PerformanceBudgetStatus.allCases == [.pendingVerticalSpike])
        #expect(ServiceObjectiveStatus.allCases == [.notEvaluated, .satisfied, .violated])
        #expect(registry.alerts.allSatisfy { $0.authority == .candidateOnly })
        #expect(registry.performanceBudgets.allSatisfy { $0.status == .pendingVerticalSpike })
        #expect(!encoded.contains("productionThreshold"))
        #expect(!encoded.contains("numericThreshold"))
        #expect(!encoded.contains("active_policy"))
        #expect(!encoded.contains("alert_emitted"))
        #expect(!encoded.contains("acknowledged"))
        #expect(!encoded.contains("resolved_alert"))
        #expect(!encoded.contains("operator_action"))
    }

    private static let observedAt = Date(timeIntervalSince1970: 1_788_100_000)

    private static func capability() throws -> CapabilityID {
        try CapabilityID(validating: "project_workspace")
    }

    private static func subscription(
        state: SubscriptionReadinessState
    ) throws -> SubscriptionReadinessSnapshot {
        let version = try OperationContractVersion(validating: "1")
        return SubscriptionReadinessSnapshot(
            capability: try capability(),
            required: true,
            requiredContractVersion: version,
            localContractVersion: version,
            state: state
        )
    }

    private static func syncHealth(
        connectivity: ConnectivityState,
        subscriptionState: SubscriptionReadinessState,
        checkpoint: Date?,
        pendingOperationCount: Int = 0,
        oldestPendingOperationAt: Date? = nil,
        pendingAttachmentCount: Int = 0,
        oldestPendingAttachmentAt: Date? = nil,
        subscriptions: [SubscriptionReadinessSnapshot]? = nil
    ) throws -> SyncHealthSnapshot {
        try SyncHealthSnapshot(
            connectivity: connectivity,
            authentication: .current,
            subscriptions: subscriptions ?? [subscription(state: subscriptionState)],
            lastSuccessfulCheckpointAt: checkpoint,
            pendingOperationCount: pendingOperationCount,
            oldestPendingOperationAt: oldestPendingOperationAt,
            pendingAttachmentCount: pendingAttachmentCount,
            oldestPendingAttachmentAt: oldestPendingAttachmentAt,
            rejectedOperationCount: 0,
            transientError: nil,
            writeBlock: .none
        )
    }

    private static func component(
        _ id: OperationalComponentID,
        in snapshot: OperationalHealthSnapshot
    ) -> OperationalHealthComponent? {
        snapshot.components.first { $0.id == id }
    }

    private static func evidence(
        measurement: OperationalMeasurementID,
        observedValue: UInt64
    ) throws -> ServiceObjectiveEvidence {
        try ServiceObjectiveEvidence(
            measurement: measurement,
            observedValue: observedValue,
            sampleCount: 1,
            evidenceDigest: digest()
        )
    }

    private static func digest() throws -> OperationFingerprint {
        try OperationFingerprint(validating: String(repeating: "a", count: 64))
    }

    private static func runbookIsComplete(_ runbook: OperationalRunbookDefinition) -> Bool {
        let values = [
            runbook.detection.rawValue,
            runbook.impact.rawValue,
            runbook.firstSafeAction.rawValue,
            runbook.evidenceToPreserve.rawValue,
            runbook.rollbackBoundary.rawValue,
            runbook.escalationOwner.rawValue,
            runbook.recoveryVerification.rawValue
        ]
        return Set(values).count == values.count && values.allSatisfy { !$0.isEmpty }
    }

    private static func replacingDigest(in data: Data) throws -> Data {
        var object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["contentDigest"] = String(repeating: "b", count: 64)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func captureOperationalFailure<Value>(
        _ operation: () throws -> Value
    ) -> OperationalControlFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as OperationalControlFailure {
            return failure
        } catch {
            return nil
        }
    }

    private static func captureOperationFailure<Value>(
        _ operation: () throws -> Value
    ) -> OperationContractFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as OperationContractFailure {
            return failure
        } catch {
            return nil
        }
    }
}
