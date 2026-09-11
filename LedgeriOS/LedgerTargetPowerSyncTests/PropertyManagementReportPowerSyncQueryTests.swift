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

    @Test("Equivalent SDK parameter dictionaries retain one canonical subscription")
    func subscriptionParameterOrder() async throws {
        try await withDatabase { db in
            var subscriptions: [any SyncStreamSubscription] = []
            for index in 0..<32 {
                var params: JsonParam = [:]
                let fields = index.isMultiple(of: 2)
                    ? [("project_id", project.rawValue), ("account_id", account.rawValue)]
                    : [("account_id", account.rawValue), ("project_id", project.rawValue)]
                for (key, value) in fields { params[key] = .string(value) }
                subscriptions.append(try await db.syncStream(name: "property_management_report", params: params).subscribe())
            }
            let stored = try await db.getAll(sql: "SELECT local_params FROM ps_stream_subscriptions WHERE stream_name='property_management_report'",
                parameters: nil) { try $0.getString(name: "local_params") }
            #expect(stored == [#"{"account_id":"report-account","project_id":"report-project"}"#])
            withExtendedLifetime(subscriptions) {}
        }
    }

    @Test("Core-completed report survives encrypted reopen and offline resubscription")
    func encryptedOfflineReopen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("report-reopen-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("ledger.sqlite").path
        let key = try LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "5a", count: 32))
        var db = try LedgerPowerSyncDatabaseFactory.open(absolutePath: path, encryptionKey: key)
        do {
            let identity = PropertyManagementReportStreamIdentity(accountId: account, projectId: project)
            let subscription = try await db.syncStream(name: identity.name, params: identity.parameters).subscribe()
            func json(_ value: Any) throws -> String {
                String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
            }
            // Feed a synthetic protocol download through the pinned engine.
            // No provider connection or fabricated completed-checkpoint row.
            let schema = try JSONSerialization.jsonObject(with: JSONEncoder().encode(LedgerPowerSyncSchema.schema))
            let start: [String: Any] = ["parameters": [:], "schema": schema, "include_defaults": false,
                "active_streams": [["name": identity.name, "params": ["account_id": account.rawValue, "project_id": project.rawValue]]],
                "app_metadata": [:], "checkpoint_mode": "legacy"]
            let facts: [(String, String, [String: Any])] = [
                ("spike_account_memberships", "report-member", ["account_id": account.rawValue, "principal_id": principal.rawValue, "state": "active", "financial_access": "full"]),
                ("spike_projects", project.rawValue, ["account_id": account.rawValue, "client_id": "report-client", "display_name": "Offline property", "property_address": "123 Synthetic Street", "lifecycle": "active", "revision": 1]),
                ("spike_items", "offline-chair", ["account_id": account.rawValue, "name": "Offline chair", "sku": "CHAIR-1", "market_value_minor_units": "9007199254740993", "market_value_currency": "USD", "revision": 1]),
                ("spike_item_placements", "offline-placement", ["account_id": account.rawValue, "item_id": "offline-chair", "project_id": project.rawValue, "scope_kind": "project"]),
                ("item_client_payment_connections", "offline-payment-link", ["account_id": account.rawValue,
                    "project_id": project.rawValue, "client_id": "report-client", "item_id": "offline-chair",
                    "placement_id": "offline-placement", "transaction_id": "report-purchase",
                    "transaction_type": "purchase", "transaction_role": "standalone"]),
            ]
            let rows = try facts.enumerated().map { index, fact -> [String: Any] in
                ["checksum": 0, "op_id": String(index + 1), "object_id": fact.1,
                 "object_type": fact.0, "op": "PUT", "data": try json(fact.2)]
            }
            let controls: [(String, String?)] = [
                ("start", try json(start)), ("connection", "established"),
                ("line_text", try json(["checkpoint": ["last_op_id": "5", "buckets": [["bucket": "report-reopen-bucket", "priority": 3, "checksum": 0, "subscriptions": [["sub": 0]]]], "streams": [["name": identity.name, "is_default": false, "errors": []]]]])),
                ("line_text", try json(["data": ["bucket": "report-reopen-bucket", "data": rows, "has_more": false]])),
                ("line_text", try json(["checkpoint_complete": ["last_op_id": "5"]])), ("stop", nil),
            ]
            for (operation, parameter) in controls {
                _ = try await db.writeTransaction { tx in
                    try tx.getAll(sql: "SELECT powersync_control(?,?) AS result", parameters: [operation, parameter]) {
                        try $0.getString(name: "result")
                    }
                }
            }
            let original = try await readReopenCheckpoint(db, stage: "after protocol completion")
            #expect(original.totals.itemCount == 1)
            #expect(original.totals.totalMarketValue?.minorUnits == 9_007_199_254_740_993)
            try await subscription.unsubscribe()
            try await db.close()
            db = try LedgerPowerSyncDatabaseFactory.open(absolutePath: path, encryptionKey: key)
            // Reopening the report follows the SDK's real subscribe path, but
            // no transport is started: bytes and completion must be durable.
            let reopenedSubscription = try await db.syncStream(name: identity.name, params: identity.parameters).subscribe()
            let reopened = try await readReopenCheckpoint(db, stage: "after encrypted reopen and subscribe")
            #expect(reopened.reference == original.reference)
            #expect(PropertyManagementReportCSV.render(reopened) == PropertyManagementReportCSV.render(original))
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed' WHERE id='report-member'", parameters: nil)
            await #expect(throws: PropertyManagementReportLocalReadFailure.accountUnavailable) { try await read(db) }
            try await reopenedSubscription.unsubscribe()
            try await db.close()
        } catch { try? await db.close(); throw error }
    }

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

    private func readReopenCheckpoint(_ db: any PowerSyncDatabaseProtocol, stage: String) async throws -> PropertyManagementReportSnapshot {
        do { return try await read(db) }
        catch {
            let evidence = try? await db.getAll(sql: """
                SELECT json_object('id',id,'params',local_params,'active',active,
                    'synced',last_synced_at,'expires',expires_at) AS evidence
                FROM ps_stream_subscriptions ORDER BY id
                """, parameters: nil) { try $0.getString(name: "evidence") }
            print("Synthetic report checkpoint failure \(stage): \(evidence ?? [])")
            throw error
        }
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
