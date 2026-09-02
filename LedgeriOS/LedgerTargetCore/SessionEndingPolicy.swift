import CryptoKit
import Foundation

public enum SessionEndingFailure: Error, Equatable, Sendable {
    case invalidObservedAt
    case invalidConfirmedAt
    case invalidRequestedAt
    case pendingWorkRequiresDisposition
    case destructiveConfirmationRequired
    case destructiveConfirmationMismatch
    case scopeMismatch
    case summaryChanged
    case summaryRegressed
    case summaryFingerprintMismatch
    case requestFingerprintMismatch
    case synchronizationIncomplete
    case sessionEndFailed
    case invalidEncodedSummary
    case invalidEncodedConfirmation
    case invalidEncodedRequest

    public var diagnosticCode: String {
        switch self {
        case .invalidObservedAt: "session_end_observed_at_invalid"
        case .invalidConfirmedAt: "session_end_confirmed_at_invalid"
        case .invalidRequestedAt: "session_end_requested_at_invalid"
        case .pendingWorkRequiresDisposition: "session_end_pending_work_requires_disposition"
        case .destructiveConfirmationRequired: "session_end_destructive_confirmation_required"
        case .destructiveConfirmationMismatch: "session_end_destructive_confirmation_mismatch"
        case .scopeMismatch: "session_end_scope_mismatch"
        case .summaryChanged: "session_end_pending_summary_changed"
        case .summaryRegressed: "session_end_pending_summary_regressed"
        case .summaryFingerprintMismatch: "session_end_pending_summary_fingerprint_mismatch"
        case .requestFingerprintMismatch: "session_end_request_fingerprint_mismatch"
        case .synchronizationIncomplete: "session_end_synchronization_incomplete"
        case .sessionEndFailed: "session_end_failed"
        case .invalidEncodedSummary: "session_end_pending_summary_encoding_invalid"
        case .invalidEncodedConfirmation: "session_end_destructive_confirmation_encoding_invalid"
        case .invalidEncodedRequest: "session_end_request_encoding_invalid"
        }
    }
}

