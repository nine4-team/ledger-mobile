import CryptoKit
import Foundation
import LedgerTargetCore
import PowerSync

public enum AccountDiscoveryFreshness: String, Codable, CaseIterable, Sendable {
    case fresh
    case stale
}

/// Query-specific evidence supplied by the eventual identity-bootstrap stream.
/// It is deliberately independent from connection-wide PowerSync status.
public struct AccountDiscoveryReadiness: Codable, Equatable, Sendable {
    public let relationshipsAreComplete: Bool
    public let freshness: AccountDiscoveryFreshness

    public init(
        relationshipsAreComplete: Bool,
        freshness: AccountDiscoveryFreshness
    ) {
        self.relationshipsAreComplete = relationshipsAreComplete
        self.freshness = freshness
    }
}

struct AccountDiscoveryLocalRow: Equatable, Sendable {
    let principalIsPresent: Bool
    let rawActiveMembershipCount: Int64
    let membershipId: String?
    let membershipAccountId: String?
    let joinedAccountId: String?
    let displayName: String?

    init(
        principalIsPresent: Bool,
        rawActiveMembershipCount: Int64,
        membershipId: String?,
        membershipAccountId: String?,
        joinedAccountId: String?,
        displayName: String?
    ) {
        self.principalIsPresent = principalIsPresent
        self.rawActiveMembershipCount = rawActiveMembershipCount
        self.membershipId = membershipId
        self.membershipAccountId = membershipAccountId
        self.joinedAccountId = joinedAccountId
        self.displayName = displayName
    }

    init(cursor: any SqlCursor) throws {
        principalIsPresent = try cursor.getInt64(name: "principal_is_present") == 1
        rawActiveMembershipCount = try cursor.getInt64(name: "raw_membership_count")
        membershipId = try cursor.getStringOptional(name: "membership_id")
        membershipAccountId = try cursor.getStringOptional(name: "membership_account_id")
        joinedAccountId = try cursor.getStringOptional(name: "joined_account_id")
        displayName = try cursor.getStringOptional(name: "display_name")
    }
}

protocol AccountDiscoveryLocalReading: Sendable {
    func watchRows(
        principalId: PrincipalID
    ) throws -> AsyncThrowingStream<[AccountDiscoveryLocalRow], Error>
}

private final class PowerSyncAccountDiscoveryLocalReader:
    AccountDiscoveryLocalReading, @unchecked Sendable
{
    private let database: any PowerSyncDatabaseProtocol

    init(database: any PowerSyncDatabaseProtocol) {
        self.database = database
    }

    func watchRows(
        principalId: PrincipalID
    ) throws -> AsyncThrowingStream<[AccountDiscoveryLocalRow], Error> {
        try database.watch(
            sql: Self.accountDiscoverySQL,
            parameters: [principalId.rawValue, principalId.rawValue]
        ) { cursor in
            try AccountDiscoveryLocalRow(cursor: cursor)
        }
    }

    /// The count is intentionally computed before the Account join. A missing or
    /// malformed Account row therefore cannot masquerade as an empty membership set.
    private static let accountDiscoverySQL = """
        WITH principal_scope AS (
          SELECT EXISTS (
            SELECT 1
            FROM spike_principals
            WHERE id = ?
          ) AS principal_is_present
        ), active_memberships AS (
          SELECT id, account_id
          FROM spike_account_memberships
          WHERE principal_id = ? AND state = 'active'
        ), membership_count AS (
          SELECT count(*) AS raw_membership_count
          FROM active_memberships
        )
        SELECT principal_scope.principal_is_present,
               membership_count.raw_membership_count,
               membership.id AS membership_id,
               membership.account_id AS membership_account_id,
               account.id AS joined_account_id,
               account.display_name
        FROM principal_scope
        CROSS JOIN membership_count
        LEFT JOIN active_memberships AS membership
          ON principal_scope.principal_is_present
        LEFT JOIN spike_accounts AS account
          ON account.id = membership.account_id
        ORDER BY membership.account_id, membership.id
        """
}

/// Principal- and environment-bound PowerSync implementation of AccountQuerying.
/// It reports local evidence only; it does not activate an Account workspace or
/// turn historical connection state into current authorization.
public final class AccountDiscoveryPowerSyncQuery: AccountQuerying, @unchecked Sendable {
    public typealias ReadinessObservation = @Sendable () -> AsyncThrowingStream<
        AccountDiscoveryReadiness,
        Error
    >

    private let localReader: any AccountDiscoveryLocalReading
    private let boundEnvironment: LedgerEnvironmentKind
    private let boundPrincipalId: PrincipalID
    private let readinessObservation: ReadinessObservation
    private let now: @Sendable () -> Date

