import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Operation Lifecycle and Readiness Contracts")
struct OperationLifecycleContractTests {
    private struct RenamePayload: Codable, Equatable, Sendable {
        let name: String
    }

    @Test("Local acceptance is queued and canonical fingerprints survive encoding")
    func localAcceptanceIsQueued() throws {
        let envelope = try Self.envelope(id: "operation-001", name: "North House")
        let fingerprint = try OperationFingerprint.make(for: envelope)
        let decoded = try OperationContractCodec.decode(
            OperationEnvelope<RenamePayload>.self,
            from: OperationContractCodec.encode(envelope)
        )
        var journal = OperationJournal()

        let receipt = try journal.accept(envelope, at: Self.t0)
        let replay = try journal.accept(decoded, at: Self.t1)

        #expect(receipt.localState == .queued)
        #expect(replay == receipt)
        #expect(journal.snapshots.count == 1)
        #expect(journal.snapshot(for: envelope.operationId)?.fingerprint == fingerprint)
        #expect(journal.snapshot(for: envelope.operationId)?.state.phase == .queued)
        #expect(journal.snapshot(for: envelope.operationId)?.updatedAt == Self.t0)
    }

    @Test("The same operation ID cannot carry a different payload")
    func payloadMismatchFailsPermanently() throws {
        let original = try Self.envelope(id: "operation-002", name: "Original")
        let changed = try Self.envelope(id: "operation-002", name: "Changed")
        var journal = OperationJournal()
        _ = try journal.accept(original, at: Self.t0)

        let failure = Self.captureFailure {
            _ = try journal.accept(changed, at: Self.t1)
        }

        #expect(failure == .payloadMismatch(original.operationId))
        #expect(journal.snapshots.count == 1)
    }

    @Test("Transient failure requeues and lost-response replay returns the prior result")
    func retryAndLostResponseAreIdempotent() throws {
        let envelope = try Self.envelope(id: "operation-003", name: "Retry")
        let transient = try Self.error(
            code: "transport_unavailable",
            category: .transientInfrastructure,
            retry: .automatic
        )
        let result = try Self.appliedResult(code: "project_renamed")
        var journal = OperationJournal()
        _ = try journal.accept(envelope, at: Self.t0)

        let firstAttempt = try journal.apply(.beginApplying, to: envelope.operationId, at: Self.t1)
        let requeued = try journal.apply(
            .transientFailure(transient),
            to: envelope.operationId,
            at: Self.t2
        )
        let secondAttempt = try journal.apply(.beginApplying, to: envelope.operationId, at: Self.t3)
        let applied = try journal.apply(.applied(result), to: envelope.operationId, at: Self.t4)
        let lostResponseReplay = try journal.apply(
            .applied(result),
            to: envelope.operationId,
            at: Self.t5
        )

        #expect(firstAttempt.state.phase == .applying)
        #expect(requeued.state == .queued(attemptCount: 1, lastTransientError: transient))
        #expect(secondAttempt.state == .applying(attempt: 2, startedAt: Self.t3))
        #expect(applied.state == .applied(result))
        #expect(lostResponseReplay == applied)
        #expect(lostResponseReplay.updatedAt == Self.t4)
    }

    @Test("Permanent rejection does not starve unrelated operations")
    func permanentRejectionDoesNotStarveQueue() throws {
        let rejectedEnvelope = try Self.envelope(id: "operation-004", name: "Rejected")
        let laterEnvelope = try Self.envelope(id: "operation-005", name: "Later")
        let rejection = OperationRejection(
            error: try Self.error(
                code: "membership_revoked",
                category: .authorization,
                retry: .never
            ),
            rejectedAt: Self.t2
        )
        let resolution = RejectionResolution(
            code: try ResolutionCode(validating: "acknowledged"),
            resolvedAt: Self.t5
        )
        var journal = OperationJournal()
        _ = try journal.accept(rejectedEnvelope, at: Self.t0)
        _ = try journal.accept(laterEnvelope, at: Self.t1)

        _ = try journal.apply(.beginApplying, to: rejectedEnvelope.operationId, at: Self.t1)
        _ = try journal.apply(.rejected(rejection), to: rejectedEnvelope.operationId, at: Self.t2)
        _ = try journal.apply(.beginApplying, to: laterEnvelope.operationId, at: Self.t3)
        _ = try journal.apply(
            .applied(try Self.appliedResult(code: "project_renamed")),
            to: laterEnvelope.operationId,
            at: Self.t4
        )

        #expect(journal.snapshot(for: rejectedEnvelope.operationId)?.state == .rejected(rejection))
        #expect(journal.snapshot(for: laterEnvelope.operationId)?.state.phase == .applied)
        #expect(journal.unresolved(accountId: rejectedEnvelope.accountId).map(\.operationId) == [rejectedEnvelope.operationId])

        let resolved = try journal.apply(
            .resolveRejection(resolution),
            to: rejectedEnvelope.operationId,
            at: Self.t5
        )
        #expect(resolved.state == .resolved(rejection: rejection, resolution: resolution))
        #expect(journal.unresolved(accountId: rejectedEnvelope.accountId).isEmpty)
    }

