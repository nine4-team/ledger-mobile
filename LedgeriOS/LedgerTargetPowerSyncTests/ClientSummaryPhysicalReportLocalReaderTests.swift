import Foundation
import LedgerTargetCore
import PowerSync
import Testing
@testable import LedgerTargetPowerSync

@Suite("Client Summary exact Client relationship", .serialized)
struct ClientSummaryPhysicalReportLocalReaderTests {
    private let account = try! AccountID(validating: "summary-account")
    private let principal = try! PrincipalID(validating: "summary-principal")
    private let project = try! ProjectID(validating: "summary-project")

    @Test func physicalCategoryCompletesReportAndRevalidatesChanges() async throws {
        try await withDatabase { db in
            try await installPaymentFixture(db)
            for sql in [
                "INSERT INTO spike_budget_categories(id,account_id,display_name,visibility_class,lifecycle,revision) VALUES('furnishings','summary-account','Archived furnishings','ordinary','archived',1)",
                "INSERT INTO spike_item_project_categories(id,account_id,project_id,item_id,category_id,revision) VALUES('placement','summary-account','summary-project','chair','furnishings',1)"
            ] { _ = try await db.execute(sql: sql, parameters: nil) }
            func report() async throws -> ClientSummaryPhysicalReportSnapshot {
                try await PropertyManagementReportPowerSyncQuery(database: db)
                    .readDownloadedClientSummary(accountId: account, principalId: principal,
                        projectId: project, asOf: .init(validating: 1_800_000_000_000))
            }
            let first = try await report()
            #expect(first.isComplete && first.items.count == 1)
            #expect(first.items.first?.category == .known(categoryId: try BudgetCategoryID(validating: "furnishings"), name: "Archived furnishings"))
            _ = try await db.execute(sql: "UPDATE spike_budget_categories SET display_name='Renamed category',revision=2", parameters: nil)
            #expect(try await report().reference != first.reference)
            _ = try await db.execute(sql: "UPDATE spike_budget_categories SET visibility_class='company_financial'", parameters: nil)
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET financial_access='limited'", parameters: nil)
            #expect(try await readItems(db).first?.category == .unavailable)
            #expect(try await report().isComplete == false)
            _ = try await db.execute(sql: "UPDATE spike_item_project_categories SET item_id='wrong-item'", parameters: nil)
            await #expect(throws: ClientSummaryPhysicalReportLocalReadFailure.malformedItem) { try await readItems(db) }
        }
    }

