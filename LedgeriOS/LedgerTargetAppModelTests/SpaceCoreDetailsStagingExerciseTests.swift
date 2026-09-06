import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetAppModel

@Suite("Space core-details staging presenter")
@MainActor
struct SpaceCoreDetailsStagingExerciseTests {
    @Test("Waiting, partial, stale, ready and authoritative-empty truth stay distinct")
    func presentationStates() async throws {
        let source = SpaceDetailsControlledStream()
        let requests = SpaceDetailsRequestRecorder()
        let model = Self.model()
        await model.select(
            spaceId: Self.spaceA,
            runtime: Self.runtime(source: source, requests: requests)
        )

        #expect(model.selectedSpaceId == Self.spaceA)
        #expect(model.presentation == .waiting(.loading))
        await Self.waitUntil { requests.spaceIds == [Self.spaceA] }

        for readiness in [ListReadiness.notRequested, .loading, .blocked] {
            source.yield(try Self.update(.waiting(readiness)))
            await Self.waitUntil { model.presentation == .waiting(readiness) }
            #expect(model.row == nil)
            #expect(!model.progressCountsAreAuthoritative)
        }

        let row = try Self.space()
        source.yield(try Self.snapshotUpdate(rows: [row], quality: .partial))
        await Self.waitUntil { model.presentation == .partial(row) }
        #expect(!model.progressCountsAreAuthoritative)

        source.yield(try Self.snapshotUpdate(rows: [], quality: .partial))
        await Self.waitUntil { model.presentation == .partial(nil) }
        #expect(model.status == "partial empty • completeness unknown")

        source.yield(try Self.snapshotUpdate(rows: [row], quality: .stale))
        await Self.waitUntil { model.presentation == .stale(row) }
        #expect(!model.progressCountsAreAuthoritative)

        source.yield(try Self.snapshotUpdate(rows: [], quality: .stale))
        await Self.waitUntil { model.presentation == .stale(nil) }
        #expect(model.status == "stale empty • completeness unknown")

        source.yield(try Self.snapshotUpdate(rows: [row], quality: .ready, complete: true))
        await Self.waitUntil { model.presentation == .ready(row) }
        #expect(model.progressCountsAreAuthoritative)
        #expect(model.completedItemCount == 2)
        #expect(model.totalItemCount == 3)

        source.yield(try Self.snapshotUpdate(rows: [], quality: .ready, complete: true))
        await Self.waitUntil { model.presentation == .authoritativeEmpty }
        #expect(model.isAuthoritativelyEmpty)
        #expect(model.row == nil)
        #expect(model.completedItemCount == 0 && model.totalItemCount == 0)
        await model.stop()
    }

