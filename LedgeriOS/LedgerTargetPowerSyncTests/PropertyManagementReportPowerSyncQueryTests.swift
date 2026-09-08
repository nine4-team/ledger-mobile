import Foundation
import LedgerTargetCore
import PowerSync
import Testing
@testable import LedgerTargetPowerSync

@Suite("Property report scoped download readiness", .serialized)
struct PropertyManagementReportPowerSyncQueryTests {
    private let account = try! AccountID(validating: "report-account")
    private let principal = try! PrincipalID(validating: "report-principal")
    private let project = try! ProjectID(validating: "report-project")
    private let parameters = #"{"project_id":"report-project","account_id":"report-account"}"#

    @Test("Live report refreshes same-count edits, clears evicted data and terminates on removal")
    func liveWatch() async throws {
        try await withDatabase { db in
            let updates = AsyncThrowingStream<PropertyManagementReportUpdate, Error>.makeStream()
            let consumer = Task {
                do {
                    try await PropertyManagementReportWatch(database: db).run(accountId: account,
                        principalId: principal, projectId: project, currency: CurrencyCode(validating: "USD")) {
                            updates.continuation.yield($0)
                            return true
                        }
                    updates.continuation.finish()
                } catch { updates.continuation.finish(throwing: error) }
            }
            let deadline = Task {
                try await Task.sleep(for: .seconds(10))
                consumer.cancel()
                updates.continuation.finish()
            }
            do {
                var iterator = updates.stream.makeAsyncIterator()
                #expect(try await iterator.next() == .incomplete)
                // Wait for actual local SDK registration; never fabricate its
                // subscription row. Completion is synthetic in this watch test.
                for _ in 0..<1000 {
                    let registered = try await db.get(sql: "SELECT count(*) AS n FROM ps_stream_subscriptions WHERE stream_name='property_management_report'", parameters: nil) { try $0.getInt(name: "n") }
                    if registered == 1 { break }
                    try await Task.sleep(for: .milliseconds(1))
                }
                _ = try await db.execute(sql: "UPDATE ps_stream_subscriptions SET active=1,last_synced_at=1000000 WHERE stream_name='property_management_report'", parameters: nil)
                while true {
                    let value = try #require(try await iterator.next())
                    if case .ready(let snapshot) = value { #expect(snapshot.project.name == "Property"); break }
                }
                _ = try await db.execute(sql: "UPDATE spike_projects SET display_name='Changed property',revision=2 WHERE id='report-project'", parameters: nil)
                while true {
                    let value = try #require(try await iterator.next())
                    if case .ready(let snapshot) = value, snapshot.project.name == "Changed property" { break }
                }
                _ = try await db.execute(sql: "UPDATE ps_stream_subscriptions SET last_synced_at=NULL WHERE stream_name='property_management_report'", parameters: nil)
                while try #require(try await iterator.next()) != .incomplete { }
                _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed' WHERE id='report-member'", parameters: nil)
                await #expect(throws: PropertyManagementReportLocalReadFailure.accountUnavailable) {
                    while let _ = try await iterator.next() { }
                }
                consumer.cancel(); deadline.cancel()
                await consumer.value
            } catch {
                consumer.cancel(); deadline.cancel()
                await consumer.value
                throw error
            }
        }
    }

    @Test("Only the exact completed retained stream allows a report, even when rows exist")
    func readiness() async throws {
        try await withDatabase { db in
            for (json, active, epoch) in [
                (#"{"account_id":"report-account","project_id":"other-project"}"#, 1, "1000000"),
                (#"{"account_id":"other-account","project_id":"report-project"}"#, 1, "1000000"),
                (parameters, 1, "NULL"), (parameters, 0, "1000000"), (parameters, 1, "0")
            ] {
                _ = try await db.execute(sql: "DELETE FROM ps_stream_subscriptions WHERE stream_name='property_management_report'", parameters: nil)
                _ = try await db.execute(sql: "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES('property_management_report',?,0,?,\(epoch))", parameters: [active, json])
                await #expect(throws: PropertyManagementReportFailure.incompleteReadiness) { try await read(db) }
            }
        }
    }

    @Test("Complete offline reports have no age expiry, and removal still blocks them")
    func offlineAndRemoval() async throws {
        try await withDatabase { db in
            _ = try await db.execute(sql: "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES('property_management_report',1,0,?,1000000)", parameters: [parameters])
            let snapshot = try await read(db)
            #expect(snapshot.totals.itemCount == 0)
            #expect(snapshot.provenance.lastSyncedAt?.rawValue == 1000)
            #expect(snapshot.project.address == nil)
            let again = try await read(db)
            #expect(snapshot.reference == again.reference)
            _ = try await db.execute(sql: "UPDATE spike_projects SET display_name='Changed property',revision=2 WHERE id='report-project'", parameters: nil)
            let changed = try await read(db)
            #expect(changed.provenance.localDataVersion != snapshot.provenance.localDataVersion)
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed' WHERE id='report-member'", parameters: nil)
            await #expect(throws: (any Error).self) { try await read(db) }
        }
    }

    @Test("Malformed and duplicated checkpoint evidence never qualifies")
    func malformed() async throws {
        try await withDatabase { db in
            for json in ["not-json", parameters, #"{"account_id":"report-account","project_id":"report-project"}"#] {
                _ = try await db.execute(sql: "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES('property_management_report',1,0,?,1000000)", parameters: [json])
            }
            await #expect(throws: (any Error).self) { try await read(db) }
            _ = try await db.execute(sql: "DELETE FROM ps_stream_subscriptions WHERE local_params='not-json'", parameters: nil)
            await #expect(throws: PropertyManagementReportFailure.incompleteReadiness) { try await read(db) }
        }
    }

    private func read(_ db: any PowerSyncDatabaseProtocol) async throws -> PropertyManagementReportSnapshot {
        try await PropertyManagementReportPowerSyncQuery(database: db).readDownloaded(accountId: account,
            principalId: principal, projectId: project, currency: CurrencyCode(validating: "USD"),
            asOf: .init(validating: 1_800_000_000_000))
    }

    private func withDatabase(_ body: (any PowerSyncDatabaseProtocol) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("report-query-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try LedgerPowerSyncDatabaseFactory.open(absolutePath: root.appendingPathComponent("ledger.sqlite").path,
            encryptionKey: LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "5a", count: 32)))
        do {
            _ = try await db.execute(sql: "INSERT INTO spike_account_memberships(id,account_id,principal_id,state) VALUES('report-member','report-account','report-principal','active')", parameters: nil)
            _ = try await db.execute(sql: "INSERT INTO spike_projects(id,account_id,display_name,lifecycle,revision) VALUES('report-project','report-account','Property','active',1)", parameters: nil)
            try await body(db)
            try await db.close()
        } catch { try? await db.close(); throw error }
    }
}
