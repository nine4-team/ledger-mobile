import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetAppModel

@Suite("Project Archive Browser Staging Application Flow")
@MainActor
struct ProjectArchiveBrowserStagingExerciseTests {
    @Test("Confirmation is exact current evidence and cancellation dispatches nothing")
    func confirmationAndStaleEvidence() async throws {
        let browser = try await BrowserFixture.ready(revision: 7)
        let archive = ArchiveProbe(behaviors: [.success(.queued), .success(.queued)])
        let operations = OperationWatchProbe()
        let model = Self.model(browser: browser.model)
        await model.start(runtime: Self.runtime(archive: archive, operations: operations))

        model.requestArchiveConfirmation()
        #expect(model.isConfirmationPresented)
        model.cancelConfirmation()
        #expect(!model.isConfirmationPresented)
        #expect(await archive.recordedCommands().isEmpty)

        model.requestArchiveConfirmation()
        try browser.yieldDetail(revision: 8, version: "revision-eight")
        await Self.waitUntil {
            browser.model.selectedProjectArchiveEvidence?.expectedRevision.rawValue == 8
        }
        await model.confirmArchive()
        #expect(await archive.recordedCommands().isEmpty)
        #expect(model.diagnostic == "project_archive_confirmation_stale")
        #expect(!model.isConfirmationPresented)

        await model.stop()
        await browser.stop()
    }

    @Test("Exact current Project revision and operation metadata dispatch once")
    func exactSubmissionAndSimultaneousConfirm() async throws {
        let browser = try await BrowserFixture.ready(revision: 7)
        let archive = ArchiveProbe(behaviors: [.success(.queued)])
        let operations = OperationWatchProbe()
        let model = Self.model(browser: browser.model)
        await model.start(runtime: Self.runtime(archive: archive, operations: operations))
        model.requestArchiveConfirmation()

        async let first: Void = model.confirmArchive()
        async let second: Void = model.confirmArchive()
        _ = await (first, second)
        let commands = await archive.recordedCommands()
        let command = try #require(commands.only)
        #expect(command.envelope.operationId.rawValue == "archive-operation-1")
        #expect(command.envelope.accountId == Self.accountId)
        #expect(command.envelope.actorPrincipalId == Self.principalId)
        #expect(command.envelope.contractVersion == Self.contractVersion)
        #expect(command.envelope.clientCreatedAt == Self.capturedAt)
        #expect(command.envelope.payload.projectId == Self.projectId)
        #expect(command.draft.expectedRevision.rawValue == 7)
        #expect(model.operationStateLabel == "queued")
        #expect(model.operationIdLabel == "archive-operation-1")
        #expect(!model.canRequestArchive)
        await Self.waitUntil { operations.ids == ["archive-operation-1"] }

        await model.stop()
        await browser.stop()
    }

