import Foundation
import LedgerTargetCore
import PowerSync
import Testing
@testable import LedgerTargetPowerSync

@Suite("Owned reactive physical Item watch", .serialized)
struct DownloadedItemPlacementWatchTests {
    @Test("Real offline SDK subscription binds Account and membership removal terminates rows")
    func realSubscriptionAndRemoval() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("physical-sdk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try LedgerPowerSyncDatabaseFactory.open(absolutePath: root.appendingPathComponent("ledger.sqlite").path,
            encryptionKey: LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "4a", count: 32)))
        let account = try AccountID(validating: "sdk-account")
        let principal = try PrincipalID(validating: "sdk-principal")
        _ = try await db.execute(sql: "INSERT INTO spike_account_memberships(id,account_id,principal_id,state) VALUES('member','sdk-account','sdk-principal','active')", parameters: nil)
        let values = AsyncStream<DownloadedItemPlacements>.makeStream()
        let task = Task {
            defer { values.continuation.finish() }
            try await DownloadedItemPlacementWatch(database: db).run(
                accountId: account, principalId: principal, scope: .businessInventory
            ) { value in
                values.continuation.yield(value)
                return true
            }
        }
        let deadline = Task { try await Task.sleep(for: .seconds(10)); task.cancel() }
        defer { deadline.cancel(); task.cancel() }
        var iterator = values.stream.makeAsyncIterator()
        let first = try #require(await iterator.next())
        #expect(first.accountId == account)
        #expect(first.rows.isEmpty)
        // Query the SDK's actual retained registration; no server connection,
        // injected subscription, or manually inserted subscription row.
        var parameters: [String] = []
        for _ in 0..<500 {
            parameters = try await db.getAll(sql: "SELECT local_params FROM ps_stream_subscriptions WHERE stream_name='physical_account_items'", parameters: nil) {
                try $0.getString(index: 0)
            }
            if !parameters.isEmpty { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(parameters.count == 1)
        if let json = parameters.first {
            #expect(try JSONDecoder().decode([String: String].self, from: Data(json.utf8)) == ["account_id": account.rawValue])
        }
        // No Item rows change: an empty active Space must still refresh choices.
        _ = try await db.execute(sql: "INSERT INTO spike_spaces(id,account_id,scope_kind,display_name,lifecycle) VALUES('empty-space','sdk-account','business_inventory','Empty warehouse','active')", parameters: nil)
        var spaces = try #require(await iterator.next())
        while spaces.spaces.first?.displayName != "Empty warehouse" {
            spaces = try #require(await iterator.next())
        }
        #expect(spaces.rows.isEmpty)
        _ = try await db.execute(sql: "UPDATE spike_spaces SET display_name='Renamed warehouse' WHERE id='empty-space'", parameters: nil)
        while spaces.spaces.first?.displayName != "Renamed warehouse" {
            spaces = try #require(await iterator.next())
        }
        _ = try await db.execute(sql: "UPDATE spike_spaces SET lifecycle='archived' WHERE id='empty-space'", parameters: nil)
        while !spaces.spaces.isEmpty { spaces = try #require(await iterator.next()) }
        _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed' WHERE id='member'", parameters: nil)
        await #expect(throws: CurrentItemPlacementReadFailure.accountUnavailable) { try await task.value }
        try await db.close()
    }

    @Test("Offline rows update before subscription finishes; cancellation drains delayed subscription cleanup")
    func offlineUpdatesAndCleanup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("physical-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try LedgerPowerSyncDatabaseFactory.open(absolutePath: root.appendingPathComponent("ledger.sqlite").path,
            encryptionKey: LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "4a", count: 32)))
        let account = try AccountID(validating: "watch-account")
        let principal = try PrincipalID(validating: "watch-principal")
        for sql in [
            "INSERT INTO spike_account_memberships(id,account_id,principal_id,state) VALUES('member','watch-account','watch-principal','active')",
            "INSERT INTO spike_items(id,account_id,description,revision) VALUES('chair','watch-account','Before',1)",
            "INSERT INTO spike_item_placements(id,account_id,item_id,scope_kind,started_at) VALUES('placement','watch-account','chair','business_inventory','2026-09-01')"
        ] { _ = try await db.execute(sql: sql, parameters: nil) }
        let subscriptionGate = PhysicalWatchGate()
        let cleanupGate = PhysicalWatchGate()
        let subscription = PhysicalWatchSubscription(cleanup: cleanupGate)
        let completed = PhysicalWatchCompletion()
        let values = AsyncStream<DownloadedItemPlacements>.makeStream()
        let watch = DownloadedItemPlacementWatch(database: db, subscribe: { requested in
            #expect(requested == account)
            await subscriptionGate.wait()
            return subscription
        })
        let task = Task {
            do {
                try await watch.run(accountId: account, principalId: principal, scope: .businessInventory) {
                    values.continuation.yield($0)
                    return true
                }
            } catch is CancellationError { }
            catch { Issue.record(error) }
            await completed.mark()
        }
        await subscriptionGate.waitUntilEntered()
        var iterator = values.stream.makeAsyncIterator()
        let first = try #require(await iterator.next())
        #expect(first.rows.first?.description == "Before")
        _ = try await db.execute(sql: "UPDATE spike_items SET description='After',revision=2 WHERE id='chair'", parameters: nil)
        var updated = first
        while updated.rows.first?.description != "After" {
            updated = try #require(await iterator.next())
        }
        #expect(updated.rows.first?.itemRevision == 2)
        // Cancel while subscribe is still suspended. A late subscription must
        // still be released, not escape the runtime's drain bookkeeping.
        task.cancel()
        await subscriptionGate.release()
        await cleanupGate.waitUntilEntered()
        #expect(await completed.value == false)
        await cleanupGate.release()
        await task.value
        #expect(await completed.value)
        #expect(await subscription.unsubscribeCount == 1)
        values.continuation.finish()
        try await db.close()
    }
}

private actor PhysicalWatchCompletion {
    private(set) var value = false
    func mark() { value = true }
}

private actor PhysicalWatchSubscription: SyncStreamSubscription {
    nonisolated let name = "physical_account_items"
    nonisolated let parameters: JsonParam? = ["account_id": .string("watch-account")]
    private let cleanup: PhysicalWatchGate
    private(set) var unsubscribeCount = 0
    init(cleanup: PhysicalWatchGate) { self.cleanup = cleanup }
    func waitForFirstSync() async throws { Issue.record("Offline read must never wait for first sync") }
    func unsubscribe() async throws {
        unsubscribeCount += 1
        await cleanup.wait()
    }
}

private actor PhysicalWatchGate {
    private var entered = false
    private var released = false
    private var entries: [CheckedContinuation<Void, Never>] = []
    private var releases: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        entered = true
        let pending = entries; entries.removeAll()
        for waiter in pending { waiter.resume() }
        if !released { await withCheckedContinuation { releases.append($0) } }
    }
    func waitUntilEntered() async {
        if !entered { await withCheckedContinuation { entries.append($0) } }
    }
    func release() {
        released = true
        let pending = releases; releases.removeAll()
        for waiter in pending { waiter.resume() }
    }
}
