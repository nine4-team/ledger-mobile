import CryptoKit
import Foundation

public enum AccountDiscoverySelectionFailure: Error, Equatable, Sendable {
    case invalidDisplayName
    case duplicateAccountIdentity
    case invalidSnapshotAsOf
    case invalidSnapshotReadiness
    case snapshotFingerprintMismatch
    case invalidRequestedAt
    case accountUnavailable
    case scopeMismatch
    case snapshotChanged
    case selectionFingerprintMismatch
    case localReadFailed
    case invalidEncodedDisplayName
    case invalidEncodedAccountSummary
    case invalidEncodedSnapshot
    case invalidEncodedDiscoveryUpdate
    case invalidEncodedSelectionIntent

    public var diagnosticCode: String {
        switch self {
        case .invalidDisplayName: "account_discovery_display_name_invalid"
        case .duplicateAccountIdentity: "account_discovery_identity_duplicate"
        case .invalidSnapshotAsOf: "account_discovery_as_of_invalid"
        case .invalidSnapshotReadiness: "account_discovery_readiness_invalid"
        case .snapshotFingerprintMismatch: "account_discovery_snapshot_fingerprint_mismatch"
        case .invalidRequestedAt: "account_selection_requested_at_invalid"
        case .accountUnavailable: "account_selection_unavailable"
        case .scopeMismatch: "account_selection_scope_mismatch"
        case .snapshotChanged: "account_selection_snapshot_changed"
        case .selectionFingerprintMismatch: "account_selection_fingerprint_mismatch"
        case .localReadFailed: "account_discovery_local_read_failed"
        case .invalidEncodedDisplayName: "account_discovery_display_name_encoding_invalid"
        case .invalidEncodedAccountSummary: "account_discovery_summary_encoding_invalid"
        case .invalidEncodedSnapshot: "account_discovery_snapshot_encoding_invalid"
        case .invalidEncodedDiscoveryUpdate: "account_discovery_update_encoding_invalid"
        case .invalidEncodedSelectionIntent: "account_selection_intent_encoding_invalid"
        }
    }
}

public struct AccountDisplayName: Codable, Equatable, Hashable, Sendable {
    public static let maximumUTF8ByteCount = 200

    public let rawValue: String
    public let normalizedComparisonKey: String

    public init(validating rawValue: String) throws {
        let containsControlCharacter = rawValue.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
        }
        let displayValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let comparisonKey = displayValue
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
            .lowercased()
        guard !displayValue.isEmpty,
              displayValue.utf8.count <= Self.maximumUTF8ByteCount,
              !containsControlCharacter,
              !comparisonKey.isEmpty else {
            throw AccountDiscoverySelectionFailure.invalidDisplayName
        }
        self.rawValue = displayValue
        normalizedComparisonKey = comparisonKey
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            try self.init(validating: container.decode(String.self))
        } catch let failure as AccountDiscoverySelectionFailure {
            throw failure
        } catch {
            throw AccountDiscoverySelectionFailure.invalidEncodedDisplayName
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct AccountSummary: Codable, Equatable, Sendable {
    public let id: AccountID
    public let displayName: AccountDisplayName

    public init(id: AccountID, displayName: AccountDisplayName) {
        self.id = id
        self.displayName = displayName
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                id: try container.decode(AccountID.self, forKey: .id),
                displayName: try container.decode(AccountDisplayName.self, forKey: .displayName)
            )
        } catch let failure as AccountDiscoverySelectionFailure {
            throw failure
        } catch {
            throw AccountDiscoverySelectionFailure.invalidEncodedAccountSummary
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
    }
}

