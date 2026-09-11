import Foundation
import LedgerTargetCore
import PowerSync
import Testing
@testable import LedgerTargetPowerSync

@Suite("Transfer destination PowerSync derived query")
struct TransferDestinationSelectionPowerSyncQueryTests {
    @Test("Encrypted local Project directory drives the derived query without a second read")
    func encryptedDirectoryIntegration() async throws {
        let fixture = try TransferDestinationDatabaseFixture()
        let database = try fixture.open()
        try await Self.insertMembership(database)
        try await Self.insertClient(database, id: "client-current", name: "Current Client")
        try await Self.insertClient(database, id: "client-stale", name: "Stale Client")
        try await Self.insertProject(
            database, id: "source", clientId: "client-current",
            name: "Source Current", lifecycle: "active"
        )
        try await Self.insertProject(
            database, id: "destination-a", clientId: "client-current",
            name: "Same Name", lifecycle: "active"
        )
        try await Self.insertProject(
            database, id: "destination-b", clientId: "client-current",
            name: "Same Name", lifecycle: "active"
        )
        try await Self.insertProject(
            database, id: "destination-archived", clientId: "client-current",
            name: "Archived", lifecycle: "archived"
        )
        try await Self.insertProject(
            database, id: "stale-match", clientId: "client-stale",
            name: "Wrong Client", lifecycle: "active"
        )

        let cipher: String = try await database.get("PRAGMA cipher") {
            try $0.getString(index: 0)
        }
        #expect(!cipher.isEmpty)

        let directory = ClientProjectDirectoryPowerSyncQuery(
            database: database,
            principalId: Self.principalId,
            accountId: Self.accountId,
            completenessObservation: { _, _ in
                AsyncStream { continuation in
                    continuation.yield(true)
                    continuation.finish()
                }
            },
            now: { Self.observedAt }
        )
        let query = TransferDestinationSelectionPowerSyncQuery(
            directoryQuery: directory,
            accountId: Self.accountId
        )
        let staleCaller = try Self.project(
            "source", clientId: "client-stale", name: "Caller Stale",
            lifecycle: .archived
        )
        var iterator = query.watchTransferDestinations(
            source: staleCaller
        ).makeAsyncIterator()
        let snapshot = try #require(try await iterator.next())

        #expect(snapshot.source.clientId.rawValue == "client-current")
        #expect(snapshot.source.displayName.rawValue == "Source Current")
        #expect(snapshot.source.lifecycle == .active)
        #expect(snapshot.candidates.map(\.destination.id.rawValue) == [
            "destination-a", "destination-b"
        ])
        #expect(snapshot.isCompleteForSelection)
        #expect(snapshot.quality == .ready)

        await query.cancelAndDrainWatches()
        await directory.cancelAndDrainWatches()
        try await database.close(deleteDatabase: true)
        fixture.remove()
    }

    @Test("Retained encrypted rows remain incomplete after restart until fresh Project proof")
    func encryptedRestartRequiresCurrentProcessCompleteness() async throws {
        let fixture = try TransferDestinationDatabaseFixture()
        let initialDatabase = try fixture.open()
        try await Self.insertMembership(initialDatabase)
        try await Self.insertClient(
            initialDatabase, id: "client-current", name: "Current Client"
        )
        try await Self.insertProject(
            initialDatabase, id: "source", clientId: "client-current",
            name: "Source", lifecycle: "active"
        )
        try await Self.insertProject(
            initialDatabase, id: "destination", clientId: "client-current",
            name: "Destination", lifecycle: "active"
        )
        try await initialDatabase.close(deleteDatabase: false)

        let reopenedDatabase = try fixture.open()
        let projectProof = AsyncStream<Bool>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let directory = ClientProjectDirectoryPowerSyncQuery(
            database: reopenedDatabase,
            principalId: Self.principalId,
            accountId: Self.accountId,
            completenessObservation: { stream, _ in
                switch stream {
                case .clients:
                    AsyncStream { $0.finish() }
                case .projects:
                    projectProof.stream
                }
            },
            now: { Self.observedAt }
        )
        let query = TransferDestinationSelectionPowerSyncQuery(
            directoryQuery: directory,
            accountId: Self.accountId
        )
        var iterator = query.watchTransferDestinations(
            source: try Self.project(
                "source", clientId: "client-current", name: "Caller Copy"
            )
        ).makeAsyncIterator()

        let retained = try #require(try await iterator.next())
        #expect(retained.source.displayName.rawValue == "Source")
        #expect(retained.candidates.map(\.destination.id.rawValue) == ["destination"])
        #expect(retained.quality == .partial || retained.quality == .stale)
        #expect(!retained.isCompleteForSelection)

        projectProof.continuation.yield(true)
        let currentProcessReady = try #require(try await iterator.next())
        #expect(currentProcessReady.candidates.map(\.destination.id.rawValue) == [
            "destination"
        ])
        #expect(currentProcessReady.quality == .ready)
        #expect(currentProcessReady.isCompleteForSelection)

        _ = try await reopenedDatabase.execute(
            sql: "DELETE FROM spike_projects WHERE id = ?",
            parameters: ["destination"]
        )
        projectProof.continuation.finish()
        await query.cancelAndDrainWatches()
        await directory.cancelAndDrainWatches()
        try await reopenedDatabase.close(deleteDatabase: false)

        let emptyReopenDatabase = try fixture.open()
        let emptyProjectProof = AsyncStream<Bool>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let emptyDirectory = ClientProjectDirectoryPowerSyncQuery(
            database: emptyReopenDatabase,
            principalId: Self.principalId,
            accountId: Self.accountId,
            completenessObservation: { stream, _ in
                switch stream {
                case .clients:
                    AsyncStream { $0.finish() }
                case .projects:
                    emptyProjectProof.stream
                }
            },
            now: { Self.observedAt }
        )
        let emptyQuery = TransferDestinationSelectionPowerSyncQuery(
            directoryQuery: emptyDirectory,
            accountId: Self.accountId
        )
        var emptyIterator = emptyQuery.watchTransferDestinations(
            source: try Self.project(
                "source", clientId: "client-current", name: "Caller Copy"
            )
        ).makeAsyncIterator()
        let retainedEmpty = try #require(try await emptyIterator.next())
        #expect(retainedEmpty.candidates.isEmpty)
        #expect(retainedEmpty.availability == .directoryIncomplete)
        #expect(!retainedEmpty.isCompleteForSelection)

        emptyProjectProof.continuation.yield(true)
        let authoritativeEmpty = try #require(try await emptyIterator.next())
        #expect(authoritativeEmpty.candidates.isEmpty)
        #expect(authoritativeEmpty.availability == .noEligibleDestination)
        #expect(authoritativeEmpty.isCompleteForSelection)

        emptyProjectProof.continuation.finish()
        await emptyQuery.cancelAndDrainWatches()
        await emptyDirectory.cancelAndDrainWatches()
        try await emptyReopenDatabase.close(deleteDatabase: true)
        fixture.remove()
    }

    @Test("Current directory source controls filtering, order, routes, and archived-source reads")
    func currentSourceControlsProjection() async throws {
        let upstream = ControlledProjectDirectoryQuery()
        let query = TransferDestinationSelectionPowerSyncQuery(
            directoryQuery: upstream,
            accountId: Self.accountId
        )
        let caller = try Self.project(
            "source", clientId: "client-stale", name: "Caller Stale",
            lifecycle: .active
        )
        let current = try Self.project(
            "source", clientId: "client-a", name: "Current Source",
            lifecycle: .archived
        )
        let first = try Self.project("destination-b", clientId: "client-a", name: "Same")
        let second = try Self.project("destination-a", clientId: "client-a", name: "Same")
        let archived = try Self.project(
            "destination-archived", clientId: "client-a", name: "Archived",
            lifecycle: .archived
        )
        let otherClient = try Self.project(
            "destination-other", clientId: "client-other", name: "Other"
        )

        var iterator = query.watchTransferDestinations(source: caller).makeAsyncIterator()
        upstream.yield(try Self.directory(
            rows: [first, current, archived, otherClient, second],
            quality: .ready,
            complete: true,
            marker: "a"
        ))
        let snapshot = try #require(try await iterator.next())

        #expect(upstream.requestedAccounts == [Self.accountId])
        #expect(snapshot.source == current)
        #expect(snapshot.source.lifecycle == .archived)
        #expect(snapshot.candidates.map(\.destination.id.rawValue) == [
            "destination-b", "destination-a"
        ])
        #expect(snapshot.candidates.map(\.destination.displayName.rawValue) == ["Same", "Same"])
        #expect(snapshot.candidates.allSatisfy {
            $0.route.source.clientId == current.clientId
                && $0.route.source.projectId == current.id
                && $0.route.destination.projectId == $0.destination.id
        })
        #expect(snapshot.availability == .available)
        #expect(snapshot.isCompleteForSelection)
        await query.cancelAndDrainWatches()
    }

    @Test("Incomplete absence never filters by stale caller and current relationships replace it")
    func sourceAbsenceAndRelationshipChanges() async throws {
        let upstream = ControlledProjectDirectoryQuery()
        let query = TransferDestinationSelectionPowerSyncQuery(
            directoryQuery: upstream,
            accountId: Self.accountId
        )
        let caller = try Self.project(
            "source", clientId: "client-stale", name: "Caller Stale"
        )
        let staleMatch = try Self.project(
            "must-not-leak", clientId: "client-stale", name: "Must Not Leak"
        )
        let sourceA = try Self.project("source", clientId: "client-a", name: "Source A")
        let destinationA = try Self.project(
            "destination", clientId: "client-a", name: "Destination A"
        )
        let sourceB = try Self.project("source", clientId: "client-b", name: "Source B")
        let destinationB = try Self.project(
            "destination", clientId: "client-b", name: "Destination B"
        )

        var iterator = query.watchTransferDestinations(source: caller).makeAsyncIterator()

        let absent = try Self.directory(
            rows: [staleMatch], quality: .partial, complete: false, marker: "b"
        )
        upstream.yield(absent)
        let incomplete = try #require(try await iterator.next())
        #expect(incomplete.candidates.isEmpty)
        #expect(incomplete.availability == .directoryIncomplete)
        #expect(!incomplete.isCompleteForSelection)
        #expect(incomplete.quality == .partial)
        #expect(incomplete.sourceDirectoryFingerprint == absent.local.queryFingerprint)
        #expect(incomplete.localDataVersion == absent.local.localDataVersion)
        #expect(incomplete.asOf == absent.local.asOf)
        #expect(incomplete.visibleProjectCountBeforeFiltering == 1)

        upstream.yield(try Self.directory(
            rows: [sourceA, destinationA], quality: .stale,
            complete: false, marker: "c"
        ))
        let staleA = try #require(try await iterator.next())
        #expect(staleA.source == sourceA)
        #expect(staleA.candidates.map(\.destination.id.rawValue) == ["destination"])
        #expect(staleA.quality == .stale)

        upstream.yield(try Self.directory(
            rows: [destinationA], quality: .stale,
            complete: false, marker: "d"
        ))
        let disappeared = try #require(try await iterator.next())
        #expect(disappeared.candidates.isEmpty)
        #expect(disappeared.availability == .directoryIncomplete)

        upstream.yield(try Self.directory(
            rows: [sourceB, destinationB], quality: .ready,
            complete: true, marker: "e"
        ))
        let reassigned = try #require(try await iterator.next())
        #expect(reassigned.source == sourceB)
        #expect(reassigned.candidates.map(\.destination.displayName.rawValue) == [
            "Destination B"
        ])
        #expect(reassigned.candidates.allSatisfy { $0.destination.clientId == sourceB.clientId })
        #expect(reassigned.quality == .ready)
        #expect(reassigned.isCompleteForSelection)

        upstream.yield(try Self.directory(
            rows: [sourceB], quality: .ready, complete: true, marker: "f"
        ))
        let empty = try #require(try await iterator.next())
        #expect(empty.availability == .noEligibleDestination)
        #expect(empty.candidates.isEmpty)
        #expect(empty.isCompleteForSelection)
        await query.cancelAndDrainWatches()
    }

    @Test("Scope, complete absence, upstream failure, cancellation, and close fail boundedly")
    func boundedFailureAndDrainage() async throws {
        let wrongUpstream = ControlledProjectDirectoryQuery()
        let wrongQuery = TransferDestinationSelectionPowerSyncQuery(
            directoryQuery: wrongUpstream,
            accountId: Self.accountId
        )
        let wrongSource = try Self.project(
            "wrong", accountId: AccountID(validating: "account-other"),
            clientId: "client-other", name: "Wrong"
        )
        do {
            var iterator = wrongQuery.watchTransferDestinations(
                source: wrongSource
            ).makeAsyncIterator()
            _ = try await iterator.next()
            Issue.record("Expected Account mismatch")
        } catch let failure as TransferDestinationSelectionFailure {
            #expect(failure == .sourceDirectoryAccountMismatch)
        }
        #expect(wrongUpstream.requestedAccounts.isEmpty)

        let absentUpstream = ControlledProjectDirectoryQuery()
        let absentQuery = TransferDestinationSelectionPowerSyncQuery(
            directoryQuery: absentUpstream,
            accountId: Self.accountId
        )
        var absentIterator = absentQuery.watchTransferDestinations(
            source: try Self.project("source", clientId: "client-a", name: "Source")
        ).makeAsyncIterator()
        absentUpstream.yield(try Self.directory(
            rows: [], quality: .ready, complete: true, marker: "1"
        ))
        do {
            _ = try await absentIterator.next()
            Issue.record("Expected source-unavailable failure")
        } catch let failure as TransferDestinationSelectionPowerSyncFailure {
            #expect(failure == .sourceUnavailable)
            #expect(failure.diagnosticCode == "transfer_destination_source_unavailable")
        }

        let failedUpstream = ControlledProjectDirectoryQuery()
        let failedQuery = TransferDestinationSelectionPowerSyncQuery(
            directoryQuery: failedUpstream,
            accountId: Self.accountId
        )
        var failedIterator = failedQuery.watchTransferDestinations(
            source: try Self.project("source", clientId: "client-a", name: "Source")
        ).makeAsyncIterator()
        failedUpstream.finish(throwing: ControlledDirectoryFailure.failed)
        do {
            _ = try await failedIterator.next()
            Issue.record("Expected upstream failure")
        } catch let failure as ControlledDirectoryFailure {
            #expect(failure == .failed)
        }

        let drainingUpstream = ControlledProjectDirectoryQuery()
        let drainingQuery = TransferDestinationSelectionPowerSyncQuery(
            directoryQuery: drainingUpstream,
            accountId: Self.accountId
        )
        let source = try Self.project("source", clientId: "client-a", name: "Source")
        let consumer = Task {
            var iterator = drainingQuery.watchTransferDestinations(
                source: source
            ).makeAsyncIterator()
            while try await iterator.next() != nil {}
        }
        await Self.wait { drainingUpstream.requestedAccounts.count == 1 }
        await drainingQuery.cancelAndDrainWatches()
        _ = await consumer.result
        await Self.wait { drainingUpstream.terminationCount == 1 }

        var refused = drainingQuery.watchTransferDestinations(
            source: source
        ).makeAsyncIterator()
        #expect(try await refused.next() == nil)
        #expect(drainingUpstream.requestedAccounts.count == 1)
    }

    @Test("Cancelling a destination consumer drains the derived and upstream watches")
    func consumerCancellationDrainsUpstream() async throws {
        let upstream = ControlledProjectDirectoryQuery()
        let query = TransferDestinationSelectionPowerSyncQuery(
            directoryQuery: upstream,
            accountId: Self.accountId
        )
        let source = try Self.project(
            "source", clientId: "client-a", name: "Source"
        )
        let consumer = Task {
            do {
                var iterator = query.watchTransferDestinations(
                    source: source
                ).makeAsyncIterator()
                while try await iterator.next() != nil {}
            } catch is CancellationError {
                // Expected consumer-driven termination.
            } catch {
                Issue.record("Unexpected cancellation failure: \(error)")
            }
        }
        await Self.wait { upstream.requestedAccounts == [Self.accountId] }

        consumer.cancel()
        await consumer.value
        await Self.wait { upstream.terminationCount == 1 }
        await query.cancelAndDrainWatches()

        #expect(upstream.requestedAccounts == [Self.accountId])
        #expect(upstream.terminationCount == 1)
    }

    private static let accountId = try! AccountID(validating: "account-transfer")
    private static let principalId = try! PrincipalID(validating: "principal-transfer")
    private static let observedAt = Date(timeIntervalSince1970: 1_788_600_000)

    private static func project(
        _ id: String,
        accountId: AccountID = accountId,
        clientId: String,
        name: String,
        lifecycle: DirectoryLifecycleState = .active
    ) throws -> ProjectSummary {
        let clientID = try ClientID(validating: clientId)
        let client = try ClientSummary(
            id: clientID,
            accountId: accountId,
            displayName: ClientDisplayName(validating: "Client \(clientId)"),
            lifecycle: .active,
            createdAt: observedAt,
            updatedAt: observedAt
        )
        return try ProjectSummary(
            id: ProjectID(validating: id),
            accountId: accountId,
            clientId: clientID,
            client: client,
            displayName: ProjectDisplayName(validating: name),
            description: nil,
            lifecycle: lifecycle
        )
    }

    private static func directory(
        rows: [ProjectSummary],
        quality: ListSnapshotQuality,
        complete: Bool,
        marker: Character
    ) throws -> ProjectListSnapshot {
        try ProjectListSnapshot(
            accountId: accountId,
            local: ListLocalSnapshot(
                queryFingerprint: ListQueryFingerprint(
                    validating: String(repeating: marker, count: 64)
                ),
                rows: rows,
                visibleRowCountBeforeFiltering: rows.count,
                isCompleteForQuery: complete,
                quality: quality,
                localDataVersion: LocalDataVersion(
                    validating: "transfer-provider-\(marker)"
                ),
                asOf: observedAt.addingTimeInterval(
                    TimeInterval(marker.asciiValue ?? 0)
                )
            )
        )
    }

    private static func wait(
        _ condition: @escaping @Sendable () -> Bool
    ) async {
        for _ in 0..<2_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Timed out waiting for derived query state")
    }

    private static func insertMembership(
        _ database: any PowerSyncDatabaseProtocol
    ) async throws {
        _ = try await database.execute(
            sql: """
            INSERT INTO spike_account_memberships (
              id, account_id, principal_id, role, state,
              can_manage_clients, can_manage_projects,
              can_manage_project_budgets, financial_access
            ) VALUES (?, ?, ?, 'owner', 'active', 1, 1, 1, 'full')
            """,
            parameters: ["membership-transfer", accountId.rawValue, principalId.rawValue]
        )
    }

    private static func insertClient(
        _ database: any PowerSyncDatabaseProtocol,
        id: String,
        name: String
    ) async throws {
        _ = try await database.execute(
            sql: """
            INSERT INTO spike_clients (
              id, account_id, display_name, lifecycle, revision,
              created_at_ms, updated_at_ms, created_by_principal_id
            ) VALUES (?, ?, ?, 'active', 1, 1788500000000, 1788500001000, ?)
            """,
            parameters: [id, accountId.rawValue, name, principalId.rawValue]
        )
    }

    private static func insertProject(
        _ database: any PowerSyncDatabaseProtocol,
        id: String,
        clientId: String,
        name: String,
        lifecycle: String
    ) async throws {
        _ = try await database.execute(
            sql: """
            INSERT INTO spike_projects (
              id, account_id, client_id, display_name, description, lifecycle,
              revision, created_at_ms, updated_at_ms, created_by_principal_id
            ) VALUES (?, ?, ?, ?, NULL, ?, 1, 1788500000000, 1788500001000, ?)
            """,
            parameters: [
                id, accountId.rawValue, clientId, name, lifecycle, principalId.rawValue
            ]
        )
    }
}

