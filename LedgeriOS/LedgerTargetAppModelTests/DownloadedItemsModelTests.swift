import Foundation
import LedgerTargetCore
import LedgerTargetAppModel
import Testing

@Suite("Downloaded Items presentation") @MainActor
struct DownloadedItemsModelTests {
    private let account = try! AccountID(validating: "account-items")

    @Test("Project Items consume one combined stream and keep unknown Items visible")
    func combinedProjectRead() async throws {
        let snapshot = try projectSnapshot()
        let model = DownloadedItemsModel()
        await model.load(accountId: account, scope: snapshot.placements.scope,
                         reader: ProjectReader(snapshots: [snapshot]))
        #expect(model.state == .downloaded(snapshot.placements))
        #expect(model.accounting == snapshot.accounting)
        #expect(model.accounting?.unresolvedRows.count == 1)
        model.clear()
        #expect(model.accounting == nil)
        #expect(model.state == .idle)
    }

    @Test("Loss of accounting evidence retains physical Items without stale accounting")
    func accountingBecomesUnavailable() async throws {
        let known = try projectSnapshot()
        let unknown = try DownloadedProjectItems(placements: known.placements, accounting: nil)
        let model = DownloadedItemsModel()
        await model.load(accountId: account, scope: known.placements.scope,
                         reader: ProjectReader(snapshots: [known, unknown]))
        #expect(model.state == .downloaded(known.placements))
        #expect(model.accounting == nil)
    }

    @Test("Project stream failure removes both physical and accounting data")
    func projectStreamFailure() async throws {
        let snapshot = try projectSnapshot()
        let model = DownloadedItemsModel()
        await model.load(accountId: account, scope: snapshot.placements.scope,
                         reader: ProjectReader(snapshots: [snapshot], fails: true))
        #expect(model.state == .unavailable)
        #expect(model.accounting == nil)
    }

    @Test("Wrong Project snapshot is rejected after a valid snapshot")
    func wrongProjectCombinedRead() async throws {
        let snapshot = try projectSnapshot()
        let foreign = try projectSnapshot(project: "foreign-project")
        let model = DownloadedItemsModel()
        await model.load(accountId: account, scope: snapshot.placements.scope,
                         reader: ProjectReader(snapshots: [snapshot, foreign]))
        #expect(model.state == .unavailable)
        #expect(model.accounting == nil)
    }

    private func projectSnapshot(project: String = "project-items") throws -> DownloadedProjectItems {
        let projectId = try ProjectID(validating: project)
        let itemId = try ItemID(validating: "project-chair")
        let clientId = try ClientID(validating: "client-items")
        let physical = try DownloadedItemPlacements(accountId: account, scope: .project(projectId), rows: [
            PhysicalItemPlacement(itemId: itemId, description: "Chair", itemRevision: 1,
                placementId: .init(validating: "placement-chair"), scope: .project(projectId), spaceId: nil)
        ])
        let accounting = try ProjectItemAccountingSectionsSnapshot(accountId: account, projectId: projectId,
            clientId: clientId, items: [.init(accountId: account, projectId: projectId, clientId: clientId, itemId: itemId)],
            isCompleteForAccounting: false, quality: .ready, localDataVersion: .init(validating: "project-items-v1"), asOf: Date())
        return try .init(placements: physical, accounting: accounting)
    }

    @Test("Later downloaded rows replace the initial snapshot without another load")
    func reactiveUpdates() async throws {
        let empty = try DownloadedItemPlacements(accountId: account, scope: .businessInventory, rows: [])
        let chair = try PhysicalItemPlacement(itemId: ItemID(validating: "chair"), description: "Chair",
            itemRevision: 2, placementId: EntityID(validating: "placement"), scope: .businessInventory, spaceId: nil)
        let updated = try DownloadedItemPlacements(accountId: account, scope: .businessInventory, rows: [chair])
        let model = DownloadedItemsModel()
        await model.load(accountId: account, scope: .businessInventory,
                         reader: SequenceReader(snapshots: [empty, updated]))
        #expect(model.state == .downloaded(updated))
    }

    @Test("Watch failure clears previously displayed rows")
    func streamFailure() async throws {
        let snapshot = try DownloadedItemPlacements(accountId: account, scope: .businessInventory, rows: [])
        let model = DownloadedItemsModel()
        await model.load(accountId: account, scope: .businessInventory,
                         reader: SequenceReader(snapshots: [snapshot], fails: true))
        #expect(model.state == .unavailable)
    }

    @Test("A foreign update after valid data clears presentation")
    func foreignUpdate() async throws {
        let valid = try DownloadedItemPlacements(accountId: account, scope: .businessInventory, rows: [])
        let foreign = try DownloadedItemPlacements(accountId: AccountID(validating: "foreign"), scope: .businessInventory, rows: [])
        let model = DownloadedItemsModel()
        await model.load(accountId: account, scope: .businessInventory,
                         reader: SequenceReader(snapshots: [valid, foreign]))
        #expect(model.state == .unavailable)
    }

    @Test("A stream ending without a snapshot does not leave an endless spinner")
    func emptyStream() async {
        let model = DownloadedItemsModel()
        await model.load(accountId: account, scope: .businessInventory, reader: SequenceReader(snapshots: []))
        #expect(model.state == .unavailable)
    }

    @Test("Downloaded emptiness is represented without a completeness claim")
    func empty() async throws {
        let snapshot = try DownloadedItemPlacements(accountId: account, scope: .businessInventory, rows: [])
        let model = DownloadedItemsModel()
        await model.load(accountId: account, scope: .businessInventory, reader: ImmediateReader(snapshot: snapshot))
        #expect(model.state == .downloaded(snapshot))
        model.clear()
        #expect(model.state == .idle)
    }

