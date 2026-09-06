import CryptoKit
import Foundation

public enum OperationalControlFailure: Error, Equatable, Sendable {
    case invalidObservationTime
    case sourceTimeAfterObservation(String)
    case duplicateSubscription(CapabilityID)
    case duplicateMeasurement(OperationalMeasurementID)
    case missingMeasurement(OperationalMeasurementID)
    case duplicateObjective(ServiceObjectiveID)
    case missingObjective(ServiceObjectiveID)
    case duplicateAlert(AlertCandidateID)
    case missingAlert(AlertCandidateID)
    case duplicateRunbook(OperationalRunbookID)
    case missingRunbook(OperationalRunbookID)
    case duplicatePerformanceBudget(ProvisionalPerformanceBudgetID)
    case missingPerformanceBudget(ProvisionalPerformanceBudgetID)
    case emptyObjectiveMeasurements(ServiceObjectiveID)
    case duplicateObjectiveMeasurement(ServiceObjectiveID, OperationalMeasurementID)
    case objectiveWithoutAlert(ServiceObjectiveID)
    case unknownMeasurementReference(String, OperationalMeasurementID)
    case unknownObjectiveReference(AlertCandidateID, ServiceObjectiveID)
    case unknownRunbookReference(String, OperationalRunbookID)
    case invalidAlertPolicy(AlertCandidateID)
    case invalidRunbook(OperationalRunbookID)
    case invalidEvidenceSample(OperationalMeasurementID)
    case duplicateObjectiveEvidence(OperationalMeasurementID)
    case incompleteObjectiveEvidence(ServiceObjectiveID)
    case unexpectedObjectiveEvidence(ServiceObjectiveID, OperationalMeasurementID)
    case healthDigestMismatch
    case noncanonicalHealth
    case malformedHealth
    case healthTooLarge(actual: Int, maximum: Int)
    case registryDigestMismatch
    case noncanonicalRegistry
    case malformedRegistry
    case registryTooLarge(actual: Int, maximum: Int)

    public var diagnosticCode: String {
        switch self {
        case .invalidObservationTime: return "operational_health_observation_invalid"
        case .sourceTimeAfterObservation: return "operational_health_time_regression"
        case .duplicateSubscription: return "operational_health_subscription_duplicate"
        case .duplicateMeasurement: return "operational_registry_measurement_duplicate"
        case .missingMeasurement: return "operational_registry_measurement_missing"
        case .duplicateObjective: return "operational_registry_objective_duplicate"
        case .missingObjective: return "operational_registry_objective_missing"
        case .duplicateAlert: return "operational_registry_alert_duplicate"
        case .missingAlert: return "operational_registry_alert_missing"
        case .duplicateRunbook: return "operational_registry_runbook_duplicate"
        case .missingRunbook: return "operational_registry_runbook_missing"
        case .duplicatePerformanceBudget: return "operational_registry_budget_duplicate"
        case .missingPerformanceBudget: return "operational_registry_budget_missing"
        case .emptyObjectiveMeasurements: return "operational_registry_objective_measurements_empty"
        case .duplicateObjectiveMeasurement: return "operational_registry_objective_measurement_duplicate"
        case .objectiveWithoutAlert: return "operational_registry_objective_alert_missing"
        case .unknownMeasurementReference: return "operational_registry_measurement_unknown"
        case .unknownObjectiveReference: return "operational_registry_objective_unknown"
        case .unknownRunbookReference: return "operational_registry_runbook_unknown"
        case .invalidAlertPolicy: return "operational_registry_alert_policy_invalid"
        case .invalidRunbook: return "operational_registry_runbook_invalid"
        case .invalidEvidenceSample: return "operational_objective_evidence_invalid"
        case .duplicateObjectiveEvidence: return "operational_objective_evidence_duplicate"
        case .incompleteObjectiveEvidence: return "operational_objective_evidence_incomplete"
        case .unexpectedObjectiveEvidence: return "operational_objective_evidence_unexpected"
        case .healthDigestMismatch: return "operational_health_digest_mismatch"
        case .noncanonicalHealth: return "operational_health_noncanonical"
        case .malformedHealth: return "operational_health_malformed"
        case .healthTooLarge: return "operational_health_too_large"
        case .registryDigestMismatch: return "operational_registry_digest_mismatch"
        case .noncanonicalRegistry: return "operational_registry_noncanonical"
        case .malformedRegistry: return "operational_registry_malformed"
        case .registryTooLarge: return "operational_registry_too_large"
        }
    }
}

public enum OperationalComponentID: String, Codable, CaseIterable, Sendable {
    case connectivity
    case authentication
    case subscriptions
    case replicationCheckpoint = "replication_checkpoint"
    case operationQueue = "operation_queue"
    case attachmentQueue = "attachment_queue"
    case rejectedOperations = "rejected_operations"
    case writeAuthority = "write_authority"
    case transientTransport = "transient_transport"
}

public enum OperationalComponentState: String, Codable, CaseIterable, Sendable {
    case healthy
    case offline
    case synchronizing
    case waiting
    case degraded
    case blocked
    case unavailable
    case attentionRequired = "attention_required"
}

public enum OperationalActionCode: String, Codable, CaseIterable, Sendable {
    case continueOffline = "continue_offline"
    case waitForConnection = "wait_for_connection"
    case reauthenticate
    case waitForSubscriptions = "wait_for_subscriptions"
    case waitForLocalDurability = "wait_for_local_durability"
    case reviewRejectedOperations = "review_rejected_operations"
    case retryTransientFailure = "retry_transient_failure"
    case waitForMaintenance = "wait_for_maintenance"
    case completeMigration = "complete_migration"
    case installRequiredUpdate = "install_required_update"
    case authorizationEnded = "authorization_ended"
}

public enum OperationalOverallState: String, Codable, CaseIterable, Sendable {
    case ready
    case readyOffline = "ready_offline"
    case synchronizing
    case degraded
    case blocked
}

public enum OperationalPolicyAuthority: String, Codable, CaseIterable, Sendable {
    case candidateOnly = "candidate_only"
}

public enum OperationalAuthorityDisposition: String, Codable, CaseIterable, Sendable {
    case evidenceOnly = "evidence_only"
}

public struct OperationalHealthComponent: Codable, Equatable, Sendable {
    public let id: OperationalComponentID
    public let state: OperationalComponentState
    public let action: OperationalActionCode?

    public init(
        id: OperationalComponentID,
        state: OperationalComponentState,
        action: OperationalActionCode?
    ) {
        self.id = id
        self.state = state
        self.action = action
    }
}

public struct OperationalHealthSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let observedAt: Date
    public let syncHealth: SyncHealthSnapshot
    public let isOnline: Bool
    public let isSynchronized: Bool
    public let lastCheckpointAgeMilliseconds: UInt64?
    public let oldestPendingOperationAgeMilliseconds: UInt64?
    public let oldestPendingAttachmentAgeMilliseconds: UInt64?
    public let components: [OperationalHealthComponent]
    public let overallState: OperationalOverallState
    public let authorityDisposition: OperationalAuthorityDisposition
    public let contentDigest: OperationFingerprint

    fileprivate var draft: OperationalHealthDraft {
        OperationalHealthDraft(syncHealth: syncHealth, observedAt: observedAt)
    }
}

public struct OperationalHealthDraft: Sendable {
    public let syncHealth: SyncHealthSnapshot
    public let observedAt: Date

    public init(syncHealth: SyncHealthSnapshot, observedAt: Date) {
        self.syncHealth = syncHealth
        self.observedAt = observedAt
    }
}

public struct OperationalHealthValidator: Sendable {
    public static let schemaVersion = 1
    public static let maximumCanonicalBytes = 32_768

