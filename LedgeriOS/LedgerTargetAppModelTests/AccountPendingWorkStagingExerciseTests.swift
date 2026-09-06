import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetAppModel

@Suite("Account pending-work staging presenter")
@MainActor
struct AccountPendingWorkStagingExerciseTests {
    @Test("Exact local evidence and all four counts remain distinct")
    func exactEvidenceAndCounts() async throws {
        let pending = try Self.summary(
            revision: 42,
            observedAt: Self.t2,
            queued: 1,
            applying: 2,
            rejected: 3,
            attachments: .max
        )
        let model = Self.model { pending }

        #expect(model.presentation == .notRequested)
        #expect(model.queuedOperationCountLabel == "—")
        await model.refresh()

        #expect(model.presentation == .pending(pending))
        #expect(model.presentation.summary == pending)
        #expect(model.queuedOperationCountLabel == "1")
        #expect(model.applyingOperationCountLabel == "2")
        #expect(model.unresolvedRejectedOperationCountLabel == "3")
        #expect(model.unverifiedAttachmentCountLabel == String(UInt64.max))
        #expect(model.diagnosticCode == nil)
        await model.stop()
    }

    @Test("Only a validated all-zero summary presents clean")
    func validatedZeroIsClean() async throws {
        let zero = try Self.summary(revision: 7, observedAt: Self.t1)
        let model = Self.model { zero }

        await model.refresh()

        #expect(model.presentation == .clean(zero))
        #expect(model.statusLabel == "No pending local work")
        #expect(model.queuedOperationCountLabel == "0")
        #expect(model.applyingOperationCountLabel == "0")
        #expect(model.unresolvedRejectedOperationCountLabel == "0")
        #expect(model.unverifiedAttachmentCountLabel == "0")
        await model.stop()
    }

    @Test("Each pending class blocks independently and evidence revisions stay exact")
    func individualPendingClassesAndEvidenceIdentity() async throws {
        let cases: [(UInt64, UInt64, UInt64, UInt64)] = [
            (1, 0, 0, 0),
            (0, 1, 0, 0),
            (0, 0, 1, 0),
            (0, 0, 0, 1),
        ]
        for (queued, applying, rejected, attachments) in cases {
            let summary = try Self.summary(
                queued: queued,
                applying: applying,
                rejected: rejected,
                attachments: attachments
            )
            let model = Self.model { summary }
            await model.refresh()
            #expect(model.presentation == .pending(summary))
            await model.stop()
        }

        let first = try Self.summary(revision: 9, observedAt: Self.t1)
        let second = try Self.summary(revision: 10, observedAt: Self.t2)
        #expect(first != second)
        #expect(first.fingerprint != second.fingerprint)

        let firstModel = Self.model { first }
        await firstModel.refresh()
        #expect(firstModel.presentation.summary == first)
        await firstModel.stop()

        let secondModel = Self.model { second }
        await secondModel.refresh()
        #expect(secondModel.presentation.summary == second)
        await secondModel.stop()
    }

    @Test("Every foreign scope dimension fails closed without counts")
    func foreignScopesFailClosed() async throws {
        let summaries = try [
            Self.summary(environment: .targetLocal),
            Self.summary(principalID: "principal-foreign"),
            Self.summary(accountID: "account-foreign"),
        ]

        for summary in summaries {
            let model = Self.model { summary }
            await model.refresh()
            #expect(model.presentation == .failed(.scopeMismatch))
            #expect(model.diagnosticCode == "account_pending_work_scope_mismatch")
            #expect(model.queuedOperationCountLabel == "—")
            #expect(model.applyingOperationCountLabel == "—")
            #expect(model.unresolvedRejectedOperationCountLabel == "—")
            #expect(model.unverifiedAttachmentCountLabel == "—")
            await model.stop()
        }
    }

    @Test("Failures and spontaneous cancellation replace prior evidence")
    func failuresReplacePriorEvidence() async throws {
        let source = SequencedPendingSummarySource()
        let model = Self.model { try await source.read() }

        let clean = try Self.summary()
        let first = Task { await model.refresh() }
        await Self.wait { await source.callCount == 1 }
        await source.resume(0, returning: clean)
        await first.value
        #expect(model.presentation == .clean(clean))

        let cancelled = Task { await model.refresh() }
        await Self.wait { await source.callCount == 2 }
        await source.resume(1, throwing: CancellationError())
        await cancelled.value
        #expect(model.presentation == .failed(.sourceCancelled))
        #expect(model.presentation.summary == nil)

        let failed = Task { await model.refresh() }
        await Self.wait { await source.callCount == 3 }
        await source.resume(2, throwing: TestFailure.localRead)
        await failed.value
        #expect(model.presentation == .failed(.localReadFailed))
        #expect(model.presentation.summary == nil)
        await model.stop()
    }

    @Test("Status copy is exact and never claims remote durability or logout safety")
    func exactStatusCopyMatrix() async throws {
        let source = SequencedPendingSummarySource()
        let model = Self.model { try await source.read() }

        #expect(model.statusLabel == "Not requested")

        let cleanRead = Task { await model.refresh() }
        await Self.wait { await source.callCount == 1 }
        #expect(model.statusLabel == "Reading local status")
        await source.resume(0, returning: try Self.summary())
        await cleanRead.value
        #expect(model.statusLabel == "No pending local work")

        let pendingRead = Task { await model.refresh() }
        await Self.wait { await source.callCount == 2 }
        await source.resume(1, returning: try Self.summary(revision: 2, queued: 1))
        await pendingRead.value
        #expect(model.statusLabel == "Pending local work")

        let failedRead = Task { await model.refresh() }
        await Self.wait { await source.callCount == 3 }
        await source.resume(2, throwing: TestFailure.localRead)
        await failedRead.value
        #expect(model.statusLabel == "Local status unavailable")

        let exactLabels = [
            "Not requested",
            "Reading local status",
            "No pending local work",
            "Pending local work",
            "Local status unavailable",
        ]
        for label in exactLabels {
            let normalized = label.lowercased()
            #expect(!normalized.contains("synced"))
            #expect(!normalized.contains("uploaded"))
            #expect(!normalized.contains("remote"))
            #expect(!normalized.contains("safe to log out"))
        }

        await model.stop()
        #expect(model.statusLabel == "Not requested")
    }

