import Foundation
import LedgerTargetCore
import PowerSync
import Testing
@testable import LedgerTargetPowerSync

@Suite("Account discovery PowerSync provider", .serialized)
struct AccountDiscoveryPowerSyncQueryTests {
    private static let environment = LedgerEnvironmentKind.targetLocal
    private static let principalId = try! PrincipalID(validating: "principal-owner")
    private static let observedAt = Date(timeIntervalSince1970: 1_788_700_000)

    @Test("Zero, one, many, and equal-name Accounts stay explicit and deterministic")
    func deterministicDiscoveryAndSelection() async throws {
        let zero = try await Self.snapshot(
            rows: [Self.sentinel(rawCount: 0)],
            readiness: .freshComplete
        )
        #expect(zero.accounts.isEmpty)
        #expect(zero.isAuthoritativeEmpty)

        let one = try await Self.snapshot(
            rows: [Self.row(membership: "m-a", account: "account-a", name: "Aster")],
            readiness: .freshComplete
        )
        #expect(one.accounts.map(\.id.rawValue) == ["account-a"])
        #expect(one.quality == .ready)

        let many = try await Self.snapshot(
            rows: [
                Self.row(
                    membership: "m-z", account: "account-z", name: "Same Name", rawCount: 3
                ),
                Self.row(
                    membership: "m-b", account: "account-b", name: "Beta", rawCount: 3
                ),
                Self.row(
                    membership: "m-a", account: "account-a", name: "same   name", rawCount: 3
                )
            ],
            readiness: .freshComplete
        )
        #expect(many.accounts.map(\.id.rawValue) == [
            "account-b", "account-a", "account-z"
        ])
        #expect(many.accounts.suffix(2).map(\.displayName.normalizedComparisonKey)
            == ["same name", "same name"])

        let selectedId = try AccountID(validating: "account-z")
        let intent = try AccountSelectionPolicy.makeIntent(
            selecting: selectedId,
            from: many,
            requestedAt: many.asOf.addingTimeInterval(1)
        )
        #expect(try AccountSelectionPolicy.validate(intent, against: many).id == selectedId)

        let changed = try await Self.snapshot(
            rows: [
                Self.row(
                    membership: "m-z", account: "account-z", name: "Same Name", rawCount: 2
                ),
                Self.row(
                    membership: "m-b", account: "account-b", name: "Beta", rawCount: 2
                )
            ],
            readiness: .freshComplete
        )
        #expect(throws: AccountDiscoverySelectionFailure.snapshotChanged) {
            try AccountSelectionPolicy.validate(intent, against: changed)
        }
    }

    @Test("Freshness changes emit ready, stale, ready without row changes")
    func readinessIsIndependentlyReactive() async throws {
        let rows = TestStreamSource<[AccountDiscoveryLocalRow]>()
        let readiness = TestStreamSource<AccountDiscoveryReadiness>()
        let reader = ControlledAccountReader(source: rows)
        let query = Self.query(reader: reader, readiness: readiness)
        var iterator = query.watchAuthorizedAccounts(
            environment: Self.environment,
            principalId: Self.principalId
        ).makeAsyncIterator()

        #expect(try await iterator.next() == .waiting(.loading))
        rows.yield([Self.row(membership: "m-a", account: "account-a", name: "Aster")])
        let partial = try Self.requireSnapshot(try await iterator.next())
        #expect(partial.quality == .partial)

        readiness.yield(.freshComplete)
        let ready = try Self.requireSnapshot(try await iterator.next())
        readiness.yield(.staleComplete)
        let stale = try Self.requireSnapshot(try await iterator.next())
        readiness.yield(.freshComplete)
        let readyAgain = try Self.requireSnapshot(try await iterator.next())

        #expect(ready.quality == .ready)
        #expect(stale.quality == .stale)
        #expect(stale.isComplete)
        #expect(!stale.isAuthoritativeEmpty)
        #expect(readyAgain.quality == .ready)
        #expect(ready.localDataVersion != stale.localDataVersion)
        #expect(ready.localDataVersion == readyAgain.localDataVersion)
        #expect(ready.accounts == stale.accounts)
        #expect(stale.accounts == readyAgain.accounts)
        rows.finish()
        readiness.finish()

        let staleEmpty = try await Self.snapshot(
            rows: [Self.sentinel(rawCount: 0)],
            readiness: .staleComplete,
            expectedQuality: .stale
        )
        #expect(staleEmpty.isComplete)
        #expect(!staleEmpty.isAuthoritativeEmpty)
    }

    @Test("Missing and malformed relationship evidence cannot become authoritative empty")
    func malformedRelationshipsStayPartial() async throws {
        let cases: [[AccountDiscoveryLocalRow]] = [
            [Self.sentinel(principalPresent: false, rawCount: 0)],
            [AccountDiscoveryLocalRow(
                principalIsPresent: true,
                rawActiveMembershipCount: 0,
                membershipId: nil,
                membershipAccountId: "account-ghost",
                joinedAccountId: "account-ghost",
                displayName: "Ghost"
            )],
            [Self.sentinel(rawCount: 0), Self.sentinel(rawCount: 0)],
            [Self.row(membership: " ", account: "account-a", name: "Aster")],
            [Self.row(
                membership: "m-missing",
                account: "account-missing",
                joinedAccount: nil,
                name: nil
            )],
            [Self.row(
                membership: "m-malformed",
                account: "account-malformed",
                name: "\n"
            )],
            [
                Self.row(membership: "m-1", account: "account-a", name: "Aster", rawCount: 2),
                Self.row(membership: "m-2", account: "account-a", name: "Aster", rawCount: 2)
            ],
            [
                Self.row(membership: "m-a", account: "account-a", name: "Aster"),
                AccountDiscoveryLocalRow(
                    principalIsPresent: true,
                    rawActiveMembershipCount: 1,
                    membershipId: nil,
                    membershipAccountId: nil,
                    joinedAccountId: nil,
                    displayName: nil
                )
            ]
        ]

        for rows in cases {
            let snapshot = try await Self.snapshot(
                rows: rows,
                readiness: .freshComplete,
                expectedQuality: .partial
            )
            #expect(snapshot.quality == .partial)
            #expect(!snapshot.isComplete)
            #expect(!snapshot.isAuthoritativeEmpty)
        }
    }

    @Test("Local SQL includes only active same-Principal memberships")
    func localSQLIsPrincipalScoped() async throws {
        let fixture = try AccountDatabaseFixture()
        let database = try fixture.open()
        try await Self.insertPrincipal(database, id: Self.principalId.rawValue)
        try await Self.insertPrincipal(database, id: "principal-other")
        try await Self.insertAccount(database, id: "account-active", name: "Active")
        try await Self.insertAccount(database, id: "account-inactive", name: "Inactive")
        try await Self.insertAccount(database, id: "account-other", name: "Other")
        try await Self.insertMembership(
            database,
            id: "m-active",
            accountId: "account-active",
            principalId: Self.principalId.rawValue,
            state: "active"
        )
        try await Self.insertMembership(
            database,
            id: "m-inactive",
            accountId: "account-inactive",
            principalId: Self.principalId.rawValue,
            state: "revoked"
        )
        try await Self.insertMembership(
            database,
            id: "m-other",
            accountId: "account-other",
            principalId: "principal-other",
            state: "active"
        )

        let readiness = TestStreamSource<AccountDiscoveryReadiness>()
        readiness.yield(.freshComplete)
        let query = AccountDiscoveryPowerSyncQuery(
            database: database,
            environment: Self.environment,
            principalId: Self.principalId,
            readinessObservation: { readiness.stream },
            now: { Self.observedAt }
        )
        let snapshot = try await Self.firstSnapshot(
            query.watchAuthorizedAccounts(
                environment: Self.environment,
                principalId: Self.principalId
            ),
            quality: .ready
        )
        #expect(snapshot.accounts.map(\.id.rawValue) == ["account-active"])

        try await database.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("Missing Principal and membership-before-Account stay incomplete in local SQL")
    func localSQLPreventsFalseEmpty() async throws {
        let fixture = try AccountDatabaseFixture()
        let database = try fixture.open()
        try await Self.insertMembership(
            database,
            id: "m-delayed",
            accountId: "account-delayed",
            principalId: Self.principalId.rawValue,
            state: "active"
        )
        let readiness = TestStreamSource<AccountDiscoveryReadiness>()
        readiness.yield(.freshComplete)
        let query = AccountDiscoveryPowerSyncQuery(
            database: database,
            environment: Self.environment,
            principalId: Self.principalId,
            readinessObservation: { readiness.stream },
            now: { Self.observedAt }
        )
        var iterator = query.watchAuthorizedAccounts(
            environment: Self.environment,
            principalId: Self.principalId
        ).makeAsyncIterator()
        let missingPrincipal = try await Self.nextSnapshot(&iterator, quality: .partial)
        #expect(missingPrincipal.accounts.isEmpty)
        #expect(!missingPrincipal.isAuthoritativeEmpty)

        try await Self.insertPrincipal(database, id: Self.principalId.rawValue)
        let missingAccount = try await Self.nextSnapshot(&iterator, quality: .partial)
        #expect(missingAccount.accounts.isEmpty)
        #expect(!missingAccount.isAuthoritativeEmpty)

        try await Self.insertAccount(database, id: "account-delayed", name: "Arrived")
        let joined = try await Self.nextSnapshot(&iterator, quality: .ready)
        #expect(joined.accounts.map(\.id.rawValue) == ["account-delayed"])
        #expect(joined.isComplete)

        try await database.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("Cross-environment and cross-Principal requests perform zero local reads")
    func rejectedScopePerformsZeroDatabaseAccess() async throws {
        let rows = TestStreamSource<[AccountDiscoveryLocalRow]>()
        let readiness = TestStreamSource<AccountDiscoveryReadiness>()
        let reader = ControlledAccountReader(source: rows)
        let query = Self.query(reader: reader, readiness: readiness)

        let wrongEnvironment = query.watchAuthorizedAccounts(
            environment: .targetStaging,
            principalId: Self.principalId
        )
        #expect(try await wrongEnvironment.firstUpdate()
            == .failed(failure: .unavailable, cached: nil))
        let otherPrincipal = try PrincipalID(validating: "principal-other")
        let wrongPrincipal = query.watchAuthorizedAccounts(
            environment: Self.environment,
            principalId: otherPrincipal
        )
        #expect(try await wrongPrincipal.firstUpdate()
            == .failed(failure: .unavailable, cached: nil))
        #expect(reader.accessCount == 0)
    }

    @Test("Read and readiness failures are bounded and retain only exact cache")
    func failuresAreBounded() async throws {
        do {
            let rows = TestStreamSource<[AccountDiscoveryLocalRow]>()
            let readiness = TestStreamSource<AccountDiscoveryReadiness>()
            let query = Self.query(
                reader: ControlledAccountReader(source: rows),
                readiness: readiness
            )
            var iterator = query.watchAuthorizedAccounts(
                environment: Self.environment,
                principalId: Self.principalId
            ).makeAsyncIterator()
            _ = try await iterator.next()
            rows.fail(TestProviderFailure.secretProviderFailure)
            #expect(try await iterator.next()
                == .failed(failure: .retryable, cached: nil))
            #expect(try await iterator.next() == nil)
        }

        do {
            let rows = TestStreamSource<[AccountDiscoveryLocalRow]>()
            let readiness = TestStreamSource<AccountDiscoveryReadiness>()
            let query = Self.query(
                reader: ControlledAccountReader(source: rows),
                readiness: readiness
            )
            var iterator = query.watchAuthorizedAccounts(
                environment: Self.environment,
                principalId: Self.principalId
            ).makeAsyncIterator()
            _ = try await iterator.next()
            readiness.fail(TestProviderFailure.secretProviderFailure)
            #expect(try await iterator.next()
                == .failed(failure: .retryable, cached: nil))
            #expect(try await iterator.next() == nil)
        }

        do {
            let rows = TestStreamSource<[AccountDiscoveryLocalRow]>()
            let readiness = TestStreamSource<AccountDiscoveryReadiness>()
            let query = Self.query(
                reader: ControlledAccountReader(source: rows),
                readiness: readiness
            )
            var iterator = query.watchAuthorizedAccounts(
                environment: Self.environment,
                principalId: Self.principalId
            ).makeAsyncIterator()
            _ = try await iterator.next()
            readiness.yield(.freshComplete)
            rows.yield([Self.row(membership: "m-a", account: "account-a", name: "Aster")])
            let cached = try await Self.nextSnapshot(&iterator, quality: .ready)
            readiness.fail(TestProviderFailure.secretProviderFailure)
            #expect(try await iterator.next()
                == .failed(failure: .retryable, cached: cached))
            #expect(try await iterator.next() == nil)
        }

        do {
            let rows = TestStreamSource<[AccountDiscoveryLocalRow]>()
            let readiness = TestStreamSource<AccountDiscoveryReadiness>()
            let query = Self.query(
                reader: ControlledAccountReader(source: rows),
                readiness: readiness
            )
            var iterator = query.watchAuthorizedAccounts(
                environment: Self.environment,
                principalId: Self.principalId
            ).makeAsyncIterator()
            _ = try await iterator.next()
            readiness.yield(.freshComplete)
            rows.yield([Self.row(membership: "m-a", account: "account-a", name: "Aster")])
            let cached = try await Self.nextSnapshot(&iterator, quality: .ready)
            rows.fail(TestProviderFailure.secretProviderFailure)
            #expect(try await iterator.next()
                == .failed(failure: .retryable, cached: cached))
            #expect(try await iterator.next() == nil)
        }

        do {
            let rows = TestStreamSource<[AccountDiscoveryLocalRow]>()
            let readiness = TestStreamSource<AccountDiscoveryReadiness>()
            let query = Self.query(
                reader: ControlledAccountReader(source: rows),
                readiness: readiness
            )
            var iterator = query.watchAuthorizedAccounts(
                environment: Self.environment,
                principalId: Self.principalId
            ).makeAsyncIterator()
            _ = try await iterator.next()
            readiness.finish()
            #expect(try await iterator.next()
                == .failed(failure: .retryable, cached: nil))
            #expect(try await iterator.next() == nil)
        }
    }

    @Test("Encrypted cache survives close and reopens partial until fresh evidence")
    func encryptedOfflineRestartPreservesRowsWithoutFreshness() async throws {
        let fixture = try AccountDatabaseFixture()
        let database = try fixture.open()
        try await Self.insertPrincipal(database, id: Self.principalId.rawValue)
        try await Self.insertAccount(database, id: "account-a", name: "Aster")
        try await Self.insertMembership(
            database,
            id: "m-a",
            accountId: "account-a",
            principalId: Self.principalId.rawValue,
            state: "active"
        )
        let firstReadiness = TestStreamSource<AccountDiscoveryReadiness>()
        firstReadiness.yield(.freshComplete)
        let firstRuntime = LedgerPrincipalOfflineRuntime(
            database: database,
            environment: Self.environment,
            principalId: Self.principalId,
            readinessObservation: { firstReadiness.stream },
            now: { Self.observedAt }
        )
        let pendingBeforeDiscovery = try await firstRuntime.pendingUploadCount()
        let first = try await Self.firstSnapshot(
            firstRuntime.watchAuthorizedAccounts(
                environment: Self.environment,
                principalId: Self.principalId
            ),
            quality: .ready
        )
        #expect(first.accounts.map(\.id.rawValue) == ["account-a"])
        #expect(!((try await firstRuntime.encryptionCipher()).isEmpty))
        #expect(try await firstRuntime.pendingUploadCount() == pendingBeforeDiscovery)
        try await firstRuntime.close()

        let reopenedDatabase = try fixture.open()
        let reopenedReadiness = TestStreamSource<AccountDiscoveryReadiness>()
        let reopenedRuntime = LedgerPrincipalOfflineRuntime(
            database: reopenedDatabase,
            environment: Self.environment,
            principalId: Self.principalId,
            readinessObservation: { reopenedReadiness.stream },
            now: { Self.observedAt }
        )
        var iterator = reopenedRuntime.watchAuthorizedAccounts(
            environment: Self.environment,
            principalId: Self.principalId
        ).makeAsyncIterator()
        #expect(try await iterator.next() == .waiting(.loading))
        let cached = try Self.requireSnapshot(try await iterator.next())
        #expect(cached.accounts == first.accounts)
        #expect(cached.quality == .partial)
        #expect(!cached.isComplete)

        reopenedReadiness.yield(.freshComplete)
        let refreshed = try Self.requireSnapshot(try await iterator.next())
        #expect(refreshed.quality == .ready)
        #expect(refreshed.accounts == first.accounts)
        #expect(try await reopenedRuntime.pendingUploadCount() == pendingBeforeDiscovery)

        try await reopenedRuntime.close()
        fixture.removeDirectory()
    }

    @Test("Consumer cancellation terminates database and readiness observations")
    func cancellationStopsBothSources() async throws {
        let rows = TestStreamSource<[AccountDiscoveryLocalRow]>()
        let readiness = TestStreamSource<AccountDiscoveryReadiness>()
        let query = Self.query(
            reader: ControlledAccountReader(source: rows),
            readiness: readiness
        )
        let consumer = Task {
            for try await _ in query.watchAuthorizedAccounts(
                environment: Self.environment,
                principalId: Self.principalId
            ) {
                try Task.checkCancellation()
            }
        }
        await Task.yield()
        consumer.cancel()
        _ = try? await consumer.value

        for _ in 0..<100 where rows.terminationCount == 0 || readiness.terminationCount == 0 {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(rows.terminationCount == 1)
        #expect(readiness.terminationCount == 1)
    }

    @Test("Bootstrap filesystem namespaces cannot be traversed by valid identifiers")
    func bootstrapNamespaceIsPathSafe() throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-bootstrap-root", isDirectory: true)
        let adversarialPrincipal = try PrincipalID(validating: "..")
        let directory = try LedgerPrincipalPowerSyncLocalBootstrap.bootstrapDirectory(
            applicationSupport: applicationSupport,
            localDataNamespacePrefix: "apps.nine4.ledger.target",
            environment: .targetLocal,
            principalId: adversarialPrincipal
        )
        #expect(directory.lastPathComponent == "bootstrap")
        #expect(directory.deletingLastPathComponent().lastPathComponent.hasPrefix("principal-"))
        #expect(directory.deletingLastPathComponent().lastPathComponent != "..")
        #expect(directory.standardizedFileURL.path.hasPrefix(
            applicationSupport.standardizedFileURL.path + "/"
        ))
        let distinctDirectory = try LedgerPrincipalPowerSyncLocalBootstrap.bootstrapDirectory(
            applicationSupport: applicationSupport,
            localDataNamespacePrefix: "apps.nine4.ledger.target",
            environment: .targetLocal,
            principalId: Self.principalId
        )
        #expect(directory != distinctDirectory)

        #expect(throws: LedgerPrincipalOfflineRuntimeFailure.invalidLocalDataNamespace) {
            try LedgerPrincipalPowerSyncLocalBootstrap.bootstrapDirectory(
                applicationSupport: applicationSupport,
                localDataNamespacePrefix: "../escaped",
                environment: .targetLocal,
                principalId: Self.principalId
            )
        }
    }

    private static func query(
        reader: ControlledAccountReader,
        readiness: TestStreamSource<AccountDiscoveryReadiness>
    ) -> AccountDiscoveryPowerSyncQuery {
        AccountDiscoveryPowerSyncQuery(
            localReader: reader,
            environment: environment,
            principalId: principalId,
            readinessObservation: { readiness.stream },
            now: { observedAt }
        )
    }

    private static func snapshot(
        rows: [AccountDiscoveryLocalRow],
        readiness readinessValue: AccountDiscoveryReadiness,
        expectedQuality: ListSnapshotQuality? = .ready
    ) async throws -> AuthorizedAccountListSnapshot {
        let rowSource = TestStreamSource<[AccountDiscoveryLocalRow]>()
        let readiness = TestStreamSource<AccountDiscoveryReadiness>()
        readiness.yield(readinessValue)
        rowSource.yield(rows)
        let query = Self.query(
            reader: ControlledAccountReader(source: rowSource),
            readiness: readiness
        )
        let result = try await firstSnapshot(
            query.watchAuthorizedAccounts(
                environment: environment,
                principalId: principalId
            ),
            quality: expectedQuality
        )
        rowSource.finish()
        readiness.finish()
        return result
    }

    private static func firstSnapshot(
        _ stream: AsyncThrowingStream<AuthorizedAccountDiscoveryUpdate, Error>,
        quality: ListSnapshotQuality?
    ) async throws -> AuthorizedAccountListSnapshot {
        var iterator = stream.makeAsyncIterator()
        return try await nextSnapshot(&iterator, quality: quality)
    }

    private static func nextSnapshot(
        _ iterator: inout AsyncThrowingStream<AuthorizedAccountDiscoveryUpdate, Error>
            .AsyncIterator,
        quality: ListSnapshotQuality?
    ) async throws -> AuthorizedAccountListSnapshot {
        while let update = try await iterator.next() {
            if case .snapshot(let snapshot) = update,
               quality == nil || snapshot.quality == quality {
                return snapshot
            }
            if case .failed = update {
                Issue.record("Expected Account discovery snapshot before failure")
                throw TestProviderFailure.unexpectedUpdate
            }
        }
        throw TestProviderFailure.unexpectedUpdate
    }

    private static func requireSnapshot(
        _ update: AuthorizedAccountDiscoveryUpdate?
    ) throws -> AuthorizedAccountListSnapshot {
        guard case .snapshot(let snapshot) = update else {
            Issue.record("Expected Account discovery snapshot")
            throw TestProviderFailure.unexpectedUpdate
        }
        return snapshot
    }

    private static func sentinel(
        principalPresent: Bool = true,
        rawCount: Int64
    ) -> AccountDiscoveryLocalRow {
        AccountDiscoveryLocalRow(
            principalIsPresent: principalPresent,
            rawActiveMembershipCount: rawCount,
            membershipId: nil,
            membershipAccountId: nil,
            joinedAccountId: nil,
            displayName: nil
        )
    }

    private static func row(
        membership: String,
        account: String,
        joinedAccount: String? = nil,
        name: String?,
        rawCount: Int64 = 1
    ) -> AccountDiscoveryLocalRow {
        AccountDiscoveryLocalRow(
            principalIsPresent: true,
            rawActiveMembershipCount: rawCount,
            membershipId: membership,
            membershipAccountId: account,
            joinedAccountId: joinedAccount ?? account,
            displayName: name
        )
    }

    private static func insertPrincipal(
        _ database: any PowerSyncDatabaseProtocol,
        id: String
    ) async throws {
        _ = try await database.execute(
            sql: "INSERT INTO spike_principals (id, auth_user_id) VALUES (?, ?)",
            parameters: [id, "auth-\(id)"]
        )
    }

    private static func insertAccount(
        _ database: any PowerSyncDatabaseProtocol,
        id: String,
        name: String
    ) async throws {
        _ = try await database.execute(
            sql: "INSERT INTO spike_accounts (id, display_name) VALUES (?, ?)",
            parameters: [id, name]
        )
    }

    private static func insertMembership(
        _ database: any PowerSyncDatabaseProtocol,
        id: String,
        accountId: String,
        principalId: String,
        state: String
    ) async throws {
        _ = try await database.execute(
            sql: """
            INSERT INTO spike_account_memberships (
              id, account_id, principal_id, role, state,
              can_manage_clients, can_manage_projects,
              can_manage_project_budgets, financial_access
            ) VALUES (?, ?, ?, 'owner', ?, 1, 1, 1, 'full')
            """,
            parameters: [id, accountId, principalId, state]
        )
    }
}