    public init() {}

    public func validate(_ draft: OperationalHealthDraft) throws -> OperationalHealthSnapshot {
        let observedMilliseconds = try Self.epochMilliseconds(draft.observedAt)
        let revalidatedHealth = try Self.revalidated(draft.syncHealth)
        var capabilities: Set<CapabilityID> = []
        for subscription in revalidatedHealth.subscriptions {
            guard capabilities.insert(subscription.capability).inserted else {
                throw OperationalControlFailure.duplicateSubscription(subscription.capability)
            }
        }

        let lastCheckpointAge = try Self.age(
            from: revalidatedHealth.lastSuccessfulCheckpointAt,
            observedAt: draft.observedAt,
            observedMilliseconds: observedMilliseconds,
            field: "last_checkpoint"
        )
        let oldestPendingOperationAge = try Self.age(
            from: revalidatedHealth.oldestPendingOperationAt,
            observedAt: draft.observedAt,
            observedMilliseconds: observedMilliseconds,
            field: "oldest_pending_operation"
        )
        let oldestPendingAttachmentAge = try Self.age(
            from: revalidatedHealth.oldestPendingAttachmentAt,
            observedAt: draft.observedAt,
            observedMilliseconds: observedMilliseconds,
            field: "oldest_pending_attachment"
        )
        let syncHealth = try Self.normalized(revalidatedHealth)

        let content = OperationalHealthContent(
            schemaVersion: Self.schemaVersion,
            observedAt: Self.date(fromEpochMilliseconds: observedMilliseconds),
            syncHealth: syncHealth,
            isOnline: syncHealth.isOnline,
            isSynchronized: syncHealth.isSynchronized,
            lastCheckpointAgeMilliseconds: lastCheckpointAge,
            oldestPendingOperationAgeMilliseconds: oldestPendingOperationAge,
            oldestPendingAttachmentAgeMilliseconds: oldestPendingAttachmentAge,
            components: Self.components(for: syncHealth),
            overallState: Self.overallState(for: syncHealth),
            authorityDisposition: .evidenceOnly
        )
        let snapshot = OperationalHealthSnapshot(
            schemaVersion: content.schemaVersion,
            observedAt: content.observedAt,
            syncHealth: content.syncHealth,
            isOnline: content.isOnline,
            isSynchronized: content.isSynchronized,
            lastCheckpointAgeMilliseconds: content.lastCheckpointAgeMilliseconds,
            oldestPendingOperationAgeMilliseconds: content.oldestPendingOperationAgeMilliseconds,
            oldestPendingAttachmentAgeMilliseconds: content.oldestPendingAttachmentAgeMilliseconds,
            components: content.components,
            overallState: content.overallState,
            authorityDisposition: content.authorityDisposition,
            contentDigest: try OperationalCanonical.digest(content)
        )
        let canonical = try OperationalCanonical.encode(snapshot)
        guard canonical.count <= Self.maximumCanonicalBytes else {
            throw OperationalControlFailure.healthTooLarge(
                actual: canonical.count,
                maximum: Self.maximumCanonicalBytes
            )
        }
        return snapshot
    }

    public func canonicalData(for snapshot: OperationalHealthSnapshot) throws -> Data {
        let validated = try validate(snapshot.draft)
        guard validated.contentDigest == snapshot.contentDigest else {
            throw OperationalControlFailure.healthDigestMismatch
        }
        guard validated == snapshot else {
            throw OperationalControlFailure.noncanonicalHealth
        }
        return try OperationalCanonical.encode(validated)
    }

    public func decodeAndValidate(_ data: Data) throws -> OperationalHealthSnapshot {
        guard data.count <= Self.maximumCanonicalBytes else {
            throw OperationalControlFailure.healthTooLarge(
                actual: data.count,
                maximum: Self.maximumCanonicalBytes
            )
        }
        let decoded: OperationalHealthSnapshot
        do {
            decoded = try OperationalCanonical.decode(OperationalHealthSnapshot.self, from: data)
        } catch {
            throw OperationalControlFailure.malformedHealth
        }
        let validated = try validate(decoded.draft)
        guard validated.contentDigest == decoded.contentDigest else {
            throw OperationalControlFailure.healthDigestMismatch
        }
        guard validated == decoded, try OperationalCanonical.encode(validated) == data else {
            throw OperationalControlFailure.noncanonicalHealth
        }
        return validated
    }

    private static func revalidated(_ value: SyncHealthSnapshot) throws -> SyncHealthSnapshot {
        try SyncHealthSnapshot(
            connectivity: value.connectivity,
            authentication: value.authentication,
            subscriptions: value.subscriptions,
            lastSuccessfulCheckpointAt: value.lastSuccessfulCheckpointAt,
            pendingOperationCount: value.pendingOperationCount,
            oldestPendingOperationAt: value.oldestPendingOperationAt,
            pendingAttachmentCount: value.pendingAttachmentCount,
            oldestPendingAttachmentAt: value.oldestPendingAttachmentAt,
            rejectedOperationCount: value.rejectedOperationCount,
            transientError: value.transientError,
            writeBlock: value.writeBlock
        )
    }

    private static func normalized(_ value: SyncHealthSnapshot) throws -> SyncHealthSnapshot {
        try SyncHealthSnapshot(
            connectivity: value.connectivity,
            authentication: value.authentication,
            subscriptions: value.subscriptions,
            lastSuccessfulCheckpointAt: try normalized(value.lastSuccessfulCheckpointAt),
            pendingOperationCount: value.pendingOperationCount,
            oldestPendingOperationAt: try normalized(value.oldestPendingOperationAt),
            pendingAttachmentCount: value.pendingAttachmentCount,
            oldestPendingAttachmentAt: try normalized(value.oldestPendingAttachmentAt),
            rejectedOperationCount: value.rejectedOperationCount,
            transientError: value.transientError,
            writeBlock: value.writeBlock
        )
    }

    private static func normalized(_ value: Date?) throws -> Date? {
        guard let value else { return nil }
        return date(fromEpochMilliseconds: try epochMilliseconds(value))
    }

    private static func components(for health: SyncHealthSnapshot) -> [OperationalHealthComponent] {
        let subscriptionState: OperationalComponentState
        if health.subscriptions.contains(where: { $0.required && $0.state == .blocked }) {
            subscriptionState = .blocked
        } else if health.subscriptions.contains(where: { $0.required && $0.state == .stale }) {
            subscriptionState = .degraded
        } else if health.subscriptions.allSatisfy(\.satisfiesRequirement) {
            subscriptionState = .healthy
        } else {
            subscriptionState = .synchronizing
        }

        let authenticationState: OperationalComponentState
        switch health.authentication {
        case .current: authenticationState = .healthy
        case .refreshing: authenticationState = .synchronizing
        case .stale: authenticationState = .degraded
        case .expired, .revoked: authenticationState = .blocked
        case .unavailable: authenticationState = .unavailable
        }

        let connectivityState: OperationalComponentState
        let connectivityAction: OperationalActionCode?
        switch health.connectivity {
        case .online:
            connectivityState = .healthy
            connectivityAction = nil
        case .connecting:
            connectivityState = .synchronizing
            connectivityAction = .waitForConnection
        case .offline:
            connectivityState = .offline
            connectivityAction = .continueOffline
        }

        let writeAction: OperationalActionCode?
        switch health.writeBlock {
        case .none: writeAction = nil
        case .maintenance: writeAction = .waitForMaintenance
        case .migrationRequired: writeAction = .completeMigration
        case .clientUpdateRequired: writeAction = .installRequiredUpdate
        case .authorizationExpired, .authorizationRevoked: writeAction = .authorizationEnded
        }

        return [
            .init(id: .connectivity, state: connectivityState, action: connectivityAction),
            .init(
                id: .authentication,
                state: authenticationState,
                action: authenticationState == .blocked ? .reauthenticate : nil
            ),
            .init(
                id: .subscriptions,
                state: subscriptionState,
                action: subscriptionState == .healthy ? nil : .waitForSubscriptions
            ),
            .init(
                id: .replicationCheckpoint,
                state: health.lastSuccessfulCheckpointAt == nil ? .unavailable : .healthy,
                action: health.lastSuccessfulCheckpointAt == nil ? .waitForSubscriptions : nil
            ),
            .init(
                id: .operationQueue,
                state: health.pendingOperationCount == 0 ? .healthy : .waiting,
                action: health.pendingOperationCount == 0 ? nil : .waitForLocalDurability
            ),
            .init(
                id: .attachmentQueue,
                state: health.pendingAttachmentCount == 0 ? .healthy : .waiting,
                action: health.pendingAttachmentCount == 0 ? nil : .waitForLocalDurability
            ),
            .init(
                id: .rejectedOperations,
                state: health.rejectedOperationCount == 0 ? .healthy : .attentionRequired,
                action: health.rejectedOperationCount == 0 ? nil : .reviewRejectedOperations
            ),
            .init(
                id: .writeAuthority,
                state: health.writeBlock == .none ? .healthy : .blocked,
                action: writeAction
            ),
            .init(
                id: .transientTransport,
                state: health.transientError == nil ? .healthy : .degraded,
                action: health.transientError == nil ? nil : .retryTransientFailure
            )
        ]
    }

