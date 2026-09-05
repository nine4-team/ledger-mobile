import Foundation
import LedgerTargetCore
import PowerSync
import Testing
@testable import LedgerTargetPowerSync

@Suite("Budget category PowerSync reference query", .serialized)
struct BudgetCategoryReferencePowerSyncQueryTests {
    @Test("Materialized categories preserve every literal field in canonical order")
    func materializedCategoriesPreserveLiteralFields() async throws {
        let fixture = try BudgetCategoryDatabaseFixture()
        let database = try fixture.open()
        try await Self.insertActiveMembership(database)
        try await Self.insertCategory(
            database,
            id: "category-fee",
            name: "Design Fee",
            kind: "fee",
            lifecycle: "archived",
            isSystem: 1,
            excludesFromOverallBudget: 1,
            order: 30,
            revision: 7,
            visibilityClass: "restricted"
        )
        try await Self.insertCategory(
            database,
            id: "category-general",
            name: "General",
            kind: "general",
            lifecycle: "active",
            isSystem: 0,
            excludesFromOverallBudget: 0,
            order: 10,
            revision: 2,
            visibilityClass: "ordinary"
        )
        try await Self.insertCategory(
            database,
            id: "category-itemized",
            name: "Furnishings",
            kind: "itemized",
            lifecycle: "active",
            isSystem: 0,
            excludesFromOverallBudget: 1,
            order: 20,
            revision: 4,
            visibilityClass: "restricted"
        )

        let snapshot = try await Self.firstSnapshot(
            query: Self.query(database, complete: true)
        )

        #expect(snapshot.accountId == Self.accountId)
        #expect(snapshot.local.quality == .ready)
        #expect(snapshot.local.isCompleteForQuery)
        #expect(snapshot.local.visibleRowCountBeforeFiltering == 3)
        #expect(snapshot.local.rows.map(\.id.rawValue) == [
            "category-general", "category-itemized", "category-fee"
        ])
        #expect(snapshot.local.rows.map(\.name.rawValue) == [
            "General", "Furnishings", "Design Fee"
        ])
        #expect(snapshot.local.rows.map(\.kind) == [.general, .itemized, .fee])
        #expect(snapshot.local.rows.map(\.lifecycle) == [.active, .active, .archived])
        #expect(snapshot.local.rows.map(\.isSystem) == [false, false, true])
        #expect(snapshot.local.rows.map(\.excludesFromOverallBudget) == [false, true, true])
        #expect(snapshot.local.rows.map(\.presentationOrder) == [10, 20, 30])
        #expect(snapshot.local.rows.map(\.revision) == [2, 4, 7])
        #expect(snapshot.local.asOf == Self.observedAt)

        try await database.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("Completeness is explicit, reactive, and reset by invalidation")
    func completenessIsExplicitAndReactive() async throws {
        let reader = ControlledBudgetCategoryReader(
            initialRows: [Self.sentinel(scope: 1)],
            hasLastSyncedAt: false
        )
        let proof = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
        proof.continuation.yield(false)
        let query = Self.query(reader, completeness: proof.stream)
        var iterator = query.watchBudgetCategories(accountId: Self.accountId).makeAsyncIterator()

        let partial = try #require(try await iterator.next())
        #expect(partial.local.rows.isEmpty)
        #expect(partial.local.quality == .partial)
        #expect(!partial.local.isCompleteForQuery)

        proof.continuation.yield(true)
        let readyEmpty = try #require(try await iterator.next())
        #expect(readyEmpty.local.rows.isEmpty)
        #expect(readyEmpty.local.quality == .ready)
        #expect(readyEmpty.local.isCompleteForQuery)
        #expect(readyEmpty.local.queryFingerprint == partial.local.queryFingerprint)
        #expect(readyEmpty.local.localDataVersion != partial.local.localDataVersion)

        proof.continuation.yield(false)
        let invalidated = try #require(try await iterator.next())
        #expect(invalidated.local.quality == .partial)
        #expect(!invalidated.local.isCompleteForQuery)
        #expect(invalidated.local.localDataVersion == partial.local.localDataVersion)

        proof.continuation.finish()
    }

    @Test("CATPOWER-TEST-002 initial snapshots require both sources in either order")
    func initialSnapshotCombinesBothSourceOrders() throws {
        let rows = [Self.row()]

        var rowsFirst = BudgetCategoryReferenceObservedState()
        let beforeCompleteness = rowsFirst.observe(.rows(rows))
        #expect(beforeCompleteness == nil)
        let rowsFirstCombined = rowsFirst.observe(.completeness(false))
        let rowsFirstEvidence = try #require(rowsFirstCombined)
        #expect(rowsFirstEvidence.rows == rows)
        #expect(!rowsFirstEvidence.completeness)

        var completenessFirst = BudgetCategoryReferenceObservedState()
        let beforeRows = completenessFirst.observe(.completeness(true))
        #expect(beforeRows == nil)
        let completenessFirstCombined = completenessFirst.observe(.rows(rows))
        let completenessFirstEvidence = try #require(completenessFirstCombined)
        #expect(completenessFirstEvidence.rows == rows)
        #expect(completenessFirstEvidence.completeness)
    }

    @Test("Cached local rows are stale, never complete, without explicit proof")
    func cachedRowsAreStaleWithoutCompleteness() async throws {
        let reader = ControlledBudgetCategoryReader(
            initialRows: [Self.row()],
            hasLastSyncedAt: true
        )
        let snapshot = try await Self.firstSnapshot(
            query: Self.query(reader, complete: false)
        )

        #expect(snapshot.local.rows.map(\.id.rawValue) == ["category-primary"])
        #expect(snapshot.local.quality == .stale)
        #expect(!snapshot.local.isCompleteForQuery)
    }

    @Test("The same watch clears categories immediately when membership is lost")
    func membershipLossClearsSameWatch() async throws {
        let reader = ControlledBudgetCategoryReader(
            initialRows: [Self.row()],
            hasLastSyncedAt: true
        )
        let proof = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
        proof.continuation.yield(true)
        let query = Self.query(reader, completeness: proof.stream)
        var iterator = query.watchBudgetCategories(accountId: Self.accountId).makeAsyncIterator()

        var ready = try #require(try await iterator.next())
        while ready.local.quality != .ready {
            ready = try #require(try await iterator.next())
        }
        #expect(ready.local.rows.count == 1)
        #expect(ready.local.quality == .ready)

        reader.yield([Self.sentinel(scope: 0)])
        var revoked = try #require(try await iterator.next())
        while !revoked.local.rows.isEmpty {
            revoked = try #require(try await iterator.next())
        }
        #expect(revoked.local.rows.isEmpty)
        #expect(revoked.local.quality == .partial)
        #expect(!revoked.local.isCompleteForQuery)

        proof.continuation.yield(true)
        let staleProof = try #require(try await iterator.next())
        #expect(staleProof.local.rows.isEmpty)
        #expect(staleProof.local.quality == .partial)
        #expect(!staleProof.local.isCompleteForQuery)

        reader.yield([Self.sentinel(scope: 0)])
        let deleted = try #require(try await iterator.next())
        #expect(deleted.local.rows.isEmpty)
        #expect(deleted.local.quality == .partial)
        #expect(!deleted.local.isCompleteForQuery)

        proof.continuation.finish()
    }

    @Test("Real membership revocation and deletion clear one live SQL watch")
    func realMembershipLossClearsLiveSQLWatch() async throws {
        let fixture = try BudgetCategoryDatabaseFixture()
        let database = try fixture.open()
        try await Self.insertActiveMembership(database)
        try await Self.insertCategory(database)
        let proof = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
        proof.continuation.yield(true)
        let query = BudgetCategoryReferencePowerSyncQuery(
            database: database,
            principalId: Self.principalId,
            accountId: Self.accountId,
            completenessObservation: { _ in proof.stream },
            now: { Self.observedAt }
        )
        var iterator = query.watchBudgetCategories(accountId: Self.accountId).makeAsyncIterator()

        var ready = try #require(try await iterator.next())
        while ready.local.quality != .ready {
            ready = try #require(try await iterator.next())
        }
        #expect(ready.local.rows.map(\.id.rawValue) == ["category-primary"])

        _ = try await database.execute(
            sql: "UPDATE spike_account_memberships SET state = 'revoked' WHERE id = ?",
            parameters: ["membership-primary"]
        )
        var revoked = try #require(try await iterator.next())
        while !revoked.local.rows.isEmpty {
            revoked = try #require(try await iterator.next())
        }
        #expect(revoked.local.quality == .partial)
        #expect(!revoked.local.isCompleteForQuery)

        _ = try await database.execute(
            sql: "DELETE FROM spike_account_memberships WHERE id = ?",
            parameters: ["membership-primary"]
        )
        let deleted = try #require(try await iterator.next())
        #expect(deleted.local.rows.isEmpty)
        #expect(deleted.local.quality == .partial)
        #expect(!deleted.local.isCompleteForQuery)

        proof.continuation.yield(true)
        let staleProof = try #require(try await iterator.next())
        #expect(staleProof.local.rows.isEmpty)
        #expect(staleProof.local.quality == .partial)
        #expect(!staleProof.local.isCompleteForQuery)

        proof.continuation.finish()
        try await database.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("Account mismatch fails before local observation")
    func accountMismatchFailsBeforeObservation() async throws {
        let reader = ControlledBudgetCategoryReader(
            initialRows: [Self.row()],
            hasLastSyncedAt: false
        )
        let query = Self.query(reader, complete: true)
        let otherAccount = try AccountID(validating: "account-other")

        do {
            for try await _ in query.watchBudgetCategories(accountId: otherAccount) {
                Issue.record("Cross-Account query must not emit")
            }
            Issue.record("Expected exact Account binding failure")
        } catch let failure as BudgetCategoryReferenceFailure {
            #expect(failure == .accountScopeMismatch)
        }
        #expect(reader.observationCount == 0)
    }

    @Test("Malformed local evidence fails atomically with bounded errors", arguments: [
        [],
        [Self.sentinel(scope: 2)],
        [Self.sentinel(scope: 0), Self.sentinel(scope: 0)],
        [Self.row(), Self.sentinel(scope: 0)],
        [Self.row(scope: 0)],
        [Self.row(id: "")],
        [Self.row(name: nil)],
        [Self.row(accountId: "account-other")],
        [Self.row(kind: "unknown")],
        [Self.row(lifecycle: "deleted")],
        [Self.row(isSystem: 2)],
        [Self.row(excludesFromOverallBudget: -1)],
        [Self.row(order: -1)],
        [Self.row(order: Int64(UInt32.max) + 1)],
        [Self.row(revision: 0)],
        [Self.row(revision: -1)],
        [Self.row(name: "   ")],
    ])
    func malformedEvidenceFailsAtomically(rows: [BudgetCategoryPowerSyncRow]) async throws {
        let reader = ControlledBudgetCategoryReader(
            initialRows: rows,
            hasLastSyncedAt: false
        )

        do {
            for try await _ in Self.query(reader, complete: true)
                .watchBudgetCategories(accountId: Self.accountId) {
                Issue.record("Malformed evidence must not emit a partial snapshot")
            }
            Issue.record("Expected bounded local-read failure")
        } catch let failure as BudgetCategoryReferenceFailure {
            if rows.first?.displayName == "   " {
                #expect(failure == .invalidName)
            } else {
                #expect(failure == .localReadFailed)
            }
        }
    }

    @Test("Duplicate identity, name, and presentation order remain domain failures")
    func duplicateDefinitionsRemainDomainFailures() async throws {
        let cases: [([BudgetCategoryPowerSyncRow], BudgetCategoryReferenceFailure)] = [
            ([Self.row(), Self.row(name: "Other", order: 2)], .duplicateCategoryIdentity),
            ([Self.row(), Self.row(id: "category-other", name: " general ", order: 2)], .duplicateCategoryName),
            ([Self.row(), Self.row(id: "category-other", name: "Other")], .duplicatePresentationOrder),
        ]

        for (rows, expected) in cases {
            let reader = ControlledBudgetCategoryReader(
                initialRows: rows,
                hasLastSyncedAt: false
            )
            do {
                for try await _ in Self.query(reader, complete: true)
                    .watchBudgetCategories(accountId: Self.accountId) {
                    Issue.record("Duplicate definitions must not emit")
                }
                Issue.record("Expected duplicate-definition failure")
            } catch let failure as BudgetCategoryReferenceFailure {
                #expect(failure == expected)
            }
        }
    }

    @Test("Fingerprint is Account-bound while local version covers every output field")
    func fingerprintAndLocalVersionContract() async throws {
        let reader = ControlledBudgetCategoryReader(
            initialRows: [Self.row()],
            hasLastSyncedAt: false
        )
        let query = Self.query(reader, complete: true)
        var iterator = query.watchBudgetCategories(accountId: Self.accountId).makeAsyncIterator()
        var baseline = try #require(try await iterator.next())
        while baseline.local.quality != .ready {
            baseline = try #require(try await iterator.next())
        }

        let variants = [
            Self.row(id: "category-other"),
            Self.row(name: "Other"),
            Self.row(kind: "itemized"),
            Self.row(kind: "fee"),
            Self.row(lifecycle: "archived"),
            Self.row(isSystem: 1),
            Self.row(excludesFromOverallBudget: 1),
            Self.row(order: 2),
            Self.row(revision: 2),
        ]
        var versions: Set<LocalDataVersion> = [baseline.local.localDataVersion]
        for variant in variants {
            reader.yield([variant])
            let snapshot = try #require(try await iterator.next())
            #expect(snapshot.local.queryFingerprint == baseline.local.queryFingerprint)
            #expect(snapshot.local.localDataVersion != baseline.local.localDataVersion)
            let output = try #require(snapshot.local.rows.first)
            #expect(output.id.rawValue == variant.id)
            #expect(output.accountId.rawValue == variant.accountId)
            #expect(output.name.rawValue == variant.displayName)
            #expect(output.kind.rawValue == variant.kind)
            #expect(output.lifecycle.rawValue == variant.lifecycle)
            #expect(output.isSystem == (variant.isSystem == 1))
            #expect(
                output.excludesFromOverallBudget
                    == (variant.excludesFromOverallBudget == 1)
            )
            #expect(output.presentationOrder == UInt32(try #require(variant.presentationOrder)))
            #expect(output.revision == UInt64(try #require(variant.revision)))
            versions.insert(snapshot.local.localDataVersion)
        }
        #expect(versions.count == variants.count + 1)

        let orderReader = ControlledBudgetCategoryReader(
            initialRows: [
                Self.row(id: "category-b", name: "B", order: 2),
                Self.row(id: "category-a", name: "A", order: 1),
            ],
            hasLastSyncedAt: false
        )
        let orderQuery = Self.query(orderReader, complete: true)
        var orderIterator = orderQuery.watchBudgetCategories(accountId: Self.accountId)
            .makeAsyncIterator()
        var forward = try #require(try await orderIterator.next())
        while forward.local.quality != .ready {
            forward = try #require(try await orderIterator.next())
        }
        orderReader.yield([
            Self.row(id: "category-a", name: "A", order: 1),
            Self.row(id: "category-b", name: "B", order: 2),
        ])
        let reversedInput = try #require(try await orderIterator.next())
        #expect(reversedInput.local.rows == forward.local.rows)
        #expect(reversedInput.local.localDataVersion == forward.local.localDataVersion)

        let otherAccount = try AccountID(validating: "account-other")
        let otherReader = ControlledBudgetCategoryReader(
            initialRows: [Self.row(accountId: otherAccount.rawValue)],
            hasLastSyncedAt: false
        )
        let otherQuery = BudgetCategoryReferencePowerSyncQuery(
            localReader: otherReader,
            principalId: Self.principalId,
            accountId: otherAccount,
            completenessObservation: { _ in Self.fixedStream(true) },
            now: { Self.observedAt }
        )
        var otherIterator = otherQuery.watchBudgetCategories(accountId: otherAccount)
            .makeAsyncIterator()
        var other = try #require(try await otherIterator.next())
        while other.local.quality != .ready {
            other = try #require(try await otherIterator.next())
        }
        #expect(other.accountId == otherAccount)
        #expect(other.local.rows.map(\.accountId) == [otherAccount])
        #expect(other.local.queryFingerprint != baseline.local.queryFingerprint)
        #expect(other.local.localDataVersion != baseline.local.localDataVersion)

        let membershipReader = ControlledBudgetCategoryReader(
            initialRows: [Self.sentinel(scope: 1)],
            hasLastSyncedAt: false
        )
        let membershipProof = AsyncStream<Bool>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        membershipProof.continuation.yield(true)
        let membershipQuery = Self.query(
            membershipReader,
            completeness: membershipProof.stream
        )
        var membershipIterator = membershipQuery
            .watchBudgetCategories(accountId: Self.accountId)
            .makeAsyncIterator()
        var activeEmpty = try #require(try await membershipIterator.next())
        while activeEmpty.local.quality != .ready {
            activeEmpty = try #require(try await membershipIterator.next())
        }
        membershipReader.yield([Self.sentinel(scope: 0)])
        let inactiveEmpty = try #require(try await membershipIterator.next())
        #expect(inactiveEmpty.local.rows.isEmpty)
        #expect(inactiveEmpty.local.quality == .partial)
        #expect(inactiveEmpty.local.localDataVersion != activeEmpty.local.localDataVersion)
        membershipProof.continuation.finish()

        let completenessReader = ControlledBudgetCategoryReader(
            initialRows: [Self.row()],
            hasLastSyncedAt: false
        )
        let completenessProof = AsyncStream<Bool>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        completenessProof.continuation.yield(false)
        let completenessQuery = Self.query(
            completenessReader,
            completeness: completenessProof.stream
        )
        var completenessIterator = completenessQuery
            .watchBudgetCategories(accountId: Self.accountId)
            .makeAsyncIterator()
        let incomplete = try #require(try await completenessIterator.next())
        completenessProof.continuation.yield(true)
        var complete = try #require(try await completenessIterator.next())
        while complete.local.quality != .ready {
            complete = try #require(try await completenessIterator.next())
        }
        #expect(complete.local.rows == incomplete.local.rows)
        #expect(complete.local.localDataVersion != incomplete.local.localDataVersion)
        completenessProof.continuation.finish()

        let staleReader = ControlledBudgetCategoryReader(
            initialRows: [Self.row()],
            hasLastSyncedAt: true
        )
        let stale = try await Self.firstSnapshot(query: Self.query(staleReader, complete: false))
        let partialReader = ControlledBudgetCategoryReader(
            initialRows: [Self.row()],
            hasLastSyncedAt: false
        )
        let partial = try await Self.firstSnapshot(
            query: Self.query(partialReader, complete: false)
        )
        #expect(stale.local.rows == partial.local.rows)
        #expect(stale.local.quality == .stale)
        #expect(partial.local.quality == .partial)
        #expect(stale.local.localDataVersion != partial.local.localDataVersion)

        let membershipVariantReader = ControlledBudgetCategoryReader(
            initialRows: [
                Self.row(),
                Self.row(id: "category-second", name: "Second", order: 2),
            ],
            hasLastSyncedAt: false
        )
        var membershipVariantIterator = Self.query(membershipVariantReader, complete: true)
            .watchBudgetCategories(accountId: Self.accountId)
            .makeAsyncIterator()
        var twoRows = try #require(try await membershipVariantIterator.next())
        while twoRows.local.quality != .ready {
            twoRows = try #require(try await membershipVariantIterator.next())
        }
        #expect(twoRows.local.rows.count == 2)
        #expect(twoRows.local.localDataVersion != baseline.local.localDataVersion)
    }

    @Test("Encrypted restart preserves rows but resets completeness proof")
    func encryptedRestartResetsCompleteness() async throws {
        let fixture = try BudgetCategoryDatabaseFixture()
        let firstDatabase = try fixture.open()
        try await Self.insertActiveMembership(firstDatabase)
        try await Self.insertCategory(firstDatabase)
        let ready = try await Self.firstSnapshot(
            query: Self.query(firstDatabase, complete: true)
        )
        #expect(ready.local.quality == .ready)
        try await firstDatabase.close(deleteDatabase: false)

        let reopened = try fixture.open()
        let afterRestart = try await Self.firstSnapshot(
            query: Self.query(reopened, complete: false)
        )
        #expect(afterRestart.local.rows == ready.local.rows)
        #expect(afterRestart.local.quality == .partial)
        #expect(!afterRestart.local.isCompleteForQuery)
        #expect(afterRestart.local.localDataVersion != ready.local.localDataVersion)

        try await reopened.close(deleteDatabase: true)
        fixture.removeDirectory()
    }

    @Test("Reader failure is bounded and consumer cancellation drains both sources")
    func failureAndCancellationDrainSources() async throws {
        let failingReader = ControlledBudgetCategoryReader(
            initialRows: [],
            hasLastSyncedAt: false,
            startError: true
        )
        do {
            for try await _ in Self.query(failingReader, complete: false)
                .watchBudgetCategories(accountId: Self.accountId) {
                Issue.record("A failed local read must not emit")
            }
            Issue.record("Expected bounded local-read failure")
        } catch let failure as BudgetCategoryReferenceFailure {
            #expect(failure == .localReadFailed)
        }

        let reader = ControlledBudgetCategoryReader(
            initialRows: [Self.row()],
            hasLastSyncedAt: false
        )
        let proof = ControlledCategoryCompleteness(initialValue: false)
        let firstEmission = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let emissionCounter = LockedCategoryEmissionCounter()
        let query = Self.query(reader, completeness: proof.stream)
        let publicStream = query.watchBudgetCategories(accountId: Self.accountId)
        let consumer = Task {
            do {
                for try await _ in publicStream {
                    emissionCounter.increment()
                    firstEmission.continuation.yield(())
                }
            } catch {
                Issue.record("Cancellation must finish without surfacing a provider error")
            }
        }
        var signalIterator = firstEmission.stream.makeAsyncIterator()
        _ = await signalIterator.next()
        consumer.cancel()
        await consumer.value

        for _ in 0..<50 where reader.terminationCount != 1 || proof.terminationCount != 1 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(reader.terminationCount == 1)
        #expect(proof.terminationCount == 1)
        let observedCount = emissionCounter.value
        reader.yield([Self.row(name: "After Cancellation", revision: 2)])
        proof.yield(true)
        try await Task.sleep(for: .milliseconds(20))
        #expect(emissionCounter.value == observedCount)
        var postCancellationIterator = publicStream.makeAsyncIterator()
        #expect(try await postCancellationIterator.next() == nil)
        firstEmission.continuation.finish()
    }

    @Test("Provider shutdown joins row and completeness observers")
    func providerShutdownJoinsOwnedObservers() async throws {
        let reader = ControlledBudgetCategoryReader(
            initialRows: [Self.row()],
            hasLastSyncedAt: false
        )
        let proof = ControlledCategoryCompleteness(initialValue: false)
        let firstEmission = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let query = Self.query(reader, completeness: proof.stream)
        let consumer = Task {
            do {
                for try await _ in query.watchBudgetCategories(accountId: Self.accountId) {
                    firstEmission.continuation.yield(())
                }
            } catch {
                Issue.record("Provider shutdown must terminate normally")
            }
        }
        var signalIterator = firstEmission.stream.makeAsyncIterator()
        _ = await signalIterator.next()

        await query.cancelAndDrainWatches()
        #expect(reader.terminationCount == 1)
        #expect(proof.terminationCount == 1)
        await consumer.value
        firstEmission.continuation.finish()
    }

    @Test("CATPOWER-TEST-004 shutdown drains before initial completeness evidence")
    func providerShutdownBeforeFirstCombinedSnapshot() async throws {
        let reader = ControlledBudgetCategoryReader(
            initialRows: [Self.row()],
            hasLastSyncedAt: false
        )
        let proof = ControlledCategoryCompleteness(initialValue: nil)
        let emissionCounter = LockedCategoryEmissionCounter()
        let query = Self.query(reader, completeness: proof.stream)
        let consumer = Task {
            do {
                for try await _ in query.watchBudgetCategories(accountId: Self.accountId) {
                    emissionCounter.increment()
                }
            } catch {
                Issue.record("Provider shutdown must terminate normally")
            }
        }

        for _ in 0..<100 where reader.observationCount == 0 {
            await Task.yield()
        }
        #expect(reader.observationCount == 1)
        #expect(emissionCounter.value == 0)

        await query.cancelAndDrainWatches()
        await consumer.value
        #expect(emissionCounter.value == 0)
        #expect(reader.terminationCount == 1)
        #expect(proof.terminationCount == 1)
    }

    private static let accountId = try! AccountID(validating: "account-primary")
    private static let principalId = try! PrincipalID(validating: "principal-owner")
    private static let observedAt = Date(timeIntervalSince1970: 1_788_600_000)

    private static func query(
        _ database: any PowerSyncDatabaseProtocol,
        complete: Bool
    ) -> BudgetCategoryReferencePowerSyncQuery {
        BudgetCategoryReferencePowerSyncQuery(
            database: database,
            principalId: principalId,
            accountId: accountId,
            completenessObservation: { _ in fixedStream(complete) },
            now: { observedAt }
        )
    }

    private static func query(
        _ reader: any BudgetCategoryReferenceLocalReading,
        complete: Bool
    ) -> BudgetCategoryReferencePowerSyncQuery {
        query(reader, completeness: fixedStream(complete))
    }

    private static func query(
        _ reader: any BudgetCategoryReferenceLocalReading,
        completeness: AsyncStream<Bool>
    ) -> BudgetCategoryReferencePowerSyncQuery {
        BudgetCategoryReferencePowerSyncQuery(
            localReader: reader,
            principalId: principalId,
            accountId: accountId,
            completenessObservation: { _ in completeness },
            now: { observedAt }
        )
    }

    private static func fixedStream(_ value: Bool) -> AsyncStream<Bool> {
        AsyncStream { continuation in
            continuation.yield(value)
            continuation.finish()
        }
    }

    private static func firstSnapshot(
        query: BudgetCategoryReferencePowerSyncQuery
    ) async throws -> BudgetCategoryReferenceSnapshot {
        var iterator = query.watchBudgetCategories(accountId: accountId).makeAsyncIterator()
        return try #require(try await iterator.next())
    }

    private static func row(
        scope: Int64 = 1,
        id: String? = "category-primary",
        accountId: String? = "account-primary",
        name: String? = "General",
        kind: String? = "general",
        lifecycle: String? = "active",
        isSystem: Int64? = 0,
        excludesFromOverallBudget: Int64? = 0,
        order: Int64? = 1,
        revision: Int64? = 1
    ) -> BudgetCategoryPowerSyncRow {
        BudgetCategoryPowerSyncRow(
            scopeRawValue: scope,
            id: id,
            accountId: accountId,
            displayName: name,
            kind: kind,
            lifecycle: lifecycle,
            isSystem: isSystem,
            excludesFromOverallBudget: excludesFromOverallBudget,
            presentationOrder: order,
            revision: revision
        )
    }

    private static func sentinel(scope: Int64) -> BudgetCategoryPowerSyncRow {
        BudgetCategoryPowerSyncRow(
            scopeRawValue: scope,
            id: nil,
            accountId: nil,
            displayName: nil,
            kind: nil,
            lifecycle: nil,
            isSystem: nil,
            excludesFromOverallBudget: nil,
            presentationOrder: nil,
            revision: nil
        )
    }

    private static func insertActiveMembership(
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
            parameters: ["membership-primary", accountId.rawValue, principalId.rawValue]
        )
    }

    private static func insertCategory(
        _ database: any PowerSyncDatabaseProtocol,
        id: String = "category-primary",
        accountId: String = "account-primary",
        name: String = "General",
        kind: String = "general",
        lifecycle: String = "active",
        isSystem: Int64 = 0,
        excludesFromOverallBudget: Int64 = 0,
        order: Int64 = 1,
        revision: Int64 = 1,
        visibilityClass: String = "ordinary"
    ) async throws {
        _ = try await database.execute(
            sql: """
            INSERT INTO spike_budget_categories (
              id, account_id, display_name, kind, lifecycle, is_system,
              excludes_from_overall_budget, visibility_class,
              presentation_order, revision, created_at_ms, updated_at_ms
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1788500000000, 1788500001000)
            """,
            parameters: [
                id, accountId, name, kind, lifecycle, isSystem,
                excludesFromOverallBudget, visibilityClass, order, revision,
            ]
        )
    }
}