private final class TransferDestinationDatabaseFixture: @unchecked Sendable {
    private let root: URL
    private let databaseURL: URL
    private let key: LedgerPowerSyncEncryptionKey

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ledger-transfer-destination-\(UUID().uuidString)",
            isDirectory: true
        )
        databaseURL = root.appendingPathComponent("ledger.sqlite")
        key = try LedgerPowerSyncEncryptionKey(
            hexadecimal: String(repeating: "6a", count: 32)
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
    }

    func open() throws -> any PowerSyncDatabaseProtocol {
        try LedgerPowerSyncDatabaseFactory.open(
            absolutePath: databaseURL.path,
            encryptionKey: key
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private enum ControlledDirectoryFailure: Error, Equatable, Sendable {
    case failed
}

private final class ControlledProjectDirectoryQuery:
    ClientProjectDirectoryQuerying, @unchecked Sendable
{
    private let lock = NSLock()
    private let stream: AsyncThrowingStream<ProjectListSnapshot, Error>
    private let continuation: AsyncThrowingStream<ProjectListSnapshot, Error>.Continuation
    private var accounts: [AccountID] = []
    private var terminations = 0

    init() {
        var captured: AsyncThrowingStream<ProjectListSnapshot, Error>.Continuation!
        stream = AsyncThrowingStream { value in captured = value }
        continuation = captured
        continuation.onTermination = { [weak self] _ in
            self?.lock.withLock { self?.terminations += 1 }
        }
    }

    var requestedAccounts: [AccountID] {
        lock.withLock { accounts }
    }

    var terminationCount: Int {
        lock.withLock { terminations }
    }

    func watchClients(
        accountId: AccountID
    ) -> AsyncThrowingStream<ClientListSnapshot, Error> {
        AsyncThrowingStream { $0.finish(throwing: ControlledDirectoryFailure.failed) }
    }

    func watchProjects(
        accountId: AccountID
    ) -> AsyncThrowingStream<ProjectListSnapshot, Error> {
        lock.withLock { accounts.append(accountId) }
        return stream
    }

    func yield(_ snapshot: ProjectListSnapshot) {
        continuation.yield(snapshot)
    }

    func finish(throwing error: Error) {
        continuation.finish(throwing: error)
    }
}