    @Test("Replacement drains a noncooperative predecessor and rejects its late result")
    func replacementDrainsPredecessor() async throws {
        let source = SequencedPendingSummarySource()
        let model = Self.model { try await source.read() }
        let old = try Self.summary(revision: 10)
        let current = try Self.summary(revision: 11, queued: 5)

        let first = Task { await model.refresh() }
        await Self.wait { await source.callCount == 1 }
        let second = Task { await model.refresh() }

        await Self.yieldSeveralTimes()
        #expect(await source.callCount == 1)
        #expect(model.presentation == .loading)
        #expect(model.admittedTaskCountForTesting == 2)

        await source.resume(0, returning: old)
        await Self.wait { await source.callCount == 2 }
        #expect(model.presentation == .loading)
        await source.resume(1, returning: current)
        await first.value
        await second.value

        #expect(model.presentation == .pending(current))
        #expect(model.presentation.summary?.snapshotRevision == 11)
        #expect(model.admittedTaskCountForTesting == 0)
        await model.stop()
    }

    @Test("Stop is terminal and drains the entire admitted task registry")
    func stopIsTerminalAndDrainsEveryTask() async throws {
        let source = SequencedPendingSummarySource()
        let stopProbe = CompletionProbe()
        let model = Self.model { try await source.read() }

        let first = Task { await model.refresh() }
        await Self.wait { await source.callCount == 1 }
        let replacement = Task { await model.refresh() }
        await Self.wait { model.admittedTaskCountForTesting == 2 }

        let stop = Task {
            await model.stop()
            await stopProbe.markComplete()
        }
        await Self.yieldSeveralTimes()

        #expect(model.isStoppedForTesting)
        #expect(model.presentation == .notRequested)
        #expect(!model.canRefresh)
        #expect(!(await stopProbe.isComplete))

        let lateRefresh = Task { await model.refresh() }
        await lateRefresh.value
        #expect(await source.callCount == 1)
        #expect(model.admittedTaskCountForTesting == 2)

        await source.resume(0, returning: try Self.summary(queued: 99))
        await stop.value
        await first.value
        await replacement.value

        #expect(await stopProbe.isComplete)
        #expect(model.admittedTaskCountForTesting == 0)
        #expect(model.presentation == .notRequested)
        #expect(await source.callCount == 1)

        await model.refresh()
        await model.stop()
        #expect(await source.callCount == 1)
        #expect(model.presentation == .notRequested)
    }

    private static let principalId = try! PrincipalID(validating: "principal-pending-status")
    private static let accountId = try! AccountID(validating: "account-pending-status")
    private static let t1 = Date(timeIntervalSince1970: 1_788_600_001)
    private static let t2 = Date(timeIntervalSince1970: 1_788_600_002)

    private static func model(
        summary: @escaping AccountPendingWorkStagingRuntime.Summary
    ) -> AccountPendingWorkStagingExercise {
        AccountPendingWorkStagingExercise(
            expectedEnvironment: .targetStaging,
            expectedPrincipalId: principalId,
            expectedAccountId: accountId,
            runtime: AccountPendingWorkStagingRuntime(pendingWorkSummary: summary)
        )
    }

    private static func summary(
        environment: LedgerEnvironmentKind = .targetStaging,
        principalID: String = "principal-pending-status",
        accountID: String = "account-pending-status",
        revision: UInt64 = 1,
        observedAt: Date = t1,
        queued: UInt64 = 0,
        applying: UInt64 = 0,
        rejected: UInt64 = 0,
        attachments: UInt64 = 0
    ) throws -> PendingLocalWorkSummary {
        try PendingLocalWorkSummary(
            environment: environment,
            principalId: PrincipalID(validating: principalID),
            accountId: AccountID(validating: accountID),
            snapshotRevision: revision,
            observedAt: observedAt,
            queuedOperationCount: queued,
            applyingOperationCount: applying,
            unresolvedRejectedOperationCount: rejected,
            unverifiedAttachmentCount: attachments
        )
    }

    private static func wait(
        _ condition: @escaping @Sendable () async -> Bool
    ) async {
        for _ in 0..<2_000 {
            if await condition() { return }
            await Task.yield()
        }
        Issue.record("Timed out waiting for pending-work staging state")
    }

    private static func wait(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<2_000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("Timed out waiting for pending-work staging model state")
    }

    private static func yieldSeveralTimes() async {
        for _ in 0..<20 { await Task.yield() }
    }
}

private enum TestFailure: Error {
    case localRead
}

private actor SequencedPendingSummarySource {
    private var continuations: [Int: CheckedContinuation<PendingLocalWorkSummary, Error>] = [:]
    private(set) var callCount = 0

    func read() async throws -> PendingLocalWorkSummary {
        let index = callCount
        callCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            continuations[index] = continuation
        }
    }

    func resume(_ index: Int, returning summary: PendingLocalWorkSummary) {
        continuations.removeValue(forKey: index)?.resume(returning: summary)
    }

    func resume(_ index: Int, throwing error: any Error) {
        continuations.removeValue(forKey: index)?.resume(throwing: error)
    }
}

private actor CompletionProbe {
    private(set) var isComplete = false

    func markComplete() {
        isComplete = true
    }
}
