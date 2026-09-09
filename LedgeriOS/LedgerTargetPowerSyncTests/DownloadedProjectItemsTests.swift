import Foundation
import LedgerTargetCore
import PowerSync
import Testing
@testable import LedgerTargetPowerSync

@Suite("Atomic downloaded Project Items", .serialized)
struct DownloadedProjectItemsTests {
    private let account = try! AccountID(validating: "account")
    private let principal = try! PrincipalID(validating: "principal")
    private let project = try! ProjectID(validating: "project")

    @Test("Browsing reads canonical names, SKU and optional creation evidence")
    func browsingFields() async throws {
        try await withDatabase { db in
            _ = try await db.execute(sql: "UPDATE spike_items SET name='Named chair',sku='SKU-7',workflow_status='to_return',bookmark=1,created_at='2026-09-09T07:00:00.123456Z' WHERE id='paid'", parameters: nil)
            let value = try await read(db)
            let row = try #require(value.placements.rows.first { $0.itemId.rawValue == "paid" })
            #expect(row.name == "Named chair")
            #expect(row.description == "paid")
            #expect(row.sku == "SKU-7")
            #expect(row.workflowStatusRaw == "to_return" && row.isBookmarked == true)
            #expect(value.accounting?.rows.first { $0.evidence.itemId == row.itemId }?.resolution == .accountedFor)
            #expect(row.createdAt != nil)
            #expect(value.placements.rows.first { $0.itemId.rawValue == "unknown" }?.createdAt == nil)
            for timestamp in ["2026-09-08T05:53:09.335662+00:00", "2026-09-09T07:00:00Z"] {
                _ = try await db.execute(sql: "UPDATE spike_items SET created_at=? WHERE id='paid'", parameters: [timestamp])
                #expect(try await read(db).placements.rows.first { $0.itemId.rawValue == "paid" }?.createdAt != nil)
            }
            _ = try await db.execute(sql: "UPDATE spike_item_placements SET started_at='2026-09-08T05:00:00Z' WHERE item_id='paid'", parameters: nil)
            let history = try await CurrentItemPlacementLocalReader(database: db)
                .readHistory(accountId: account, principalId: principal, itemId: ItemID(validating: "paid"))
            #expect(history.description == "Named chair")
            _ = try await db.execute(sql: "UPDATE spike_items SET created_at='invalid' WHERE id='paid'", parameters: nil)
            #expect(try await read(db).placements.rows.first { $0.itemId.rawValue == "paid" }?.createdAt == nil)
        }
    }

    @Test("All physical Items remain visible alongside paid, charge and unknown evidence")
    func allPhysicalRows() async throws {
        try await withDatabase { db in
            let value = try await read(db)
            #expect(value.placements.rows.count == 3)
            let accounting = try #require(value.accounting)
            #expect(accounting.rows.count == 3)
            #expect(accounting.rows.filter { $0.evidence.clientPaidPurchases.count == 1 }.count == 1)
            #expect(accounting.rows.filter { $0.evidence.billableOccurrences.count == 1 }.count == 1)
            #expect(accounting.unresolvedRows.map(\.evidence.itemId.rawValue) == ["unknown"])
            #expect(!accounting.isCompleteForAccounting)
            #expect(accounting.rows.allSatisfy { !$0.relationshipAbsenceIsAuthoritative })
        }
    }

    @Test("Limited access retains physical data but hides retained financial relationships")
    func downgradeAndRemoval() async throws {
        try await withDatabase { db in
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET financial_access='limited'", parameters: nil)
            let value = try await read(db)
            #expect(value.placements.rows.count == 3)
            #expect(value.accounting?.unresolvedRows.count == 3)
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed'", parameters: nil)
            await #expect(throws: CurrentItemPlacementReadFailure.accountUnavailable) { try await read(db) }
        }
    }

    @Test("Incomplete scoped download clears accounting without hiding physical rows")
    func incompleteCheckpoint() async throws {
        try await withDatabase { db in
            _ = try await db.execute(sql: "UPDATE ps_stream_subscriptions SET last_synced_at=NULL", parameters: nil)
            let value = try await read(db)
            #expect(value.placements.rows.count == 3)
            #expect(value.accounting == nil)
        }
    }

    @Test("A new placement cannot inherit an old visit's paid status")
    func visitIdentity() async throws {
        try await withDatabase { db in
            _ = try await db.execute(sql: "UPDATE spike_item_placements SET ended_at='2026-09-09' WHERE id='paid-placement'", parameters: nil)
            _ = try await db.execute(sql: "INSERT INTO spike_item_placements(id,account_id,item_id,scope_kind,project_id) VALUES('new-visit','account','paid','project','project')", parameters: nil)
            let value = try await read(db)
            #expect(value.placements.rows.first { $0.itemId.rawValue == "paid" }?.placementId.rawValue == "new-visit")
            #expect(value.accounting?.unresolvedRows.contains { $0.evidence.itemId.rawValue == "paid" } == true)
            await #expect(throws: CurrentItemPlacementReadFailure.accountUnavailable) {
                try await DownloadedProjectItemsWatch(database: db).read(accountId: AccountID(validating: "other"),
                    principalId: principal, projectId: project)
            }
        }
    }

    private func read(_ db: any PowerSyncDatabaseProtocol) async throws -> DownloadedProjectItems {
        try await DownloadedProjectItemsWatch(database: db).read(accountId: account,
            principalId: principal, projectId: project)
    }

    private func withDatabase(_ body: (any PowerSyncDatabaseProtocol) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("project-items-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try LedgerPowerSyncDatabaseFactory.open(absolutePath: root.appendingPathComponent("ledger.sqlite").path,
            encryptionKey: LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "5a", count: 32)))
        do {
            for sql in [
                "INSERT INTO spike_account_memberships(id,account_id,principal_id,state,financial_access) VALUES('member','account','principal','active','full')",
                "INSERT INTO spike_projects(id,account_id,client_id,display_name,lifecycle,revision) VALUES('project','account','client','Project','active',1)",
                "INSERT INTO spike_clients(id,account_id,display_name,lifecycle,revision) VALUES('client','account','Client','active',1)",
                "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES('property_management_report',1,0,'{\"account_id\":\"account\",\"project_id\":\"project\"}',1000000)",
                "INSERT INTO item_client_payment_connections(id,account_id,project_id,client_id,item_id,placement_id,transaction_id,transaction_type,transaction_role) VALUES('payment','account','project','client','paid','paid-placement','purchase','purchase','standalone')",
                "INSERT INTO item_charge_occurrences(id,account_id,project_id,item_id,placement_id,category_id,amount_minor_units,currency,revision) VALUES('charge','account','project','charged','charged-placement','category','100','USD',1)"
            ] { _ = try await db.execute(sql: sql, parameters: nil) }
            for item in ["paid", "charged", "unknown"] {
                _ = try await db.execute(sql: "INSERT INTO spike_items(id,account_id,description,revision) VALUES(?,'account',?,1)", parameters: [item, item])
                _ = try await db.execute(sql: "INSERT INTO spike_item_placements(id,account_id,item_id,scope_kind,project_id) VALUES(?,'account',?,'project','project')", parameters: ["\(item)-placement", item])
            }
            try await body(db)
            try await db.close()
        } catch { try? await db.close(); throw error }
    }
}