    public convenience init(
        database: any PowerSyncDatabaseProtocol,
        environment: LedgerEnvironmentKind,
        principalId: PrincipalID,
        readinessObservation: @escaping ReadinessObservation,
        now: @Sendable @escaping () -> Date = Date.init
    ) {
        self.init(
            localReader: PowerSyncAccountDiscoveryLocalReader(database: database),
            environment: environment,
            principalId: principalId,
            readinessObservation: readinessObservation,
            now: now
        )
    }

    public convenience init(
        database: any PowerSyncDatabaseProtocol,
        environment: LedgerEnvironmentKind,
        principalId: PrincipalID,
        now: @Sendable @escaping () -> Date = Date.init
    ) {
        self.init(
            database: database,
            environment: environment,
            principalId: principalId,
            readinessObservation: AccountDiscoveryPowerSyncQuery.notReadyObservation,
            now: now
        )
    }

    init(
        localReader: any AccountDiscoveryLocalReading,
        environment: LedgerEnvironmentKind,
        principalId: PrincipalID,
        readinessObservation: @escaping ReadinessObservation,
        now: @Sendable @escaping () -> Date = Date.init
    ) {
        self.localReader = localReader
        boundEnvironment = environment
        boundPrincipalId = principalId
        self.readinessObservation = readinessObservation
        self.now = now
    }

