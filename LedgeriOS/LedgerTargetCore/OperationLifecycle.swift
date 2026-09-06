import CryptoKit
import Foundation

public enum OperationContractFailure: Error, Equatable, Sendable {
    case invalidIdentifier(kind: String)
    case invalidStableCode(kind: String)
    case invalidFingerprint
    case payloadMismatch(OperationID)
    case missingOperation(OperationID)
    case illegalTransition(from: OperationPhase, event: OperationEventKind)
    case invalidCount(field: String)
    case inconsistentOldestTimestamp(field: String)
}

public struct LedgerIdentifier<Tag: Sendable>: Codable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.:"))
        guard rawValue == trimmed,
              !rawValue.isEmpty,
              rawValue.utf8.count <= 128,
              rawValue.unicodeScalars.allSatisfy(allowed.contains) else {
            throw OperationContractFailure.invalidIdentifier(
                kind: String(describing: Tag.self)
            )
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        do {
            try self.init(validating: value)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid Ledger identifier"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum OperationIDTag: Sendable {}
public enum AccountIDTag: Sendable {}
public enum PrincipalIDTag: Sendable {}
public enum EntityIDTag: Sendable {}
public enum OperationContractVersionTag: Sendable {}

public typealias OperationID = LedgerIdentifier<OperationIDTag>
public typealias AccountID = LedgerIdentifier<AccountIDTag>
public typealias PrincipalID = LedgerIdentifier<PrincipalIDTag>
public typealias EntityID = LedgerIdentifier<EntityIDTag>
public typealias OperationContractVersion = LedgerIdentifier<OperationContractVersionTag>

public struct StableCode<Tag: Sendable>: Codable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        let allowed = CharacterSet.lowercaseLetters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: "_"))
        guard rawValue.utf8.count >= 3,
              rawValue.utf8.count <= 80,
              rawValue.unicodeScalars.allSatisfy(allowed.contains),
              rawValue.first?.isLetter == true else {
            throw OperationContractFailure.invalidStableCode(
                kind: String(describing: Tag.self)
            )
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        do {
            try self.init(validating: value)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid stable code"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum ApplicationErrorCodeTag: Sendable {}
public enum ApplicationResultCodeTag: Sendable {}
public enum EntityStateCodeTag: Sendable {}
public enum ResolutionCodeTag: Sendable {}
public enum CapabilityIDTag: Sendable {}

public typealias ApplicationErrorCode = StableCode<ApplicationErrorCodeTag>
public typealias ApplicationResultCode = StableCode<ApplicationResultCodeTag>
public typealias EntityStateCode = StableCode<EntityStateCodeTag>
public typealias ResolutionCode = StableCode<ResolutionCodeTag>
public typealias CapabilityID = StableCode<CapabilityIDTag>

public enum LedgerEntityKind: String, Codable, CaseIterable, Sendable {
    case account
    case membership
    case client
    case project
    case item
    case transaction
    case invoice
    case expense
    case fee
    case space
    case attachment
    case referenceData
}

public struct LedgerEntityReference: Codable, Equatable, Hashable, Sendable {
    public let kind: LedgerEntityKind
    public let id: EntityID

    public init(kind: LedgerEntityKind, id: EntityID) {
        self.kind = kind
        self.id = id
    }
}

public enum OperationPrecondition: Codable, Equatable, Hashable, Sendable {
    case expectedRevision(subject: LedgerEntityReference, revision: UInt64)
    case expectedState(subject: LedgerEntityReference, state: EntityStateCode)
    case expectedRelationship(
        subject: LedgerEntityReference,
        relation: EntityStateCode,
        target: LedgerEntityReference
    )
    case expectedSourceSetHash(subject: LedgerEntityReference, sha256: String)
    case noUnresolvedOperation(subject: LedgerEntityReference)
}

public struct OperationEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    public let operationId: OperationID
    public let contractVersion: OperationContractVersion
    public let accountId: AccountID
    public let actorPrincipalId: PrincipalID
    public let clientCreatedAt: Date
    public let payload: Payload
    public let preconditions: [OperationPrecondition]

    public init(
        operationId: OperationID,
        contractVersion: OperationContractVersion,
        accountId: AccountID,
        actorPrincipalId: PrincipalID,
        clientCreatedAt: Date,
        payload: Payload,
        preconditions: [OperationPrecondition] = []
    ) {
        self.operationId = operationId
        self.contractVersion = contractVersion
        self.accountId = accountId
        self.actorPrincipalId = actorPrincipalId
        self.clientCreatedAt = clientCreatedAt
        self.payload = payload
        self.preconditions = preconditions
    }
}

public enum OperationContractCodec {
    public static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(value)
    }

    public static func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data
    ) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: data)
    }
}