    private static func overallState(for health: SyncHealthSnapshot) -> OperationalOverallState {
        if health.writeBlock != .none ||
            health.authentication == .expired ||
            health.authentication == .revoked ||
            health.subscriptions.contains(where: { $0.required && $0.state == .blocked }) {
            return .blocked
        }
        if health.transientError != nil || health.rejectedOperationCount > 0 {
            return .degraded
        }
        if health.isSynchronized {
            switch health.connectivity {
            case .online: return .ready
            case .offline: return .readyOffline
            case .connecting: return .synchronizing
            }
        }
        return health.connectivity == .offline ? .degraded : .synchronizing
    }

    private static func epochMilliseconds(_ value: Date) throws -> Int64 {
        let seconds = value.timeIntervalSince1970
        guard seconds.isFinite, seconds > 0 else {
            throw OperationalControlFailure.invalidObservationTime
        }
        let milliseconds = seconds * 1_000
        guard milliseconds <= Double(Int64.max) else {
            throw OperationalControlFailure.invalidObservationTime
        }
        return Int64(milliseconds.rounded(.towardZero))
    }

    private static func date(fromEpochMilliseconds value: Int64) -> Date {
        Date(timeIntervalSince1970: Double(value) / 1_000)
    }

    private static func age(
        from source: Date?,
        observedAt: Date,
        observedMilliseconds: Int64,
        field: String
    ) throws -> UInt64? {
        guard let source else { return nil }
        guard source <= observedAt else {
            throw OperationalControlFailure.sourceTimeAfterObservation(field)
        }
        let sourceMilliseconds = try epochMilliseconds(source)
        guard sourceMilliseconds <= observedMilliseconds else {
            throw OperationalControlFailure.sourceTimeAfterObservation(field)
        }
        return UInt64(observedMilliseconds - sourceMilliseconds)
    }
}

private struct OperationalHealthContent: Codable {
    let schemaVersion: Int
    let observedAt: Date
    let syncHealth: SyncHealthSnapshot
    let isOnline: Bool
    let isSynchronized: Bool
    let lastCheckpointAgeMilliseconds: UInt64?
    let oldestPendingOperationAgeMilliseconds: UInt64?
    let oldestPendingAttachmentAgeMilliseconds: UInt64?
    let components: [OperationalHealthComponent]
    let overallState: OperationalOverallState
    let authorityDisposition: OperationalAuthorityDisposition
}

public enum OperationalMeasurementID: String, Codable, CaseIterable, Sendable {
    case appBuildBackendContractSchemaVersions = "app_build_backend_contract_schema_versions"
    case localDatabaseOpenLatency = "local_database_open_latency"
    case localQueryLatency = "local_query_latency"
    case localQueryMemory = "local_query_memory"
    case localOperationAcceptanceLatency = "local_operation_acceptance_latency"
    case activeSubscriptionReadiness = "active_subscription_readiness"
    case lastCompletedSync = "last_completed_sync"
    case syncLag = "sync_lag"
    case pendingCommandCount = "pending_command_count"
    case oldestPendingCommandAge = "oldest_pending_command_age"
    case rejectedCommandCount = "rejected_command_count"
    case conflictedCommandCount = "conflicted_command_count"
    case pendingAttachmentCount = "pending_attachment_count"
    case failedAttachmentCount = "failed_attachment_count"
    case oldestPendingAttachmentAge = "oldest_pending_attachment_age"
    case attachmentQueueThroughput = "attachment_queue_throughput"
    case authRefreshFailureCount = "auth_refresh_failure_count"
    case localDecodeMappingFailureCount = "local_decode_mapping_failure_count"
    case localDatabaseSize = "local_database_size"
    case offlineSessionDuration = "offline_session_duration"
    case serverCommandCount = "server_command_count"
    case serverCommandLatency = "server_command_latency"
    case serverCommandOutcomeCount = "server_command_outcome_count"
    case serverRetryCount = "server_retry_count"
    case serverDeduplicationCount = "server_deduplication_count"
    case serverTransientFailureRate = "server_transient_failure_rate"
    case serverPermanentFailureRate = "server_permanent_failure_rate"
    case serverLockWaitCount = "server_lock_wait_count"
    case serverDeadlockCount = "server_deadlock_count"
    case serverSerializationRetryCount = "server_serialization_retry_count"
    case rlsDenialCount = "rls_denial_count"
    case suspiciousCrossScopeAttemptCount = "suspicious_cross_scope_attempt_count"
    case migrationReconciliationDriftCount = "migration_reconciliation_drift_count"
    case migrationProductionGuardViolationCount = "migration_production_guard_violation_count"
    case postgresCPUUtilization = "postgres_cpu_utilization"
    case postgresConnectionCount = "postgres_connection_count"
    case postgresDiskBytes = "postgres_disk_bytes"
    case postgresIOBytes = "postgres_io_bytes"
    case postgresSlowQueryCount = "postgres_slow_query_count"
    case targetDatabaseAvailabilityState = "target_database_availability_state"
    case storageUploadErrorCount = "storage_upload_error_count"
    case storageDownloadErrorCount = "storage_download_error_count"
    case storageDeleteErrorCount = "storage_delete_error_count"
    case orphanAttachmentCount = "orphan_attachment_count"
    case targetStorageAvailabilityState = "target_storage_availability_state"
    case edgeFunctionFailureCount = "edge_function_failure_count"
    case externalIntegrationFailureCount = "external_integration_failure_count"
    case mcpCommandActivityCount = "mcp_command_activity_count"
    case mcpReadActivityCount = "mcp_read_activity_count"
    case replicationLag = "replication_lag"
    case activeClientCount = "active_client_count"
    case peakClientCount = "peak_client_count"
    case hostedDataBytes = "hosted_data_bytes"
    case synchronizedBytesPerMonth = "synchronized_bytes_per_month"
    case streamCountPerUser = "stream_count_per_user"
    case initialSyncDuration = "initial_sync_duration"
    case initialSyncDownloadedBytes = "initial_sync_downloaded_bytes"
    case incrementalSyncDuration = "incremental_sync_duration"
    case uploadQueueErrorCount = "upload_queue_error_count"
    case oldestPendingUploadAge = "oldest_pending_upload_age"
    case deploymentReprocessingState = "deployment_reprocessing_state"
    case lostAcceptedOperationCount = "lost_accepted_operation_count"
    case duplicateAuthoritativeEffectCount = "duplicate_authoritative_effect_count"
    case unexplainedReconciliationDifferenceCount = "unexplained_reconciliation_difference_count"
    case unauthorizedLocalRowCount = "unauthorized_local_row_count"
    case poisonOperationStarvationCount = "poison_operation_starvation_count"
    case cachedCoreOfflineFailureCount = "cached_core_offline_failure_count"
    case alertWithoutOwnerOrRunbookCount = "alert_without_owner_or_runbook_count"
}

