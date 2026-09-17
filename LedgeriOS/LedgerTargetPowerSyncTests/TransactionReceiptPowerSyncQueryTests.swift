import Foundation
import LedgerTargetCore
import PowerSync
import Testing
@testable import LedgerTargetPowerSync

@Suite("Downloaded Transaction receipt evidence", .serialized)
struct TransactionReceiptPowerSyncQueryTests {
    @Test(arguments: [false, true])
    func completedScopeSurvivesOfflineCategoryEditAndEncryptedReopen(inventory: Bool) async throws {
        let account = try AccountID(validating: "receipt-account")
        let principal = try PrincipalID(validating: "receipt-member")
        let transactionId = try TransactionID(validating: "receipt")
        let scope: TransactionScope = inventory ? .businessInventory(accountId: account) : .project(
            accountId: account, projectId: try ProjectID(validating: "project"), clientId: try ClientID(validating: "client"))
        let identity = TransactionReceiptStreamIdentity(scope: scope)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("receipt-reopen-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("ledger.sqlite").path
        let key = try LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "5a", count: 32))
        var db = try LedgerPowerSyncDatabaseFactory.open(absolutePath: path, encryptionKey: key)
        func read(_ database: any PowerSyncDatabaseProtocol) async throws -> TransactionReceiptSnapshot {
            try await TransactionReceiptPowerSyncQuery(database: database, principalId: principal, scope: scope)
                .read(transactionId: transactionId)
        }
        func detail(_ database: any PowerSyncDatabaseProtocol) async throws -> TransactionDetailSnapshot {
            try await TransactionDetailPowerSyncQuery(database: database, principalId: principal, scope: scope)
                .read(transactionId: transactionId)
        }
        func attachments(_ database: any PowerSyncDatabaseProtocol,
                         section: TransactionAttachmentSection = .receipts) async throws -> DownloadedTransactionAttachments {
            try await TransactionAttachmentLocalReader(database: database, principalId: principal, scope: scope)
                .read(transactionId: transactionId, section: section)
        }
        func export(_ database: any PowerSyncDatabaseProtocol, ids: [TransactionID]? = nil) async throws -> TransactionExportSnapshot {
            try await TransactionDetailPowerSyncQuery(database: database, principalId: principal, scope: scope)
                .readTransactionExport(scope: scope, orderedTransactionIDs: ids, asOf: .init(validating: 1_800_000_000_000))
        }
        func json(_ value: Any) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
        }
        do {
            let subscription = try await db.syncStream(name: identity.name, params: identity.parameters).subscribe()
            let projectsSubscription = try await db.syncStream(name: "spike_projects", params: nil).subscribe()
            let params = try JSONSerialization.jsonObject(with: JSONEncoder().encode(identity.parameters))
            let schema = try JSONSerialization.jsonObject(with: JSONEncoder().encode(LedgerPowerSyncSchema.schema))
            let facts: [(String, String, [String: Any])] = [
                ("spike_projects", "project", ["account_id": account.rawValue, "client_id": "client",
                    "display_name": "Export project", "lifecycle": "active", "revision": 1]),
                ("spike_account_memberships", "membership", ["account_id": account.rawValue,
                    "principal_id": principal.rawValue, "state": "active", "financial_access": "full"]),
                ("spike_budget_categories", "category", ["account_id": account.rawValue, "display_name": "Items",
                    "kind": "itemized", "lifecycle": "active", "is_system": 0, "excludes_from_overall_budget": 0,
                    "presentation_order": 0, "revision": 1]),
                ("spike_transactions", "receipt", ["account_id": account.rawValue,
                    "project_id": scope.projectId?.rawValue as Any? ?? NSNull(),
                    "client_id": scope.clientId?.rawValue as Any? ?? NSNull(),
                    "scope_kind": inventory ? "business_inventory" : "project",
                    "origin": "vendor_payment", "type": "purchase", "role": "standalone",
                    "amount_minor_units": "3050", "currency": "USD", "category_id": "category",
                    "source": "Café vendor", "transaction_date": "2024-02-29", "created_at_ms": "1709251200123",
                    "notes": "Preserved notes", "payment_method": "Company card", "has_email_receipt": 0,
                    "details_revision": "9007199254740993",
                    "legacy_subtotal_minor_units": "9007199254740993", "legacy_tax_rate_pct": "8.12345678901234567890",
                    "non_item_receipt_lines": try json([
                        ["id": "tax", "description": "Tax", "amountMinorUnits": "100", "effect": "increase", "quantity": "10"],
                        ["id": "discount", "description": "Discount", "amountMinorUnits": "50", "effect": "decrease"]])]),
                // No Item connection: financial history belongs to the Project.
                ("spike_transactions", "payment", ["account_id": account.rawValue,
                    "project_id": "project", "client_id": "client", "scope_kind": "project",
                    "origin": "firebase_client_payment", "type": "purchase", "role": "standalone",
                    "amount_minor_units": "9007199254740993", "currency": "USD", "source": "Client payment"]),
                ("transaction_receipt_items", "link-a", ["account_id": account.rawValue, "transaction_id": "receipt",
                    "item_id": "a", "amount_minor_units": "1000", "currency": "USD", "membership_kind": "linked"]),
                ("transaction_receipt_items", "link-b", ["account_id": account.rawValue, "transaction_id": "receipt",
                    "item_id": "b", "amount_minor_units": "2000", "currency": "USD", "membership_kind": "sold"]),
                ("spike_items", "b", ["account_id": account.rawValue, "name": "Historical chair", "sku": "CHAIR-2", "source": "Original vendor", "current_source": "Display vendor"]),
                ("spike_item_placements", "p-a", ["account_id": account.rawValue, "item_id": "a",
                    "scope_kind": "project", "project_id": "project"]),
                ("spike_item_placements", "p-b", ["account_id": account.rawValue, "item_id": "b",
                    "scope_kind": "project", "project_id": "project", "space_id": "current-space"]),
                ("spike_spaces", "current-space", ["account_id": account.rawValue, "scope_kind": "project",
                    "project_id": "project", "display_name": "Current room", "lifecycle": "active", "revision": 1]),
                ("item_image_sets", "b", ["account_id": account.rawValue, "item_id": "b", "revision": "1", "expected_count": 2]),
                ("spike_item_project_categories", "p-a", ["account_id": account.rawValue, "item_id": "a",
                    "project_id": "project", "category_id": "category", "revision": 1])
            ]
            let rows = try facts.enumerated().map { index, fact -> [String: Any] in
                ["checksum": 0, "op_id": String(index + 1), "object_id": fact.1,
                 "object_type": fact.0, "op": "PUT", "data": try json(fact.2)]
            }
            let controls: [(String, String?)] = [
                ("start", try json(["parameters": [:], "schema": schema, "include_defaults": false,
                    "active_streams": [["name": identity.name, "params": params], ["name": "spike_projects", "params": NSNull()]],
                    "app_metadata": [:], "checkpoint_mode": "legacy"])),
                ("connection", "established"),
                ("line_text", try json(["checkpoint": ["last_op_id": "5", "buckets": [
                    ["bucket": "receipt-bucket", "priority": 3, "checksum": 0, "subscriptions": [["sub": 0], ["sub": 1]]]],
                    "streams": [["name": identity.name, "is_default": false, "errors": []],
                                ["name": "spike_projects", "is_default": false, "errors": []]]]])),
                ("line_text", try json(["data": ["bucket": "receipt-bucket", "data": rows, "has_more": false]]))
            ]
            for (operation, parameter) in controls {
                _ = try await db.writeTransaction { tx in
                    try tx.getAll(sql: "SELECT powersync_control(?,?) AS result", parameters: [operation, parameter]) {
                        try $0.getString(name: "result")
                    }
                }
            }
            // Receiving rows alone is not a completed download.
            await #expect(throws: (any Error).self) { try await read(db) }
            await #expect(throws: (any Error).self) { try await detail(db) }
            await #expect(throws: (any Error).self) { try await attachments(db) }
            await #expect(throws: (any Error).self) { try await export(db) }
            for (operation, parameter) in [("line_text", try json(["checkpoint_complete": ["last_op_id": "5"]]) as String?), ("stop", nil)] {
                _ = try await db.writeTransaction { tx in
                    try tx.getAll(sql: "SELECT powersync_control(?,?) AS result", parameters: [operation, parameter]) {
                        try $0.getString(name: "result")
                    }
                }
            }
            let original = try await read(db)
            let originalDetail = try await detail(db)
            #expect(originalDetail.detailsRevision == 9_007_199_254_740_993)
            #expect(try await attachments(db).isComplete == false)
            _ = try await db.execute(sql: "INSERT INTO transaction_attachment_sets(id,account_id,transaction_id,section,revision,expected_count) VALUES('receipt-set',?,'receipt','receipts','1',0)", parameters: [account.rawValue])
            #expect(try await attachments(db).isComplete)
            #expect(try await attachments(db, section: .other).isComplete == false)
            _ = try await db.execute(sql: "UPDATE transaction_attachment_sets SET expected_count=1", parameters: nil)
            _ = try await db.execute(sql: "INSERT INTO transaction_attachment_references(id,account_id,transaction_id,section,attachment_id,set_revision,position,is_primary,file_name) VALUES('pdf-reference',?,'receipt','receipts','pdf-object','1',0,1,'Vendor receipt.pdf')", parameters: [account.rawValue])
            #expect(try await attachments(db).isComplete == false)
            let hash = String(repeating: "a", count: 64)
            _ = try await db.execute(sql: "UPDATE transaction_attachment_references SET content_sha256=?,byte_count='123',media_type='application/pdf',storage_path=? WHERE id='pdf-reference'", parameters: [hash, "accounts/\(account.rawValue)/attachments/pdf-object/\(hash)"])
            let originalAttachments = try await attachments(db)
            #expect(originalAttachments.isComplete && originalAttachments.attachments.count == 1)
            #expect(originalAttachments.attachments.first?.fileName == "Vendor receipt.pdf")
            #expect(originalAttachments.attachments.first?.object.mediaType == "application/pdf")
            try await verifyAttachmentByteAuthorization(database: db, principal: principal, catalog: originalAttachments)
            // A new marker never exposes the old revision, even if its bytes remain cached.
            _ = try await db.execute(sql: "UPDATE transaction_attachment_sets SET revision='2'", parameters: nil)
            #expect(try await attachments(db).attachments.isEmpty)
            #expect(try await attachments(db).isComplete == false)
            _ = try await db.execute(sql: "UPDATE transaction_attachment_references SET set_revision='2'", parameters: nil)
            #expect(try await attachments(db).isComplete)
            for badUpdate in ["UPDATE transaction_attachment_references SET storage_path='accounts/foreign/attachments/pdf-object/invalid'",
                              "UPDATE transaction_attachment_references SET media_type='text/html'",
                              "UPDATE transaction_attachment_references SET media_type='application/pdf',byte_count='00123'"] {
                _ = try await db.execute(sql: "UPDATE transaction_attachment_references SET storage_path=?", parameters: ["accounts/\(account.rawValue)/attachments/pdf-object/\(hash)"])
                _ = try await db.execute(sql: badUpdate, parameters: nil)
                #expect(try await attachments(db).attachments.isEmpty)
                #expect(try await attachments(db).isComplete == false)
            }
            _ = try await db.execute(sql: "UPDATE transaction_attachment_references SET byte_count='123',storage_path=?", parameters: ["accounts/\(account.rawValue)/attachments/pdf-object/\(hash)"])
            _ = try await db.execute(sql: """
                INSERT INTO transaction_attachment_references(id,account_id,transaction_id,section,attachment_id,set_revision,
                  position,is_primary,file_name,content_sha256,byte_count,media_type,storage_path)
                SELECT 'duplicate',account_id,transaction_id,section,attachment_id,set_revision,
                  position,is_primary,file_name,content_sha256,byte_count,media_type,storage_path
                FROM transaction_attachment_references WHERE id='pdf-reference'
                """, parameters: nil)
            #expect(try await attachments(db).attachments.isEmpty)
            _ = try await db.execute(sql: "DELETE FROM transaction_attachment_references WHERE id='duplicate'", parameters: nil)
            let currentAttachments = try await attachments(db)
            #expect(currentAttachments.isComplete && currentAttachments.revision == 2)
            try await verifyAttachmentWatch(database: db, principal: principal, catalog: currentAttachments)
            #expect(originalDetail.receipt == original && originalDetail.linkedItemCount == 1)
            let browserRows = try await TransactionDetailPowerSyncQuery(database: db, principalId: principal, scope: scope)
                .readRows(transactionId: nil)
            #expect(browserRows.map(\.transactionId.rawValue) == (inventory ? ["receipt"] : ["payment", "receipt"]))
            if !inventory {
                #expect(browserRows.first?.amount.minorUnits == 9007199254740993)
                #expect(browserRows.first?.category == nil && browserRows.first?.source == "Client payment")
                let exported = try await export(db)
                #expect(exported.rows == browserRows)
                #expect(originalDetail.currentItemCategories?.map(\.itemId.rawValue) == ["a"])
                #expect(try TransactionExportValues.cell(fieldID: "itemCategories", row: originalDetail) == .text("category"))
                _ = try await db.execute(sql: "UPDATE spike_item_project_categories SET category_id='missing' WHERE id='p-a'", parameters: nil)
                let unknown = try await detail(db)
                #expect(unknown.currentItemCategories?.count == 1 && unknown.currentItemCategories?.first?.categoryId == nil)
                #expect(throws: TransactionExportValues.Failure.incompleteField("itemCategories")) {
                    try TransactionExportValues.cell(fieldID: "itemCategories", row: unknown)
                }
                #expect(try await export(db).reference != exported.reference)
                _ = try await db.execute(sql: "UPDATE spike_item_project_categories SET category_id='category' WHERE id='p-a'", parameters: nil)
                _ = try await db.execute(sql: "UPDATE spike_item_placements SET ended_at='2026-09-01' WHERE id='p-a'", parameters: nil)
                let departed = try await detail(db)
                #expect(departed.currentItemCategories == [] && departed.receipt == original)
                _ = try await db.execute(sql: "UPDATE spike_item_placements SET ended_at=NULL WHERE id='p-a'", parameters: nil)
                #expect(try await export(db, ids: [transactionId]).rows.map(\.transactionId) == [transactionId])
                #expect(try await export(db, ids: []).rows.isEmpty)
                // Negative ordering test only: real-service coverage below is
                // separate from this injected one-microsecond race.
                let checkpoints = try await db.getAll(sql: "SELECT stream_name,last_synced_at FROM ps_stream_subscriptions",
                    parameters: nil) { (try $0.getString(name: "stream_name"), try $0.getInt64(name: "last_synced_at")) }
                let directoryTime = try #require(checkpoints.first { $0.0 == "spike_projects" }?.1)
                let receiptTime = try #require(checkpoints.first { $0.0 == identity.name }?.1)
                _ = try await db.execute(sql: "UPDATE ps_stream_subscriptions SET last_synced_at=? WHERE stream_name='spike_projects'",
                    parameters: [receiptTime + 1])
                await #expect(throws: PropertyManagementReportFailure.incompleteReadiness) { try await export(db) }
                _ = try await db.execute(sql: "UPDATE ps_stream_subscriptions SET last_synced_at=? WHERE stream_name='spike_projects'",
                    parameters: [directoryTime])
                _ = try await db.execute(sql: "UPDATE spike_transactions SET category_id='missing-category' WHERE id='receipt'", parameters: nil)
                await #expect(throws: PropertyManagementReportFailure.incompleteReadiness) { try await export(db) }
                _ = try await db.execute(sql: "UPDATE spike_transactions SET category_id='category' WHERE id='receipt'", parameters: nil)
                _ = try await db.execute(sql: "UPDATE spike_transactions SET origin='unsupported' WHERE id='payment'", parameters: nil)
                await #expect(throws: TransactionDetailSnapshot.Failure.invalidEvidence) { try await export(db) }
                _ = try await db.execute(sql: "UPDATE spike_transactions SET origin='firebase_client_payment' WHERE id='payment'", parameters: nil)
                _ = try await db.execute(sql: "UPDATE spike_projects SET client_id='wrong-client' WHERE id='project'", parameters: nil)
                await #expect(throws: TransactionExportSnapshot.Failure.wrongScope) { try await export(db) }
                _ = try await db.execute(sql: "UPDATE spike_projects SET client_id='client',lifecycle='archived' WHERE id='project'", parameters: nil)
                #expect(try await export(db).rows == browserRows)
            } else {
                await #expect(throws: TransactionExportSnapshot.Failure.wrongScope) { try await export(db) }
            }
            #expect(originalDetail.source == "Café vendor" && originalDetail.transactionDate == "2024-02-29")
            #expect(originalDetail.createdAtMilliseconds == 1709251200123 && originalDetail.hasEmailReceipt == false)
            #expect(originalDetail.legacySubtotal?.minorUnits == 9_007_199_254_740_993)
            #expect(originalDetail.legacyTaxRatePct == "8.12345678901234567890")
            #expect(originalDetail.notes == "Preserved notes" && originalDetail.paymentMethod == "Company card")
            #expect(originalDetail.classification.scope == scope)
            #expect(original.auditStatus == .balanced)
            #expect(original.reconstruction?.physicalItemTotal.minorUnits == 3000)
            #expect(original.items.last?.membership == .sold)
            #expect(original.items.last?.name == "Historical chair" && original.items.last?.sku == "CHAIR-2")
            #expect(original.items.last?.source == "Original vendor" && original.items.last?.currentSource == "Display vendor")
            #expect(original.items.last?.currentSpaceName == "Current room" && original.items.last?.imageCount == 2)
            #expect(original.items.first?.name == nil)
            let command = try CategoryManagementCommand(
                operationId: CategoryManagementOperationIdentity.make(accountId: account, uuid: UUID()),
                accountId: account, actorPrincipalId: principal, capturedAt: Date(),
                payload: .init(action: .edit, categoryId: BudgetCategoryID(validating: "category"), expectedRevision: 1,
                    name: BudgetCategoryName(validating: "Items"), kind: .general, excludesFromOverallBudget: false))
            _ = try await CategoryManagementPowerSyncStore(database: db, accountId: account, principalId: principal,
                accessFence: LedgerWorkspaceAccessFence(), isDirectoryComplete: { true }).submit(command)
            #expect(try await read(db).auditStatus == .notApplicable)
            #expect(try await detail(db).category?.kind == .general)
            try await subscription.unsubscribe()
            try await projectsSubscription.unsubscribe()
            try await db.close()
            db = try LedgerPowerSyncDatabaseFactory.open(absolutePath: path, encryptionKey: key)
            let reopenedSubscription = try await db.syncStream(name: identity.name, params: identity.parameters).subscribe()
            let reopenedProjects = try await db.syncStream(name: "spike_projects", params: nil).subscribe()
            let reopened = try await read(db)
            let reopenedDetail = try await detail(db)
            #expect(reopenedDetail.detailsRevision == originalDetail.detailsRevision)
            #expect(try await attachments(db) == currentAttachments)
            #expect(reopenedDetail.source == originalDetail.source && reopenedDetail.notes == originalDetail.notes)
            #expect(reopenedDetail.transactionDate == originalDetail.transactionDate)
            #expect(reopenedDetail.createdAtMilliseconds == originalDetail.createdAtMilliseconds)
            #expect(reopenedDetail.hasEmailReceipt == originalDetail.hasEmailReceipt)
            #expect(reopenedDetail.legacySubtotal == originalDetail.legacySubtotal)
            #expect(reopenedDetail.legacyTaxRatePct == originalDetail.legacyTaxRatePct)
            #expect(reopenedDetail.category?.kind == .general)
            let reopenedRows = try await TransactionDetailPowerSyncQuery(database: db, principalId: principal, scope: scope)
                .readRows(transactionId: nil)
            #expect(reopenedRows.map(\.transactionId) == browserRows.map(\.transactionId))
            if !inventory { #expect(reopenedRows.first == browserRows.first) }
            if !inventory {
                let reopenedExport = try await export(db)
                #expect(reopenedExport.rows == reopenedRows)
                #expect(reopenedExport.rows.last?.category?.kind == .general)
            }
            let wrongScope = TransactionScope.project(accountId: account,
                projectId: try ProjectID(validating: "another-project"), clientId: try ClientID(validating: "another-client"))
            await #expect(throws: (any Error).self) {
                try await TransactionDetailPowerSyncQuery(database: db, principalId: principal, scope: wrongScope)
                    .read(transactionId: transactionId)
            }
            await #expect(throws: (any Error).self) {
                try await TransactionAttachmentLocalReader(database: db, principalId: principal, scope: wrongScope)
                    .read(transactionId: transactionId, section: .receipts)
            }
            #expect(reopened.auditStatus == .notApplicable && reopened.items == original.items)
            #expect(reopened.reconstruction == original.reconstruction)
            let updates = AsyncThrowingStream<TransactionReceiptUpdate, Error>.makeStream()
            let consumer = Task { [database = db] in
                do {
                    try await TransactionDetailPowerSyncQuery(database: database, principalId: principal, scope: scope)
                        .watch { value in
                            switch value {
                            case .partial(let rows), .ready(let rows):
                                if let receipt = rows.first(where: { $0.transactionId == transactionId })?.receipt {
                                    updates.continuation.yield(.ready(receipt))
                                } else { updates.continuation.yield(.unavailable) }
                            case .incomplete: updates.continuation.yield(.incomplete)
                            case .unavailable: updates.continuation.yield(.unavailable)
                            }
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
            #expect(try await iterator.next() == .ready(reopened))
            // Rejection restores authoritative applicability, without touching receipt facts.
            _ = try await db.execute(sql: "UPDATE spike_local_operations SET local_state='rejected' WHERE id=?",
                parameters: [command.envelope.operationId.rawValue])
            #expect(try await read(db).auditStatus == .balanced)
            while true {
                if case .ready(let value) = try #require(try await iterator.next()), value.auditStatus == .balanced { break }
            }
            _ = try await db.execute(sql: "UPDATE spike_items SET name='Renamed chair',sku='NEW-SKU' WHERE id='b'", parameters: nil)
            while true {
                if case .ready(let value) = try #require(try await iterator.next()), value.items.last?.name == "Renamed chair" {
                    #expect(value.items.last?.sku == "NEW-SKU")
                    #expect(value.reconstruction == original.reconstruction)
                    break
                }
            }
            // A stale or foreign physical row must not supply another Account's label.
            _ = try await db.execute(sql: "UPDATE spike_items SET account_id='foreign' WHERE id='b'", parameters: nil)
            while true {
                if case .ready(let value) = try #require(try await iterator.next()), value.items.last?.name == nil {
                    #expect(value.items.last?.sku == nil)
                    #expect(value.reconstruction == original.reconstruction)
                    break
                }
            }
            _ = try await db.execute(sql: "UPDATE transaction_receipt_items SET amount_minor_units=NULL WHERE id='link-b'", parameters: nil)
            #expect(try await read(db).auditStatus == .incompleteEvidence)
            while true {
                if case .ready(let value) = try #require(try await iterator.next()), value.auditStatus == .incompleteEvidence { break }
            }
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET financial_access='restricted'", parameters: nil)
            _ = try await db.execute(sql: "UPDATE spike_budget_categories SET kind='fee'", parameters: nil)
            await #expect(throws: (any Error).self) { try await read(db) }
            await #expect(throws: TransactionDetailSnapshot.Failure.scopeMismatch) { try await detail(db) }
            await #expect(throws: DownloadedTransactionAttachments.Failure.unavailable) { try await attachments(db) }
            #expect(try await TransactionDetailPowerSyncQuery(database: db, principalId: principal, scope: scope)
                .readRows(transactionId: nil).isEmpty)
            while try #require(try await iterator.next()) != .unavailable { }
            _ = try await db.execute(sql: "UPDATE spike_budget_categories SET kind='general'", parameters: nil)
            #expect(try await read(db).auditStatus == .notApplicable)
            #expect(try await attachments(db) == currentAttachments)
            while true {
                if case .ready(let value) = try #require(try await iterator.next()), value.auditStatus == .notApplicable { break }
            }
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed'", parameters: nil)
            await #expect(throws: CategoryManagementFailure.categoryUnavailable) { try await read(db) }
            await #expect(throws: CategoryManagementFailure.categoryUnavailable) { try await detail(db) }
            await #expect(throws: CategoryManagementFailure.categoryUnavailable) { try await attachments(db) }
            if !inventory {
                await #expect(throws: CategoryManagementFailure.categoryUnavailable) { try await export(db) }
            }
            await #expect(throws: CategoryManagementFailure.categoryUnavailable) {
                while let _ = try await iterator.next() { }
            }
            } catch {
                consumer.cancel(); _ = await consumer.result; deadline.cancel()
                throw error
            }
            consumer.cancel(); _ = await consumer.result; deadline.cancel()
            try await reopenedSubscription.unsubscribe()
            try await reopenedProjects.unsubscribe()
            try await db.close()
        } catch { try? await db.close(); throw error }
    }
}