public struct OperationFingerprint: Codable, Equatable, Hashable, Sendable {
    public let sha256: String

    public init(validating sha256: String) throws {
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        guard sha256.utf8.count == 64,
              sha256.unicodeScalars.allSatisfy(hexadecimal.contains) else {
            throw OperationContractFailure.invalidFingerprint
        }
        self.sha256 = sha256
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        do {
            try self.init(validating: value)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid operation fingerprint"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(sha256)
    }

    public static func make<Payload>(
        for envelope: OperationEnvelope<Payload>
    ) throws -> Self where Payload: Codable & Sendable {
        let bytes = try OperationContractCodec.encode(envelope)
        let digest = SHA256.hash(data: bytes)
            .map { String(format: "%02x", $0) }
            .joined()
        return try Self(validating: digest)
    }
}

public enum ApplicationErrorCategory: String, Codable, CaseIterable, Sendable {
    case validation
    case conflict
    case authorization
    case authentication
    case unsupportedContract
    case invariant
    case transientInfrastructure
    case requiredUpdate
}

public enum RetryDisposition: String, Codable, CaseIterable, Sendable {
    case never
    case automatic
    case afterUserCorrection
    case afterReauthentication
    case afterClientUpdate
}

public struct ApplicationErrorSummary: Codable, Equatable, Sendable {
    public let code: ApplicationErrorCode
    public let category: ApplicationErrorCategory
    public let retryDisposition: RetryDisposition

    public init(
        code: ApplicationErrorCode,
        category: ApplicationErrorCategory,
        retryDisposition: RetryDisposition
    ) {
        self.code = code
        self.category = category
        self.retryDisposition = retryDisposition
    }
}

public struct OperationRejection: Codable, Equatable, Sendable {
    public let error: ApplicationErrorSummary
    public let rejectedAt: Date
    public let conflictingEntities: [LedgerEntityReference]

    public init(
        error: ApplicationErrorSummary,
        rejectedAt: Date,
        conflictingEntities: [LedgerEntityReference] = []
    ) {
        self.error = error
        self.rejectedAt = rejectedAt
        self.conflictingEntities = conflictingEntities
    }
}

public struct EntityRevision: Codable, Equatable, Hashable, Sendable {
    public let entity: LedgerEntityReference
    public let revision: UInt64

    public init(entity: LedgerEntityReference, revision: UInt64) {
        self.entity = entity
        self.revision = revision
    }
}

public struct AppliedOperationResult: Codable, Equatable, Sendable {
    public let resultCode: ApplicationResultCode
    public let serverReceivedAt: Date
    public let completedAt: Date
    public let affectedRevisions: [EntityRevision]

    public init(
        resultCode: ApplicationResultCode,
        serverReceivedAt: Date,
        completedAt: Date,
        affectedRevisions: [EntityRevision] = []
    ) {
        self.resultCode = resultCode
        self.serverReceivedAt = serverReceivedAt
        self.completedAt = completedAt
        self.affectedRevisions = affectedRevisions
    }
}

public struct CorrectionReference: Codable, Equatable, Sendable {
    public let operationId: OperationID
    public let correctedAt: Date

    public init(operationId: OperationID, correctedAt: Date) {
        self.operationId = operationId
        self.correctedAt = correctedAt
    }
}

public struct RejectionResolution: Codable, Equatable, Sendable {
    public let code: ResolutionCode
    public let resolvedAt: Date

    public init(code: ResolutionCode, resolvedAt: Date) {
        self.code = code
        self.resolvedAt = resolvedAt
    }
}

public enum LocalOperationState: String, Codable, CaseIterable, Sendable {
    case queued
    case applying
    case applied
    case rejected
    case superseded
    case resolved
}

public struct OperationReceipt: Codable, Equatable, Sendable {
    public let operationId: OperationID
    public let localState: LocalOperationState