    @Test("Live fractional capture time is normalized before command fingerprinting")
    func fractionalCaptureTimeIsMillisecondCanonical() async throws {
        let browser = try await BrowserFixture.ready(revision: 7)
        let archive = ArchiveProbe(behaviors: [.success(.queued)])
        let operations = OperationWatchProbe()
        let fractional = Date(timeIntervalSince1970: 1_804_100_000.123_789)
        let model = Self.model(
            browser: browser.model,
            now: { fractional }
        )
        await model.start(runtime: Self.runtime(archive: archive, operations: operations))
        model.requestArchiveConfirmation()
        await model.confirmArchive()

        let command = try #require((await archive.recordedCommands()).only)
        #expect(command.envelope.clientCreatedAt == Date(
            timeIntervalSince1970: 1_804_100_000.123
        ))
        let encoded = try OperationContractCodec.encode(command.envelope)
        #expect(String(decoding: encoded, as: UTF8.self).contains(
            "\"clientCreatedAt\":1804100000123"
        ))

        await model.stop()
        await browser.stop()
    }

    @Test("Ambiguous local acceptance retry replays byte-identical command evidence")
    func ambiguousRetryIsByteIdentical() async throws {
        let browser = try await BrowserFixture.ready(revision: 7)
        let archive = ArchiveProbe(behaviors: [
            .failure(ProjectArchiveFailure.localAcceptanceFailed),
            .success(.queued)
        ])
        let operations = OperationWatchProbe()
        let model = Self.model(browser: browser.model)
        await model.start(runtime: Self.runtime(archive: archive, operations: operations))
        model.requestArchiveConfirmation()
        await model.confirmArchive()
        #expect(model.canRetryAmbiguousAcceptance)
        #expect(model.diagnostic == ProjectArchiveFailure.localAcceptanceFailed.diagnosticCode)

        await model.retryAmbiguousAcceptance()
        let commands = await archive.recordedCommands()
        #expect(commands.count == 2)
        #expect(commands[0] == commands[1])
        #expect(!model.canRetryAmbiguousAcceptance)
        #expect(model.operationStateLabel == "queued")

        await model.stop()
        await browser.stop()
    }

    @Test("All six local operation states remain exact presentation truth")
    func allOperationStates() async throws {
        let browser = try await BrowserFixture.ready(revision: 7)
        let archive = ArchiveProbe(behaviors: [.success(.queued)])
        let operations = OperationWatchProbe()
        let model = Self.model(browser: browser.model)
        await model.start(runtime: Self.runtime(archive: archive, operations: operations))
        model.requestArchiveConfirmation()
        await model.confirmArchive()
        let command = try #require((await archive.recordedCommands()).only)
        let source = operations.source(for: command.envelope.operationId)
        await Self.waitUntil { operations.ids.count == 1 }

        let result = Self.appliedResult(revision: 8)
        let rejection = Self.rejection()
        let states: [(OperationState, String)] = [
            (.queued(attemptCount: 0, lastTransientError: nil), "queued"),
            (.applying(attempt: 1, startedAt: Self.capturedAt.addingTimeInterval(1)), "applying"),
            (.applied(result), "applied"),
            (.rejected(rejection), "rejected"),
            (.superseded(
                original: result,
                correction: CorrectionReference(
                    operationId: command.envelope.operationId,
                    correctedAt: Self.capturedAt.addingTimeInterval(4)
                )
            ), "superseded"),
            (.resolved(
                rejection: rejection,
                resolution: RejectionResolution(
                    code: try ResolutionCode(validating: "retry_resolved"),
                    resolvedAt: Self.capturedAt.addingTimeInterval(5)
                )
            ), "resolved")
        ]
        for (index, state) in states.enumerated() {
            source.yield(Self.snapshot(
                command: command,
                state: state.0,
                updatedAt: Self.capturedAt.addingTimeInterval(Double(index + 1))
            ))
            await Self.waitUntil { model.operationStateLabel == state.1 }
            #expect(model.operationStateLabel == state.1)
        }

        await model.stop()
        #expect(source.terminationCount == 1)
        await browser.stop()
    }

    @Test("Mismatched operation evidence fails closed and drains its source")
    func invalidOperationEvidence() async throws {
        let browser = try await BrowserFixture.ready(revision: 7)
        let archive = ArchiveProbe(behaviors: [.success(.queued)])
        let operations = OperationWatchProbe()
        let model = Self.model(browser: browser.model)
        await model.start(runtime: Self.runtime(archive: archive, operations: operations))
        model.requestArchiveConfirmation()
        await model.confirmArchive()
        let command = try #require((await archive.recordedCommands()).only)
        let source = operations.source(for: command.envelope.operationId)
        await Self.waitUntil { operations.ids.count == 1 }
        let other = try OperationID(validating: "other-operation")
        source.yield(OperationSnapshot(
            operationId: other,
            accountId: Self.accountId,
            contractVersion: Self.contractVersion,
            fingerprint: command.fingerprint,
            acceptedAt: Self.capturedAt,
            updatedAt: Self.capturedAt,
            state: .queued(attemptCount: 0, lastTransientError: nil)
        ))
        await Self.waitUntil {
            model.diagnostic == "project_archive_operation_evidence_invalid"
        }
        await Self.waitUntil { source.terminationCount == 1 }
        #expect(source.terminationCount == 1)

        await model.stop()
        await browser.stop()
    }

    @Test("Rejected conflict requires refreshed active evidence and a new identity")
    func rejectedRetryRequiresRefresh() async throws {
        let browser = try await BrowserFixture.ready(revision: 7)
        let archive = ArchiveProbe(behaviors: [.success(.queued), .success(.queued)])
        let operations = OperationWatchProbe()
        let identities = IdentitySequence(["archive-operation-1", "archive-operation-2"])
        let model = Self.model(browser: browser.model, identities: identities)
        await model.start(runtime: Self.runtime(archive: archive, operations: operations))
        model.requestArchiveConfirmation()
        await model.confirmArchive()
        let first = try #require((await archive.recordedCommands()).only)
        let firstSource = operations.source(for: first.envelope.operationId)
        await Self.waitUntil { operations.ids.count == 1 }
        firstSource.yield(Self.snapshot(
            command: first,
            state: .rejected(Self.rejection()),
            updatedAt: Self.capturedAt.addingTimeInterval(1)
        ))
        await Self.waitUntil { model.operationStateLabel == "rejected" }
        #expect(!model.canRetryRejectedArchive)
        #expect(!model.canRequestArchive)
        model.requestRejectedRetryConfirmation()
        #expect(model.diagnostic == "project_archive_refreshed_evidence_required")

        try browser.yieldDetail(revision: 8, version: "conflict-refresh")
        await Self.waitUntil { model.canRetryRejectedArchive }
        model.requestRejectedRetryConfirmation()
        #expect(model.isConfirmationPresented)
        await model.confirmArchive()
        let commands = await archive.recordedCommands()
        #expect(commands.count == 2)
        #expect(commands[0].envelope.operationId.rawValue == "archive-operation-1")
        #expect(commands[1].envelope.operationId.rawValue == "archive-operation-2")
        #expect(commands[1].draft.expectedRevision.rawValue == 8)
        #expect(firstSource.terminationCount == 1)

        await model.stop()
        await browser.stop()
    }

    @Test("Applied terminal state blocks stale evidence without locking later revisions")
    func appliedTerminalStateReleasesSubmissionWithoutDuplicate() async throws {
        let browser = try await BrowserFixture.ready(revision: 7)
        let archive = ArchiveProbe(behaviors: [.success(.queued)])
        let operations = OperationWatchProbe()
        let model = Self.model(browser: browser.model)
        await model.start(runtime: Self.runtime(archive: archive, operations: operations))
        model.requestArchiveConfirmation()
        await model.confirmArchive()
        let command = try #require((await archive.recordedCommands()).only)
        let source = operations.source(for: command.envelope.operationId)
        await Self.waitUntil { operations.ids.count == 1 }

        source.yield(Self.snapshot(
            command: command,
            state: .applied(Self.appliedResult(revision: 8)),
            updatedAt: Self.capturedAt.addingTimeInterval(2)
        ))
        await Self.waitUntil { model.operationStateLabel == "applied" }
        #expect(!model.canRequestArchive)

        try browser.yieldDetail(revision: 8, version: "post-apply-authoritative-refresh")
        await Self.waitUntil {
            browser.model.selectedProjectArchiveEvidence?.expectedRevision.rawValue == 8
        }
        #expect(model.canRequestArchive)

        await model.stop()
        await browser.stop()
    }

    @Test("Only represented active content admits confirmation across offline quality states")
    func admissionMatrix() async throws {
        let browser = try await BrowserFixture.ready(revision: 7)
        let model = Self.model(browser: browser.model)
        await model.start(runtime: Self.runtime(
            archive: ArchiveProbe(behaviors: []),
            operations: OperationWatchProbe()
        ))

        for quality in [ListSnapshotQuality.ready, .partial, .stale] {
            try browser.yieldDetail(
                revision: 7,
                quality: quality,
                complete: quality == .ready,
                version: "quality-\(quality.rawValue)"
            )
            await Self.waitUntil { browser.model.selectedProjectArchiveEvidence != nil }
            #expect(model.canRequestArchive)
        }

        try browser.yieldCachedFailure(.retryable, revision: 7, version: "retryable-cache")
        await Self.waitUntil { browser.model.detailStateLabel == "retryable • cached" }
        #expect(model.canRequestArchive)
        try browser.yieldCachedFailure(.requiredUpdate, revision: 7, version: "update-cache")
        await Self.waitUntil { browser.model.detailStateLabel == "required update • cached" }
        #expect(model.canRequestArchive)

        browser.yield(try ProjectCoreDetailsUpdate(
            request: try #require(browser.request),
            state: .waiting(.loading)
        ))
        await Self.waitUntil { browser.model.detailStateLabel == "waiting" }
        #expect(!model.canRequestArchive)
        try browser.yieldEmpty(quality: .partial, complete: false, version: "incomplete")
        await Self.waitUntil { browser.model.detailStateLabel == "incomplete" }
        #expect(!model.canRequestArchive)
        try browser.yieldCachedFailure(.retryable, revision: nil, version: "retryable-empty")
        await Self.waitUntil { browser.model.detailStateLabel == "retryable • uncached" }
        #expect(!model.canRequestArchive)

        await model.stop()
        await browser.stop()
    }

    @Test("Selection change and stop cancel and join operation observation")
    func selectionAndStopDrainObservation() async throws {
        let browser = try await BrowserFixture.ready(revision: 7)
        let archive = ArchiveProbe(behaviors: [
            .success(.queued), .success(.queued), .success(.queued)
        ])
        let operations = OperationWatchProbe()
        let identities = IdentitySequence([
            "archive-operation-1", "archive-operation-2", "archive-operation-3"
        ])
        let model = Self.model(browser: browser.model, identities: identities)
        await model.start(runtime: Self.runtime(archive: archive, operations: operations))
        model.requestArchiveConfirmation()
        await model.confirmArchive()
        let first = try #require((await archive.recordedCommands()).only)
        let firstSource = operations.source(for: first.envelope.operationId)
        await Self.waitUntil { operations.ids.count == 1 }
        await model.selectionDidChange()
        #expect(firstSource.terminationCount == 1)
        firstSource.yield(Self.snapshot(
            command: first,
            state: .applied(Self.appliedResult(revision: 8)),
            updatedAt: Self.capturedAt.addingTimeInterval(2)
        ))
        try? await Task.sleep(for: .milliseconds(10))
        #expect(model.operationStateLabel == "queued")

        try await browser.reselectPrimaryProject(revision: 7)
        await model.selectionDidSettle()
        await Self.waitUntil { operations.ids.count == 2 }
        #expect(!model.canRequestArchive)
        model.requestArchiveConfirmation()
        await model.confirmArchive()
        #expect(await archive.recordedCommands().count == 1)

        await model.selectionDidChange()
        try await browser.selectAdditionalProject(revision: 3)
        await model.selectionDidSettle()
        #expect(model.canRequestArchive)
        model.requestArchiveConfirmation()
        await model.confirmArchive()
        await Self.waitUntil { operations.ids.count == 3 }
        let commands = await archive.recordedCommands()
        #expect(commands.count == 2)
        #expect(commands[1].envelope.operationId.rawValue == "archive-operation-2")
        #expect(commands[1].draft.projectId.rawValue == "archive-project-2")

        await model.selectionDidChange()
        try await browser.reselectPrimaryProject(revision: 7)
        await model.selectionDidSettle()
        await Self.waitUntil { operations.ids.count == 4 }
        let rejectionSource = operations.source(for: first.envelope.operationId)
        rejectionSource.yield(Self.snapshot(
            command: first,
            state: .rejected(Self.rejection()),
            updatedAt: Self.capturedAt.addingTimeInterval(3)
        ))
        await Self.waitUntil { model.operationStateLabel == "rejected" }
        try browser.yieldDetail(revision: 8, version: "offscreen-rejection-refresh")
        await Self.waitUntil { model.canRetryRejectedArchive }
        model.requestRejectedRetryConfirmation()
        await model.confirmArchive()
        let retried = await archive.recordedCommands()
        #expect(retried.count == 3)
        #expect(retried[2].envelope.operationId.rawValue == "archive-operation-3")
        #expect(retried[2].draft.expectedRevision.rawValue == 8)
        await model.stop()
        await browser.stop()

        let secondBrowser = try await BrowserFixture.ready(revision: 7)
        let secondArchive = ArchiveProbe(behaviors: [.success(.queued)])
        let secondOperations = OperationWatchProbe()
        let secondModel = Self.model(
            browser: secondBrowser.model,
            identities: IdentitySequence(["archive-operation-2"])
        )
        await secondModel.start(runtime: Self.runtime(
            archive: secondArchive,
            operations: secondOperations
        ))
        secondModel.requestArchiveConfirmation()
        await secondModel.confirmArchive()
        let second = try #require((await secondArchive.recordedCommands()).only)
        let secondSource = secondOperations.source(for: second.envelope.operationId)
        await Self.waitUntil { secondOperations.ids.count == 1 }
        await secondModel.stop()
        #expect(secondSource.terminationCount == 1)
        #expect(secondModel.operationStateLabel == "stopped")
        await secondBrowser.stop()
    }

    @Test("Operation source failures are bounded before and after valid evidence")
    func operationSourceFailureMatrix() async throws {
        let cases: [(ArchiveStreamCompletion, Bool, String)] = [
            (.normal, false, "project_archive_operation_source_completed"),
            (.cancelled, false, "project_archive_operation_source_cancelled"),
            (.failed, false, "project_archive_operation_local_failed"),
            (.normal, true, "project_archive_operation_source_completed"),
            (.cancelled, true, "project_archive_operation_source_cancelled"),
            (.failed, true, "project_archive_operation_local_failed")
        ]

        for (index, testCase) in cases.enumerated() {
            let browser = try await BrowserFixture.ready(revision: 7)
            let archive = ArchiveProbe(behaviors: [.success(.queued)])
            let operations = OperationWatchProbe()
            let model = Self.model(
                browser: browser.model,
                identities: IdentitySequence(["archive-operation-\(index + 10)"])
            )
            await model.start(runtime: Self.runtime(archive: archive, operations: operations))
            model.requestArchiveConfirmation()
            await model.confirmArchive()
            let command = try #require((await archive.recordedCommands()).only)
            let source = operations.source(for: command.envelope.operationId)
            await Self.waitUntil { operations.ids.count == 1 }

            if testCase.1 {
                source.yield(Self.snapshot(
                    command: command,
                    state: .applying(
                        attempt: 1,
                        startedAt: Self.capturedAt.addingTimeInterval(1)
                    ),
                    updatedAt: Self.capturedAt.addingTimeInterval(1)
                ))
                await Self.waitUntil { model.operationStateLabel == "applying" }
            }
            testCase.0.finish(source)
            await Self.waitUntil { model.diagnostic == testCase.2 }
            #expect(source.terminationCount == 1)

            await model.stop()
            await browser.stop()
        }
    }

    fileprivate static let accountId = try! AccountID(validating: "archive-account")
    fileprivate static let principalId = try! PrincipalID(validating: "archive-principal")
    fileprivate static let projectId = try! ProjectID(validating: "archive-project")
    fileprivate static let contractVersion = try! OperationContractVersion(
        validating: "project-archive-v1"
    )
    fileprivate static let capturedAt = Date(timeIntervalSince1970: 1_804_100_000)

    private static func model(
        browser: ProjectBrowsingStagingExercise,
        identities: IdentitySequence = IdentitySequence(["archive-operation-1"]),
        now: @escaping @MainActor () -> Date = { capturedAt }
    ) -> ProjectArchiveBrowserStagingExercise {
        ProjectArchiveBrowserStagingExercise(
            accountId: accountId,
            actorPrincipalId: principalId,
            operationContractVersion: contractVersion,
            browser: browser,
            makeIdentity: { try identities.next() },
            now: now
        )
    }

    private static func runtime(
        archive: ArchiveProbe,
        operations: OperationWatchProbe
    ) -> ProjectArchiveBrowserStagingRuntime {
        ProjectArchiveBrowserStagingRuntime(
            archive: { try await archive.archive($0) },
            watchOperation: { operations.watch($0) }
        )
    }

    private static func snapshot(
        command: ArchiveProjectCommand,
        state: OperationState,
        updatedAt: Date
    ) -> OperationSnapshot {
        OperationSnapshot(
            operationId: command.envelope.operationId,
            accountId: command.envelope.accountId,
            contractVersion: command.envelope.contractVersion,
            fingerprint: command.fingerprint,
            acceptedAt: command.envelope.clientCreatedAt.addingTimeInterval(0.5),
            updatedAt: updatedAt,
            state: state
        )
    }

    private static func appliedResult(revision: UInt64) -> AppliedOperationResult {
        AppliedOperationResult(
            resultCode: try! ApplicationResultCode(validating: "project_archived"),
            serverReceivedAt: capturedAt.addingTimeInterval(1),
            completedAt: capturedAt.addingTimeInterval(2),
            affectedRevisions: [
                EntityRevision(
                    entity: LedgerEntityReference(
                        kind: .project,
                        id: try! EntityID(validating: projectId.rawValue)
                    ),
                    revision: revision
                )
            ]
        )
    }

    private static func rejection() -> OperationRejection {
        OperationRejection(
            error: ApplicationErrorSummary(
                code: try! ApplicationErrorCode(validating: "project_revision_conflict"),
                category: .conflict,
                retryDisposition: .afterUserCorrection
            ),
            rejectedAt: capturedAt.addingTimeInterval(2),
            conflictingEntities: [
                LedgerEntityReference(
                    kind: .project,
                    id: try! EntityID(validating: projectId.rawValue)
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
        Issue.record("Timed out waiting for Project archive browser state")
    }
}

private final class IdentitySequence {
    private var values: [String]

    init(_ values: [String]) {
        self.values = values
    }

    @MainActor
    func next() throws -> ProjectArchiveSubmissionIdentity {
        ProjectArchiveSubmissionIdentity(
            operationId: try OperationID(validating: values.removeFirst())
        )
    }
}

private enum ArchiveStreamCompletion: Sendable {
    case normal
    case cancelled
    case failed

    func finish(_ source: ArchiveControlledStream<OperationSnapshot>) {
        switch self {
        case .normal:
            source.finish()
        case .cancelled:
            source.finish(throwing: CancellationError())
        case .failed:
            source.finish(throwing: ArchiveOperationSourceTestFailure())
        }
    }
}

private struct ArchiveOperationSourceTestFailure: Error {}

private actor ArchiveProbe {
    enum Behavior: @unchecked Sendable {
        case success(LocalOperationState)
        case failure(Error)
    }

    private var behaviors: [Behavior]
    private var commands: [ArchiveProjectCommand] = []

    init(behaviors: [Behavior]) {
        self.behaviors = behaviors
    }

    func archive(_ command: ArchiveProjectCommand) throws -> OperationReceipt {
        commands.append(command)
        guard !behaviors.isEmpty else {
            throw ProjectArchiveFailure.localAcceptanceFailed
        }
        switch behaviors.removeFirst() {
        case .success(let state):
            return OperationReceipt(
                operationId: command.envelope.operationId,
                localState: state
            )
        case .failure(let error):
            throw error
        }
    }

    func recordedCommands() -> [ArchiveProjectCommand] {
        commands
    }
}

private final class OperationWatchProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var watchedIds: [String] = []
    private var sources: [String: ArchiveControlledStream<OperationSnapshot>] = [:]

    var ids: [String] { lock.withLock { watchedIds } }

    func source(for operationId: OperationID) -> ArchiveControlledStream<OperationSnapshot> {
        lock.withLock {
            if let source = sources[operationId.rawValue] { return source }
            let source = ArchiveControlledStream<OperationSnapshot>()
            sources[operationId.rawValue] = source
            return source
        }
    }

    func watch(
        _ operationId: OperationID
    ) -> AsyncThrowingStream<OperationSnapshot, Error> {
        lock.withLock {
            watchedIds.append(operationId.rawValue)
            if let source = sources[operationId.rawValue], source.terminationCount == 0 {
                return source.stream
            }
            let source = ArchiveControlledStream<OperationSnapshot>()
            sources[operationId.rawValue] = source
            return source.stream
        }
    }
}

private final class ArchiveControlledStream<Value: Sendable>: @unchecked Sendable {
    let stream: AsyncThrowingStream<Value, Error>
    private let continuation: AsyncThrowingStream<Value, Error>.Continuation
    private let termination = ArchiveTerminationProbe()

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

    func yield(_ value: Value) {
        continuation.yield(value)
    }

    func finish(throwing error: Error? = nil) {
        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }
}

private final class ArchiveTerminationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func record() { lock.withLock { value += 1 } }
}