    public func watchAuthorizedAccounts(
        environment: LedgerEnvironmentKind,
        principalId: PrincipalID
    ) -> AsyncThrowingStream<AuthorizedAccountDiscoveryUpdate, Error> {
        guard environment == boundEnvironment,
              principalId == boundPrincipalId else {
            return Self.boundedFailureStream(failure: .unavailable, cached: nil)
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.waiting(.loading))
                var latestRows: [AccountDiscoveryLocalRow]?
                var latestReadiness: AccountDiscoveryReadiness?
                var cachedSnapshot: AuthorizedAccountListSnapshot?

                do {
                    for try await event in events() {
                        try Task.checkCancellation()
                        switch event {
                        case .rows(let rows):
                            latestRows = rows
                        case .readiness(let readiness):
                            latestReadiness = readiness
                        case .sourceTerminated:
                            continuation.yield(
                                .failed(failure: .retryable, cached: cachedSnapshot)
                            )
                            continuation.finish()
                            return
                        }

                        guard let latestRows else { continue }
                        let snapshot = try Self.makeSnapshot(
                            rows: latestRows,
                            readiness: latestReadiness,
                            environment: boundEnvironment,
                            principalId: boundPrincipalId,
                            asOf: now()
                        )
                        cachedSnapshot = snapshot
                        continuation.yield(.snapshot(snapshot))
                    }

                    if !Task.isCancelled {
                        continuation.yield(
                            .failed(failure: .retryable, cached: cachedSnapshot)
                        )
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(failure: .retryable, cached: cachedSnapshot))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private enum Event: Sendable {
        case rows([AccountDiscoveryLocalRow])
        case readiness(AccountDiscoveryReadiness)
        case sourceTerminated
    }

    private func events() -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let databaseTask = Task {
                do {
                    let updates = try localReader.watchRows(principalId: boundPrincipalId)
                    for try await rows in updates {
                        try Task.checkCancellation()
                        continuation.yield(.rows(rows))
                    }
                    if !Task.isCancelled {
                        continuation.yield(.sourceTerminated)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            let readinessTask = Task {
                do {
                    for try await readiness in readinessObservation() {
                        try Task.checkCancellation()
                        continuation.yield(.readiness(readiness))
                    }
                    if !Task.isCancelled {
                        continuation.yield(.sourceTerminated)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                databaseTask.cancel()
                readinessTask.cancel()
            }
        }
    }

    private static func makeSnapshot(
        rows: [AccountDiscoveryLocalRow],
        readiness: AccountDiscoveryReadiness?,
        environment: LedgerEnvironmentKind,
        principalId: PrincipalID,
        asOf: Date
    ) throws -> AuthorizedAccountListSnapshot {
        let first = rows.first
        let principalIsPresent = first?.principalIsPresent == true
        let rawMembershipCount = first?.rawActiveMembershipCount ?? 0
        var relationshipEvidenceIsValid = !rows.isEmpty
            && rawMembershipCount >= 0
            && rows.allSatisfy {
                $0.principalIsPresent == principalIsPresent
                    && $0.rawActiveMembershipCount == rawMembershipCount
            }
        let membershipRows = rows.filter { $0.membershipId != nil }
        if rawMembershipCount == 0 {
            let exactSentinel = rows.count == 1
                && rows[0].membershipId == nil
                && rows[0].membershipAccountId == nil
                && rows[0].joinedAccountId == nil
                && rows[0].displayName == nil
            relationshipEvidenceIsValid = relationshipEvidenceIsValid
                && principalIsPresent
                && exactSentinel
        } else {
            let membershipIds = membershipRows.compactMap { row -> EntityID? in
                guard let rawValue = row.membershipId else { return nil }
                return try? EntityID(validating: rawValue)
            }
            relationshipEvidenceIsValid = relationshipEvidenceIsValid
                && principalIsPresent
                && Int64(rows.count) == rawMembershipCount
                && Int64(membershipRows.count) == rawMembershipCount
                && membershipIds.count == membershipRows.count
                && Set(membershipIds).count == membershipIds.count
        }

        var accountsById: [AccountID: AccountSummary] = [:]
        for row in membershipRows {
            guard let membershipAccountId = row.membershipAccountId,
                  let joinedAccountId = row.joinedAccountId,
                  membershipAccountId == joinedAccountId,
                  let displayName = row.displayName,
                  let accountId = try? AccountID(validating: joinedAccountId),
                  let accountName = try? AccountDisplayName(validating: displayName) else {
                relationshipEvidenceIsValid = false
                continue
            }
            guard accountsById[accountId] == nil else {
                relationshipEvidenceIsValid = false
                continue
            }
            accountsById[accountId] = AccountSummary(
                id: accountId,
                displayName: accountName
            )
        }

        relationshipEvidenceIsValid = relationshipEvidenceIsValid
            && Int64(accountsById.count) == rawMembershipCount
        let accounts = Array(accountsById.values)
        let isComplete = relationshipEvidenceIsValid
            && readiness?.relationshipsAreComplete == true
        let quality = Self.quality(
            isComplete: isComplete,
            freshness: readiness?.freshness
        )
        let localDataVersion = try Self.localDataVersion(
            environment: environment,
            principalId: principalId,
            principalIsPresent: principalIsPresent,
            rawMembershipCount: rawMembershipCount,
            relationshipEvidenceIsValid: relationshipEvidenceIsValid,
            readiness: readiness,
            quality: quality,
            accounts: accounts
        )
        return try AuthorizedAccountListSnapshot(
            environment: environment,
            principalId: principalId,
            accounts: accounts,
            isComplete: isComplete,
            quality: quality,
            localDataVersion: localDataVersion,
            asOf: asOf
        )
    }

    private static func quality(
        isComplete: Bool,
        freshness: AccountDiscoveryFreshness?
    ) -> ListSnapshotQuality {
        guard isComplete else {
            return .partial
        }
        return freshness == .fresh ? .ready : .stale
    }

    private static func localDataVersion(
        environment: LedgerEnvironmentKind,
        principalId: PrincipalID,
        principalIsPresent: Bool,
        rawMembershipCount: Int64,
        relationshipEvidenceIsValid: Bool,
        readiness: AccountDiscoveryReadiness?,
        quality: ListSnapshotQuality,
        accounts: [AccountSummary]
    ) throws -> LocalDataVersion {
        let basis = LocalVersionBasis(
            contractVersion: "account-discovery-local-v1",
            environment: environment,
            principalId: principalId,
            principalIsPresent: principalIsPresent,
            rawMembershipCount: rawMembershipCount,
            relationshipEvidenceIsValid: relationshipEvidenceIsValid,
            readiness: readiness,
            quality: quality,
            accounts: accounts.sorted {
                if $0.displayName.normalizedComparisonKey
                    != $1.displayName.normalizedComparisonKey {
                    return $0.displayName.normalizedComparisonKey
                        < $1.displayName.normalizedComparisonKey
                }
                return $0.id.rawValue < $1.id.rawValue
            }
        )
        let encoded = try OperationContractCodec.encode(basis)
        let digest = SHA256.hash(data: encoded)
            .map { String(format: "%02x", $0) }
            .joined()
        return try LocalDataVersion(validating: "account-discovery-\(digest)")
    }

    private struct LocalVersionBasis: Codable {
        let contractVersion: String
        let environment: LedgerEnvironmentKind
        let principalId: PrincipalID
        let principalIsPresent: Bool
        let rawMembershipCount: Int64
        let relationshipEvidenceIsValid: Bool
        let readiness: AccountDiscoveryReadiness?
        let quality: ListSnapshotQuality
        let accounts: [AccountSummary]
    }

    private static func boundedFailureStream(
        failure: ListFailureState,
        cached: AuthorizedAccountListSnapshot?
    ) -> AsyncThrowingStream<AuthorizedAccountDiscoveryUpdate, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.failed(failure: failure, cached: cached))
            continuation.finish()
        }
    }

    private static func notReadyObservation() -> AsyncThrowingStream<
        AccountDiscoveryReadiness,
        Error
    > {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(AccountDiscoveryReadiness(
                    relationshipsAreComplete: false,
                    freshness: .stale
                ))
                do {
                    while !Task.isCancelled {
                        try await Task.sleep(for: .seconds(3_600))
                    }
                } catch {
                    return
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