public enum OperationalMeasurementUnit: String, Codable, CaseIterable, Sendable {
    case count
    case milliseconds
    case bytes
    case bytesPerSecond = "bytes_per_second"
    case basisPoints = "basis_points"
    case state
    case version
}

public enum OperationalMeasurementScope: String, Codable, CaseIterable, Sendable {
    case client
    case server
    case replication
    case crossCutting = "cross_cutting"
}

public enum OperationalCollectionState: String, Codable, CaseIterable, Sendable {
    case derivedLocally = "derived_locally"
    case planned
}

public enum OperationalOwnerCodeTag: Sendable {}
public enum OperationalReferenceCodeTag: Sendable {}
public typealias OperationalOwnerCode = StableCode<OperationalOwnerCodeTag>
public typealias OperationalReferenceCode = StableCode<OperationalReferenceCodeTag>

public struct OperationalMeasurementDefinition: Codable, Equatable, Sendable {
    public let id: OperationalMeasurementID
    public let unit: OperationalMeasurementUnit
    public let scope: OperationalMeasurementScope
    public let owner: OperationalOwnerCode
    public let collectionState: OperationalCollectionState

    public init(
        id: OperationalMeasurementID,
        unit: OperationalMeasurementUnit,
        scope: OperationalMeasurementScope,
        owner: OperationalOwnerCode,
        collectionState: OperationalCollectionState
    ) {
        self.id = id
        self.unit = unit
        self.scope = scope
        self.owner = owner
        self.collectionState = collectionState
    }
}

public enum ServiceObjectiveID: String, Codable, CaseIterable, Sendable {
    case durability
    case idempotency
    case integrity
    case isolation
    case queueHealth = "queue_health"
    case offlineAvailability = "offline_availability"
    case recovery
}

public enum ServiceObjectiveThreshold: String, Codable, CaseIterable, Sendable {
    case exactZero = "exact_zero"
}

public struct ServiceObjectiveDefinition: Codable, Equatable, Sendable {
    public let id: ServiceObjectiveID
    public let requiredMeasurements: [OperationalMeasurementID]
    public let threshold: ServiceObjectiveThreshold
    public let owner: OperationalOwnerCode
    public let runbook: OperationalRunbookID

    public init(
        id: ServiceObjectiveID,
        requiredMeasurements: [OperationalMeasurementID],
        threshold: ServiceObjectiveThreshold,
        owner: OperationalOwnerCode,
        runbook: OperationalRunbookID
    ) {
        self.id = id
        self.requiredMeasurements = requiredMeasurements
        self.threshold = threshold
        self.owner = owner
        self.runbook = runbook
    }
}

public enum ServiceObjectiveStatus: String, Codable, CaseIterable, Sendable {
    case notEvaluated = "not_evaluated"
    case satisfied
    case violated
}

public struct ServiceObjectiveEvidence: Codable, Equatable, Sendable {
    public let measurement: OperationalMeasurementID
    public let observedValue: UInt64
    public let sampleCount: UInt64
    public let evidenceDigest: OperationFingerprint

    public init(
        measurement: OperationalMeasurementID,
        observedValue: UInt64,
        sampleCount: UInt64,
        evidenceDigest: OperationFingerprint
    ) throws {
        guard sampleCount > 0 else {
            throw OperationalControlFailure.invalidEvidenceSample(measurement)
        }
        self.measurement = measurement
        self.observedValue = observedValue
        self.sampleCount = sampleCount
        self.evidenceDigest = evidenceDigest
    }
}

public struct ServiceObjectiveAssessment: Codable, Equatable, Sendable {
    public let objective: ServiceObjectiveID
    public let status: ServiceObjectiveStatus
    public let evidence: [ServiceObjectiveEvidence]
    public let missingMeasurements: [OperationalMeasurementID]
    public let evidenceDigest: OperationFingerprint?

    fileprivate init(
        objective: ServiceObjectiveID,
        status: ServiceObjectiveStatus,
        evidence: [ServiceObjectiveEvidence],
        missingMeasurements: [OperationalMeasurementID],
        evidenceDigest: OperationFingerprint?
    ) {
        self.objective = objective
        self.status = status
        self.evidence = evidence
        self.missingMeasurements = missingMeasurements
        self.evidenceDigest = evidenceDigest
    }
}

public enum AlertCandidateID: String, Codable, CaseIterable, Sendable {
    case sustainedCommandApplyFailure = "sustained_command_apply_failure"
    case replicationHaltedOrLagged = "replication_halted_or_lagged"
    case financialReconciliationDrift = "financial_reconciliation_drift"
    case crossTenantAuthorizationAnomaly = "cross_tenant_authorization_anomaly"
    case migrationProductionGuardViolation = "migration_production_guard_violation"
    case cutoverTargetOutage = "cutover_target_outage"
    case growingQueueAge = "growing_queue_age"
    case repeatedStaleRejection = "repeated_stale_rejection"
    case increasedDecodeMappingFailure = "increased_decode_mapping_failure"
    case risingHostedSyncCost = "rising_hosted_sync_cost"
    case orphanAttachment = "orphan_attachment"
    case slowQueryOrRLSRegression = "slow_query_or_rls_regression"
}

public enum AlertSeverity: String, Codable, CaseIterable, Sendable {
    case highUrgency = "high_urgency"
    case lowerUrgency = "lower_urgency"
}

public enum OperationalAlertCondition: String, Codable, CaseIterable, Sendable {
    case nonzero
    case sustainedFailure = "sustained_failure"
    case unhealthyState = "unhealthy_state"
    case approvedThresholdRequired = "approved_threshold_required"
}

public struct AlertCandidateDefinition: Codable, Equatable, Sendable {
    public let id: AlertCandidateID
    public let severity: AlertSeverity
    public let condition: OperationalAlertCondition
    public let measurements: [OperationalMeasurementID]
    public let objectives: [ServiceObjectiveID]
    public let runbook: OperationalRunbookID
    public let groupingWindowSeconds: UInt32
    public let maximumNotificationsPerHour: UInt16
    public let authority: OperationalPolicyAuthority

    public init(
        id: AlertCandidateID,
        severity: AlertSeverity,
        condition: OperationalAlertCondition,
        measurements: [OperationalMeasurementID],
        objectives: [ServiceObjectiveID],
        runbook: OperationalRunbookID,
        groupingWindowSeconds: UInt32,
        maximumNotificationsPerHour: UInt16,
        authority: OperationalPolicyAuthority = .candidateOnly
    ) {
        self.id = id
        self.severity = severity
        self.condition = condition
        self.measurements = measurements
        self.objectives = objectives
        self.runbook = runbook
        self.groupingWindowSeconds = groupingWindowSeconds
        self.maximumNotificationsPerHour = maximumNotificationsPerHour
        self.authority = authority
    }
}