// Reuse the completed, encrypted Project/Inventory fixture above. These hooks
// deterministically change authorization inside each byte await; the real vault's
// hash/encryption/restart behavior is covered by downloadedPDFRestart.
private func verifyAttachmentByteAuthorization(database: any PowerSyncDatabaseProtocol,
    principal: PrincipalID, catalog: DownloadedTransactionAttachments) async throws {
    let attachment = try #require(catalog.attachments.first)
    let reader = TransactionAttachmentLocalReader(database: database, principalId: principal, scope: catalog.scope)
    let bytes = Data(repeating: 7, count: 123)
    let cache = TransactionAttachmentByteTestCache()
    #expect(try await reader.load(catalog: catalog, attachment: attachment, cache: cache,
        download: nil, authorizeAccess: {}) == nil)
    #expect(try await reader.load(catalog: catalog, attachment: attachment, cache: cache,
        download: { _ in bytes }, authorizeAccess: {}) == bytes)
    #expect(try await reader.load(catalog: catalog, attachment: attachment, cache: cache,
        download: nil, authorizeAccess: {}) == bytes)
    #expect(await cache.writes == 1)

    for phase in ["cache-read", "download", "cache-write"] {
        for change in ["revision", "reference", "membership", "category", "parent", "access"] {
            let access = TransactionAttachmentByteTestAccess()
            let invalidate: @Sendable () async throws -> Void = {
                switch change {
                case "revision":
                    _ = try await database.execute(sql: "UPDATE transaction_attachment_sets SET revision='2'", parameters: nil)
                case "reference":
                    _ = try await database.execute(sql: "UPDATE transaction_attachment_references SET file_name='Replaced.pdf'", parameters: nil)
                case "membership":
                    _ = try await database.execute(sql: "UPDATE spike_account_memberships SET state='removed'", parameters: nil)
                case "category":
                    _ = try await database.execute(sql: "UPDATE spike_account_memberships SET financial_access='restricted'", parameters: nil)
                    _ = try await database.execute(sql: "UPDATE spike_budget_categories SET kind='fee'", parameters: nil)
                case "parent":
                    _ = try await database.execute(sql: "UPDATE spike_transactions SET account_id='foreign' WHERE id='receipt'", parameters: nil)
                default: await access.remove()
                }
            }
            let changingCache = TransactionAttachmentByteTestCache(bytes: phase == "cache-read" ? bytes : nil,
                onRead: phase == "cache-read" ? invalidate : nil,
                onWrite: phase == "cache-write" ? invalidate : nil)
            await #expect(throws: (any Error).self) {
                try await reader.load(catalog: catalog, attachment: attachment, cache: changingCache,
                    download: { _ in
                        if phase == "download" { try await invalidate() }
                        return bytes
                    }, authorizeAccess: { try await access.check() })
            }
            // Download-time revocation must not populate the cache. A cache write
            // already in flight may finish, but its bytes must never be returned.
            #expect(await changingCache.writes == (phase == "cache-write" ? 1 : 0))
            await #expect(throws: (any Error).self) {
                try await reader.load(catalog: catalog, attachment: attachment, cache: changingCache,
                    download: nil, authorizeAccess: { try await access.check() })
            }
            _ = try await database.execute(sql: "UPDATE transaction_attachment_sets SET revision='1'", parameters: nil)
            _ = try await database.execute(sql: "UPDATE transaction_attachment_references SET file_name='Vendor receipt.pdf'", parameters: nil)
            _ = try await database.execute(sql: "UPDATE spike_account_memberships SET state='active',financial_access='full'", parameters: nil)
            _ = try await database.execute(sql: "UPDATE spike_budget_categories SET kind='itemized'", parameters: nil)
            _ = try await database.execute(sql: "UPDATE spike_transactions SET account_id=? WHERE id='receipt'", parameters: [catalog.scope.accountId.rawValue])
        }
    }
}

