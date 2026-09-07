import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetAppModel

@Suite("Scoped active Space browser staging orchestration")
@MainActor
struct SpaceBrowserStagingExerciseTests {
    @Test("Space name search is case-insensitive, literal and locale-independent")
    func nameSearch() {
        #expect(SpaceNameSearch.matches("Living Room", query: " ROOM \n"))
        #expect(SpaceNameSearch.matches("Living Room", query: " \n"))
        #expect(SpaceNameSearch.matches("Café", query: "CAFÉ"))
        #expect(!SpaceNameSearch.matches("Café", query: "cafe"))
        #expect(!SpaceNameSearch.matches("Living Room", query: "%"))
    }
    @Test("Project and Inventory directories preserve honest states and deterministic active rows")
    func directoryStatesOrderingAndScopeReplacement() async throws {
        let project = BrowserControlledSource<SpaceListUpdate>()
        let inventory = BrowserControlledSource<SpaceListUpdate>()
        let listRequests = BrowserRecorder<SpaceListRequest>()
        let projectScope = Self.projectScope
        let runtime = Self.runtime(
            list: { request in
                listRequests.record(request)
                return request.scope == projectScope ? project.stream : inventory.stream
            }
        )
        let model = Self.model()
        await model.start(scope: Self.projectScope, runtime: runtime)
        #expect(model.directoryPresentation == .waiting(.loading))
        await Self.wait { listRequests.values.count == 1 }
        #expect(listRequests.values[0].accountId == Self.accountId)
        #expect(listRequests.values[0].scope == Self.projectScope)

        project.yield(try Self.listUpdate(scope: Self.projectScope, state: .waiting(.blocked)))
        await Self.wait { model.directoryPresentation == .waiting(.blocked) }

        let sourceRows = try [
            Self.row("space-z", "loft", scope: Self.projectScope),
            Self.row("space-archived", "Archive", scope: Self.projectScope, lifecycle: .archived),
            Self.row("space-b", "Loft", scope: Self.projectScope),
            Self.row("space-a", "loft", scope: Self.projectScope),
        ]
        let partial = try Self.listSnapshot(
            scope: Self.projectScope, rows: sourceRows, quality: .partial, complete: false
        )
        project.yield(try Self.listUpdate(scope: Self.projectScope, state: .snapshot(partial)))
        await Self.wait {
            if case .partial = model.directoryPresentation { return true }
            return false
        }
        #expect(model.spaces.map(\.id.rawValue) == ["space-b", "space-a", "space-z"])
        model.searchText = " LOFT "
        #expect(model.matchingSpaces.map(\.id) == model.spaces.map(\.id))
        model.searchText = "absent"
        #expect(model.matchingSpaces.isEmpty)
        #expect(model.spaces.count == 3)
        if case .partial = model.directoryPresentation {} else {
            Issue.record("Search must not turn partial evidence into authoritative empty")
        }
        model.searchText = ""
        #expect(model.spaces.allSatisfy { $0.lifecycle == .active })
        #expect(model.spaces.allSatisfy { $0.itemCountState == .unavailable })

        let stale = try Self.listSnapshot(
            scope: Self.projectScope, rows: sourceRows, quality: .stale, complete: false
        )
        project.yield(try Self.listUpdate(scope: Self.projectScope, state: .snapshot(stale)))
        await Self.wait {
            if case .stale = model.directoryPresentation { return true }
            return false
        }

        let ready = try Self.listSnapshot(scope: Self.projectScope, rows: sourceRows)
        project.yield(try Self.listUpdate(scope: Self.projectScope, state: .snapshot(ready)))
        await Self.wait {
            if case .ready = model.directoryPresentation { return true }
            return false
        }
        project.yield(try Self.listUpdate(
            scope: Self.projectScope,
            state: .failed(failure: .retryable, cached: ready)
        ))
        await Self.wait { model.directoryDiagnostic == "space_list_retryable" }
        #expect(model.spaces.map(\.id.rawValue) == ["space-b", "space-a", "space-z"])
        #expect(model.directoryPresentation.snapshot?.quality == .stale)

        project.yield(try Self.listUpdate(
            scope: Self.projectScope,
            state: .snapshot(Self.listSnapshot(scope: Self.projectScope, rows: []))
        ))
        await Self.wait { model.directoryPresentation == .authoritativeEmpty }

        model.searchText = "previous Project query"
        await model.start(scope: .businessInventory, runtime: runtime)
        #expect(model.searchText.isEmpty)
        await Self.wait { listRequests.values.count == 2 }
        #expect(project.terminationCount == 1)
        let inventoryRow = try Self.row(
            "inventory-floor", "Main Floor", scope: .businessInventory
        )
        inventory.yield(try Self.listUpdate(
            scope: .businessInventory,
            state: .snapshot(Self.listSnapshot(scope: .businessInventory, rows: [inventoryRow]))
        ))
        await Self.wait { model.spaces.map(\.id) == [inventoryRow.id] }
        #expect(model.scope == .businessInventory)
        await model.stop()
        #expect(inventory.terminationCount == 1)
    }