@MainActor
private final class BrowserFixture {
    let model: ProjectBrowsingStagingExercise
    let project: ProjectSummary
    private let directory = ArchiveControlledStream<ProjectListSnapshot>()
    private let detailProbe: ArchiveDetailProbe

    var request: ProjectCoreDetailsRequest? { detailProbe.requests.last }

    private init(model: ProjectBrowsingStagingExercise, project: ProjectSummary) {
        self.model = model
        self.project = project
        detailProbe = ArchiveDetailProbe()
    }

    static func ready(revision: UInt64) async throws -> BrowserFixture {
        let fixture = try BrowserFixture(
            model: ProjectBrowsingStagingExercise(
                accountId: ProjectArchiveBrowserStagingExerciseTests.accountId
            ),
            project: makeProject(lifecycle: .active)
        )
        await fixture.model.start(runtime: ProjectBrowsingStagingRuntime(
            watchProjects: { fixture.directory.stream },
            watchProject: { fixture.detailProbe.watch($0) }
        ))
        fixture.directory.yield(try directory([fixture.project], version: "initial-directory"))
        await ProjectArchiveBrowserStagingExerciseTests.waitUntil {
            fixture.model.activeProjects.count == 1
        }
        await fixture.model.select(projectId: fixture.project.id, segment: .active)
        await ProjectArchiveBrowserStagingExerciseTests.waitUntil {
            fixture.detailProbe.requests.count == 1
        }
        try fixture.yieldDetail(revision: revision, version: "initial-detail")
        await ProjectArchiveBrowserStagingExerciseTests.waitUntil {
            fixture.model.selectedProjectArchiveEvidence?.expectedRevision.rawValue == revision
        }
        return fixture
    }