    @Test("Foreign Account and wrong placement scope never reach presentation", arguments: [false, true])
    func wrongScope(foreignAccount: Bool) async throws {
        let snapshot = try DownloadedItemPlacements(
            accountId: foreignAccount ? AccountID(validating: "foreign") : account,
            scope: foreignAccount ? .businessInventory : .project(ProjectID(validating: "other-project")), rows: [])
        let model = DownloadedItemsModel()
        await model.load(accountId: account, scope: .businessInventory, reader: ImmediateReader(snapshot: snapshot))
        #expect(model.state == .unavailable)
    }

    @Test("Clearing or replacing a request suppresses its delayed result", arguments: [false, true])
    func staleResult(replace: Bool) async throws {
        let model = DownloadedItemsModel()
        let oldReader = SuspendedReader()
        let oldSnapshot = try DownloadedItemPlacements(accountId: account, scope: .businessInventory, rows: [])
        let old = Task { await model.load(accountId: account, scope: .businessInventory, reader: oldReader) }
        await oldReader.waitUntilStarted()
        #expect(model.state == .loading)
        var expected = DownloadedItemsState.idle
        if replace {
            let scope = ItemPlacementScope.project(try ProjectID(validating: "new-project"))
            let newer = try DownloadedItemPlacements(accountId: account, scope: scope, rows: [])
            await model.load(accountId: account, scope: scope, reader: ImmediateReader(snapshot: newer))
            expected = .downloaded(newer)
        } else { model.clear() }
        await oldReader.finish(oldSnapshot)
        await old.value
        #expect(model.state == expected)
    }

    @Test("Cancellation suppresses a reader that returns after cancellation")
    func cancellation() async throws {
        let model = DownloadedItemsModel()
        let reader = SuspendedReader()
        let task = Task { await model.load(accountId: account, scope: .businessInventory, reader: reader) }
        await reader.waitUntilStarted()
        task.cancel()
        await reader.finish(try DownloadedItemPlacements(accountId: account, scope: .businessInventory, rows: []))
        await task.value
        #expect(model.state == .idle)
    }
}

private struct ProjectReader: DownloadedItemPlacementReading, DownloadedProjectItemsReading {
    let snapshots: [DownloadedProjectItems]
    var fails = false
    enum Failure: Error { case unavailable, separatePhysicalRead }
    func watchDownloadedProjectItems(accountId: AccountID, projectId: ProjectID) -> AsyncThrowingStream<DownloadedProjectItems, Error> {
        AsyncThrowingStream { continuation in
            for snapshot in snapshots { continuation.yield(snapshot) }
            if fails { continuation.finish(throwing: Failure.unavailable) }
            else { continuation.finish() }
        }
    }
    func readDownloadedItemPlacements(accountId: AccountID, scope: ItemPlacementScope) async throws -> DownloadedItemPlacements {
        throw Failure.separatePhysicalRead
    }
    func watchDownloadedItemPlacements(accountId: AccountID, scope: ItemPlacementScope) -> AsyncThrowingStream<DownloadedItemPlacements, Error> {
        AsyncThrowingStream { $0.finish(throwing: Failure.separatePhysicalRead) }
    }
}

private struct ImmediateReader: DownloadedItemPlacementReading {
    let snapshot: DownloadedItemPlacements
    func watchDownloadedItemPlacements(accountId: AccountID, scope: ItemPlacementScope) -> AsyncThrowingStream<DownloadedItemPlacements, Error> {
        AsyncThrowingStream { $0.yield(snapshot); $0.finish() }
    }
    func readDownloadedItemPlacements(accountId: AccountID, scope: ItemPlacementScope) async throws -> DownloadedItemPlacements { snapshot }
}

private struct SequenceReader: DownloadedItemPlacementReading {
    let snapshots: [DownloadedItemPlacements]
    var fails = false
    enum Failure: Error { case unavailable }
    func readDownloadedItemPlacements(accountId: AccountID, scope: ItemPlacementScope) async throws -> DownloadedItemPlacements {
        guard let first = snapshots.first else { throw Failure.unavailable }
        return first
    }
    func watchDownloadedItemPlacements(accountId: AccountID, scope: ItemPlacementScope) -> AsyncThrowingStream<DownloadedItemPlacements, Error> {
        AsyncThrowingStream { continuation in
            for snapshot in snapshots { continuation.yield(snapshot) }
            if fails { continuation.finish(throwing: Failure.unavailable) }
            else { continuation.finish() }
        }
    }
}

private actor SuspendedReader: DownloadedItemPlacementReading {
    nonisolated func watchDownloadedItemPlacements(accountId: AccountID, scope: ItemPlacementScope) -> AsyncThrowingStream<DownloadedItemPlacements, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(try await readDownloadedItemPlacements(accountId: accountId, scope: scope))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    private var pending: CheckedContinuation<DownloadedItemPlacements, Never>?
    private var started: [CheckedContinuation<Void, Never>] = []
    func readDownloadedItemPlacements(accountId: AccountID, scope: ItemPlacementScope) async throws -> DownloadedItemPlacements {
        await withCheckedContinuation { continuation in
            pending = continuation
            started.forEach { $0.resume() }
            started.removeAll()
        }
    }
    func waitUntilStarted() async {
        if pending != nil { return }
        await withCheckedContinuation { started.append($0) }
    }
    func finish(_ snapshot: DownloadedItemPlacements) {
        pending?.resume(returning: snapshot)
        pending = nil
    }
}
