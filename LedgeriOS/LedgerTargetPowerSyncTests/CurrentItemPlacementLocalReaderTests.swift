import Foundation
import LedgerTargetCore
import PowerSync
import Testing
@testable import LedgerTargetPowerSync

@Suite("Downloaded physical Item placements", .serialized)
struct CurrentItemPlacementLocalReaderTests {
    private let account = try! AccountID(validating: "account-item")
    private let principal = try! PrincipalID(validating: "principal-item")
    private let project = try! ProjectID(validating: "project-item")

    @Test("Physical detail retains ordered raw intervals with missing historical labels")
    func placementHistory() async throws {
        try await withDatabase { db in
            let reader = CurrentItemPlacementLocalReader(database: db)
            _ = try await db.execute(sql: "UPDATE spike_projects SET display_name='Original project' WHERE id='project-item'", parameters: nil)
            let history = try await reader.readHistory(accountId: account, principalId: principal, itemId: ItemID(validating: "chair"))
            #expect(history.accountId == account && history.itemId.rawValue == "chair")
            #expect(history.description == "Chair" && history.isPartial)
            #expect(history.intervals.map(\.placementId.rawValue) == ["project-now", "inventory-before"])
            #expect(history.intervals.map(\.startedAt) == ["2026-02-01", "2026-01-01"])
            #expect(history.intervals[0].endedAt == nil)
            #expect(history.intervals[1].endedAt == "2026-02-01")
            #expect(history.intervals[0].projectDisplayName == "Original project")
            _ = try await db.execute(sql: "DELETE FROM spike_projects WHERE id='project-item'", parameters: nil)
            _ = try await db.execute(sql: "DELETE FROM spike_spaces WHERE id='room'", parameters: nil)
            let partial = try await reader.readHistory(accountId: account, principalId: principal, itemId: ItemID(validating: "chair"))
            #expect(partial.intervals[0].scope == .project(project))
            #expect(partial.intervals[0].spaceId?.rawValue == "room")
            #expect(partial.intervals[0].projectDisplayName == nil && partial.intervals[0].spaceDisplayName == nil)
            _ = try await db.execute(sql: "DELETE FROM spike_item_placements", parameters: nil)
            let empty = try await reader.readHistory(accountId: account, principalId: principal, itemId: ItemID(validating: "chair"))
            #expect(empty.isPartial && empty.intervals.isEmpty)
        }
    }