    func yieldDetail(
        revision: UInt64,
        quality: ListSnapshotQuality = .ready,
        complete: Bool = true,
        version: String
    ) throws {
        let request = try #require(request)
        yield(try ProjectCoreDetailsUpdate(
            request: request,
            state: .snapshot(try local(
                request: request,
                rows: [try row(revision: revision)],
                quality: quality,
                complete: complete,
                version: version
            ))
        ))
    }

    func selectAdditionalProject(revision: UInt64) async throws {
        let additional = try Self.makeProject(
            id: ProjectID(validating: "archive-project-2"),
            displayName: "Archive Project Two",
            lifecycle: .active
        )
        directory.yield(try Self.directory(
            [project, additional],
            version: "additional-directory"
        ))
        await ProjectArchiveBrowserStagingExerciseTests.waitUntil {
            self.model.activeProjects.count == 2
        }
        await model.select(projectId: additional.id, segment: .active)
        await ProjectArchiveBrowserStagingExerciseTests.waitUntil {
            self.detailProbe.requests.last?.projectId == additional.id
        }
        let request = try #require(request)
        yield(try ProjectCoreDetailsUpdate(
            request: request,
            state: .snapshot(try local(
                request: request,
                rows: [try row(project: additional, revision: revision)],
                quality: .ready,
                complete: true,
                version: "additional-detail"
            ))
        ))
        await ProjectArchiveBrowserStagingExerciseTests.waitUntil {
            self.model.selectedProjectArchiveEvidence?.projectId == additional.id
        }
    }

