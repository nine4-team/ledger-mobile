import Foundation
import PowerSync
import Testing
@testable import LedgerTargetCore
@testable import LedgerTargetPowerSync

@Suite("Ledger PowerSync pending-work provider", .serialized)
struct PendingWorkPowerSyncQueryTests {
    @Test("PENDINGWORK-TEST-001 exact operation classes and attachments drive the summary")
    func exactCountsAndTerminalExclusion() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let database = try fixture.open()
        for (index, state) in LocalOperationState.allCases.enumerated() {
            try await fixture.insertOperation(
                database,
                id: "operation-state-\(state.rawValue)",
                state: state,
                timestamp: Int64(index + 1)
            )
        }
        let observer = AttachmentObserver(
            observation: try fixture.attachments(
                ("attachment-pending", .pending),
                ("attachment-missing", .missing),
                ("attachment-corrupt", .corrupt)
            )
        )
        let query = fixture.query(database: database, observer: observer)

        let summary = try await query.summary()
        #expect(summary.environment == .targetLocal)
        #expect(summary.principalId == fixture.principalID)
        #expect(summary.accountId == fixture.accountID)
        #expect(summary.queuedOperationCount == 1)
        #expect(summary.applyingOperationCount == 1)
        #expect(summary.unresolvedRejectedOperationCount == 1)
        #expect(summary.unverifiedAttachmentCount == 3)
        #expect(summary.hasBlockingWork)
        #expect(summary.snapshotRevision == 1)
        try await database.close()
    }

    @Test("PENDINGWORK-TEST-002 ps_crud is not pending-work authority")
    func crudQueueDivergence() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let database = try fixture.open()
        let observer = AttachmentObserver(observation: .init(queue: [], orphans: []))
        let query = fixture.query(database: database, observer: observer)
        let before = try await query.summary()

        _ = try await database.execute(
            sql: "INSERT INTO \(LedgerPowerSyncTable.clientCommands) (id) VALUES (?)",
            parameters: ["crud-only-command"]
        )
        #expect(try await database.getNextCrudTransaction() != nil)
        let after = try await query.summary()

        #expect(after == before)
        #expect(!after.hasBlockingWork)
        try await database.close()
    }

    @Test("PENDINGWORK-TEST-003 malformed and foreign operation evidence refuses a summary")
    func malformedAndForeignOperationsRefuse() async throws {
        for invalid in InvalidOperationCase.allCases {
            let fixture = try Fixture(suffix: invalid.rawValue)
            defer { fixture.removeDirectory() }
            let database = try fixture.open()
            switch invalid {
            case .missingFields:
                _ = try await database.execute(
                    sql: "INSERT INTO \(LedgerPowerSyncTable.localOperations) (id) VALUES (?)",
                    parameters: ["operation-missing-fields"]
                )
            case .unknownState:
                try await fixture.insertOperation(
                    database,
                    id: "operation-unknown-state",
                    stateText: "not_a_state"
                )
            case .invalidTimestamp:
                try await fixture.insertOperation(
                    database,
                    id: "operation-invalid-time",
                    state: .queued,
                    acceptedAt: 10,
                    updatedAt: 9
                )
            case .invalidOperationIdentity:
                try await fixture.insertOperation(
                    database,
                    id: "invalid operation id",
                    state: .queued
                )
            case .invalidAccountIdentity:
                try await fixture.insertOperation(
                    database,
                    id: "operation-invalid-account",
                    state: .queued,
                    accountID: "invalid account"
                )
            case .invalidPrincipalIdentity:
                try await fixture.insertOperation(
                    database,
                    id: "operation-invalid-principal",
                    state: .queued,
                    principalID: "invalid principal"
                )
            case .invalidContractIdentity:
                try await fixture.insertOperation(
                    database,
                    id: "operation-invalid-contract",
                    state: .queued,
                    contractVersion: "invalid contract"
                )
            case .invalidFingerprint:
                try await fixture.insertOperation(
                    database,
                    id: "operation-invalid-fingerprint",
                    state: .queued,
                    fingerprint: "not-a-sha256"
                )
            case .invalidSubjectIdentity:
                try await fixture.insertOperation(
                    database,
                    id: "operation-invalid-subject",
                    state: .queued,
                    subjectID: "invalid subject"
                )
            case .foreignAccount:
                try await fixture.insertOperation(
                    database,
                    id: "operation-foreign-account",
                    state: .queued,
                    accountID: "account-foreign"
                )
            case .foreignPrincipal:
                try await fixture.insertOperation(
                    database,
                    id: "operation-foreign-principal",
                    state: .queued,
                    principalID: "principal-foreign"
                )
            }
            let query = fixture.query(
                database: database,
                observer: AttachmentObserver(observation: .init(queue: [], orphans: []))
            )
            let failure = await Self.failure(of: query)
            switch invalid {
            case .foreignAccount, .foreignPrincipal:
                #expect(failure == .operationScopeMismatch)
            default:
                #expect(failure == .malformedOperationEvidence)
            }
            try await database.close()
        }
    }

    @Test("PENDINGWORK-TEST-004 attachment scope, observer faults, and orphans fail closed")
    func attachmentFailuresRefuse() async throws {
        let foreignFixture = try Fixture(suffix: "foreign-attachment")
        defer { foreignFixture.removeDirectory() }
        let foreignDatabase = try foreignFixture.open()
        let foreignReceipt = try foreignFixture.receipt(
            id: "attachment-foreign",
            principalID: "principal-foreign"
        )
        let foreignQuery = foreignFixture.query(
            database: foreignDatabase,
            observer: AttachmentObserver(observation: .init(
                queue: [.init(receipt: foreignReceipt, state: .pending)],
                orphans: []
            ))
        )
        #expect(await Self.failure(of: foreignQuery) == .attachmentScopeMismatch)
        try await foreignDatabase.close()

        let environmentFixture = try Fixture(suffix: "foreign-environment")
        defer { environmentFixture.removeDirectory() }
        let environmentDatabase = try environmentFixture.open()
        let environmentReceipt = try environmentFixture.receipt(
            id: "attachment-foreign-environment",
            environment: .targetStaging
        )
        let environmentQuery = environmentFixture.query(
            database: environmentDatabase,
            observer: AttachmentObserver(observation: .init(
                queue: [.init(receipt: environmentReceipt, state: .pending)],
                orphans: []
            ))
        )
        #expect(await Self.failure(of: environmentQuery) == .attachmentScopeMismatch)
        try await environmentDatabase.close()

        let observerFixture = try Fixture(suffix: "observer-failure")
        defer { observerFixture.removeDirectory() }
        let observerDatabase = try observerFixture.open()
        let observerQuery = observerFixture.query(
            database: observerDatabase,
            observer: AttachmentObserver(failure: InjectedFailure())
        )
        #expect(await Self.failure(of: observerQuery) == .attachmentObservationFailed)
        try await observerDatabase.close()

        let orphanFixture = try Fixture(suffix: "orphan")
        defer { orphanFixture.removeDirectory() }
        let orphanDatabase = try orphanFixture.open()
        let orphanQuery = orphanFixture.query(
            database: orphanDatabase,
            observer: AttachmentObserver(observation: .init(
                queue: [],
                orphans: [.init(kind: .finalObject, opaqueIdentity: "opaque-final")]
            ))
        )
        #expect(await Self.failure(of: orphanQuery) == .orphanedAttachmentEvidence)
        try await orphanDatabase.close()
    }

    @Test("PENDINGWORK-TEST-005 unchanged evidence is byte-stable across encrypted restart")
    func stableAcrossRestart() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let observer = AttachmentObserver(
            observation: try fixture.attachments(("attachment-restart", .pending))
        )
        let firstDatabase = try fixture.open()
        try await fixture.insertOperation(
            firstDatabase,
            id: "operation-restart",
            state: .queued
        )
        let first = try await fixture.query(database: firstDatabase, observer: observer).summary()
        let firstBytes = try OperationContractCodec.encode(first)
        try await firstDatabase.close()

        let reopened = try fixture.open()
        let cipher = try await reopened.get("PRAGMA cipher") { try $0.getString(index: 0) }
        #expect(!cipher.isEmpty)
        let second = try await fixture.query(database: reopened, observer: observer).summary()
        #expect(try OperationContractCodec.encode(second) == firstBytes)
        #expect(second.snapshotRevision == 1)
        try await reopened.close()
    }

    @Test("PENDINGWORK-TEST-006 identity changes advance revision even when counts do not")
    func sameCountIdentityTransitionAdvancesRevision() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let database = try fixture.open()
        try await fixture.insertOperation(database, id: "operation-a", state: .queued)
        let observer = AttachmentObserver(observation: .init(queue: [], orphans: []))
        let query = fixture.query(database: database, observer: observer)
        let first = try await query.summary()

        _ = try await database.execute(
            sql: "DELETE FROM \(LedgerPowerSyncTable.localOperations) WHERE id = ?",
            parameters: ["operation-a"]
        )
        try await fixture.insertOperation(database, id: "operation-b", state: .queued)
        let second = try await query.summary()

        #expect(first.queuedOperationCount == second.queuedOperationCount)
        #expect(second.snapshotRevision == first.snapshotRevision + 1)
        #expect(second.fingerprint != first.fingerprint)

        _ = try await database.execute(
            sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET local_state = ? WHERE id = ?",
            parameters: [LocalOperationState.applying.rawValue, "operation-b"]
        )
        let applying = try await query.summary()
        #expect(applying.applyingOperationCount == 1)
        #expect(applying.snapshotRevision == second.snapshotRevision + 1)

        _ = try await database.execute(
            sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET local_state = ? WHERE id = ?",
            parameters: [LocalOperationState.applied.rawValue, "operation-b"]
        )
        let applied = try await query.summary()
        #expect(!applied.hasBlockingWork)
        #expect(applied.snapshotRevision == applying.snapshotRevision + 1)

        _ = try await database.execute(
            sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET local_state = ? WHERE id = ?",
            parameters: [LocalOperationState.rejected.rawValue, "operation-b"]
        )
        let rejected = try await query.summary()
        #expect(rejected.unresolvedRejectedOperationCount == 1)
        #expect(rejected.snapshotRevision == applied.snapshotRevision + 1)

        _ = try await database.execute(
            sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET local_state = ? WHERE id = ?",
            parameters: [LocalOperationState.resolved.rawValue, "operation-b"]
        )
        let resolved = try await query.summary()
        #expect(!resolved.hasBlockingWork)
        #expect(resolved.snapshotRevision == rejected.snapshotRevision + 1)

        let rollbackQuery = fixture.query(
            database: database,
            observer: observer,
            observedAt: fixture.observedAt.addingTimeInterval(-1_000)
        )
        _ = try await database.execute(
            sql: "UPDATE \(LedgerPowerSyncTable.localOperations) SET local_state = ? WHERE id = ?",
            parameters: [LocalOperationState.queued.rawValue, "operation-b"]
        )
        let afterClockRollback = try await rollbackQuery.summary()
        #expect(afterClockRollback.snapshotRevision == resolved.snapshotRevision + 1)
        #expect(afterClockRollback.observedAt == resolved.observedAt)
        try await database.close()
    }

    @Test("PENDINGWORK-TEST-007 mutations after a stable read and during journal commit are retried")
    func interleavedMutationsAreRevalidated() async throws {
        let afterReadFixture = try Fixture(suffix: "after-read")
        defer { afterReadFixture.removeDirectory() }
        let afterReadDatabase = try afterReadFixture.open()
        let readGate = OneShotGate()
        let afterReadQuery = afterReadFixture.query(
            database: afterReadDatabase,
            observer: AttachmentObserver(observation: .init(queue: [], orphans: [])),
            checkpoint: { checkpoint in
                guard case .afterInitialStableObservation = checkpoint,
                      await readGate.claim() else { return }
                try await afterReadFixture.insertOperation(
                    afterReadDatabase,
                    id: "operation-after-read",
                    state: .queued
                )
            }
        )
        let afterRead = try await afterReadQuery.summary()
        #expect(afterRead.queuedOperationCount == 1)
        #expect(afterRead.snapshotRevision == 2)
        try await afterReadDatabase.close()

        let journalFixture = try Fixture(suffix: "journal")
        defer { journalFixture.removeDirectory() }
        let journalDatabase = try journalFixture.open()
        let journalGate = LockedGate()
        let journalQuery = journalFixture.query(
            database: journalDatabase,
            observer: AttachmentObserver(observation: .init(queue: [], orphans: [])),
            journalInterleave: { transaction in
                guard journalGate.claim() else { return }
                try journalFixture.insertOperation(
                    transaction,
                    id: "operation-during-journal",
                    state: .applying
                )
            }
        )
        let journal = try await journalQuery.summary()
        #expect(journal.applyingOperationCount == 1)
        #expect(journal.snapshotRevision == 2)
        try await journalDatabase.close()
    }

    @Test("PENDINGWORK-TEST-008 concurrent ABA cannot return an older journal revision")
    func concurrentABACallersAreSerialized() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let database = try fixture.open()
        let coordinator = BlockingAfterJournalCheckpoint()
        let query = fixture.query(
            database: database,
            observer: AttachmentObserver(observation: .init(queue: [], orphans: [])),
            checkpoint: { checkpoint in
                await coordinator.observe(checkpoint)
            }
        )

        let first = Task { try await query.summary() }
        await coordinator.waitUntilBlocked()
        try await fixture.insertOperation(
            database,
            id: "operation-concurrent-aba",
            state: .queued
        )
        let second = Task { try await query.summary() }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await coordinator.initialObservationCount == 1)
        _ = try await database.execute(
            sql: "DELETE FROM \(LedgerPowerSyncTable.localOperations) WHERE id = ?",
            parameters: ["operation-concurrent-aba"]
        )
        await coordinator.release()

        let summaries = try await [first.value, second.value]
        #expect(summaries[0] == summaries[1])
        #expect(summaries[0].snapshotRevision == 1)
        try await database.close()
    }

    @Test("PENDINGWORK-TEST-009 persistent churn and malformed journals refuse authority")
    func instabilityAndJournalCorruptionRefuse() async throws {
        let churnFixture = try Fixture(suffix: "churn")
        defer { churnFixture.removeDirectory() }
        let churnDatabase = try churnFixture.open()
        let empty = AttachmentPendingWorkObservation(queue: [], orphans: [])
        let nonempty = try churnFixture.attachments(("attachment-churn", .pending))
        let churnObserver = AttachmentObserver(sequence: [empty, nonempty])
        let churnQuery = churnFixture.query(
            database: churnDatabase,
            observer: churnObserver,
            maximumAttempts: 2
        )
        #expect(await Self.failure(of: churnQuery) == .observationUnstable)
        try await churnDatabase.close()

        let journalFixture = try Fixture(suffix: "bad-journal")
        defer { journalFixture.removeDirectory() }
        let journalDatabase = try journalFixture.open()
        let observer = AttachmentObserver(observation: empty)
        let journalQuery = journalFixture.query(database: journalDatabase, observer: observer)
        _ = try await journalQuery.summary()
        _ = try await journalDatabase.execute(
            sql: "UPDATE \(LedgerPowerSyncTable.pendingWorkObservations) SET environment = ?",
            parameters: [LedgerEnvironmentKind.targetStaging.rawValue]
        )
        #expect(await Self.failure(of: journalQuery) == .observationJournalFailed)
        try await journalDatabase.close()
    }

    @Test("PENDINGWORK-TEST-010 provider output integrates with session-ending policy")
    func sessionEndingPolicyIntegration() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let database = try fixture.open()
        try await fixture.insertOperation(database, id: "operation-session-end", state: .queued)
        let summary = try await fixture.query(
            database: database,
            observer: AttachmentObserver(observation: .init(queue: [], orphans: []))
        ).summary()
        let request = try #require(try SessionEndPolicy.makeRequest(
            choice: .synchronizeThenLogout,
            summary: summary,
            requestedAt: summary.observedAt.addingTimeInterval(1)
        ))
        #expect(try SessionEndPolicy.evaluate(request, against: summary) ==
            .synchronizationRequired(summary))
        try await database.close()
    }

    @Test("PENDINGWORK-TEST-011 finite-overflow and nonfinite observation times fail closed")
    func invalidObservationTimesRefuse() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let database = try fixture.open()
        let observer = AttachmentObserver(
            observation: .init(queue: [], orphans: [])
        )
        for invalidDate in [
            Date(timeIntervalSince1970: .infinity),
            Date(timeIntervalSince1970: Double(Int64.max) / 1_000)
        ] {
            let query = fixture.query(
                database: database,
                observer: observer,
                observedAt: invalidDate
            )
            #expect(await Self.failure(of: query) == .invalidObservationTime)
        }
        try await database.close()
    }

    @Test("PENDINGWORK-TEST-012 large valid counts remain exact and revision overflow refuses")
    func largeCountAndRevisionOverflow() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let database = try fixture.open()
        try await fixture.insertOperations(database, count: 128, state: .queued)
        let query = fixture.query(
            database: database,
            observer: AttachmentObserver(observation: .init(queue: [], orphans: []))
        )
        let valid = try await query.summary()
        #expect(valid.queuedOperationCount == 128)

        _ = try await database.execute(
            sql: "UPDATE \(LedgerPowerSyncTable.pendingWorkObservations) SET snapshot_revision = ?",
            parameters: [Int64.max]
        )
        try await fixture.insertOperation(
            database,
            id: "operation-overflow-trigger",
            state: .queued
        )
        #expect(await Self.failure(of: query) == .countOverflow)
        try await database.close()
    }

    @Test("PENDINGWORK-TEST-013 diagnostics are bounded stable codes")
    func boundedDiagnostics() {
        let failures: [PendingWorkPowerSyncQueryFailure] = [
            .malformedOperationEvidence, .operationScopeMismatch,
            .attachmentScopeMismatch, .attachmentObservationFailed,
            .orphanedAttachmentEvidence, .observationUnstable, .countOverflow,
            .invalidObservationTime, .databaseReadFailed, .observationJournalFailed,
            .summaryConstructionFailed
        ]
        let codes = failures.map(\.diagnosticCode)
        #expect(Set(codes).count == failures.count)
        for code in codes {
            #expect(code.hasPrefix("pending_work_"))
            #expect(code.count < 80)
            for forbidden in ["account-pending-work", "principal-pending-work", "/", "https:"] {
                #expect(!code.contains(forbidden))
            }
        }
    }

    @Test("PENDINGWORK-TEST-014 real attachment store orphans and enumeration faults refuse")
    func realAttachmentStoreIntegrationRefuses() async throws {
        let orphanFixture = try Fixture(suffix: "real-orphan")
        defer { orphanFixture.removeDirectory() }
        let operationDatabase = try orphanFixture.open()
        let attachmentDatabase = try orphanFixture.openAttachmentDatabase()
        let interruptedVault = try orphanFixture.makeAttachmentVault { checkpoint in
            if checkpoint == .afterStagingWrite { throw InjectedFailure() }
        }
        let interruptedStore = try orphanFixture.makeAttachmentStore(
            database: attachmentDatabase,
            vault: interruptedVault
        )
        await #expect(throws: (any Error).self) {
            _ = try await interruptedStore.enqueue(
                try orphanFixture.capture(id: "attachment-real-staging-orphan")
            )
        }
        try await attachmentDatabase.close()

        let reopenedAttachmentDatabase = try orphanFixture.openAttachmentDatabase()
        let restoredStore = try orphanFixture.makeAttachmentStore(
            database: reopenedAttachmentDatabase,
            vault: try orphanFixture.makeAttachmentVault()
        )
        let orphanQuery = orphanFixture.query(
            database: operationDatabase,
            observer: restoredStore
        )
        #expect(await Self.failure(of: orphanQuery) == .orphanedAttachmentEvidence)
        try await reopenedAttachmentDatabase.close()
        try await operationDatabase.close()

        let unavailableFixture = try Fixture(suffix: "real-unavailable")
        defer { unavailableFixture.removeDirectory() }
        let unavailableOperationDatabase = try unavailableFixture.open()
        let unavailableAttachmentDatabase = try unavailableFixture.openAttachmentDatabase()
        let unavailableVault = try unavailableFixture.makeAttachmentVault { checkpoint in
            if checkpoint == .beforeOrphanInventory { throw InjectedFailure() }
        }
        let unavailableStore = try unavailableFixture.makeAttachmentStore(
            database: unavailableAttachmentDatabase,
            vault: unavailableVault
        )
        let unavailableQuery = unavailableFixture.query(
            database: unavailableOperationDatabase,
            observer: unavailableStore
        )
        #expect(await Self.failure(of: unavailableQuery) == .attachmentObservationFailed)
        try await unavailableAttachmentDatabase.close()
        try await unavailableOperationDatabase.close()
    }

    @Test("PENDINGWORK-TEST-015 final journal reread detects a completed cross-instance ABA")
    func crossInstanceABAJournalDefenseInDepth() async throws {
        let fixture = try Fixture()
        defer { fixture.removeDirectory() }
        let database = try fixture.open()
        let observer = AttachmentObserver(observation: .init(queue: [], orphans: []))
        let coordinator = BlockingAfterJournalCheckpoint()
        let firstQuery = fixture.query(
            database: database,
            observer: observer,
            checkpoint: { checkpoint in await coordinator.observe(checkpoint) }
        )
        let secondQuery = fixture.query(database: database, observer: observer)

        let olderCandidate = Task { try await firstQuery.summary() }
        await coordinator.waitUntilBlocked()
        try await fixture.insertOperation(
            database,
            id: "operation-cross-instance-aba",
            state: .queued
        )
        let newer = try await secondQuery.summary()
        #expect(newer.snapshotRevision == 2)
        #expect(newer.queuedOperationCount == 1)
        _ = try await database.execute(
            sql: "DELETE FROM \(LedgerPowerSyncTable.localOperations) WHERE id = ?",
            parameters: ["operation-cross-instance-aba"]
        )
        await coordinator.release()

        let afterABA = try await olderCandidate.value
        #expect(afterABA.snapshotRevision == 3)
        #expect(afterABA.queuedOperationCount == 0)
        #expect(afterABA.snapshotRevision > newer.snapshotRevision)
        try await database.close()
    }

    @Test("PENDINGWORK-TEST-016 each pending class is independently authoritative")
    func eachPendingClassIndependently() async throws {
        for pendingClass in PendingClass.allCases {
            let fixture = try Fixture(suffix: pendingClass.rawValue)
            defer { fixture.removeDirectory() }
            let database = try fixture.open()
            let observation: AttachmentPendingWorkObservation
            switch pendingClass {
            case .queued:
                try await fixture.insertOperation(database, id: "operation-only-queued", state: .queued)
                observation = .init(queue: [], orphans: [])
            case .applying:
                try await fixture.insertOperation(database, id: "operation-only-applying", state: .applying)
                observation = .init(queue: [], orphans: [])
            case .rejected:
                try await fixture.insertOperation(database, id: "operation-only-rejected", state: .rejected)
                observation = .init(queue: [], orphans: [])
            case .attachment:
                observation = try fixture.attachments(("attachment-only", .pending))
            }
            let summary = try await fixture.query(
                database: database,
                observer: AttachmentObserver(observation: observation)
            ).summary()
            #expect(summary.queuedOperationCount == (pendingClass == .queued ? 1 : 0))
            #expect(summary.applyingOperationCount == (pendingClass == .applying ? 1 : 0))
            #expect(summary.unresolvedRejectedOperationCount == (pendingClass == .rejected ? 1 : 0))
            #expect(summary.unverifiedAttachmentCount == (pendingClass == .attachment ? 1 : 0))
            try await database.close()
        }
    }

    private static func failure(
        of query: PendingWorkPowerSyncQuery
    ) async -> PendingWorkPowerSyncQueryFailure? {
        do {
            _ = try await query.summary()
            return nil
        } catch let failure as PendingWorkPowerSyncQueryFailure {
            return failure
        } catch {
            return nil
        }
    }
}

