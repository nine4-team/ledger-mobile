import Foundation
import LedgerTargetCore
import PowerSync
import Testing
@testable import LedgerTargetPowerSync

@Suite("Coherent downloaded Property Management inputs", .serialized)
struct PropertyManagementReportLocalReaderTests {
    private let account = try! AccountID(validating: "report-account")
    private let principal = try! PrincipalID(validating: "report-principal")
    private let project = try! ProjectID(validating: "report-project")

    @Test("Actual Postgres stream rows match the authoritative MCP report",
          .enabled(if: ProcessInfo.processInfo.environment["LEDGER_REPORT_PARITY_INPUT"] != nil
                    || ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
                   "Requires the guarded local MCP script's differential artifact"))
    func actualMCPReaderParity() async throws {
        let environment = ProcessInfo.processInfo.environment
        let path = try #require(environment["LEDGER_REPORT_PARITY_INPUT"]
            ?? environment["RUNNER_TEMP"].map { "\($0)/ledger-property-report-parity.json" })
        let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
        try await withDatabase(seed: false) { db in
            let fixture = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            let account = try AccountID(validating: #require(fixture["accountId"] as? String))
            let principal = try PrincipalID(validating: #require(fixture["principalId"] as? String))
            let project = try ProjectID(validating: #require(fixture["projectId"] as? String))
            let currency = try CurrencyCode(validating: #require(fixture["currency"] as? String))
            let expected = try #require(fixture["report"] as? [String: Any])
            let provenance = try #require(expected["provenance"] as? [String: Any])
            #expect(provenance["accountId"] as? String == account.rawValue)
            #expect(provenance["principalId"] as? String == principal.rawValue)
            #expect(provenance["projectId"] as? String == project.rawValue)
            #expect(expected["currency"] as? String == currency.rawValue)
            let tables = try #require(fixture["tables"] as? [[String: Any]])
            let allowed = Set(["spike_projects", "spike_spaces", "spike_item_placements", "spike_items",
                "spike_clients", "item_client_payment_connections", "spike_item_project_categories", "spike_budget_categories"])
            #expect(Set(tables.compactMap { $0["table"] as? String }) == allowed)
            #expect(tables.count == 8)
            for table in tables {
                let name = try #require(table["table"] as? String)
                guard allowed.contains(name) else { throw CocoaError(.coderInvalidValue) }
                let rows = try #require(table["rows"] as? [[String: Any]])
                for row in rows {
                    let columns = row.keys.sorted()
                    guard columns.allSatisfy({ $0.range(of: "^[a-z_]+$", options: .regularExpression) != nil })
                    else { throw CocoaError(.coderInvalidValue) }
                    let json = String(decoding: try JSONSerialization.data(withJSONObject: row), as: UTF8.self)
                    let values = columns.map { "json_extract(?, '$.\($0)')" }.joined(separator: ",")
                    _ = try await db.execute(sql: "INSERT INTO \(name)(\(columns.joined(separator: ","))) VALUES(\(values))",
                        parameters: columns.map { _ in json })
                }
            }
            _ = try await db.execute(sql: "INSERT INTO spike_account_memberships(id,account_id,principal_id,state,financial_access) VALUES('parity-member',?,?, 'active','full')",
                parameters: [account.rawValue, principal.rawValue])
            let inputs = try await PropertyManagementReportLocalReader(database: db)
                .read(accountId: account, principalId: principal, projectId: project)
            let snapshot = try PropertyManagementReportSnapshot.build(project: inputs.project,
                spaces: inputs.spaces, items: inputs.items, currency: currency,
                provenance: .init(accountId: account, projectId: project, principalId: principal,
                    visibilityScopeID: .make(bytes: Data("differential-local".utf8)),
                    localDataVersion: .init(validating: "differential-local"),
                    authorityVersion: .init(validating: "property-management-v1"),
                    asOf: .init(validating: 1_800_000_000_000), readiness: .ready,
                    lastSyncedAt: .init(validating: 1_800_000_000_000)))
            let actual = try #require(JSONSerialization.jsonObject(with: snapshot.canonicalData()) as? [String: Any])
            let clientInputs = try await db.readTransaction { transaction in
                try ClientSummaryPhysicalReportLocalReader.read(transaction: transaction,
                    accountId: account, principalId: principal, projectId: project)
            }
            #expect(clientInputs.items.count == 3)
            #expect(clientInputs.items.allSatisfy { item in
                if case .known(_, "Furnishings") = item.category { return true }
                return false
            })
            let expectedClient = try #require(fixture["clientReport"] as? [String: Any])
            let clientProvenance = try #require(expectedClient["provenance"] as? [String: Any])
            #expect(clientProvenance["principalId"] as? String == principal.rawValue)
            #expect(clientProvenance["authorityVersion"] as? String == "client-summary-physical-v1")
            let scopeEncoder = JSONEncoder()
            scopeEncoder.outputFormatting = [.withoutEscapingSlashes]
            let scope = try ProtectedArtifactVisibilityScopeID.make(bytes: scopeEncoder.encode([
                account.rawValue, principal.rawValue, project.rawValue, "client-summary-physical-v1"]))
            #expect(clientProvenance["visibilityScopeID"] as? String == scope.rawValue)
            let clientSummary = try ClientSummaryPhysicalReportSnapshot.build(project: clientInputs.project,
                client: clientInputs.client, spaces: clientInputs.spaces, items: clientInputs.items,
                provenance: .init(accountId: account, projectId: project, principalId: principal,
                    visibilityScopeID: scope, source: .authoritative,
                    authorityVersion: .init(validating: "client-summary-physical-v1"),
                    asOf: .init(validating: #require(clientProvenance["asOf"] as? Int64)), readiness: .ready))
            #expect(clientSummary.isComplete)
            let actualClient = try #require(JSONSerialization.jsonObject(with: clientSummary.canonicalData()) as? [String: Any])
            #expect(NSDictionary(dictionary: actualClient).isEqual(to: expectedClient),
                "Actual online MCP and downloaded native Client source, provenance and all hashes must agree")
            // Deliberately exclude online-versus-downloaded provenance and the
            // resulting snapshot reference; source data and calculation must match.
            for key in ["reportKind", "project", "spaces", "groups", "totals", "currency", "sourceSetHash"] {
                let left = try #require(actual[key]), right = try #require(expected[key])
                #expect(NSDictionary(dictionary: [key: left]).isEqual(to: [key: right]), "Mismatch: \(key)")
            }
        }
    }

    @Test("Pinned core withdrawal and resubscription cannot certify evicted report rows")
    func coreWithdrawalAndResubscription() async throws {
        try await withDatabase(seed: false) { db in
            let parameters: JsonParam = ["account_id": .string(account.rawValue), "project_id": .string(project.rawValue)]
            let stream = db.syncStream(name: "property_management_report", params: parameters)
            let subscription = try await stream.subscribe()
            let schema = try JSONSerialization.jsonObject(with: JSONEncoder().encode(LedgerPowerSyncSchema.schema))
            let start: [String: Any] = ["parameters": [:], "schema": schema, "include_defaults": false,
                "active_streams": [["name": "property_management_report", "params": ["account_id": account.rawValue, "project_id": project.rawValue]]],
                "app_metadata": [:], "checkpoint_mode": "legacy"]
            func json(_ object: Any) throws -> String {
                String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
            }
            func control(_ operation: String, _ parameter: String?) async throws {
                let instructions = try await db.writeTransaction { tx in
                    try tx.getAll(sql: "SELECT powersync_control(?,?) AS result", parameters: [operation, parameter]) {
                        try $0.getString(name: "result")
                    }
                }
                print("report-core-control-\(operation): \(instructions)")
            }
            func observed(_ label: String) async throws -> (Int, Int64?, Int) {
                let metadata = try await db.getAll(sql: "SELECT active,last_synced_at FROM ps_stream_subscriptions WHERE stream_name='property_management_report'", parameters: nil) {
                    (try $0.getInt(name: "active"), try $0.getInt64Optional(name: "last_synced_at"))
                }
                let count = try await db.get(sql: "SELECT count(*) AS count FROM spike_items WHERE id='core-synced-chair'", parameters: nil) { try $0.getInt(name: "count") }
                print("report-core-\(label): metadata=\(metadata), bucketRows=\(count)")
                return (metadata.first?.0 ?? 0, metadata.first?.1, count)
            }
            try await control("start", json(start))
            try await control("connection", "established")
            try await control("line_text", json(["checkpoint": ["last_op_id": "1", "buckets": [["bucket": "report-test-bucket", "priority": 3, "checksum": 0, "subscriptions": [["sub": 0]]]], "streams": [["name": "property_management_report", "is_default": false, "errors": []]]]]))
            let data = try json(["account_id": account.rawValue, "name": "Core downloaded", "description": "", "revision": 1])
            try await control("line_text", json(["data": ["bucket": "report-test-bucket", "data": [["checksum": 0, "op_id": "1", "object_id": "core-synced-chair", "object_type": "spike_items", "op": "PUT", "data": data]], "has_more": false]]))
            try await control("line_text", json(["checkpoint_complete": ["last_op_id": "1"]]))
            let completed = try await observed("completed")
            #expect(completed.0 == 1 && completed.1 != nil && completed.2 == 1)
            try await control("stop", nil)
            // Exercise the SDK unsubscribe action and core expiry handling. Only
            // expiry time is accelerated; completion/data were created by core.
            try await stream.unsubscribeAll()
            _ = try await db.execute(sql: "UPDATE ps_stream_subscriptions SET expires_at=0 WHERE stream_name='property_management_report'", parameters: nil)
            var withoutSubscription = start
            withoutSubscription["active_streams"] = []
            try await control("start", json(withoutSubscription))
            let expired = try await observed("expired-start")
            #expect(expired.0 == 0 && expired.1 == nil && expired.2 == 1)
            let identity = PropertyManagementReportStreamIdentity(accountId: account, projectId: project)
            await #expect(throws: PropertyManagementReportFailure.incompleteReadiness) {
                try await db.readTransaction { tx in try PropertyManagementReportPowerSyncQuery.completedCheckpoint(transaction: tx, identity: identity) }
            }
            try await control("connection", "established")
            try await control("line_text", json(["checkpoint": ["last_op_id": "2", "buckets": [], "streams": []]]))
            try await control("line_text", json(["checkpoint_complete": ["last_op_id": "2"]]))
            let evicted = try await observed("withdrawn")
            #expect(evicted.2 == 0)
            await #expect(throws: PropertyManagementReportFailure.incompleteReadiness) {
                try await db.readTransaction { tx in try PropertyManagementReportPowerSyncQuery.completedCheckpoint(transaction: tx, identity: identity) }
            }
            try await control("stop", nil)
            let replacement = try await stream.subscribe()
            _ = try await observed("resubscribed")
            await #expect(throws: PropertyManagementReportFailure.incompleteReadiness) {
                try await db.readTransaction { tx in try PropertyManagementReportPowerSyncQuery.completedCheckpoint(transaction: tx, identity: identity) }
            }
            try await replacement.unsubscribe()
            try await subscription.unsubscribe()
        }
    }