    @Test("Stable-ID selection derives one exact detail request and reuses detail presentation")
    func exactSelectionAndDetailStates() async throws {
        let list = BrowserControlledSource<SpaceListUpdate>()
        let detail = BrowserControlledSource<SpaceCoreDetailsUpdate>()
        let detailRequests = BrowserRecorder<SpaceCoreDetailsRequest>()
        let model = Self.model()
        await model.start(scope: Self.projectScope, runtime: Self.runtime(
            list: { _ in list.stream },
            detail: { request in
                detailRequests.record(request)
                return detail.stream
            }
        ))
        let row = try Self.row("space-selected", "Same Name", scope: Self.projectScope)
        let duplicateName = try Self.row("space-other", "Same Name", scope: Self.projectScope)
        list.yield(try Self.listUpdate(
            scope: Self.projectScope,
            state: .snapshot(Self.listSnapshot(scope: Self.projectScope, rows: [duplicateName, row]))
        ))
        await Self.wait { model.spaces.count == 2 }
        await model.select(spaceId: row.id)
        await Self.wait { detailRequests.values.count == 1 }
        #expect(detailRequests.values[0] == (try SpaceCoreDetailsRequest(
            accountId: Self.accountId, spaceId: row.id
        )))
        #expect(model.selectedSpaceId == row.id)
        #expect(model.detailModel.presentation == .waiting(.loading))

        detail.yield(try Self.detailUpdate(id: row.id, state: .waiting(.blocked)))
        await Self.wait { model.detailModel.presentation == .waiting(.blocked) }
        let represented = try Self.detail(id: row.id, scope: Self.projectScope)
        detail.yield(try Self.detailSnapshotUpdate(
            id: row.id, rows: [represented], quality: .partial, complete: false
        ))
        await Self.wait { model.detailModel.presentation == .partial(represented) }
        detail.yield(try Self.detailSnapshotUpdate(
            id: row.id, rows: [represented], quality: .stale, complete: false
        ))
        await Self.wait { model.detailModel.presentation == .stale(represented) }
        detail.yield(try Self.detailSnapshotUpdate(id: row.id, rows: [represented]))
        await Self.wait { model.detailModel.presentation == .ready(represented) }
        #expect(model.detail == represented)

        let cached = try Self.detailSnapshot(id: row.id, rows: [represented])
        detail.yield(try Self.detailUpdate(
            id: row.id,
            state: .failed(failure: .requiredUpdate, cached: cached)
        ))
        await Self.wait { model.detailModel.diagnostic == "space_core_details_requiredUpdate" }
        #expect(model.detail == represented)

        await model.clearSelection()
        #expect(model.detailPresentation == .notSelected)
        #expect(detail.terminationCount == 1)
        await model.select(spaceId: try SpaceID(validating: "not-represented"))
        #expect(model.detailPresentation == .unavailable(previousSelection: nil))
        #expect(detailRequests.values.count == 1)
        await model.stop()
    }

    @Test("Authoritative disappearance and selection-mismatched detail become unavailable")
    func disappearanceAndMismatchedDetail() async throws {
        let list = BrowserControlledSource<SpaceListUpdate>()
        let detail = BrowserControlledSource<SpaceCoreDetailsUpdate>()
        let model = Self.model()
        await model.start(scope: Self.projectScope, runtime: Self.runtime(
            list: { _ in list.stream }, detail: { _ in detail.stream }
        ))
        let row = try Self.row("space-selected", "Selected", scope: Self.projectScope)
        list.yield(try Self.listUpdate(
            scope: Self.projectScope,
            state: .snapshot(Self.listSnapshot(scope: Self.projectScope, rows: [row]))
        ))
        await Self.wait { model.spaces == [try! SpaceDirectoryRowPresentation(sourceRow: row)] }
        await model.select(spaceId: row.id)

        let wrongScope = try Self.detail(id: row.id, scope: .businessInventory)
        detail.yield(try Self.detailSnapshotUpdate(id: row.id, rows: [wrongScope]))
        await Self.wait {
            if case .unavailable(let prior) = model.detailPresentation { return prior?.id == row.id }
            return false
        }
        #expect(model.detail == nil)

        await model.clearSelection()
        let list2 = BrowserControlledSource<SpaceListUpdate>()
        let detail2 = BrowserControlledSource<SpaceCoreDetailsUpdate>()
        let runtime2 = Self.runtime(list: { _ in list2.stream }, detail: { _ in detail2.stream })
        await model.start(scope: Self.projectScope, runtime: runtime2)
        list2.yield(try Self.listUpdate(
            scope: Self.projectScope,
            state: .snapshot(Self.listSnapshot(scope: Self.projectScope, rows: [row], version: "again"))
        ))
        await Self.wait { model.spaces.count == 1 }
        await model.select(spaceId: row.id)
        detail2.yield(try Self.detailSnapshotUpdate(id: row.id, rows: [Self.detail(id: row.id)]))
        await Self.wait { model.detail != nil }

        list2.yield(try Self.listUpdate(
            scope: Self.projectScope,
            state: .snapshot(Self.listSnapshot(scope: Self.projectScope, rows: [], version: "gone"))
        ))
        await Self.wait {
            if case .unavailable(let prior) = model.detailPresentation { return prior?.id == row.id }
            return false
        }
        #expect(detail2.terminationCount == 1)
        await model.stop()
    }

    @Test("Any latest directory without the selected row invalidates, while exact cached evidence retains")
    func incompleteAndFailedDirectorySelectionInvalidation() async throws {
        for terminal in ["partial", "stale", "failure"] {
            let list = BrowserControlledSource<SpaceListUpdate>()
            let detail = BrowserControlledSource<SpaceCoreDetailsUpdate>()
            let model = Self.model()
            await model.start(scope: Self.projectScope, runtime: Self.runtime(
                list: { _ in list.stream }, detail: { _ in detail.stream }
            ))
            let row = try Self.row(
                "space-selected-\(terminal)", "Selected", scope: Self.projectScope
            )
            let represented = try Self.listSnapshot(
                scope: Self.projectScope, rows: [row], version: "represented-\(terminal)"
            )
            list.yield(try Self.listUpdate(
                scope: Self.projectScope, state: .snapshot(represented)
            ))
            await Self.wait { model.spaces.count == 1 }
            await model.select(spaceId: row.id)
            detail.yield(try Self.detailSnapshotUpdate(
                id: row.id, rows: [Self.detail(id: row.id)]
            ))
            await Self.wait { model.detail?.id == row.id }

            list.yield(try Self.listUpdate(
                scope: Self.projectScope,
                state: .failed(failure: .retryable, cached: represented)
            ))
            await Self.wait { model.directoryDiagnostic == "space_list_retryable" }
            #expect(model.selectedSpaceId == row.id)
            #expect(detail.terminationCount == 0)

            let emptyState: SpaceListUpdateState
            switch terminal {
            case "partial":
                emptyState = .snapshot(try Self.listSnapshot(
                    scope: Self.projectScope,
                    rows: [],
                    quality: .partial,
                    complete: false,
                    version: "partial-empty"
                ))
            case "stale":
                emptyState = .snapshot(try Self.listSnapshot(
                    scope: Self.projectScope,
                    rows: [],
                    quality: .stale,
                    complete: false,
                    version: "stale-empty"
                ))
            default:
                emptyState = .failed(failure: .requiredUpdate, cached: nil)
            }
            list.yield(try Self.listUpdate(scope: Self.projectScope, state: emptyState))
            await Self.wait {
                if case .unavailable(let previous) = model.detailPresentation {
                    return previous?.id == row.id
                }
                return false
            }
            #expect(detail.terminationCount == 1)
            #expect(model.detail == nil)
            await model.stop()
        }
    }

    @Test("Scope and selection replacement fence late noncooperative emissions and fully drain")
    func generationFencingAndDrainage() async throws {
        let lateList = BrowserDelayedSource<SpaceListUpdate>()
        let currentList = BrowserControlledSource<SpaceListUpdate>()
        let lateDetail = BrowserDelayedSource<SpaceCoreDetailsUpdate>()
        let currentDetail = BrowserControlledSource<SpaceCoreDetailsUpdate>()
        let listRequests = BrowserRecorder<SpaceListRequest>()
        let projectScope = Self.projectScope
        let spaceA = Self.spaceA
        let runtime = Self.runtime(
            list: { request in
                listRequests.record(request)
                return request.scope == projectScope ? lateList.stream : currentList.stream
            },
            detail: { request in
                request.spaceId == spaceA ? lateDetail.stream : currentDetail.stream
            }
        )
        let model = Self.model()
        await model.start(scope: Self.projectScope, runtime: runtime)
        #expect(await Self.waitAsync { await lateList.isWaiting })
        let listProbe = BrowserCompletionProbe()
        let replaceList = Task { @MainActor in
            listProbe.start()
            await model.start(scope: .businessInventory, runtime: runtime)
            listProbe.finish()
        }
        await Self.wait { listProbe.didStart }
        #expect(model.scope == .businessInventory)
        #expect(!listProbe.didFinish)
        await lateList.release(try Self.listUpdate(
            scope: Self.projectScope,
            state: .snapshot(Self.listSnapshot(
                scope: Self.projectScope,
                rows: [Self.row("late-project", "Late", scope: Self.projectScope)]
            ))
        ))
        await replaceList.value
        #expect(model.spaces.isEmpty)

        let a = try Self.row(Self.spaceA.rawValue, "A", scope: .businessInventory)
        let b = try Self.row(Self.spaceB.rawValue, "B", scope: .businessInventory)
        currentList.yield(try Self.listUpdate(
            scope: .businessInventory,
            state: .snapshot(Self.listSnapshot(scope: .businessInventory, rows: [a, b]))
        ))
        await Self.wait { model.spaces.count == 2 }
        await model.select(spaceId: Self.spaceA)
        #expect(await Self.waitAsync { await lateDetail.isWaiting })

        let detailProbe = BrowserCompletionProbe()
        let replaceDetail = Task { @MainActor in
            detailProbe.start()
            await model.select(spaceId: Self.spaceB)
            detailProbe.finish()
        }
        await Self.wait { detailProbe.didStart }
        #expect(!detailProbe.didFinish)
        await lateDetail.release(try Self.detailSnapshotUpdate(
            id: Self.spaceA,
            rows: [Self.detail(id: Self.spaceA, scope: .businessInventory)]
        ))
        await replaceDetail.value
        #expect(model.selectedSpaceId == Self.spaceB)
        #expect(model.detail == nil)
        currentDetail.yield(try Self.detailSnapshotUpdate(
            id: Self.spaceB,
            rows: [Self.detail(id: Self.spaceB, scope: .businessInventory)]
        ))
        await Self.wait { model.detail?.id == Self.spaceB }
        await model.stop()
        #expect(currentList.terminationCount == 1)
        #expect(currentDetail.terminationCount == 1)
    }

    @Test("Malformed ready completeness and terminal failures stay bounded")
    func invalidAndTerminalFailures() async throws {
        let list = BrowserControlledSource<SpaceListUpdate>()
        let model = Self.model()
        await model.start(scope: Self.projectScope, runtime: Self.runtime(list: { _ in list.stream }))
        list.yield(try Self.listUpdate(
            scope: Self.projectScope,
            state: .snapshot(Self.listSnapshot(
                scope: Self.projectScope,
                rows: [Self.row("incomplete", "Incomplete", scope: Self.projectScope)],
                quality: .ready,
                complete: false
            ))
        ))
        await Self.wait {
            model.directoryDiagnostic == SpaceListFailure.invalidCompleteness.diagnosticCode
        }
        #expect(model.spaces.isEmpty)
        await model.stop()

        let completed = BrowserControlledSource<SpaceListUpdate>()
        await model.start(scope: .businessInventory, runtime: Self.runtime(list: { _ in completed.stream }))
        completed.finish()
        await Self.wait { model.directoryDiagnostic == "space_list_source_completed" }
        await model.stop()
    }

    private static let accountId = try! AccountID(validating: "account-space-browser")
    private static let projectId = try! ProjectID(validating: "project-space-browser")
    private static let projectScope = SpaceCreationScope.project(projectId)
    private static let spaceA = try! SpaceID(validating: "space-a")
    private static let spaceB = try! SpaceID(validating: "space-b")
    private static let observedAt = Date(timeIntervalSince1970: 1_789_000_000)

    private static func model() -> SpaceBrowserStagingExercise {
        SpaceBrowserStagingExercise(accountId: accountId)
    }

    private static func runtime(
        list: @escaping @Sendable (SpaceListRequest) -> AsyncThrowingStream<SpaceListUpdate, Error>,
        detail: @escaping @Sendable (SpaceCoreDetailsRequest)
            -> AsyncThrowingStream<SpaceCoreDetailsUpdate, Error> = { _ in
                AsyncThrowingStream { _ in }
            }
    ) -> SpaceBrowserStagingRuntime {
        SpaceBrowserStagingRuntime(
            listQuery: BrowserListQuery(watch: list),
            detailQuery: BrowserDetailQuery(watch: detail)
        )
    }

    private static func row(
        _ id: String,
        _ name: String,
        scope: SpaceCreationScope,
        lifecycle: DirectoryLifecycleState = .active
    ) throws -> SpaceListSourceRow {
        SpaceListSourceRow(
            id: try SpaceID(validating: id),
            accountId: accountId,
            scope: scope,
            displayName: try SpaceDisplayName(validating: name),
            lifecycle: lifecycle,
            revision: 1,
            checklists: try SpaceChecklistCollection(checklists: [])
        )
    }

    private static func listSnapshot(
        scope: SpaceCreationScope,
        rows: [SpaceListSourceRow],
        quality: ListSnapshotQuality = .ready,
        complete: Bool = true,
        version: String = "space-browser-list"
    ) throws -> SpaceListLocalSnapshot {
        let request = try SpaceListRequest(accountId: accountId, scope: scope)
        return try SpaceListLocalSnapshot(
            request: request,
            rows: rows,
            visibleRowCountBeforeFiltering: rows.count,
            isCompleteForQuery: complete,
            quality: quality,
            localDataVersion: LocalDataVersion(validating: "\(version)-\(quality.rawValue)"),
            asOf: observedAt
        )
    }

    private static func listUpdate(
        scope: SpaceCreationScope,
        state: SpaceListUpdateState
    ) throws -> SpaceListUpdate {
        try SpaceListUpdate(
            request: SpaceListRequest(accountId: accountId, scope: scope),
            state: state
        )
    }

    private static func detail(
        id: SpaceID,
        scope: SpaceCreationScope = projectScope
    ) throws -> SpaceCoreDetailsSnapshot {
        try SpaceCoreDetailsSnapshot(
            id: id,
            accountId: accountId,
            scope: scope,
            displayName: SpaceDisplayName(validating: "Detail \(id.rawValue)"),
            notes: SpaceCreationNotes(nil),
            lifecycle: .active,
            revision: 2,
            createdAt: observedAt,
            updatedAt: observedAt,
            checklists: SpaceChecklistCollection(checklists: [])
        )
    }

    private static func detailSnapshot(
        id: SpaceID,
        rows: [SpaceCoreDetailsSnapshot],
        quality: ListSnapshotQuality = .ready,
        complete: Bool = true
    ) throws -> SpaceCoreDetailsLocalSnapshot {
        let request = try SpaceCoreDetailsRequest(accountId: accountId, spaceId: id)
        return try SpaceCoreDetailsLocalSnapshot(
            request: request,
            rows: rows,
            visibleRowCountBeforeFiltering: rows.count,
            isCompleteForQuery: complete,
            quality: quality,
            localDataVersion: LocalDataVersion(validating: "space-browser-detail-\(quality.rawValue)"),
            asOf: observedAt
        )
    }

    private static func detailUpdate(
        id: SpaceID,
        state: SpaceCoreDetailsUpdateState
    ) throws -> SpaceCoreDetailsUpdate {
        try SpaceCoreDetailsUpdate(
            request: SpaceCoreDetailsRequest(accountId: accountId, spaceId: id),
            state: state
        )
    }

    private static func detailSnapshotUpdate(
        id: SpaceID,
        rows: [SpaceCoreDetailsSnapshot],
        quality: ListSnapshotQuality = .ready,
        complete: Bool = true
    ) throws -> SpaceCoreDetailsUpdate {
        try detailUpdate(
            id: id,
            state: .snapshot(try detailSnapshot(
                id: id, rows: rows, quality: quality, complete: complete
            ))
        )
    }

    private static func wait(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<2_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Timed out waiting for Space browser state")
    }

    private static func waitAsync(
        _ condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0..<2_000 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }
}