private final class ControlledBudgetCategoryReader:
    BudgetCategoryReferenceLocalReading, @unchecked Sendable
{
    let hasLastSyncedAt: Bool
    private let lock = NSLock()
    private let initialRows: [BudgetCategoryPowerSyncRow]
    private let startError: Bool
    private var continuation: AsyncThrowingStream<[BudgetCategoryPowerSyncRow], Error>.Continuation?
    private var observations = 0
    private var terminations = 0

    init(
        initialRows: [BudgetCategoryPowerSyncRow],
        hasLastSyncedAt: Bool,
        startError: Bool = false
    ) {
        self.initialRows = initialRows
        self.hasLastSyncedAt = hasLastSyncedAt
        self.startError = startError
    }

    var observationCount: Int {
        lock.withLock { observations }
    }

    var terminationCount: Int {
        lock.withLock { terminations }
    }

    func watchRows(
        accountId: AccountID,
        principalId: PrincipalID
    ) throws -> AsyncThrowingStream<[BudgetCategoryPowerSyncRow], Error> {
        lock.withLock { observations += 1 }
        if startError { throw CategoryInjectedFailure() }
        return AsyncThrowingStream { continuation in
            lock.withLock { self.continuation = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.terminations += 1 }
            }
            continuation.yield(initialRows)
        }
    }

    func yield(_ rows: [BudgetCategoryPowerSyncRow]) {
        lock.withLock { continuation }?.yield(rows)
    }
}

private struct CategoryInjectedFailure: Error {}

private final class LockedCategoryEmissionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() {
        lock.withLock { count += 1 }
    }
}

private final class ControlledCategoryCompleteness: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Bool>.Continuation?
    private var terminations = 0
    let stream: AsyncStream<Bool>

    init(initialValue: Bool?) {
        var captured: AsyncStream<Bool>.Continuation?
        stream = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            captured = continuation
        }
        continuation = captured
        continuation?.onTermination = { [weak self] _ in
            self?.lock.withLock { self?.terminations += 1 }
        }
        if let initialValue {
            continuation?.yield(initialValue)
        }
    }

    var terminationCount: Int {
        lock.withLock { terminations }
    }

    func yield(_ value: Bool) {
        continuation?.yield(value)
    }
}

private final class BudgetCategoryDatabaseFixture: @unchecked Sendable {
    let directoryURL: URL
    private let databaseURL: URL
    private let key: LedgerPowerSyncEncryptionKey

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ledger-category-powersync-\(UUID().uuidString)",
            isDirectory: true
        )
        databaseURL = directoryURL.appendingPathComponent("ledger.sqlite")
        key = try LedgerPowerSyncEncryptionKey(
            hexadecimal: String(repeating: "6c", count: 32)
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