private enum TestProviderFailure: Error {
    case secretProviderFailure
    case unexpectedUpdate
}

private extension AccountDiscoveryReadiness {
    static let freshComplete = Self(
        relationshipsAreComplete: true,
        freshness: .fresh
    )
    static let staleComplete = Self(
        relationshipsAreComplete: true,
        freshness: .stale
    )
}

private extension AsyncThrowingStream where Element == AuthorizedAccountDiscoveryUpdate {
    func firstUpdate() async throws -> AuthorizedAccountDiscoveryUpdate? {
        var iterator = makeAsyncIterator()
        return try await iterator.next()
    }
}

private final class TestStreamSource<Element: Sendable>: @unchecked Sendable {
    let stream: AsyncThrowingStream<Element, Error>
    private let continuation: AsyncThrowingStream<Element, Error>.Continuation
    private let lock = NSLock()
    private var _terminationCount = 0

    init() {
        var captured: AsyncThrowingStream<Element, Error>.Continuation?
        stream = AsyncThrowingStream { captured = $0 }
        continuation = captured!
        continuation.onTermination = { [weak self] _ in
            self?.lock.withLock { self?._terminationCount += 1 }
        }
    }

    var terminationCount: Int {
        lock.withLock { _terminationCount }
    }

    func yield(_ element: Element) {
        continuation.yield(element)
    }

