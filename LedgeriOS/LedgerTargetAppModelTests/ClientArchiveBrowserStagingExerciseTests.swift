import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetAppModel

@Suite("Client Archive Browser Staging Application Flow")
@MainActor
struct ClientArchiveBrowserStagingExerciseTests {
    @Test("Confirmation captures exact current active evidence and stale confirmation makes zero calls")
    func confirmationAndExactSubmission() async throws {
        let browser = try await CAClientBrowserFixture.ready(revision: 7)
        let archive = CAArchiveProbe(behaviors: [.success(.queued)])
        let watches = CAOperationWatchProbe()
        let model = Self.model(browser: browser.model)
        await model.start(runtime: Self.runtime(archive: archive, watches: watches))

        model.requestArchiveConfirmation()
        #expect(model.isConfirmationPresented)
        model.cancelConfirmation()
        #expect((await archive.commands).isEmpty)

        model.requestArchiveConfirmation()
        try browser.yieldDetail(revision: 8, quality: .partial, complete: false, version: "newer")
        await Self.waitUntil {
            browser.model.selectedClientArchiveEvidence?.expectedRevision.rawValue == 8
        }
        await model.confirmArchive()
        #expect((await archive.commands).isEmpty)
        #expect(model.diagnostic == "client_archive_confirmation_stale")

        model.requestArchiveConfirmation()
        await model.confirmArchive()
        let command = try #require((await archive.commands).only)
        #expect(command.envelope.operationId.rawValue == "client-archive-operation-1")
        #expect(command.envelope.accountId == Self.accountId)
        #expect(command.envelope.actorPrincipalId == Self.principalId)
        #expect(command.envelope.contractVersion == Self.contractVersion)
        #expect(command.envelope.clientCreatedAt == Self.capturedAt)
        #expect(command.draft.clientId == Self.clientId)
        #expect(command.draft.expectedRevision == ExpectedClientRevision(8))
        #expect(model.operationStateLabel == "queued")
        await Self.waitUntil { watches.ids == ["client-archive-operation-1"] }
        await model.stop()
        await browser.stop()
    }

    @Test("Ambiguous local acceptance retries byte-identical command evidence")
    func ambiguousRetry() async throws {
        let browser = try await CAClientBrowserFixture.ready(revision: 7)
        let archive = CAArchiveProbe(behaviors: [
            .failure(ClientArchiveFailure.localAcceptanceFailed),
            .success(.queued)
        ])
        let watches = CAOperationWatchProbe()
        let model = Self.model(browser: browser.model)
        await model.start(runtime: Self.runtime(archive: archive, watches: watches))
        model.requestArchiveConfirmation()
        await model.confirmArchive()
        #expect(model.canRetryAmbiguousAcceptance)
        await model.retryAmbiguousAcceptance()
        let commands = await archive.commands
        #expect(commands.count == 2)
        #expect(commands[0] == commands[1])
        #expect(!model.canRetryAmbiguousAcceptance)
        await model.stop()
        await browser.stop()
    }

