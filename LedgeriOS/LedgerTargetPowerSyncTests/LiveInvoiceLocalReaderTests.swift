import Foundation
import LedgerTargetCore
import PowerSync
import Testing
@testable import LedgerTargetPowerSync

@Suite("Live Invoice downloaded source facts", .serialized)
struct LiveInvoiceLocalReaderTests {
    private let account = try! AccountID(validating: "account")
    private let principal = try! PrincipalID(validating: "principal")
    private let project = try! ProjectID(validating: "project")

    @Test func currentExpenseUpdatesExactTotalAndMissingSourceNeverDisappears() async throws {
        try await withDatabase { db in
            let first = try #require(try await read(db).first)
            #expect(first.total.minorUnits == 9_007_199_254_740_993)
            _ = try await db.execute(sql: "UPDATE expenses SET final_amount_minor_units='100',vendor='Changed',revision='2'", parameters: nil)
            let changed = try #require(try await read(db).first)
            #expect(changed.total.minorUnits == 100)
            #expect(changed.lines.first?.description == "Changed")
            #expect(changed.lines.first?.selection.expectedRevision == 2)
            _ = try await db.execute(sql: "DELETE FROM expenses", parameters: nil)
            await #expect(throws: (any Error).self) { try await read(db) }
        }
    }
    @Test func financialWithdrawalAndIncompleteDownloadDenyRead() async throws {
        try await withDatabase { db in
            // Locally present rows are not proof the required streams completed.
            await #expect(throws: (any Error).self) {
                try await LiveInvoicePowerSyncQuery(database: db).read(accountId: account, principalId: principal, projectId: project)
            }
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET financial_access='none'", parameters: nil)
            await #expect(throws: (any Error).self) { try await read(db) }
        }
    }
    @Test func gapsAndCollectedSourcesDenyLiveRead() async throws {
        try await withDatabase { db in
            _ = try await db.execute(sql: "UPDATE live_invoice_memberships SET position=1", parameters: nil)
            await #expect(throws: (any Error).self) { try await read(db) }
            _ = try await db.execute(sql: "UPDATE live_invoice_memberships SET position=0", parameters: nil)
            _ = try await db.execute(sql: "INSERT INTO collected_invoice_lines(id,account_id,invoice_id,source_kind,source_id) VALUES('paid','account','frozen','expense','expense')", parameters: nil)
            await #expect(throws: (any Error).self) { try await read(db) }
        }
    }
    @Test func mixedSourcesKeepOrderAndRejectWithdrawnOccurrence() async throws {
        try await withDatabase { db in
            for sql in [
                "UPDATE expenses SET final_amount_minor_units='100'",
                "INSERT INTO spike_items(id,account_id,description) VALUES('chair','account','Chair')",
                "INSERT INTO item_charge_occurrences(id,account_id,project_id,item_id,category_id,amount_minor_units,currency,revision) VALUES('sale','account','project','chair','category','250','USD',3)",
                "INSERT INTO fee_installments(id,account_id,project_id,category_id,label,amount_minor_units,currency,revision) VALUES('fee','account','project','category','Design fee','50','USD','4')",
                "INSERT INTO live_invoice_memberships(id,account_id,invoice_id,source_kind,source_id,position) VALUES('item-line','account','invoice','item','sale',1)",
                "INSERT INTO live_invoice_memberships(id,account_id,invoice_id,source_kind,source_id,position) VALUES('fee-line','account','invoice','fee_installment','fee',2)"
            ] { _ = try await db.execute(sql: sql, parameters: nil) }
            let result = try #require(try await read(db).first)
            #expect(result.total.minorUnits == 400)
            #expect(result.lines.map(\.description) == ["Vendor", "Chair", "Design fee"])
            #expect(result.lines[1].selection.source == .itemOccurrence(try .init(validating: "sale")))
            _ = try await db.execute(sql: "UPDATE item_charge_occurrences SET withdrawn_at='2026-09-15'", parameters: nil)
            await #expect(throws: (any Error).self) { try await read(db) }
        }
    }
    private func read(_ db: any PowerSyncDatabaseProtocol) async throws -> [LiveInvoiceContents] {
        try await db.readTransaction { local in
            try ProjectInvoicingItemLocalReader.requireAccess(transaction: local, accountId: account, principalId: principal, projectId: project)
            return try LiveInvoicePowerSyncQuery.readAuthorized(transaction: local, accountId: account, projectId: project)
        }
    }
    @Test func incompleteWatchEmitsUnavailableAndFinishesWithoutClosingSharedDatabase() async throws {
        try await withDatabase { db in
            let emitted = AsyncStream<Bool>.makeStream()
            try await LiveInvoicePowerSyncQuery(database: db).run(accountId: account, principalId: principal, projectId: project) { value in
                emitted.continuation.yield(value == nil)
                return false
            }
            emitted.continuation.finish()
            var iterator = emitted.stream.makeAsyncIterator()
            #expect(await iterator.next() == true)
            #expect(try await read(db).count == 1)
        }
    }
    private func withDatabase(_ body: (any PowerSyncDatabaseProtocol) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("live-invoice-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try LedgerPowerSyncDatabaseFactory.open(absolutePath: root.appendingPathComponent("ledger.sqlite").path,
            encryptionKey: .init(hexadecimal: String(repeating: "4a", count: 32)))
        do {
            for sql in [
                "INSERT INTO spike_account_memberships(id,account_id,principal_id,state,financial_access) VALUES('member','account','principal','active','full')",
                "INSERT INTO spike_projects(id,account_id,client_id) VALUES('project','account','client')",
                "INSERT INTO live_invoices(id,account_id,project_id,name,notes,status,revision) VALUES('invoice','account','project','Invoice','','created','1')",
                "INSERT INTO live_invoice_memberships(id,account_id,invoice_id,source_kind,source_id,position) VALUES('line','account','invoice','expense','expense',0)",
                "INSERT INTO expenses(id,account_id,project_id,category_id,vendor,final_amount_minor_units,currency,revision) VALUES('expense','account','project','category','Vendor','9007199254740993','USD','1')"
            ] { _ = try await db.execute(sql: sql, parameters: nil) }
            try await body(db)
            try await db.close()
        } catch { try? await db.close(); throw error }
    }
}