    @Test("Active Project and archived Inventory fields preserve ordered checklist progress")
    func exactFieldsLifecycleAndHierarchy() async throws {
        let first = SpaceDetailsControlledStream()
        let second = SpaceDetailsControlledStream()
        let requests = SpaceDetailsRequestRecorder()
        let spaceA = Self.spaceA
        let runtime = SpaceDetailsTestRuntime { spaceId in
            requests.record(spaceId)
            return spaceId == spaceA ? first.stream : second.stream
        }
        let model = Self.model()

        await model.select(spaceId: Self.spaceA, runtime: runtime)
        let project = try Self.space()
        first.yield(try Self.snapshotUpdate(rows: [project], quality: .ready, complete: true))
        await Self.waitUntil { model.row == project }
        #expect(model.row?.scope == .project(Self.projectId))
        #expect(model.row?.displayName.rawValue == "Living Room")
        #expect(model.row?.notes.value == "Keep original trim")
        #expect(model.row?.lifecycle == .active)
        #expect(model.row?.revision == UInt64(Int64.max))
        #expect(model.row?.createdAt == Self.createdAt)
        #expect(model.row?.updatedAt == Self.updatedAt)
        #expect(model.row?.checklists.checklists.map(\.id.rawValue) == ["prep", "install", "empty"])
        #expect(model.row?.checklists.checklists[0].items.map(\.id.rawValue) == ["shared"])
        #expect(model.row?.checklists.checklists[1].items.map(\.id.rawValue) == ["level", "shared"])
        #expect(model.row?.checklists.checklists.map(\.presentationOrder) == [0, 20, UInt32.max])
        #expect(model.row?.checklists.checklists[0].items.map(\.presentationOrder) == [UInt32.max])
        #expect(model.row?.checklists.checklists[1].items.map(\.presentationOrder) == [1, 2])
        #expect(model.row?.checklists.checklists.map(\.completedItemCount) == [1, 1, 0])
        #expect(model.row?.checklists.checklists.map(\.totalItemCount) == [1, 2, 0])

        await model.select(spaceId: Self.spaceB, runtime: runtime)
        #expect(first.terminationCount == 1)
        #expect(model.row == nil)
        let inventory = try Self.space(
            id: Self.spaceB,
            scope: .businessInventory,
            lifecycle: .archived,
            notes: nil,
            checklists: []
        )
        second.yield(try Self.snapshotUpdate(
            spaceId: Self.spaceB,
            rows: [inventory],
            quality: .ready,
            complete: true
        ))
        await Self.waitUntil { model.row == inventory }
        #expect(model.row?.scope == .businessInventory)
        #expect(model.row?.lifecycle == .archived)
        #expect(model.row?.notes.value == nil)
        #expect(model.completedItemCount == 0 && model.totalItemCount == 0)
        #expect(requests.spaceIds == [Self.spaceA, Self.spaceB])
        await model.stop()
        #expect(second.terminationCount == 1)
    }

    @Test("Bounded upstream failures preserve only exact cached evidence")
    func boundedFailuresAndCache() async throws {
        let source = SpaceDetailsControlledStream()
        let model = Self.model()
        await model.select(spaceId: Self.spaceA, runtime: Self.runtime(source: source))
        let request = try Self.request()
        let row = try Self.space()
        let partial = try Self.local(rows: [row], quality: .partial)
        let ready = try Self.local(rows: [row], quality: .ready, complete: true, version: "ready-cache")

        source.yield(try SpaceCoreDetailsUpdate(
            request: request,
            state: .failed(failure: .unavailable, cached: nil)
        ))
        await Self.waitUntil { model.diagnostic == "space_core_details_unavailable" }
        #expect(model.row == nil)

        source.yield(try SpaceCoreDetailsUpdate(
            request: request,
            state: .failed(failure: .retryable, cached: partial)
        ))
        await Self.waitUntil { model.diagnostic == "space_core_details_retryable" }
        #expect(model.row == row)
        #expect(!model.progressCountsAreAuthoritative)

        source.yield(try SpaceCoreDetailsUpdate(
            request: request,
            state: .failed(failure: .requiredUpdate, cached: ready)
        ))
        await Self.waitUntil { model.diagnostic == "space_core_details_requiredUpdate" }
        #expect(model.row == row)
        #expect(model.progressCountsAreAuthoritative)
        await model.stop()
    }

    @Test("Incoherent completeness and rebound requests fail closed")
    func malformedPresentationEvidenceFailsClosed() async throws {
        let malformedUpdates: [(SpaceCoreDetailsUpdate, String)] = [
            (
                try Self.snapshotUpdate(
                    rows: [Self.space()], quality: .ready, complete: false,
                    version: "ready-incomplete-found"
                ),
                SpaceCoreDetailsFailure.invalidCompleteness.diagnosticCode
            ),
            (
                try Self.snapshotUpdate(
                    rows: [], quality: .ready, complete: false,
                    version: "ready-incomplete-empty"
                ),
                SpaceCoreDetailsFailure.invalidCompleteness.diagnosticCode
            ),
            (
                try Self.snapshotUpdate(
                    spaceId: Self.spaceB,
                    rows: [Self.space(id: Self.spaceB)],
                    quality: .ready,
                    complete: true,
                    version: "rebound-request"
                ),
                SpaceCoreDetailsFailure.updateRequestMismatch.diagnosticCode
            ),
        ]
        for (malformed, expectedDiagnostic) in malformedUpdates {
            let source = SpaceDetailsControlledStream()
            let model = Self.model()
            await model.select(spaceId: Self.spaceA, runtime: Self.runtime(source: source))
            source.yield(malformed)
            await Self.waitUntil { model.diagnostic == expectedDiagnostic }
            #expect(model.row == nil)
            #expect(!model.isAuthoritativelyEmpty)
            #expect(!model.progressCountsAreAuthoritative)
            await model.stop()
        }
    }