    @Test("All six operation states remain exact and rejection requires refreshed active evidence")
    func operationStatesAndRejectedRecovery() async throws {
        let browser = try await CAClientBrowserFixture.ready(revision: 7)
        let archive = CAArchiveProbe(behaviors: [.success(.queued), .success(.queued)])
        let watches = CAOperationWatchProbe()
        let identities = CAIdentitySequence([
            "client-archive-operation-1", "client-archive-operation-2"
        ])
        let model = Self.model(browser: browser.model, identities: identities)
        await model.start(runtime: Self.runtime(archive: archive, watches: watches))
        model.requestArchiveConfirmation()
        await model.confirmArchive()
        let first = try #require((await archive.commands).only)
        let source = watches.source(for: first.envelope.operationId)
        await Self.waitUntil { watches.ids.count == 1 }

        let applied = Self.appliedResult(revision: 8)
        let rejected = Self.rejection()
        let states: [(OperationState, String)] = [
            (.queued(attemptCount: 0, lastTransientError: nil), "queued"),
            (.applying(attempt: 1, startedAt: Self.capturedAt.addingTimeInterval(1)), "applying"),
            (.applied(applied), "applied"),
            (.superseded(
                original: applied,
                correction: CorrectionReference(
                    operationId: first.envelope.operationId,
                    correctedAt: Self.capturedAt.addingTimeInterval(3)
                )
            ), "superseded"),
            (.resolved(
                rejection: rejected,
                resolution: RejectionResolution(
                    code: try ResolutionCode(validating: "conflict_resolved"),
                    resolvedAt: Self.capturedAt.addingTimeInterval(4)
                )
            ), "resolved"),
            (.rejected(rejected), "rejected")
        ]
        for (index, value) in states.enumerated() {
            source.yield(Self.snapshot(
                command: first, state: value.0,
                updatedAt: Self.capturedAt.addingTimeInterval(Double(index + 1))
            ))
            await Self.waitUntil { model.operationStateLabel == value.1 }
        }
        #expect(!model.canRetryRejectedArchive)
        model.requestRejectedRetryConfirmation()
        #expect(model.diagnostic == "client_archive_refreshed_evidence_required")

        try browser.yieldDetail(revision: 8, version: "refresh")
        await Self.waitUntil { model.canRetryRejectedArchive }
        model.requestRejectedRetryConfirmation()
        await model.confirmArchive()
        let commands = await archive.commands
        #expect(commands.count == 2)
        #expect(commands[1].envelope.operationId.rawValue == "client-archive-operation-2")
        #expect(commands[1].draft.expectedRevision == ExpectedClientRevision(8))
        await model.stop()
        await browser.stop()
    }

    @Test("Archived, absent, waiting, and stale-selection evidence refuse with zero calls")
    func invalidEvidenceRefuses() async throws {
        let browser = try await CAClientBrowserFixture.ready(revision: 7)
        let archive = CAArchiveProbe(behaviors: [.success(.queued)])
        let watches = CAOperationWatchProbe()
        let model = Self.model(browser: browser.model)
        await model.start(runtime: Self.runtime(archive: archive, watches: watches))

        try browser.yieldClient(lifecycle: .archived, revision: 8, version: "archived")
        await Self.waitUntil { browser.model.selectedClientArchiveEvidence == nil }
        model.requestArchiveConfirmation()
        #expect(!model.isConfirmationPresented)
        #expect(model.diagnostic == "client_archive_current_evidence_required")
        #expect((await archive.commands).isEmpty)

        try browser.yieldEmpty(complete: true, quality: .ready, version: "absent")
        await Self.waitUntil { browser.model.detailStateLabel == "authoritative absence" }
        model.requestArchiveConfirmation()
        #expect((await archive.commands).isEmpty)

        try browser.yieldWaiting()
        await Self.waitUntil { browser.model.detailStateLabel == "waiting" }
        model.requestArchiveConfirmation()
        #expect((await archive.commands).isEmpty)

        await model.selectionDidChange()
        #expect(!model.canRequestArchive)
        #expect((await archive.commands).isEmpty)
        await model.stop()
        await browser.stop()
    }

    @Test("Invalid operation evidence and stop cancel and drain operation observation")
    func invalidEvidenceAndDrainage() async throws {
        let browser = try await CAClientBrowserFixture.ready(revision: 7)
        let archive = CAArchiveProbe(behaviors: [.success(.queued)])
        let watches = CAOperationWatchProbe()
        let model = Self.model(browser: browser.model)
        await model.start(runtime: Self.runtime(archive: archive, watches: watches))
        model.requestArchiveConfirmation()
        await model.confirmArchive()
        let command = try #require((await archive.commands).only)
        let source = watches.source(for: command.envelope.operationId)
        await Self.waitUntil { watches.ids.count == 1 }
        source.yield(OperationSnapshot(
            operationId: try OperationID(validating: "wrong-operation"),
            accountId: Self.accountId,
            contractVersion: Self.contractVersion,
            fingerprint: command.fingerprint,
            acceptedAt: Self.capturedAt,
            updatedAt: Self.capturedAt,
            state: .queued(attemptCount: 0, lastTransientError: nil)
        ))
        await Self.waitUntil { model.diagnostic == "client_archive_operation_evidence_invalid" }
        await Self.waitUntil { source.terminationCount == 1 }
        await model.stop()
        #expect(source.terminationCount == 1)
        await browser.stop()
    }

