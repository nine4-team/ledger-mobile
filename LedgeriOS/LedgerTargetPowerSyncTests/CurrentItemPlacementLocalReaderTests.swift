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

    @Test("Current Purchase facts are exact, durable and cleared when the Item leaves its Project")
    func currentPurchaseFacts() async throws {
        try await withDatabase(reopen: { db in
            let reader = CurrentItemPlacementLocalReader(database: db)
            let item = try ItemID(validating: "chair")
            let loaded = try await reader.readHistory(accountId: account, principalId: principal, itemId: item)
            #expect(loaded.currentClientPaidPurchases.first?.amount.minorUnits == 12345)
            _ = try await db.execute(sql: "UPDATE spike_item_placements SET ended_at='2026-03-01' WHERE id='project-now'", parameters: nil)
            _ = try await db.execute(sql: "INSERT INTO spike_item_placements(id,account_id,item_id,scope_kind,started_at) VALUES('inventory-now','account-item','chair','business_inventory','2026-03-01')", parameters: nil)
            #expect(try await reader.readHistory(accountId: account, principalId: principal, itemId: item).currentClientPaidPurchases.isEmpty)
        }) { db in
            try await seedAccounting(db)
            let reader = CurrentItemPlacementLocalReader(database: db)
            let item = try ItemID(validating: "chair")
            #expect(try await reader.readHistory(accountId: account, principalId: principal, itemId: item).currentClientPaidPurchases.isEmpty)
            _ = try await db.execute(sql: "INSERT INTO spike_transactions(id,account_id,project_id,client_id,type,role,amount_minor_units,currency,origin) VALUES('purchase','account-item','project-item','client','purchase','standalone','12345','USD','firebase_client_payment')", parameters: nil)
            var iterator = try reader.watchHistory(accountId: account, principalId: principal, itemId: item).makeAsyncIterator()
            _ = try #require(await iterator.next())
            #expect(try await reader.readHistory(accountId: account, principalId: principal, itemId: item).currentClientPaidPurchases.first?.id.rawValue == "purchase")
            for field in ["account_id", "project_id", "client_id", "type", "role", "amount_minor_units", "currency", "origin"] {
                _ = try await db.execute(sql: "UPDATE spike_transactions SET \(field)='wrong' WHERE id='purchase'", parameters: nil)
                _ = try #require(await iterator.next())
                #expect(try await reader.readHistory(accountId: account, principalId: principal, itemId: item).currentClientPaidPurchases.isEmpty)
                _ = try await db.execute(sql: "UPDATE spike_transactions SET account_id='account-item',project_id='project-item',client_id='client',type='purchase',role='standalone',amount_minor_units='12345',currency='USD',origin='firebase_client_payment' WHERE id='purchase'", parameters: nil)
                _ = try #require(await iterator.next())
            }
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET financial_access='limited'", parameters: nil)
            _ = try #require(await iterator.next())
            #expect(try await reader.readHistory(accountId: account, principalId: principal, itemId: item).currentClientPaidPurchases.isEmpty)
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET financial_access='full'", parameters: nil)
        }
    }

    @Test("Purchase reads retain exact cents and omit missing or malformed financial evidence")
    func purchaseEvidenceBoundaries() async throws {
        try await withDatabase { db in
            try await seedAccounting(db)
            let reader = CurrentItemPlacementLocalReader(database: db)
            let item = try ItemID(validating: "chair")
            _ = try await db.execute(sql: "INSERT INTO spike_transactions(id,account_id,project_id,client_id,type,role,amount_minor_units,currency,origin) VALUES('purchase','account-item','project-item','client','purchase','standalone','9007199254740993','USD','firebase_client_payment')", parameters: nil)
            let exact = try await reader.readHistory(accountId: account, principalId: principal, itemId: item)
            #expect(exact.currentClientPaidPurchases.first?.amount.minorUnits == 9_007_199_254_740_993)
            #expect(exact.currentClientPaidPurchases.first?.amount.currency.rawValue == "USD")
            for amount in ["0", "-1", "01", "+1", "1.0", "9223372036854775808"] {
                _ = try await db.execute(sql: "UPDATE spike_transactions SET amount_minor_units=? WHERE id='purchase'", parameters: [amount])
                let invalid = try await reader.readHistory(accountId: account, principalId: principal, itemId: item)
                #expect(invalid.currentClientPaidPurchases.isEmpty)
                #expect(invalid.currentAccountingResolution == .relationshipEvidenceIncomplete)
                #expect(invalid.description == "Chair")
            }
            _ = try await db.execute(sql: "UPDATE spike_transactions SET amount_minor_units='1' WHERE id='purchase'", parameters: nil)
            _ = try await db.execute(sql: "UPDATE item_client_payment_connections SET ended_at='2026-03-01'", parameters: nil)
            #expect(try await reader.readHistory(accountId: account, principalId: principal, itemId: item).currentClientPaidPurchases.isEmpty)
            _ = try await db.execute(sql: "UPDATE item_client_payment_connections SET ended_at=NULL", parameters: nil)
            _ = try await db.execute(sql: "DELETE FROM spike_transactions WHERE id='purchase'", parameters: nil)
            let missing = try await reader.readHistory(accountId: account, principalId: principal, itemId: item)
            #expect(missing.currentClientPaidPurchases.isEmpty && missing.isPartial)
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed'", parameters: nil)
            await #expect(throws: CurrentItemPlacementReadFailure.accountUnavailable) {
                try await reader.readHistory(accountId: account, principalId: principal, itemId: item)
            }
        }
    }

    @Test("Current accounting association is scoped, access checked and survives reopen without historical fallback")
    func currentAccountingAssociation() async throws {
        try await withDatabase(reopen: { db in
            let reader = CurrentItemPlacementLocalReader(database: db)
            let item = try ItemID(validating: "chair")
            #expect(try await reader.readHistory(accountId: account, principalId: principal, itemId: item).currentAccountingResolution == .accountedFor)
            _ = try await db.execute(sql: "UPDATE spike_item_placements SET ended_at='2026-03-01' WHERE id='project-now'", parameters: nil)
            _ = try await db.execute(sql: "INSERT INTO spike_item_placements(id,account_id,item_id,scope_kind,started_at) VALUES('inventory-now','account-item','chair','business_inventory','2026-03-01')", parameters: nil)
            #expect(try await reader.readHistory(accountId: account, principalId: principal, itemId: item).currentAccountingResolution == nil)
        }) { db in
            let reader = CurrentItemPlacementLocalReader(database: db)
            let item = try ItemID(validating: "chair")
            #expect(try await reader.readHistory(accountId: account, principalId: principal, itemId: item).currentAccountingResolution == .relationshipEvidenceIncomplete)
            try await seedAccounting(db)
            // A malformed different placement must not poison this exact Item.
            _ = try await db.execute(sql: "INSERT INTO item_client_payment_connections(id,account_id,project_id,placement_id) VALUES('unrelated','foreign','project-item','other-placement')", parameters: nil)
            #expect(try await reader.readHistory(accountId: account, principalId: principal, itemId: item).currentAccountingResolution == .accountedFor)
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET financial_access='limited'", parameters: nil)
            #expect(try await reader.readHistory(accountId: account, principalId: principal, itemId: item).currentAccountingResolution == .relationshipEvidenceIncomplete)
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET financial_access='full'", parameters: nil)
            for field in ["account_id", "client_id", "item_id"] {
                _ = try await db.execute(sql: "UPDATE item_client_payment_connections SET \(field)='wrong' WHERE id='payment'", parameters: nil)
                #expect(try await reader.readHistory(accountId: account, principalId: principal, itemId: item).currentAccountingResolution == .relationshipEvidenceIncomplete)
                _ = try await db.execute(sql: "UPDATE item_client_payment_connections SET account_id='account-item',client_id='client',item_id='chair' WHERE id='payment'", parameters: nil)
            }
        }
    }

    @Test("History accounting invalidates for same-count payment, charge, frozen-line and Invoice updates")
    func currentAccountingWatch() async throws {
        try await withDatabase { db in
            try await seedAccounting(db)
            let reader = CurrentItemPlacementLocalReader(database: db)
            let item = try ItemID(validating: "chair")
            var iterator = try reader.watchHistory(accountId: account, principalId: principal, itemId: item).makeAsyncIterator()
            // Match the runtime: notifications trigger a new atomic physical +
            // accounting read, not a category/history-only opening snapshot.
            _ = try #require(await iterator.next())
            #expect(try await reader.readHistory(accountId: account, principalId: principal, itemId: item).currentAccountingResolution == .accountedFor)
            let steps: [(String, ProjectItemAccountingResolution?)] = [
                ("UPDATE item_client_payment_connections SET transaction_type='refund'", .relationshipEvidenceIncomplete),
                ("UPDATE item_client_payment_connections SET transaction_type='purchase'", .accountedFor),
                ("UPDATE item_client_payment_connections SET ended_at='2026-03-01'", .relationshipEvidenceIncomplete),
                ("INSERT INTO item_charge_occurrences(id,account_id,project_id,item_id,placement_id,category_id,amount_minor_units,currency,revision) VALUES('charge','account-item','project-item','chair','project-now','category','100','USD',1)", .accountedFor),
                ("UPDATE item_charge_occurrences SET amount_minor_units='0'", .relationshipEvidenceIncomplete),
                ("UPDATE item_charge_occurrences SET amount_minor_units='100'", .accountedFor),
                ("INSERT INTO collected_invoice_lines(id,account_id,invoice_id,source_kind,source_id,item_id,category_id,source_revision,signed_amount_minor_units,currency) VALUES('line','account-item','invoice','item','charge','chair','category',1,'100','USD')", .relationshipEvidenceIncomplete),
                ("INSERT INTO collected_invoices(id,account_id,project_id,client_id,sealed) VALUES('invoice','account-item','project-item','client',1)", .accountedFor),
                ("UPDATE collected_invoices SET sealed=0", .relationshipEvidenceIncomplete),
                ("UPDATE collected_invoices SET sealed=1", .accountedFor),
                ("UPDATE collected_invoice_lines SET signed_amount_minor_units='99'", .relationshipEvidenceIncomplete),
                ("UPDATE collected_invoice_lines SET signed_amount_minor_units='100'", .accountedFor),
                ("UPDATE spike_account_memberships SET financial_access='none'", .relationshipEvidenceIncomplete)
            ]
            for (sql, expected) in steps {
                _ = try await db.execute(sql: sql, parameters: nil)
                _ = try #require(await iterator.next())
                #expect(try await reader.readHistory(accountId: account, principalId: principal, itemId: item).currentAccountingResolution == expected)
            }
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed'", parameters: nil)
            await #expect(throws: CurrentItemPlacementReadFailure.accountUnavailable) {
                while try await iterator.next() != nil {}
            }
        }
    }

    private func seedAccounting(_ db: any PowerSyncDatabaseProtocol) async throws {
        _ = try await db.execute(sql: "UPDATE spike_account_memberships SET financial_access='full'", parameters: nil)
        _ = try await db.execute(sql: "UPDATE spike_projects SET client_id='client'", parameters: nil)
        _ = try await db.execute(sql: "INSERT INTO item_client_payment_connections(id,account_id,project_id,client_id,item_id,placement_id,transaction_id,transaction_type,transaction_role) VALUES('payment','account-item','project-item','client','chair','project-now','purchase','purchase','standalone')", parameters: nil)
    }

    @Test("Current category preserves authorized labels across restart and never uses historical assignment")
    func currentBudgetCategory() async throws {
        try await withDatabase(reopen: { db in
            let reader = CurrentItemPlacementLocalReader(database: db)
            let item = try ItemID(validating: "chair")
            #expect(try await reader.readHistory(accountId: account, principalId: principal, itemId: item).currentBudgetCategoryName == "Archived furnishings")
            _ = try await db.execute(sql: "UPDATE spike_item_placements SET ended_at='2026-03-01' WHERE id='project-now'", parameters: nil)
            _ = try await db.execute(sql: "INSERT INTO spike_item_placements(id,account_id,item_id,scope_kind,started_at) VALUES('inventory-now','account-item','chair','business_inventory','2026-03-01')", parameters: nil)
            let moved = try await reader.readHistory(accountId: account, principalId: principal, itemId: item)
            #expect(moved.currentBudgetCategoryName == nil)
            #expect(moved.intervals.contains { $0.placementId.rawValue == "project-now" })
        }) { db in
            let reader = CurrentItemPlacementLocalReader(database: db)
            let item = try ItemID(validating: "chair")
            #expect(try await reader.readHistory(accountId: account, principalId: principal, itemId: item).currentBudgetCategoryName == nil)
            try await seedCategory(db)
            #expect(try await reader.readHistory(accountId: account, principalId: principal, itemId: item).currentBudgetCategoryName == "Archived furnishings")
            _ = try await db.execute(sql: "DELETE FROM spike_budget_categories", parameters: nil)
            #expect(try await reader.readHistory(accountId: account, principalId: principal, itemId: item).currentBudgetCategoryName == nil)
            _ = try await db.execute(sql: "INSERT INTO spike_budget_categories(id,account_id,display_name,visibility_class,lifecycle,revision) VALUES('furnishings','account-item','Archived furnishings','ordinary','archived',1)", parameters: nil)
        }
    }

    @Test("Category history watch reacts to labels and financial visibility without exposing restricted names")
    func currentBudgetCategoryWatch() async throws {
        try await withDatabase { db in
            try await seedCategory(db)
            let reader = CurrentItemPlacementLocalReader(database: db)
            var iterator = try reader.watchHistory(accountId: account, principalId: principal,
                itemId: ItemID(validating: "chair")).makeAsyncIterator()
            func category(_ rows: [CurrentItemPlacementLocalReader.HistoryRow]) throws -> String? {
                try CurrentItemPlacementLocalReader.history(accountId: account,
                    itemId: ItemID(validating: "chair"), rows: rows).currentBudgetCategoryName
            }
            #expect(try category(try #require(await iterator.next())) == "Archived furnishings")
            _ = try await db.execute(sql: "UPDATE spike_budget_categories SET display_name='Updated name'", parameters: nil)
            while try category(try #require(await iterator.next())) != "Updated name" {}
            _ = try await db.execute(sql: "UPDATE spike_budget_categories SET visibility_class='restricted'", parameters: nil)
            while try category(try #require(await iterator.next())) != nil {}
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET financial_access='full'", parameters: nil)
            while try category(try #require(await iterator.next())) != "Updated name" {}
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET financial_access='limited'", parameters: nil)
            while try category(try #require(await iterator.next())) != nil {}
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed'", parameters: nil)
            await #expect(throws: CurrentItemPlacementReadFailure.accountUnavailable) {
                while try await iterator.next() != nil {}
            }
        }
    }

    @Test("Current category rejects mismatched assignment account, Project and Item")
    func invalidBudgetCategoryAssignment() async throws {
        for mutation in [
            "UPDATE spike_item_project_categories SET account_id='foreign'",
            "UPDATE spike_item_project_categories SET project_id='other-project'",
            "UPDATE spike_item_project_categories SET item_id='other-item'"
        ] {
            try await withDatabase { db in
                try await seedCategory(db)
                _ = try await db.execute(sql: mutation, parameters: nil)
                await #expect(throws: CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement) {
                    try await CurrentItemPlacementLocalReader(database: db).readHistory(accountId: account,
                        principalId: principal, itemId: ItemID(validating: "chair"))
                }
            }
        }
    }

    private func seedCategory(_ db: any PowerSyncDatabaseProtocol) async throws {
        _ = try await db.execute(sql: "INSERT INTO spike_budget_categories(id,account_id,display_name,visibility_class,lifecycle,revision) VALUES('furnishings','account-item','Archived furnishings','ordinary','archived',1)", parameters: nil)
        _ = try await db.execute(sql: "INSERT INTO spike_item_project_categories(id,account_id,project_id,item_id,category_id,revision) VALUES('project-now','account-item','project-item','chair','furnishings',1)", parameters: nil)
    }

    @Test("Exact Item details preserve raw notes and timestamp across encrypted reopen")
    func descriptiveDetails() async throws {
        let item = try ItemID(validating: "chair")
        try await withDatabase(reopen: { db in
            let reader = CurrentItemPlacementLocalReader(database: db)
            let history = try await reader.readHistory(accountId: account, principalId: principal, itemId: item)
            let details = try #require(history.details)
            #expect(details.name == "" && details.displayName == "")
            #expect(details.description == "Chair")
            #expect(details.notes == "  Notes\nsecond line  ")
            #expect(details.sku == " SKU " && details.source == " Vendor ")
            #expect(details.currentSource == "" && details.displaySource == "")
            #expect(details.createdAt == "2026-01-01T12:34:56.123456789Z")
            #expect(details.workflowStatus == .toPurchase && details.workflowStatusRaw == "to-purchase")
            #expect(details.isBookmarked == true)
            _ = try await db.execute(sql: "UPDATE spike_items SET notes='',name=NULL,current_source=NULL,bookmark=NULL WHERE id='chair'", parameters: nil)
            let empty = try await reader.readHistory(accountId: account, principalId: principal, itemId: item)
            #expect(empty.details?.notes == "" && empty.details?.displayName == "Chair")
            #expect(empty.details?.displaySource == " Vendor " && empty.details?.isBookmarked == nil)
            await #expect(throws: CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement) {
                try await reader.readHistory(accountId: account, principalId: principal, itemId: ItemID(validating: "missing"))
            }
            _ = try await db.execute(sql: "UPDATE spike_items SET account_id='foreign' WHERE id='chair'", parameters: nil)
            await #expect(throws: CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement) {
                try await reader.readHistory(accountId: account, principalId: principal, itemId: item)
            }
        }) { db in
            let reader = CurrentItemPlacementLocalReader(database: db)
            #expect(try await reader.readHistory(accountId: account, principalId: principal, itemId: item).details?.notes == nil)
            _ = try await db.execute(sql: "UPDATE spike_items SET name='',sku=' SKU ',source=' Vendor ',current_source='',notes=?,workflow_status='to-purchase',bookmark=1,created_at='2026-01-01T12:34:56.123456789Z' WHERE id='chair'", parameters: ["  Notes\nsecond line  "])
        }
    }

    @Test("One history watch delivers descriptive changes and rejects removed Items")
    func descriptiveHistoryWatch() async throws {
        try await withDatabase { db in
            let reader = CurrentItemPlacementLocalReader(database: db)
            let item = try ItemID(validating: "chair")
            var iterator = try reader.watchHistory(accountId: account, principalId: principal, itemId: item).makeAsyncIterator()
            let initial = try await iterator.next()
            #expect(initial?.first?.details?.notes == nil)
            _ = try await db.execute(sql: "UPDATE spike_items SET notes='Updated',source='Original',current_source='Immediate' WHERE id='chair'", parameters: nil)
            var changed = false
            while let rows = try await iterator.next() {
                if rows.first?.details?.notes == "Updated" {
                    #expect(rows.first?.details?.source == "Original")
                    #expect(rows.first?.details?.displaySource == "Immediate")
                    changed = true; break
                }
            }
            #expect(changed)
            _ = try await db.execute(sql: "DELETE FROM spike_items WHERE id='chair'", parameters: nil)
            await #expect(throws: CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement) {
                while try await iterator.next() != nil { }
            }
        }
    }

    @Test("Image count is explicit scoped metadata, survives restart and never invents No Image")
    func imageCountMetadata() async throws {
        try await withDatabase(reopen: { db in
            let reader = CurrentItemPlacementLocalReader(database: db)
            #expect(try await reader.readSnapshot(accountId: account,principalId: principal,scope: .project(project)).rows.first?.imageCount == 2)
            for sql in [
                "UPDATE item_image_sets SET revision='0'",
                "UPDATE item_image_sets SET revision='9223372036854775808'",
                "UPDATE item_image_sets SET revision='1',expected_count=-1",
                "UPDATE item_image_sets SET expected_count=0,account_id='foreign'",
                "DELETE FROM item_image_sets"
            ] {
                _ = try await db.execute(sql: sql,parameters: nil)
                #expect(try await reader.readSnapshot(accountId: account,principalId: principal,scope: .project(project)).rows.first?.imageCount == nil)
            }
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed'",parameters: nil)
            await #expect(throws: CurrentItemPlacementReadFailure.accountUnavailable) {
                try await reader.readSnapshot(accountId: account,principalId: principal,scope: .project(project))
            }
        }) { db in
            let reader = CurrentItemPlacementLocalReader(database: db)
            #expect(try await reader.readSnapshot(accountId: account,principalId: principal,scope: .project(project)).rows.first?.imageCount == nil)
            _ = try await db.execute(sql: "INSERT INTO item_image_sets(id,account_id,item_id,revision,expected_count) VALUES('chair','account-item','chair','1',0)",parameters: nil)
            #expect(try await reader.readSnapshot(accountId: account,principalId: principal,scope: .project(project)).rows.first?.imageCount == 0)
            _ = try await db.execute(sql: "UPDATE item_image_sets SET revision='2',expected_count=2",parameters: nil)
            // No references or bytes are needed to know the authoritative count.
        }
    }

    @Test("Original source and immediate origin stay distinct across encrypted restart")
    func sourceOriginMetadata() async throws {
        try await withDatabase(reopen: { db in
            let reader = CurrentItemPlacementLocalReader(database: db)
            let row = try #require(try await reader.readSnapshot(accountId: account, principalId: principal,
                scope: .project(project)).rows.first)
            #expect(row.source == " Original vendor ")
            #expect(row.currentSource == "Design Inventory")
            _ = try await db.execute(sql: "UPDATE spike_items SET current_source='',revision=2 WHERE id='chair'", parameters: nil)
            let blank = try #require(try await reader.readSnapshot(accountId: account, principalId: principal,
                scope: .project(project)).rows.first)
            #expect(blank.currentSource == "")
            #expect(blank.source == " Original vendor ")
            _ = try await db.execute(sql: "UPDATE spike_items SET current_source=NULL,revision=3 WHERE id='chair'", parameters: nil)
            #expect(try await reader.readSnapshot(accountId: account, principalId: principal,
                scope: .project(project)).rows.first?.currentSource == nil)
        }) { db in
            let absent = try #require(try await CurrentItemPlacementLocalReader(database: db)
                .readSnapshot(accountId: account, principalId: principal, scope: .project(project)).rows.first)
            #expect(absent.source == nil && absent.currentSource == nil)
            _ = try await db.execute(sql: "UPDATE spike_items SET source=' Original vendor ',current_source='Design Inventory' WHERE id='chair'", parameters: nil)
        }
    }

    @Test("Raw workflow and nullable bookmark survive encrypted restart without accounting inference")
    func workflowBookmarkMetadata() async throws {
        try await withDatabase(reopen: { db in
            let reader = CurrentItemPlacementLocalReader(database: db)
            let row = try #require(try await reader.readSnapshot(accountId: account, principalId: principal,
                scope: .project(project)).rows.first)
            #expect(row.workflowStatusRaw == "  legacy sold  ")
            #expect(row.isBookmarked == true)
            _ = try await db.execute(sql: "UPDATE spike_items SET workflow_status='returned',bookmark=0,revision=2 WHERE id='chair'", parameters: nil)
            let updated = try #require(try await reader.readSnapshot(accountId: account, principalId: principal,
                scope: .project(project)).rows.first)
            #expect(updated.workflowStatusRaw == "returned")
            #expect(updated.isBookmarked == false)
            _ = try await db.execute(sql: "UPDATE spike_items SET bookmark=2 WHERE id='chair'", parameters: nil)
            await #expect(throws: CurrentItemPlacementReadFailure.incompleteOrConflictingPlacement) {
                try await reader.readSnapshot(accountId: account, principalId: principal, scope: .project(project))
            }
        }) { db in
            let absent = try #require(try await CurrentItemPlacementLocalReader(database: db)
                .readSnapshot(accountId: account, principalId: principal, scope: .project(project)).rows.first)
            #expect(absent.workflowStatusRaw == nil && absent.isBookmarked == nil)
            _ = try await db.execute(sql: "UPDATE spike_items SET workflow_status='  legacy sold  ',bookmark=1 WHERE id='chair'", parameters: nil)
        }
    }

    @Test("Space choices retain empty active and referenced archived parents across encrypted restart")
    func scopedSpaceChoices() async throws {
        try await withDatabase(reopen: { db in
            let snapshot = try await CurrentItemPlacementLocalReader(database: db)
                .readSnapshot(accountId: account, principalId: principal, scope: .project(project))
            #expect(snapshot.spaces.map(\.id.rawValue) == ["empty", "room"])
            #expect(snapshot.spaces.first?.displayName == "Empty room")
            #expect(snapshot.spaces.last?.isArchived == true)
            #expect(snapshot.rows.map(\.spaceId?.rawValue) == ["room"])
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed' WHERE id='member'", parameters: nil)
            await #expect(throws: CurrentItemPlacementReadFailure.accountUnavailable) {
                try await CurrentItemPlacementLocalReader(database: db)
                    .readSnapshot(accountId: account, principalId: principal, scope: .project(project))
            }
        }) { db in
            _ = try await db.execute(sql: "UPDATE spike_spaces SET lifecycle='archived',display_name='Archived room' WHERE id='room'", parameters: nil)
            for sql in [
                "INSERT INTO spike_spaces(id,account_id,scope_kind,project_id,display_name,lifecycle) VALUES('empty','account-item','project','project-item','Empty room','active')",
                "INSERT INTO spike_spaces(id,account_id,scope_kind,project_id,display_name,lifecycle) VALUES('unused','account-item','project','project-item','Unused archive','archived')",
                "INSERT INTO spike_spaces(id,account_id,scope_kind,project_id,display_name,lifecycle) VALUES('foreign','other','project','project-item','Foreign room','active')",
                "INSERT INTO spike_spaces(id,account_id,scope_kind,project_id,display_name,lifecycle) VALUES('elsewhere','account-item','project','other-project','Other Project','active')",
                "INSERT INTO spike_spaces(id,account_id,scope_kind,display_name,lifecycle) VALUES('inventory-empty','account-item','business_inventory','Empty warehouse','active')"
            ] { _ = try await db.execute(sql: sql, parameters: nil) }
            let reader = CurrentItemPlacementLocalReader(database: db)
            let snapshot = try await reader.readSnapshot(accountId: account, principalId: principal, scope: .project(project))
            #expect(snapshot.spaces.map(\.id.rawValue) == ["empty", "room"])
            let inventory = try await reader.readSnapshot(accountId: account, principalId: principal, scope: .businessInventory)
            #expect(inventory.rows.isEmpty)
            #expect(inventory.spaces.map(\.id.rawValue) == ["inventory-empty"])
            await #expect(throws: CurrentItemPlacementReadFailure.accountUnavailable) {
                try await reader.readSnapshot(accountId: account, principalId: PrincipalID(validating: "foreign"), scope: .project(project))
            }
        }
    }

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