    @Test("Supersession retains the original authoritative result")
    func supersessionRetainsOriginalEvidence() throws {
        let envelope = try Self.envelope(id: "operation-010", name: "Corrected")
        let original = try Self.appliedResult(code: "project_renamed")
        let correction = CorrectionReference(
            operationId: try OperationID(validating: "operation-correction-010"),
            correctedAt: Self.t5
        )
        var journal = OperationJournal()
        _ = try journal.accept(envelope, at: Self.t0)
        _ = try journal.apply(.beginApplying, to: envelope.operationId, at: Self.t1)
        _ = try journal.apply(.applied(original), to: envelope.operationId, at: Self.t4)

        let superseded = try journal.apply(
            .superseded(correction),
            to: envelope.operationId,
            at: Self.t5
        )
        let restored = try OperationContractCodec.decode(
            OperationJournal.self,
            from: OperationContractCodec.encode(journal)
        )

        #expect(superseded.state == .superseded(original: original, correction: correction))
        #expect(restored.snapshot(for: envelope.operationId)?.state == superseded.state)
        #expect(restored.snapshot(for: envelope.operationId)?.state.outcome == .superseded(correction))
    }

    @Test("Illegal lifecycle transitions fail without changing the record")
    func illegalTransitionPreservesState() throws {
        let envelope = try Self.envelope(id: "operation-006", name: "Illegal")
        var journal = OperationJournal()
        _ = try journal.accept(envelope, at: Self.t0)

        let failure = Self.captureFailure {
            _ = try journal.apply(
                .applied(try Self.appliedResult(code: "project_renamed")),
                to: envelope.operationId,
                at: Self.t1
            )
        }

        #expect(failure == .illegalTransition(from: .queued, event: .applied))
        #expect(journal.snapshot(for: envelope.operationId)?.state.phase == .queued)
        #expect(journal.snapshot(for: envelope.operationId)?.updatedAt == Self.t0)
    }

    @Test("Restart restores unresolved evidence and Account isolation")
    func restartAndAccountIsolation() throws {
        let accountA = try Self.envelope(id: "operation-007", account: "account-a", name: "A")
        let accountB = try Self.envelope(id: "operation-008", account: "account-b", name: "B")
        var journal = OperationJournal()
        _ = try journal.accept(accountA, at: Self.t0)
        _ = try journal.accept(accountB, at: Self.t1)
        _ = try journal.apply(.beginApplying, to: accountA.operationId, at: Self.t2)

        let persisted = try OperationContractCodec.encode(journal)
        let restored = try OperationContractCodec.decode(OperationJournal.self, from: persisted)

        #expect(restored.unresolved(accountId: accountA.accountId).map(\.operationId) == [accountA.operationId])
        #expect(restored.unresolved(accountId: accountB.accountId).map(\.operationId) == [accountB.operationId])
        #expect(restored.snapshot(for: accountA.operationId)?.state == .applying(attempt: 1, startedAt: Self.t2))
        #expect(restored.snapshot(for: accountB.operationId)?.state.phase == .queued)
    }

    @Test("Online and synchronized are independent states")
    func onlineAndSynchronizedAreIndependent() throws {
        let ready = try Self.subscription(state: .ready, localVersion: "operation-v1")
        let offlineReady = try SyncHealthSnapshot(
            connectivity: .offline,
            authentication: .stale,
            subscriptions: [ready],
            lastSuccessfulCheckpointAt: Self.t0,
            pendingOperationCount: 1,
            oldestPendingOperationAt: Self.t1,
            pendingAttachmentCount: 0,
            oldestPendingAttachmentAt: nil,
            rejectedOperationCount: 0,
            transientError: nil,
            writeBlock: .none
        )
        let onlineLoading = try SyncHealthSnapshot(
            connectivity: .online,
            authentication: .current,
            subscriptions: [try Self.subscription(state: .loading, localVersion: nil)],
            lastSuccessfulCheckpointAt: Self.t0,
            pendingOperationCount: 0,
            oldestPendingOperationAt: nil,
            pendingAttachmentCount: 0,
            oldestPendingAttachmentAt: nil,
            rejectedOperationCount: 0,
            transientError: nil,
            writeBlock: .none
        )

        #expect(!offlineReady.isOnline)
        #expect(offlineReady.isSynchronized)
        #expect(onlineLoading.isOnline)
        #expect(!onlineLoading.isSynchronized)
    }