    @Test("Unavailable, uncached, and directory/detail mismatch evidence dispatch nothing")
    func unavailableAndMismatchedEvidenceRefuses() async throws {
        let browser = try await CAClientBrowserFixture.ready(revision: 7)
        let archive = CAArchiveProbe(behaviors: [.success(.queued)])
        let watches = CAOperationWatchProbe()
        let model = Self.model(browser: browser.model)
        await model.start(runtime: Self.runtime(archive: archive, watches: watches))

        try browser.yieldFailure(.unavailable, cachedRevision: nil, version: "unavailable")
        await Self.waitUntil { browser.model.detailStateLabel == "unavailable" }
        model.requestArchiveConfirmation()
        #expect(!model.isConfirmationPresented)
        #expect((await archive.commands).isEmpty)

        try browser.yieldFailure(.retryable, cachedRevision: nil, version: "retryable")
        await Self.waitUntil { browser.model.detailStateLabel == "retryable • uncached" }
        model.requestArchiveConfirmation()
        #expect((await archive.commands).isEmpty)

        try browser.yieldDirectoryNameMismatch()
        await Self.waitUntil { browser.model.selectedClientArchiveEvidence == nil }
        model.requestArchiveConfirmation()
        #expect((await archive.commands).isEmpty)
        await model.stop()
        await browser.stop()
    }

