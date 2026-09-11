import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetAppModel

@Suite("Inventory navigation suspension fences")
@MainActor
struct InventoryNavigationRaceTests {
    @Test("Changing sections during selection cleanup cannot open a Space detail")
    func sectionChangeDuringSelectionCleanup() async throws {
        let fixture = try Fixture()
        await fixture.model.start(runtime: fixture.runtime)
        await fixture.model.openBusinessInventory(savedSection: "spaces")
        await fixture.directory.consumed.wait()
        #expect(fixture.model.spaceBrowser.spaces.count == 1)
        await fixture.seedCleanupObservation()

        let selection = Task { await fixture.model.selectSpace(spaceId: Fixture.spaceId) }
        await fixture.cleanup.cancelled.wait()
        #expect(fixture.model.route == .businessInventory)
        fixture.model.selectInventorySection(.transactions)
        await fixture.cleanup.release.open()
        await selection.value

        #expect(fixture.model.inventorySection == .transactions)
        #expect(fixture.model.route == .businessInventory)
        #expect(fixture.model.spaceBrowser.selectedSpaceId == nil)
        #expect(fixture.model.checklistToggle.selectedSpaceId == nil)
        await fixture.directory.release.open()
        await fixture.model.stop()
    }

    @Test("Changing sections during Inventory initialization preserves reader startup")
    func sectionChangeDuringInitialization() async throws {
        let fixture = try Fixture()
        await fixture.model.start(runtime: fixture.runtime)
        await fixture.seedCleanupObservation()

        let opening = Task { await fixture.model.openBusinessInventory(savedSection: "items") }
        await fixture.cleanup.cancelled.wait()
        #expect(fixture.model.route == .businessInventory)
        #expect(fixture.model.spaceBrowser.scope == nil)
        fixture.model.selectInventorySection(.spaces)
        await fixture.cleanup.release.open()
        await opening.value
        await fixture.directory.consumed.wait()

        #expect(fixture.model.inventorySection == .spaces)
        #expect(fixture.model.route == .businessInventory)
        #expect(fixture.model.spaceBrowser.scope == .businessInventory)
        #expect(fixture.model.spaceBrowser.spaces.map(\.id) == [Fixture.spaceId])
        await fixture.directory.release.open()
        await fixture.model.stop()
    }

    @MainActor
    private struct Fixture {
        static let accountId = try! AccountID(validating: "inventory-race-account")
        static let spaceId = try! SpaceID(validating: "inventory-race-space")
        let model: ActiveWorkspaceToSpaceChecklistStagingExercise
        let runtime: ActiveWorkspaceToSpaceChecklistStagingRuntime
        let cleanup = InventoryCleanupGate()
        let directory: InventoryDirectoryGate

        init() throws {
            let request = try SpaceListRequest(accountId: Self.accountId, scope: .businessInventory)
            let row = SpaceListSourceRow(
                id: Self.spaceId, accountId: Self.accountId, scope: .businessInventory,
                displayName: try SpaceDisplayName(validating: "Inventory Space"),
                lifecycle: .active, revision: 1,
                checklists: try SpaceChecklistCollection(checklists: [])
            )
            directory = InventoryDirectoryGate(update: try SpaceListUpdate(
                request: request,
                state: .snapshot(SpaceListLocalSnapshot(
                    request: request, rows: [row], visibleRowCountBeforeFiltering: 1,
                    isCompleteForQuery: true, quality: .ready,
                    localDataVersion: LocalDataVersion(validating: "inventory-race-version"),
                    asOf: Date(timeIntervalSince1970: 1_789_500_000)
                ))
            ))
            let toggle = SpaceChecklistItemToggleStagingExercise(
                accountId: Self.accountId,
                actorPrincipalId: try PrincipalID(validating: "inventory-race-principal"),
                operationContractVersion: try OperationContractVersion(validating: "space-checklist-revision-v1"),
                makeIdentity: {
                    SpaceChecklistItemToggleSubmissionIdentity(
                        operationId: try OperationID(validating: "inventory-race-operation")
                    )
                },
                now: { Date(timeIntervalSince1970: 1_789_500_000) }
            )
            model = ActiveWorkspaceToSpaceChecklistStagingExercise(
                accountId: Self.accountId,
                projectBrowser: ProjectBrowsingStagingExercise(accountId: Self.accountId),
                spaceBrowser: SpaceBrowserStagingExercise(accountId: Self.accountId),
                checklistToggle: toggle
            )
            let cleanup = cleanup
            runtime = ActiveWorkspaceToSpaceChecklistStagingRuntime(
                projectBrowsing: ProjectBrowsingStagingRuntime(
                    watchProjects: { AsyncThrowingStream { _ in } },
                    watchProject: { _ in AsyncThrowingStream { _ in } }
                ),
                spaceBrowsing: SpaceBrowserStagingRuntime(
                    listQuery: InventoryRaceListQuery(gate: directory),
                    detailQuery: InventoryRaceDetailQuery()
                ),
                checklistToggle: SpaceChecklistItemToggleStagingRuntime(
                    reviseChecklists: { _ in throw CancellationError() },
                    watchOperation: { _ in AsyncThrowingStream { _ in } },
                    rejectedOperations: { try RejectedOperationRecoverySnapshot(request: $0, candidates: []) },
                    watchRejectedOperations: { _ in
                        AsyncThrowingStream(unfolding: { await cleanup.next() })
                    }
                )
            )
        }

        // Seed the existing public child model to represent an observation that
        // must drain. No private route mutation or production test hook is needed.
        func seedCleanupObservation() async {
            await model.checklistToggle.receiveDetailUpdate(nil, selectedSpaceId: Self.spaceId)
            await cleanup.entered.wait()
        }
    }
}

private actor InventoryRaceSignal {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        // A broken fence must fail the test and release its suspended work,
        // rather than hanging the entire suite. This timer never drives success.
        let timeout = Task {
            do { try await Task.sleep(for: .seconds(5)) }
            catch { return }
            Issue.record("Timed out waiting for an Inventory race signal")
            open()
        }
        await withCheckedContinuation { waiters.append($0) }
        timeout.cancel()
    }
    func open() {
        opened = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private struct InventoryCleanupGate: Sendable {
    let entered = InventoryRaceSignal()
    let cancelled = InventoryRaceSignal()
    let release = InventoryRaceSignal()
    func next() async -> RejectedOperationRecoverySnapshot? {
        await withTaskCancellationHandler {
            await entered.open()
            await release.wait()
            return nil
        } onCancel: {
            Task { await cancelled.open() }
        }
    }
}

private actor InventoryDirectoryGate {
    let consumed = InventoryRaceSignal()
    let release = InventoryRaceSignal()
    private var update: SpaceListUpdate?
    init(update: SpaceListUpdate) { self.update = update }
    func next() async -> SpaceListUpdate? {
        if let update {
            self.update = nil
            return update
        }
        // The consumer requests the second element only after projecting the first.
        await consumed.open()
        await release.wait()
        return nil
    }
}

private struct InventoryRaceListQuery: SpaceListQuerying {
    let gate: InventoryDirectoryGate
    func watchSpaces(_ request: SpaceListRequest) -> AsyncThrowingStream<SpaceListUpdate, Error> {
        AsyncThrowingStream(unfolding: { await gate.next() })
    }
}

private struct InventoryRaceDetailQuery: SpaceCoreDetailsQuerying {
    func watchSpaceCoreDetails(_ request: SpaceCoreDetailsRequest) -> AsyncThrowingStream<SpaceCoreDetailsUpdate, Error> {
        AsyncThrowingStream { _ in }
    }
}