    func reselectPrimaryProject(revision: UInt64) async throws {
        let priorRequestCount = detailProbe.requests.count
        await model.select(projectId: project.id, segment: .active)
        await ProjectArchiveBrowserStagingExerciseTests.waitUntil {
            self.detailProbe.requests.count == priorRequestCount + 1
                && self.detailProbe.requests.last?.projectId == self.project.id
        }
        try yieldDetail(revision: revision, version: "reselected-primary-detail")
        await ProjectArchiveBrowserStagingExerciseTests.waitUntil {
            self.model.selectedProjectArchiveEvidence?.projectId == self.project.id
        }
    }

    func yieldEmpty(
        quality: ListSnapshotQuality,
        complete: Bool,
        version: String
    ) throws {
        let request = try #require(request)
        yield(try ProjectCoreDetailsUpdate(
            request: request,
            state: .snapshot(try local(
                request: request,
                rows: [],
                quality: quality,
                complete: complete,
                version: version
            ))
        ))
    }

    func yieldCachedFailure(
        _ failure: ListFailureState,
        revision: UInt64?,
        version: String
    ) throws {
        let request = try #require(request)
        let cached: ProjectCoreDetailsLocalSnapshot? = try revision.map {
            try local(
                request: request,
                rows: [try row(revision: $0)],
                quality: .stale,
                complete: false,
                version: version
            )
        }
        yield(try ProjectCoreDetailsUpdate(
            request: request,
            state: .failed(failure: failure, cached: cached)
        ))
    }