    @Test("Exact signed amounts, unknown versus zero, and actual archived Space parent survive")
    func valuesAndParents() async throws {
        try await withDatabase { db in
            let reader = PropertyManagementReportLocalReader(database: db)
            let unknown = try await reader.read(accountId: account, principalId: principal, projectId: project)
            #expect(unknown.project.address == nil)
            #expect(unknown.items.first?.marketValue == nil)
            #expect(unknown.items.first?.name == "Actual name")
            #expect(unknown.spaces.first?.name == "Archived room")
            #expect(unknown.items.first?.spaceId == unknown.spaces.first?.spaceId)
            for amount: Int64 in [0, 9_007_199_254_740_993, Int64.min, Int64.max] {
                _ = try await db.execute(sql: "UPDATE spike_items SET market_value_minor_units=?,market_value_currency='USD' WHERE id='chair'", parameters: [amount])
                let read = try await reader.read(accountId: account, principalId: principal, projectId: project)
                #expect(read.items.first?.marketValue?.minorUnits == amount)
                #expect(read.items.first?.marketValue?.currency.rawValue == "USD")
            }
            _ = try await db.execute(sql: "UPDATE spike_items SET name=NULL WHERE id='chair'", parameters: nil)
            let fallback = try await reader.read(accountId: account, principalId: principal, projectId: project)
            #expect(fallback.items.first?.name == "Source description")
            let storedName = try await db.getAll(sql: "SELECT name FROM spike_items WHERE id='chair'", parameters: nil) { try $0.getStringOptional(name: "name") }
            #expect(storedName.count == 1 && storedName[0] == nil)
        }
    }