public struct AuthorizedAccountListFingerprint: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    fileprivate init(validating rawValue: String) throws {
        let lowercaseHexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        guard rawValue.utf8.count == 64,
              rawValue.unicodeScalars.allSatisfy(lowercaseHexadecimal.contains) else {
            throw AccountDiscoverySelectionFailure.snapshotFingerprintMismatch
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            try self.init(validating: container.decode(String.self))
        } catch let failure as AccountDiscoverySelectionFailure {
            throw failure
        } catch {
            throw AccountDiscoverySelectionFailure.snapshotFingerprintMismatch
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    fileprivate static func make(
        environment: LedgerEnvironmentKind,
        principalId: PrincipalID,
        accounts: [AccountSummary],
        isComplete: Bool,
        quality: ListSnapshotQuality,
        localDataVersion: LocalDataVersion,
        asOf: Date
    ) throws -> Self {
        let basis = AuthorizedAccountListFingerprintBasis(
            environment: environment,
            principalId: principalId,
            accounts: accounts,
            isComplete: isComplete,
            quality: quality,
            localDataVersion: localDataVersion,
            asOf: asOf
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

private struct AuthorizedAccountListFingerprintBasis: Codable {
    let environment: LedgerEnvironmentKind
    let principalId: PrincipalID
    let accounts: [AccountSummary]
    let isComplete: Bool
    let quality: ListSnapshotQuality
    let localDataVersion: LocalDataVersion
    let asOf: Date
}

public struct AuthorizedAccountListSnapshot: Codable, Equatable, Sendable {
    public let environment: LedgerEnvironmentKind
    public let principalId: PrincipalID
    public let accounts: [AccountSummary]
    public let isComplete: Bool
    public let quality: ListSnapshotQuality
    public let localDataVersion: LocalDataVersion
    public let asOf: Date
    public let fingerprint: AuthorizedAccountListFingerprint

    public var isAuthoritativeEmpty: Bool {
        isComplete && quality == .ready && accounts.isEmpty
    }

    public init(
        environment: LedgerEnvironmentKind,
        principalId: PrincipalID,
        accounts: [AccountSummary],
        isComplete: Bool,
        quality: ListSnapshotQuality,
        localDataVersion: LocalDataVersion,
        asOf: Date
    ) throws {
        guard asOf.timeIntervalSinceReferenceDate.isFinite else {
            throw AccountDiscoverySelectionFailure.invalidSnapshotAsOf
        }
        guard quality != .ready || isComplete,
              quality != .partial || !isComplete else {
            throw AccountDiscoverySelectionFailure.invalidSnapshotReadiness
        }
        guard Self.firstDuplicate(accounts.map(\.id)) == nil else {
            throw AccountDiscoverySelectionFailure.duplicateAccountIdentity
        }

        let orderedAccounts = accounts.sorted(by: Self.stableOrder)
        self.environment = environment
        self.principalId = principalId
        self.accounts = orderedAccounts
        self.isComplete = isComplete
        self.quality = quality
        self.localDataVersion = localDataVersion
        self.asOf = asOf
        fingerprint = try AuthorizedAccountListFingerprint.make(
            environment: environment,
            principalId: principalId,
            accounts: orderedAccounts,
            isComplete: isComplete,
            quality: quality,
            localDataVersion: localDataVersion,
            asOf: asOf
        )
    }

    private init(
        environment: LedgerEnvironmentKind,
        principalId: PrincipalID,
        accounts: [AccountSummary],
        isComplete: Bool,
        quality: ListSnapshotQuality,
        localDataVersion: LocalDataVersion,
        asOf: Date,
        fingerprint: AuthorizedAccountListFingerprint
    ) throws {
        let validated = try Self(
            environment: environment,
            principalId: principalId,
            accounts: accounts,
            isComplete: isComplete,
            quality: quality,
            localDataVersion: localDataVersion,
            asOf: asOf
        )
        guard fingerprint == validated.fingerprint else {
            throw AccountDiscoverySelectionFailure.snapshotFingerprintMismatch
        }
        self = validated
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                environment: container.decode(LedgerEnvironmentKind.self, forKey: .environment),
                principalId: container.decode(PrincipalID.self, forKey: .principalId),
                accounts: container.decode([AccountSummary].self, forKey: .accounts),
                isComplete: container.decode(Bool.self, forKey: .isComplete),
                quality: container.decode(ListSnapshotQuality.self, forKey: .quality),
                localDataVersion: container.decode(
                    LocalDataVersion.self,
                    forKey: .localDataVersion
                ),
                asOf: container.decode(Date.self, forKey: .asOf),
                fingerprint: container.decode(
                    AuthorizedAccountListFingerprint.self,
                    forKey: .fingerprint
                )
            )
        } catch let failure as AccountDiscoverySelectionFailure {
            throw failure
        } catch {
            throw AccountDiscoverySelectionFailure.invalidEncodedSnapshot
        }
    }

    public func orderedForPresentation(
        rememberedAccountId: AccountID?
    ) -> [AccountSummary] {
        guard let rememberedAccountId,
              let remembered = accounts.first(where: { $0.id == rememberedAccountId }) else {
            return accounts
        }
        return [remembered] + accounts.filter { $0.id != rememberedAccountId }
    }

    fileprivate func account(id: AccountID) -> AccountSummary? {
        accounts.first { $0.id == id }
    }

    private static func stableOrder(_ lhs: AccountSummary, _ rhs: AccountSummary) -> Bool {
        if lhs.displayName.normalizedComparisonKey != rhs.displayName.normalizedComparisonKey {
            return lhs.displayName.normalizedComparisonKey < rhs.displayName.normalizedComparisonKey
        }
        return lhs.id.rawValue < rhs.id.rawValue
    }

    private static func firstDuplicate<Value: Hashable>(_ values: [Value]) -> Value? {
        var seen: Set<Value> = []
        return values.first { !seen.insert($0).inserted }
    }

    private enum CodingKeys: String, CodingKey {
        case environment
        case principalId
        case accounts
        case isComplete
        case quality
        case localDataVersion
        case asOf
        case fingerprint
    }
}

public enum AccountDiscoveryWaitingState: String, Codable, CaseIterable, Sendable {
    case notRequested
    case loading
}

public enum AuthorizedAccountDiscoveryUpdate: Codable, Equatable, Sendable {
    case waiting(AccountDiscoveryWaitingState)
    case snapshot(AuthorizedAccountListSnapshot)
    case failed(failure: ListFailureState, cached: AuthorizedAccountListSnapshot?)

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(Kind.self, forKey: .kind) {
            case .waiting:
                self = .waiting(try container.decode(
                    AccountDiscoveryWaitingState.self,
                    forKey: .waitingState
                ))
            case .snapshot:
                self = .snapshot(try container.decode(
                    AuthorizedAccountListSnapshot.self,
                    forKey: .snapshot
                ))
            case .failed:
                self = .failed(
                    failure: try container.decode(ListFailureState.self, forKey: .failure),
                    cached: try container.decodeIfPresent(
                        AuthorizedAccountListSnapshot.self,
                        forKey: .cached
                    )
                )
            }
        } catch let failure as AccountDiscoverySelectionFailure {
            throw failure
        } catch {
            throw AccountDiscoverySelectionFailure.invalidEncodedDiscoveryUpdate
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .waiting(let state):
            try container.encode(Kind.waiting, forKey: .kind)
            try container.encode(state, forKey: .waitingState)
        case .snapshot(let snapshot):
            try container.encode(Kind.snapshot, forKey: .kind)
            try container.encode(snapshot, forKey: .snapshot)
        case .failed(let failure, let cached):
            try container.encode(Kind.failed, forKey: .kind)
            try container.encode(failure, forKey: .failure)
            try container.encodeIfPresent(cached, forKey: .cached)
        }
    }

