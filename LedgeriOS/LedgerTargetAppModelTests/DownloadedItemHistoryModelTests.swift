import LedgerTargetCore
import LedgerTargetAppModel
import Testing

@Suite("Downloaded physical Item history presentation") @MainActor
struct DownloadedItemHistoryModelTests {
    private let account = try! AccountID(validating: "account-history")
    private let item = try! ItemID(validating: "item-history")

    @Test("Current accounting evidence replaces old labels and is removed on access loss")
    func accountingUpdates() async throws {
        let (stream, continuation) = AsyncThrowingStream<DownloadedItemPlacementHistory, Error>.makeStream()
        let model = DownloadedItemHistoryModel()
        let task = Task {
            await model.load(accountId: account, itemId: item,
                reader: HistoryReader(values: [], stream: stream))
        }
        defer { continuation.finish(); task.cancel() }
        for resolution in [ProjectItemAccountingResolution.accountedFor, .relationshipEvidenceIncomplete, nil] {
            let snapshot = try DownloadedItemPlacementHistory(accountId: account, itemId: item,
                description: "Chair", intervals: [
                    .init(placementId: EntityID(validating: "placement"),
                        scope: .project(ProjectID(validating: "project")), spaceId: nil,
                        startedAt: "2026-09-01T00:00:00Z", endedAt: nil)
                ], currentAccountingResolution: resolution)
            continuation.yield(snapshot)
            for _ in 0..<1000 {
                if model.state == .downloaded(snapshot) { break }
                await Task.yield()
            }
            #expect(model.state == .downloaded(snapshot))
        }
        continuation.finish(throwing: HistoryReader.Failure.unavailable)
        await task.value
        #expect(model.state == .unavailable)
    }

    @Test("Category readback changes and unavailable evidence replace the displayed label")
    func categoryUpdates() async throws {
        let (stream, continuation) = AsyncThrowingStream<DownloadedItemPlacementHistory, Error>.makeStream()
        let model = DownloadedItemHistoryModel()
        let task = Task {
            await model.load(accountId: account, itemId: item,
                reader: HistoryReader(values: [], stream: stream))
        }
        defer { continuation.finish(); task.cancel() }
        for category in ["Furniture", "Lighting", nil] as [String?] {
            let snapshot = try DownloadedItemPlacementHistory(accountId: account, itemId: item,
                description: "Chair", intervals: [
                    .init(placementId: EntityID(validating: "placement"),
                        scope: .project(ProjectID(validating: "project")), spaceId: nil,
                        startedAt: "2026-09-01T00:00:00Z", endedAt: nil)
                ], currentBudgetCategoryName: category)
            continuation.yield(snapshot)
            for _ in 0..<1000 {
                if model.state == .downloaded(snapshot) { break }
                await Task.yield()
            }
            #expect(model.state == .downloaded(snapshot))
        }
        continuation.finish(throwing: HistoryReader.Failure.unavailable)
        await task.value
        #expect(model.state == .unavailable)
    }

    @Test("Downloaded history remains explicitly partial and clear removes it")
    func downloaded() async throws {
        let snapshot = try history()
        let model = DownloadedItemHistoryModel()
        let reader = HistoryReader(values: [snapshot], finishes: false)
        let task = Task { await model.load(accountId: account, itemId: item, reader: reader) }
        for _ in 0..<1000 {
            if model.state == .downloaded(snapshot) { break }
            await Task.yield()
        }
        #expect(model.state == .downloaded(snapshot))
        #expect(snapshot.isPartial)
        model.clear()
        task.cancel()
        await task.value
        #expect(model.state == .idle)
    }

    @Test("Normal watch termination discards previously downloaded Item details")
    func endedWatch() async throws {
        let snapshot = try DownloadedItemPlacementHistory(accountId: account, itemId: item,
            description: "Chair", intervals: [],
            details: .init(description: "Chair", notes: "Protected notes"))
        let model = DownloadedItemHistoryModel()
        await model.load(accountId: account, itemId: item, reader: HistoryReader(values: [snapshot]))
        #expect(model.state == .unavailable)
    }

    @Test("Foreign Account or Item update clears previously shown history", arguments: [false, true])
    func wrongScope(foreignAccount: Bool) async throws {
        let invalid = try DownloadedItemPlacementHistory(
            accountId: foreignAccount ? AccountID(validating: "foreign") : account,
            itemId: foreignAccount ? item : ItemID(validating: "foreign"), description: "Hidden", intervals: [])
        let model = DownloadedItemHistoryModel()
        await model.load(accountId: account, itemId: item, reader: HistoryReader(values: [try history(), invalid]))
        #expect(model.state == .unavailable)
    }

    @Test("Failure and empty streams do not retain data or spin forever", arguments: [false, true])
    func unavailable(fails: Bool) async throws {
        let model = DownloadedItemHistoryModel()
        await model.load(accountId: account, itemId: item,
                         reader: HistoryReader(values: fails ? [try history()] : [], fails: fails))
        #expect(model.state == .unavailable)
    }

    @Test("Closing history suppresses delayed results from the old request")
    func clearDelayed() async throws {
        let model = DownloadedItemHistoryModel()
        let reader = DelayedHistoryReader()
        let task = Task { await model.load(accountId: account, itemId: item, reader: reader) }
        await reader.waitUntilStarted()
        model.clear()
        await reader.finish(try history())
        await task.value
        #expect(model.state == .idle)
    }

    private func history() throws -> DownloadedItemPlacementHistory {
        try DownloadedItemPlacementHistory(accountId: account, itemId: item, description: "Chair", intervals: [])
    }
}

private struct HistoryReader: DownloadedItemPlacementHistoryReading {
    let values: [DownloadedItemPlacementHistory]
    var fails = false
    var finishes = true
    var stream: AsyncThrowingStream<DownloadedItemPlacementHistory, Error>?
    enum Failure: Error { case unavailable }
    func readDownloadedItemPlacementHistory(accountId: AccountID, itemId: ItemID) async throws -> DownloadedItemPlacementHistory {
        guard let first = values.first else { throw Failure.unavailable }
        return first
    }
    func watchDownloadedItemPlacementHistory(accountId: AccountID, itemId: ItemID) -> AsyncThrowingStream<DownloadedItemPlacementHistory, Error> {
        if let stream { return stream }
        return AsyncThrowingStream { continuation in
            for value in values { continuation.yield(value) }
            if fails { continuation.finish(throwing: Failure.unavailable) }
            else if finishes { continuation.finish() }
        }
    }
}

private actor DelayedHistoryReader: DownloadedItemPlacementHistoryReading {
    private var pending: CheckedContinuation<DownloadedItemPlacementHistory, Never>?
    private var started: [CheckedContinuation<Void, Never>] = []
    func readDownloadedItemPlacementHistory(accountId: AccountID, itemId: ItemID) async -> DownloadedItemPlacementHistory {
        await withCheckedContinuation { continuation in
            pending = continuation
            started.forEach { $0.resume() }
            started.removeAll()
        }
    }
    nonisolated func watchDownloadedItemPlacementHistory(accountId: AccountID, itemId: ItemID) -> AsyncThrowingStream<DownloadedItemPlacementHistory, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(await self.readDownloadedItemPlacementHistory(accountId: accountId, itemId: itemId))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    func waitUntilStarted() async {
        if pending != nil { return }
        await withCheckedContinuation { started.append($0) }
    }
    func finish(_ value: DownloadedItemPlacementHistory) {
        pending?.resume(returning: value)
        pending = nil
    }
}