    @Test("Cached stale active detail admits offline archive with its exact represented revision")
    func cachedStaleActiveEvidenceDispatchesExactly() async throws {
        let browser = try await CAClientBrowserFixture.ready(revision: 7)
        let archive = CAArchiveProbe(behaviors: [.success(.queued)])
        let watches = CAOperationWatchProbe()
        let model = Self.model(browser: browser.model)
        await model.start(runtime: Self.runtime(archive: archive, watches: watches))

        try browser.yieldFailure(.retryable, cachedRevision: 11, version: "cached-active-11")
        await Self.waitUntil {
            browser.model.detailStateLabel == "retryable • cached"
                && browser.model.selectedClientArchiveEvidence?.expectedRevision.rawValue == 11
        }
        #expect(model.canRequestArchive)
        model.requestArchiveConfirmation()
        await model.confirmArchive()
        let command = try #require((await archive.commands).only)
        #expect(command.draft.clientId == Self.clientId)
        #expect(command.draft.expectedRevision == ExpectedClientRevision(11))
        #expect(command.envelope.preconditions == [
            .expectedRevision(
                subject: LedgerEntityReference(
                    kind: .client,
                    id: try EntityID(validating: Self.clientId.rawValue)
                ),
                revision: 11
            )
        ])
        #expect((await archive.commands).count == 1)
        await model.stop()
        await browser.stop()
    }

    @Test("Selection change and restart drain watches and ignore stale noncooperative emissions")
    func selectionRestartAndStaleEmissionDrainage() async throws {
        let browser = try await CAClientBrowserFixture.ready(revision: 7)
        let archive = CAArchiveProbe(behaviors: [.success(.queued)])
        let firstWatches = CAOperationWatchProbe()
        let model = Self.model(browser: browser.model)
        await model.start(runtime: Self.runtime(archive: archive, watches: firstWatches))
        model.requestArchiveConfirmation()
        await model.confirmArchive()
        let command = try #require((await archive.commands).only)
        let firstSource = firstWatches.source(for: command.envelope.operationId)
        await Self.waitUntil { firstWatches.ids.count == 1 }

        await model.selectionDidChange()
        #expect(firstSource.terminationCount == 1)
        firstSource.yield(Self.snapshot(
            command: command,
            state: .applied(Self.appliedResult(revision: 8)),
            updatedAt: Self.capturedAt.addingTimeInterval(2)
        ))
        try? await Task.sleep(for: .milliseconds(10))
        #expect(model.operationStateLabel == "queued")

        let restartWatches = CAOperationWatchProbe()
        await model.start(runtime: Self.runtime(archive: archive, watches: restartWatches))
        #expect(model.operationStateLabel == "not submitted")
        #expect(model.operationIdLabel == nil)
        #expect(firstSource.terminationCount == 1)

        let gate = CAArchiveGate()
        let blockedWatches = CAOperationWatchProbe()
        let blocked = Self.model(
            browser: browser.model,
            identities: CAIdentitySequence(["client-archive-operation-blocked"])
        )
        await blocked.start(runtime: ClientArchiveBrowserStagingRuntime(
            archive: { command in
                await gate.wait()
                return OperationReceipt(
                    operationId: command.envelope.operationId,
                    localState: .queued
                )
            },
            watchOperation: { blockedWatches.watch($0) }
        ))
        blocked.requestArchiveConfirmation()
        let submission = Task { await blocked.confirmArchive() }
        await gate.waitUntilEntered()
        await blocked.stop()
        await gate.release()
        await submission.value
        #expect(blocked.operationStateLabel == "stopped")
        #expect(blocked.operationIdLabel == nil)
        #expect(blockedWatches.ids.isEmpty)
        await model.stop()
        await browser.stop()
    }

    @Test("Runtime-close failures remain bounded during acceptance and observation")
    func runtimeCloseBehavior() async throws {
        let browser = try await CAClientBrowserFixture.ready(revision: 7)
        let model = Self.model(browser: browser.model)
        await model.start(runtime: ClientArchiveBrowserStagingRuntime(
            archive: { _ in throw CARuntimeClosedFailure() },
            watchOperation: { _ in
                AsyncThrowingStream { $0.finish(
                    throwing: CARuntimeClosedFailure()
                ) }
            }
        ))
        model.requestArchiveConfirmation()
        await model.confirmArchive()
        #expect(model.diagnostic == "client_archive_local_acceptance_failed")
        #expect(model.canRetryAmbiguousAcceptance)
        await model.stop()

        let archive = CAArchiveProbe(behaviors: [.success(.queued)])
        let observed = Self.model(
            browser: browser.model,
            identities: CAIdentitySequence(["client-archive-operation-runtime-close"])
        )
        await observed.start(runtime: ClientArchiveBrowserStagingRuntime(
            archive: { try await archive.archive($0) },
            watchOperation: { _ in
                AsyncThrowingStream { $0.finish(
                    throwing: CARuntimeClosedFailure()
                ) }
            }
        ))
        observed.requestArchiveConfirmation()
        await observed.confirmArchive()
        await Self.waitUntil {
            observed.diagnostic == "client_archive_operation_local_failed"
        }
        #expect(observed.operationStateLabel == "queued")
        await observed.stop()
        await browser.stop()
    }

    fileprivate static let accountId = try! AccountID(validating: "archive-account")
    fileprivate static let principalId = try! PrincipalID(validating: "archive-principal")
    fileprivate static let clientId = try! ClientID(validating: "archive-client")
    fileprivate static let contractVersion = try! OperationContractVersion(
        validating: "client-archive-v1"
    )
    fileprivate static let capturedAt = Date(timeIntervalSince1970: 1_804_100_000)

    private static func model(
        browser: ClientBrowsingStagingExercise,
        identities: CAIdentitySequence = CAIdentitySequence(["client-archive-operation-1"])
    ) -> ClientArchiveBrowserStagingExercise {
        ClientArchiveBrowserStagingExercise(
            accountId: accountId,
            actorPrincipalId: principalId,
            operationContractVersion: contractVersion,
            browser: browser,
            makeIdentity: { try identities.next() },
            now: { capturedAt }
        )
    }

    private static func runtime(
        archive: CAArchiveProbe,
        watches: CAOperationWatchProbe
    ) -> ClientArchiveBrowserStagingRuntime {
        ClientArchiveBrowserStagingRuntime(
            archive: { try await archive.archive($0) },
            watchOperation: { watches.watch($0) }
        )
    }

    private static func snapshot(
        command: ArchiveClientCommand,
        state: OperationState,
        updatedAt: Date
    ) -> OperationSnapshot {
        OperationSnapshot(
            operationId: command.envelope.operationId,
            accountId: command.envelope.accountId,
            contractVersion: command.envelope.contractVersion,
            fingerprint: command.fingerprint,
            acceptedAt: command.envelope.clientCreatedAt,
            updatedAt: updatedAt,
            state: state
        )
    }

    private static func appliedResult(revision: UInt64) -> AppliedOperationResult {
        AppliedOperationResult(
            resultCode: try! ApplicationResultCode(validating: "client_archived"),
            serverReceivedAt: capturedAt.addingTimeInterval(1),
            completedAt: capturedAt.addingTimeInterval(2),
            affectedRevisions: [
                EntityRevision(
                    entity: LedgerEntityReference(
                        kind: .client,
                        id: try! EntityID(validating: clientId.rawValue)
                    ),
                    revision: revision
                )
            ]
        )
    }

    private static func rejection() -> OperationRejection {
        OperationRejection(
            error: ApplicationErrorSummary(
                code: try! ApplicationErrorCode(validating: "client_revision_conflict"),
                category: .conflict,
                retryDisposition: .afterUserCorrection
            ),
            rejectedAt: capturedAt.addingTimeInterval(2),
            conflictingEntities: [
                LedgerEntityReference(
                    kind: .client,
                    id: try! EntityID(validating: clientId.rawValue)
                )
            ]
        )
    }

    fileprivate static func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<2_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Timed out waiting for Client archive browser state")
    }
}

