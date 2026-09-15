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

    @Test("Invoicing retains a charge after its physical placement ends and denies restricted access")
    func historicalInvoicingCharge() async throws {
        try await withDatabase { db in
            _ = try await db.execute(sql: "UPDATE spike_item_placements SET ended_at='2026-09-15' WHERE id='charged-placement'", parameters: nil)
            let rows = try await db.readTransaction { transaction in
                try ProjectInvoicingItemLocalReader.readCharges(transaction: transaction, accountId: account, principalId: principal, projectId: project)
            }
            #expect(rows.count == 1 && rows[0].id.rawValue == "charge" && rows[0].amount.minorUnits == 100)
            let current = try await db.readTransaction { transaction in
                try ItemClientPaymentConnectionLocalReader.read(transaction: transaction, accountId: account, principalId: principal, projectId: project)
            }
            #expect(current[try EntityID(validating: "charged-placement")] == nil)
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET financial_access='none'", parameters: nil)
            await #expect(throws: ProjectInvoicingItemLocalReader.Failure.unavailable) {
                try await db.readTransaction { transaction in
                    try ProjectInvoicingItemLocalReader.readCharges(transaction: transaction, accountId: account, principalId: principal, projectId: project)
                }
            }
        }
    }

    @Test("Invoicing uses frozen paid contents after a move and rejects inconsistent evidence")
    func frozenInvoicingCharge() async throws {
        try await withDatabase { db in
            for sql in [
                "UPDATE spike_item_placements SET ended_at='2026-09-15' WHERE id='charged-placement'",
                "UPDATE spike_items SET name='Renamed after payment' WHERE id='charged'",
                "INSERT INTO spike_budget_categories(id,account_id,display_name) VALUES('category','account','Renamed category')",
                "INSERT INTO collected_invoices(id,account_id,project_id,client_id,sealed) VALUES('invoice','account','project','client',1)",
                "INSERT INTO collected_invoice_lines(id,account_id,invoice_id,source_kind,source_id,item_id,category_id,source_revision,signed_amount_minor_units,currency,description) VALUES('line','account','invoice','item','charge','charged','category',1,'100','USD','Original client description')"
            ] { _ = try await db.execute(sql: sql, parameters: nil) }
            let rows = try await db.readTransaction { transaction in
                try ProjectInvoicingItemLocalReader.readCharges(transaction: transaction, accountId: account, principalId: principal, projectId: project)
            }
            let row = try #require(rows.first)
            #expect(rows.count == 1 && row.availability == .paid && row.amount.minorUnits == 100)
            #expect(row.title == "Original client description" && row.categoryName == nil)
            #expect(row.occurrence.phase.invoiceId?.rawValue == "invoice")
            _ = try await db.execute(sql: "UPDATE collected_invoice_lines SET signed_amount_minor_units='101' WHERE id='line'", parameters: nil)
            await #expect(throws: PropertyManagementReportLocalReadFailure.malformedEvidence) {
                try await db.readTransaction { transaction in
                    try ProjectInvoicingItemLocalReader.readCharges(transaction: transaction, accountId: account, principalId: principal, projectId: project)
                }
            }
        }
    }

    @Test("Invoicing readiness requires its exact historical and physical downloads")
    func invoicingCheckpointScope() async throws {
        try await withDatabase { db in
            let query = ProjectInvoicingChargePowerSyncQuery(database: db)
            await #expect(throws: PropertyManagementReportFailure.incompleteReadiness) {
                try await query.read(accountId: account, principalId: principal, projectId: project)
            }
            _ = try await db.execute(sql: "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES('project_invoicing_item_charges',1,0,'{\"account_id\":\"account\",\"project_id\":\"other\"}',1000000)", parameters: nil)
            await #expect(throws: PropertyManagementReportFailure.incompleteReadiness) {
                try await query.read(accountId: account, principalId: principal, projectId: project)
            }
            _ = try await db.execute(sql: "UPDATE ps_stream_subscriptions SET local_params='{\"account_id\":\"account\",\"project_id\":\"project\"}' WHERE stream_name='project_invoicing_item_charges'", parameters: nil)
            await #expect(throws: PropertyManagementReportFailure.incompleteReadiness) {
                try await query.read(accountId: account, principalId: principal, projectId: project)
            }
            _ = try await db.execute(sql: "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES('physical_account_items',1,0,'{\"account_id\":\"account\"}',1000000)", parameters: nil)
            #expect(try await query.read(accountId: account, principalId: principal, projectId: project).rows.count == 1)
            _ = try await db.execute(sql: "UPDATE ps_stream_subscriptions SET active=0 WHERE stream_name='project_invoicing_item_charges'", parameters: nil)
            await #expect(throws: PropertyManagementReportFailure.incompleteReadiness) {
                try await query.read(accountId: account, principalId: principal, projectId: project)
            }
        }
    }

    @Test("Invoicing watch emits incomplete offline and terminates on access removal", .timeLimit(.minutes(1)))
    func invoicingWatchRemoval() async throws {
        try await withDatabase { db in
            let values = AsyncStream<Bool>.makeStream()
            let task = Task {
                defer { values.continuation.finish() }
                try await ProjectInvoicingChargePowerSyncQuery(database: db).run(accountId: account,
                    principalId: principal, projectId: project) { snapshot in
                        values.continuation.yield(snapshot == nil)
                        return true
                    }
            }
            var iterator = values.stream.makeAsyncIterator()
            #expect(await iterator.next() == true)
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed'", parameters: nil)
            await #expect(throws: ProjectInvoicingItemLocalReader.Failure.unavailable) { try await task.value }
            // withDatabase closes only after both owned subscription tasks drain.
        }
    }

    @Test("Combined Project snapshot reacts to marker-only changes and revocation")
    func imageMarkerWatch() async throws {
        try await withDatabase { db in
            let values = AsyncThrowingStream<DownloadedProjectItems,Error>.makeStream()
            let task = Task {
                do {
                    try await DownloadedProjectItemsWatch(database: db).run(accountId: account,principalId: principal,projectId: project) {
                        values.continuation.yield($0)
                        return true
                    }
                    values.continuation.finish()
                } catch { values.continuation.finish(throwing: error) }
            }
            let deadline = Task { try await Task.sleep(for: .seconds(10));task.cancel() }
            defer { task.cancel();deadline.cancel() }
            var iterator = values.stream.makeAsyncIterator()
            let initial = try await nextMatching(&iterator) { _ in true }
            #expect(initial.placements.rows.allSatisfy { $0.imageCount == nil })
            _ = try await db.execute(sql: "INSERT INTO item_image_sets(id,account_id,item_id,revision,expected_count) VALUES('paid','account','paid','1',0)",parameters: nil)
            let empty = try await nextMatching(&iterator) {
                $0.placements.rows.first(where: { $0.itemId.rawValue == "paid" })?.imageCount == 0
            }
            #expect(empty.accounting?.rows.count == empty.placements.rows.count)
            _ = try await db.execute(sql: "UPDATE item_image_sets SET revision='2',expected_count=2",parameters: nil)
            _ = try await nextMatching(&iterator) {
                $0.placements.rows.first(where: { $0.itemId.rawValue == "paid" })?.imageCount == 2
            }
            _ = try await db.execute(sql: "DELETE FROM item_image_sets",parameters: nil)
            _ = try await nextMatching(&iterator) { $0.placements.rows.allSatisfy { $0.imageCount == nil } }
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed'",parameters: nil)
            await #expect(throws: CurrentItemPlacementReadFailure.accountUnavailable) {
                while try await iterator.next() != nil {}
            }
            await task.value
        }
    }

    private func nextMatching(
        _ iterator: inout AsyncThrowingStream<DownloadedProjectItems,Error>.Iterator,
        predicate: (DownloadedProjectItems) -> Bool
    ) async throws -> DownloadedProjectItems {
        while let snapshot = try await iterator.next() {
            if predicate(snapshot) { return snapshot }
        }
        throw MarkerTestFailure.streamEnded
    }

    private enum MarkerTestFailure: Error { case streamEnded }

    @Test("Browsing reads canonical names, SKU and optional creation evidence")
    func browsingFields() async throws {
        try await withDatabase { db in
            _ = try await db.execute(sql: "UPDATE spike_items SET name='Named chair',sku='SKU-7',workflow_status='to_return',bookmark=1,source='Original vendor',current_source='Inventory',created_at='2026-09-09T07:00:00.123456Z' WHERE id='paid'", parameters: nil)
            let value = try await read(db)
            let row = try #require(value.placements.rows.first { $0.itemId.rawValue == "paid" })
            #expect(row.name == "Named chair")
            #expect(row.description == "paid")
            #expect(row.sku == "SKU-7")
            #expect(row.workflowStatusRaw == "to_return" && row.isBookmarked == true)
            #expect(row.source == "Original vendor" && row.currentSource == "Inventory")
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
