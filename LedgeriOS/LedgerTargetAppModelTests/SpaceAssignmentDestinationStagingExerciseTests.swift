import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetAppModel

@Suite("Space destination staging presenter")
@MainActor
struct SpaceAssignmentDestinationStagingExerciseTests {
    @Test("All six states remain distinct and selection requires a represented ID")
    func statesAndSelection() async throws {
        let source = SpaceDestinationControlledStream()
        let model = SpaceAssignmentDestinationStagingExercise(accountId: Self.accountId)
        await model.open(scope: Self.scope, runtime: .init(watch: { _ in source.stream }))
        #expect(model.presentation == .waiting)

        let row = try Self.row("space-a", "Loft")
        source.yield(try Self.directory(rows: [row], quality: .partial, complete: false))
        await Self.wait { model.presentation == .partial([row]) }
        source.yield(try Self.directory(rows: [row], quality: .stale, complete: false))
        await Self.wait { model.presentation == .stale([row]) }
        source.yield(try Self.directory(rows: [row], quality: .ready, complete: true))
        await Self.wait { model.presentation == .ready([row]) }

        let hidden = try SpaceID(validating: "space-hidden")
        #expect(!model.select(spaceId: hidden))
        #expect(model.selectedSpaceId == nil)
        #expect(model.select(spaceId: row.id))
        #expect(model.selectedSpaceId == row.id)

        source.yield(try Self.directory(rows: [], quality: .ready, complete: true))
        await Self.wait { model.presentation == .authoritativeEmpty }
        #expect(model.selectedSpaceId == nil)
        source.finish(throwing: SpaceAssignmentDestinationFailure.localReadFailed)
        await Self.wait { model.diagnostic == "space_assignment_destination_local_read_failed" }
        await model.stop()
    }

    @Test("Ready quality without query completeness fails closed, including empty rows")
    func incoherentReadyIncompleteFailsClosed() async throws {
        for rows in [
            [try Self.row("space-incoherent", "Incoherent")],
            [],
        ] {
            let source = SpaceDestinationControlledStream()
            let model = SpaceAssignmentDestinationStagingExercise(accountId: Self.accountId)
            await model.open(scope: Self.scope, runtime: .init(watch: { _ in source.stream }))
            source.yield(try Self.directory(rows: rows, quality: .ready, complete: false))
            await Self.wait {
                model.diagnostic == "space_assignment_destination_local_read_failed"
            }
            #expect(model.presentation != .authoritativeEmpty)
            #expect(model.rows.isEmpty)
            await model.stop()
        }
    }

    @Test("Replacement is exact-scope and late prior-request evidence is ignored")
    func replacementIgnoresLateEvidence() async throws {
        let project = SpaceDestinationControlledStream()
        let inventory = SpaceDestinationControlledStream()
        let scopes = SpaceDestinationScopeRecorder()
        let projectScope = Self.scope
        let runtime = SpaceAssignmentDestinationStagingRuntime { scope in
            scopes.record(scope)
            return scope == projectScope ? project.stream : inventory.stream
        }
        let model = SpaceAssignmentDestinationStagingExercise(accountId: Self.accountId)
        await model.open(scope: Self.scope, runtime: runtime)
        await Self.wait { scopes.values.count == 1 }
        await model.open(scope: .businessInventory, runtime: runtime)
        await Self.wait { scopes.values.count == 2 }
        project.yield(try Self.directory(rows: [Self.row("space-old", "Old")],
                                         quality: .ready, complete: true))
        inventory.yield(try Self.directory(scope: .businessInventory,
                                           rows: [Self.row("space-new", "New", scope: .businessInventory)],
                                           quality: .ready, complete: true))
        await Self.wait { model.rows.map(\.id.rawValue) == ["space-new"] }
        #expect(scopes.values == [Self.scope, .businessInventory])
        await model.stop()
        #expect(project.terminationCount == 1)
        #expect(inventory.terminationCount == 1)
    }

    private static let accountId = try! AccountID(validating: "account-space")
    private static let scope = ItemPlacementScope.project(
        try! ProjectID(validating: "project-space")
    )
    private static let observedAt = Date(timeIntervalSince1970: 1_788_600_000)

    private static func row(_ id: String, _ name: String,
                            scope: ItemPlacementScope = scope) throws
        -> SpaceAssignmentDestinationSnapshot
    {
        try .init(id: SpaceID(validating: id), accountId: accountId, scope: scope,
                  displayName: SpaceDisplayName(validating: name),
                  lifecycle: .active, revision: 1)
    }

    private static func directory(
        scope: ItemPlacementScope = scope,
        rows: [SpaceAssignmentDestinationSnapshot],
        quality: ListSnapshotQuality,
        complete: Bool
    ) throws -> SpaceAssignmentDestinationDirectorySnapshot {
        let request = try SpaceAssignmentDestinationRequest(accountId: accountId, scope: scope)
        return try .init(request: request, local: .init(
            queryFingerprint: request.queryFingerprint, rows: rows,
            visibleRowCountBeforeFiltering: rows.count,
            isCompleteForQuery: complete, quality: quality,
            localDataVersion: LocalDataVersion(validating: "space-presenter-\(quality.rawValue)-\(rows.count)"),
            asOf: observedAt
        ))
    }

    private static func wait(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<2_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Timed out waiting for presenter state")
    }
}

private final class SpaceDestinationControlledStream: @unchecked Sendable {
    let stream: AsyncThrowingStream<SpaceAssignmentDestinationDirectorySnapshot, Error>
    private let continuation: AsyncThrowingStream<SpaceAssignmentDestinationDirectorySnapshot, Error>.Continuation
    private let termination = SpaceDestinationTerminationCounter()
    init() {
        var captured: AsyncThrowingStream<SpaceAssignmentDestinationDirectorySnapshot, Error>.Continuation!
        let termination = termination
        stream = AsyncThrowingStream { value in
            captured = value
            value.onTermination = { _ in termination.record() }
        }
        continuation = captured
    }
    var terminationCount: Int { termination.value }
    func yield(_ value: SpaceAssignmentDestinationDirectorySnapshot) { continuation.yield(value) }
    func finish(throwing error: Error) { continuation.finish(throwing: error) }
}

private final class SpaceDestinationTerminationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func record() { lock.withLock { count += 1 } }
}

private final class SpaceDestinationScopeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var scopes: [ItemPlacementScope] = []
    var values: [ItemPlacementScope] { lock.withLock { scopes } }
    func record(_ scope: ItemPlacementScope) { lock.withLock { scopes.append(scope) } }
}