    func finish() {
        continuation.finish()
    }

    func fail(_ error: Error) {
        continuation.finish(throwing: error)
    }
}

private final class ControlledAccountReader: AccountDiscoveryLocalReading, @unchecked Sendable {
    private let source: TestStreamSource<[AccountDiscoveryLocalRow]>
    private let lock = NSLock()
    private var _accessCount = 0

    init(source: TestStreamSource<[AccountDiscoveryLocalRow]>) {
        self.source = source
    }

    var accessCount: Int {
        lock.withLock { _accessCount }
    }

    func watchRows(
        principalId _: PrincipalID
    ) throws -> AsyncThrowingStream<[AccountDiscoveryLocalRow], Error> {
        lock.withLock { _accessCount += 1 }
        return source.stream
    }
}

private final class AccountDatabaseFixture: @unchecked Sendable {
    let directoryURL: URL
    let databaseURL: URL
    private let key: LedgerPowerSyncEncryptionKey

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ledger-account-discovery-\(UUID().uuidString)",
            isDirectory: true
        )
        databaseURL = directoryURL.appendingPathComponent("ledger.sqlite")
        key = try LedgerPowerSyncEncryptionKey(
            hexadecimal: String(repeating: "5e", count: 32)
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    func open() throws -> any PowerSyncDatabaseProtocol {
        try LedgerPowerSyncDatabaseFactory.open(
            absolutePath: databaseURL.path,
            encryptionKey: key
        )
    }

    func removeDirectory() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
