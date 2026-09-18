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

    @Test("Budget composes downloaded facts and refuses incomplete or unauthorized totals", .timeLimit(.minutes(1)))
    func budgetSnapshot() async throws {
        try await withDatabase { db in
            let query = ProjectBudgetPowerSyncQuery(database: db)
            let usd = try CurrencyCode(validating: "USD")
            await #expect(throws: PropertyManagementReportFailure.incompleteReadiness) {
                try await query.readImplementedSources(accountId: account, principalId: principal, projectId: project, currency: usd)
            }
            for sql in [
                "UPDATE spike_clients SET created_at_ms=1,updated_at_ms=1",
                "UPDATE spike_projects SET created_at_ms=1,updated_at_ms=1",
                "INSERT INTO spike_budget_categories(id,account_id,display_name,kind,lifecycle,is_system,excludes_from_overall_budget,presentation_order,revision) VALUES('category','account','Furnishings','itemized','active',0,0,0,1)",
                "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,last_synced_at) VALUES('spike_projects',1,1,1000000)",
                "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES('physical_account_items',1,0,'{\"account_id\":\"account\"}',1000000)",
                "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES('transaction_receipts',1,0,'{\"account_id\":\"account\",\"project_id\":\"project\",\"scope_kind\":\"project\"}',1000000)"
            ] { _ = try await db.execute(sql: sql, parameters: nil) }
            for name in ["project_live_invoices", "project_expenses", "project_invoicing_item_charges"] {
                _ = try await db.execute(sql: "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES(?,1,0,'{\"account_id\":\"account\",\"project_id\":\"project\"}',1000000)", parameters: [name])
            }
            let initial = try await query.readImplementedSources(accountId: account, principalId: principal, projectId: project, currency: usd).segments
            #expect(initial.count == 1 && initial[0].clientPaid.minorUnits == 0 && initial[0].invoicingUnpaid.minorUnits == 100)
            #expect(try await query.readImplementedSources(accountId: account, principalId: principal, projectId: project, currency: usd).allocations.isEmpty)
            _ = try await db.execute(sql: "INSERT INTO spike_project_category_allocations(id,account_id,project_id,category_id) VALUES('allocation','account','project','category')", parameters: nil)
            let enabled = try await query.readImplementedSources(accountId: account, principalId: principal, projectId: project, currency: usd)
            #expect(enabled.allocations.count == 1 && enabled.allocations[0].allocation == nil)
            _ = try await db.execute(sql: "UPDATE spike_project_category_allocations SET allocation_minor_units=1000,allocation_currency='USD'", parameters: nil)
            let allocated = try await query.readImplementedSources(accountId: account, principalId: principal, projectId: project, currency: usd)
            #expect(allocated.allocations.first?.allocation?.minorUnits == 1000)
            _ = try await db.execute(sql: "UPDATE spike_project_category_allocations SET allocation_currency='EUR'", parameters: nil)
            await #expect(throws: ProjectBudgetSegmentFailure.currencyMismatch) {
                try await query.readImplementedSources(accountId: account, principalId: principal, projectId: project, currency: usd)
            }
            _ = try await db.execute(sql: "UPDATE spike_project_category_allocations SET allocation_currency='USD'", parameters: nil)
            for sql in [
                "INSERT INTO expenses(id,account_id,project_id,category_id,final_amount_minor_units,currency,revision,vendor) VALUES('expense','account','project','category','50','USD',1,'Vendor')",
                "INSERT INTO fee_installments(id,account_id,project_id,category_id,amount_minor_units,currency,revision,label) VALUES('fee','account','project','category','25','USD',1,'Fee')",
                "INSERT INTO spike_transactions(id,account_id,project_id,client_id,scope_kind,type,role,origin,amount_minor_units,currency,category_id,non_item_receipt_lines) VALUES('direct','account','project','client','project','purchase','standalone','vendor_payment','20','USD','category','[]')"
            ] { _ = try await db.execute(sql: sql, parameters: nil) }
            let mixed = try await query.readImplementedSources(accountId: account, principalId: principal, projectId: project, currency: usd).segments
            #expect(mixed.count == 1 && mixed[0].clientPaid.minorUnits == 20 && mixed[0].invoicingUnpaid.minorUnits == 175)
            #expect(mixed[0].recognized.minorUnits == 195)
            let updates = AsyncStream<Int64>.makeStream()
            let watch = Task {
                defer { updates.continuation.finish() }
                try await query.run(accountId: account, principalId: principal, projectId: project, currency: usd) { read in
                    guard let amount = read?.segments.first?.recognized.minorUnits else { return true }
                    updates.continuation.yield(amount)
                    return amount != 196
                }
            }
            defer { watch.cancel() }
            var changes = updates.stream.makeAsyncIterator()
            #expect(await changes.next() == 195)
            _ = try await db.execute(sql: "UPDATE expenses SET final_amount_minor_units='51' WHERE id='expense'", parameters: nil)
            var changed: Int64?
            while let amount = await changes.next() { changed = amount }
            #expect(changed == 196)
            try await watch.value // All owned subscriptions drained before closing the DB.
            _ = try await db.execute(sql: "UPDATE expenses SET final_amount_minor_units='50' WHERE id='expense'", parameters: nil)
            for (id, target, actor, kind, state) in [
                ("pending", "project", "principal", "return_paid_items", "queued"),
                ("rejected", "project", "principal", "edit_expense", "rejected"),
                ("other-project", "elsewhere", "principal", "return_paid_items", "queued"),
                ("other-principal", "project", "someone-else", "return_paid_items", "queued"),
                ("note", "project", "principal", "create_project_note", "queued")
            ] {
                _ = try await db.execute(sql: "INSERT INTO spike_local_operations(id,account_id,actor_principal_id,command_type,local_state,command_envelope_json) VALUES(?,'account',?,?,?,?)",
                    parameters: [id,actor,kind,state,"{\"payload\":{\"projectId\":\"\(target)\"}}"])
            }
            let pending = try await query.readImplementedSources(accountId: account, principalId: principal, projectId: project, currency: usd)
            #expect(pending.segments == mixed)
            #expect(pending.localOperations.map(\.operationId.rawValue) == ["pending", "rejected"])
            #expect(pending.localOperations.map(\.localState) == [.queued, .rejected])
            for (id, kind, payload) in [
                ("nested-expense", "edit_expense", "{\"entry\":{\"projectId\":\"project\"}}"),
                ("invoice", "create_invoice", "{\"selection\":{\"scope\":{\"projectId\":\"project\"}}}"),
                ("revision", "revise_created_invoice", "{\"invoice\":{\"selection\":{\"scope\":{\"projectId\":\"project\"}}}}"),
                ("category", "manage_categories", "{\"action\":\"rename\",\"categoryId\":\"category\"}"),
                ("receipt-adjustments", "edit_transaction_receipt_lines", "{\"scope\":{\"projectId\":\"project\"}}"),
                ("transaction-edit", "edit_transaction_details", "{\"scope\":{\"projectId\":\"project\"}}"),
                ("other-receipt", "edit_transaction_receipt_lines", "{\"scope\":{\"projectId\":\"elsewhere\"}}")
            ] {
                _ = try await db.execute(sql: "INSERT INTO spike_local_operations(id,account_id,actor_principal_id,command_type,local_state,command_envelope_json) VALUES(?,'account','principal',?,'queued',?)",
                    parameters: [id,kind,"{\"payload\":\(payload)}"])
            }
            _ = try await db.execute(sql: "UPDATE spike_local_operations SET category_projection_json='[]' WHERE id='category'", parameters: nil)
            let nested = try await query.readImplementedSources(accountId: account, principalId: principal, projectId: project, currency: usd)
            #expect(Set(nested.localOperations.map(\.operationId.rawValue)) == ["pending","rejected","nested-expense","invoice","revision","category","receipt-adjustments","transaction-edit"])
            _ = try await db.execute(sql: "UPDATE spike_local_operations SET local_state='applied',contract_version='return-paid-items-v1',fingerprint='fingerprint' WHERE id='pending'", parameters: nil)
            _ = try await db.execute(sql: "INSERT INTO spike_operation_results(id,account_id,actor_principal_id,command_type,contract_version,command_fingerprint,envelope_sha256,phase) VALUES('pending','account','principal','return_paid_items','return-paid-items-v1','wrong','fingerprint','applied')", parameters: nil)
            let mismatch = try await query.readImplementedSources(accountId: account, principalId: principal, projectId: project, currency: usd)
            #expect(mismatch.localOperations.contains { $0.operationId.rawValue == "pending" })
            _ = try await db.execute(sql: "UPDATE spike_operation_results SET command_fingerprint='fingerprint' WHERE id='pending'", parameters: nil)
            let replicated = try await query.readImplementedSources(accountId: account, principalId: principal, projectId: project, currency: usd)
            #expect(!replicated.localOperations.contains { $0.operationId.rawValue == "pending" })
            #expect(replicated.segments == mixed)
            _ = try await db.execute(sql: "UPDATE spike_transactions SET origin='unsupported' WHERE id='direct'", parameters: nil)
            await #expect(throws: TransactionDetailSnapshot.Failure.invalidEvidence) {
                try await query.readImplementedSources(accountId: account, principalId: principal, projectId: project, currency: usd)
            }
            _ = try await db.execute(sql: "UPDATE spike_transactions SET origin='vendor_payment',category_id='missing' WHERE id='direct'", parameters: nil)
            await #expect(throws: PropertyManagementReportFailure.incompleteReadiness) {
                try await query.readImplementedSources(accountId: account, principalId: principal, projectId: project, currency: usd)
            }
            _ = try await db.execute(sql: "UPDATE spike_transactions SET category_id='category' WHERE id='direct'", parameters: nil)
            _ = try await db.execute(sql: "UPDATE ps_stream_subscriptions SET last_synced_at=NULL WHERE stream_name='transaction_receipts'", parameters: nil)
            await #expect(throws: PropertyManagementReportFailure.incompleteReadiness) {
                try await query.readImplementedSources(accountId: account, principalId: principal, projectId: project, currency: usd)
            }
            _ = try await db.execute(sql: "UPDATE ps_stream_subscriptions SET last_synced_at=1000000 WHERE stream_name='transaction_receipts'", parameters: nil)
            for stream in ["physical_account_items", "project_live_invoices", "project_expenses", "project_invoicing_item_charges", "transaction_receipts"] {
                _ = try await db.execute(sql: "UPDATE ps_stream_subscriptions SET last_synced_at=999999 WHERE stream_name=?", parameters: [stream])
                await #expect(throws: PropertyManagementReportFailure.incompleteReadiness) {
                    try await query.readImplementedSources(accountId: account, principalId: principal, projectId: project, currency: usd)
                }
                _ = try await db.execute(sql: "UPDATE ps_stream_subscriptions SET last_synced_at=1000000 WHERE stream_name=?", parameters: [stream])
            }
            await #expect(throws: ProjectInvoicingItemLocalReader.Failure.unavailable) {
                try await query.readImplementedSources(accountId: account, principalId: .init(validating: "other"), projectId: project, currency: usd)
            }
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET financial_access='none'", parameters: nil)
            await #expect(throws: ProjectInvoicingItemLocalReader.Failure.unavailable) {
                try await query.readImplementedSources(accountId: account, principalId: principal, projectId: project, currency: usd)
            }
        }
    }

    @Test("Budget watch exposes incomplete download then terminates on revoked access", .timeLimit(.minutes(1)))
    func budgetWatchRevocation() async throws {
        try await withDatabase { db in
            let updates = AsyncStream<Bool>.makeStream()
            let watch = Task {
                defer { updates.continuation.finish() }
                try await ProjectBudgetPowerSyncQuery(database: db).run(accountId: account,
                    principalId: principal, projectId: project, currency: .init(validating: "USD")) { read in
                        updates.continuation.yield(read == nil)
                        return true
                    }
            }
            defer { watch.cancel() }
            var changes = updates.stream.makeAsyncIterator()
            #expect(await changes.next() == true)
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed'", parameters: nil)
            await #expect(throws: ProjectInvoicingItemLocalReader.Failure.unavailable) { try await watch.value }
        }
    }

    @Test("Invoicing retains a charge after its physical placement ends and denies restricted access")
    func historicalInvoicingCharge() async throws {
        try await withDatabase { db in
            _ = try await db.execute(sql: "UPDATE spike_item_placements SET ended_at='2026-09-15' WHERE id='charged-placement'", parameters: nil)
            let rows = try await db.readTransaction { transaction in
                try ProjectInvoicingItemLocalReader.readCharges(transaction: transaction, accountId: account, principalId: principal, projectId: project)
            }
            #expect(rows.count == 1 && rows[0].occurrence.id.rawValue == "charge" && rows[0].amount.minorUnits == 100)
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
            _ = try await db.execute(sql: "INSERT INTO paid_item_return_credits(id,account_id,charge_id,paid_invoice_line_id,return_occurrence_id,inventory_placement_id,item_id) VALUES('charge','account','charge','line','return','inventory','charged')", parameters: nil)
            let credited = try await db.readTransaction { transaction in
                try ProjectInvoicingItemLocalReader.readCharges(transaction: transaction, accountId: account, principalId: principal, projectId: project)
            }
            let credit = try #require(credited.first { $0.occurrence.polarity == .credit })
            #expect(credited.count == 2 && credit.amount.minorUnits == -100)
            #expect(credit.occurrence.polarity == .credit && credit.availability == .available)
            #expect(credit.title == "Original client description" && credit.categoryName == nil)
            #expect(credit.categoryId?.rawValue == "category" && row.categoryId == credit.categoryId)
            #expect(credited.first { $0.occurrence.polarity == .charge } == row)
            let snapshot = try ProjectInvoicingItems(accountId: account, projectId: project, rows: credited)
            #expect(snapshot.rows.count == 2)
            let category = try BudgetCategoryDefinitionSnapshot(id: .init(validating: "category"),
                accountId: account, name: .init(validating: "Renamed category"), kind: .itemized,
                lifecycle: .active, isSystem: false, excludesFromOverallBudget: false, presentationOrder: 0, revision: 1)
            let budget = try #require(snapshot.budgetContributions(categories: [category], currency: .init(validating: "USD")).first)
            #expect(budget.clientPaid.minorUnits == 100 && budget.invoicingUnpaid.minorUnits == -100)
            #expect(budget.recognized.minorUnits == 0)
            _ = try await db.execute(sql: "UPDATE paid_item_return_credits SET paid_invoice_line_id='missing'", parameters: nil)
            await #expect(throws: PropertyManagementReportFailure.incompleteReadiness) {
                try await db.readTransaction { transaction in
                    try ProjectInvoicingItemLocalReader.readCharges(transaction: transaction, accountId: account, principalId: principal, projectId: project)
                }
            }
            _ = try await db.execute(sql: "UPDATE paid_item_return_credits SET paid_invoice_line_id='line'", parameters: nil)
            _ = try await db.execute(sql: "UPDATE collected_invoice_lines SET signed_amount_minor_units='101' WHERE id='line'", parameters: nil)
            await #expect(throws: PropertyManagementReportLocalReadFailure.malformedEvidence) {
                try await db.readTransaction { transaction in
                    try ProjectInvoicingItemLocalReader.readCharges(transaction: transaction, accountId: account, principalId: principal, projectId: project)
                }
            }
        }
    }

    @Test("Paid return acceptance atomically queues exact intent and refuses a second return")
    func paidReturnAdmission() async throws {
        try await withDatabase { db in
            for sql in [
                "UPDATE spike_clients SET created_at_ms=1,updated_at_ms=1",
                "UPDATE spike_projects SET created_at_ms=1,updated_at_ms=1",
                "UPDATE spike_item_placements SET started_at='2025-01-01',start_evidence='recorded_move' WHERE id='charged-placement'",
                "INSERT INTO spike_item_placements(id,account_id,item_id,scope_kind,started_at,ended_at) VALUES('prior','account','charged','business_inventory','2024-01-01','2025-01-01')",
                "INSERT INTO collected_invoices(id,account_id,project_id,client_id,sealed) VALUES('invoice','account','project','client',1)",
                "INSERT INTO collected_invoice_lines(id,account_id,invoice_id,source_kind,source_id,item_id,category_id,source_revision,signed_amount_minor_units,currency,description) VALUES('line','account','invoice','item','charge','charged','category',1,'100','USD','Original')",
                "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES('project_invoicing_item_charges',1,0,'{\"account_id\":\"account\",\"project_id\":\"project\"}',1000000)",
                "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES('item_return_review',1,0,'{\"account_id\":\"account\",\"project_id\":\"project\"}',1000000)"
            ] { _ = try await db.execute(sql: sql, parameters: nil) }
            func command() throws -> ReturnPaidItemsCommand {
                try .init(operationId: ReturnPaidItemsOperationIdentity.make(accountId: account, uuid: UUID()),
                    accountId: account, actorPrincipalId: principal, capturedAt: Date(timeIntervalSince1970: 1000),
                    payload: .init(projectId: project, items: [
                        .init(itemId: .init(validating: "charged"), placementId: .init(validating: "charged-placement"),
                            chargeId: .init(validating: "charge"), paidInvoiceLineId: .init(validating: "line"),
                            inventoryPlacementId: .init(validating: "next"), returnOccurrenceId: .init(validating: "return"),
                            creditId: .init(validating: "credit"))]))
            }
            enum Injected: Error { case rollback }
            let value = try command()
            let failing = ReturnPaidItemsPowerSyncStore(database: db, accountId: account, principalId: principal,
                accessFence: .init(), afterOperationWrite: { throw Injected.rollback })
            await #expect(throws: Injected.self) { try await failing.submit(value) }
            let count = try await db.get(sql: "SELECT count(*) AS n FROM spike_local_operations", parameters: nil) { try $0.getInt(name: "n") }
            #expect(count == 0)
            let store = ReturnPaidItemsPowerSyncStore(database: db, accountId: account, principalId: principal, accessFence: .init())
            // Imported observations and a discontinuous history are not proof
            // of an Inventory sale, even when a paid line exists.
            for (change, restore) in [
                ("UPDATE spike_item_placements SET start_evidence='import_observation' WHERE id='charged-placement'",
                 "UPDATE spike_item_placements SET start_evidence='recorded_move' WHERE id='charged-placement'"),
                ("UPDATE spike_item_placements SET ended_at='2024-12-31' WHERE id='prior'",
                 "UPDATE spike_item_placements SET ended_at='2025-01-01' WHERE id='prior'")
            ] {
                _ = try await db.execute(sql: change, parameters: nil)
                await #expect(throws: ReturnPaidItemsPowerSyncStore.Failure.unavailable) {
                    try await store.review(projectId: project, itemIds: [.init(validating: "charged")])
                }
                await #expect(throws: ReturnPaidItemsPowerSyncStore.Failure.unavailable) {
                    try await store.submit(value)
                }
                #expect(try await db.get(sql: "SELECT count(*) AS n FROM spike_local_operations", parameters: nil) {
                    try $0.getInt(name: "n")
                } == 0)
                _ = try await db.execute(sql: restore, parameters: nil)
            }
            let review = try await store.review(projectId: project, itemIds: [.init(validating: "charged")])
            #expect(review.items.count == 1 && review.items[0].paidAmount.minorUnits == 100)
            #expect(review.items[0].paidInvoiceLineId.rawValue == "line" && review.items[0].categoryId.rawValue == "category")
            let reviewedPayload = try review.makePayload()
            #expect(reviewedPayload.items[0].paidInvoiceLineId == value.envelope.payload.items[0].paidInvoiceLineId)
            await #expect(throws: (any Error).self) {
                try await store.review(projectId: project, itemIds: [.init(validating: "charged"), .init(validating: "unknown")])
            }
            for (name, params) in [
                ("physical_account_items", "{\"account_id\":\"account\"}"),
                ("project_live_invoices", "{\"account_id\":\"account\",\"project_id\":\"project\"}")
            ] {
                _ = try await db.execute(sql: "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES(?,1,0,?,1000000)", parameters: [name, params])
            }
            let availability = AsyncThrowingStream<Bool, Error>.makeStream()
            let observer = Task {
                do {
                    for try await snapshot in store.watchReview(projectId: project, itemIds: [try .init(validating: "charged")]) {
                        availability.continuation.yield(snapshot != nil)
                    }
                    availability.continuation.finish()
                } catch { availability.continuation.finish(throwing: error) }
            }
            let deadline = Task { try await Task.sleep(for: .seconds(10)); observer.cancel() }
            defer { deadline.cancel(); observer.cancel() }
            var availabilityIterator = availability.stream.makeAsyncIterator()
            #expect(try await availabilityIterator.next() == true)
            _ = try await db.execute(sql: "UPDATE spike_clients SET lifecycle='archived' WHERE id='client'", parameters: nil)
            var archivedObserved = false
            while let available = try await availabilityIterator.next() {
                if !available { archivedObserved = true; break }
            }
            #expect(archivedObserved)
            await store.cancelAndDrainWatches()
            await observer.value
            deadline.cancel()
            _ = try await db.execute(sql: "UPDATE spike_clients SET lifecycle='active' WHERE id='client'", parameters: nil)
            #expect(try await store.submit(value).localState == .queued)
            #expect(try await store.submit(value).localState == .queued)
            await #expect(throws: ReturnPaidItemsPowerSyncStore.Failure.alreadyAccepted) {
                try await store.submit(command())
            }
            let saved = try await db.get(sql: "SELECT count(*) AS n FROM spike_local_operations WHERE command_type='return_paid_items'", parameters: nil) { try $0.getInt(name: "n") }
            #expect(saved == 1)
            let ended = try await db.get(sql: "SELECT ended_at FROM spike_item_placements WHERE id='charged-placement'", parameters: nil) { try $0.getStringOptional(name: "ended_at") }
            #expect(ended == nil)
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
            await #expect(throws: PropertyManagementReportFailure.incompleteReadiness) {
                try await query.read(accountId: account, principalId: principal, projectId: project)
            }
            _ = try await db.execute(sql: "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES('project_live_invoices',1,0,'{\"account_id\":\"account\",\"project_id\":\"project\"}',1000000)", parameters: nil)
            #expect(try await query.read(accountId: account, principalId: principal, projectId: project).rows.count == 1)
            #expect(try await query.read(accountId: account, principalId: principal, projectId: project).rows.first?.availability == .available)
            _ = try await db.execute(sql: "INSERT INTO live_invoice_memberships(id,account_id,invoice_id,source_kind,source_id,position) VALUES('member','account','live','item','charge',0)", parameters: nil)
            await #expect(throws: PropertyManagementReportFailure.incompleteReadiness) {
                try await query.read(accountId: account, principalId: principal, projectId: project)
            }
            _ = try await db.execute(sql: "INSERT INTO live_invoices(id,account_id,project_id,status,name,revision) VALUES('live','account','project','created','INV-ITEM',1)", parameters: nil)
            let created = try #require(try await query.read(accountId: account, principalId: principal, projectId: project).rows.first)
            #expect(created.availability == .created && created.invoiceName == "INV-ITEM")
            #expect(created.occurrence.phase.invoiceId?.rawValue == "live")
            #expect(created.occurrence.id.rawValue == "charge" && created.occurrence.itemId.rawValue == "charged")
            _ = try await db.execute(sql: "UPDATE live_invoices SET status='sent' WHERE id='live'", parameters: nil)
            #expect(try await query.read(accountId: account, principalId: principal, projectId: project).rows.first?.availability == .sent)
            _ = try await db.execute(sql: "INSERT INTO live_invoice_memberships(id,account_id,invoice_id,source_kind,source_id,position) VALUES('duplicate','account','live','item','charge',1)", parameters: nil)
            await #expect(throws: ProjectInvoicingItemsFailure.duplicateOccurrence) {
                try await query.read(accountId: account, principalId: principal, projectId: project)
            }
            _ = try await db.execute(sql: "DELETE FROM live_invoice_memberships", parameters: nil)
            #expect(try await query.read(accountId: account, principalId: principal, projectId: project).rows.first?.availability == .available)
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

    @Test("Budget and pending intent survive encrypted offline database reopen", .timeLimit(.minutes(1)))
    func budgetRestart() async throws {
        let usd = try CurrencyCode(validating: "USD")
        func verify(_ db: any PowerSyncDatabaseProtocol) async throws {
            let value = try await ProjectBudgetPowerSyncQuery(database: db).readImplementedSources(
                accountId: account, principalId: principal, projectId: project, currency: usd)
            #expect(value.overallRecognized.minorUnits == 100)
            #expect(value.overallBudget.minorUnits == 1000)
            #expect(value.localOperations.map(\.operationId.rawValue) == ["pending-return"])
            #expect(value.localOperations.map(\.localState) == [.queued])
            #expect(!value.isCompleteForProjectBudget)
        }
        try await withDatabase({ db in
            for sql in [
                "UPDATE spike_clients SET created_at_ms=1,updated_at_ms=1",
                "UPDATE spike_projects SET created_at_ms=1,updated_at_ms=1",
                "INSERT INTO spike_budget_categories(id,account_id,display_name,kind,lifecycle,is_system,excludes_from_overall_budget,presentation_order,revision) VALUES('category','account','Furnishings','itemized','active',0,0,0,1)",
                "INSERT INTO spike_project_category_allocations(id,account_id,project_id,category_id,allocation_minor_units,allocation_currency) VALUES('allocation','account','project','category',1000,'USD')",
                "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,last_synced_at) VALUES('spike_projects',1,1,1000000)",
                "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES('physical_account_items',1,0,'{\"account_id\":\"account\"}',1000000)",
                "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES('transaction_receipts',1,0,'{\"account_id\":\"account\",\"project_id\":\"project\",\"scope_kind\":\"project\"}',1000000)",
                "INSERT INTO spike_local_operations(id,account_id,actor_principal_id,command_type,local_state,command_envelope_json) VALUES('pending-return','account','principal','return_paid_items','queued','{\"payload\":{\"projectId\":\"project\"}}')"
            ] { _ = try await db.execute(sql: sql, parameters: nil) }
            for name in ["project_live_invoices", "project_expenses", "project_invoicing_item_charges"] {
                _ = try await db.execute(sql: "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES(?,1,0,'{\"account_id\":\"account\",\"project_id\":\"project\"}',1000000)", parameters: [name])
            }
            try await verify(db)
        }, afterReopen: { db in
            try await verify(db)
        })
    }

    private func withDatabase(_ body: (any PowerSyncDatabaseProtocol) async throws -> Void,
        afterReopen: ((any PowerSyncDatabaseProtocol) async throws -> Void)? = nil) async throws {
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
        if let afterReopen {
            let reopened = try LedgerPowerSyncDatabaseFactory.open(absolutePath: root.appendingPathComponent("ledger.sqlite").path,
                encryptionKey: LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "5a", count: 32)))
            do {
                try await afterReopen(reopened)
                try await reopened.close()
            } catch { try? await reopened.close(); throw error }
        }
    }
}
