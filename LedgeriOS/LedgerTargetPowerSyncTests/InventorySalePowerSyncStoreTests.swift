import Foundation
import LedgerTargetCore
import PowerSync
import Testing
@testable import LedgerTargetPowerSync

@Suite("Inventory sale durable queue", .serialized)
struct InventorySalePowerSyncStoreTests {
    private let account = try! AccountID(validating: "sale-account")
    private let principal = try! PrincipalID(validating: "sale-member")
    private struct InjectedFailure: Error {}

    @Test func uninvoicedReturnRequiresMatchingInventoryOrigin() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seedReturn(db)
        do {
            let store = returnStore(db), command = try returnCommand()
            _ = try await db.execute(sql: "UPDATE spike_item_placements SET ended_at='2024-12-31T00:00:00Z' WHERE id='inventory-origin'", parameters: nil)
            await #expect(throws: ReturnUninvoicedItemsPowerSyncStore.Failure.unavailable) { try await store.submit(command) }
            await #expect(throws: ReturnUninvoicedItemsPowerSyncStore.Failure.unavailable) {
                try await store.review(projectId: command.envelope.payload.projectId, itemIds: [.init(validating: "item")])
            }
            _ = try await db.execute(sql: "UPDATE spike_item_placements SET ended_at='2025-01-01T00:00:00Z' WHERE id='inventory-origin'", parameters: nil)
            _ = try await db.execute(sql: "UPDATE spike_item_placements SET start_evidence='unknown' WHERE id='old'", parameters: nil)
            await #expect(throws: ReturnUninvoicedItemsPowerSyncStore.Failure.unavailable) { try await store.submit(command) }
            #expect(try await db.get("SELECT count(*) FROM spike_local_operations") { try $0.getInt(index: 0) } == 0)
            try await db.close()
        } catch { try? await db.close(); throw error }
    }

    @Test(.timeLimit(.minutes(1))) func uninvoicedReturnReviewWatchWithdrawsInvoicedSelection() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seedReturn(db)
        let store = returnStore(db)
        var updates = store.watchReview(projectId: try .init(validating: "destination"),
            itemIds: [try .init(validating: "item")]).makeAsyncIterator()
        #expect(try await updates.next()??.items.count == 1)
        _ = try await db.execute(sql: "INSERT INTO return_live_memberships(id,account_id,source_id) VALUES('charge',?,'charge')", parameters: [account.rawValue])
        var withdrawn = false
        while let next = try await updates.next() {
            if next == nil { withdrawn = true; break }
        }
        #expect(withdrawn)
        await store.cancelAndDrainWatches()
        #expect(try await updates.next() == nil)
        try await db.close()
    }

    @Test func uninvoicedReturnReviewBindsSelectionWithoutMoneyOrNewItemIdentity() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seedReturn(db)
        do {
            let store = returnStore(db), project = try ProjectID(validating: "destination")
            let review = try await store.review(projectId: project, itemIds: [.init(validating: "item")])
            #expect(review.accountId == account && review.principalId == principal)
            let payload = try review.makePayload()
            #expect(payload.items[0].itemId.rawValue == "item")
            #expect(payload.items[0].chargeId.rawValue == "charge")
            #expect(payload.items[0].placementId.rawValue == "old")
            #expect(payload.items[0].inventoryPlacementId != payload.items[0].placementId)
            let command = try ReturnUninvoicedItemsCommand(
                operationId: ReturnUninvoicedItemsOperationIdentity.make(accountId: account, uuid: UUID()),
                accountId: account, actorPrincipalId: principal, capturedAt: Date(), payload: payload)
            _ = try await db.execute(sql: "UPDATE return_charge_sources SET revision='2'", parameters: nil)
            await #expect(throws: ReturnUninvoicedItemsPowerSyncStore.Failure.unavailable) { try await store.submit(command) }
            await #expect(throws: ReturnUninvoicedItemsPowerSyncStore.Failure.unavailable) {
                try await store.review(projectId: project, itemIds: [.init(validating: "item"),.init(validating: "missing")])
            }
            #expect(try await db.get("SELECT count(*) FROM spike_local_operations") { try $0.getInt(index: 0) } == 0)
            try await db.close()
        } catch { try? await db.close(); throw error }
    }

    @Test func uninvoicedReturnRequiresCompleteAuthorizedNonfinancialReview() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seedReturn(db)
        do {
            #expect(try await db.get("SELECT count(*) FROM item_charge_occurrences") { try $0.getInt(index: 0) } == 0)
            _ = try await db.execute(sql: "UPDATE ps_stream_subscriptions SET last_synced_at=NULL WHERE stream_name='item_return_review'", parameters: nil)
            await #expect(throws: PropertyManagementReportFailure.incompleteReadiness) {
                try await returnStore(db).submit(returnCommand())
            }
            _ = try await db.execute(sql: "UPDATE ps_stream_subscriptions SET last_synced_at=1000000 WHERE stream_name='item_return_review'", parameters: nil)
            _ = try await db.execute(sql: "UPDATE spike_budget_categories SET visibility_class='company_financial'", parameters: nil)
            await #expect(throws: ReturnUninvoicedItemsPowerSyncStore.Failure.unavailable) {
                try await returnStore(db).submit(returnCommand())
            }
            _ = try await db.execute(sql: "UPDATE spike_budget_categories SET visibility_class='ordinary'", parameters: nil)
            _ = try await db.execute(sql: "INSERT INTO return_paid_memberships(id,account_id,source_id) VALUES('charge',?,'charge')", parameters: [account.rawValue])
            await #expect(throws: ReturnUninvoicedItemsPowerSyncStore.Failure.unavailable) {
                try await returnStore(db).submit(returnCommand())
            }
            _ = try await db.execute(sql: "DELETE FROM return_paid_memberships", parameters: nil)
            #expect(try await returnStore(db).submit(returnCommand()).localState == .queued)
            try await db.close()
        } catch { try? await db.close(); throw error }
    }

    @Test(.timeLimit(.minutes(1))) func uninvoicedReturnWatchFollowsReceiptAndStopsOnRemoval() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seedReturn(db)
        let store = returnStore(db), command = try returnCommand()
        _ = try await store.submit(command)
        var updates = store.watch(command.envelope.operationId).makeAsyncIterator()
        #expect(try await updates.next()??.state.phase == .queued)
        try await returnConnector(ReturnApplier()).uploadData(database: db)
        var applied = false
        while let update = try await updates.next() {
            if update?.state.phase == .applied { applied = true; break }
        }
        #expect(applied)
        _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed'", parameters: nil)
        await #expect(throws: (any Error).self) { while let _ = try await updates.next() {} }
        await store.cancelAndDrainWatches()
        try await db.close()
    }

    @Test(.timeLimit(.minutes(1))) func uninvoicedReturnWatchDrainsBeforeClosingDatabase() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seedReturn(db)
        let store = returnStore(db), command = try returnCommand()
        var updates = store.watch(command.envelope.operationId).makeAsyncIterator()
        let initial = try await updates.next()
        #expect(initial != nil && initial! == nil)
        await store.cancelAndDrainWatches()
        #expect(try await updates.next() == nil)
        try await db.close()
    }

    @Test func uninvoicedReturnCountsAsPendingWorkAcrossRestartAndRejection() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seedReturn(db)
        let command = try returnCommand(); _ = try await returnStore(db).submit(command)
        #expect(try await pending(db).summary().queuedOperationCount == 1)
        try await db.close()
        let reopened = try fixture.open()
        #expect(try await pending(reopened).summary().queuedOperationCount == 1)
        try await returnConnector(ReturnApplier(rejected: true)).uploadData(database: reopened)
        #expect(try await returnStore(reopened).status(command.envelope.operationId)?.state.phase == .rejected)
        let summary = try await pending(reopened).summary()
        #expect(summary.queuedOperationCount == 0)
        #expect(summary.unresolvedRejectedOperationCount == 1)
        try await reopened.close()
    }

    @Test(arguments: [false, true]) func uninvoicedReturnUploadRetainsTerminalReceipt(rejected: Bool) async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seedReturn(db)
        let command = try returnCommand(); _ = try await returnStore(db).submit(command)
        try await returnConnector(ReturnApplier(rejected: rejected)).uploadData(database: db)
        #expect(try await db.getNextCrudTransaction() == nil)
        #expect(try await returnStore(db).submit(command).localState == (rejected ? .rejected : .applied))
        try await db.close()
        let reopened = try fixture.open()
        #expect(try await returnStore(reopened).submit(command).localState == (rejected ? .rejected : .applied))
        #expect(try await reopened.getNextCrudTransaction() == nil)
        try await reopened.close()
    }

    @Test func uninvoicedReturnInterruptedUploadRetriesAfterRestart() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seedReturn(db)
        let command = try returnCommand(); _ = try await returnStore(db).submit(command)
        await #expect(throws: InjectedFailure.self) {
            try await returnConnector(ReturnApplier(fails: true)).uploadData(database: db)
        }
        await #expect(throws: ReturnUninvoicedItemsServerResult.Failure.receiptMismatch) {
            try await returnConnector(ReturnApplier(wrongHash: true)).uploadData(database: db)
        }
        #expect(try await db.getNextCrudTransaction() != nil)
        #expect(try await returnStore(db).submit(command).localState == .applying)
        try await db.close()
        let reopened = try fixture.open()
        try await returnConnector(ReturnApplier()).uploadData(database: reopened)
        #expect(try await returnStore(reopened).submit(command).localState == .applied)
        #expect(try await reopened.getNextCrudTransaction() == nil)
        try await reopened.close()
    }

    @Test func uninvoicedReturnRemovalDuringUploadRetainsIntent() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seedReturn(db)
        _ = try await returnStore(db).submit(returnCommand())
        let fence = LedgerWorkspaceAccessFence()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            try await returnConnector(ReturnApplier(removes: fence), fence: fence).uploadData(database: db)
        }
        #expect(try await db.getNextCrudTransaction() != nil)
        #expect(try await db.get("SELECT local_state FROM spike_local_operations") { try $0.getString(index: 0) } == "applying")
        try await db.close()
    }

    private func returnConnector(_ applier: ReturnApplier, fence: LedgerWorkspaceAccessFence = .init()) -> LedgerPowerSyncUploadConnector {
        .init(accessFence: fence, credentialProvider: { nil }, clientCreationApplier: UnusedClientApplier(), uninvoicedReturnApplier: applier)
    }
    private struct ReturnApplier: ReturnUninvoicedItemsCommandApplying {
        var rejected = false
        var fails = false
        var wrongHash = false
        var removes: LedgerWorkspaceAccessFence?
        func apply(_ command: ReturnUninvoicedItemsCommand) async throws -> ReturnUninvoicedItemsServerResult {
            if fails { throw InjectedFailure() }
            removes?.markRemoved()
            let e = command.envelope, wire = try ReturnUninvoicedItemsUploadRequest(command)
            var values: [String: Any] = ["operation_id":e.operationId.rawValue,"account_id":e.accountId.rawValue,
                "actor_principal_id":e.actorPrincipalId.rawValue,"subject_id":e.payload.projectId.rawValue,
                "command_type":"return_uninvoiced_items","contract_version":"return-uninvoiced-items-v1",
                "command_fingerprint":wrongHash ? "wrong" : wire.fingerprint,"envelope_sha256":wire.fingerprint,
                "phase":rejected ? "rejected" : "applied","client_created_at_ms":1000000,
                "server_received_at_ms":2000000,"completed_at_ms":2000001]
            if rejected { values["error_code"] = "return_charge_invoiced" }
            else { values["result_code"] = "uninvoiced_items_returned" }
            return try JSONDecoder().decode(ReturnUninvoicedItemsServerResult.self,
                from: JSONSerialization.data(withJSONObject: values))
        }
    }

    @Test func uninvoicedReturnSurvivesRestartAndReservesExactPlacement() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seedReturn(db)
        let command = try returnCommand()
        #expect(try await returnStore(db).submit(command).localState == .queued)
        #expect(try await db.get("SELECT scope_kind FROM spike_item_placements WHERE id='old'") { try $0.getString(index: 0) } == "project")
        try await db.close()
        let reopened = try fixture.open()
        do {
            #expect(try await returnStore(reopened).submit(command).localState == .queued)
            await #expect(throws: ReturnUninvoicedItemsPowerSyncStore.Failure.alreadyAccepted) {
                try await returnStore(reopened).submit(returnCommand())
            }
            #expect(try await reopened.get("SELECT count(*) FROM spike_local_operations") { try $0.getInt(index: 0) } == 1)
            let crud = try #require(try await reopened.getNextCrudTransaction())
            #expect(crud.crud.count == 1)
            #expect(crud.crud.first?.table == LedgerPowerSyncTable.uninvoicedReturnCommands)
            _ = try await reopened.execute(sql: "UPDATE spike_account_memberships SET state='removed'", parameters: nil)
            await #expect(throws: (any Error).self) { try await returnStore(reopened).submit(command) }
            #expect(try await reopened.get("SELECT count(*) FROM spike_local_operations") { try $0.getInt(index: 0) } == 1)
            try await reopened.close()
        } catch { try? await reopened.close(); throw error }
    }

    @Test func uninvoicedReturnAcceptanceIsAtomicAndRejectsInvoicedSource() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seedReturn(db)
        do {
            let failing = ReturnUninvoicedItemsPowerSyncStore(database: db, accountId: account,
                principalId: principal, accessFence: .init(), afterOperationWrite: { throw InjectedFailure() })
            await #expect(throws: InjectedFailure.self) { try await failing.submit(returnCommand()) }
            #expect(try await db.get("SELECT count(*) FROM spike_local_operations") { try $0.getInt(index: 0) } == 0)
            #expect(try await db.getNextCrudTransaction() == nil)
            _ = try await db.execute(sql: "INSERT INTO return_live_memberships(id,account_id,source_id) VALUES('charge',?,'charge')",
                parameters: [account.rawValue])
            await #expect(throws: ReturnUninvoicedItemsPowerSyncStore.Failure.unavailable) {
                try await returnStore(db).submit(returnCommand())
            }
            #expect(try await db.get("SELECT count(*) FROM spike_local_operations") { try $0.getInt(index: 0) } == 0)
            try await db.close()
        } catch { try? await db.close(); throw error }
    }

    private func returnStore(_ db: any PowerSyncDatabaseProtocol) -> ReturnUninvoicedItemsPowerSyncStore {
        .init(database: db, accountId: account, principalId: principal, accessFence: .init())
    }
    private func returnCommand() throws -> ReturnUninvoicedItemsCommand {
        try .init(operationId: ReturnUninvoicedItemsOperationIdentity.make(accountId: account, uuid: UUID()),
            accountId: account, actorPrincipalId: principal, capturedAt: Date(timeIntervalSince1970: 1000),
            payload: .init(projectId: .init(validating: "destination"), items: [
                .init(itemId: .init(validating: "item"), placementId: .init(validating: "old"),
                    chargeId: .init(validating: "charge"), expectedChargeRevision: 1,
                    inventoryPlacementId: .init(validating: "returned"), returnOccurrenceId: .init(validating: "return"))]))
    }
    private func seedReturn(_ db: any PowerSyncDatabaseProtocol) async throws {
        try await seed(db)
        _ = try await db.execute(sql: "UPDATE spike_item_placements SET scope_kind='project',project_id='destination',start_evidence='recorded_move',started_at='2025-01-01T00:00:00Z' WHERE id='old'", parameters: nil)
        _ = try await db.execute(sql: "INSERT INTO spike_item_placements(id,account_id,item_id,scope_kind,ended_at) VALUES('inventory-origin',?,'item','business_inventory','2025-01-01T00:00:00Z')", parameters: [account.rawValue])
        _ = try await db.execute(sql: "INSERT INTO spike_budget_categories(id,account_id,display_name,kind,visibility_class) VALUES('category',?,'Furnishings','itemized','ordinary')", parameters: [account.rawValue])
        _ = try await db.execute(sql: "INSERT INTO return_charge_sources(id,account_id,project_id,item_id,placement_id,category_id,revision) VALUES('charge',?,'destination','item','old','category','1')", parameters: [account.rawValue])
        _ = try await db.execute(sql: "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES('item_return_review',1,0,?,1000000)",
            parameters: [#"{"account_id":"sale-account","project_id":"destination"}"#])
        while let pending = try await db.getNextCrudTransaction() { try await pending.complete() }
    }

    @Test func paidExpenseReadsFrozenContentsAndSurvivesRestart() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open()
        do {
            try await seed(db)
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET financial_access='full'", parameters: nil)
            _ = try await db.execute(sql: "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES('project_expenses',1,0,?,1000000)",
                parameters: [#"{"account_id":"sale-account","project_id":"destination"}"#])
            _ = try await db.execute(sql: "INSERT INTO expenses(id,account_id,project_id,category_id,vendor,expense_date,final_amount_minor_units,currency,notes,revision) VALUES('expense','sale-account','destination','general','Current vendor','2024-02-29','9223372036854775807','USD','Notes','1')", parameters: nil)
            let project = try ProjectID(validating: "destination")
            let query = ProjectExpensePowerSyncQuery(database: db)
            #expect(try await query.read(accountId: account, principalId: principal, projectId: project).expenses[0].collectedInvoice == nil)
            _ = try await db.execute(sql: "INSERT INTO collected_invoices(id,account_id,project_id,client_id,sealed,purchase_id,invoice_revision,currency,total_minor_units) VALUES('invoice','sale-account','destination','client',1,'payment','1','USD','9223372036854775807')", parameters: nil)
            _ = try await db.execute(sql: """
                INSERT INTO collected_invoice_lines(id,account_id,invoice_id,line_position,source_kind,source_id,source_revision,category_id,signed_amount_minor_units,currency,description,source_snapshot_json)
                VALUES('line','sale-account','invoice',0,'expense','expense','1','historical-category','9223372036854775807','USD','Historical description','{"expense":{"expenseId":"expense"}}')
                """, parameters: nil)
            let paid = try await query.read(accountId: account, principalId: principal, projectId: project)
            #expect(paid.expenses[0].collectedInvoice?.purchaseId.rawValue == "payment")
            #expect(paid.expenses[0].collectedInvoice?.total.minorUnits == Int64.max)
            #expect(paid.expenses[0].collectedInvoice?.lines[0].description == "Historical description")
            let collected = try await query.readCollectedInvoices(accountId: account, principalId: principal, projectId: project)
            #expect(collected == paid.expenses.compactMap(\.collectedInvoice))
            let report = try await query.readCollectedInvoiceReport(accountId: account, principalId: principal,
                projectId: project, invoiceId: .init(validating: "invoice"), asOf: .init(validating: 2000))
            #expect(report.invoice == collected.first)
            #expect(report.provenance.lastSyncedAt?.rawValue == 1000)
            #expect(report.provenance.localDataVersion != nil)
            // A completed background sync is not a content change. Offline
            // reports do not expire merely because their read time advances.
            _ = try await db.execute(sql: "UPDATE ps_stream_subscriptions SET last_synced_at=3000000", parameters: nil)
            let refreshed = try await query.readCollectedInvoiceReport(accountId: account, principalId: principal,
                projectId: project, invoiceId: .init(validating: "invoice"), asOf: .init(validating: 31536000000))
            #expect(refreshed.invoice == report.invoice)
            #expect(refreshed.provenance.localDataVersion == report.provenance.localDataVersion)
            #expect(refreshed.provenance.visibilityScopeID == report.provenance.visibilityScopeID)
            #expect(refreshed.provenance.lastSyncedAt?.rawValue == 3000)
            // Simulate changed downloaded evidence, not an authorized edit to
            // paid accounting: even non-monetary content must invalidate export.
            _ = try await db.execute(sql: "UPDATE collected_invoice_lines SET description='Changed downloaded evidence'", parameters: nil)
            let changed = try await query.readCollectedInvoiceReport(accountId: account, principalId: principal,
                projectId: project, invoiceId: .init(validating: "invoice"), asOf: .init(validating: 31536000000))
            #expect(changed.provenance.localDataVersion != report.provenance.localDataVersion)
            #expect(changed.invoice.total == report.invoice.total)
            _ = try await db.execute(sql: "UPDATE collected_invoice_lines SET description='Historical description'", parameters: nil)
            _ = try await db.execute(sql: "UPDATE ps_stream_subscriptions SET last_synced_at=1000000", parameters: nil)
            _ = try await db.execute(sql: "UPDATE collected_invoice_lines SET source_revision='2'", parameters: nil)
            await #expect(throws: ProjectExpenses.Failure.invalidEvidence) {
                try await query.read(accountId: account, principalId: principal, projectId: project)
            }
            _ = try await db.execute(sql: "UPDATE collected_invoice_lines SET source_revision='1'", parameters: nil)
            try await db.close()
            let reopened = try fixture.open()
            do {
                let reader = ProjectExpensePowerSyncQuery(database: reopened)
                #expect(try await reader.read(accountId: account, principalId: principal, projectId: project) == paid)
                #expect(try await reader.readCollectedInvoices(accountId: account, principalId: principal, projectId: project) == collected)
                #expect(try await reader.readCollectedInvoiceReport(accountId: account, principalId: principal,
                    projectId: project, invoiceId: .init(validating: "invoice"), asOf: .init(validating: 2000)) == report)
                let invoice = try #require(collected.first)
                let exportReader = CollectedInvoiceReportDeliveryTests.Reader(invoices: nil, reportRead: { asOf in
                    try await reader.readCollectedInvoiceReport(accountId: account, principalId: principal,
                        projectId: project, invoiceId: invoice.invoiceId, asOf: asOf)
                })
                let renderedBytes = Data("%PDF-offline-delivery-boundary".utf8)
                // No connector is started after reopen. This exercises delivery
                // authorization against persisted local data, not a canned read.
                try await CollectedInvoiceReportDelivery.deliver(data: renderedBytes, invoice: invoice,
                    reader: exportReader) { url in
                        let handedOffBytes = try Data(contentsOf: url)
                        #expect(handedOffBytes == renderedBytes)
                    }
                // Persisted Invoice rows alone do not establish a complete
                // download. Revalidation must also require its sync checkpoint.
                _ = try await reopened.execute(sql: "UPDATE ps_stream_subscriptions SET last_synced_at=NULL WHERE stream_name='project_expenses'", parameters: nil)
                await #expect(throws: PropertyManagementReportFailure.incompleteReadiness) {
                    try await CollectedInvoiceReportDelivery.deliver(data: renderedBytes, invoice: invoice,
                        reader: exportReader) { _ in Issue.record("Export without a completed Invoice download") }
                }
                _ = try await reopened.execute(sql: "UPDATE ps_stream_subscriptions SET last_synced_at=1000000 WHERE stream_name='project_expenses'", parameters: nil)
                _ = try await reopened.execute(sql: "UPDATE spike_account_memberships SET financial_access='none'", parameters: nil)
                await #expect(throws: ProjectInvoicingItemLocalReader.Failure.unavailable) {
                    try await reader.readCollectedInvoiceReport(accountId: account, principalId: principal,
                        projectId: project, invoiceId: .init(validating: "invoice"), asOf: .init(validating: 2000))
                }
                await #expect(throws: ProjectInvoicingItemLocalReader.Failure.unavailable) {
                    try await CollectedInvoiceReportDelivery.deliver(data: renderedBytes, invoice: invoice,
                        reader: exportReader) { _ in Issue.record("Export after financial access withdrawal") }
                }
                await #expect(throws: ProjectInvoicingItemLocalReader.Failure.unavailable) {
                    try await reader.read(accountId: account, principalId: principal, projectId: project)
                }
                await #expect(throws: ProjectInvoicingItemLocalReader.Failure.unavailable) {
                    try await reader.readCollectedInvoices(accountId: account, principalId: principal, projectId: project)
                }
                try await reopened.close()
            } catch { try? await reopened.close(); throw error }
        } catch { try? await db.close(); throw error }
    }

    @Test func collectedInvoiceBrowseIncludesNonExpenseSourcesAndRejectsIncompleteContents() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open()
        do {
            try await seed(db)
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET financial_access='full'", parameters: nil)
            let project = try ProjectID(validating: "destination"), query = ProjectExpensePowerSyncQuery(database: db)
            await #expect(throws: PropertyManagementReportFailure.incompleteReadiness) {
                try await query.readCollectedInvoices(accountId: account, principalId: principal, projectId: project)
            }
            _ = try await db.execute(sql: "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES('project_expenses',1,0,?,1000000)",
                parameters: [#"{"account_id":"sale-account","project_id":"destination"}"#])
            #expect(try await query.readCollectedInvoices(accountId: account, principalId: principal, projectId: project).isEmpty)
            _ = try await db.execute(sql: "INSERT INTO collected_invoices(id,account_id,project_id,client_id,sealed,purchase_id,invoice_revision,currency,total_minor_units) VALUES('fee-invoice','sale-account','destination','client',1,'fee-payment',1,'USD','99')", parameters: nil)
            _ = try await db.execute(sql: """
                INSERT INTO collected_invoice_lines(id,account_id,invoice_id,line_position,source_kind,source_id,source_revision,category_id,signed_amount_minor_units,currency,description,source_snapshot_json)
                VALUES('fee-line','sale-account','fee-invoice',0,'fee_installment','fee',1,'fee-category','99','USD','Historical fee','{"feeInstallment":{"installmentId":"fee"}}')
                """, parameters: nil)
            let invoices = try await query.readCollectedInvoices(accountId: account, principalId: principal, projectId: project)
            #expect(invoices.count == 1)
            #expect(invoices.first?.lines.first?.source == .feeInstallment(installmentId: try .init(validating: "fee")))
            // A selected report needs its own complete frozen contents, not
            // successfully decoded contents for every other Project Invoice.
            _ = try await db.execute(sql: "INSERT INTO collected_invoices(id,account_id,project_id,client_id,sealed,purchase_id,invoice_revision,currency,total_minor_units) VALUES('incomplete-invoice','sale-account','destination','client',1,'other-payment',1,'USD','42')", parameters: nil)
            let report = try await query.readCollectedInvoiceReport(accountId: account, principalId: principal,
                projectId: project, invoiceId: .init(validating: "fee-invoice"), asOf: .init(validating: 2000))
            #expect(report.invoice == invoices[0])
            #expect(try await query.readCollectedInvoices(accountId: account, principalId: principal,
                projectId: project, invoiceId: .init(validating: "fee-invoice")) == invoices)
            await #expect(throws: (any Error).self) {
                try await query.readCollectedInvoices(accountId: account, principalId: principal, projectId: project)
            }
            await #expect(throws: (any Error).self) {
                try await query.readCollectedInvoiceReport(accountId: account, principalId: principal,
                    projectId: project, invoiceId: .init(validating: "incomplete-invoice"), asOf: .init(validating: 2000))
            }
            await #expect(throws: ProjectInvoicingItemLocalReader.Failure.unavailable) {
                try await query.readCollectedInvoiceReport(accountId: account, principalId: principal,
                    projectId: .init(validating: "another-project"), invoiceId: .init(validating: "fee-invoice"),
                    asOf: .init(validating: 2000))
            }
            _ = try await db.execute(sql: "DELETE FROM collected_invoices WHERE id='incomplete-invoice'", parameters: nil)
            _ = try await db.execute(sql: "UPDATE collected_invoice_lines SET signed_amount_minor_units='98'", parameters: nil)
            await #expect(throws: (any Error).self) {
                try await query.readCollectedInvoiceReport(accountId: account, principalId: principal,
                    projectId: project, invoiceId: .init(validating: "fee-invoice"), asOf: .init(validating: 2000))
            }
            await #expect(throws: (any Error).self) {
                try await query.readCollectedInvoices(accountId: account, principalId: principal, projectId: project)
            }
            try await db.close()
        } catch { try? await db.close(); throw error }
    }

    @Test(.timeLimit(.minutes(1))) func expenseWatchInvalidatesForInvoiceMembershipAndStatus() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open()
        do {
            try await seed(db)
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET financial_access='full'", parameters: nil)
            let emissions = AsyncStream<String>.makeStream()
            let watcher = Task {
                defer { emissions.continuation.finish() }
                try await ProjectExpensePowerSyncQuery(database: db).run(accountId: account,
                    principalId: principal, projectId: .init(validating: "destination")) { _ in
                    do {
                        let evidence = try await db.get(sql: "SELECT (SELECT count(*) FROM live_invoice_memberships),COALESCE((SELECT status FROM live_invoices LIMIT 1),'none')", parameters: nil) {
                            try "\($0.getInt(index: 0)):\($0.getString(index: 1))"
                        }
                        emissions.continuation.yield(evidence)
                        return true
                    } catch { return false }
                }
            }
            var iterator = emissions.stream.makeAsyncIterator()
            #expect(await iterator.next() == "0:none")
            _ = try await db.execute(sql: "INSERT INTO live_invoices(id,account_id,project_id,status) VALUES('watch-invoice','sale-account','destination','created')", parameters: nil)
            var observed: String?
            repeat { observed = await iterator.next() } while observed != nil && observed != "0:created"
            #expect(observed == "0:created")
            _ = try await db.execute(sql: "INSERT INTO live_invoice_memberships(id,account_id,invoice_id) VALUES('watch-member','sale-account','watch-invoice')", parameters: nil)
            repeat { observed = await iterator.next() } while observed != nil && observed != "1:created"
            #expect(observed == "1:created")
            _ = try await db.execute(sql: "UPDATE live_invoices SET status='sent' WHERE id='watch-invoice'", parameters: nil)
            repeat { observed = await iterator.next() } while observed != nil && observed != "1:sent"
            #expect(observed == "1:sent")
            watcher.cancel()
            _ = await watcher.result
            try await db.close()
        } catch { try? await db.close(); throw error }
    }

    @Test func expenseStatusUsesCompletedLiveMembershipAcrossReopen() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open()
        do {
            try await seed(db)
            for sql in [
                "UPDATE spike_account_memberships SET financial_access='full'",
                "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES('project_expenses',1,0,'{\"account_id\":\"sale-account\",\"project_id\":\"destination\"}',1000000)",
                "INSERT INTO expenses(id,account_id,project_id,category_id,vendor,expense_date,final_amount_minor_units,currency,notes,revision) VALUES('status-expense','sale-account','destination','general','Vendor','2024-02-29','100','USD','','1')"
            ] { _ = try await db.execute(sql: sql, parameters: nil) }
            let project = try ProjectID(validating: "destination")
            let query = ProjectExpensePowerSyncQuery(database: db)
            #expect(try await query.read(accountId: account, principalId: principal, projectId: project).expenses.first?.availability == nil)
            _ = try await db.execute(sql: "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES('project_live_invoices',1,0,'{\"account_id\":\"sale-account\",\"project_id\":\"destination\"}',1000000)", parameters: nil)
            #expect(try await query.read(accountId: account, principalId: principal, projectId: project).expenses.first?.availability == .available)
            _ = try await db.execute(sql: "INSERT INTO live_invoices(id,account_id,project_id,revision,status,name,notes) VALUES('status-invoice','sale-account','destination','1','created','INV-STATUS','')", parameters: nil)
            _ = try await db.execute(sql: "INSERT INTO live_invoice_memberships(id,account_id,invoice_id,source_kind,source_id,position) VALUES('status-member','sale-account','status-invoice','expense','status-expense',0)", parameters: nil)
            #expect(try await query.read(accountId: account, principalId: principal, projectId: project).expenses.first?.availability == .created)
            _ = try await db.execute(sql: "UPDATE live_invoices SET status='sent' WHERE id='status-invoice'", parameters: nil)
            try await db.close()
            let reopened = try fixture.open()
            do {
                let rows = try await ProjectExpensePowerSyncQuery(database: reopened).read(accountId: account, principalId: principal, projectId: project)
                #expect(rows.expenses.first?.availability == .sent)
                #expect(rows.expenses.first?.liveInvoice?.name == "INV-STATUS")
                _ = try await reopened.execute(sql: "INSERT INTO live_invoice_memberships(id,account_id,invoice_id,source_kind,source_id,position) VALUES('missing-source','sale-account','status-invoice','fee_installment','not-downloaded',1)", parameters: nil)
                #expect(try await ProjectExpensePowerSyncQuery(database: reopened).read(accountId: account, principalId: principal, projectId: project).expenses.first?.availability == nil)
                _ = try await reopened.execute(sql: "DELETE FROM live_invoice_memberships WHERE id='missing-source'", parameters: nil)
                // A partially downloaded Invoice must not turn its Expense into Available.
                _ = try await reopened.execute(sql: "DELETE FROM live_invoice_memberships WHERE id='status-member'", parameters: nil)
                let reopenedQuery = ProjectExpensePowerSyncQuery(database: reopened)
                #expect(try await reopenedQuery.read(accountId: account, principalId: principal, projectId: project).expenses.first?.availability == nil)
                // Once both records are absent in a completed stream, absence is authoritative.
                _ = try await reopened.execute(sql: "DELETE FROM live_invoices WHERE id='status-invoice'", parameters: nil)
                #expect(try await reopenedQuery.read(accountId: account, principalId: principal, projectId: project).expenses.first?.availability == .available)
                try await reopened.close()
            } catch { try? await reopened.close(); throw error }
        } catch { try? await db.close(); throw error }
    }

    @Test func downloadedExpensesRequireCheckpointAndPreserveSourceDetail() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seed(db)
        _ = try await db.execute(sql: "UPDATE spike_account_memberships SET financial_access='full'", parameters: nil)
        let project = try ProjectID(validating: "destination"), query = ProjectExpensePowerSyncQuery(database: db)
        let expenseId = try EntityID(validating: "expense"), attachmentId = try AttachmentID(validating: "receipt")
        await #expect(throws: PropertyManagementReportFailure.incompleteReadiness) {
            try await query.read(accountId: account, principalId: principal, projectId: project)
        }
        await #expect(throws: PropertyManagementReportFailure.incompleteReadiness) {
            try await query.receiptObject(accountId: account, principalId: principal, projectId: project,
                expenseId: expenseId, attachmentId: attachmentId)
        }
        // Inject completed download evidence for this local-reader test; actual
        // service subscription behavior is covered by the live integration run.
        _ = try await db.execute(sql: "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES ('project_expenses',1,0,?,1000000)",
            parameters: ["{\"account_id\":\"\(account.rawValue)\",\"project_id\":\"\(project.rawValue)\"}"])
        _ = try await db.execute(sql: """
            INSERT INTO expenses(id,account_id,project_id,category_id,vendor,expense_date,final_amount_minor_units,currency,notes,revision)
            VALUES ('expense',?,'destination','general','Vendor','2024-02-29','9223372036854775807','USD','Notes','1')
            """, parameters: [account.rawValue])
        _ = try await db.execute(sql: """
            INSERT INTO expense_receipt_lines(id,line_id,account_id,expense_id,position,description,magnitude_minor_units,currency,effect)
            VALUES ('expense/line','line',?,'expense',0,'Delivery','25','USD','increase')
            """, parameters: [account.rawValue])
        _ = try await db.execute(sql: """
            INSERT INTO expense_receipt_attachments(id,account_id,expense_id,attachment_id,position)
            VALUES ('expense/receipt',?,'expense','receipt',0)
            """, parameters: [account.rawValue])
        #expect(try await query.read(accountId: account, principalId: principal, projectId: project).expenses[0].currentCategoryName == nil)
        _ = try await db.execute(sql: "INSERT INTO spike_budget_categories(id,account_id,display_name,kind,lifecycle) VALUES ('general',?,'Delivery','general','active')", parameters: [account.rawValue])
        let value = try await query.read(accountId: account, principalId: principal, projectId: project)
        #expect(value.expenses[0].currentCategoryName == "Delivery")
        #expect(value.expenses.count == 1)
        #expect(value.expenses[0].entry.finalAmount.minorUnits == Int64.max)
        #expect(value.expenses[0].entry.receiptLines[0].magnitude.minorUnits == 25)
        #expect(value.expenses[0].entry.receiptAttachmentIds.map(\.rawValue) == ["receipt"])
        #expect(try await query.receiptObject(accountId: account, principalId: principal, projectId: project,
            expenseId: expenseId, attachmentId: attachmentId) == nil)
        let hash = String(repeating: "a", count: 64)
        _ = try await db.execute(sql: """
            INSERT INTO item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path)
            VALUES ('receipt',?,?,'12','application/pdf',?)
            """, parameters: [account.rawValue, hash, "accounts/\(account.rawValue)/attachments/receipt/\(hash)"])
        let object = try #require(await query.receiptObject(accountId: account, principalId: principal, projectId: project,
            expenseId: expenseId, attachmentId: attachmentId))
        #expect(object.byteCount == 12)
        let withObject = try await query.read(accountId: account, principalId: principal, projectId: project)
        #expect(withObject.expenses[0].receiptObjects == [object])
        #expect(withObject.expenses[0].entry == value.expenses[0].entry)
        #expect(try await query.receiptObject(accountId: account, principalId: principal, projectId: project,
            expenseId: .init(validating: "other-expense"), attachmentId: attachmentId) == nil)
        try await db.close()
        let reopened = try fixture.open(), offline = ProjectExpensePowerSyncQuery(database: reopened)
        #expect(try await offline.read(accountId: account, principalId: principal, projectId: project) == withObject)
        #expect(try await offline.receiptObject(accountId: account, principalId: principal, projectId: project,
            expenseId: expenseId, attachmentId: attachmentId) == object)
        _ = try await reopened.execute(sql: "UPDATE expense_receipt_lines SET position=1", parameters: nil)
        await #expect(throws: ProjectExpenses.Failure.invalidEvidence) {
            try await offline.read(accountId: account, principalId: principal, projectId: project)
        }
        _ = try await reopened.execute(sql: "UPDATE expense_receipt_lines SET position=0,currency='EUR'", parameters: nil)
        await #expect(throws: BusinessPaidExpenseDraft.Failure.currencyMismatch) {
            try await offline.read(accountId: account, principalId: principal, projectId: project)
        }
        _ = try await reopened.execute(sql: "UPDATE spike_account_memberships SET financial_access='none'", parameters: nil)
        await #expect(throws: ProjectInvoicingItemLocalReader.Failure.self) {
            try await offline.read(accountId: account, principalId: principal, projectId: project)
        }
        await #expect(throws: ProjectInvoicingItemLocalReader.Failure.self) {
            try await offline.receiptObject(accountId: account, principalId: principal, projectId: project,
                expenseId: expenseId, attachmentId: attachmentId)
        }
        try await reopened.close()
    }

    // Reuse this encrypted database/directory fixture for the new creation queue.
    @Test(arguments: [false, true]) func expenseCreationSurvivesRestartWithoutDuplicateAcceptance(withReceipt: Bool) async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seed(db)
        _ = try await db.execute(sql: "UPDATE spike_account_memberships SET financial_access='full'", parameters: nil)
        _ = try await db.execute(sql: "INSERT INTO spike_budget_categories(id,account_id,kind,lifecycle) VALUES ('general',?,'general','active')", parameters: [account.rawValue])
        while let pending = try await db.getNextCrudTransaction() { try await pending.complete() }
        let draft = try BusinessPaidExpenseDraft(accountId: account, projectId: .init(validating: "destination"),
            expenseId: .init(validating: "expense"), vendor: "Vendor", date: "2024-02-29",
            finalAmount: .init(minorUnits: Int64.max, currency: .init(validating: "USD")),
            categoryId: .init(validating: "general"), notes: "Retained offline",
            receiptAttachmentIds: withReceipt ? [.init(validating: "expense-receipt")] : [])
        let command = try CreateExpenseCommand(operationId: ExpenseCreationOperationIdentity.make(accountId: account, uuid: UUID()),
            actorPrincipalId: principal, capturedAt: Date(), draft: draft)
        let store = ExpenseCreationPowerSyncStore(database: db, accountId: account, principalId: principal, accessFence: .init())
        #expect(try await store.submit(command).localState == .queued)
        #expect(try await store.submit(command).localState == .queued)
        try await db.close()
        let reopened = try fixture.open()
        let restoredStore = ExpenseCreationPowerSyncStore(database: reopened, accountId: account, principalId: principal, accessFence: .init())
        #expect(try await restoredStore.submit(command).localState == .queued)
        _ = try await reopened.execute(sql: "INSERT INTO ps_stream_subscriptions(stream_name,active,is_default,local_params,last_synced_at) VALUES ('project_expenses',1,0,?,1000000)",
            parameters: ["{\"account_id\":\"\(account.rawValue)\",\"project_id\":\"destination\"}"])
        let expenseQuery = ProjectExpensePowerSyncQuery(database: reopened)
        let restored = try await expenseQuery.read(accountId: account, principalId: principal, projectId: draft.projectId)
        #expect(restored.expenses.isEmpty)
        #expect(restored.pendingCreations.count == 1)
        #expect(restored.pendingCreations.first?.entry == draft)
        #expect(restored.pendingCreations.first?.state == .queued)
        let pending = try #require(await reopened.getNextCrudTransaction())
        #expect(pending.crud.count == 1)
        #expect(pending.crud[0].table == LedgerPowerSyncTable.expenseCommands)
        #expect(pending.crud[0].id == command.envelope.operationId.rawValue)
        let duplicate = try CreateExpenseCommand(operationId: ExpenseCreationOperationIdentity.make(accountId: account, uuid: UUID()),
            actorPrincipalId: principal, capturedAt: Date(), draft: draft)
        await #expect(throws: ExpenseCreationPowerSyncStore.Failure.duplicateExpense) { try await restoredStore.submit(duplicate) }
        let ready: @Sendable (CreateExpenseCommand) async throws -> Set<AttachmentID> = { Set($0.envelope.payload.receiptAttachmentIds) }
        if withReceipt {
            let waiting = LedgerPowerSyncUploadConnector(accessFence: .init(), credentialProvider: { nil },
                clientCreationApplier: UnusedClientApplier(), expenseCreationApplier: ExpenseApplier())
            await #expect(throws: ExpenseCreationUpload.Failure.receiptNotReady) { try await waiting.uploadData(database: reopened) }
            #expect(try await restoredStore.submit(command).localState == .queued)
        }
        let failingUpload = LedgerPowerSyncUploadConnector(accessFence: .init(), credentialProvider: { nil },
            clientCreationApplier: UnusedClientApplier(), expenseCreationApplier: ExpenseApplier(fails: true), verifiedExpenseReceipts: ready)
        await #expect(throws: InjectedFailure.self) { try await failingUpload.uploadData(database: reopened) }
        #expect(try await restoredStore.submit(command).localState == .applying)
        let malformedUpload = LedgerPowerSyncUploadConnector(accessFence: .init(), credentialProvider: { nil },
            clientCreationApplier: UnusedClientApplier(), expenseCreationApplier: ExpenseApplier(wrongHash: true), verifiedExpenseReceipts: ready)
        await #expect(throws: CreateExpenseServerResult.Failure.self) { try await malformedUpload.uploadData(database: reopened) }
        #expect(try await reopened.getNextCrudTransaction() != nil)
        let upload = LedgerPowerSyncUploadConnector(accessFence: .init(), credentialProvider: { nil },
            clientCreationApplier: UnusedClientApplier(), expenseCreationApplier: ExpenseApplier(), verifiedExpenseReceipts: ready)
        try await upload.uploadData(database: reopened)
        #expect(try await reopened.getNextCrudTransaction() == nil)
        #expect(try await restoredStore.submit(command).localState == .applied)
        #expect(try await expenseQuery.read(accountId: account, principalId: principal, projectId: draft.projectId).pendingCreations.first?.state == .applied)
        _ = try await reopened.execute(sql: "UPDATE spike_local_operations SET local_state='rejected' WHERE id=?", parameters: [command.envelope.operationId.rawValue])
        let rejected = try await expenseQuery.read(accountId: account, principalId: principal, projectId: draft.projectId)
        #expect(rejected.pendingCreations.first?.state == .rejected)
        #expect(rejected.pendingCreations.first?.entry == draft)
        _ = try await reopened.execute(sql: "UPDATE spike_local_operations SET actor_principal_id='another-member' WHERE id=?", parameters: [command.envelope.operationId.rawValue])
        #expect(try await expenseQuery.read(accountId: account, principalId: principal, projectId: draft.projectId).pendingCreations.isEmpty)
        _ = try await reopened.execute(sql: "UPDATE spike_local_operations SET actor_principal_id=?,local_state='applied' WHERE id=?", parameters: [principal.rawValue, command.envelope.operationId.rawValue])
        // A downloaded authoritative row replaces the pending presentation, not the operation history.
        _ = try await reopened.execute(sql: """
            INSERT INTO expenses(id,account_id,project_id,category_id,vendor,expense_date,final_amount_minor_units,currency,notes,revision)
            VALUES ('expense',?,'destination','general','Vendor','2024-02-29','9223372036854775807','USD','Retained offline','1')
            """, parameters: [account.rawValue])
        let downloaded = try await expenseQuery.read(accountId: account, principalId: principal, projectId: draft.projectId)
        #expect(downloaded.expenses.count == 1)
        #expect(downloaded.pendingCreations.isEmpty)
        _ = try await reopened.execute(sql: "UPDATE spike_account_memberships SET financial_access='none'", parameters: nil)
        await #expect(throws: ExpenseCreationPowerSyncStore.Failure.unavailable) { try await restoredStore.submit(command) }
        await #expect(throws: ProjectInvoicingItemLocalReader.Failure.self) {
            try await expenseQuery.read(accountId: account, principalId: principal, projectId: draft.projectId)
        }
        try await reopened.close()
    }

    @Test func expenseAcceptanceRollsBackBothQueueRecords() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seed(db)
        _ = try await db.execute(sql: "UPDATE spike_account_memberships SET financial_access='full'", parameters: nil)
        _ = try await db.execute(sql: "INSERT INTO spike_budget_categories(id,account_id,kind,lifecycle) VALUES ('general',?,'general','active')", parameters: [account.rawValue])
        while let pending = try await db.getNextCrudTransaction() { try await pending.complete() }
        let command = try CreateExpenseCommand(operationId: ExpenseCreationOperationIdentity.make(accountId: account, uuid: UUID()),
            actorPrincipalId: principal, capturedAt: Date(), draft: .init(accountId: account,
                projectId: .init(validating: "destination"), expenseId: .init(validating: "expense"), vendor: "Vendor",
                date: "2024-02-29", finalAmount: .init(minorUnits: 100, currency: .init(validating: "USD")),
                categoryId: .init(validating: "general"), notes: ""))
        let store = ExpenseCreationPowerSyncStore(database: db, accountId: account, principalId: principal,
            accessFence: .init(), afterOperationWrite: { throw InjectedFailure() })
        await #expect(throws: InjectedFailure.self) { try await store.submit(command) }
        #expect(try await db.get(sql: "SELECT count(*) FROM spike_local_operations WHERE id=?", parameters: [command.envelope.operationId.rawValue]) { try $0.getInt(index: 0) } == 0)
        #expect(try await db.getNextCrudTransaction() == nil)
        try await db.close()
    }

    @Test func offlineReviewRequiresCompleteScopeAndRetainsExactEvidence() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seed(db)
        let item = try ItemID(validating: "item")
        _ = try await db.execute(sql: "INSERT INTO spike_items(id,account_id) VALUES ('item','sale-account')",parameters: nil)
        await #expect(throws: InventorySalePrice.Failure.evidenceUnavailable) {
            try await store(db).review(itemIds: [item])
        }
        let subscription = try await db.syncStream(name: "physical_account_items",params: ["account_id": .string(account.rawValue)]).subscribe()
        _ = try await db.execute(sql: "UPDATE ps_stream_subscriptions SET last_synced_at=1000000 WHERE stream_name='physical_account_items'",parameters: nil)
        _ = try await db.execute(sql: "INSERT INTO item_project_prices(id,account_id,item_id,revision,amount_minor_units,currency) VALUES ('item','sale-account','item','1','100','USD')",parameters: nil)
        let missingCost = try await store(db).review(itemIds: [item])
        #expect(throws: InventorySalePrice.Failure.evidenceUnavailable) {
            try missingCost.items[0].reviewedPrice(currency: .init(validating: "USD"))
        }
        _ = try await db.execute(sql: "INSERT INTO item_acquisition_reviews(id,account_id,state,amount_minor_units,currency) VALUES ('item','sale-account','known','9223372036854775807','USD')",parameters: nil)
        let review = try await store(db).review(itemIds: [item])
        #expect(try review.items[0].reviewedPrice(currency: .init(validating: "USD")).minorUnits == Int64.max)
        try await subscription.unsubscribe()
        try await db.close()
        let reopened = try fixture.open()
        let offline = try await store(reopened).review(itemIds: [item])
        #expect(offline.items[0].purchaseCost == review.items[0].purchaseCost)
        let watchedStore = store(reopened)
        var changes = watchedStore.watchReview(itemIds: [item]).makeAsyncIterator()
        #expect(try await changes.next()??.items[0].purchaseCost == review.items[0].purchaseCost)
        _ = try await reopened.execute(sql: "DELETE FROM item_acquisition_reviews",parameters: nil)
        #expect(try await store(reopened).review(itemIds: [item]).items[0].purchaseCost == .unavailable)
        var withdrawn = false
        while let update = try await changes.next() {
            if update?.items[0].purchaseCost == .unavailable { withdrawn = true; break }
        }
        #expect(withdrawn)
        _ = try await reopened.execute(sql: "UPDATE spike_item_placements SET scope_kind='project'",parameters: nil)
        await #expect(throws: InventorySalePowerSyncStore.Failure.stalePlacement) {
            try await store(reopened).review(itemIds: [item])
        }
        _ = try await reopened.execute(sql: "UPDATE spike_account_memberships SET state='removed'",parameters: nil)
        await #expect(throws: (any Error).self) { try await store(reopened).review(itemIds: [item]) }
        await #expect(throws: (any Error).self) { while let _ = try await changes.next() {} }
        await watchedStore.cancelAndDrainWatches()
        try await reopened.close()
    }

    @Test(.timeLimit(.minutes(1))) func watchTracksUploadAndTerminatesOnRemoval() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seed(db)
        let store = store(db), command = try command()
        _ = try await store.submit(command)
        var updates = store.watch(command.envelope.operationId).makeAsyncIterator()
        #expect(try await updates.next()??.state.phase == .queued)
        try await connector(Applier(rejected: false)).uploadData(database: db)
        var applied = false
        while let update = try await updates.next() {
            if update?.state.phase == .applied { applied = true; break }
        }
        #expect(applied)
        _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed'", parameters: nil)
        await #expect(throws: (any Error).self) {
            while let _ = try await updates.next() {}
        }
        await store.cancelAndDrainWatches()
        try await db.close()
    }

    @Test(.timeLimit(.minutes(1))) func watchDrainStopsBeforeDatabaseClose() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seed(db)
        let store = store(db), command = try command()
        var updates = store.watch(command.envelope.operationId).makeAsyncIterator()
        let initial = try await updates.next()
        #expect(initial != nil && initial! == nil)
        await store.cancelAndDrainWatches()
        #expect(try await updates.next() == nil)
        try await db.close()
    }

    @Test func newlyCreatedOfflineProjectCanReceiveQueuedSale() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seed(db)
        _ = try await db.execute(sql: "DELETE FROM spike_projects WHERE id='destination'", parameters: nil)
        while let pending = try await db.getNextCrudTransaction() { try await pending.complete() }
        let creation = try CreateProjectCommand(operationId: .init(validating: "create-before-sale"),
            draft: .init(accountId: account, actorPrincipalId: principal,
                operationContractVersion: .init(validating: "project-create-v1"),
                projectId: .init(validating: "destination"),
                clientSelection: .init(existing: .init(validating: "client")),
                displayName: .init(validating: "Offline Project"), description: nil,
                categoryAllocations: [], capturedAt: Date(timeIntervalSince1970: 1000)))
        _ = try await ProjectSetupPowerSyncStore(database: db).create(creation)
        #expect(try await store(db).submit(command()).localState == .queued)
        let first = try #require(await db.getNextCrudTransaction())
        #expect(first.crud.first?.table == LedgerPowerSyncTable.projectCommands)
        #expect(try await db.get("SELECT count(*) FROM spike_local_operations") { try $0.getInt(index: 0) } == 2)
        try await db.close()
    }

    @Test func unavailableDestinationDoesNotAcceptAnyWork() async throws {
        for mutation in [
            "DELETE FROM spike_projects",
            "UPDATE spike_projects SET lifecycle='archived'",
            "UPDATE spike_clients SET lifecycle='archived'",
            "UPDATE spike_clients SET account_id='foreign'",
            "INSERT INTO spike_local_operations(id,account_id,subject_id,command_type,local_state) VALUES ('archive','sale-account','destination','archive_project','queued')",
            "INSERT INTO spike_local_operations(id,account_id,subject_id,command_type,local_state) VALUES ('archive','sale-account','client','archive_client','applying')"
        ] {
            let fixture = try Fixture(); defer { fixture.remove() }
            let db = try fixture.open(); try await seed(db)
            _ = try await db.execute(sql: mutation, parameters: nil)
            let command = try command()
            await #expect(throws: InventorySalePowerSyncStore.Failure.destinationUnavailable) {
                try await store(db).submit(command)
            }
            #expect(try await db.get("SELECT count(*) FROM spike_local_operations WHERE command_type='sell_inventory_items'") {
                try $0.getInt(index: 0)
            } == 0)
            try await db.close()
        }
    }

    @Test func pendingWorkSafeguardCountsSaleAcrossRestartAndRejection() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seed(db)
        _ = try await store(db).submit(command())
        let queued = try await pending(db).summary()
        #expect(queued.queuedOperationCount == 1)
        try await db.close()
        let reopened = try fixture.open()
        #expect(try await pending(reopened).summary().queuedOperationCount == 1)
        try await connector(Applier(rejected: true)).uploadData(database: reopened)
        let rejected = try await pending(reopened).summary()
        #expect(rejected.queuedOperationCount == 0)
        #expect(rejected.unresolvedRejectedOperationCount == 1)
        try await reopened.close()
    }

    private func pending(_ db: any PowerSyncDatabaseProtocol) -> PendingWorkPowerSyncQuery {
        .init(database: db, attachmentObserver: EmptyAttachments(), environment: .targetLocal,
              principalId: principal, accountId: account)
    }
    private struct EmptyAttachments: AttachmentPendingWorkObserving {
        func pendingWorkObservation() async throws -> AttachmentPendingWorkObservation {
            .init(queue: [], orphans: [])
        }
    }

    @Test func uploadPersistsAppliedAndRejectedResultsBeforeRemovingQueue() async throws {
        for rejected in [false, true] {
            let fixture = try Fixture(); defer { fixture.remove() }
            let db = try fixture.open(); try await seed(db)
            let command = try command()
            _ = try await store(db).submit(command)
            try await connector(Applier(rejected: rejected)).uploadData(database: db)
            #expect(try await db.getNextCrudTransaction() == nil)
            #expect(try await store(db).submit(command).localState == (rejected ? .rejected : .applied))
            try await db.close()
            let reopened = try fixture.open()
            #expect(try await store(reopened).submit(command).localState == (rejected ? .rejected : .applied))
            #expect(try await store(reopened).status(command.envelope.operationId)?.state.phase == (rejected ? .rejected : .applied))
            #expect(try await reopened.getNextCrudTransaction() == nil)
            try await reopened.close()
        }
    }

    @Test func interruptedOrMisboundResponseKeepsIntentForRetry() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seed(db)
        let command = try command(); _ = try await store(db).submit(command)
        await #expect(throws: InjectedFailure.self) {
            try await connector(Applier(fails: true)).uploadData(database: db)
        }
        #expect(try await store(db).submit(command).localState == .applying)
        #expect(try await store(db).status(command.envelope.operationId)?.state.phase == .applying)
        await #expect(throws: InventorySaleServerResult.Failure.receiptMismatch) {
            try await connector(Applier(wrongHash: true)).uploadData(database: db)
        }
        #expect(try await db.getNextCrudTransaction() != nil)
        try await db.close()
        let reopened = try fixture.open()
        try await connector(Applier()).uploadData(database: reopened)
        #expect(try await store(reopened).submit(command).localState == .applied)
        #expect(try await reopened.getNextCrudTransaction() == nil)
        try await reopened.close()
    }

    @Test func removalDuringRequestRetainsQueueWithoutAcceptingResponse() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seed(db)
        _ = try await store(db).submit(command())
        let fence = LedgerWorkspaceAccessFence()
        await #expect(throws: LedgerOfflineClientRuntimeFailure.runtimeClosed) {
            try await connector(Applier(removes: fence), fence: fence).uploadData(database: db)
        }
        #expect(try await db.getNextCrudTransaction() != nil)
        #expect(try await db.get("SELECT local_state FROM spike_local_operations") { try $0.getString(index: 0) } == "applying")
        try await db.close()
    }

    private func connector(_ applier: Applier, fence: LedgerWorkspaceAccessFence = .init()) -> LedgerPowerSyncUploadConnector {
        .init(accessFence: fence, credentialProvider: { nil }, clientCreationApplier: UnusedClientApplier(), inventorySaleApplier: applier)
    }
    private struct UnusedClientApplier: ClientCreationCommandApplying {
        func apply(_ request: ClientCreationUploadRequest) async throws -> ClientCreationServerResult { throw InjectedFailure() }
    }
    private struct ExpenseApplier: CreateExpenseCommandApplying {
        var fails = false
        var wrongHash = false
        func apply(_ command: CreateExpenseCommand) async throws -> CreateExpenseServerResult {
            if fails { throw InjectedFailure() }
            let e = command.envelope, request = try CreateExpenseUploadRequest(command)
            let value: [String: Any] = [
                "operation_id": e.operationId.rawValue, "account_id": e.accountId.rawValue,
                "actor_principal_id": e.actorPrincipalId.rawValue, "command_type": "create_expense",
                "contract_version": "expense-create-v1", "subject_id": e.payload.expenseId.rawValue,
                "command_fingerprint": wrongHash ? "wrong" : request.fingerprint,
                "envelope_sha256": request.fingerprint, "phase": "applied", "result_code": "expense_created",
                "client_created_at_ms": Int64((e.clientCreatedAt.timeIntervalSince1970 * 1000).rounded()),
                "server_received_at_ms": 1788523200000, "completed_at_ms": 1788523200000
            ]
            return try JSONDecoder().decode(CreateExpenseServerResult.self, from: JSONSerialization.data(withJSONObject: value))
        }
    }
    private struct Applier: InventorySaleCommandApplying {
        var rejected = false
        var fails = false
        var wrongHash = false
        var removes: LedgerWorkspaceAccessFence? = nil
        func apply(_ command: InventorySaleCommand) async throws -> InventorySaleServerResult {
            if fails { throw InjectedFailure() }
            removes?.markRemoved()
            let e = command.envelope
            let hash = try InventorySaleUploadRequest(command).fingerprint
            return .init(operation_id: e.operationId.rawValue, account_id: e.accountId.rawValue,
                actor_principal_id: e.actorPrincipalId.rawValue, command_type: "sell_inventory_items",
                contract_version: "inventory-sale-v1", command_fingerprint: wrongHash ? "wrong" : hash,
                envelope_sha256: hash, subject_id: e.payload.projectId.rawValue,
                phase: rejected ? "rejected" : "applied", request_sha256: nil,
                result_code: rejected ? nil : "inventory_items_sold", error_code: rejected ? "sale_price_stale" : nil,
                client_created_at_ms: 1000000, server_received_at_ms: 1000001, completed_at_ms: 1000002)
        }
    }

    @Test func pendingPlacementSurvivesRestartAndSourceDownloadGap() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seed(db)
        try await db.execute(sql: "INSERT INTO spike_items(id,account_id,description,revision) VALUES ('item',?,'Chair',1)",parameters: [account.rawValue])
        try await db.execute(sql: "UPDATE spike_item_placements SET started_at='2026-01-01' WHERE id='old'",parameters: [])
        while let crud = try await db.getNextCrudTransaction() { try await crud.complete() }
        _ = try await store(db).submit(command())
        let reader = CurrentItemPlacementLocalReader(database: db)
        #expect(try await reader.readSnapshot(accountId: account,principalId: principal,scope: .businessInventory).rows.isEmpty)
        let destination = try ProjectID(validating: "destination")
        let moved = try await reader.readSnapshot(accountId: account,principalId: principal,scope: .project(destination))
        #expect(moved.rows.count == 1 && moved.rows[0].pendingSale != nil)
        #expect(moved.rows[0].description == "Chair" && moved.rows[0].spaceId == nil)
        let history = try await reader.readHistory(accountId: account,principalId: principal,itemId: .init(validating: "item"))
        #expect(history.pendingSale != nil)
        #expect(history.intervals.count == 1 && history.intervals[0].placementId.rawValue == "old")
        #expect(history.intervals[0].scope == .businessInventory && history.intervals[0].endedAt == nil)
        try await connector(Applier(rejected: false)).uploadData(database: db)
        try await db.close()
        let reopened = try fixture.open()
        let restored = CurrentItemPlacementLocalReader(database: reopened)
        #expect(try await restored.readSnapshot(accountId: account,principalId: principal,scope: .project(destination)).rows.first?.pendingSale != nil)
        try await reopened.execute(sql: "UPDATE spike_item_placements SET ended_at='2026-09-15T00:00:00Z' WHERE id='old'",parameters: [])
        #expect(try await restored.readSnapshot(accountId: account,principalId: principal,scope: .project(destination)).rows.first?.pendingSale != nil)
        #expect(try await restored.readHistory(accountId: account,principalId: principal,itemId: .init(validating: "item")).pendingSale != nil)
        try await reopened.execute(sql: "INSERT INTO spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at) VALUES ('new',?,'item','project','destination','2026-09-15T00:00:00Z')",parameters: [account.rawValue])
        let synced = try await restored.readSnapshot(accountId: account,principalId: principal,scope: .project(destination))
        #expect(synced.rows.count == 1 && synced.rows[0].pendingSale == nil)
        let syncedHistory = try await restored.readHistory(accountId: account,principalId: principal,itemId: .init(validating: "item"))
        #expect(syncedHistory.pendingSale == nil && syncedHistory.intervals.count == 2)
        try await reopened.execute(sql: "UPDATE spike_account_memberships SET state='removed'",parameters: [])
        await #expect(throws: CurrentItemPlacementReadFailure.accountUnavailable) {
            try await restored.readSnapshot(accountId: account,principalId: principal,scope: .project(destination))
        }
        try await reopened.close()
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func openListsReactToSaleAcceptanceAndRejection(project: Bool) async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seed(db)
        try await db.execute(sql: "INSERT INTO spike_items(id,account_id,description,revision) VALUES ('item',?,'Chair',1)",parameters: [account.rawValue])
        while let crud = try await db.getNextCrudTransaction() { try await crud.complete() }
        let changes = AsyncStream<[PhysicalItemPlacement]>.makeStream()
        let task = Task {
            defer { changes.continuation.finish() }
            do {
                if project {
                    try await DownloadedProjectItemsWatch(database: db).run(accountId: account,principalId: principal,
                        projectId: .init(validating: "destination")) {
                            changes.continuation.yield($0.placements.rows); return true
                        }
                } else {
                    try await DownloadedItemPlacementWatch(database: db).run(accountId: account,principalId: principal,
                        scope: .businessInventory) { changes.continuation.yield($0.rows); return true }
                }
            } catch is CancellationError { }
            catch { Issue.record(error) }
        }
        let deadline = Task { try await Task.sleep(for: .seconds(15)); task.cancel() }
        defer { deadline.cancel(); task.cancel() }
        var iterator = changes.stream.makeAsyncIterator()
        let initial = try #require(await iterator.next())
        #expect(initial.count == (project ? 0 : 1))
        _ = try await store(db).submit(command())
        var pending = try #require(await iterator.next())
        while project ? pending.first?.pendingSale == nil : !pending.isEmpty {
            pending = try #require(await iterator.next())
        }
        #expect(pending.count == (project ? 1 : 0))
        try await connector(Applier(rejected: true)).uploadData(database: db)
        var restored = try #require(await iterator.next())
        while project ? !restored.isEmpty : restored.isEmpty {
            restored = try #require(await iterator.next())
        }
        #expect(restored.count == (project ? 0 : 1))
        task.cancel(); await task.value
        try await db.close()
    }

    @Test func rejectedSaleRestoresInventoryPresentation() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seed(db)
        try await db.execute(sql: "INSERT INTO spike_items(id,account_id,description,revision) VALUES ('item',?,'Chair',1)",parameters: [account.rawValue])
        while let crud = try await db.getNextCrudTransaction() { try await crud.complete() }
        _ = try await store(db).submit(command())
        try await connector(Applier(rejected: true)).uploadData(database: db)
        let restored = try await CurrentItemPlacementLocalReader(database: db).readSnapshot(accountId: account,principalId: principal,scope: .businessInventory)
        #expect(restored.rows.count == 1 && restored.rows[0].pendingSale == nil)
        try await db.close()
    }

    @Test func restartAndReplayRetainOneIntent() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open()
        try await seed(db)
        let command = try command()
        let first = try await store(db).submit(command)
        #expect(first.localState == .queued)
        try await db.close()
        let reopened = try fixture.open()
        let replay = try await store(reopened).submit(command)
        #expect(replay.localState == .queued)
        #expect(try await store(reopened).status(command.envelope.operationId)?.state.phase == .queued)
        #expect(try await reopened.get("SELECT count(*) FROM spike_local_operations") { try $0.getInt(index: 0) } == 1)
        let queue = try #require(await reopened.getNextCrudTransaction())
        #expect(queue.crud.count == 1)
        #expect(queue.crud[0].table == LedgerPowerSyncTable.inventorySaleCommands)
        #expect(queue.crud[0].id == command.envelope.operationId.rawValue)
        #expect(try await reopened.get("SELECT scope_kind FROM spike_item_placements WHERE id='old'") {
            try $0.getString(index: 0)
        } == "business_inventory")
        try await reopened.close()
    }

    @Test func secondSaleCannotReserveSamePlacementUntilRejection() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seed(db)
        let first = try command()
        _ = try await store(db).submit(first)
        try await db.close()
        let reopened = try fixture.open()
        for phase in ["queued", "applying", "applied"] {
            try await reopened.execute(sql: "UPDATE spike_local_operations SET local_state=?", parameters: [phase])
            do {
                _ = try await store(reopened).submit(command())
                Issue.record("Accepted a second sale while first was \(phase)")
            } catch InventorySaleCommandFailure.saleAlreadyAccepted { }
            #expect(try await reopened.get("SELECT count(*) FROM spike_local_operations") { try $0.getInt(index: 0) } == 1)
        }
        try await reopened.execute(sql: "UPDATE spike_local_operations SET local_state='rejected'", parameters: [])
        #expect(try await store(reopened).submit(command()).localState == .queued)
        try await reopened.close()
    }

    @Test func failureRollsBackBothRecordsAndRevocationDenies() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seed(db)
        let failing = InventorySalePowerSyncStore(database: db, accountId: account, principalId: principal,
            accessFence: LedgerWorkspaceAccessFence(), checkpoint: { _ in throw InjectedFailure() })
        let command = try command()
        await #expect(throws: InjectedFailure.self) { try await failing.submit(command) }
        #expect(try await db.get("SELECT count(*) FROM spike_local_operations") { try $0.getInt(index: 0) } == 0)
        #expect(try await db.getNextCrudTransaction() == nil)
        _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed'", parameters: nil)
        await #expect(throws: (any Error).self) { try await store(db).submit(command) }
        await #expect(throws: (any Error).self) { try await store(db).status(command.envelope.operationId) }
        #expect(try await db.get("SELECT count(*) FROM spike_local_operations") { try $0.getInt(index: 0) } == 0)
        try await db.close()
    }

    @Test func changedDownloadedPriceRequiresReviewButAcceptedReplayRemainsStable() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let db = try fixture.open(); try await seed(db)
        _ = try await db.execute(sql: """
            INSERT INTO item_project_prices(id,account_id,item_id,amount_minor_units,currency,revision)
            VALUES ('item','sale-account','item','100','USD','1')
            """, parameters: nil)
        await #expect(throws: InventorySalePowerSyncStore.Failure.stalePrice) {
            try await store(db).submit(command())
        }
        #expect(try await db.get("SELECT count(*) FROM spike_local_operations") { try $0.getInt(index: 0) } == 0)
        let accepted = try command(priceRevision: 1)
        #expect(try await store(db).submit(accepted).localState == .queued)
        _ = try await db.execute(sql: "UPDATE item_project_prices SET revision='2'", parameters: nil)
        #expect(try await store(db).submit(accepted).localState == .queued)
        await #expect(throws: InventorySalePowerSyncStore.Failure.stalePrice) {
            try await store(db).submit(command(priceRevision: 1))
        }
        _ = try await db.execute(sql: "UPDATE item_project_prices SET currency='EUR'", parameters: nil)
        await #expect(throws: InventorySalePowerSyncStore.Failure.stalePrice) {
            try await store(db).submit(command(priceRevision: 2))
        }
        #expect(try await db.get("SELECT count(*) FROM spike_local_operations") { try $0.getInt(index: 0) } == 1)
        try await db.close()
    }

    private func command(priceRevision: Int64 = 0) throws -> InventorySaleCommand {
        try .init(operationId: InventorySaleOperationIdentity.make(accountId: account, uuid: UUID()),
            accountId: account, actorPrincipalId: principal, capturedAt: Date(timeIntervalSince1970: 1000),
            payload: .init(projectId: .init(validating: "destination"), currency: .init(validating: "USD"),
                items: [.init(itemId: .init(validating: "item"), placementId: .init(validating: "old"),
                    priceRevision: priceRevision, reviewedPriceMinorUnits: 100,
                    newPlacementId: .init(validating: "new"), occurrenceId: .init(validating: "charge"))]))
    }
    private func store(_ db: any PowerSyncDatabaseProtocol) -> InventorySalePowerSyncStore {
        .init(database: db, accountId: account, principalId: principal, accessFence: LedgerWorkspaceAccessFence())
    }
    private func seed(_ db: any PowerSyncDatabaseProtocol) async throws {
        _ = try await db.execute(sql: "INSERT INTO spike_clients(id,account_id,display_name,lifecycle,revision,created_at_ms,updated_at_ms) VALUES ('client',?,'Client','active',1,1,1)",
                                parameters: [account.rawValue])
        _ = try await db.execute(sql: "INSERT INTO spike_projects(id,account_id,client_id,display_name,lifecycle,revision) VALUES ('destination',?,'client','Project','active',1)",
                                parameters: [account.rawValue])
        _ = try await db.execute(sql: """
            INSERT INTO spike_account_memberships(id,account_id,principal_id,state,financial_access)
            VALUES ('member',?,?,'active','none')
            """, parameters: [account.rawValue, principal.rawValue])
        _ = try await db.execute(sql: """
            INSERT INTO spike_item_placements(id,account_id,item_id,scope_kind)
            VALUES ('old',?,'item','business_inventory')
            """, parameters: [account.rawValue])
        while let pending = try await db.getNextCrudTransaction() { try await pending.complete() }
    }
    private struct Fixture {
        let directory: URL
        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-sale-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        func open() throws -> any PowerSyncDatabaseProtocol {
            try LedgerPowerSyncDatabaseFactory.open(absolutePath: directory.appendingPathComponent("ledger.sqlite").path,
                encryptionKey: LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "3a", count: 32)))
        }
        func remove() { try? FileManager.default.removeItem(at: directory) }
    }
}