    private enum Kind: String, Codable {
        case waiting
        case snapshot
        case failed
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case waitingState
        case snapshot
        case failure
        case cached
    }
}

public struct WorkspaceSelectionFingerprint: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    fileprivate init(validating rawValue: String) throws {
        let lowercaseHexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        guard rawValue.utf8.count == 64,
              rawValue.unicodeScalars.allSatisfy(lowercaseHexadecimal.contains) else {
            throw AccountDiscoverySelectionFailure.selectionFingerprintMismatch
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            try self.init(validating: container.decode(String.self))
        } catch let failure as AccountDiscoverySelectionFailure {
            throw failure
        } catch {
            throw AccountDiscoverySelectionFailure.selectionFingerprintMismatch
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
        sourceSnapshotFingerprint: AuthorizedAccountListFingerprint,
        localDataVersion: LocalDataVersion,
        requestedAt: Date
    ) throws -> Self {
        let basis = WorkspaceSelectionFingerprintBasis(
            environment: environment,
            principalId: principalId,
            accountId: accountId,
            sourceSnapshotFingerprint: sourceSnapshotFingerprint,
            localDataVersion: localDataVersion,
            requestedAt: requestedAt
        )
        return try Self(validating: AuthorizedAccountListFingerprint.hexDigest(
            try OperationContractCodec.encode(basis)
        ))
    }
}

private struct WorkspaceSelectionFingerprintBasis: Codable {
    let environment: LedgerEnvironmentKind
    let principalId: PrincipalID
    let accountId: AccountID
    let sourceSnapshotFingerprint: AuthorizedAccountListFingerprint
    let localDataVersion: LocalDataVersion
    let requestedAt: Date
}

public struct WorkspaceSelectionIntent: Codable, Equatable, Sendable {
    public let environment: LedgerEnvironmentKind
    public let principalId: PrincipalID
    public let accountId: AccountID
    public let sourceSnapshotFingerprint: AuthorizedAccountListFingerprint
    public let localDataVersion: LocalDataVersion
    public let requestedAt: Date
    public let fingerprint: WorkspaceSelectionFingerprint