    @Test("Normal completion, upstream cancellation and unknown errors clear prior detail")
    func terminalSourcesFailClosed() async throws {
        let cases: [(SpaceDetailsTerminal, String)] = [
            (.completed, "space_core_details_source_completed"),
            (.cancelled, "space_core_details_source_cancelled"),
            (.failed, SpaceCoreDetailsFailure.localReadFailed.diagnosticCode),
        ]
        for (terminal, expectedCode) in cases {
            let source = SpaceDetailsControlledStream()
            let model = Self.model()
            await model.select(spaceId: Self.spaceA, runtime: Self.runtime(source: source))
            source.yield(try Self.snapshotUpdate(
                rows: [Self.space()], quality: .ready, complete: true
            ))
            await Self.waitUntil { model.row != nil }
            switch terminal {
            case .completed: source.finish()
            case .cancelled: source.finish(throwing: CancellationError())
            case .failed: source.finish(throwing: SpaceDetailsTestFailure.upstream)
            }
            await Self.waitUntil { model.diagnostic == expectedCode }
            #expect(model.row == nil)
            #expect(model.selectedSpaceId == Self.spaceA)
            #expect(!model.progressCountsAreAuthoritative)
            await model.stop()
        }
    }

    @Test("Selection replacement drains and rejects a noncooperative late value")
    func replacementDrainageAndGenerationIsolation() async throws {
        let old = SpaceDetailsDelayedValueSource()
        let current = SpaceDetailsControlledStream()
        let spaceA = Self.spaceA
        let runtime = SpaceDetailsTestRuntime { spaceId in
            spaceId == spaceA ? old.stream : current.stream
        }
        let model = Self.model()
        await model.select(spaceId: Self.spaceA, runtime: runtime)
        #expect(await Self.waitUntilAsync { await old.isWaiting })

        let completion = SpaceDetailsCompletionProbe()
        let replacement = Task { @MainActor in
            completion.markStarted()
            await model.select(spaceId: Self.spaceB, runtime: runtime)
            completion.markFinished()
        }
        await Self.waitUntil { completion.didStart }
        #expect(model.selectedSpaceId == Self.spaceB)
        #expect(model.presentation == .waiting(.loading))
        #expect(!completion.didFinish)

        await old.release(try Self.snapshotUpdate(
            rows: [Self.space(name: "Late old Space")],
            quality: .ready,
            complete: true,
            version: "late-old"
        ))
        await replacement.value
        #expect(completion.didFinish)
        #expect(model.row == nil)
        #expect(model.selectedSpaceId == Self.spaceB)

        let newRow = try Self.space(id: Self.spaceB, name: "Current Space")
        current.yield(try Self.snapshotUpdate(
            spaceId: Self.spaceB,
            rows: [newRow],
            quality: .ready,
            complete: true,
            version: "current"
        ))
        await Self.waitUntil { model.row == newRow }
        #expect(model.row?.displayName.rawValue == "Current Space")
        await model.stop()
        #expect(current.terminationCount == 1)
    }