private final class CAIdentitySequence {
    private var values: [String]
    init(_ values: [String]) { self.values = values }
    @MainActor func next() throws -> ClientArchiveSubmissionIdentity {
        ClientArchiveSubmissionIdentity(
            operationId: try OperationID(validating: values.removeFirst())
        )
    }
}

private struct CARuntimeClosedFailure: Error {}

private actor CAArchiveProbe {
    enum Behavior: @unchecked Sendable {
        case success(LocalOperationState)
        case failure(Error)
    }
    private var behaviors: [Behavior]
    private(set) var commands: [ArchiveClientCommand] = []
    init(behaviors: [Behavior]) { self.behaviors = behaviors }
    func archive(_ command: ArchiveClientCommand) throws -> OperationReceipt {
        commands.append(command)
        guard !behaviors.isEmpty else { throw ClientArchiveFailure.localAcceptanceFailed }
        switch behaviors.removeFirst() {
        case .success(let state):
            return OperationReceipt(operationId: command.envelope.operationId, localState: state)
        case .failure(let error): throw error
        }
    }
}

private final class CAOperationWatchProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var watched: [String] = []
    private var sources: [String: CAControlledStream<OperationSnapshot>] = [:]
    var ids: [String] { lock.withLock { watched } }
    func source(for id: OperationID) -> CAControlledStream<OperationSnapshot> {
        lock.withLock {
            if let source = sources[id.rawValue] { return source }
            let source = CAControlledStream<OperationSnapshot>()
            sources[id.rawValue] = source
            return source
        }
    }
    func watch(_ id: OperationID) -> AsyncThrowingStream<OperationSnapshot, Error> {
        lock.withLock {
            watched.append(id.rawValue)
            if let source = sources[id.rawValue] { return source.stream }
            let source = CAControlledStream<OperationSnapshot>()
            sources[id.rawValue] = source
            return source.stream
        }
    }
}