    fileprivate init(
        environment: LedgerEnvironmentKind,
        principalId: PrincipalID,
        accountId: AccountID,
        sourceSnapshotFingerprint: AuthorizedAccountListFingerprint,
        localDataVersion: LocalDataVersion,
        requestedAt: Date
    ) throws {
        guard requestedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw AccountDiscoverySelectionFailure.invalidRequestedAt
        }
        self.environment = environment
        self.principalId = principalId
        self.accountId = accountId
        self.sourceSnapshotFingerprint = sourceSnapshotFingerprint
        self.localDataVersion = localDataVersion
        self.requestedAt = requestedAt
        fingerprint = try WorkspaceSelectionFingerprint.make(
            environment: environment,
            principalId: principalId,
            accountId: accountId,
            sourceSnapshotFingerprint: sourceSnapshotFingerprint,
            localDataVersion: localDataVersion,
            requestedAt: requestedAt
        )
    }

    private init(
        environment: LedgerEnvironmentKind,
        principalId: PrincipalID,
        accountId: AccountID,
        sourceSnapshotFingerprint: AuthorizedAccountListFingerprint,
        localDataVersion: LocalDataVersion,
        requestedAt: Date,
        fingerprint: WorkspaceSelectionFingerprint
    ) throws {
        let validated = try Self(
            environment: environment,
            principalId: principalId,
            accountId: accountId,
            sourceSnapshotFingerprint: sourceSnapshotFingerprint,
            localDataVersion: localDataVersion,
            requestedAt: requestedAt
        )
        guard fingerprint == validated.fingerprint else {
            throw AccountDiscoverySelectionFailure.selectionFingerprintMismatch
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
                sourceSnapshotFingerprint: container.decode(
                    AuthorizedAccountListFingerprint.self,
                    forKey: .sourceSnapshotFingerprint
                ),
                localDataVersion: container.decode(
                    LocalDataVersion.self,
                    forKey: .localDataVersion
                ),
                requestedAt: container.decode(Date.self, forKey: .requestedAt),
                fingerprint: container.decode(
                    WorkspaceSelectionFingerprint.self,
                    forKey: .fingerprint
                )
            )
        } catch let failure as AccountDiscoverySelectionFailure {
            throw failure
        } catch {
            throw AccountDiscoverySelectionFailure.invalidEncodedSelectionIntent
        }
    }

    private enum CodingKeys: String, CodingKey {
        case environment
        case principalId
        case accountId
        case sourceSnapshotFingerprint
        case localDataVersion
        case requestedAt
        case fingerprint
    }
}

public enum AccountSelectionPolicy {
    public static func makeIntent(
        selecting accountId: AccountID,
        from snapshot: AuthorizedAccountListSnapshot,
        requestedAt: Date
    ) throws -> WorkspaceSelectionIntent {
        guard requestedAt.timeIntervalSinceReferenceDate.isFinite,
              requestedAt >= snapshot.asOf else {
            throw AccountDiscoverySelectionFailure.invalidRequestedAt
        }
        guard snapshot.account(id: accountId) != nil else {
            throw AccountDiscoverySelectionFailure.accountUnavailable
        }
        return try WorkspaceSelectionIntent(
            environment: snapshot.environment,
            principalId: snapshot.principalId,
            accountId: accountId,
            sourceSnapshotFingerprint: snapshot.fingerprint,
            localDataVersion: snapshot.localDataVersion,
            requestedAt: requestedAt
        )
    }

    public static func validate(
        _ intent: WorkspaceSelectionIntent,
        against currentSnapshot: AuthorizedAccountListSnapshot
    ) throws -> AccountSummary {
        guard intent.environment == currentSnapshot.environment,
              intent.principalId == currentSnapshot.principalId else {
            throw AccountDiscoverySelectionFailure.scopeMismatch
        }
        guard intent.sourceSnapshotFingerprint == currentSnapshot.fingerprint,
              intent.localDataVersion == currentSnapshot.localDataVersion else {
            throw AccountDiscoverySelectionFailure.snapshotChanged
        }
        guard let account = currentSnapshot.account(id: intent.accountId) else {
            throw AccountDiscoverySelectionFailure.accountUnavailable
        }
        return account
    }
}

public protocol AccountQuerying: Sendable {
    func watchAuthorizedAccounts(
        environment: LedgerEnvironmentKind,
        principalId: PrincipalID
    ) -> AsyncThrowingStream<AuthorizedAccountDiscoveryUpdate, Error>
}