    @Test("Clear and stop cancel and join before returning, then restart cleanly")
    func clearStopAndRestartDrainage() async throws {
        let clearRow = try Self.space(name: "Clear me")
        let delayedClear = SpaceDetailsDelayedCancellationSource(initial: try Self.snapshotUpdate(
            rows: [clearRow], quality: .ready, complete: true, version: "before-clear"
        ))
        let model = Self.model()
        await model.select(
            spaceId: Self.spaceA,
            runtime: SpaceDetailsTestRuntime { _ in delayedClear.stream }
        )
        await Self.waitUntil { model.row == clearRow }
        #expect(await Self.waitUntilAsync { await delayedClear.isWaiting })
        let clearProbe = SpaceDetailsCompletionProbe()
        let clear = Task { @MainActor in
            clearProbe.markStarted()
            await model.clear()
            clearProbe.markFinished()
        }
        await Self.waitUntil { clearProbe.didStart }
        #expect(model.presentation == .waiting(.notRequested))
        #expect(model.selectedSpaceId == nil)
        #expect(model.row == nil)
        #expect(!clearProbe.didFinish)
        await delayedClear.releaseCancellation()
        await clear.value
        #expect(clearProbe.didFinish)
        #expect(delayedClear.terminationCount == 1)

        let stopRow = try Self.space(id: Self.spaceB, name: "Stop me")
        let delayedStop = SpaceDetailsDelayedCancellationSource(initial: try Self.snapshotUpdate(
            spaceId: Self.spaceB,
            rows: [stopRow],
            quality: .ready,
            complete: true,
            version: "before-stop"
        ))
        await model.select(
            spaceId: Self.spaceB,
            runtime: SpaceDetailsTestRuntime { _ in delayedStop.stream }
        )
        await Self.waitUntil { model.row == stopRow }
        #expect(await Self.waitUntilAsync { await delayedStop.isWaiting })
        let stopProbe = SpaceDetailsCompletionProbe()
        let stop = Task { @MainActor in
            stopProbe.markStarted()
            await model.stop()
            stopProbe.markFinished()
        }
        await Self.waitUntil { stopProbe.didStart }
        #expect(model.presentation == .waiting(.blocked))
        #expect(model.selectedSpaceId == nil)
        #expect(model.row == nil)
        #expect(!stopProbe.didFinish)
        await delayedStop.releaseCancellation()
        await stop.value
        #expect(stopProbe.didFinish)
        #expect(delayedStop.terminationCount == 1)

        let restarted = SpaceDetailsControlledStream()
        await model.select(spaceId: Self.spaceA, runtime: Self.runtime(source: restarted))
        let row = try Self.space(name: "Restarted")
        restarted.yield(try Self.snapshotUpdate(
            rows: [row], quality: .ready, complete: true, version: "restarted"
        ))
        await Self.waitUntil { model.row == row }
        #expect(model.presentation == .ready(row))
        await model.stop()
    }

    private static let accountId = try! AccountID(validating: "account-space-details")
    private static let spaceA = try! SpaceID(validating: "space-a")
    private static let spaceB = try! SpaceID(validating: "space-b")
    private static let projectId = try! ProjectID(validating: "project-archived-compatible")
    private static let createdAt = Date(timeIntervalSince1970: 1_788_600_000.123)
    private static let updatedAt = Date(timeIntervalSince1970: 1_788_600_005.456)

    private static func model() -> SpaceCoreDetailsStagingExercise {
        SpaceCoreDetailsStagingExercise(accountId: accountId)
    }

    private static func runtime(
        source: SpaceDetailsControlledStream,
        requests: SpaceDetailsRequestRecorder = SpaceDetailsRequestRecorder()
    ) -> SpaceDetailsTestRuntime {
        SpaceDetailsTestRuntime { spaceId in
            requests.record(spaceId)
            return source.stream
        }
    }

    private static func request(
        spaceId: SpaceID = spaceA
    ) throws -> SpaceCoreDetailsRequest {
        try SpaceCoreDetailsRequest(accountId: accountId, spaceId: spaceId)
    }