    func yield(_ update: ProjectCoreDetailsUpdate) {
        detailProbe.yield(update)
    }

    func stop() async {
        await model.stop()
    }

    private func row(
        project: ProjectSummary? = nil,
        revision: UInt64
    ) throws -> ProjectCoreDetailsSnapshot {
        try ProjectCoreDetailsSnapshot(
            project: project ?? self.project,
            locallyObservedRevision: ExpectedProjectRevision(revision)
        )
    }

    private func local(
        request: ProjectCoreDetailsRequest,
        rows: [ProjectCoreDetailsSnapshot],
        quality: ListSnapshotQuality,
        complete: Bool,
        version: String
    ) throws -> ProjectCoreDetailsLocalSnapshot {
        try ProjectCoreDetailsLocalSnapshot(
            request: request,
            rows: rows,
            visibleRowCountBeforeFiltering: rows.count,
            isCompleteForQuery: complete,
            quality: quality,
            localDataVersion: LocalDataVersion(validating: version),
            asOf: ProjectArchiveBrowserStagingExerciseTests.capturedAt
        )
    }

    private static func makeProject(
        id: ProjectID = ProjectArchiveBrowserStagingExerciseTests.projectId,
        displayName: String = "Archive Project",
        lifecycle: DirectoryLifecycleState
    ) throws -> ProjectSummary {
        let clientId = try ClientID(validating: "archive-client")
        let client = try ClientSummary(
            id: clientId,
            accountId: ProjectArchiveBrowserStagingExerciseTests.accountId,
            displayName: ClientDisplayName(validating: "Archive Client"),
            lifecycle: .active,
            createdAt: ProjectArchiveBrowserStagingExerciseTests.capturedAt.addingTimeInterval(-20),
            updatedAt: ProjectArchiveBrowserStagingExerciseTests.capturedAt.addingTimeInterval(-10)
        )
        return try ProjectSummary(
            id: id,
            accountId: ProjectArchiveBrowserStagingExerciseTests.accountId,
            clientId: clientId,
            client: client,
            displayName: ProjectDisplayName(validating: displayName),
            description: nil,
            lifecycle: lifecycle
        )
    }