private final class CAControlledStream<Value: Sendable>: @unchecked Sendable {
    let stream: AsyncThrowingStream<Value, Error>
    private let continuation: AsyncThrowingStream<Value, Error>.Continuation
    private let termination = CATerminationProbe()
    init() {
        var captured: AsyncThrowingStream<Value, Error>.Continuation?
        let termination = termination
        stream = AsyncThrowingStream { continuation in
            captured = continuation
            continuation.onTermination = { _ in termination.record() }
        }
        continuation = captured!
    }
    var terminationCount: Int { termination.count }
    func yield(_ value: Value) { continuation.yield(value) }
    func finish() { continuation.finish() }
}

private final class CATerminationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func record() { lock.withLock { value += 1 } }
}

private actor CAArchiveGate {
    private var entered = false
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        entered = true
        if released { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func waitUntilEntered() async {
        while !entered { await Task.yield() }
    }

    func release() {
        released = true
        let current = waiters
        waiters.removeAll()
        current.forEach { $0.resume() }
    }
}

@MainActor
private final class CAClientBrowserFixture {
    let model: ClientBrowsingStagingExercise
    private let directory = CAControlledStream<ClientListSnapshot>()
    private let details = CAClientDetailProbe()

    private init() {
        model = ClientBrowsingStagingExercise(
            accountId: ClientArchiveBrowserStagingExerciseTests.accountId
        )
    }

    static func ready(revision: UInt64) async throws -> CAClientBrowserFixture {
        let fixture = CAClientBrowserFixture()
        await fixture.model.start(runtime: ClientBrowsingStagingRuntime(
            watchClients: { fixture.directory.stream },
            watchClient: { fixture.details.watch($0) }
        ))
        fixture.directory.yield(try fixture.directorySnapshot(lifecycle: .active))
        await ClientArchiveBrowserStagingExerciseTests.waitUntil {
            fixture.model.activeClients.count == 1
        }
        await fixture.model.select(
            clientId: ClientArchiveBrowserStagingExerciseTests.clientId,
            segment: .active
        )
        await ClientArchiveBrowserStagingExerciseTests.waitUntil {
            fixture.details.requests.count == 1
        }
        try fixture.yieldDetail(revision: revision, version: "initial")
        await ClientArchiveBrowserStagingExerciseTests.waitUntil {
            fixture.model.selectedClientArchiveEvidence?.expectedRevision.rawValue == revision
        }
        return fixture
    }

    func yieldDetail(
        revision: UInt64,
        quality: ListSnapshotQuality = .ready,
        complete: Bool = true,
        version: String
    ) throws {
        try yieldClient(
            lifecycle: .active, revision: revision, quality: quality,
            complete: complete, version: version
        )
    }

    func yieldClient(
        lifecycle: DirectoryLifecycleState,
        revision: UInt64,
        quality: ListSnapshotQuality = .ready,
        complete: Bool = true,
        version: String
    ) throws {
        let request = try #require(details.requests.last)
        let client = try summary(lifecycle: lifecycle)
        details.yield(try ClientCoreDetailsUpdate(
            request: request,
            state: .snapshot(try local(
                request: request,
                rows: [ClientCoreDetailsSnapshot(
                    client: client,
                    locallyObservedRevision: ExpectedClientRevision(revision)
                )],
                complete: complete,
                quality: quality,
                version: version
            ))
        ))
    }

    func yieldEmpty(
        complete: Bool,
        quality: ListSnapshotQuality,
        version: String
    ) throws {
        let request = try #require(details.requests.last)
        details.yield(try ClientCoreDetailsUpdate(
            request: request,
            state: .snapshot(try local(
                request: request, rows: [], complete: complete,
                quality: quality, version: version
            ))
        ))
    }

    func yieldWaiting() throws {
        let request = try #require(details.requests.last)
        details.yield(try ClientCoreDetailsUpdate(request: request, state: .waiting(.loading)))
    }

    func yieldFailure(
        _ failure: ListFailureState,
        cachedRevision: UInt64?,
        version: String
    ) throws {
        let request = try #require(details.requests.last)
        let cached: ClientCoreDetailsLocalSnapshot? = try cachedRevision.map {
            try local(
                request: request,
                rows: [ClientCoreDetailsSnapshot(
                    client: try summary(lifecycle: .active),
                    locallyObservedRevision: ExpectedClientRevision($0)
                )],
                complete: false,
                quality: .stale,
                version: version
            )
        }
        details.yield(try ClientCoreDetailsUpdate(
            request: request,
            state: .failed(failure: failure, cached: cached)
        ))
    }

    func yieldDirectoryNameMismatch() throws {
        let mismatch = try summary(lifecycle: .active, displayName: "Different Name")
        directory.yield(try ClientListSnapshot(
            accountId: ClientArchiveBrowserStagingExerciseTests.accountId,
            local: ListLocalSnapshot(
                queryFingerprint: ListQueryFingerprint(validating: String(repeating: "b", count: 64)),
                rows: [mismatch], visibleRowCountBeforeFiltering: 1,
                isCompleteForQuery: true, quality: .ready,
                localDataVersion: LocalDataVersion(validating: "directory-mismatch"),
                asOf: ClientArchiveBrowserStagingExerciseTests.capturedAt
            )
        ))
    }

    func stop() async { await model.stop() }

    private func summary(
        lifecycle: DirectoryLifecycleState,
        id: ClientID = ClientArchiveBrowserStagingExerciseTests.clientId,
        displayName: String = "Archive Client"
    ) throws -> ClientSummary {
        try ClientSummary(
            id: id,
            accountId: ClientArchiveBrowserStagingExerciseTests.accountId,
            displayName: ClientDisplayName(validating: displayName),
            lifecycle: lifecycle,
            createdAt: ClientArchiveBrowserStagingExerciseTests.capturedAt.addingTimeInterval(-20),
            updatedAt: ClientArchiveBrowserStagingExerciseTests.capturedAt.addingTimeInterval(-10)
        )
    }

    private func directorySnapshot(lifecycle: DirectoryLifecycleState) throws -> ClientListSnapshot {
        let row = try summary(lifecycle: lifecycle)
        return try ClientListSnapshot(
            accountId: ClientArchiveBrowserStagingExerciseTests.accountId,
            local: ListLocalSnapshot(
                queryFingerprint: ListQueryFingerprint(validating: String(repeating: "a", count: 64)),
                rows: [row], visibleRowCountBeforeFiltering: 1,
                isCompleteForQuery: true, quality: .ready,
                localDataVersion: LocalDataVersion(validating: "directory"),
                asOf: ClientArchiveBrowserStagingExerciseTests.capturedAt
            )
        )
    }

    private func local(
        request: ClientCoreDetailsRequest,
        rows: [ClientCoreDetailsSnapshot],
        complete: Bool,
        quality: ListSnapshotQuality,
        version: String
    ) throws -> ClientCoreDetailsLocalSnapshot {
        try ClientCoreDetailsLocalSnapshot(
            request: request, rows: rows,
            visibleRowCountBeforeFiltering: rows.count,
            isCompleteForQuery: complete, quality: quality,
            localDataVersion: LocalDataVersion(validating: version),
            asOf: ClientArchiveBrowserStagingExerciseTests.capturedAt
        )
    }
}

private final class CAClientDetailProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ClientCoreDetailsRequest] = []
    private var source: CAControlledStream<ClientCoreDetailsUpdate>?
    var requests: [ClientCoreDetailsRequest] { lock.withLock { recorded } }
    func watch(_ request: ClientCoreDetailsRequest) -> AsyncThrowingStream<ClientCoreDetailsUpdate, Error> {
        lock.withLock {
            recorded.append(request)
            let next = CAControlledStream<ClientCoreDetailsUpdate>()
            source = next
            return next.stream
        }
    }
    func yield(_ update: ClientCoreDetailsUpdate) { lock.withLock { source }?.yield(update) }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
