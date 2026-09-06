import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Session Ending and Pending-Work Contracts")
struct SessionEndingPolicyTests {
    @Test("Exact pending classes drive clean, sync-first, destructive, and cancel choices")
    func exactCountsAndChoices() throws {
        let pending = try Self.summary(
            queued: 1,
            applying: 2,
            rejected: 3,
            attachments: 4
        )
        #expect(pending.queuedOperationCount == 1)
        #expect(pending.applyingOperationCount == 2)
        #expect(pending.unresolvedRejectedOperationCount == 3)
        #expect(pending.unverifiedAttachmentCount == 4)
        #expect(pending.hasBlockingWork)

        let canceled = try SessionEndPolicy.makeRequest(
            choice: .cancel,
            summary: pending,
            requestedAt: Self.t2
        )
        #expect(canceled == nil)

        #expect(Self.failure {
            try SessionEndPolicy.makeRequest(
                choice: .ordinaryCleanLogout,
                summary: pending,
                requestedAt: Self.t2
            )
        } == .pendingWorkRequiresDisposition)

        let sync = try #require(try SessionEndPolicy.makeRequest(
            choice: .synchronizeThenLogout,
            summary: pending,
            requestedAt: Self.t2
        ))
        #expect(sync.disposition == .synchronizeThenLogout)
        #expect(try SessionEndPolicy.evaluate(sync, against: pending) ==
            .synchronizationRequired(pending))

        let resolved = try Self.summary(revision: 8, observedAt: Self.t3)
        #expect(!resolved.hasBlockingWork)
        #expect(try SessionEndPolicy.evaluate(sync, against: resolved) ==
            .readyForTeardown(.synchronizeThenLogout))

        let clean = try #require(try SessionEndPolicy.makeRequest(
            choice: .ordinaryCleanLogout,
            summary: resolved,
            requestedAt: Self.t4
        ))
        #expect(try SessionEndPolicy.evaluate(clean, against: resolved) ==
            .readyForTeardown(.ordinaryCleanLogout))

        let destructive = try #require(try SessionEndPolicy.makeRequest(
            choice: .removeFromDeviceDiscardingPendingWork(confirmedAt: Self.t2),
            summary: pending,
            requestedAt: Self.t3
        ))
        #expect(destructive.destructiveConfirmation?.confirmedSummary == pending)
        #expect(try SessionEndPolicy.evaluate(destructive, against: pending) ==
            .readyForTeardown(.removeFromDeviceDiscardingPendingWork))
    }

    @Test("Summary, confirmation, and every disposition survive canonical restart")
    func canonicalRestart() throws {
        let pending = try Self.summary(queued: 2, rejected: 1, attachments: 3)
        let cleanSummary = try Self.summary(revision: 8, observedAt: Self.t3)
        let confirmation = try DestructiveLocalRemovalConfirmation(
            confirming: pending,
            confirmedAt: Self.t2
        )
        let requests = try [
            SessionEndRequest(
                disposition: .ordinaryCleanLogout,
                expectedSummary: cleanSummary,
                requestedAt: Self.t4
            ),
            SessionEndRequest(
                disposition: .synchronizeThenLogout,
                expectedSummary: pending,
                requestedAt: Self.t2
            ),
            SessionEndRequest(
                disposition: .removeFromDeviceDiscardingPendingWork,
                expectedSummary: pending,
                destructiveConfirmation: confirmation,
                requestedAt: Self.t3
            )
        ]

        try Self.expectCanonicalRoundTrip(pending)
        try Self.expectCanonicalRoundTrip(confirmation)
        for request in requests {
            try Self.expectCanonicalRoundTrip(request)
            let bytes = try OperationContractCodec.encode(request)
            let text = String(decoding: bytes, as: UTF8.self).lowercased()
            for forbidden in [
                "firebase", "firestore", "supabase", "powersync", "https://",
                "file://", "bearer", "token", "secret", "provider", "payload",
                "databasepath", "encryptionkey", "serverapplied"
            ] {
                #expect(!text.contains(forbidden))
            }
        }
        #expect(Set(requests.map(\.fingerprint)).count == 3)
    }

    @Test("Malformed, rebound, stale, and tampered session evidence fails closed")
    func invalidAndTamperedEvidenceFailsClosed() throws {
        #expect(Self.failure {
            try Self.summary(observedAt: Date(timeIntervalSinceReferenceDate: .infinity))
        } == .invalidObservedAt)
        #expect(Self.failure {
            try Self.summary(observedAt: Date(timeIntervalSinceReferenceDate: .nan))
        } == .invalidObservedAt)

        let pending = try Self.summary(queued: 1, attachments: 1)
        #expect(Self.failure {
            try DestructiveLocalRemovalConfirmation(
                confirming: pending,
                confirmedAt: Self.t0
            )
        } == .invalidConfirmedAt)
        #expect(Self.failure {
            try SessionEndRequest(
                disposition: .ordinaryCleanLogout,
                expectedSummary: pending,
                requestedAt: Self.t2
            )
        } == .pendingWorkRequiresDisposition)
        #expect(Self.failure {
            try SessionEndRequest(
                disposition: .removeFromDeviceDiscardingPendingWork,
                expectedSummary: pending,
                requestedAt: Self.t2
            )
        } == .destructiveConfirmationRequired)

        let otherCounts = try Self.summary(queued: 2, attachments: 1)
        let otherConfirmation = try DestructiveLocalRemovalConfirmation(
            confirming: otherCounts,
            confirmedAt: Self.t2
        )
        #expect(Self.failure {
            try SessionEndRequest(
                disposition: .removeFromDeviceDiscardingPendingWork,
                expectedSummary: pending,
                destructiveConfirmation: otherConfirmation,
                requestedAt: Self.t3
            )
        } == .destructiveConfirmationMismatch)

        let cleanSummary = try Self.summary(revision: 8, observedAt: Self.t3)
        let clean = try SessionEndRequest(
            disposition: .ordinaryCleanLogout,
            expectedSummary: cleanSummary,
            requestedAt: Self.t4
        )
        for changed in try [
            Self.summary(environment: .targetLocal, revision: 8, observedAt: Self.t3),
            Self.summary(principalID: "principal-other", revision: 8, observedAt: Self.t3),
            Self.summary(accountID: "account-other", revision: 8, observedAt: Self.t3)
        ] {
            #expect(Self.failure {
                try SessionEndPolicy.evaluate(clean, against: changed)
            } == .scopeMismatch)
        }
        let newlyPending = try Self.summary(
            revision: 9,
            observedAt: Self.t4,
            queued: 1
        )
        #expect(Self.failure {
            try SessionEndPolicy.evaluate(clean, against: newlyPending)
        } == .summaryChanged)

        let sync = try SessionEndRequest(
            disposition: .synchronizeThenLogout,
            expectedSummary: pending,
            requestedAt: Self.t2
        )
        let regressed = try Self.summary(
            revision: pending.snapshotRevision - 1,
            observedAt: Self.t0
        )
        #expect(Self.failure {
            try SessionEndPolicy.evaluate(sync, against: regressed)
        } == .summaryRegressed)

        let destructive = try SessionEndRequest(
            disposition: .removeFromDeviceDiscardingPendingWork,
            expectedSummary: pending,
            destructiveConfirmation: DestructiveLocalRemovalConfirmation(
                confirming: pending,
                confirmedAt: Self.t2
            ),
            requestedAt: Self.t3
        )
        #expect(Self.failure {
            try SessionEndPolicy.evaluate(destructive, against: otherCounts)
        } == .summaryChanged)

        let summaryBytes = try OperationContractCodec.encode(pending)
        #expect(Self.summaryDecodeFailure(try Self.mutate(
            summaryBytes,
            path: ["fingerprint"],
            value: String(repeating: "0", count: 64)
        )) == .summaryFingerprintMismatch)
        #expect(Self.summaryDecodeFailure(try Self.mutate(
            summaryBytes,
            path: ["queuedOperationCount"],
            value: 9
        )) == .summaryFingerprintMismatch)
        #expect(Self.summaryDecodeFailure(try Self.mutate(
            summaryBytes,
            path: ["queuedOperationCount"],
            value: -1
        )) == .invalidEncodedSummary)

        let requestBytes = try OperationContractCodec.encode(destructive)
        #expect(Self.requestDecodeFailure(try Self.mutate(
            requestBytes,
            path: ["fingerprint"],
            value: String(repeating: "0", count: 64)
        )) == .requestFingerprintMismatch)
        #expect(Self.requestDecodeFailure(try Self.mutate(
            requestBytes,
            path: ["destructiveConfirmation", "confirmedSummary", "accountId"],
            value: "account-other"
        )) == .summaryFingerprintMismatch)

        #expect(Self.summaryDecodeFailure(Data("{}".utf8)) == .invalidEncodedSummary)
        #expect(Self.confirmationDecodeFailure(Data("{}".utf8)) ==
            .invalidEncodedConfirmation)
        #expect(Self.requestDecodeFailure(Data("{}".utf8)) == .invalidEncodedRequest)

        let diagnostics: [(SessionEndingFailure, String)] = [
            (.invalidObservedAt, "session_end_observed_at_invalid"),
            (.invalidConfirmedAt, "session_end_confirmed_at_invalid"),
            (.invalidRequestedAt, "session_end_requested_at_invalid"),
            (.pendingWorkRequiresDisposition, "session_end_pending_work_requires_disposition"),
            (.destructiveConfirmationRequired, "session_end_destructive_confirmation_required"),
            (.destructiveConfirmationMismatch, "session_end_destructive_confirmation_mismatch"),
            (.scopeMismatch, "session_end_scope_mismatch"),
            (.summaryChanged, "session_end_pending_summary_changed"),
            (.summaryRegressed, "session_end_pending_summary_regressed"),
            (.summaryFingerprintMismatch, "session_end_pending_summary_fingerprint_mismatch"),
            (.requestFingerprintMismatch, "session_end_request_fingerprint_mismatch"),
            (.synchronizationIncomplete, "session_end_synchronization_incomplete"),
            (.sessionEndFailed, "session_end_failed"),
            (.invalidEncodedSummary, "session_end_pending_summary_encoding_invalid"),
            (.invalidEncodedConfirmation, "session_end_destructive_confirmation_encoding_invalid"),
            (.invalidEncodedRequest, "session_end_request_encoding_invalid")
        ]
        for (failure, code) in diagnostics {
            #expect(failure.diagnosticCode == code)
        }
    }

    @Test("The narrow port ends only policy-ready sessions and never invents completion")
    func referencePortFlow() async throws {
        let pending = try Self.summary(queued: 1, rejected: 1, attachments: 2)
        let adapter = ReferenceAccountSessionEnder(summary: pending)

        let canceled = try SessionEndPolicy.makeRequest(
            choice: .cancel,
            summary: await adapter.pendingWorkSummary(),
            requestedAt: Self.t2
        )
        #expect(canceled == nil)
        #expect(await adapter.endCount == 0)

        let sync = try #require(try SessionEndPolicy.makeRequest(
            choice: .synchronizeThenLogout,
            summary: pending,
            requestedAt: Self.t2
        ))
        do {
            try await adapter.endSession(sync)
            Issue.record("Sync-first session ended while work remained pending")
        } catch let failure as SessionEndingFailure {
            #expect(failure == .synchronizationIncomplete)
        }
        #expect(await adapter.endCount == 0)

        let resolved = try Self.summary(revision: 8, observedAt: Self.t3)
        await adapter.replaceSummary(resolved)
        try await adapter.endSession(sync)
        #expect(await adapter.endCount == 1)
        #expect(await adapter.lastDisposition == .synchronizeThenLogout)

        let destructiveAdapter = ReferenceAccountSessionEnder(summary: pending)
        let destructive = try #require(try SessionEndPolicy.makeRequest(
            choice: .removeFromDeviceDiscardingPendingWork(confirmedAt: Self.t2),
            summary: pending,
            requestedAt: Self.t3
        ))
        await destructiveAdapter.replaceSummary(try Self.summary(
            revision: 8,
            observedAt: Self.t3,
            queued: 2,
            rejected: 1,
            attachments: 2
        ))
        do {
            try await destructiveAdapter.endSession(destructive)
            Issue.record("Changed pending work reused stale destructive confirmation")
        } catch let failure as SessionEndingFailure {
            #expect(failure == .summaryChanged)
        }
        #expect(await destructiveAdapter.endCount == 0)

        let exactDestructiveAdapter = ReferenceAccountSessionEnder(summary: pending)
        try await exactDestructiveAdapter.endSession(destructive)
        #expect(await exactDestructiveAdapter.endCount == 1)
        #expect(await exactDestructiveAdapter.lastDisposition ==
            .removeFromDeviceDiscardingPendingWork)

        let failing = FailingAccountSessionEnder(summary: resolved)
        let clean = try #require(try SessionEndPolicy.makeRequest(
            choice: .ordinaryCleanLogout,
            summary: resolved,
            requestedAt: Self.t4
        ))
        var falseCompletion = false
        do {
            try await failing.endSession(clean)
            falseCompletion = true
        } catch let failure as SessionEndingFailure {
            #expect(failure == .sessionEndFailed)
        }
        #expect(!falseCompletion)
    }

    private static let t0 = Date(timeIntervalSince1970: 1_803_000_000)
    private static let t1 = Date(timeIntervalSince1970: 1_803_000_001)
    private static let t2 = Date(timeIntervalSince1970: 1_803_000_002)
    private static let t3 = Date(timeIntervalSince1970: 1_803_000_003)
    private static let t4 = Date(timeIntervalSince1970: 1_803_000_004)

    private static func summary(
        environment: LedgerEnvironmentKind = .targetStaging,
        principalID: String = "principal-session-end-test",
        accountID: String = "account-session-end-test",
        revision: UInt64 = 7,
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

    private static func expectCanonicalRoundTrip<Value>(
        _ value: Value
    ) throws where Value: Codable & Equatable {
        let bytes = try OperationContractCodec.encode(value)
        let restored = try OperationContractCodec.decode(Value.self, from: bytes)
        #expect(restored == value)
        #expect(try OperationContractCodec.encode(restored) == bytes)
    }

    private static func failure<T>(
        _ operation: () throws -> T
    ) -> SessionEndingFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as SessionEndingFailure {
            return failure
        } catch {
            return nil
        }
    }

    private static func summaryDecodeFailure(_ data: Data) -> SessionEndingFailure? {
        failure {
            try OperationContractCodec.decode(PendingLocalWorkSummary.self, from: data)
        }
    }

    private static func confirmationDecodeFailure(_ data: Data) -> SessionEndingFailure? {
        failure {
            try OperationContractCodec.decode(
                DestructiveLocalRemovalConfirmation.self,
                from: data
            )
        }
    }

    private static func requestDecodeFailure(_ data: Data) -> SessionEndingFailure? {
        failure {
            try OperationContractCodec.decode(SessionEndRequest.self, from: data)
        }
    }

    private static func mutate(
        _ data: Data,
        path: [String],
        value: Any
    ) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SessionEndingFailure.invalidEncodedRequest
        }
        try set(value, path: ArraySlice(path), in: &object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func set(
        _ value: Any,
        path: ArraySlice<String>,
        in object: inout [String: Any]
    ) throws {
        guard let key = path.first else {
            throw SessionEndingFailure.invalidEncodedRequest
        }
        let remainder = path.dropFirst()
        if remainder.isEmpty {
            object[key] = value
            return
        }
        guard var child = object[key] as? [String: Any] else {
            throw SessionEndingFailure.invalidEncodedRequest
        }
        try set(value, path: remainder, in: &child)
        object[key] = child
    }
}

private actor ReferenceAccountSessionEnder: AccountSessionEnding {
    private var summary: PendingLocalWorkSummary
    private(set) var ended: [SessionEndDisposition] = []

    init(summary: PendingLocalWorkSummary) {
        self.summary = summary
    }

    var endCount: Int { ended.count }
    var lastDisposition: SessionEndDisposition? { ended.last }

    func pendingWorkSummary() async throws -> PendingLocalWorkSummary {
        summary
    }

    func replaceSummary(_ replacement: PendingLocalWorkSummary) {
        summary = replacement
    }

    func endSession(_ request: SessionEndRequest) async throws {
        switch try SessionEndPolicy.evaluate(request, against: summary) {
        case .readyForTeardown(let disposition):
            ended.append(disposition)
        case .synchronizationRequired:
            throw SessionEndingFailure.synchronizationIncomplete
        }
    }
}

private struct FailingAccountSessionEnder: AccountSessionEnding {
    let summary: PendingLocalWorkSummary

    func pendingWorkSummary() async throws -> PendingLocalWorkSummary {
        summary
    }

    func endSession(_ request: SessionEndRequest) async throws {
        _ = request
        throw SessionEndingFailure.sessionEndFailed
    }
}