    private static func directory(
        _ rows: [ProjectSummary],
        version: String
    ) throws -> ProjectListSnapshot {
        try ProjectListSnapshot(
            accountId: ProjectArchiveBrowserStagingExerciseTests.accountId,
            local: ListLocalSnapshot(
                queryFingerprint: ListQueryFingerprint(
                    validating: String(repeating: "a", count: 64)
                ),
                rows: rows,
                visibleRowCountBeforeFiltering: rows.count,
                isCompleteForQuery: true,
                quality: .ready,
                localDataVersion: LocalDataVersion(validating: version),
                asOf: ProjectArchiveBrowserStagingExerciseTests.capturedAt
            )
        )
    }
}

private final class ArchiveDetailProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ProjectCoreDetailsRequest] = []
    private var source: ArchiveControlledStream<ProjectCoreDetailsUpdate>?

    var requests: [ProjectCoreDetailsRequest] { lock.withLock { values } }

    func watch(
        _ request: ProjectCoreDetailsRequest
    ) -> AsyncThrowingStream<ProjectCoreDetailsUpdate, Error> {
        lock.withLock {
            values.append(request)
            let next = ArchiveControlledStream<ProjectCoreDetailsUpdate>()
            source = next
            return next.stream
        }
    }

    func yield(_ update: ProjectCoreDetailsUpdate) {
        lock.withLock { source }?.yield(update)
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