private struct BrowserListQuery: SpaceListQuerying {
    let watch: @Sendable (SpaceListRequest) -> AsyncThrowingStream<SpaceListUpdate, Error>
    func watchSpaces(_ request: SpaceListRequest) -> AsyncThrowingStream<SpaceListUpdate, Error> {
        watch(request)
    }
}

private struct BrowserDetailQuery: SpaceCoreDetailsQuerying {
    let watch: @Sendable (SpaceCoreDetailsRequest)
        -> AsyncThrowingStream<SpaceCoreDetailsUpdate, Error>
    func watchSpaceCoreDetails(
        _ request: SpaceCoreDetailsRequest
    ) -> AsyncThrowingStream<SpaceCoreDetailsUpdate, Error> {
        watch(request)
    }
}

private final class BrowserControlledSource<Value: Sendable>: @unchecked Sendable {
    let stream: AsyncThrowingStream<Value, Error>
    private let continuation: AsyncThrowingStream<Value, Error>.Continuation
    private let terminations = BrowserCounter()

    init() {
        var captured: AsyncThrowingStream<Value, Error>.Continuation!
        let terminations = terminations
        stream = AsyncThrowingStream { continuation in
            captured = continuation
            continuation.onTermination = { _ in terminations.increment() }
        }
        continuation = captured
    }

