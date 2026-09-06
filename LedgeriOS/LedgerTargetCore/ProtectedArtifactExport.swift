import CryptoKit
import Foundation

public enum ProtectedArtifactFailure: Error, Equatable, Sendable {
    case invalidExportID
    case invalidSnapshotID
    case invalidVisibilityScopeID
    case invalidProfileVersion
    case invalidAuthorityVersion
    case invalidSHA256
    case invalidEpochMilliseconds
    case emptyAllowedContentKinds
    case emptyAllowedDestinationIntents
    case duplicateAllowedContentKind
    case duplicateAllowedDestinationIntent
    case invalidMaximumOutputByteCount
    case invalidMaximumLeaseDuration
    case invalidMaximumCanonicalBytes
    case contentKindNotAllowed(ProtectedArtifactContentKind)
    case destinationIntentNotAllowed(ProtectedArtifactDestinationIntent)
    case invalidLeaseExpiry
    case leaseDurationExceeded
    case policyMismatch
    case requestFingerprintMismatch
    case invalidOutputByteCount
    case outputByteCountExceeded
    case outputHashMismatch
    case eventTimestampOutOfOrder
    case eventAfterLeaseExpiry
    case leaseExpiryFailureBeforeExpiry
    case nonExpiryFailureAfterExpiry
    case illegalLifecycleTransition(
        from: ProtectedArtifactLifecyclePhase,
        event: ProtectedArtifactLifecycleEventKind
    )
    case tooManyLifecycleEvents(maximum: Int)
    case receiptNotTerminal
    case receiptMismatch
    case authorityDispositionMismatch
    case schemaVersionMismatch
    case contentDigestMismatch
    case noncanonicalEvidence
    case evidenceTooLarge(actual: Int, maximum: Int)
    case malformedEvidence

    public var diagnosticCode: String {
        switch self {
        case .invalidExportID: return "protected_artifact_export_id_invalid"
        case .invalidSnapshotID: return "protected_artifact_snapshot_id_invalid"
        case .invalidVisibilityScopeID: return "protected_artifact_visibility_scope_invalid"
        case .invalidProfileVersion: return "protected_artifact_profile_version_invalid"
        case .invalidAuthorityVersion: return "protected_artifact_authority_version_invalid"
        case .invalidSHA256: return "protected_artifact_sha256_invalid"
        case .invalidEpochMilliseconds: return "protected_artifact_epoch_millis_invalid"
        case .emptyAllowedContentKinds: return "protected_artifact_content_kinds_empty"
        case .emptyAllowedDestinationIntents: return "protected_artifact_destination_intents_empty"
        case .duplicateAllowedContentKind: return "protected_artifact_content_kind_duplicate"
        case .duplicateAllowedDestinationIntent: return "protected_artifact_destination_intent_duplicate"
        case .invalidMaximumOutputByteCount: return "protected_artifact_output_limit_invalid"
        case .invalidMaximumLeaseDuration: return "protected_artifact_lease_limit_invalid"
        case .invalidMaximumCanonicalBytes: return "protected_artifact_evidence_limit_invalid"
        case .contentKindNotAllowed: return "protected_artifact_content_kind_not_allowed"
        case .destinationIntentNotAllowed: return "protected_artifact_destination_intent_not_allowed"
        case .invalidLeaseExpiry: return "protected_artifact_lease_expiry_invalid"
        case .leaseDurationExceeded: return "protected_artifact_lease_duration_exceeded"
        case .policyMismatch: return "protected_artifact_policy_mismatch"
        case .requestFingerprintMismatch: return "protected_artifact_request_fingerprint_mismatch"
        case .invalidOutputByteCount: return "protected_artifact_output_byte_count_invalid"
        case .outputByteCountExceeded: return "protected_artifact_output_byte_count_exceeded"
        case .outputHashMismatch: return "protected_artifact_output_hash_mismatch"
        case .eventTimestampOutOfOrder: return "protected_artifact_event_time_out_of_order"
        case .eventAfterLeaseExpiry: return "protected_artifact_event_after_lease_expiry"
        case .leaseExpiryFailureBeforeExpiry: return "protected_artifact_expiry_failure_too_early"
        case .nonExpiryFailureAfterExpiry: return "protected_artifact_failure_after_expiry"
        case .illegalLifecycleTransition: return "protected_artifact_transition_illegal"
        case .tooManyLifecycleEvents: return "protected_artifact_events_too_many"
        case .receiptNotTerminal: return "protected_artifact_receipt_not_terminal"
        case .receiptMismatch: return "protected_artifact_receipt_mismatch"
        case .authorityDispositionMismatch: return "protected_artifact_authority_disposition_mismatch"
        case .schemaVersionMismatch: return "protected_artifact_schema_mismatch"
        case .contentDigestMismatch: return "protected_artifact_content_digest_mismatch"
        case .noncanonicalEvidence: return "protected_artifact_evidence_noncanonical"
        case .evidenceTooLarge: return "protected_artifact_evidence_too_large"
        case .malformedEvidence: return "protected_artifact_evidence_malformed"
        }
    }
}

public enum ProtectedArtifactContentKind: String, Codable, CaseIterable, Sendable {
    case pdf
    case csv
    case html
    case plainText = "plain_text"
    case image
    case archive
    case binary
}

public enum ProtectedArtifactDestinationIntent: String, Codable, CaseIterable, Sendable {
    case localPreview = "local_preview"
    case systemActivity = "system_activity"
    case printController = "print_controller"
    case userSelectedFile = "user_selected_file"
}

public enum ProtectedArtifactDestinationOutcome: String, Codable, CaseIterable, Sendable {
    case destinationAccepted = "destination_accepted"
    case cancelled
    case failed
    case notAttempted = "not_attempted"
}

public enum ProtectedArtifactOperationalFailureCode: String, Codable, CaseIterable, Sendable {
    case materializationFailed = "materialization_failed"
    case protectionUnavailable = "protection_unavailable"
    case leaseExpired = "lease_expired"
    case cancelledBySystem = "cancelled_by_system"
}

public enum ProtectedArtifactLifecyclePhase: String, Codable, CaseIterable, Sendable {
    case requested
    case materialized
    case handoffRecorded = "handoff_recorded"
    case cleanupRequired = "cleanup_required"
    case cleaned
    case cancelled
    case failed
}

public enum ProtectedArtifactLifecycleEventKind: String, Codable, CaseIterable, Sendable {
    case requested
    case materialized
    case handoffRecorded = "handoff_recorded"
    case cleanupRequired = "cleanup_required"
    case cleaned
    case cancelled
    case failed
}