    public init(operationId: OperationID, localState: LocalOperationState) {
        self.operationId = operationId
        self.localState = localState
    }
}

public enum OperationPhase: String, Codable, CaseIterable, Sendable {
    case draft
    case queued
    case applying
    case applied
    case rejected
    case superseded
    case resolved
}

public enum OperationOutcome: Codable, Equatable, Sendable {
    case applied(AppliedOperationResult)
    case rejected(OperationRejection)
    case superseded(CorrectionReference)
}

public enum OperationState: Codable, Equatable, Sendable {
    case draft
    case queued(attemptCount: UInt32, lastTransientError: ApplicationErrorSummary?)
    case applying(attempt: UInt32, startedAt: Date)
    case applied(AppliedOperationResult)
    case rejected(OperationRejection)
    case superseded(original: AppliedOperationResult, correction: CorrectionReference)
    case resolved(rejection: OperationRejection, resolution: RejectionResolution)

    public var phase: OperationPhase {
        switch self {
        case .draft: .draft
        case .queued: .queued
        case .applying: .applying
        case .applied: .applied
        case .rejected: .rejected
        case .superseded: .superseded
        case .resolved: .resolved
        }
    }

    public var localState: LocalOperationState? {
        switch self {
        case .draft: nil
        case .queued: .queued
        case .applying: .applying
        case .applied: .applied
        case .rejected: .rejected
        case .superseded: .superseded
        case .resolved: .resolved
        }
    }

    public var isUnresolved: Bool {
        switch self {
        case .queued, .applying, .rejected:
            true
        case .draft, .applied, .superseded, .resolved:
            false
        }
    }

    public var outcome: OperationOutcome? {
        switch self {
        case .applied(let result): .applied(result)
        case .rejected(let rejection): .rejected(rejection)
        case .superseded(_, let correction): .superseded(correction)
        case .draft, .queued, .applying, .resolved: nil
        }
    }
}

public struct OperationSnapshot: Codable, Equatable, Sendable {
    public let operationId: OperationID
    public let accountId: AccountID
    public let contractVersion: OperationContractVersion
    public let fingerprint: OperationFingerprint
    public let acceptedAt: Date
    public let updatedAt: Date
    public let state: OperationState

    public init(
        operationId: OperationID,
        accountId: AccountID,
        contractVersion: OperationContractVersion,
        fingerprint: OperationFingerprint,
        acceptedAt: Date,
        updatedAt: Date,
        state: OperationState
    ) {
        self.operationId = operationId
        self.accountId = accountId
        self.contractVersion = contractVersion
        self.fingerprint = fingerprint
        self.acceptedAt = acceptedAt
        self.updatedAt = updatedAt
        self.state = state
    }
}

public enum OperationEventKind: String, Codable, CaseIterable, Sendable {
    case acceptLocally
    case beginApplying
    case transientFailure
    case applied
    case rejected
    case superseded
    case resolveRejection
}

public enum OperationEvent: Codable, Equatable, Sendable {
    case acceptLocally
    case beginApplying
    case transientFailure(ApplicationErrorSummary)
    case applied(AppliedOperationResult)
    case rejected(OperationRejection)
    case superseded(CorrectionReference)
    case resolveRejection(RejectionResolution)

    public var kind: OperationEventKind {
        switch self {
        case .acceptLocally: .acceptLocally
        case .beginApplying: .beginApplying
        case .transientFailure: .transientFailure
        case .applied: .applied
        case .rejected: .rejected
        case .superseded: .superseded
        case .resolveRejection: .resolveRejection
        }
    }
}

public enum OperationLifecycle {
    public static func transition(
        _ snapshot: OperationSnapshot,
        event: OperationEvent,
        at timestamp: Date
    ) throws -> OperationSnapshot {
        let state: OperationState
        switch (snapshot.state, event) {
        case (.draft, .acceptLocally):
            state = .queued(attemptCount: 0, lastTransientError: nil)
        case (.queued(let attempts, _), .beginApplying):
            state = .applying(attempt: attempts + 1, startedAt: timestamp)
        case (.applying(let attempt, _), .transientFailure(let error)):
            state = .queued(attemptCount: attempt, lastTransientError: error)
        case (.applying, .applied(let result)):
            state = .applied(result)
        case (.applying, .rejected(let rejection)):
            state = .rejected(rejection)
        case (.applied(let original), .superseded(let correction)):
            state = .superseded(original: original, correction: correction)
        case (.rejected(let rejection), .resolveRejection(let resolution)):
            state = .resolved(rejection: rejection, resolution: resolution)
        default:
            throw OperationContractFailure.illegalTransition(
                from: snapshot.state.phase,
                event: event.kind
            )
        }

        return OperationSnapshot(
            operationId: snapshot.operationId,
            accountId: snapshot.accountId,
            contractVersion: snapshot.contractVersion,
            fingerprint: snapshot.fingerprint,
            acceptedAt: snapshot.acceptedAt,
            updatedAt: timestamp,
            state: state
        )
    }
}

public struct OperationJournal: Codable, Sendable {
    private var records: [OperationSnapshot]