    @Test("Physical history rejects malformed intervals and contradictory downloaded evidence")
    func invalidHistory() async throws {
        for mutation in [
            "UPDATE spike_item_placements SET started_at='invalid' WHERE id='project-now'",
            "UPDATE spike_item_placements SET started_at='2026-02-01T00:00:00.١Z' WHERE id='project-now'",
            "UPDATE spike_item_placements SET started_at='2026-02-30T00:00:00Z' WHERE id='project-now'",
            "UPDATE spike_item_placements SET started_at='2026-02-01T00:00:00+2400' WHERE id='project-now'",
            "UPDATE spike_item_placements SET started_at='2026-02-01T00:00:00+00:60' WHERE id='project-now'",
            "UPDATE spike_item_placements SET ended_at='invalid' WHERE id='inventory-before'",
            "UPDATE spike_item_placements SET ended_at='2025-01-01' WHERE id='inventory-before'",
            "UPDATE spike_item_placements SET ended_at='2026-03-01' WHERE id='inventory-before'",
            "UPDATE spike_item_placements SET ended_at=NULL WHERE id='inventory-before'",
            "UPDATE spike_item_placements SET scope_kind='unknown' WHERE id='inventory-before'",
            "UPDATE spike_item_placements SET project_id=NULL WHERE id='project-now'",
            "UPDATE spike_spaces SET project_id='different' WHERE id='room'",
            "DELETE FROM spike_items WHERE id='chair'"
        ] {
            try await withDatabase { db in
                _ = try await db.execute(sql: mutation, parameters: nil)
                await #expect(throws: CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement) {
                    try await CurrentItemPlacementLocalReader(database: db).readHistory(accountId: account,
                        principalId: principal, itemId: ItemID(validating: "chair"))
                }
            }
        }
    }

    @Test("History never resolves labels or placements from another Account and requires active membership")
    func historyAuthorization() async throws {
        try await withDatabase { db in
            let reader = CurrentItemPlacementLocalReader(database: db)
            _ = try await db.execute(sql: "UPDATE spike_projects SET account_id='account-other',display_name='Secret project' WHERE id='project-item'", parameters: nil)
            _ = try await db.execute(sql: "UPDATE spike_spaces SET account_id='account-other',display_name='Secret room' WHERE id='room'", parameters: nil)
            _ = try await db.execute(sql: "INSERT INTO spike_item_placements(id,account_id,item_id,scope_kind,started_at) VALUES('foreign','account-other','chair','business_inventory','2026-03-01')", parameters: nil)
            let history = try await reader.readHistory(accountId: account, principalId: principal, itemId: ItemID(validating: "chair"))
            #expect(history.intervals.count == 2)
            #expect(history.intervals[0].projectDisplayName == nil && history.intervals[0].spaceDisplayName == nil)
            await #expect(throws: CurrentItemPlacementReadFailure.accountUnavailable) {
                try await reader.readHistory(accountId: AccountID(validating: "account-other"), principalId: principal, itemId: ItemID(validating: "chair"))
            }
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed'", parameters: nil)
            await #expect(throws: CurrentItemPlacementReadFailure.accountUnavailable) {
                try await reader.readHistory(accountId: account, principalId: principal, itemId: ItemID(validating: "chair"))
            }
        }
    }

    @Test("Physical history compares submillisecond boundaries without rounding or reordering")
    func preciseHistoryIntervals() async throws {
        try await withDatabase { db in
            _ = try await db.execute(sql: "UPDATE spike_item_placements SET started_at='2026-02-01T00:00:00.000001Z',ended_at='2026-02-01T00:00:00.000002Z' WHERE id='inventory-before'", parameters: nil)
            _ = try await db.execute(sql: "UPDATE spike_item_placements SET started_at='2026-01-31T16:00:00.000002-08:00' WHERE id='project-now'", parameters: nil)
            let reader = CurrentItemPlacementLocalReader(database: db)
            let history = try await reader.readHistory(accountId: account, principalId: principal, itemId: ItemID(validating: "chair"))
            #expect(history.intervals.map(\.placementId.rawValue) == ["project-now", "inventory-before"])
            #expect(history.intervals[0].startedAt == "2026-01-31T16:00:00.000002-08:00")
            _ = try await db.execute(sql: "UPDATE spike_item_placements SET ended_at='2026-02-01T00:00:00.000003Z' WHERE id='inventory-before'", parameters: nil)
            await #expect(throws: CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement) {
                try await reader.readHistory(accountId: account, principalId: principal, itemId: ItemID(validating: "chair"))
            }
        }
    }

    @Test("Physical history watch stops on membership removal without opening a subscription")
    func historyWatchRevocation() async throws {
        try await withDatabase { db in
            let reader = CurrentItemPlacementLocalReader(database: db)
            var iterator = try reader.watchHistory(accountId: account, principalId: principal,
                itemId: ItemID(validating: "chair")).makeAsyncIterator()
            let rows = try #require(try await iterator.next())
            #expect(try CurrentItemPlacementLocalReader.history(accountId: account,
                itemId: ItemID(validating: "chair"), rows: rows).intervals.count == 2)
            let subscriptions = try await db.getAll(sql: "SELECT stream_name FROM ps_stream_subscriptions", parameters: nil) {
                try $0.getString(index: 0)
            }
            #expect(subscriptions.isEmpty)
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed'", parameters: nil)
            await #expect(throws: CurrentItemPlacementReadFailure.accountUnavailable) {
                while try await iterator.next() != nil { }
            }
        }
    }

    @Test("Physical placement history survives encrypted database close and reopen")
    func historyEncryptedReopen() async throws {
        try await withDatabase(reopen: { db in
            let history = try await CurrentItemPlacementLocalReader(database: db).readHistory(
                accountId: account, principalId: principal, itemId: ItemID(validating: "chair"))
            #expect(history.description == "Chair" && history.isPartial)
            #expect(history.intervals.map(\.placementId.rawValue) == ["project-now", "inventory-before"])
            #expect(history.intervals[1].endedAt == "2026-02-01")
        }) { _ in }
    }

    @Test("Report storage preserves distinct text, unknown valuation and exact signed cents")
    func reportFields() async throws {
        try await withDatabase { db in
            let unknown = try await db.getAll(sql: "SELECT market_value_minor_units FROM spike_items WHERE id='chair'", parameters: nil) {
                try $0.getIntOptional(name: "market_value_minor_units")
            }
            #expect(unknown.count == 1 && unknown[0] == nil)
            _ = try await db.execute(sql: "UPDATE spike_items SET name='Named chair',sku='SKU-1',market_value_currency='USD' WHERE id='chair'", parameters: nil)
            for amount: Int64 in [0, 9_007_199_254_740_993, Int64.min, Int64.max] {
                _ = try await db.execute(sql: "UPDATE spike_items SET market_value_minor_units=? WHERE id='chair'", parameters: [amount])
                let stored = try await db.getAll(sql: "SELECT name,description,sku,market_value_minor_units,market_value_currency FROM spike_items WHERE id='chair'", parameters: nil) {
                    (try $0.getString(name: "name"), try $0.getString(name: "description"),
                     try $0.getString(name: "sku"), try $0.getInt(name: "market_value_minor_units"),
                     try $0.getString(name: "market_value_currency"))
                }
                #expect(stored[0].0 == "Named chair" && stored[0].1 == "Chair")
                #expect(stored[0].2 == "SKU-1" && stored[0].3 == amount && stored[0].4 == "USD")
            }
            _ = try await db.execute(sql: "UPDATE spike_projects SET property_address='123 Main St' WHERE id='project-item'", parameters: nil)
            let addresses = try await db.getAll(sql: "SELECT property_address FROM spike_projects WHERE id='project-item'", parameters: nil) {
                try $0.getString(name: "property_address")
            }
            #expect(addresses == ["123 Main St"])
        }
    }

    @Test("Current physical rows retain history and do not become assignment preconditions")
    func currentRows() async throws {
        try await withDatabase { db in
            let reader = CurrentItemPlacementLocalReader(database: db)
            let rows = try await reader.read(accountId: account, principalId: principal, scope: .project(project))
            #expect(rows.count == 1)
            #expect(rows.first?.itemId.rawValue == "chair")
            #expect(rows.first?.placementId.rawValue == "project-now")
            #expect(rows.first?.itemRevision == 1)
            #expect(rows.first?.spaceId?.rawValue == "room")
            let inventory = try await reader.read(accountId: account, principalId: principal, scope: .businessInventory)
            #expect(inventory.isEmpty) // Locally empty, not a complete inventory claim.
            let history = try await db.getAll(sql: "SELECT id FROM spike_item_placements WHERE item_id='chair' ORDER BY id", parameters: nil) {
                try $0.getString(name: "id")
            }
            #expect(history == ["inventory-before", "project-now"])
            _ = try await db.execute(sql: "UPDATE spike_item_placements SET ended_at='2026-03-01' WHERE id='project-now'", parameters: nil)
            _ = try await db.execute(sql: "INSERT INTO spike_item_placements(id,account_id,item_id,scope_kind,started_at) VALUES('inventory-return','account-item','chair','business_inventory','2026-03-01')", parameters: nil)
            let returned = try await reader.read(accountId: account, principalId: principal, scope: .businessInventory)
            #expect(returned.first?.placementId.rawValue == "inventory-return")
            #expect(returned.first?.itemRevision == 1) // Demonstrates why no candidate conversion is safe yet.
        }
    }

    @Test("Partial or contradictory graphs fail, including a duplicate in another Project")
    func malformedGraph() async throws {
        for mutation in [
            "DELETE FROM spike_items WHERE id='chair'",
            "UPDATE spike_items SET account_id='account-other' WHERE id='chair'",
            "UPDATE spike_items SET revision=0 WHERE id='chair'",
            "DELETE FROM spike_spaces WHERE id='room'",
            "UPDATE spike_spaces SET project_id='project-other' WHERE id='room'",
            "UPDATE spike_spaces SET account_id='account-other' WHERE id='room'",
            "DELETE FROM spike_projects WHERE id='project-item'",
            "INSERT INTO spike_item_placements(id,account_id,item_id,scope_kind,project_id) VALUES('duplicate','account-item','chair','project','project-other')"
        ] {
            try await withDatabase { db in
                _ = try await db.execute(sql: mutation, parameters: nil)
                await #expect(throws: CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement) {
                    try await CurrentItemPlacementLocalReader(database: db).read(accountId: account, principalId: principal, scope: .project(project))
                }
            }
        }
    }

    @Test("Exact Account and Principal membership is required even with downloaded data")
    func membership() async throws {
        try await withDatabase { db in
            let reader = CurrentItemPlacementLocalReader(database: db)
            await #expect(throws: CurrentItemPlacementReadFailure.accountUnavailable) {
                try await reader.read(accountId: account, principalId: PrincipalID(validating: "principal-other"), scope: .project(project))
            }
            await #expect(throws: CurrentItemPlacementReadFailure.accountUnavailable) {
                try await reader.read(accountId: account, principalId: PrincipalID(validating: "principal-other"), scope: .businessInventory)
            }
            await #expect(throws: CurrentItemPlacementReadFailure.accountUnavailable) {
                try await reader.read(accountId: AccountID(validating: "account-other"), principalId: principal, scope: .project(project))
            }
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed' WHERE id='member'", parameters: nil)
            await #expect(throws: CurrentItemPlacementReadFailure.accountUnavailable) {
                try await reader.read(accountId: account, principalId: principal, scope: .project(project))
            }
        }
    }

    @Test("An archived Inventory parent remains readable after encrypted restart")
    func archivedInventoryParent() async throws {
        try await withDatabase(reopen: { db in
            let reader = CurrentItemPlacementLocalReader(database: db)
            let rows = try await reader.read(accountId: account, principalId: principal, scope: .businessInventory)
            #expect(rows.map(\.itemId.rawValue) == ["chair"])
            #expect(rows.first?.spaceId?.rawValue == "warehouse")
            _ = try await db.execute(sql: "UPDATE spike_spaces SET account_id='account-other' WHERE id='warehouse'", parameters: nil)
            await #expect(throws: CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement) {
                try await reader.read(accountId: account, principalId: principal, scope: .businessInventory)
            }
        }) { db in
            _ = try await db.execute(sql: "UPDATE spike_item_placements SET ended_at='2026-03-01' WHERE id='project-now'", parameters: nil)
            _ = try await db.execute(sql: "INSERT INTO spike_spaces(id,account_id,scope_kind,display_name,lifecycle) VALUES('warehouse','account-item','business_inventory','Archived warehouse','archived')", parameters: nil)
            _ = try await db.execute(sql: "INSERT INTO spike_item_placements(id,account_id,item_id,scope_kind,space_id,started_at) VALUES('returned','account-item','chair','business_inventory','warehouse','2026-03-01')", parameters: nil)
            let rows = try await CurrentItemPlacementLocalReader(database: db).read(accountId: account, principalId: principal, scope: .businessInventory)
            #expect(rows.first?.spaceId?.rawValue == "warehouse")
        }
    }

    @Test("Inventory Space requires exact Inventory scope, not merely the same Account")
    func inventorySpace() async throws {
        try await withDatabase { db in
            _ = try await db.execute(sql: "UPDATE spike_item_placements SET ended_at='2026-03-01' WHERE id='project-now'", parameters: nil)
            _ = try await db.execute(sql: "INSERT INTO spike_spaces(id,account_id,scope_kind) VALUES('warehouse','account-item','business_inventory')", parameters: nil)
            _ = try await db.execute(sql: "INSERT INTO spike_item_placements(id,account_id,item_id,scope_kind,space_id) VALUES('returned','account-item','chair','business_inventory','warehouse')", parameters: nil)
            let reader = CurrentItemPlacementLocalReader(database: db)
            let rows = try await reader.read(accountId: account, principalId: principal, scope: .businessInventory)
            #expect(rows.first?.spaceId?.rawValue == "warehouse")
            _ = try await db.execute(sql: "UPDATE spike_item_placements SET space_id='room' WHERE id='returned'", parameters: nil)
            await #expect(throws: CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement) {
                try await reader.read(accountId: account, principalId: principal, scope: .businessInventory)
            }
        }
    }

    private func withDatabase(reopen: ((any PowerSyncDatabaseProtocol) async throws -> Void)? = nil,
                              _ body: (any PowerSyncDatabaseProtocol) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("item-reader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try LedgerPowerSyncDatabaseFactory.open(absolutePath: root.appendingPathComponent("ledger.sqlite").path,
            encryptionKey: LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "4a", count: 32)))
        do {
            for sql in [
                "INSERT INTO spike_account_memberships(id,account_id,principal_id,state) VALUES('member','account-item','principal-item','active')",
                "INSERT INTO spike_projects(id,account_id) VALUES('project-item','account-item')",
                "INSERT INTO spike_spaces(id,account_id,scope_kind,project_id) VALUES('room','account-item','project','project-item')",
                "INSERT INTO spike_items(id,account_id,description,revision) VALUES('chair','account-item','Chair',1)",
                "INSERT INTO spike_item_placements(id,account_id,item_id,scope_kind,started_at,ended_at) VALUES('inventory-before','account-item','chair','business_inventory','2026-01-01','2026-02-01')",
                "INSERT INTO spike_item_placements(id,account_id,item_id,scope_kind,project_id,space_id,started_at) VALUES('project-now','account-item','chair','project','project-item','room','2026-02-01')"
            ] { _ = try await db.execute(sql: sql, parameters: nil) }
            try await body(db)
            try await db.close()
            if let reopen {
                let reopened = try LedgerPowerSyncDatabaseFactory.open(absolutePath: root.appendingPathComponent("ledger.sqlite").path,
                    encryptionKey: LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "4a", count: 32)))
                do { try await reopen(reopened); try await reopened.close() }
                catch { try? await reopened.close(); throw error }
            }
        } catch {
            try? await db.close()
            throw error
        }
    }
}