public enum OperationalRunbookID: String, Codable, CaseIterable, Sendable {
    case syncReplicationLagDiagnosis = "sync_replication_lag_diagnosis"
    case stuckUploadQueueRecovery = "stuck_upload_queue_recovery"
    case commandIdempotencyMismatchInvestigation = "command_idempotency_mismatch_investigation"
    case membershipRevocationLocalRemoval = "membership_revocation_local_removal"
    case accessIncident = "rls_sync_stream_access_incident"
    case postgresRestoreAndResync = "postgres_restore_and_resync"
    case storageObjectRecovery = "storage_object_recovery"
    case migrationAbortResumeRollback = "migration_abort_resume_rollback"
    case accountingMaintenanceMode = "accounting_maintenance_mode"
    case unsupportedClientStaleWriter = "unsupported_client_stale_writer"
    case reconciliationDriftTriage = "reconciliation_drift_triage"
    case credentialKeyCompromiseRotation = "credential_key_compromise_rotation"
}

public struct OperationalRunbookDefinition: Codable, Equatable, Sendable {
    public let id: OperationalRunbookID
    public let detection: OperationalReferenceCode
    public let impact: OperationalReferenceCode
    public let firstSafeAction: OperationalReferenceCode
    public let evidenceToPreserve: OperationalReferenceCode
    public let rollbackBoundary: OperationalReferenceCode
    public let escalationOwner: OperationalOwnerCode
    public let recoveryVerification: OperationalReferenceCode

    public init(
        id: OperationalRunbookID,
        detection: OperationalReferenceCode,
        impact: OperationalReferenceCode,
        firstSafeAction: OperationalReferenceCode,
        evidenceToPreserve: OperationalReferenceCode,
        rollbackBoundary: OperationalReferenceCode,
        escalationOwner: OperationalOwnerCode,
        recoveryVerification: OperationalReferenceCode
    ) {
        self.id = id
        self.detection = detection
        self.impact = impact
        self.firstSafeAction = firstSafeAction
        self.evidenceToPreserve = evidenceToPreserve
        self.rollbackBoundary = rollbackBoundary
        self.escalationOwner = escalationOwner
        self.recoveryVerification = recoveryVerification
    }
}

public enum ProvisionalPerformanceBudgetID: String, Codable, CaseIterable, Sendable {
    case localScreenQueryTime = "local_screen_query_time"
    case localOperationAcceptanceLatency = "local_operation_acceptance_latency"
    case coldSyncDuration = "cold_sync_duration"
    case coldSyncDownloadedBytes = "cold_sync_downloaded_bytes"
    case incrementalSyncLatency = "incremental_sync_latency"
    case localDatabaseSize = "local_database_size"
    case localQueryMemory = "local_query_memory"
    case attachmentQueueThroughput = "attachment_queue_throughput"
    case attachmentRetryAge = "attachment_retry_age"
    case serverCommandLatencyP50 = "server_command_latency_p50"
    case serverCommandLatencyP95 = "server_command_latency_p95"
    case serverCommandLatencyP99 = "server_command_latency_p99"
}

public enum PerformanceBudgetStatus: String, Codable, CaseIterable, Sendable {
    case pendingVerticalSpike = "pending_vertical_spike"
}

public struct ProvisionalPerformanceBudgetDefinition: Codable, Equatable, Sendable {
    public let id: ProvisionalPerformanceBudgetID
    public let measurement: OperationalMeasurementID
    public let status: PerformanceBudgetStatus

    public init(
        id: ProvisionalPerformanceBudgetID,
        measurement: OperationalMeasurementID,
        status: PerformanceBudgetStatus = .pendingVerticalSpike
    ) {
        self.id = id
        self.measurement = measurement
        self.status = status
    }
}

public struct OperationalControlRegistryDraft: Sendable {
    public let measurements: [OperationalMeasurementDefinition]
    public let objectives: [ServiceObjectiveDefinition]
    public let alerts: [AlertCandidateDefinition]
    public let runbooks: [OperationalRunbookDefinition]
    public let performanceBudgets: [ProvisionalPerformanceBudgetDefinition]

    public init(
        measurements: [OperationalMeasurementDefinition],
        objectives: [ServiceObjectiveDefinition],
        alerts: [AlertCandidateDefinition],
        runbooks: [OperationalRunbookDefinition],
        performanceBudgets: [ProvisionalPerformanceBudgetDefinition]
    ) {
        self.measurements = measurements
        self.objectives = objectives
        self.alerts = alerts
        self.runbooks = runbooks
        self.performanceBudgets = performanceBudgets
    }
}

public struct OperationalControlRegistry: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let measurements: [OperationalMeasurementDefinition]
    public let objectives: [ServiceObjectiveDefinition]
    public let alerts: [AlertCandidateDefinition]
    public let runbooks: [OperationalRunbookDefinition]
    public let performanceBudgets: [ProvisionalPerformanceBudgetDefinition]
    public let policyAuthority: OperationalPolicyAuthority
    public let authorityDisposition: OperationalAuthorityDisposition
    public let contentDigest: OperationFingerprint

    fileprivate var draft: OperationalControlRegistryDraft {
        OperationalControlRegistryDraft(
            measurements: measurements,
            objectives: objectives,
            alerts: alerts,
            runbooks: runbooks,
            performanceBudgets: performanceBudgets
        )
    }
}

public struct OperationalControlRegistryValidator: Sendable {
    public static let schemaVersion = 1
    public static let maximumCanonicalBytes = 131_072
    public static let maximumGroupingWindowSeconds: UInt32 = 86_400
    public static let maximumNotificationsPerHour: UInt16 = 60

    public init() {}

    public func validate(
        _ draft: OperationalControlRegistryDraft
    ) throws -> OperationalControlRegistry {
        let measurements = try normalizeMeasurements(draft.measurements)
        let measurementIDs = Set(measurements.map(\.id))
        let runbooks = try normalizeRunbooks(draft.runbooks)
        let runbookIDs = Set(runbooks.map(\.id))
        let objectives = try normalizeObjectives(
            draft.objectives,
            measurementIDs: measurementIDs,
            runbookIDs: runbookIDs
        )
        let objectiveIDs = Set(objectives.map(\.id))
        let alerts = try normalizeAlerts(
            draft.alerts,
            measurementIDs: measurementIDs,
            objectiveIDs: objectiveIDs,
            runbookIDs: runbookIDs
        )
        for objective in objectiveIDs where !alerts.contains(where: {
            $0.objectives.contains(objective)
        }) {
            throw OperationalControlFailure.objectiveWithoutAlert(objective)
        }
        let budgets = try normalizeBudgets(
            draft.performanceBudgets,
            measurementIDs: measurementIDs
        )
        let content = OperationalControlRegistryContent(
            schemaVersion: Self.schemaVersion,
            measurements: measurements,
            objectives: objectives,
            alerts: alerts,
            runbooks: runbooks,
            performanceBudgets: budgets,
            policyAuthority: .candidateOnly,
            authorityDisposition: .evidenceOnly
        )
        let registry = OperationalControlRegistry(
            schemaVersion: content.schemaVersion,
            measurements: content.measurements,
            objectives: content.objectives,
            alerts: content.alerts,
            runbooks: content.runbooks,
            performanceBudgets: content.performanceBudgets,
            policyAuthority: content.policyAuthority,
            authorityDisposition: content.authorityDisposition,
            contentDigest: try OperationalCanonical.digest(content)
        )
        let canonical = try OperationalCanonical.encode(registry)
        guard canonical.count <= Self.maximumCanonicalBytes else {
            throw OperationalControlFailure.registryTooLarge(
                actual: canonical.count,
                maximum: Self.maximumCanonicalBytes
            )
        }
        return registry
    }