    public init() {
        records = []
    }

    public var snapshots: [OperationSnapshot] {
        records
    }

    public mutating func accept<Payload>(
        _ envelope: OperationEnvelope<Payload>,
        at timestamp: Date
    ) throws -> OperationReceipt where Payload: Codable & Sendable {
        let fingerprint = try OperationFingerprint.make(for: envelope)
        if let existing = records.first(where: { $0.operationId == envelope.operationId }) {
            guard existing.fingerprint == fingerprint else {
                throw OperationContractFailure.payloadMismatch(envelope.operationId)
            }
            return OperationReceipt(
                operationId: existing.operationId,
                localState: existing.state.localState ?? .queued
            )
        }

        let draft = OperationSnapshot(
            operationId: envelope.operationId,
            accountId: envelope.accountId,
            contractVersion: envelope.contractVersion,
            fingerprint: fingerprint,
            acceptedAt: timestamp,
            updatedAt: timestamp,
            state: .draft
        )
        let queued = try OperationLifecycle.transition(
            draft,
            event: .acceptLocally,
            at: timestamp
        )
        records.append(queued)
        return OperationReceipt(operationId: envelope.operationId, localState: .queued)
    }

    public func snapshot(for operationId: OperationID) -> OperationSnapshot? {
        records.first { $0.operationId == operationId }
    }

    public func unresolved(accountId: AccountID) -> [OperationSnapshot] {
        records
            .filter { $0.accountId == accountId && $0.state.isUnresolved }
            .sorted {
                if $0.acceptedAt != $1.acceptedAt {
                    return $0.acceptedAt < $1.acceptedAt
                }
                return $0.operationId.rawValue < $1.operationId.rawValue
            }
    }

    @discardableResult
    public mutating func apply(
        _ event: OperationEvent,
        to operationId: OperationID,
        at timestamp: Date
    ) throws -> OperationSnapshot {
        guard let index = records.firstIndex(where: { $0.operationId == operationId }) else {
            throw OperationContractFailure.missingOperation(operationId)
        }

        let current = records[index]
        if isIdempotentReplay(current.state, event: event) {
            return current
        }
        let next = try OperationLifecycle.transition(current, event: event, at: timestamp)
        records[index] = next
        return next
    }

    private func isIdempotentReplay(_ state: OperationState, event: OperationEvent) -> Bool {
        switch (state, event) {
        case (.applied(let existing), .applied(let replayed)):
            existing == replayed
        case (.rejected(let existing), .rejected(let replayed)):
            existing == replayed
        case (.superseded(_, let existing), .superseded(let replayed)):
            existing == replayed
        case (.resolved(_, let existing), .resolveRejection(let replayed)):
            existing == replayed
        default:
            false
        }
    }
}

public protocol OperationQuerying: Sendable {
    func watchOperation(
        _ id: OperationID
    ) -> AsyncThrowingStream<OperationSnapshot, Error>

    func watchUnresolvedOperations(
        accountId: AccountID
    ) -> AsyncThrowingStream<[OperationSnapshot], Error>
}

public enum ConnectivityState: String, Codable, CaseIterable, Sendable {
    case offline
    case connecting
    case online
}

public enum AuthenticationRefreshState: String, Codable, CaseIterable, Sendable {
    case unavailable
    case refreshing
    case current
    case stale
    case expired
    case revoked
}

public enum SubscriptionReadinessState: String, Codable, CaseIterable, Sendable {
    case notRequested
    case loading
    case ready
    case stale
    case blocked
}

public struct SubscriptionReadinessSnapshot: Codable, Equatable, Sendable {
    public let capability: CapabilityID
    public let required: Bool
    public let requiredContractVersion: OperationContractVersion
    public let localContractVersion: OperationContractVersion?
    public let state: SubscriptionReadinessState