public struct PendingLocalWorkFingerprint: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    fileprivate init(validating rawValue: String) throws {
        let lowercaseHexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        guard rawValue.utf8.count == 64,
              rawValue.unicodeScalars.allSatisfy(lowercaseHexadecimal.contains) else {
            throw SessionEndingFailure.summaryFingerprintMismatch
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            try self.init(validating: container.decode(String.self))
        } catch let failure as SessionEndingFailure {
            throw failure
        } catch {
            throw SessionEndingFailure.summaryFingerprintMismatch
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    fileprivate static func make(
        environment: LedgerEnvironmentKind,
        principalId: PrincipalID,
        accountId: AccountID,
        snapshotRevision: UInt64,
        observedAt: Date,
        queuedOperationCount: UInt64,
        applyingOperationCount: UInt64,
        unresolvedRejectedOperationCount: UInt64,
        unverifiedAttachmentCount: UInt64
    ) throws -> Self {
        let basis = PendingLocalWorkFingerprintBasis(
            environment: environment,
            principalId: principalId,
            accountId: accountId,
            snapshotRevision: snapshotRevision,
            observedAt: observedAt,
            queuedOperationCount: queuedOperationCount,
            applyingOperationCount: applyingOperationCount,
            unresolvedRejectedOperationCount: unresolvedRejectedOperationCount,
            unverifiedAttachmentCount: unverifiedAttachmentCount
        )
        return try Self(validating: Self.hexDigest(
            try OperationContractCodec.encode(basis)
        ))
    }

    fileprivate static func hexDigest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private struct PendingLocalWorkFingerprintBasis: Codable {
    let environment: LedgerEnvironmentKind
    let principalId: PrincipalID
    let accountId: AccountID
    let snapshotRevision: UInt64
    let observedAt: Date
    let queuedOperationCount: UInt64
    let applyingOperationCount: UInt64
    let unresolvedRejectedOperationCount: UInt64
    let unverifiedAttachmentCount: UInt64
}

public struct PendingLocalWorkSummary: Codable, Equatable, Sendable {
    public let environment: LedgerEnvironmentKind
    public let principalId: PrincipalID
    public let accountId: AccountID
    public let snapshotRevision: UInt64
    public let observedAt: Date
    public let queuedOperationCount: UInt64
    public let applyingOperationCount: UInt64
    public let unresolvedRejectedOperationCount: UInt64
    public let unverifiedAttachmentCount: UInt64
    public let fingerprint: PendingLocalWorkFingerprint

    public init(
        environment: LedgerEnvironmentKind,
        principalId: PrincipalID,
        accountId: AccountID,
        snapshotRevision: UInt64,
        observedAt: Date,
        queuedOperationCount: UInt64,
        applyingOperationCount: UInt64,
        unresolvedRejectedOperationCount: UInt64,
        unverifiedAttachmentCount: UInt64
    ) throws {
        guard observedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw SessionEndingFailure.invalidObservedAt
        }
        self.environment = environment
        self.principalId = principalId
        self.accountId = accountId
        self.snapshotRevision = snapshotRevision
        self.observedAt = observedAt
        self.queuedOperationCount = queuedOperationCount
        self.applyingOperationCount = applyingOperationCount
        self.unresolvedRejectedOperationCount = unresolvedRejectedOperationCount
        self.unverifiedAttachmentCount = unverifiedAttachmentCount
        self.fingerprint = try PendingLocalWorkFingerprint.make(
            environment: environment,
            principalId: principalId,
            accountId: accountId,
            snapshotRevision: snapshotRevision,
            observedAt: observedAt,
            queuedOperationCount: queuedOperationCount,
            applyingOperationCount: applyingOperationCount,
            unresolvedRejectedOperationCount: unresolvedRejectedOperationCount,
            unverifiedAttachmentCount: unverifiedAttachmentCount
        )
    }

    private init(
        environment: LedgerEnvironmentKind,
        principalId: PrincipalID,
        accountId: AccountID,
        snapshotRevision: UInt64,
        observedAt: Date,
        queuedOperationCount: UInt64,
        applyingOperationCount: UInt64,
        unresolvedRejectedOperationCount: UInt64,
        unverifiedAttachmentCount: UInt64,
        fingerprint: PendingLocalWorkFingerprint
    ) throws {
        let validated = try Self(
            environment: environment,
            principalId: principalId,
            accountId: accountId,
            snapshotRevision: snapshotRevision,
            observedAt: observedAt,
            queuedOperationCount: queuedOperationCount,
            applyingOperationCount: applyingOperationCount,
            unresolvedRejectedOperationCount: unresolvedRejectedOperationCount,
            unverifiedAttachmentCount: unverifiedAttachmentCount
        )
        guard fingerprint == validated.fingerprint else {
            throw SessionEndingFailure.summaryFingerprintMismatch
        }
        self = validated
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                environment: container.decode(LedgerEnvironmentKind.self, forKey: .environment),
                principalId: container.decode(PrincipalID.self, forKey: .principalId),
                accountId: container.decode(AccountID.self, forKey: .accountId),
                snapshotRevision: container.decode(UInt64.self, forKey: .snapshotRevision),
                observedAt: container.decode(Date.self, forKey: .observedAt),
                queuedOperationCount: container.decode(UInt64.self, forKey: .queuedOperationCount),
                applyingOperationCount: container.decode(UInt64.self, forKey: .applyingOperationCount),
                unresolvedRejectedOperationCount: container.decode(
                    UInt64.self,
                    forKey: .unresolvedRejectedOperationCount
                ),
                unverifiedAttachmentCount: container.decode(
                    UInt64.self,
                    forKey: .unverifiedAttachmentCount
                ),
                fingerprint: container.decode(
                    PendingLocalWorkFingerprint.self,
                    forKey: .fingerprint
                )
            )
        } catch let failure as SessionEndingFailure {
            throw failure
        } catch {
            throw SessionEndingFailure.invalidEncodedSummary
        }
    }

    public var hasBlockingWork: Bool {
        queuedOperationCount > 0 ||
            applyingOperationCount > 0 ||
            unresolvedRejectedOperationCount > 0 ||
            unverifiedAttachmentCount > 0
    }

    fileprivate func hasSameScope(as other: Self) -> Bool {
        environment == other.environment &&
            principalId == other.principalId &&
            accountId == other.accountId
    }

    private enum CodingKeys: String, CodingKey {
        case environment
        case principalId
        case accountId
        case snapshotRevision
        case observedAt
        case queuedOperationCount
        case applyingOperationCount
        case unresolvedRejectedOperationCount
        case unverifiedAttachmentCount
        case fingerprint
    }
}

public enum SessionEndDisposition: String, Codable, CaseIterable, Sendable {
    case ordinaryCleanLogout
    case synchronizeThenLogout
    case removeFromDeviceDiscardingPendingWork
}

public struct DestructiveLocalRemovalConfirmation: Codable, Equatable, Sendable {
    public let confirmedSummary: PendingLocalWorkSummary
    public let confirmedAt: Date