    private static func space(
        id: SpaceID = spaceA,
        name: String = "Living Room",
        scope: SpaceCreationScope = .project(projectId),
        lifecycle: DirectoryLifecycleState = .active,
        notes: String? = "Keep original trim",
        checklists: [SpaceChecklistState]? = nil
    ) throws -> SpaceCoreDetailsSnapshot {
        try SpaceCoreDetailsSnapshot(
            id: id,
            accountId: accountId,
            scope: scope,
            displayName: SpaceDisplayName(validating: name),
            notes: SpaceCreationNotes(notes),
            lifecycle: lifecycle,
            revision: UInt64(Int64.max),
            createdAt: createdAt,
            updatedAt: updatedAt,
            checklists: SpaceChecklistCollection(
                checklists: try checklists ?? canonicalChecklists()
            )
        )
    }

    private static func canonicalChecklists() throws -> [SpaceChecklistState] {
        let shared = try SpaceChecklistItemID(validating: "shared")
        return [
            try SpaceChecklistState(
                id: SpaceChecklistID(validating: "install"),
                name: SpaceChecklistName(validating: "Install"),
                presentationOrder: 20,
                items: [
                    SpaceChecklistItemState(
                        id: shared,
                        text: try SpaceChecklistItemText(validating: "Hang art"),
                        isChecked: true,
                        presentationOrder: 2
                    ),
                    SpaceChecklistItemState(
                        id: try SpaceChecklistItemID(validating: "level"),
                        text: try SpaceChecklistItemText(validating: "Level frames"),
                        isChecked: false,
                        presentationOrder: 1
                    ),
                ]
            ),
            try SpaceChecklistState(
                id: SpaceChecklistID(validating: "empty"),
                name: SpaceChecklistName(validating: "Empty"),
                presentationOrder: UInt32.max,
                items: []
            ),
            try SpaceChecklistState(
                id: SpaceChecklistID(validating: "prep"),
                name: SpaceChecklistName(validating: "Prepare"),
                presentationOrder: 0,
                items: [
                    SpaceChecklistItemState(
                        id: shared,
                        text: try SpaceChecklistItemText(validating: "Protect floor"),
                        isChecked: true,
                        presentationOrder: UInt32.max
                    )
                ]
            ),
        ]
    }

    private static func local(
        spaceId: SpaceID = spaceA,
        rows: [SpaceCoreDetailsSnapshot],
        quality: ListSnapshotQuality,
        complete: Bool = false,
        version: String = "space-details"
    ) throws -> SpaceCoreDetailsLocalSnapshot {
        let request = try request(spaceId: spaceId)
        return try SpaceCoreDetailsLocalSnapshot(
            request: request,
            rows: rows,
            visibleRowCountBeforeFiltering: rows.count,
            isCompleteForQuery: complete,
            quality: quality,
            localDataVersion: LocalDataVersion(validating: version),
            asOf: updatedAt
        )
    }

    private static func update(
        _ state: SpaceCoreDetailsUpdateState,
        spaceId: SpaceID = spaceA
    ) throws -> SpaceCoreDetailsUpdate {
        try SpaceCoreDetailsUpdate(request: request(spaceId: spaceId), state: state)
    }

    private static func snapshotUpdate(
        spaceId: SpaceID = spaceA,
        rows: [SpaceCoreDetailsSnapshot],
        quality: ListSnapshotQuality,
        complete: Bool = false,
        version: String = "space-details"
    ) throws -> SpaceCoreDetailsUpdate {
        try update(
            .snapshot(try local(
                spaceId: spaceId,
                rows: rows,
                quality: quality,
                complete: complete,
                version: version
            )),
            spaceId: spaceId
        )
    }

    private static func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<2_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Timed out waiting for Space detail presentation")
    }

    private static func waitUntilAsync(
        _ condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0..<2_000 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }
}

private struct SpaceDetailsTestRuntime: SpaceCoreDetailsStagingRuntime {
    let watch: @Sendable (SpaceID) -> AsyncThrowingStream<SpaceCoreDetailsUpdate, Error>

    init(
        watch: @Sendable @escaping (SpaceID)
            -> AsyncThrowingStream<SpaceCoreDetailsUpdate, Error>
    ) {
        self.watch = watch
    }

    func watchSpaceCoreDetails(
        spaceId: SpaceID
    ) -> AsyncThrowingStream<SpaceCoreDetailsUpdate, Error> {
        watch(spaceId)
    }
}