    public init(
        capability: CapabilityID,
        required: Bool,
        requiredContractVersion: OperationContractVersion,
        localContractVersion: OperationContractVersion?,
        state: SubscriptionReadinessState
    ) {
        self.capability = capability
        self.required = required
        self.requiredContractVersion = requiredContractVersion
        self.localContractVersion = localContractVersion
        self.state = state
    }

    public var satisfiesRequirement: Bool {
        !required || (
            state == .ready &&
            localContractVersion == requiredContractVersion
        )
    }
}

public enum SyncWriteBlock: String, Codable, CaseIterable, Sendable {
    case none
    case maintenance
    case migrationRequired
    case clientUpdateRequired
    case authorizationExpired
    case authorizationRevoked
}

public struct SyncHealthSnapshot: Codable, Equatable, Sendable {
    public let connectivity: ConnectivityState
    public let authentication: AuthenticationRefreshState
    public let subscriptions: [SubscriptionReadinessSnapshot]
    public let lastSuccessfulCheckpointAt: Date?
    public let pendingOperationCount: Int
    public let oldestPendingOperationAt: Date?
    public let pendingAttachmentCount: Int
    public let oldestPendingAttachmentAt: Date?
    public let rejectedOperationCount: Int
    public let transientError: ApplicationErrorSummary?
    public let writeBlock: SyncWriteBlock

    public init(
        connectivity: ConnectivityState,
        authentication: AuthenticationRefreshState,
        subscriptions: [SubscriptionReadinessSnapshot],
        lastSuccessfulCheckpointAt: Date?,
        pendingOperationCount: Int,
        oldestPendingOperationAt: Date?,
        pendingAttachmentCount: Int,
        oldestPendingAttachmentAt: Date?,
        rejectedOperationCount: Int,
        transientError: ApplicationErrorSummary?,
        writeBlock: SyncWriteBlock
    ) throws {
        try Self.validateCount(
            pendingOperationCount,
            oldest: oldestPendingOperationAt,
            field: "pending_operations"
        )
        try Self.validateCount(
            pendingAttachmentCount,
            oldest: oldestPendingAttachmentAt,
            field: "pending_attachments"
        )
        guard rejectedOperationCount >= 0 else {
            throw OperationContractFailure.invalidCount(field: "rejected_operations")
        }

        self.connectivity = connectivity
        self.authentication = authentication
        self.subscriptions = subscriptions
        self.lastSuccessfulCheckpointAt = lastSuccessfulCheckpointAt
        self.pendingOperationCount = pendingOperationCount
        self.oldestPendingOperationAt = oldestPendingOperationAt
        self.pendingAttachmentCount = pendingAttachmentCount
        self.oldestPendingAttachmentAt = oldestPendingAttachmentAt
        self.rejectedOperationCount = rejectedOperationCount
        self.transientError = transientError
        self.writeBlock = writeBlock
    }

    public var isOnline: Bool {
        connectivity == .online
    }

    public var isSynchronized: Bool {
        lastSuccessfulCheckpointAt != nil &&
        subscriptions.allSatisfy(\.satisfiesRequirement) &&
        transientError == nil &&
        writeBlock == .none
    }

    private static func validateCount(
        _ count: Int,
        oldest: Date?,
        field: String
    ) throws {
        guard count >= 0 else {
            throw OperationContractFailure.invalidCount(field: field)
        }
        guard (count == 0) == (oldest == nil) else {
            throw OperationContractFailure.inconsistentOldestTimestamp(field: field)
        }
    }
}

public protocol SyncHealthProviding: Sendable {
    func observeHealth() -> AsyncStream<SyncHealthSnapshot>
    func waitForLocalDurability(of operationId: OperationID) async throws
}

public struct OperationDiagnostic: Codable, Equatable, Sendable {
    public let operationId: OperationID
    public let accountId: AccountID
    public let error: ApplicationErrorSummary

    public init(
        operationId: OperationID,
        accountId: AccountID,
        error: ApplicationErrorSummary
    ) {
        self.operationId = operationId
        self.accountId = accountId
        self.error = error
    }
}