    @Test("An authorized empty Project is distinct from unavailable Project or Principal")
    func emptyAndDenied() async throws {
        try await withDatabase { db in
            _ = try await db.execute(sql: "DELETE FROM spike_item_placements", parameters: nil)
            let reader = PropertyManagementReportLocalReader(database: db)
            let empty = try await reader.read(accountId: account, principalId: principal, projectId: project)
            #expect(empty.items.isEmpty)
            #expect(empty.spaces.isEmpty) // Unreferenced archived room is not required.
            await #expect(throws: PropertyManagementReportLocalReadFailure.accountUnavailable) {
                try await reader.read(accountId: account, principalId: PrincipalID(validating: "other-principal"), projectId: project)
            }
            await #expect(throws: PropertyManagementReportLocalReadFailure.accountUnavailable) {
                try await reader.read(accountId: AccountID(validating: "other-account"), principalId: principal, projectId: project)
            }
            await #expect(throws: PropertyManagementReportLocalReadFailure.missingProject) {
                try await reader.read(accountId: account, principalId: principal, projectId: ProjectID(validating: "other-project"))
            }
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed'", parameters: nil)
            await #expect(throws: PropertyManagementReportLocalReadFailure.accountUnavailable) {
                try await reader.read(accountId: account, principalId: principal, projectId: project)
            }
        }
    }

    @Test("Dangling, foreign, duplicate and malformed facts cannot become report inputs")
    func invalidGraphs() async throws {
        for sql in [
            "DELETE FROM spike_items WHERE id='chair'",
            "UPDATE spike_items SET account_id='other-account' WHERE id='chair'",
            "UPDATE spike_items SET revision=0 WHERE id='chair'",
            "UPDATE spike_items SET market_value_minor_units=1 WHERE id='chair'",
            "UPDATE spike_items SET market_value_currency='USD' WHERE id='chair'",
            "UPDATE spike_items SET market_value_minor_units=1.5,market_value_currency='USD' WHERE id='chair'",
            "UPDATE spike_items SET market_value_minor_units='9223372036854775808',market_value_currency='USD' WHERE id='chair'",
            "UPDATE spike_items SET market_value_minor_units='-9223372036854775809',market_value_currency='USD' WHERE id='chair'",
            "UPDATE spike_items SET market_value_minor_units='1e3',market_value_currency='USD' WHERE id='chair'",
            "DELETE FROM spike_spaces WHERE id='room'",
            "UPDATE spike_spaces SET project_id='other-project' WHERE id='room'",
            "UPDATE spike_spaces SET account_id='other-account' WHERE id='room'",
            "UPDATE spike_spaces SET scope_kind='business_inventory' WHERE id='room'",
            "UPDATE spike_item_placements SET scope_kind='business_inventory' WHERE id='placement'",
            "UPDATE spike_item_placements SET account_id='other-account' WHERE id='placement'",
            "INSERT INTO spike_item_placements(id,account_id,item_id,scope_kind,project_id) VALUES('duplicate','report-account','chair','project','other-project')"
        ] {
            try await withDatabase { db in
                _ = try await db.execute(sql: sql, parameters: nil)
                await #expect(throws: PropertyManagementReportLocalReadFailure.malformedEvidence) {
                    try await PropertyManagementReportLocalReader(database: db).read(accountId: account, principalId: principal, projectId: project)
                }
            }
        }
    }

    @Test("Transaction entry yields deterministic identity order without promoting readiness")
    func transactionEntry() async throws {
        try await withDatabase { db in
            _ = try await db.execute(sql: "INSERT INTO spike_spaces(id,account_id,project_id,scope_kind,display_name,lifecycle,revision) VALUES('aaa-room','report-account','report-project','project','Unoccupied active','active',1)", parameters: nil)
            let read = try await db.readTransaction { tx in
                try PropertyManagementReportLocalReader.read(transaction: tx, accountId: account, principalId: principal, projectId: project)
            }
            #expect(read.spaces.map(\.spaceId.rawValue) == ["aaa-room", "room"])
            #expect(read.items.map(\.itemId.rawValue) == ["chair"])
            #expect(read.project.projectId == project)
        }
    }

    private func withDatabase(seed: Bool = true, _ body: (any PowerSyncDatabaseProtocol) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("report-reader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try LedgerPowerSyncDatabaseFactory.open(absolutePath: root.appendingPathComponent("ledger.sqlite").path,
            encryptionKey: LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "4a", count: 32)))
        do {
            for sql in seed ? [
                "INSERT INTO spike_account_memberships(id,account_id,principal_id,state) VALUES('member','report-account','report-principal','active')",
                "INSERT INTO spike_projects(id,account_id,display_name,description,lifecycle,revision) VALUES('report-project','report-account','Property','Not an address','active',1)",
                "INSERT INTO spike_spaces(id,account_id,project_id,scope_kind,display_name,lifecycle,revision) VALUES('room','report-account','report-project','project','Archived room','archived',1)",
                "INSERT INTO spike_items(id,account_id,name,description,sku,revision) VALUES('chair','report-account','Actual name','Source description','SKU',1)",
                "INSERT INTO spike_item_placements(id,account_id,item_id,scope_kind,project_id,space_id,started_at) VALUES('placement','report-account','chair','project','report-project','room','2026-09-01')"
            ] : [] { _ = try await db.execute(sql: sql, parameters: nil) }
            try await body(db)
            try await db.close()
        } catch { try? await db.close(); throw error }
    }
}