    public func canonicalData(for registry: OperationalControlRegistry) throws -> Data {
        let validated = try validate(registry.draft)
        guard validated.contentDigest == registry.contentDigest else {
            throw OperationalControlFailure.registryDigestMismatch
        }
        guard validated == registry else {
            throw OperationalControlFailure.noncanonicalRegistry
        }
        return try OperationalCanonical.encode(validated)
    }

    public func decodeAndValidate(_ data: Data) throws -> OperationalControlRegistry {
        guard data.count <= Self.maximumCanonicalBytes else {
            throw OperationalControlFailure.registryTooLarge(
                actual: data.count,
                maximum: Self.maximumCanonicalBytes
            )
        }
        let decoded: OperationalControlRegistry
        do {
            decoded = try OperationalCanonical.decode(OperationalControlRegistry.self, from: data)
        } catch {
            throw OperationalControlFailure.malformedRegistry
        }
        let validated = try validate(decoded.draft)
        guard validated.contentDigest == decoded.contentDigest else {
            throw OperationalControlFailure.registryDigestMismatch
        }
        guard validated == decoded, try OperationalCanonical.encode(validated) == data else {
            throw OperationalControlFailure.noncanonicalRegistry
        }
        return validated
    }

    public func unassessedObjectives(
        in registry: OperationalControlRegistry
    ) throws -> [ServiceObjectiveAssessment] {
        let registry = try validate(registry.draft)
        return registry.objectives.map { definition in
            ServiceObjectiveAssessment(
                objective: definition.id,
                status: .notEvaluated,
                evidence: [],
                missingMeasurements: definition.requiredMeasurements,
                evidenceDigest: nil
            )
        }
    }

    public func evaluate(
        _ objective: ServiceObjectiveID,
        evidence: [ServiceObjectiveEvidence],
        in registry: OperationalControlRegistry
    ) throws -> ServiceObjectiveAssessment {
        let registry = try validate(registry.draft)
        guard let definition = registry.objectives.first(where: { $0.id == objective }) else {
            throw OperationalControlFailure.missingObjective(objective)
        }
        var byMeasurement: [OperationalMeasurementID: ServiceObjectiveEvidence] = [:]
        for item in evidence {
            guard item.sampleCount > 0 else {
                throw OperationalControlFailure.invalidEvidenceSample(item.measurement)
            }
            guard byMeasurement[item.measurement] == nil else {
                throw OperationalControlFailure.duplicateObjectiveEvidence(item.measurement)
            }
            byMeasurement[item.measurement] = item
        }
        let expected = Set(definition.requiredMeasurements)
        for measurement in byMeasurement.keys where !expected.contains(measurement) {
            throw OperationalControlFailure.unexpectedObjectiveEvidence(objective, measurement)
        }
        guard Set(byMeasurement.keys) == expected else {
            throw OperationalControlFailure.incompleteObjectiveEvidence(objective)
        }
        let sorted = evidence.sorted { $0.measurement.rawValue < $1.measurement.rawValue }
        return ServiceObjectiveAssessment(
            objective: objective,
            status: sorted.allSatisfy { $0.observedValue == 0 } ? .satisfied : .violated,
            evidence: sorted,
            missingMeasurements: [],
            evidenceDigest: try OperationalCanonical.digest(sorted)
        )
    }