private func verifyAttachmentWatch(database: any PowerSyncDatabaseProtocol, principal: PrincipalID,
    catalog: DownloadedTransactionAttachments) async throws {
    let events = AsyncThrowingStream<DownloadedTransactionAttachments?, Error>.makeStream()
    let consumer = Task {
        do {
            try await TransactionAttachmentLocalReader(database: database, principalId: principal, scope: catalog.scope)
                .watch(transactionId: catalog.transactionId, section: catalog.section) { value in
                    events.continuation.yield(value); return true
                }
            events.continuation.finish()
        } catch { events.continuation.finish(throwing: error) }
    }
    let deadline = Task {
        try await Task.sleep(for: .seconds(10))
        consumer.cancel()
    }
    do {
        var iterator = events.stream.makeAsyncIterator()
        #expect(try await iterator.next() == .some(catalog))
        // Parent validation also depends on receipt evidence. Its withdrawal
        // and repair must refresh attachments without a category/reference edit.
        _ = try await database.execute(sql: "UPDATE transaction_receipt_items SET currency='EUR'", parameters: nil)
        while try #require(try await iterator.next()) != nil { }
        _ = try await database.execute(sql: "UPDATE transaction_receipt_items SET currency='USD'", parameters: nil)
        while try #require(try await iterator.next()) == nil { }
        _ = try await database.execute(sql: "UPDATE transaction_attachment_references SET file_name='Updated.pdf'", parameters: nil)
        while try #require(try await iterator.next())?.attachments.first?.fileName != "Updated.pdf" { }
        _ = try await database.execute(sql: "UPDATE transaction_attachment_sets SET revision='3'", parameters: nil)
        while true {
            let event = try #require(try await iterator.next())
            if event?.revision == 3 { #expect(event?.attachments.isEmpty == true && event?.isComplete == false); break }
        }
        _ = try await database.execute(sql: "UPDATE spike_account_memberships SET financial_access='restricted'", parameters: nil)
        _ = try await database.execute(sql: "UPDATE spike_budget_categories SET kind='fee'", parameters: nil)
        while try #require(try await iterator.next()) != nil { }
        _ = try await database.execute(sql: "UPDATE spike_budget_categories SET kind='general'", parameters: nil)
        while try #require(try await iterator.next()) == nil { }
        _ = try await database.execute(sql: "UPDATE spike_account_memberships SET state='removed'", parameters: nil)
        while try #require(try await iterator.next()) != nil { }
    } catch {
        consumer.cancel(); _ = await consumer.result; deadline.cancel(); throw error
    }
    consumer.cancel(); _ = await consumer.result; deadline.cancel()
    _ = try await database.execute(sql: "UPDATE transaction_attachment_sets SET revision='2'", parameters: nil)
    _ = try await database.execute(sql: "UPDATE transaction_attachment_references SET file_name='Vendor receipt.pdf'", parameters: nil)
    _ = try await database.execute(sql: "UPDATE spike_account_memberships SET state='active',financial_access='full'", parameters: nil)
    _ = try await database.execute(sql: "UPDATE spike_budget_categories SET kind='itemized'", parameters: nil)
}

private actor TransactionAttachmentByteTestCache: DownloadedImageCaching {
    var bytes: Data?
    private(set) var writes = 0
    let onRead: (@Sendable () async throws -> Void)?
    let onWrite: (@Sendable () async throws -> Void)?
    init(bytes: Data? = nil, onRead: (@Sendable () async throws -> Void)? = nil,
         onWrite: (@Sendable () async throws -> Void)? = nil) {
        self.bytes = bytes; self.onRead = onRead; self.onWrite = onWrite
    }
    func cachedDownloadedImage(_ reference: DownloadedMediaObjectReference) async throws -> Data? {
        try await onRead?()
        return bytes
    }
    func cacheDownloadedImage(_ bytes: Data, reference: DownloadedMediaObjectReference) async throws {
        writes += 1; self.bytes = bytes
        try await onWrite?()
    }
}

private actor TransactionAttachmentByteTestAccess {
    var removed = false
    func remove() { removed = true }
    func check() throws {
        if removed { throw LedgerOfflineClientRuntimeFailure.runtimeClosed }
    }
}