private final class SpaceDetailsControlledStream: @unchecked Sendable {
    let stream: AsyncThrowingStream<SpaceCoreDetailsUpdate, Error>
    private let continuation: AsyncThrowingStream<SpaceCoreDetailsUpdate, Error>.Continuation
    private let termination = SpaceDetailsTerminationProbe()

    init() {
        var captured: AsyncThrowingStream<SpaceCoreDetailsUpdate, Error>.Continuation!
        let termination = termination
        stream = AsyncThrowingStream { continuation in
            captured = continuation
            continuation.onTermination = { _ in termination.record() }
        }
        continuation = captured
    }

    var terminationCount: Int { termination.count }
    func yield(_ value: SpaceCoreDetailsUpdate) { continuation.yield(value) }
    func finish() { continuation.finish() }
    func finish(throwing error: Error) { continuation.finish(throwing: error) }
}

private final class SpaceDetailsRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [SpaceID] = []
    var spaceIds: [SpaceID] { lock.withLock { recorded } }
    func record(_ value: SpaceID) { lock.withLock { recorded.append(value) } }
}

private final class SpaceDetailsTerminationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded = 0
    var count: Int { lock.withLock { recorded } }
    func record() { lock.withLock { recorded += 1 } }
}

private final class SpaceDetailsCompletionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    private var finished = false
    var didStart: Bool { lock.withLock { started } }
    var didFinish: Bool { lock.withLock { finished } }
    func markStarted() { lock.withLock { started = true } }
    func markFinished() { lock.withLock { finished = true } }
}

private final class SpaceDetailsDelayedValueSource: @unchecked Sendable {
    let stream: AsyncThrowingStream<SpaceCoreDetailsUpdate, Error>
    private let gate: SpaceDetailsDelayedValueGate

    init() {
        let gate = SpaceDetailsDelayedValueGate()
        self.gate = gate
        stream = AsyncThrowingStream(unfolding: { await gate.next() })
    }

    var isWaiting: Bool { get async { await gate.isWaiting } }
    func release(_ value: SpaceCoreDetailsUpdate) async { await gate.release(value) }
}

private final class SpaceDetailsDelayedCancellationSource: @unchecked Sendable {
    let stream: AsyncThrowingStream<SpaceCoreDetailsUpdate, Error>
    private let gate: SpaceDetailsDelayedCancellationGate
    private let termination = SpaceDetailsTerminationProbe()

    init(initial: SpaceCoreDetailsUpdate) {
        let gate = SpaceDetailsDelayedCancellationGate(initial: initial)
        let termination = termination
        self.gate = gate
        stream = AsyncThrowingStream(unfolding: {
            do {
                return try await gate.next()
            } catch {
                termination.record()
                throw error
            }
        })
    }

    var isWaiting: Bool { get async { await gate.isWaiting } }
    var terminationCount: Int { termination.count }
    func releaseCancellation() async { await gate.releaseCancellation() }
}

private actor SpaceDetailsDelayedValueGate {
    private var continuation: CheckedContinuation<SpaceCoreDetailsUpdate?, Never>?
    var isWaiting: Bool { continuation != nil }
    func next() async -> SpaceCoreDetailsUpdate? {
        await withCheckedContinuation { continuation = $0 }
    }
    func release(_ value: SpaceCoreDetailsUpdate) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}

private actor SpaceDetailsDelayedCancellationGate {
    private var initial: SpaceCoreDetailsUpdate?
    private var continuation: CheckedContinuation<SpaceCoreDetailsUpdate?, Error>?

    init(initial: SpaceCoreDetailsUpdate) {
        self.initial = initial
    }

    var isWaiting: Bool { continuation != nil }
    func next() async throws -> SpaceCoreDetailsUpdate? {
        if let initial {
            self.initial = nil
            return initial
        }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func releaseCancellation() {
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}

private enum SpaceDetailsTerminal {
    case completed
    case cancelled
    case failed
}

private enum SpaceDetailsTestFailure: Error {
    case upstream
}