private enum InvalidOperationCase: String, CaseIterable {
    case missingFields
    case unknownState
    case invalidTimestamp
    case invalidOperationIdentity
    case invalidAccountIdentity
    case invalidPrincipalIdentity
    case invalidContractIdentity
    case invalidFingerprint
    case invalidSubjectIdentity
    case foreignAccount
    case foreignPrincipal
}

private enum PendingClass: String, CaseIterable {
    case queued
    case applying
    case rejected
    case attachment
}

private struct InjectedFailure: Error {}

private actor OneShotGate {
    private var available = true

    func claim() -> Bool {
        guard available else { return false }
        available = false
        return true
    }
}

private actor BlockingAfterJournalCheckpoint {
    private(set) var initialObservationCount = 0
    private var hasBlocked = false
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func observe(_ checkpoint: PendingWorkPowerSyncQueryCheckpoint) async {
        switch checkpoint {
        case .afterInitialStableObservation:
            initialObservationCount += 1
        case .afterJournalCommit:
            guard !hasBlocked else { return }
            hasBlocked = true
            let waiters = blockedWaiters
            blockedWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
            await withCheckedContinuation { continuation in
                releaseWaiter = continuation
            }
        }
    }

    func waitUntilBlocked() async {
        guard !hasBlocked else { return }
        await withCheckedContinuation { continuation in
            blockedWaiters.append(continuation)
        }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private final class LockedGate: @unchecked Sendable {
    private let lock = NSLock()
    private var available = true

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard available else { return false }
        available = false
        return true
    }
}

private actor AttachmentObserver: AttachmentPendingWorkObserving {
    private let observations: [AttachmentPendingWorkObservation]
    private let failure: (any Error)?
    private var index = 0

    init(observation: AttachmentPendingWorkObservation) {
        observations = [observation]
        failure = nil
    }

    init(sequence: [AttachmentPendingWorkObservation]) {
        observations = sequence
        failure = nil
    }

    init(failure: any Error) {
        observations = []
        self.failure = failure
    }

    func pendingWorkObservation() async throws -> AttachmentPendingWorkObservation {
        if let failure { throw failure }
        guard !observations.isEmpty else { throw InjectedFailure() }
        let observation = observations[index % observations.count]
        index += 1
        return observation
    }
}

private final class Fixture: @unchecked Sendable {
    let directoryURL: URL
    let databaseURL: URL
    let key = try! LedgerPowerSyncEncryptionKey(
        hexadecimal: String(repeating: "2b", count: 32)
    )
    let environment = LedgerEnvironmentKind.targetLocal
    let principalID = try! PrincipalID(validating: "principal-pending-work")
    let accountID = try! AccountID(validating: "account-pending-work")
    let observedAt = Date(timeIntervalSince1970: 2_000)

    init(suffix: String = UUID().uuidString) throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-work-provider-\(suffix)", isDirectory: true)
            .standardizedFileURL
        databaseURL = directoryURL.appendingPathComponent("pending-work.sqlite")
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

    func openAttachmentDatabase() throws -> any PowerSyncDatabaseProtocol {
        try AttachmentCapturePowerSyncDatabaseFactory.open(
            absolutePath: directoryURL.appendingPathComponent("attachments.sqlite").path,
            encryptionKey: key
        )
    }

    func makeAttachmentVault(
        fault: @Sendable @escaping (AttachmentVaultCheckpoint) throws -> Void = { _ in }
    ) throws -> AttachmentLocalByteVault {
        try AttachmentLocalByteVault(
            trustedRoot: directoryURL.appendingPathComponent("attachment-vault", isDirectory: true),
            scope: attachmentScope(),
            mediaKey: AttachmentMediaEncryptionKey(bytes: Data(repeating: 0x52, count: 32)),
            fault: fault
        )
    }

    func makeAttachmentStore(
        database: any PowerSyncDatabaseProtocol,
        vault: AttachmentLocalByteVault
    ) throws -> AttachmentCapturePowerSyncStore {
        AttachmentCapturePowerSyncStore(
            database: database,
            vault: vault,
            scope: try attachmentScope(),
            now: { self.observedAt }
        )
    }

    func capture(id: String) throws -> LocalAttachmentCapture {
        try LocalAttachmentCapture(
            attachmentId: AttachmentID(validating: id),
            scope: AttachmentCaptureScope(
                environment: environment,
                principalId: principalID,
                accountId: accountID,
                parent: LedgerEntityReference(
                    kind: .item,
                    id: EntityID(validating: "item-real-attachment")
                )
            ),
            capturedAt: AttachmentEpochMilliseconds(validating: 1_000),
            bytes: Data("real protected attachment bytes".utf8)
        )
    }

    func query(
        database: any PowerSyncDatabaseProtocol,
        observer: any AttachmentPendingWorkObserving,
        observedAt: Date? = nil,
        maximumAttempts: Int = 3,
        checkpoint: @Sendable @escaping (
            PendingWorkPowerSyncQueryCheckpoint
        ) async throws -> Void = { _ in },
        journalInterleave: @Sendable @escaping (any Transaction) throws -> Void = { _ in }
    ) -> PendingWorkPowerSyncQuery {
        PendingWorkPowerSyncQuery(
            database: database,
            attachmentObserver: observer,
            environment: environment,
            principalId: principalID,
            accountId: accountID,
            now: { observedAt ?? self.observedAt },
            maximumAttempts: maximumAttempts,
            checkpoint: checkpoint,
            journalInterleave: journalInterleave
        )
    }

    func insertOperation(
        _ database: any PowerSyncDatabaseProtocol,
        id: String,
        state: LocalOperationState,
        timestamp: Int64 = 1,
        acceptedAt: Int64? = nil,
        updatedAt: Int64? = nil,
        accountID: String? = nil,
        principalID: String? = nil,
        contractVersion: String? = nil,
        fingerprint: String? = nil,
        subjectID: String? = nil
    ) async throws {
        _ = try await database.execute(
            sql: operationInsertSQL,
            parameters: operationParameters(
                id: id,
                stateText: state.rawValue,
                timestamp: timestamp,
                acceptedAt: acceptedAt,
                updatedAt: updatedAt,
                accountID: accountID,
                principalID: principalID,
                contractVersion: contractVersion,
                fingerprint: fingerprint,
                subjectID: subjectID
            )
        )
    }

    func insertOperation(
        _ database: any PowerSyncDatabaseProtocol,
        id: String,
        stateText: String,
        timestamp: Int64 = 1
    ) async throws {
        _ = try await database.execute(
            sql: operationInsertSQL,
            parameters: operationParameters(
                id: id,
                stateText: stateText,
                timestamp: timestamp
            )
        )
    }

    func insertOperation(
        _ transaction: any Transaction,
        id: String,
        state: LocalOperationState,
        timestamp: Int64 = 1
    ) throws {
        _ = try transaction.execute(
            sql: operationInsertSQL,
            parameters: operationParameters(
                id: id,
                stateText: state.rawValue,
                timestamp: timestamp
            )
        )
    }

    func insertOperations(
        _ database: any PowerSyncDatabaseProtocol,
        count: Int,
        state: LocalOperationState
    ) async throws {
        try await database.writeTransaction { transaction in
            for index in 0..<count {
                try self.insertOperation(
                    transaction,
                    id: "operation-large-\(index)",
                    state: state,
                    timestamp: Int64(index + 1)
                )
            }
        }
    }

    func attachments(
        _ entries: (String, AttachmentPendingState)...
    ) throws -> AttachmentPendingWorkObservation {
        try AttachmentPendingWorkObservation(
            queue: entries.map { id, state in
                AttachmentPendingWorkQueueEvidence(
                    receipt: try receipt(id: id),
                    state: state
                )
            },
            orphans: []
        )
    }

    func receipt(
        id: String,
        principalID: String? = nil,
        environment: LedgerEnvironmentKind? = nil
    ) throws -> AttachmentLocalDurabilityReceipt {
        let scope = AttachmentCaptureScope(
            environment: environment ?? self.environment,
            principalId: try PrincipalID(validating: principalID ?? self.principalID.rawValue),
            accountId: accountID,
            parent: LedgerEntityReference(
                kind: .item,
                id: try EntityID(validating: "item-pending-work")
            )
        )
        let capture = try LocalAttachmentCapture(
            attachmentId: AttachmentID(validating: id),
            scope: scope,
            capturedAt: AttachmentEpochMilliseconds(validating: 1_000),
            bytes: Data("bytes-for-\(id)".utf8)
        )
        let persisted = try AttachmentPersistedLocalObjectEvidence(
            attachmentId: capture.attachmentId,
            scope: scope,
            localObjectId: AttachmentLocalObjectID(
                validating: String(repeating: id == "attachment-foreign" ? "3" : "4", count: 64)
            ),
            byteCount: capture.byteCount,
            contentSHA256: capture.contentSHA256,
            persistedAt: AttachmentEpochMilliseconds(validating: 2_000)
        )
        return try AttachmentLocalDurabilityReceipt(
            accepting: capture,
            persistedEvidence: persisted
        )
    }

    func removeDirectory() {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private var operationInsertSQL: String {
        """
        INSERT INTO \(LedgerPowerSyncTable.localOperations) (
          id, account_id, actor_principal_id, contract_version, fingerprint,
          subject_id, local_state, accepted_at_ms, updated_at_ms
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
    }

    private func attachmentScope() throws -> AttachmentDurabilityNamespaceScope {
        try AttachmentDurabilityNamespaceScope(
            validatedEnvironment: validatedEnvironment(),
            principalId: principalID,
            accountId: accountID
        )
    }

    private func validatedEnvironment() throws -> ValidatedLedgerEnvironment {
        let versions = LedgerContractVersions(
            schema: "1", query: "1", operation: "1", sync: "1"
        )
        let identifiers = Dictionary(
            uniqueKeysWithValues: LedgerTargetComponent.allCases.map {
                ($0, "pending-work-tests-\($0.rawValue)")
            }
        )
        let manifest = LedgerEnvironmentManifest(
            environment: .targetLocal,
            buildProfile: .targetLocalDevelopment,
            bundleIdentifier: "apps.nine4.ledger.pending-work-tests",
            displayName: "Ledger Pending Work Tests",
            localDataNamespacePrefix: "apps.nine4.ledger.pending-work-tests",
            contractVersions: versions,
            resources: LedgerTargetComponent.allCases.map {
                LedgerEnvironmentResource(
                    component: $0,
                    environment: .targetLocal,
                    publicIdentifier: identifiers[$0]!
                )
            }
        )
        return try LedgerEnvironmentValidator.validate(
            manifest,
            policy: LedgerEnvironmentPolicy(
                expectedEnvironment: .targetLocal,
                expectedBuildProfile: .targetLocalDevelopment,
                expectedBundleIdentifier: manifest.bundleIdentifier,
                expectedContractVersions: versions,
                allowedResourceIdentifiers: identifiers.mapValues { [$0] },
                forbiddenResourceIdentifiers: [],
                forbiddenBundleIdentifiers: []
            )
        )
    }

    private func operationParameters(
        id: String,
        stateText: String,
        timestamp: Int64,
        acceptedAt: Int64? = nil,
        updatedAt: Int64? = nil,
        accountID: String? = nil,
        principalID: String? = nil,
        contractVersion: String? = nil,
        fingerprint: String? = nil,
        subjectID: String? = nil
    ) -> [(any Sendable)?] {
        let accepted = acceptedAt ?? timestamp
        return [
            id,
            accountID ?? self.accountID.rawValue,
            principalID ?? self.principalID.rawValue,
            contractVersion ?? "pending-work-v1",
            fingerprint ?? String(repeating: "a", count: 64),
            subjectID ?? "subject-\(id)",
            stateText,
            accepted,
            updatedAt ?? accepted
        ]
    }
}