    var terminationCount: Int { terminations.value }
    func yield(_ value: Value) { continuation.yield(value) }
    func finish() { continuation.finish() }
}

private final class BrowserDelayedSource<Value: Sendable>: @unchecked Sendable {
    let stream: AsyncThrowingStream<Value, Error>
    private let gate: BrowserDelayedGate<Value>

    init() {
        let gate = BrowserDelayedGate<Value>()
        self.gate = gate
        stream = AsyncThrowingStream(unfolding: { await gate.next() })
    }

    var isWaiting: Bool { get async { await gate.isWaiting } }
    func release(_ value: Value) async { await gate.release(value) }
}

private actor BrowserDelayedGate<Value: Sendable> {
    private var continuation: CheckedContinuation<Value?, Never>?
    var isWaiting: Bool { continuation != nil }

    func next() async -> Value? {
        await withCheckedContinuation { continuation = $0 }
    }

    func release(_ value: Value) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}

private final class BrowserRecorder<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Value] = []
    var values: [Value] { lock.withLock { recorded } }
    func record(_ value: Value) { lock.withLock { recorded.append(value) } }
}

private final class BrowserCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private final class BrowserCompletionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    private var finished = false
    var didStart: Bool { lock.withLock { started } }
    var didFinish: Bool { lock.withLock { finished } }
    func start() { lock.withLock { started = true } }
    func finish() { lock.withLock { finished = true } }
}