    @Test func preservesArchivedClientNameAndRevision() async throws {
        try await withDatabase { db in
            let client = try await read(db)
            #expect(client == .known(clientId: try ClientID(validating: "summary-client"),
                                     name: "Original Client", revision: 2))
            _ = try await db.execute(sql: "UPDATE spike_clients SET display_name='Renamed', revision=3", parameters: nil)
            #expect(try await read(db) == .known(clientId: try ClientID(validating: "summary-client"),
                                               name: "Renamed", revision: 3))
        }
    }

    @Test func rejectsRemovedMembership() async throws {
        try await withDatabase { db in
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed'", parameters: nil)
            await #expect(throws: ClientSummaryPhysicalReportLocalReadFailure.accountUnavailable) {
                try await read(db)
            }
        }
    }

    @Test func rejectsMissingAndCrossAccountClient() async throws {
        try await withDatabase { db in
            _ = try await db.execute(sql: "UPDATE spike_clients SET account_id='another-account'", parameters: nil)
            await #expect(throws: ClientSummaryPhysicalReportLocalReadFailure.missingClientRelationship) {
                try await read(db)
            }
            _ = try await db.execute(sql: "DELETE FROM spike_clients", parameters: nil)
            await #expect(throws: ClientSummaryPhysicalReportLocalReadFailure.missingClientRelationship) {
                try await read(db)
            }
        }
    }

    @Test func rejectsInvalidRevision() async throws {
        try await withDatabase { db in
            _ = try await db.execute(sql: "UPDATE spike_clients SET revision=0", parameters: nil)
            await #expect(throws: ClientSummaryPhysicalReportLocalReadFailure.malformedClient) {
                try await read(db)
            }
        }
    }

    @Test func physicalRowsDoNotInferCategoryOrRequireMoney() async throws {
        try await withDatabase { db in
            _ = try await db.execute(sql: "INSERT INTO spike_items(id,account_id,description,revision,market_value_minor_units) VALUES('chair','summary-account','Receipt wording',1,'invalid-money')", parameters: nil)
            _ = try await db.execute(sql: "INSERT INTO spike_item_placements(id,account_id,item_id,scope_kind,project_id) VALUES('placement','summary-account','chair','project','summary-project')", parameters: nil)
            let items = try await readItems(db)
            #expect(items.count == 1)
            #expect(items.first?.name == "Receipt wording")
            #expect(items.first?.category == .unavailable)
            _ = try await db.execute(sql: "DELETE FROM spike_items", parameters: nil)
            await #expect(throws: ClientSummaryPhysicalReportLocalReadFailure.malformedItem) {
                try await readItems(db)
            }
        }
    }

    @Test func emptyPhysicalReadStillRequiresAccess() async throws {
        try await withDatabase { db in
            #expect(try await readItems(db).isEmpty)
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed'", parameters: nil)
            await #expect(throws: ClientSummaryPhysicalReportLocalReadFailure.accountUnavailable) {
                try await readItems(db)
            }
        }
    }

    @Test func coherentPhysicalReadPreservesArchivedSpaceAndIgnoresMoney() async throws {
        try await withDatabase { db in
            _ = try await db.execute(sql: "INSERT INTO spike_spaces(id,account_id,project_id,scope_kind,display_name,lifecycle,revision) VALUES('room','summary-account','summary-project','project','Living room','archived',4)", parameters: nil)
            _ = try await db.execute(sql: "INSERT INTO spike_items(id,account_id,name,revision,market_value_minor_units) VALUES('chair','summary-account','Chair',1,'invalid-money')", parameters: nil)
            _ = try await db.execute(sql: "INSERT INTO spike_item_placements(id,account_id,item_id,scope_kind,project_id,space_id) VALUES('placement','summary-account','chair','project','summary-project','room')", parameters: nil)
            let result = try await readAll(db)
            #expect(result.project.name == "Project")
            #expect(result.spaces.first?.name == "Living room")
            #expect(result.spaces.first?.revision == 4)
            #expect(result.items.first?.name == "Chair")
            _ = try await db.execute(sql: "DELETE FROM spike_spaces", parameters: nil)
            await #expect(throws: ClientSummaryPhysicalReportLocalReadFailure.missingSpace) {
                try await readAll(db)
            }
        }
    }

    @Test func coherentPhysicalReadRejectsForeignSpace() async throws {
        try await withDatabase { db in
            _ = try await db.execute(sql: "INSERT INTO spike_spaces(id,account_id,project_id,scope_kind,display_name,lifecycle,revision) VALUES('room','foreign-account','summary-project','project','Foreign room','active',1)", parameters: nil)
            await #expect(throws: PropertyManagementReportLocalReadFailure.malformedEvidence) {
                try await readAll(db)
            }
        }
    }

    @Test func reportRequiresExactDownloadAndBindsClientChanges() async throws {
        try await withDatabase { db in
            func report() async throws -> ClientSummaryPhysicalReportSnapshot {
                try await PropertyManagementReportPowerSyncQuery(database: db)
                    .readDownloadedClientSummary(accountId: account, principalId: principal,
                        projectId: project, asOf: .init(validating: 1_800_000_000_000))
            }
            await #expect(throws: PropertyManagementReportFailure.incompleteReadiness) { try await report() }
            _ = try await db.execute(sql: "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES('property_management_report',1,0,?,1000000)",
                parameters: [#"{"account_id":"summary-account","project_id":"summary-project"}"#])
            let first = try await report()
            #expect(first.isComplete && first.items.isEmpty)
            #expect(first.provenance.lastSyncedAt?.rawValue == 1000)
            #expect(try await report().reference == first.reference)
            _ = try await db.execute(sql: "UPDATE spike_clients SET display_name='Renamed',revision=3", parameters: nil)
            #expect(try await report().reference != first.reference)
            _ = try await db.execute(sql: "UPDATE ps_stream_subscriptions SET active=0", parameters: nil)
            await #expect(throws: PropertyManagementReportFailure.incompleteReadiness) { try await report() }
        }
    }

    @Test func completedPhysicalDownloadDoesNotInventAccountingOrCategory() async throws {
        try await withDatabase { db in
            _ = try await db.execute(sql: "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES('property_management_report',1,0,?,1000000)",
                parameters: [#"{"account_id":"summary-account","project_id":"summary-project"}"#])
            _ = try await db.execute(sql: "INSERT INTO spike_items(id,account_id,name,revision,market_value_minor_units) VALUES('chair','summary-account','Chair',1,'invalid-money')", parameters: nil)
            _ = try await db.execute(sql: "INSERT INTO spike_item_placements(id,account_id,item_id,scope_kind,project_id) VALUES('placement','summary-account','chair','project','summary-project')", parameters: nil)
            let query = PropertyManagementReportPowerSyncQuery(database: db)
            let snapshot = try await query.readDownloadedClientSummary(accountId: account,
                principalId: principal, projectId: project, asOf: .init(validating: 1_800_000_000_000))
            #expect(!snapshot.isComplete && snapshot.items.count == 1)
            #expect(snapshot.items[0].category == .unavailable && snapshot.items[0].accounting == nil)
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed'", parameters: nil)
            await #expect(throws: ClientSummaryPhysicalReportLocalReadFailure.accountUnavailable) {
                try await query.readDownloadedClientSummary(accountId: account,
                    principalId: principal, projectId: project, asOf: .init(validating: 1_800_000_000_000))
            }
        }
    }

    @Test func liveClientChangesAndRemovalReplaceVisibleEvidence() async throws {
        try await withDatabase { db in
            let updates = AsyncThrowingStream<ClientSummaryPhysicalReportUpdate, Error>.makeStream()
            let consumer = Task {
                do {
                    try await ClientSummaryPhysicalReportWatch(database: db).run(accountId: account,
                        principalId: principal, projectId: project) { value in
                            updates.continuation.yield(value)
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
                _ = try await db.execute(sql: "UPDATE ps_stream_subscriptions SET active=1,last_synced_at=1000000 WHERE stream_name='property_management_report'", parameters: nil)
                while true {
                    if case .ready(let report) = try #require(await iterator.next()) {
                        #expect(report.isComplete)
                        break
                    }
                }
                _ = try await db.execute(sql: "UPDATE spike_clients SET display_name='Live rename',revision=3", parameters: nil)
                while true {
                    if case .ready(let report) = try #require(await iterator.next()),
                       case .known(_, let name, _) = report.client, name == "Live rename" { break }
                }
                _ = try await db.execute(sql: "DELETE FROM spike_clients", parameters: nil)
                while try #require(await iterator.next()) != .incomplete { }
                _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed'", parameters: nil)
                await #expect(throws: ClientSummaryPhysicalReportLocalReadFailure.accountUnavailable) {
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

    @Test func clientPaymentEvidenceEnablesPropertyReportButNotMissingClientCategory() async throws {
        try await withDatabase { db in
            try await installPaymentFixture(db)
            let client = try await readAll(db)
            #expect(client.items[0].accounting?.resolution == .accountedFor)
            #expect(client.items[0].category == .unavailable)
            let query = PropertyManagementReportPowerSyncQuery(database: db)
            let report = try await query.readDownloaded(accountId: account, principalId: principal,
                projectId: project, currency: CurrencyCode(validating: "USD"), asOf: .init(validating: 2000))
            #expect(report.totals.itemCount == 1 && report.totals.totalMarketValue?.minorUnits == 500)
            let summary = try await query.readDownloadedClientSummary(accountId: account,
                principalId: principal, projectId: project, asOf: .init(validating: 2000))
            #expect(!summary.isComplete)
            // Learned financial restriction must suppress already-retained links.
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET financial_access='none'", parameters: nil)
            #expect(try await readAll(db).items[0].accounting == nil)
            await #expect(throws: PropertyManagementReportFailure.incompleteReadiness) {
                try await query.readDownloaded(accountId: account, principalId: principal,
                    projectId: project, currency: CurrencyCode(validating: "USD"), asOf: .init(validating: 2000))
            }
        }
    }

    @Test func closedOrEarlierPlacementLinkCannotQualifyCurrentItem() async throws {
        try await withDatabase { db in
            try await installPaymentFixture(db)
            _ = try await db.execute(sql: "UPDATE item_client_payment_connections SET ended_at='2026-09-03'", parameters: nil)
            #expect(try await readAll(db).items[0].accounting == nil)
            _ = try await db.execute(sql: "UPDATE item_client_payment_connections SET ended_at=NULL", parameters: nil)
            _ = try await db.execute(sql: "UPDATE spike_item_placements SET ended_at='2026-09-03'", parameters: nil)
            _ = try await db.execute(sql: "INSERT INTO spike_item_placements(id,account_id,item_id,scope_kind,project_id) VALUES('new-placement','summary-account','chair','project','summary-project')", parameters: nil)
            #expect(try await readAll(db).items[0].accounting == nil)
        }
    }

    @Test func malformedClientPaymentCannotQualifyItem() async throws {
        try await withDatabase { db in
            try await installPaymentFixture(db)
            _ = try await db.execute(sql: "UPDATE item_client_payment_connections SET client_id='foreign-client'", parameters: nil)
            await #expect(throws: PropertyManagementReportLocalReadFailure.malformedEvidence) { try await readAll(db) }
        }
    }

    @Test func paymentClosureInvalidatesLivePropertyReport() async throws {
        try await withDatabase { db in
            try await installPaymentFixture(db)
            let updates = AsyncThrowingStream<PropertyManagementReportUpdate, Error>.makeStream()
            let consumer = Task {
                do {
                    try await PropertyManagementReportWatch(database: db).run(accountId: account,
                        principalId: principal, projectId: project, currency: CurrencyCode(validating: "USD")) { value in
                            updates.continuation.yield(value)
                            return true
                        }
                    updates.continuation.finish()
                } catch { updates.continuation.finish(throwing: error) }
            }
            let deadline = Task {
                try await Task.sleep(for: .seconds(10))
                consumer.cancel(); updates.continuation.finish()
            }
            do {
                var iterator = updates.stream.makeAsyncIterator()
                while true {
                    if case .ready(let report) = try #require(await iterator.next()) {
                        #expect(report.totals.itemCount == 1)
                        break
                    }
                }
                _ = try await db.execute(sql: "UPDATE item_client_payment_connections SET ended_at='2026-09-03'", parameters: nil)
                while try #require(await iterator.next()) != .incomplete { }
                consumer.cancel(); deadline.cancel()
                await consumer.value
            } catch {
                consumer.cancel(); deadline.cancel()
                await consumer.value
                throw error
            }
        }
    }

    private func installPaymentFixture(_ db: any PowerSyncDatabaseProtocol) async throws {
        for sql in [
            "UPDATE spike_account_memberships SET financial_access='full'",
            "INSERT INTO spike_items(id,account_id,name,revision,market_value_minor_units,market_value_currency) VALUES('chair','summary-account','Chair',1,'500','USD')",
            "INSERT INTO spike_item_placements(id,account_id,item_id,scope_kind,project_id) VALUES('placement','summary-account','chair','project','summary-project')",
            "INSERT INTO item_client_payment_connections(id,account_id,project_id,client_id,item_id,placement_id,transaction_id,transaction_type,transaction_role) VALUES('link','summary-account','summary-project','summary-client','chair','placement','purchase','purchase','standalone')",
            #"INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES('property_management_report',1,0,'{"account_id":"summary-account","project_id":"summary-project"}',1000000)"#
        ] { _ = try await db.execute(sql: sql, parameters: nil) }
    }

    private func readAll(_ db: any PowerSyncDatabaseProtocol) async throws -> ClientSummaryPhysicalReportLocalInputs {
        try await db.readTransaction { transaction in
            try ClientSummaryPhysicalReportLocalReader.read(transaction: transaction,
                accountId: account, principalId: principal, projectId: project)
        }
    }

    private func readItems(_ db: any PowerSyncDatabaseProtocol) async throws -> [ClientSummaryPhysicalReportItem] {
        try await db.readTransaction { transaction in
            try ClientSummaryPhysicalReportLocalReader.readItems(transaction: transaction,
                accountId: account, principalId: principal, projectId: project)
        }
    }

    private func read(_ db: any PowerSyncDatabaseProtocol) async throws -> ClientSummaryPhysicalReportClient {
        try await db.readTransaction { transaction in
            try ClientSummaryPhysicalReportLocalReader.readClient(transaction: transaction,
                accountId: account, principalId: principal, projectId: project)
        }
    }

    private func withDatabase(_ body: (any PowerSyncDatabaseProtocol) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("client-summary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try LedgerPowerSyncDatabaseFactory.open(absolutePath: root.appendingPathComponent("ledger.sqlite").path,
            encryptionKey: LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "4a", count: 32)))
        do {
            for sql in [
                "INSERT INTO spike_account_memberships(id,account_id,principal_id,state) VALUES('member','summary-account','summary-principal','active')",
                "INSERT INTO spike_projects(id,account_id,client_id,display_name,lifecycle,revision) VALUES('summary-project','summary-account','summary-client','Project','active',1)",
                "INSERT INTO spike_clients(id,account_id,display_name,lifecycle,revision) VALUES('summary-client','summary-account','Original Client','archived',2)"
            ] { _ = try await db.execute(sql: sql, parameters: nil) }
            try await body(db)
            try await db.close()
        } catch { try? await db.close(); throw error }
    }
}