    @Test("Required updates and contract mismatch remain explicit readiness blockers")
    func readinessBlockersAreExplicit() throws {
        let contractMismatch = try Self.subscription(
            state: .ready,
            localVersion: "operation-v0"
        )
        let snapshot = try SyncHealthSnapshot(
            connectivity: .online,
            authentication: .current,
            subscriptions: [contractMismatch],
            lastSuccessfulCheckpointAt: Self.t0,
            pendingOperationCount: 0,
            oldestPendingOperationAt: nil,
            pendingAttachmentCount: 0,
            oldestPendingAttachmentAt: nil,
            rejectedOperationCount: 0,
            transientError: nil,
            writeBlock: .clientUpdateRequired
        )

        #expect(snapshot.isOnline)
        #expect(!snapshot.isSynchronized)
        #expect(snapshot.writeBlock == .clientUpdateRequired)
        #expect(snapshot.subscriptions.first?.satisfiesRequirement == false)
    }

    @Test("Contradictory pending-work counts fail closed")
    func pendingCountValidation() throws {
        let missingOldest = Self.captureFailure {
            _ = try SyncHealthSnapshot(
                connectivity: .offline,
                authentication: .stale,
                subscriptions: [],
                lastSuccessfulCheckpointAt: Self.t0,
                pendingOperationCount: 1,
                oldestPendingOperationAt: nil,
                pendingAttachmentCount: 0,
                oldestPendingAttachmentAt: nil,
                rejectedOperationCount: 0,
                transientError: nil,
                writeBlock: .none
            )
        }
        let negative = Self.captureFailure {
            _ = try SyncHealthSnapshot(
                connectivity: .offline,
                authentication: .stale,
                subscriptions: [],
                lastSuccessfulCheckpointAt: nil,
                pendingOperationCount: 0,
                oldestPendingOperationAt: nil,
                pendingAttachmentCount: 0,
                oldestPendingAttachmentAt: nil,
                rejectedOperationCount: -1,
                transientError: nil,
                writeBlock: .none
            )
        }

        #expect(missingOldest == .inconsistentOldestTimestamp(field: "pending_operations"))
        #expect(negative == .invalidCount(field: "rejected_operations"))
    }

    @Test("Diagnostics serialize stable codes without raw vendor messages or payloads")
    func diagnosticsAreSafe() throws {
        let diagnostic = OperationDiagnostic(
            operationId: try OperationID(validating: "operation-009"),
            accountId: try AccountID(validating: "account-a"),
            error: try Self.error(
                code: "authorization_denied",
                category: .authorization,
                retry: .never
            )
        )
        let encoded = try OperationContractCodec.encode(diagnostic)
        let text = String(decoding: encoded, as: UTF8.self)

        #expect(text.contains("authorization_denied"))
        #expect(text.contains("operation-009"))
        #expect(!text.contains("permission denied for relation"))
        #expect(!text.contains("payload"))
        #expect(!text.contains("token"))
    }

    private static let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private static let t1 = Date(timeIntervalSince1970: 1_700_000_001)
    private static let t2 = Date(timeIntervalSince1970: 1_700_000_002)
    private static let t3 = Date(timeIntervalSince1970: 1_700_000_003)
    private static let t4 = Date(timeIntervalSince1970: 1_700_000_004)
    private static let t5 = Date(timeIntervalSince1970: 1_700_000_005)

    private static func envelope(
        id: String,
        account: String = "account-a",
        name: String
    ) throws -> OperationEnvelope<RenamePayload> {
        OperationEnvelope(
            operationId: try OperationID(validating: id),
            contractVersion: try OperationContractVersion(validating: "operation-v1"),
            accountId: try AccountID(validating: account),
            actorPrincipalId: try PrincipalID(validating: "principal-a"),
            clientCreatedAt: t0,
            payload: RenamePayload(name: name),
            preconditions: [
                .expectedRevision(
                    subject: LedgerEntityReference(
                        kind: .project,
                        id: try EntityID(validating: "project-a")
                    ),
                    revision: 7
                )
            ]
        )
    }

    private static func error(
        code: String,
        category: ApplicationErrorCategory,
        retry: RetryDisposition
    ) throws -> ApplicationErrorSummary {
        ApplicationErrorSummary(
            code: try ApplicationErrorCode(validating: code),
            category: category,
            retryDisposition: retry
        )
    }

    private static func appliedResult(code: String) throws -> AppliedOperationResult {
        AppliedOperationResult(
            resultCode: try ApplicationResultCode(validating: code),
            serverReceivedAt: t3,
            completedAt: t4
        )
    }

    private static func subscription(
        state: SubscriptionReadinessState,
        localVersion: String?
    ) throws -> SubscriptionReadinessSnapshot {
        SubscriptionReadinessSnapshot(
            capability: try CapabilityID(validating: "project_workspace"),
            required: true,
            requiredContractVersion: try OperationContractVersion(validating: "operation-v1"),
            localContractVersion: try localVersion.map(OperationContractVersion.init(validating:)),
            state: state
        )
    }

    private static func captureFailure(
        _ operation: () throws -> Void
    ) -> OperationContractFailure? {
        do {
            try operation()
            return nil
        } catch let failure as OperationContractFailure {
            return failure
        } catch {
            return nil
        }
    }
}