public enum ProtectedArtifactCleanupDisposition: String, Codable, CaseIterable, Sendable {
    case notRequired = "not_required"
    case cleanupRecorded = "cleanup_recorded"
}

public enum ProtectedArtifactAuthorityDisposition: String, Codable, CaseIterable, Sendable {
    case evidenceOnly = "evidence_only"
}

public struct ProtectedArtifactExportID: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        guard ProtectedArtifactValidation.isOpaqueID(rawValue) else {
            throw ProtectedArtifactFailure.invalidExportID
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(validating: container.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid protected artifact export ID"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ProtectedArtifactSnapshotID: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        guard ProtectedArtifactValidation.isOpaqueID(rawValue) else {
            throw ProtectedArtifactFailure.invalidSnapshotID
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(validating: container.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid protected artifact snapshot ID"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ProtectedArtifactVisibilityScopeID: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        guard ProtectedArtifactValidation.isLowercaseHex(rawValue, count: 64) else {
            throw ProtectedArtifactFailure.invalidVisibilityScopeID
        }
        self.rawValue = rawValue
    }

    public static func make(bytes: Data) throws -> Self {
        try Self(validating: ProtectedArtifactValidation.sha256(bytes))
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(validating: container.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid protected artifact visibility scope"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ProtectedArtifactProfileVersion: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        guard ProtectedArtifactValidation.isStableCode(rawValue) else {
            throw ProtectedArtifactFailure.invalidProfileVersion
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(validating: container.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid protected artifact profile version"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ProtectedArtifactAuthorityVersion: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        guard ProtectedArtifactValidation.isStableCode(rawValue) else {
            throw ProtectedArtifactFailure.invalidAuthorityVersion
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(validating: container.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid protected artifact authority version"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ProtectedArtifactSHA256: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        guard ProtectedArtifactValidation.isLowercaseHex(rawValue, count: 64) else {
            throw ProtectedArtifactFailure.invalidSHA256
        }
        self.rawValue = rawValue
    }

    public static func make(bytes: Data) throws -> Self {
        try Self(validating: ProtectedArtifactValidation.sha256(bytes))
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(validating: container.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid protected artifact SHA-256"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ProtectedArtifactEpochMilliseconds: Codable, Equatable, Hashable, Comparable, Sendable {
    public let rawValue: Int64

    public init(validating rawValue: Int64) throws {
        guard rawValue > 0 else {
            throw ProtectedArtifactFailure.invalidEpochMilliseconds
        }
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(validating: container.decode(Int64.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid protected artifact epoch milliseconds"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ProtectedArtifactSnapshotReference: Codable, Equatable, Sendable {
    public let snapshotID: ProtectedArtifactSnapshotID
    public let snapshotHash: ProtectedArtifactSHA256
    public let visibilityScopeID: ProtectedArtifactVisibilityScopeID
    public let profileVersion: ProtectedArtifactProfileVersion
    public let authorityVersion: ProtectedArtifactAuthorityVersion

    public init(
        snapshotID: ProtectedArtifactSnapshotID,
        snapshotHash: ProtectedArtifactSHA256,
        visibilityScopeID: ProtectedArtifactVisibilityScopeID,
        profileVersion: ProtectedArtifactProfileVersion,
        authorityVersion: ProtectedArtifactAuthorityVersion
    ) {
        self.snapshotID = snapshotID
        self.snapshotHash = snapshotHash
        self.visibilityScopeID = visibilityScopeID
        self.profileVersion = profileVersion
        self.authorityVersion = authorityVersion
    }
}

public struct ProtectedArtifactExportPolicy: Equatable, Sendable {
    public static let absoluteMaximumOutputByteCount = 1_073_741_824
    public static let absoluteMaximumLeaseDurationMilliseconds: Int64 = 86_400_000
    public static let minimumCanonicalByteCount = 512
    public static let absoluteMaximumCanonicalByteCount = 65_536

    public let allowedContentKinds: [ProtectedArtifactContentKind]
    public let allowedDestinationIntents: [ProtectedArtifactDestinationIntent]
    public let maximumOutputByteCount: Int
    public let maximumLeaseDurationMilliseconds: Int64
    public let maximumCanonicalByteCount: Int
    public let fingerprint: ProtectedArtifactSHA256

    public init(
        allowedContentKinds: [ProtectedArtifactContentKind],
        allowedDestinationIntents: [ProtectedArtifactDestinationIntent],
        maximumOutputByteCount: Int,
        maximumLeaseDurationMilliseconds: Int64,
        maximumCanonicalByteCount: Int = 4_096
    ) throws {
        guard !allowedContentKinds.isEmpty else {
            throw ProtectedArtifactFailure.emptyAllowedContentKinds
        }
        guard !allowedDestinationIntents.isEmpty else {
            throw ProtectedArtifactFailure.emptyAllowedDestinationIntents
        }
        guard Set(allowedContentKinds.map(\.rawValue)).count == allowedContentKinds.count else {
            throw ProtectedArtifactFailure.duplicateAllowedContentKind
        }
        guard Set(allowedDestinationIntents.map(\.rawValue)).count == allowedDestinationIntents.count else {
            throw ProtectedArtifactFailure.duplicateAllowedDestinationIntent
        }
        guard maximumOutputByteCount > 0,
              maximumOutputByteCount <= Self.absoluteMaximumOutputByteCount else {
            throw ProtectedArtifactFailure.invalidMaximumOutputByteCount
        }
        guard maximumLeaseDurationMilliseconds > 0,
              maximumLeaseDurationMilliseconds <= Self.absoluteMaximumLeaseDurationMilliseconds else {
            throw ProtectedArtifactFailure.invalidMaximumLeaseDuration
        }
        guard maximumCanonicalByteCount >= Self.minimumCanonicalByteCount,
              maximumCanonicalByteCount <= Self.absoluteMaximumCanonicalByteCount else {
            throw ProtectedArtifactFailure.invalidMaximumCanonicalBytes
        }

        let sortedContentKinds = allowedContentKinds.sorted { $0.rawValue < $1.rawValue }
        let sortedDestinationIntents = allowedDestinationIntents.sorted { $0.rawValue < $1.rawValue }
        let fingerprintContent = ProtectedArtifactPolicyFingerprintContent(
            allowedContentKinds: sortedContentKinds,
            allowedDestinationIntents: sortedDestinationIntents,
            maximumOutputByteCount: maximumOutputByteCount,
            maximumLeaseDurationMilliseconds: maximumLeaseDurationMilliseconds,
            maximumCanonicalByteCount: maximumCanonicalByteCount
        )

        self.allowedContentKinds = sortedContentKinds
        self.allowedDestinationIntents = sortedDestinationIntents
        self.maximumOutputByteCount = maximumOutputByteCount
        self.maximumLeaseDurationMilliseconds = maximumLeaseDurationMilliseconds
        self.maximumCanonicalByteCount = maximumCanonicalByteCount
        self.fingerprint = try ProtectedArtifactSHA256.make(
            bytes: ProtectedArtifactValidation.encodeSorted(fingerprintContent)
        )
    }
}

public struct ProtectedArtifactExportRequestDraft: Equatable, Sendable {
    public let exportID: ProtectedArtifactExportID
    public let snapshot: ProtectedArtifactSnapshotReference
    public let contentKind: ProtectedArtifactContentKind
    public let destinationIntent: ProtectedArtifactDestinationIntent
    public let requestedAt: ProtectedArtifactEpochMilliseconds
    public let expiresAt: ProtectedArtifactEpochMilliseconds
    public let maximumOutputByteCount: Int

    public init(
        exportID: ProtectedArtifactExportID,
        snapshot: ProtectedArtifactSnapshotReference,
        contentKind: ProtectedArtifactContentKind,
        destinationIntent: ProtectedArtifactDestinationIntent,
        requestedAt: ProtectedArtifactEpochMilliseconds,
        expiresAt: ProtectedArtifactEpochMilliseconds,
        maximumOutputByteCount: Int
    ) {
        self.exportID = exportID
        self.snapshot = snapshot
        self.contentKind = contentKind
        self.destinationIntent = destinationIntent
        self.requestedAt = requestedAt
        self.expiresAt = expiresAt
        self.maximumOutputByteCount = maximumOutputByteCount
    }
}

public struct ProtectedArtifactExportRequest: Equatable, Sendable {
    public let exportID: ProtectedArtifactExportID
    public let snapshot: ProtectedArtifactSnapshotReference
    public let contentKind: ProtectedArtifactContentKind
    public let destinationIntent: ProtectedArtifactDestinationIntent
    public let requestedAt: ProtectedArtifactEpochMilliseconds
    public let expiresAt: ProtectedArtifactEpochMilliseconds
    public let maximumOutputByteCount: Int
    public let maximumCanonicalByteCount: Int
    public let policyFingerprint: ProtectedArtifactSHA256
    public let requestFingerprint: ProtectedArtifactSHA256

    fileprivate init(
        draft: ProtectedArtifactExportRequestDraft,
        maximumCanonicalByteCount: Int,
        policyFingerprint: ProtectedArtifactSHA256,
        requestFingerprint: ProtectedArtifactSHA256
    ) {
        self.exportID = draft.exportID
        self.snapshot = draft.snapshot
        self.contentKind = draft.contentKind
        self.destinationIntent = draft.destinationIntent
        self.requestedAt = draft.requestedAt
        self.expiresAt = draft.expiresAt
        self.maximumOutputByteCount = draft.maximumOutputByteCount
        self.maximumCanonicalByteCount = maximumCanonicalByteCount
        self.policyFingerprint = policyFingerprint
        self.requestFingerprint = requestFingerprint
    }

    public var lease: ProtectedArtifactLease {
        ProtectedArtifactLease(request: self)
    }
}

public struct ProtectedArtifactLease: Equatable, Sendable {
    public let exportID: ProtectedArtifactExportID
    public let requestFingerprint: ProtectedArtifactSHA256
    public let expiresAt: ProtectedArtifactEpochMilliseconds
    public let maximumOutputByteCount: Int

    fileprivate init(request: ProtectedArtifactExportRequest) {
        exportID = request.exportID
        requestFingerprint = request.requestFingerprint
        expiresAt = request.expiresAt
        maximumOutputByteCount = request.maximumOutputByteCount
    }

    public func isExpired(at time: ProtectedArtifactEpochMilliseconds) -> Bool {
        time >= expiresAt
    }
}

public struct ProtectedArtifactMaterializationEvidence: Codable, Equatable, Sendable {
    public let requestFingerprint: ProtectedArtifactSHA256
    public let recordedAt: ProtectedArtifactEpochMilliseconds
    public let byteCount: Int
    public let outputHash: ProtectedArtifactSHA256

    public init(
        requestFingerprint: ProtectedArtifactSHA256,
        recordedAt: ProtectedArtifactEpochMilliseconds,
        byteCount: Int,
        outputHash: ProtectedArtifactSHA256
    ) {
        self.requestFingerprint = requestFingerprint
        self.recordedAt = recordedAt
        self.byteCount = byteCount
        self.outputHash = outputHash
    }
}

public struct ProtectedArtifactHandoffEvidence: Codable, Equatable, Sendable {
    public let requestFingerprint: ProtectedArtifactSHA256
    public let outputHash: ProtectedArtifactSHA256
    public let recordedAt: ProtectedArtifactEpochMilliseconds
    public let outcome: ProtectedArtifactDestinationOutcome

    public init(
        requestFingerprint: ProtectedArtifactSHA256,
        outputHash: ProtectedArtifactSHA256,
        recordedAt: ProtectedArtifactEpochMilliseconds,
        outcome: ProtectedArtifactDestinationOutcome
    ) {
        self.requestFingerprint = requestFingerprint
        self.outputHash = outputHash
        self.recordedAt = recordedAt
        self.outcome = outcome
    }
}

public struct ProtectedArtifactCleanupEvidence: Codable, Equatable, Sendable {
    public let requestFingerprint: ProtectedArtifactSHA256
    public let outputHash: ProtectedArtifactSHA256
    public let recordedAt: ProtectedArtifactEpochMilliseconds

    public init(
        requestFingerprint: ProtectedArtifactSHA256,
        outputHash: ProtectedArtifactSHA256,
        recordedAt: ProtectedArtifactEpochMilliseconds
    ) {
        self.requestFingerprint = requestFingerprint
        self.outputHash = outputHash
        self.recordedAt = recordedAt
    }
}

public struct ProtectedArtifactFailureEvidence: Codable, Equatable, Sendable {
    public let requestFingerprint: ProtectedArtifactSHA256
    public let recordedAt: ProtectedArtifactEpochMilliseconds
    public let code: ProtectedArtifactOperationalFailureCode

    public init(
        requestFingerprint: ProtectedArtifactSHA256,
        recordedAt: ProtectedArtifactEpochMilliseconds,
        code: ProtectedArtifactOperationalFailureCode
    ) {
        self.requestFingerprint = requestFingerprint
        self.recordedAt = recordedAt
        self.code = code
    }
}

public enum ProtectedArtifactLifecycleEvent: Equatable, Sendable {
    case requested(
        requestFingerprint: ProtectedArtifactSHA256,
        at: ProtectedArtifactEpochMilliseconds
    )
    case materialized(ProtectedArtifactMaterializationEvidence)
    case handoffRecorded(ProtectedArtifactHandoffEvidence)
    case cleanupRequired(ProtectedArtifactCleanupEvidence)
    case cleaned(ProtectedArtifactCleanupEvidence)
    case cancelled(
        requestFingerprint: ProtectedArtifactSHA256,
        at: ProtectedArtifactEpochMilliseconds
    )
    case failed(ProtectedArtifactFailureEvidence)

    public var kind: ProtectedArtifactLifecycleEventKind {
        switch self {
        case .requested: return .requested
        case .materialized: return .materialized
        case .handoffRecorded: return .handoffRecorded
        case .cleanupRequired: return .cleanupRequired
        case .cleaned: return .cleaned
        case .cancelled: return .cancelled
        case .failed: return .failed
        }
    }

    fileprivate var recordedAt: ProtectedArtifactEpochMilliseconds {
        switch self {
        case .requested(_, let at), .cancelled(_, let at): return at
        case .materialized(let evidence): return evidence.recordedAt
        case .handoffRecorded(let evidence): return evidence.recordedAt
        case .cleanupRequired(let evidence), .cleaned(let evidence): return evidence.recordedAt
        case .failed(let evidence): return evidence.recordedAt
        }
    }

    fileprivate var requestFingerprint: ProtectedArtifactSHA256 {
        switch self {
        case .requested(let fingerprint, _), .cancelled(let fingerprint, _): return fingerprint
        case .materialized(let evidence): return evidence.requestFingerprint
        case .handoffRecorded(let evidence): return evidence.requestFingerprint
        case .cleanupRequired(let evidence), .cleaned(let evidence): return evidence.requestFingerprint
        case .failed(let evidence): return evidence.requestFingerprint
        }
    }
}

public struct ProtectedArtifactLifecycle: Equatable, Sendable {
    public let request: ProtectedArtifactExportRequest
    public let phase: ProtectedArtifactLifecyclePhase
    public let events: [ProtectedArtifactLifecycleEvent]
    public let materialization: ProtectedArtifactMaterializationEvidence?
    public let handoff: ProtectedArtifactHandoffEvidence?

    fileprivate init(
        request: ProtectedArtifactExportRequest,
        phase: ProtectedArtifactLifecyclePhase,
        events: [ProtectedArtifactLifecycleEvent],
        materialization: ProtectedArtifactMaterializationEvidence?,
        handoff: ProtectedArtifactHandoffEvidence?
    ) {
        self.request = request
        self.phase = phase
        self.events = events
        self.materialization = materialization
        self.handoff = handoff
    }
}

public struct ProtectedArtifactExportReceipt: Equatable, Sendable {
    public let requestFingerprint: ProtectedArtifactSHA256
    public let lifecycleDigest: ProtectedArtifactSHA256
    public let snapshot: ProtectedArtifactSnapshotReference
    public let contentKind: ProtectedArtifactContentKind
    public let destinationIntent: ProtectedArtifactDestinationIntent
    public let output: ProtectedArtifactMaterializationEvidence?
    public let destinationOutcome: ProtectedArtifactDestinationOutcome
    public let cleanupDisposition: ProtectedArtifactCleanupDisposition
    public let completedAt: ProtectedArtifactEpochMilliseconds
    public let authorityDisposition: ProtectedArtifactAuthorityDisposition
    public let contentDigest: ProtectedArtifactSHA256

    fileprivate init(
        requestFingerprint: ProtectedArtifactSHA256,
        lifecycleDigest: ProtectedArtifactSHA256,
        snapshot: ProtectedArtifactSnapshotReference,
        contentKind: ProtectedArtifactContentKind,
        destinationIntent: ProtectedArtifactDestinationIntent,
        output: ProtectedArtifactMaterializationEvidence?,
        destinationOutcome: ProtectedArtifactDestinationOutcome,
        cleanupDisposition: ProtectedArtifactCleanupDisposition,
        completedAt: ProtectedArtifactEpochMilliseconds,
        contentDigest: ProtectedArtifactSHA256
    ) {
        self.requestFingerprint = requestFingerprint
        self.lifecycleDigest = lifecycleDigest
        self.snapshot = snapshot
        self.contentKind = contentKind
        self.destinationIntent = destinationIntent
        self.output = output
        self.destinationOutcome = destinationOutcome
        self.cleanupDisposition = cleanupDisposition
        self.completedAt = completedAt
        self.authorityDisposition = .evidenceOnly
        self.contentDigest = contentDigest
    }
}

public enum ProtectedArtifactExportValidator {
    public static func makeRequest(
        _ draft: ProtectedArtifactExportRequestDraft,
        policy: ProtectedArtifactExportPolicy
    ) throws -> ProtectedArtifactExportRequest {
        let request = try makeRequestWithoutCanonicalSizeCheck(draft, policy: policy)
        _ = try canonicalRequestData(request, policy: policy)
        return request
    }

    public static func start(
        _ request: ProtectedArtifactExportRequest,
        policy: ProtectedArtifactExportPolicy
    ) throws -> ProtectedArtifactLifecycle {
        try validateRequest(request, policy: policy)
        return try replay(
            request: request,
            events: [
                .requested(
                    requestFingerprint: request.requestFingerprint,
                    at: request.requestedAt
                )
            ]
        )
    }

    public static func advance(
        _ lifecycle: ProtectedArtifactLifecycle,
        with event: ProtectedArtifactLifecycleEvent
    ) throws -> ProtectedArtifactLifecycle {
        try replay(request: lifecycle.request, events: lifecycle.events + [event])
    }

    public static func makeReceipt(
        from lifecycle: ProtectedArtifactLifecycle
    ) throws -> ProtectedArtifactExportReceipt {
        let normalized = try replay(request: lifecycle.request, events: lifecycle.events)
        guard let completedAt = normalized.events.last?.recordedAt else {
            throw ProtectedArtifactFailure.receiptNotTerminal
        }

        let output: ProtectedArtifactMaterializationEvidence?
        let destinationOutcome: ProtectedArtifactDestinationOutcome
        let cleanupDisposition: ProtectedArtifactCleanupDisposition

        switch normalized.phase {
        case .cleaned:
            guard let materialization = normalized.materialization else {
                throw ProtectedArtifactFailure.receiptMismatch
            }
            output = materialization
            destinationOutcome = normalized.handoff?.outcome ?? .notAttempted
            cleanupDisposition = .cleanupRecorded
        case .cancelled:
            output = nil
            destinationOutcome = .cancelled
            cleanupDisposition = .notRequired
        case .failed:
            output = nil
            destinationOutcome = .failed
            cleanupDisposition = .notRequired
        case .requested, .materialized, .handoffRecorded, .cleanupRequired:
            throw ProtectedArtifactFailure.receiptNotTerminal
        }

        let lifecycleData = try canonicalLifecycleData(normalized)
        let lifecycleDigest = try ProtectedArtifactSHA256.make(bytes: lifecycleData)
        let content = ProtectedArtifactReceiptContent(
            requestFingerprint: normalized.request.requestFingerprint,
            lifecycleDigest: lifecycleDigest,
            snapshot: normalized.request.snapshot,
            contentKind: normalized.request.contentKind,
            destinationIntent: normalized.request.destinationIntent,
            output: output,
            destinationOutcome: destinationOutcome,
            cleanupDisposition: cleanupDisposition,
            completedAt: completedAt,
            authorityDisposition: .evidenceOnly
        )
        let receipt = ProtectedArtifactExportReceipt(
            requestFingerprint: normalized.request.requestFingerprint,
            lifecycleDigest: lifecycleDigest,
            snapshot: normalized.request.snapshot,
            contentKind: normalized.request.contentKind,
            destinationIntent: normalized.request.destinationIntent,
            output: output,
            destinationOutcome: destinationOutcome,
            cleanupDisposition: cleanupDisposition,
            completedAt: completedAt,
            contentDigest: try ProtectedArtifactSHA256.make(
                bytes: ProtectedArtifactValidation.encodeSorted(content)
            )
        )
        _ = try canonicalReceiptData(
            receipt,
            maximumBytes: normalized.request.maximumCanonicalByteCount
        )
        return receipt
    }

    public static func canonicalRequestData(
        _ request: ProtectedArtifactExportRequest,
        policy: ProtectedArtifactExportPolicy
    ) throws -> Data {
        try validateRequest(request, policy: policy)
        return try ProtectedArtifactValidation.encodeCanonical(
            ProtectedArtifactRequestWire(request: request),
            maximumBytes: policy.maximumCanonicalByteCount
        )
    }

    public static func decodeRequest(
        _ data: Data,
        policy: ProtectedArtifactExportPolicy
    ) throws -> ProtectedArtifactExportRequest {
        try ProtectedArtifactValidation.checkSize(data, maximum: policy.maximumCanonicalByteCount)
        let wire: ProtectedArtifactRequestWire = try ProtectedArtifactValidation.decode(data)
        guard wire.schemaVersion == ProtectedArtifactValidation.schemaVersion else {
            throw ProtectedArtifactFailure.schemaVersionMismatch
        }
        let request = try makeRequest(wire.draft, policy: policy)
        guard request.maximumCanonicalByteCount == wire.maximumCanonicalByteCount,
              request.policyFingerprint == wire.policyFingerprint else {
            throw ProtectedArtifactFailure.policyMismatch
        }
        guard request.requestFingerprint == wire.requestFingerprint else {
            throw ProtectedArtifactFailure.requestFingerprintMismatch
        }
        guard try canonicalRequestData(request, policy: policy) == data else {
            throw ProtectedArtifactFailure.noncanonicalEvidence
        }
        return request
    }

    public static func canonicalLifecycleData(
        _ lifecycle: ProtectedArtifactLifecycle
    ) throws -> Data {
        let normalized = try replay(request: lifecycle.request, events: lifecycle.events)
        let content = ProtectedArtifactLifecycleContent(
            request: ProtectedArtifactRequestWire(request: normalized.request),
            events: normalized.events.map(ProtectedArtifactEventWire.init)
        )
        let envelope = ProtectedArtifactLifecycleEnvelope(
            schemaVersion: ProtectedArtifactValidation.schemaVersion,
            content: content,
            contentDigest: try ProtectedArtifactSHA256.make(
                bytes: ProtectedArtifactValidation.encodeSorted(content)
            )
        )
        return try ProtectedArtifactValidation.encodeCanonical(
            envelope,
            maximumBytes: normalized.request.maximumCanonicalByteCount
        )
    }

    public static func decodeLifecycle(
        _ data: Data,
        policy: ProtectedArtifactExportPolicy
    ) throws -> ProtectedArtifactLifecycle {
        try ProtectedArtifactValidation.checkSize(data, maximum: policy.maximumCanonicalByteCount)
        let envelope: ProtectedArtifactLifecycleEnvelope = try ProtectedArtifactValidation.decode(data)
        guard envelope.schemaVersion == ProtectedArtifactValidation.schemaVersion else {
            throw ProtectedArtifactFailure.schemaVersionMismatch
        }
        let expectedDigest = try ProtectedArtifactSHA256.make(
            bytes: ProtectedArtifactValidation.encodeSorted(envelope.content)
        )
        guard expectedDigest == envelope.contentDigest else {
            throw ProtectedArtifactFailure.contentDigestMismatch
        }
        let requestData = try ProtectedArtifactValidation.encodeCanonical(
            envelope.content.request,
            maximumBytes: policy.maximumCanonicalByteCount
        )
        let request = try decodeRequest(requestData, policy: policy)
        let lifecycle = try replay(
            request: request,
            events: try envelope.content.events.map { try $0.event() }
        )
        guard try canonicalLifecycleData(lifecycle) == data else {
            throw ProtectedArtifactFailure.noncanonicalEvidence
        }
        return lifecycle
    }

    public static func canonicalReceiptData(
        _ receipt: ProtectedArtifactExportReceipt,
        maximumBytes: Int
    ) throws -> Data {
        guard receipt.authorityDisposition == .evidenceOnly else {
            throw ProtectedArtifactFailure.authorityDispositionMismatch
        }
        let content = ProtectedArtifactReceiptContent(receipt: receipt)
        let expectedDigest = try ProtectedArtifactSHA256.make(
            bytes: ProtectedArtifactValidation.encodeSorted(content)
        )
        guard expectedDigest == receipt.contentDigest else {
            throw ProtectedArtifactFailure.contentDigestMismatch
        }
        return try ProtectedArtifactValidation.encodeCanonical(
            ProtectedArtifactReceiptWire(
                schemaVersion: ProtectedArtifactValidation.schemaVersion,
                content: content,
                contentDigest: receipt.contentDigest
            ),
            maximumBytes: maximumBytes
        )
    }

    public static func decodeReceipt(
        _ data: Data,
        matching lifecycle: ProtectedArtifactLifecycle
    ) throws -> ProtectedArtifactExportReceipt {
        try ProtectedArtifactValidation.checkSize(
            data,
            maximum: lifecycle.request.maximumCanonicalByteCount
        )
        let wire: ProtectedArtifactReceiptWire = try ProtectedArtifactValidation.decode(data)
        guard wire.schemaVersion == ProtectedArtifactValidation.schemaVersion else {
            throw ProtectedArtifactFailure.schemaVersionMismatch
        }
        guard wire.content.authorityDisposition == .evidenceOnly else {
            throw ProtectedArtifactFailure.authorityDispositionMismatch
        }
        let expectedDigest = try ProtectedArtifactSHA256.make(
            bytes: ProtectedArtifactValidation.encodeSorted(wire.content)
        )
        guard expectedDigest == wire.contentDigest else {
            throw ProtectedArtifactFailure.contentDigestMismatch
        }
        let expectedReceipt = try makeReceipt(from: lifecycle)
        guard ProtectedArtifactReceiptContent(receipt: expectedReceipt) == wire.content,
              expectedReceipt.contentDigest == wire.contentDigest else {
            throw ProtectedArtifactFailure.receiptMismatch
        }
        guard try canonicalReceiptData(
            expectedReceipt,
            maximumBytes: lifecycle.request.maximumCanonicalByteCount
        ) == data else {
            throw ProtectedArtifactFailure.noncanonicalEvidence
        }
        return expectedReceipt
    }

    private static func validateRequest(
        _ request: ProtectedArtifactExportRequest,
        policy: ProtectedArtifactExportPolicy
    ) throws {
        guard request.maximumCanonicalByteCount == policy.maximumCanonicalByteCount,
              request.policyFingerprint == policy.fingerprint else {
            throw ProtectedArtifactFailure.policyMismatch
        }
        let draft = ProtectedArtifactExportRequestDraft(
            exportID: request.exportID,
            snapshot: request.snapshot,
            contentKind: request.contentKind,
            destinationIntent: request.destinationIntent,
            requestedAt: request.requestedAt,
            expiresAt: request.expiresAt,
            maximumOutputByteCount: request.maximumOutputByteCount
        )
        let expected = try makeRequestWithoutCanonicalSizeCheck(draft, policy: policy)
        guard expected.requestFingerprint == request.requestFingerprint else {
            throw ProtectedArtifactFailure.requestFingerprintMismatch
        }
    }

    private static func makeRequestWithoutCanonicalSizeCheck(
        _ draft: ProtectedArtifactExportRequestDraft,
        policy: ProtectedArtifactExportPolicy
    ) throws -> ProtectedArtifactExportRequest {
        guard policy.allowedContentKinds.contains(draft.contentKind) else {
            throw ProtectedArtifactFailure.contentKindNotAllowed(draft.contentKind)
        }
        guard policy.allowedDestinationIntents.contains(draft.destinationIntent) else {
            throw ProtectedArtifactFailure.destinationIntentNotAllowed(draft.destinationIntent)
        }
        guard draft.expiresAt > draft.requestedAt else {
            throw ProtectedArtifactFailure.invalidLeaseExpiry
        }
        guard draft.expiresAt.rawValue - draft.requestedAt.rawValue <= policy.maximumLeaseDurationMilliseconds else {
            throw ProtectedArtifactFailure.leaseDurationExceeded
        }
        guard draft.maximumOutputByteCount > 0 else {
            throw ProtectedArtifactFailure.invalidOutputByteCount
        }
        guard draft.maximumOutputByteCount <= policy.maximumOutputByteCount else {
            throw ProtectedArtifactFailure.outputByteCountExceeded
        }

        let content = ProtectedArtifactRequestFingerprintContent(
            exportID: draft.exportID,
            snapshot: draft.snapshot,
            contentKind: draft.contentKind,
            destinationIntent: draft.destinationIntent,
            requestedAt: draft.requestedAt,
            expiresAt: draft.expiresAt,
            maximumOutputByteCount: draft.maximumOutputByteCount,
            policyFingerprint: policy.fingerprint
        )
        return ProtectedArtifactExportRequest(
            draft: draft,
            maximumCanonicalByteCount: policy.maximumCanonicalByteCount,
            policyFingerprint: policy.fingerprint,
            requestFingerprint: try ProtectedArtifactSHA256.make(
                bytes: ProtectedArtifactValidation.encodeSorted(content)
            )
        )
    }

    private static func replay(
        request: ProtectedArtifactExportRequest,
        events: [ProtectedArtifactLifecycleEvent]
    ) throws -> ProtectedArtifactLifecycle {
        let maximumEventCount = 5
        guard events.count <= maximumEventCount else {
            throw ProtectedArtifactFailure.tooManyLifecycleEvents(maximum: maximumEventCount)
        }
        guard let first = events.first else {
            throw ProtectedArtifactFailure.malformedEvidence
        }
        guard first == .requested(
            requestFingerprint: request.requestFingerprint,
            at: request.requestedAt
        ) else {
            throw ProtectedArtifactFailure.illegalLifecycleTransition(
                from: .requested,
                event: first.kind
            )
        }

        var phase: ProtectedArtifactLifecyclePhase = .requested
        var materialization: ProtectedArtifactMaterializationEvidence?
        var handoff: ProtectedArtifactHandoffEvidence?
        var lastAt = request.requestedAt

        for event in events.dropFirst() {
            guard event.requestFingerprint == request.requestFingerprint else {
                throw ProtectedArtifactFailure.requestFingerprintMismatch
            }
            guard event.recordedAt >= lastAt else {
                throw ProtectedArtifactFailure.eventTimestampOutOfOrder
            }

            switch event {
            case .requested:
                throw ProtectedArtifactFailure.illegalLifecycleTransition(
                    from: phase,
                    event: .requested
                )
            case .materialized(let evidence):
                guard phase == .requested else {
                    throw ProtectedArtifactFailure.illegalLifecycleTransition(
                        from: phase,
                        event: .materialized
                    )
                }
                guard evidence.recordedAt <= request.expiresAt else {
                    throw ProtectedArtifactFailure.eventAfterLeaseExpiry
                }
                guard evidence.byteCount > 0 else {
                    throw ProtectedArtifactFailure.invalidOutputByteCount
                }
                guard evidence.byteCount <= request.maximumOutputByteCount else {
                    throw ProtectedArtifactFailure.outputByteCountExceeded
                }
                materialization = evidence
                phase = .materialized
            case .handoffRecorded(let evidence):
                guard phase == .materialized else {
                    throw ProtectedArtifactFailure.illegalLifecycleTransition(
                        from: phase,
                        event: .handoffRecorded
                    )
                }
                guard evidence.recordedAt <= request.expiresAt else {
                    throw ProtectedArtifactFailure.eventAfterLeaseExpiry
                }
                guard evidence.outcome != .notAttempted else {
                    throw ProtectedArtifactFailure.malformedEvidence
                }
                guard evidence.outputHash == materialization?.outputHash else {
                    throw ProtectedArtifactFailure.outputHashMismatch
                }
                handoff = evidence
                phase = .handoffRecorded
            case .cleanupRequired(let evidence):
                guard phase == .materialized || phase == .handoffRecorded else {
                    throw ProtectedArtifactFailure.illegalLifecycleTransition(
                        from: phase,
                        event: .cleanupRequired
                    )
                }
                guard evidence.outputHash == materialization?.outputHash else {
                    throw ProtectedArtifactFailure.outputHashMismatch
                }
                phase = .cleanupRequired
            case .cleaned(let evidence):
                guard phase == .cleanupRequired else {
                    throw ProtectedArtifactFailure.illegalLifecycleTransition(
                        from: phase,
                        event: .cleaned
                    )
                }
                guard evidence.outputHash == materialization?.outputHash else {
                    throw ProtectedArtifactFailure.outputHashMismatch
                }
                phase = .cleaned
            case .cancelled(_, let at):
                guard phase == .requested else {
                    throw ProtectedArtifactFailure.illegalLifecycleTransition(
                        from: phase,
                        event: .cancelled
                    )
                }
                guard at <= request.expiresAt else {
                    throw ProtectedArtifactFailure.eventAfterLeaseExpiry
                }
                phase = .cancelled
            case .failed(let evidence):
                guard phase == .requested else {
                    throw ProtectedArtifactFailure.illegalLifecycleTransition(
                        from: phase,
                        event: .failed
                    )
                }
                if evidence.code == .leaseExpired {
                    guard evidence.recordedAt >= request.expiresAt else {
                        throw ProtectedArtifactFailure.leaseExpiryFailureBeforeExpiry
                    }
                } else {
                    guard evidence.recordedAt <= request.expiresAt else {
                        throw ProtectedArtifactFailure.nonExpiryFailureAfterExpiry
                    }
                }
                phase = .failed
            }
            lastAt = event.recordedAt
        }

        return ProtectedArtifactLifecycle(
            request: request,
            phase: phase,
            events: events,
            materialization: materialization,
            handoff: handoff
        )
    }
}

private struct ProtectedArtifactPolicyFingerprintContent: Codable {
    let allowedContentKinds: [ProtectedArtifactContentKind]
    let allowedDestinationIntents: [ProtectedArtifactDestinationIntent]
    let maximumOutputByteCount: Int
    let maximumLeaseDurationMilliseconds: Int64
    let maximumCanonicalByteCount: Int
}

private struct ProtectedArtifactRequestFingerprintContent: Codable {
    let exportID: ProtectedArtifactExportID
    let snapshot: ProtectedArtifactSnapshotReference
    let contentKind: ProtectedArtifactContentKind
    let destinationIntent: ProtectedArtifactDestinationIntent
    let requestedAt: ProtectedArtifactEpochMilliseconds
    let expiresAt: ProtectedArtifactEpochMilliseconds
    let maximumOutputByteCount: Int
    let policyFingerprint: ProtectedArtifactSHA256
}

private struct ProtectedArtifactRequestWire: Codable, Equatable {
    let schemaVersion: Int
    let exportID: ProtectedArtifactExportID
    let snapshot: ProtectedArtifactSnapshotReference
    let contentKind: ProtectedArtifactContentKind
    let destinationIntent: ProtectedArtifactDestinationIntent
    let requestedAt: ProtectedArtifactEpochMilliseconds
    let expiresAt: ProtectedArtifactEpochMilliseconds
    let maximumOutputByteCount: Int
    let maximumCanonicalByteCount: Int
    let policyFingerprint: ProtectedArtifactSHA256
    let requestFingerprint: ProtectedArtifactSHA256

    init(request: ProtectedArtifactExportRequest) {
        schemaVersion = ProtectedArtifactValidation.schemaVersion
        exportID = request.exportID
        snapshot = request.snapshot
        contentKind = request.contentKind
        destinationIntent = request.destinationIntent
        requestedAt = request.requestedAt
        expiresAt = request.expiresAt
        maximumOutputByteCount = request.maximumOutputByteCount
        maximumCanonicalByteCount = request.maximumCanonicalByteCount
        policyFingerprint = request.policyFingerprint
        requestFingerprint = request.requestFingerprint
    }

    var draft: ProtectedArtifactExportRequestDraft {
        ProtectedArtifactExportRequestDraft(
            exportID: exportID,
            snapshot: snapshot,
            contentKind: contentKind,
            destinationIntent: destinationIntent,
            requestedAt: requestedAt,
            expiresAt: expiresAt,
            maximumOutputByteCount: maximumOutputByteCount
        )
    }
}

private struct ProtectedArtifactEventWire: Codable, Equatable {
    let kind: ProtectedArtifactLifecycleEventKind
    let requestFingerprint: ProtectedArtifactSHA256
    let recordedAt: ProtectedArtifactEpochMilliseconds
    let byteCount: Int?
    let outputHash: ProtectedArtifactSHA256?
    let destinationOutcome: ProtectedArtifactDestinationOutcome?
    let failureCode: ProtectedArtifactOperationalFailureCode?

    init(_ event: ProtectedArtifactLifecycleEvent) {
        kind = event.kind
        requestFingerprint = event.requestFingerprint
        recordedAt = event.recordedAt
        switch event {
        case .requested, .cancelled:
            byteCount = nil
            outputHash = nil
            destinationOutcome = nil
            failureCode = nil
        case .materialized(let evidence):
            byteCount = evidence.byteCount
            outputHash = evidence.outputHash
            destinationOutcome = nil
            failureCode = nil
        case .handoffRecorded(let evidence):
            byteCount = nil
            outputHash = evidence.outputHash
            destinationOutcome = evidence.outcome
            failureCode = nil
        case .cleanupRequired(let evidence), .cleaned(let evidence):
            byteCount = nil
            outputHash = evidence.outputHash
            destinationOutcome = nil
            failureCode = nil
        case .failed(let evidence):
            byteCount = nil
            outputHash = nil
            destinationOutcome = nil
            failureCode = evidence.code
        }
    }

    func event() throws -> ProtectedArtifactLifecycleEvent {
        switch kind {
        case .requested:
            guard byteCount == nil, outputHash == nil,
                  destinationOutcome == nil, failureCode == nil else {
                throw ProtectedArtifactFailure.malformedEvidence
            }
            return .requested(requestFingerprint: requestFingerprint, at: recordedAt)
        case .materialized:
            guard let byteCount, let outputHash,
                  destinationOutcome == nil, failureCode == nil else {
                throw ProtectedArtifactFailure.malformedEvidence
            }
            return .materialized(
                ProtectedArtifactMaterializationEvidence(
                    requestFingerprint: requestFingerprint,
                    recordedAt: recordedAt,
                    byteCount: byteCount,
                    outputHash: outputHash
                )
            )
        case .handoffRecorded:
            guard byteCount == nil, let outputHash, let destinationOutcome,
                  failureCode == nil else {
                throw ProtectedArtifactFailure.malformedEvidence
            }
            return .handoffRecorded(
                ProtectedArtifactHandoffEvidence(
                    requestFingerprint: requestFingerprint,
                    outputHash: outputHash,
                    recordedAt: recordedAt,
                    outcome: destinationOutcome
                )
            )
        case .cleanupRequired:
            guard byteCount == nil, let outputHash,
                  destinationOutcome == nil, failureCode == nil else {
                throw ProtectedArtifactFailure.malformedEvidence
            }
            return .cleanupRequired(
                ProtectedArtifactCleanupEvidence(
                    requestFingerprint: requestFingerprint,
                    outputHash: outputHash,
                    recordedAt: recordedAt
                )
            )
        case .cleaned:
            guard byteCount == nil, let outputHash,
                  destinationOutcome == nil, failureCode == nil else {
                throw ProtectedArtifactFailure.malformedEvidence
            }
            return .cleaned(
                ProtectedArtifactCleanupEvidence(
                    requestFingerprint: requestFingerprint,
                    outputHash: outputHash,
                    recordedAt: recordedAt
                )
            )
        case .cancelled:
            guard byteCount == nil, outputHash == nil,
                  destinationOutcome == nil, failureCode == nil else {
                throw ProtectedArtifactFailure.malformedEvidence
            }
            return .cancelled(requestFingerprint: requestFingerprint, at: recordedAt)
        case .failed:
            guard byteCount == nil, outputHash == nil,
                  destinationOutcome == nil, let failureCode else {
                throw ProtectedArtifactFailure.malformedEvidence
            }
            return .failed(
                ProtectedArtifactFailureEvidence(
                    requestFingerprint: requestFingerprint,
                    recordedAt: recordedAt,
                    code: failureCode
                )
            )
        }
    }
}

private struct ProtectedArtifactLifecycleContent: Codable, Equatable {
    let request: ProtectedArtifactRequestWire
    let events: [ProtectedArtifactEventWire]
}

private struct ProtectedArtifactLifecycleEnvelope: Codable, Equatable {
    let schemaVersion: Int
    let content: ProtectedArtifactLifecycleContent
    let contentDigest: ProtectedArtifactSHA256
}

private struct ProtectedArtifactReceiptContent: Codable, Equatable {
    let requestFingerprint: ProtectedArtifactSHA256
    let lifecycleDigest: ProtectedArtifactSHA256
    let snapshot: ProtectedArtifactSnapshotReference
    let contentKind: ProtectedArtifactContentKind
    let destinationIntent: ProtectedArtifactDestinationIntent
    let output: ProtectedArtifactMaterializationEvidence?
    let destinationOutcome: ProtectedArtifactDestinationOutcome
    let cleanupDisposition: ProtectedArtifactCleanupDisposition
    let completedAt: ProtectedArtifactEpochMilliseconds
    let authorityDisposition: ProtectedArtifactAuthorityDisposition

    init(
        requestFingerprint: ProtectedArtifactSHA256,
        lifecycleDigest: ProtectedArtifactSHA256,
        snapshot: ProtectedArtifactSnapshotReference,
        contentKind: ProtectedArtifactContentKind,
        destinationIntent: ProtectedArtifactDestinationIntent,
        output: ProtectedArtifactMaterializationEvidence?,
        destinationOutcome: ProtectedArtifactDestinationOutcome,
        cleanupDisposition: ProtectedArtifactCleanupDisposition,
        completedAt: ProtectedArtifactEpochMilliseconds,
        authorityDisposition: ProtectedArtifactAuthorityDisposition
    ) {
        self.requestFingerprint = requestFingerprint
        self.lifecycleDigest = lifecycleDigest
        self.snapshot = snapshot
        self.contentKind = contentKind
        self.destinationIntent = destinationIntent
        self.output = output
        self.destinationOutcome = destinationOutcome
        self.cleanupDisposition = cleanupDisposition
        self.completedAt = completedAt
        self.authorityDisposition = authorityDisposition
    }

    init(receipt: ProtectedArtifactExportReceipt) {
        self.init(
            requestFingerprint: receipt.requestFingerprint,
            lifecycleDigest: receipt.lifecycleDigest,
            snapshot: receipt.snapshot,
            contentKind: receipt.contentKind,
            destinationIntent: receipt.destinationIntent,
            output: receipt.output,
            destinationOutcome: receipt.destinationOutcome,
            cleanupDisposition: receipt.cleanupDisposition,
            completedAt: receipt.completedAt,
            authorityDisposition: receipt.authorityDisposition
        )
    }
}

private struct ProtectedArtifactReceiptWire: Codable, Equatable {
    let schemaVersion: Int
    let content: ProtectedArtifactReceiptContent
    let contentDigest: ProtectedArtifactSHA256
}

private enum ProtectedArtifactValidation {
    static let schemaVersion = 1

    static func isOpaqueID(_ value: String) -> Bool {
        isLowercaseHex(value, count: 32)
    }

    static func isStableCode(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard !bytes.isEmpty, bytes.count <= 64 else { return false }
        return bytes.allSatisfy { byte in
            (byte >= 97 && byte <= 122)
                || (byte >= 48 && byte <= 57)
                || byte == 45
                || byte == 46
                || byte == 95
        }
    }

    static func isLowercaseHex(_ value: String, count: Int) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == count else { return false }
        return bytes.allSatisfy { byte in
            (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func encodeSorted<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            return try encoder.encode(value)
        } catch {
            throw ProtectedArtifactFailure.malformedEvidence
        }
    }

    static func encodeCanonical<T: Encodable>(
        _ value: T,
        maximumBytes: Int
    ) throws -> Data {
        let data = try encodeSorted(value)
        try checkSize(data, maximum: maximumBytes)
        return data
    }

    static func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ProtectedArtifactFailure.malformedEvidence
        }
    }

    static func checkSize(_ data: Data, maximum: Int) throws {
        guard data.count <= maximum else {
            throw ProtectedArtifactFailure.evidenceTooLarge(
                actual: data.count,
                maximum: maximum
            )
        }
    }
}