    private func normalizeMeasurements(
        _ values: [OperationalMeasurementDefinition]
    ) throws -> [OperationalMeasurementDefinition] {
        var byID: [OperationalMeasurementID: OperationalMeasurementDefinition] = [:]
        for value in values {
            guard byID[value.id] == nil else {
                throw OperationalControlFailure.duplicateMeasurement(value.id)
            }
            byID[value.id] = value
        }
        for id in OperationalMeasurementID.allCases where byID[id] == nil {
            throw OperationalControlFailure.missingMeasurement(id)
        }
        return values.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    private func normalizeObjectives(
        _ values: [ServiceObjectiveDefinition],
        measurementIDs: Set<OperationalMeasurementID>,
        runbookIDs: Set<OperationalRunbookID>
    ) throws -> [ServiceObjectiveDefinition] {
        var byID: [ServiceObjectiveID: ServiceObjectiveDefinition] = [:]
        for value in values {
            guard byID[value.id] == nil else {
                throw OperationalControlFailure.duplicateObjective(value.id)
            }
            guard !value.requiredMeasurements.isEmpty else {
                throw OperationalControlFailure.emptyObjectiveMeasurements(value.id)
            }
            var seen: Set<OperationalMeasurementID> = []
            for measurement in value.requiredMeasurements {
                guard seen.insert(measurement).inserted else {
                    throw OperationalControlFailure.duplicateObjectiveMeasurement(
                        value.id,
                        measurement
                    )
                }
                guard measurementIDs.contains(measurement) else {
                    throw OperationalControlFailure.unknownMeasurementReference(
                        value.id.rawValue,
                        measurement
                    )
                }
            }
            guard runbookIDs.contains(value.runbook) else {
                throw OperationalControlFailure.unknownRunbookReference(
                    value.id.rawValue,
                    value.runbook
                )
            }
            byID[value.id] = ServiceObjectiveDefinition(
                id: value.id,
                requiredMeasurements: value.requiredMeasurements.sorted {
                    $0.rawValue < $1.rawValue
                },
                threshold: value.threshold,
                owner: value.owner,
                runbook: value.runbook
            )
        }
        for id in ServiceObjectiveID.allCases where byID[id] == nil {
            throw OperationalControlFailure.missingObjective(id)
        }
        return byID.values.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    private func normalizeAlerts(
        _ values: [AlertCandidateDefinition],
        measurementIDs: Set<OperationalMeasurementID>,
        objectiveIDs: Set<ServiceObjectiveID>,
        runbookIDs: Set<OperationalRunbookID>
    ) throws -> [AlertCandidateDefinition] {
        var byID: [AlertCandidateID: AlertCandidateDefinition] = [:]
        for value in values {
            guard byID[value.id] == nil else {
                throw OperationalControlFailure.duplicateAlert(value.id)
            }
            guard !value.measurements.isEmpty,
                  value.groupingWindowSeconds > 0,
                  value.groupingWindowSeconds <= Self.maximumGroupingWindowSeconds,
                  value.maximumNotificationsPerHour > 0,
                  value.maximumNotificationsPerHour <= Self.maximumNotificationsPerHour else {
                throw OperationalControlFailure.invalidAlertPolicy(value.id)
            }
            let measurements = try uniqueSorted(
                value.measurements,
                alert: value.id,
                known: measurementIDs
            )
            var seenObjectives: Set<ServiceObjectiveID> = []
            for objective in value.objectives {
                guard seenObjectives.insert(objective).inserted,
                      objectiveIDs.contains(objective) else {
                    throw OperationalControlFailure.unknownObjectiveReference(value.id, objective)
                }
            }
            guard runbookIDs.contains(value.runbook) else {
                throw OperationalControlFailure.unknownRunbookReference(
                    value.id.rawValue,
                    value.runbook
                )
            }
            byID[value.id] = AlertCandidateDefinition(
                id: value.id,
                severity: value.severity,
                condition: value.condition,
                measurements: measurements,
                objectives: value.objectives.sorted { $0.rawValue < $1.rawValue },
                runbook: value.runbook,
                groupingWindowSeconds: value.groupingWindowSeconds,
                maximumNotificationsPerHour: value.maximumNotificationsPerHour,
                authority: .candidateOnly
            )
        }
        for id in AlertCandidateID.allCases where byID[id] == nil {
            throw OperationalControlFailure.missingAlert(id)
        }
        return byID.values.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    private func uniqueSorted(
        _ values: [OperationalMeasurementID],
        alert: AlertCandidateID,
        known: Set<OperationalMeasurementID>
    ) throws -> [OperationalMeasurementID] {
        var seen: Set<OperationalMeasurementID> = []
        for measurement in values {
            guard seen.insert(measurement).inserted else {
                throw OperationalControlFailure.invalidAlertPolicy(alert)
            }
            guard known.contains(measurement) else {
                throw OperationalControlFailure.unknownMeasurementReference(
                    alert.rawValue,
                    measurement
                )
            }
        }
        return values.sorted { $0.rawValue < $1.rawValue }
    }

    private func normalizeRunbooks(
        _ values: [OperationalRunbookDefinition]
    ) throws -> [OperationalRunbookDefinition] {
        var byID: [OperationalRunbookID: OperationalRunbookDefinition] = [:]
        for value in values {
            guard byID[value.id] == nil else {
                throw OperationalControlFailure.duplicateRunbook(value.id)
            }
            let references = [
                value.detection.rawValue,
                value.impact.rawValue,
                value.firstSafeAction.rawValue,
                value.evidenceToPreserve.rawValue,
                value.rollbackBoundary.rawValue,
                value.escalationOwner.rawValue,
                value.recoveryVerification.rawValue
            ]
            guard Set(references).count == references.count else {
                throw OperationalControlFailure.invalidRunbook(value.id)
            }
            byID[value.id] = value
        }
        for id in OperationalRunbookID.allCases where byID[id] == nil {
            throw OperationalControlFailure.missingRunbook(id)
        }
        return byID.values.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    private func normalizeBudgets(
        _ values: [ProvisionalPerformanceBudgetDefinition],
        measurementIDs: Set<OperationalMeasurementID>
    ) throws -> [ProvisionalPerformanceBudgetDefinition] {
        var byID: [ProvisionalPerformanceBudgetID: ProvisionalPerformanceBudgetDefinition] = [:]
        for value in values {
            guard byID[value.id] == nil else {
                throw OperationalControlFailure.duplicatePerformanceBudget(value.id)
            }
            guard measurementIDs.contains(value.measurement) else {
                throw OperationalControlFailure.unknownMeasurementReference(
                    value.id.rawValue,
                    value.measurement
                )
            }
            byID[value.id] = .init(
                id: value.id,
                measurement: value.measurement,
                status: .pendingVerticalSpike
            )
        }
        for id in ProvisionalPerformanceBudgetID.allCases where byID[id] == nil {
            throw OperationalControlFailure.missingPerformanceBudget(id)
        }
        return byID.values.sorted { $0.id.rawValue < $1.id.rawValue }
    }
}

private struct OperationalControlRegistryContent: Codable {
    let schemaVersion: Int
    let measurements: [OperationalMeasurementDefinition]
    let objectives: [ServiceObjectiveDefinition]
    let alerts: [AlertCandidateDefinition]
    let runbooks: [OperationalRunbookDefinition]
    let performanceBudgets: [ProvisionalPerformanceBudgetDefinition]
    let policyAuthority: OperationalPolicyAuthority
    let authorityDisposition: OperationalAuthorityDisposition
}

public enum TargetOperationalControlRegistry {
    public static func make() throws -> OperationalControlRegistry {
        try OperationalControlRegistryValidator().validate(draft())
    }

    public static func draft() throws -> OperationalControlRegistryDraft {
        OperationalControlRegistryDraft(
            measurements: try measurements(),
            objectives: try objectives(),
            alerts: alerts(),
            runbooks: try runbooks(),
            performanceBudgets: performanceBudgets()
        )
    }

    public static func measurements() throws -> [OperationalMeasurementDefinition] {
        try OperationalMeasurementID.allCases.map { id in
            let scope = scope(for: id)
            return OperationalMeasurementDefinition(
                id: id,
                unit: unit(for: id),
                scope: scope,
                owner: try owner(for: scope),
                collectionState: locallyDerived.contains(id) ? .derivedLocally : .planned
            )
        }
    }

    public static func objectives() throws -> [ServiceObjectiveDefinition] {
        let owner = try OperationalOwnerCode(validating: "ledger_operability")
        return [
            .init(id: .durability, requiredMeasurements: [.lostAcceptedOperationCount], threshold: .exactZero, owner: owner, runbook: .stuckUploadQueueRecovery),
            .init(id: .idempotency, requiredMeasurements: [.duplicateAuthoritativeEffectCount], threshold: .exactZero, owner: owner, runbook: .commandIdempotencyMismatchInvestigation),
            .init(id: .integrity, requiredMeasurements: [.unexplainedReconciliationDifferenceCount], threshold: .exactZero, owner: owner, runbook: .reconciliationDriftTriage),
            .init(id: .isolation, requiredMeasurements: [.unauthorizedLocalRowCount], threshold: .exactZero, owner: owner, runbook: .accessIncident),
            .init(id: .queueHealth, requiredMeasurements: [.poisonOperationStarvationCount], threshold: .exactZero, owner: owner, runbook: .stuckUploadQueueRecovery),
            .init(id: .offlineAvailability, requiredMeasurements: [.cachedCoreOfflineFailureCount], threshold: .exactZero, owner: owner, runbook: .membershipRevocationLocalRemoval),
            .init(id: .recovery, requiredMeasurements: [.alertWithoutOwnerOrRunbookCount], threshold: .exactZero, owner: owner, runbook: .unsupportedClientStaleWriter)
        ]
    }

    public static func alerts() -> [AlertCandidateDefinition] {
        let high: AlertSeverity = .highUrgency
        let lower: AlertSeverity = .lowerUrgency
        return [
            alert(.sustainedCommandApplyFailure, high, .sustainedFailure, [.serverTransientFailureRate, .serverPermanentFailureRate], [.idempotency, .queueHealth], .stuckUploadQueueRecovery),
            alert(.replicationHaltedOrLagged, high, .approvedThresholdRequired, [.replicationLag], [.offlineAvailability], .syncReplicationLagDiagnosis),
            alert(.financialReconciliationDrift, high, .nonzero, [.migrationReconciliationDriftCount, .unexplainedReconciliationDifferenceCount], [.integrity], .reconciliationDriftTriage),
            alert(.crossTenantAuthorizationAnomaly, high, .nonzero, [.suspiciousCrossScopeAttemptCount], [.isolation], .accessIncident),
            alert(.migrationProductionGuardViolation, high, .nonzero, [.migrationProductionGuardViolationCount], [.integrity], .migrationAbortResumeRollback),
            alert(.cutoverTargetOutage, high, .unhealthyState, [.targetDatabaseAvailabilityState, .targetStorageAvailabilityState], [.recovery], .postgresRestoreAndResync),
            alert(.growingQueueAge, lower, .approvedThresholdRequired, [.oldestPendingCommandAge], [.queueHealth], .stuckUploadQueueRecovery),
            alert(.repeatedStaleRejection, lower, .approvedThresholdRequired, [.rejectedCommandCount, .conflictedCommandCount], [.queueHealth], .unsupportedClientStaleWriter),
            alert(.increasedDecodeMappingFailure, lower, .approvedThresholdRequired, [.localDecodeMappingFailureCount], [.recovery], .unsupportedClientStaleWriter),
            alert(.risingHostedSyncCost, lower, .approvedThresholdRequired, [.hostedDataBytes, .synchronizedBytesPerMonth], [.recovery], .syncReplicationLagDiagnosis),
            alert(.orphanAttachment, lower, .nonzero, [.orphanAttachmentCount], [.durability], .storageObjectRecovery),
            alert(.slowQueryOrRLSRegression, lower, .approvedThresholdRequired, [.postgresSlowQueryCount, .rlsDenialCount], [.isolation], .accessIncident)
        ]
    }

    public static func runbooks() throws -> [OperationalRunbookDefinition] {
        try OperationalRunbookID.allCases.map { id in
            let prefix = id.rawValue
            return OperationalRunbookDefinition(
                id: id,
                detection: try reference(prefix, "detect"),
                impact: try reference(prefix, "impact"),
                firstSafeAction: try reference(prefix, "first_action"),
                evidenceToPreserve: try reference(prefix, "evidence"),
                rollbackBoundary: try reference(prefix, "rollback"),
                escalationOwner: try OperationalOwnerCode(validating: ownerName(for: id)),
                recoveryVerification: try reference(prefix, "verify_recovery")
            )
        }
    }

    public static func performanceBudgets() -> [ProvisionalPerformanceBudgetDefinition] {
        [
            .init(id: .localScreenQueryTime, measurement: .localQueryLatency),
            .init(id: .localOperationAcceptanceLatency, measurement: .localOperationAcceptanceLatency),
            .init(id: .coldSyncDuration, measurement: .initialSyncDuration),
            .init(id: .coldSyncDownloadedBytes, measurement: .initialSyncDownloadedBytes),
            .init(id: .incrementalSyncLatency, measurement: .incrementalSyncDuration),
            .init(id: .localDatabaseSize, measurement: .localDatabaseSize),
            .init(id: .localQueryMemory, measurement: .localQueryMemory),
            .init(id: .attachmentQueueThroughput, measurement: .attachmentQueueThroughput),
            .init(id: .attachmentRetryAge, measurement: .oldestPendingAttachmentAge),
            .init(id: .serverCommandLatencyP50, measurement: .serverCommandLatency),
            .init(id: .serverCommandLatencyP95, measurement: .serverCommandLatency),
            .init(id: .serverCommandLatencyP99, measurement: .serverCommandLatency)
        ]
    }

    private static let locallyDerived: Set<OperationalMeasurementID> = [
        .activeSubscriptionReadiness,
        .lastCompletedSync,
        .syncLag,
        .pendingCommandCount,
        .oldestPendingCommandAge,
        .rejectedCommandCount,
        .pendingAttachmentCount,
        .oldestPendingAttachmentAge
    ]

    private static func unit(for id: OperationalMeasurementID) -> OperationalMeasurementUnit {
        switch id {
        case .appBuildBackendContractSchemaVersions: return .version
        case .activeSubscriptionReadiness, .deploymentReprocessingState,
             .targetDatabaseAvailabilityState, .targetStorageAvailabilityState:
            return .state
        case .localDatabaseOpenLatency, .localQueryLatency,
             .localOperationAcceptanceLatency, .lastCompletedSync, .syncLag,
             .oldestPendingCommandAge, .oldestPendingAttachmentAge,
             .offlineSessionDuration, .serverCommandLatency, .replicationLag,
             .initialSyncDuration, .incrementalSyncDuration, .oldestPendingUploadAge:
            return .milliseconds
        case .localQueryMemory, .localDatabaseSize, .postgresDiskBytes,
             .postgresIOBytes, .hostedDataBytes, .synchronizedBytesPerMonth,
             .initialSyncDownloadedBytes:
            return .bytes
        case .attachmentQueueThroughput: return .bytesPerSecond
        case .serverTransientFailureRate, .serverPermanentFailureRate,
             .postgresCPUUtilization:
            return .basisPoints
        default: return .count
        }
    }

    private static func scope(for id: OperationalMeasurementID) -> OperationalMeasurementScope {
        switch id {
        case .serverCommandCount, .serverCommandLatency, .serverCommandOutcomeCount,
             .serverRetryCount, .serverDeduplicationCount,
             .serverTransientFailureRate, .serverPermanentFailureRate,
             .serverLockWaitCount, .serverDeadlockCount,
             .serverSerializationRetryCount, .rlsDenialCount,
             .suspiciousCrossScopeAttemptCount, .migrationReconciliationDriftCount,
             .migrationProductionGuardViolationCount, .postgresCPUUtilization,
             .postgresConnectionCount, .postgresDiskBytes, .postgresIOBytes,
             .postgresSlowQueryCount, .targetDatabaseAvailabilityState,
             .storageUploadErrorCount, .storageDownloadErrorCount,
             .storageDeleteErrorCount, .orphanAttachmentCount,
             .targetStorageAvailabilityState, .edgeFunctionFailureCount,
             .externalIntegrationFailureCount, .mcpCommandActivityCount,
             .mcpReadActivityCount,
             .duplicateAuthoritativeEffectCount,
             .unexplainedReconciliationDifferenceCount:
            return .server
        case .replicationLag, .activeClientCount, .peakClientCount, .hostedDataBytes,
             .synchronizedBytesPerMonth, .streamCountPerUser, .initialSyncDuration,
             .initialSyncDownloadedBytes, .incrementalSyncDuration, .uploadQueueErrorCount,
             .oldestPendingUploadAge, .deploymentReprocessingState,
             .unauthorizedLocalRowCount:
            return .replication
        case .lostAcceptedOperationCount, .poisonOperationStarvationCount,
             .cachedCoreOfflineFailureCount, .alertWithoutOwnerOrRunbookCount:
            return .crossCutting
        default: return .client
        }
    }

    private static func owner(
        for scope: OperationalMeasurementScope
    ) throws -> OperationalOwnerCode {
        let value: String
        switch scope {
        case .client: value = "ledger_client_runtime"
        case .server: value = "ledger_server_runtime"
        case .replication: value = "ledger_replication_runtime"
        case .crossCutting: value = "ledger_operability"
        }
        return try OperationalOwnerCode(validating: value)
    }

    private static func alert(
        _ id: AlertCandidateID,
        _ severity: AlertSeverity,
        _ condition: OperationalAlertCondition,
        _ measurements: [OperationalMeasurementID],
        _ objectives: [ServiceObjectiveID],
        _ runbook: OperationalRunbookID
    ) -> AlertCandidateDefinition {
        AlertCandidateDefinition(
            id: id,
            severity: severity,
            condition: condition,
            measurements: measurements,
            objectives: objectives,
            runbook: runbook,
            groupingWindowSeconds: 300,
            maximumNotificationsPerHour: severity == .highUrgency ? 6 : 2
        )
    }

    private static func reference(
        _ prefix: String,
        _ suffix: String
    ) throws -> OperationalReferenceCode {
        let maximumPrefixLength = 80 - suffix.count - 1
        let boundedPrefix = String(prefix.prefix(maximumPrefixLength))
        return try OperationalReferenceCode(validating: "\(boundedPrefix)_\(suffix)")
    }

    private static func ownerName(for id: OperationalRunbookID) -> String {
        switch id {
        case .syncReplicationLagDiagnosis: return "ledger_replication_owner"
        case .stuckUploadQueueRecovery: return "ledger_client_sync_owner"
        case .commandIdempotencyMismatchInvestigation: return "ledger_command_owner"
        case .membershipRevocationLocalRemoval, .accessIncident,
             .credentialKeyCompromiseRotation:
            return "ledger_security_owner"
        case .postgresRestoreAndResync: return "ledger_database_owner"
        case .storageObjectRecovery: return "ledger_storage_owner"
        case .migrationAbortResumeRollback: return "ledger_migration_owner"
        case .accountingMaintenanceMode, .reconciliationDriftTriage:
            return "ledger_accounting_owner"
        case .unsupportedClientStaleWriter: return "ledger_release_owner"
        }
    }
}

private enum OperationalCanonical {
    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(value)
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: data)
    }

    static func digest<Value: Encodable>(_ value: Value) throws -> OperationFingerprint {
        let digest = SHA256.hash(data: try encode(value))
            .map { String(format: "%02x", $0) }
            .joined()
        return try OperationFingerprint(validating: digest)
    }
}