    public init(confirming summary: PendingLocalWorkSummary, confirmedAt: Date) throws {
        guard confirmedAt.timeIntervalSinceReferenceDate.isFinite,
              confirmedAt >= summary.observedAt else {
            throw SessionEndingFailure.invalidConfirmedAt
        }
        self.confirmedSummary = summary
        self.confirmedAt = confirmedAt
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                confirming: container.decode(
                    PendingLocalWorkSummary.self,
                    forKey: .confirmedSummary
                ),
                confirmedAt: container.decode(Date.self, forKey: .confirmedAt)
            )
        } catch let failure as SessionEndingFailure {
            throw failure
        } catch {
            throw SessionEndingFailure.invalidEncodedConfirmation
        }
    }

    private enum CodingKeys: String, CodingKey {
        case confirmedSummary
        case confirmedAt
    }
}

public struct SessionEndRequestFingerprint: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    fileprivate init(validating rawValue: String) throws {
        let lowercaseHexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        guard rawValue.utf8.count == 64,
              rawValue.unicodeScalars.allSatisfy(lowercaseHexadecimal.contains) else {
            throw SessionEndingFailure.requestFingerprintMismatch
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            try self.init(validating: container.decode(String.self))
        } catch let failure as SessionEndingFailure {
            throw failure
        } catch {
            throw SessionEndingFailure.requestFingerprintMismatch
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    fileprivate static func make(
        disposition: SessionEndDisposition,
        expectedSummary: PendingLocalWorkSummary,
        destructiveConfirmation: DestructiveLocalRemovalConfirmation?,
        requestedAt: Date
    ) throws -> Self {
        let basis = SessionEndRequestFingerprintBasis(
            disposition: disposition,
            expectedSummary: expectedSummary,
            destructiveConfirmation: destructiveConfirmation,
            requestedAt: requestedAt
        )
        return try Self(validating: PendingLocalWorkFingerprint.hexDigest(
            try OperationContractCodec.encode(basis)
        ))
    }
}

private struct SessionEndRequestFingerprintBasis: Codable {
    let disposition: SessionEndDisposition
    let expectedSummary: PendingLocalWorkSummary
    let destructiveConfirmation: DestructiveLocalRemovalConfirmation?
    let requestedAt: Date
}

public struct SessionEndRequest: Codable, Equatable, Sendable {
    public let disposition: SessionEndDisposition
    public let expectedSummary: PendingLocalWorkSummary
    public let destructiveConfirmation: DestructiveLocalRemovalConfirmation?
    public let requestedAt: Date
    public let fingerprint: SessionEndRequestFingerprint

    public init(
        disposition: SessionEndDisposition,
        expectedSummary: PendingLocalWorkSummary,
        destructiveConfirmation: DestructiveLocalRemovalConfirmation? = nil,
        requestedAt: Date
    ) throws {
        guard requestedAt.timeIntervalSinceReferenceDate.isFinite,
              requestedAt >= expectedSummary.observedAt else {
            throw SessionEndingFailure.invalidRequestedAt
        }
        switch disposition {
        case .ordinaryCleanLogout:
            guard !expectedSummary.hasBlockingWork else {
                throw SessionEndingFailure.pendingWorkRequiresDisposition
            }
            guard destructiveConfirmation == nil else {
                throw SessionEndingFailure.destructiveConfirmationMismatch
            }
        case .synchronizeThenLogout:
            guard destructiveConfirmation == nil else {
                throw SessionEndingFailure.destructiveConfirmationMismatch
            }
        case .removeFromDeviceDiscardingPendingWork:
            guard let destructiveConfirmation else {
                throw SessionEndingFailure.destructiveConfirmationRequired
            }
            guard destructiveConfirmation.confirmedSummary == expectedSummary else {
                throw SessionEndingFailure.destructiveConfirmationMismatch
            }
            guard destructiveConfirmation.confirmedAt <= requestedAt else {
                throw SessionEndingFailure.invalidRequestedAt
            }
        }

        self.disposition = disposition
        self.expectedSummary = expectedSummary
        self.destructiveConfirmation = destructiveConfirmation
        self.requestedAt = requestedAt
        self.fingerprint = try SessionEndRequestFingerprint.make(
            disposition: disposition,
            expectedSummary: expectedSummary,
            destructiveConfirmation: destructiveConfirmation,
            requestedAt: requestedAt
        )
    }

    private init(
        disposition: SessionEndDisposition,
        expectedSummary: PendingLocalWorkSummary,
        destructiveConfirmation: DestructiveLocalRemovalConfirmation?,
        requestedAt: Date,
        fingerprint: SessionEndRequestFingerprint
    ) throws {
        let validated = try Self(
            disposition: disposition,
            expectedSummary: expectedSummary,
            destructiveConfirmation: destructiveConfirmation,
            requestedAt: requestedAt
        )
        guard fingerprint == validated.fingerprint else {
            throw SessionEndingFailure.requestFingerprintMismatch
        }
        self = validated
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                disposition: container.decode(SessionEndDisposition.self, forKey: .disposition),
                expectedSummary: container.decode(
                    PendingLocalWorkSummary.self,
                    forKey: .expectedSummary
                ),
                destructiveConfirmation: container.decodeIfPresent(
                    DestructiveLocalRemovalConfirmation.self,
                    forKey: .destructiveConfirmation
                ),
                requestedAt: container.decode(Date.self, forKey: .requestedAt),
                fingerprint: container.decode(
                    SessionEndRequestFingerprint.self,
                    forKey: .fingerprint
                )
            )
        } catch let failure as SessionEndingFailure {
            throw failure
        } catch {
            throw SessionEndingFailure.invalidEncodedRequest
        }
    }

    private enum CodingKeys: String, CodingKey {
        case disposition
        case expectedSummary
        case destructiveConfirmation
        case requestedAt
        case fingerprint
    }
}

public enum SessionEndChoice: Equatable, Sendable {
    case cancel
    case ordinaryCleanLogout
    case synchronizeThenLogout
    case removeFromDeviceDiscardingPendingWork(confirmedAt: Date)
}

public enum SessionEndEvaluation: Equatable, Sendable {
    case readyForTeardown(SessionEndDisposition)
    case synchronizationRequired(PendingLocalWorkSummary)
}

public enum SessionEndPolicy {
    public static func makeRequest(
        choice: SessionEndChoice,
        summary: PendingLocalWorkSummary,
        requestedAt: Date
    ) throws -> SessionEndRequest? {
        switch choice {
        case .cancel:
            return nil
        case .ordinaryCleanLogout:
            return try SessionEndRequest(
                disposition: .ordinaryCleanLogout,
                expectedSummary: summary,
                requestedAt: requestedAt
            )
        case .synchronizeThenLogout:
            return try SessionEndRequest(
                disposition: .synchronizeThenLogout,
                expectedSummary: summary,
                requestedAt: requestedAt
            )
        case .removeFromDeviceDiscardingPendingWork(let confirmedAt):
            return try SessionEndRequest(
                disposition: .removeFromDeviceDiscardingPendingWork,
                expectedSummary: summary,
                destructiveConfirmation: try DestructiveLocalRemovalConfirmation(
                    confirming: summary,
                    confirmedAt: confirmedAt
                ),
                requestedAt: requestedAt
            )
        }
    }

    public static func evaluate(
        _ request: SessionEndRequest,
        against currentSummary: PendingLocalWorkSummary
    ) throws -> SessionEndEvaluation {
        guard request.expectedSummary.hasSameScope(as: currentSummary) else {
            throw SessionEndingFailure.scopeMismatch
        }

        switch request.disposition {
        case .ordinaryCleanLogout:
            guard request.expectedSummary.fingerprint == currentSummary.fingerprint else {
                throw SessionEndingFailure.summaryChanged
            }
            guard !currentSummary.hasBlockingWork else {
                throw SessionEndingFailure.pendingWorkRequiresDisposition
            }
            return .readyForTeardown(.ordinaryCleanLogout)

        case .synchronizeThenLogout:
            guard currentSummary.snapshotRevision >= request.expectedSummary.snapshotRevision,
                  currentSummary.observedAt >= request.expectedSummary.observedAt else {
                throw SessionEndingFailure.summaryRegressed
            }
            if currentSummary.hasBlockingWork {
                return .synchronizationRequired(currentSummary)
            }
            return .readyForTeardown(.synchronizeThenLogout)

        case .removeFromDeviceDiscardingPendingWork:
            guard request.expectedSummary.fingerprint == currentSummary.fingerprint else {
                throw SessionEndingFailure.summaryChanged
            }
            guard request.destructiveConfirmation?.confirmedSummary == currentSummary else {
                throw SessionEndingFailure.destructiveConfirmationMismatch
            }
            return .readyForTeardown(.removeFromDeviceDiscardingPendingWork)
        }
    }
}

public protocol AccountSessionEnding: Sendable {
    func pendingWorkSummary() async throws -> PendingLocalWorkSummary
    func endSession(_ request: SessionEndRequest) async throws
}
