import Foundation
import LedgerTargetCore
import PowerSync

/// Reads canonical vendor and imported client payments from the scoped working
/// set. Receipt evidence remains vendor-only; a payment is not a vendor receipt.
/// Transfers/new collection writers still require their owning implementation.
struct TransactionDetailPowerSyncQuery: TransactionDetailReading, TransactionExportReading {
    let database: any PowerSyncDatabaseProtocol
    let principalId: PrincipalID
    let scope: TransactionScope

    func read(transactionId: TransactionID) async throws -> TransactionDetailSnapshot {
        let rows = try await readRows(transactionId: transactionId)
        guard rows.count == 1 else { throw TransactionDetailSnapshot.Failure.scopeMismatch }
        return rows[0]
    }

    func watch(receive: @Sendable @escaping (TransactionBrowserUpdate) async -> Bool) async throws {
        let identity = TransactionReceiptStreamIdentity(scope: scope)
        try await withOwnedSyncStreamWatch(subscribe: {
            try await database.syncStream(name: identity.name, params: identity.parameters).subscribe()
        }, observe: {
            let changes = try database.watch(sql: """
                SELECT EXISTS(SELECT 1 FROM spike_account_memberships WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_transactions WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_budget_categories WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_local_operations WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_operation_results WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM transaction_receipt_items WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_items WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_item_placements WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_item_project_categories WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM item_client_payment_connections WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_spaces WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM item_image_sets WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM collected_invoices WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM collected_invoice_lines WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM ps_stream_subscriptions WHERE stream_name='transaction_receipts')
                """, parameters: Array(repeating: scope.accountId.rawValue, count: 14)) { try $0.getInt(index: 0) }
            for try await _ in changes {
                try Task.checkCancellation()
                let update: TransactionBrowserUpdate
                do {
                    // Implemented origins only, not complete product coverage.
                    update = .partial(try await readRows(transactionId: nil))
                } catch PropertyManagementReportFailure.incompleteReadiness { update = .incomplete }
                guard await receive(update) else { return }
            }
        })
    }

    func readRows(transactionId: TransactionID?) async throws -> [TransactionDetailSnapshot] {
        try await database.readTransaction { transaction in
            try readRows(transaction: transaction, transactionId: transactionId)
        }
    }

    func readRows(transaction: any Transaction, transactionId: TransactionID?,
                          requireCompleteCategories: Bool = false) throws -> [TransactionDetailSnapshot] {
            let full = try CategoryManagementLocalProjection.requireMembership(transaction,
                account: scope.accountId, principal: principalId)
            _ = try PropertyManagementReportPowerSyncQuery.completedStreamCheckpoint(transaction: transaction,
                identity: TransactionReceiptStreamIdentity(scope: scope))
            let categories = try CategoryManagementLocalProjection.read(transaction, account: scope.accountId,
                principal: principalId, fullFinancialAccess: full)
            // One scope-wide read, not a query/subscription per card. Both reads
            // are inside this same SQLite snapshot and completed working set.
            let evidence = try transaction.getAll(sql: """
                SELECT evidence.transaction_id,evidence.item_id,evidence.currency,evidence.amount_minor_units,
                    evidence.membership_kind,COALESCE(item.name,item.description) AS item_name,item.sku AS item_sku,
                    item.source AS item_source,item.current_source AS item_current_source,
                    space.display_name AS current_space_name, CAST(images.expected_count AS TEXT) AS image_count
                FROM transaction_receipt_items evidence
                JOIN spike_transactions receipt ON receipt.account_id=evidence.account_id AND receipt.id=evidence.transaction_id
                LEFT JOIN spike_items item ON item.account_id=evidence.account_id AND item.id=evidence.item_id
                LEFT JOIN spike_item_placements placement ON placement.account_id=evidence.account_id
                    AND placement.item_id=evidence.item_id AND placement.ended_at IS NULL
                LEFT JOIN spike_spaces space ON space.account_id=placement.account_id AND space.id=placement.space_id
                    AND space.scope_kind=placement.scope_kind AND space.project_id IS placement.project_id
                LEFT JOIN item_image_sets images ON images.account_id=evidence.account_id AND images.item_id=evidence.item_id
                WHERE receipt.account_id=? AND receipt.origin='vendor_payment'
                    AND (? IS NULL OR receipt.id=?) AND receipt.scope_kind=? AND receipt.project_id IS ? AND receipt.client_id IS ?
                ORDER BY evidence.transaction_id,evidence.item_id
                """, parameters: [scope.accountId.rawValue, transactionId?.rawValue, transactionId?.rawValue,
                    scope.ownerKind == .project ? "project" : "business_inventory", scope.projectId?.rawValue, scope.clientId?.rawValue]) {
                    cursor -> (String, [String: String?]) in
                    (try cursor.getString(name: "transaction_id"), ["itemId": try cursor.getString(name: "item_id"),
                        "currency": try cursor.getString(name: "currency"),
                        "name": try cursor.getStringOptional(name: "item_name"),
                        "sku": try cursor.getStringOptional(name: "item_sku"),
                        "source": try cursor.getStringOptional(name: "item_source"),
                        "currentSource": try cursor.getStringOptional(name: "item_current_source"),
                        "currentSpaceName": try cursor.getStringOptional(name: "current_space_name"),
                        "imageCount": try cursor.getStringOptional(name: "image_count"),
                        "amountMinorUnits": try cursor.getStringOptional(name: "amount_minor_units"),
                        "membershipKind": try cursor.getString(name: "membership_kind")])
                }
            let itemsByTransaction = Dictionary(grouping: evidence, by: { $0.0 }).mapValues { $0.map { $0.1 } }
            // Current attachment and current category are distinct from retained
            // receipt contributions. One query for the scope, not per exported row.
            let currentCategories = try transaction.getAll(sql: """
                SELECT t.id AS transaction_id,p.item_id,p.id AS placement_id,a.category_id
                FROM spike_transactions t
                JOIN spike_item_placements p ON p.account_id=t.account_id AND p.project_id=t.project_id
                    AND p.scope_kind='project' AND p.ended_at IS NULL
                LEFT JOIN spike_item_project_categories a ON a.account_id=p.account_id AND a.id=p.id
                    AND a.item_id=p.item_id AND a.project_id=p.project_id
                WHERE t.account_id=? AND t.scope_kind='project' AND t.project_id IS ? AND t.client_id IS ?
                    AND (? IS NULL OR t.id=?)
                    AND ((t.origin='vendor_payment' AND EXISTS (
                        SELECT 1 FROM transaction_receipt_items r WHERE r.account_id=t.account_id
                            AND r.transaction_id=t.id AND r.item_id=p.item_id AND r.membership_kind='linked'))
                    OR (t.origin='firebase_client_payment' AND EXISTS (
                        SELECT 1 FROM item_client_payment_connections link WHERE link.account_id=t.account_id
                            AND link.transaction_id=t.id AND link.item_id=p.item_id AND link.placement_id=p.id
                            AND link.project_id=t.project_id AND link.client_id=t.client_id
                            AND link.transaction_type=t.type AND link.transaction_role=t.role AND link.ended_at IS NULL)))
                ORDER BY t.id,p.item_id
                """, parameters: [scope.accountId.rawValue, scope.projectId?.rawValue, scope.clientId?.rawValue,
                    transactionId?.rawValue, transactionId?.rawValue]) { cursor -> (String, [String: String?]) in
                    let categoryId = try cursor.getStringOptional(name: "category_id")
                    return (try cursor.getString(name: "transaction_id"), [
                        "itemId": try cursor.getString(name: "item_id"),
                        "placementId": try cursor.getString(name: "placement_id"),
                        "categoryId": categories.contains(where: { $0.id.rawValue == categoryId }) ? categoryId : nil])
                }
            let categoriesByTransaction = Dictionary(grouping: currentCategories, by: { $0.0 }).mapValues { $0.map { $0.1 } }
            let paymentContents = full && scope.ownerKind == .project
                ? try readPaymentContents(transaction: transaction, transactionId: transactionId) : [:]
            let rows = try transaction.getAll(sql: """
                SELECT id,account_id,project_id,client_id,scope_kind,type,role,origin,
                    amount_minor_units,currency,category_id,source,transaction_date,created_at_ms,
                    notes,payment_method,has_email_receipt,details_revision,non_item_receipt_lines,
                    legacy_subtotal_minor_units,legacy_tax_rate_pct
                FROM spike_transactions WHERE account_id=? AND (? IS NULL OR id=?)
                    AND scope_kind=? AND project_id IS ? AND client_id IS ?
                ORDER BY id
                """, parameters: [scope.accountId.rawValue, transactionId?.rawValue, transactionId?.rawValue,
                    scope.ownerKind == .project ? "project" : "business_inventory",
                    scope.projectId?.rawValue, scope.clientId?.rawValue]) { cursor -> TransactionDetailSnapshot? in
                    let origin = try cursor.getString(name: "origin")
                    guard TransactionDetailSnapshot.Origin(rawValue: origin) != nil else {
                        throw TransactionDetailSnapshot.Failure.invalidEvidence
                    }
                    let categoryWire: Any
                    if origin == "firebase_client_payment" {
                        // Re-check local membership even if another subscription
                        // still has a stale payment row after a downgrade.
                        guard full else { return nil }
                        guard try cursor.getStringOptional(name: "category_id") == nil else {
                            throw TransactionDetailSnapshot.Failure.invalidEvidence
                        }
                        categoryWire = NSNull()
                    } else {
                        guard let categoryId = try cursor.getStringOptional(name: "category_id"),
                              let category = categories.first(where: { $0.id.rawValue == categoryId }) else {
                            if requireCompleteCategories {
                                // A withdrawn Fee row can linger via another
                                // subscription. Do not call an unexplained omission complete.
                                throw PropertyManagementReportFailure.incompleteReadiness
                            }
                            return nil
                        }
                        categoryWire = ["id": category.id.rawValue, "name": category.name.rawValue,
                            "kind": category.kind.rawValue, "revision": String(category.revision)]
                    }
                    let emailed = try cursor.getIntOptional(name: "has_email_receipt")
                    guard emailed == nil || emailed == 0 || emailed == 1 else {
                        throw TransactionDetailSnapshot.Failure.invalidEvidence
                    }
                    var wire: [String: Any] = ["accountId": scope.accountId.rawValue,
                        "principalId": principalId.rawValue,
                        "category": categoryWire,
                        "hasEmailReceipt": emailed.map { $0 == 1 } as Any? ?? NSNull()]
                    wire["currentItemCategories"] = (categoriesByTransaction[try cursor.getString(name: "id")] ?? [])
                        .map { $0.mapValues { $0 as Any? ?? NSNull() } }
                    if origin == "firebase_client_payment" {
                        guard let contents = paymentContents[try cursor.getString(name: "id")] else {
                            throw TransactionPaymentContents.Failure.invalidEvidence
                        }
                        wire["paymentContents"] = try JSONSerialization.jsonObject(with: contents)
                    }
                    for (field, column) in [("transactionId", "id"), ("scopeKind", "scope_kind"),
                        ("type", "type"), ("role", "role"), ("origin", "origin"),
                        ("amountMinorUnits", "amount_minor_units"), ("currency", "currency")] {
                        wire[field] = try cursor.getString(name: column)
                    }
                    for (field, column) in [("projectId", "project_id"), ("clientId", "client_id"),
                        ("source", "source"), ("transactionDate", "transaction_date"),
                        ("createdAtMilliseconds", "created_at_ms"), ("notes", "notes"), ("paymentMethod", "payment_method"),
                        ("detailsRevision", "details_revision"),
                        ("legacySubtotalMinorUnits", "legacy_subtotal_minor_units"), ("legacyTaxRatePct", "legacy_tax_rate_pct")] {
                        wire[field] = try cursor.getStringOptional(name: column) as Any? ?? NSNull()
                    }
                    if origin == "vendor_payment" {
                        let items = (itemsByTransaction[try cursor.getString(name: "id")] ?? [])
                            .map { $0.mapValues { $0 as Any? ?? NSNull() } }
                        guard items.allSatisfy({ $0["currency"] as? String == wire["currency"] as? String }) else {
                            throw TransactionReceiptSnapshot.Failure.invalidEvidence
                        }
                        var receipt = wire
                        receipt["items"] = items
                        receipt["nonItemReceiptLines"] = try JSONSerialization.jsonObject(with:
                            Data(cursor.getString(name: "non_item_receipt_lines").utf8))
                        wire["receipt"] = receipt
                    }
                    return try JSONDecoder().decode(TransactionDetailSnapshot.self,
                        from: JSONSerialization.data(withJSONObject: wire))
                }
            let visible = rows.compactMap { $0 }
            for row in visible {
                try row.validate(scope: scope, principalId: principalId, transactionId: transactionId ?? row.transactionId)
            }
            return visible
    }

    /// One scope-wide read per fact type, inside the browser's existing SQLite
    /// snapshot. Current placement/category filters must not erase paid history.
    private func readPaymentContents(transaction: any Transaction, transactionId: TransactionID?) throws -> [String: Data] {
        let parameters: [Sendable?] = [scope.accountId.rawValue, scope.projectId?.rawValue,
            scope.clientId?.rawValue, transactionId?.rawValue, transactionId?.rawValue]
        let predicate = """
            t.account_id=? AND t.project_id IS ? AND t.client_id IS ? AND (? IS NULL OR t.id=?)
            AND t.scope_kind='project' AND t.origin='firebase_client_payment' AND t.type='purchase' AND t.role='standalone'
            """
        let links = try transaction.getAll(sql: """
            SELECT link.id,link.transaction_id,link.item_id,link.placement_id,link.ended_at
            FROM item_client_payment_connections link
            JOIN spike_transactions t ON t.account_id=link.account_id AND t.id=link.transaction_id
                AND t.project_id=link.project_id AND t.client_id=link.client_id
                AND t.type=link.transaction_type AND t.role=link.transaction_role
            WHERE \(predicate) ORDER BY link.id
            """, parameters: parameters) { cursor -> (String, [String: String?]) in
                (try cursor.getString(name: "transaction_id"), ["id": try cursor.getString(name: "id"),
                    "itemId": try cursor.getString(name: "item_id"), "placementId": try cursor.getString(name: "placement_id"),
                    "endedAt": try cursor.getStringOptional(name: "ended_at")])
            }
        let connections = Dictionary(grouping: links, by: { $0.0 }).mapValues { $0.map { $0.1 } }
        let lines = try transaction.getAll(sql: """
            SELECT line.id,line.invoice_id,line.line_position,line.source_kind,line.source_id,line.item_id,
                CAST(line.source_revision AS TEXT) AS source_revision,line.category_id,line.signed_amount_minor_units,
                line.description,line.source_snapshot_json,line.currency,invoice.currency AS invoice_currency
            FROM collected_invoice_lines line
            JOIN collected_invoices invoice ON invoice.account_id=line.account_id AND invoice.id=line.invoice_id AND invoice.sealed=1
            JOIN spike_transactions t ON t.account_id=invoice.account_id AND t.id=invoice.purchase_id
                AND t.project_id=invoice.project_id AND t.client_id=invoice.client_id
            WHERE \(predicate) ORDER BY line.invoice_id,line.line_position
            """, parameters: parameters) { cursor -> (String, Data) in
                guard try cursor.getString(name: "currency") == cursor.getString(name: "invoice_currency") else {
                    throw TransactionPaymentContents.Failure.invalidEvidence
                }
                var wire: [String: Any] = ["line_position": try cursor.getInt64(name: "line_position"),
                    "item_id": try cursor.getStringOptional(name: "item_id") as Any? ?? NSNull()]
                for key in ["id", "source_kind", "source_id", "source_revision", "category_id",
                    "signed_amount_minor_units", "description", "source_snapshot_json"] {
                    wire[key] = try cursor.getString(name: key)
                }
                return (try cursor.getString(name: "invoice_id"), try JSONSerialization.data(withJSONObject: wire))
            }
        let linesByInvoice = Dictionary(grouping: lines, by: { $0.0 }).mapValues { $0.map { $0.1 } }
        let metadataRows = try transaction.getAll(sql: """
            WITH members AS (
                SELECT t.id AS transaction_id,link.item_id FROM spike_transactions t
                JOIN item_client_payment_connections link ON link.account_id=t.account_id AND link.transaction_id=t.id
                    AND link.project_id=t.project_id AND link.client_id=t.client_id
                    AND link.transaction_type=t.type AND link.transaction_role=t.role WHERE \(predicate)
                UNION
                SELECT t.id AS transaction_id,line.item_id FROM spike_transactions t
                JOIN collected_invoices invoice ON invoice.account_id=t.account_id AND invoice.purchase_id=t.id
                    AND invoice.project_id=t.project_id AND invoice.client_id=t.client_id AND invoice.sealed=1
                JOIN collected_invoice_lines line ON line.account_id=invoice.account_id AND line.invoice_id=invoice.id
                    AND line.source_kind='item' AND line.item_id IS NOT NULL WHERE \(predicate)
            )
            SELECT members.transaction_id,members.item_id,COALESCE(item.name,item.description) AS name,item.sku,
                item.source,item.current_source,space.display_name AS current_space_name,CAST(images.expected_count AS TEXT) AS image_count
            FROM members
            LEFT JOIN spike_items item ON item.account_id=? AND item.id=members.item_id
            LEFT JOIN spike_item_placements placement ON placement.account_id=? AND placement.item_id=members.item_id AND placement.ended_at IS NULL
            LEFT JOIN spike_spaces space ON space.account_id=placement.account_id AND space.id=placement.space_id
                AND space.scope_kind=placement.scope_kind AND space.project_id IS placement.project_id
            LEFT JOIN item_image_sets images ON images.account_id=? AND images.item_id=members.item_id
            ORDER BY members.transaction_id,members.item_id
            """, parameters: parameters + parameters + Array(repeating: scope.accountId.rawValue, count: 3)) {
                cursor -> (String, [String: String?]) in
                (try cursor.getString(name: "transaction_id"), ["itemId": try cursor.getString(name: "item_id"),
                    "name": try cursor.getStringOptional(name: "name"), "sku": try cursor.getStringOptional(name: "sku"),
                    "source": try cursor.getStringOptional(name: "source"), "currentSource": try cursor.getStringOptional(name: "current_source"),
                    "currentSpaceName": try cursor.getStringOptional(name: "current_space_name"), "imageCount": try cursor.getStringOptional(name: "image_count")])
            }
        let metadata = Dictionary(grouping: metadataRows, by: { $0.0 }).mapValues { $0.map { $0.1 } }
        let rows = try transaction.getAll(sql: """
            SELECT t.id AS transaction_id,invoice.id AS invoice_id,invoice.invoice_revision,invoice.currency,invoice.total_minor_units,invoice.display_metadata
            FROM spike_transactions t
            LEFT JOIN collected_invoices invoice ON invoice.account_id=t.account_id AND invoice.purchase_id=t.id
                AND invoice.project_id=t.project_id AND invoice.client_id=t.client_id AND invoice.sealed=1
            WHERE \(predicate) ORDER BY t.id
            """, parameters: parameters) { cursor -> (String, Data) in
                let id = try cursor.getString(name: "transaction_id")
                var wire: [String: Any] = ["accountId": scope.accountId.rawValue, "principalId": principalId.rawValue,
                    "projectId": scope.projectId!.rawValue, "clientId": scope.clientId!.rawValue,
                    "transactionId": id, "connections": (connections[id] ?? []).map { $0.mapValues { $0 as Any? ?? NSNull() } }, "invoice": NSNull()]
                wire["items"] = (metadata[id] ?? []).map { $0.mapValues { $0 as Any? ?? NSNull() } }
                if let invoiceId = try cursor.getStringOptional(name: "invoice_id") {
                    wire["invoice"] = ["invoice_id": invoiceId, "invoice_revision": try cursor.getString(name: "invoice_revision"),
                        "account_id": scope.accountId.rawValue, "project_id": scope.projectId!.rawValue,
                        "client_id": scope.clientId!.rawValue, "purchase_id": id,
                        "currency": try cursor.getString(name: "currency"),
                        "total_minor_units": try cursor.getString(name: "total_minor_units"),
                        "display_metadata": try cursor.getStringOptional(name: "display_metadata")
                            .map { try JSONSerialization.jsonObject(with: Data($0.utf8)) } ?? NSNull(),
                        "lines": try (linesByInvoice[invoiceId] ?? []).map { try JSONSerialization.jsonObject(with: $0) }]
                }
                return (id, try JSONSerialization.data(withJSONObject: wire))
            }
        guard Set(rows.map { $0.0 }).count == rows.count else { throw TransactionPaymentContents.Failure.invalidEvidence }
        return Dictionary(uniqueKeysWithValues: rows)
    }

    func readTransactionExport(scope requestedScope: TransactionScope, orderedTransactionIDs: [TransactionID]?,
                               asOf: ProtectedArtifactEpochMilliseconds) async throws -> TransactionExportSnapshot {
        guard requestedScope == scope, scope.ownerKind == .project,
              let projectId = scope.projectId else { throw TransactionExportSnapshot.Failure.wrongScope }
        return try await database.readTransaction { transaction in
            let full = try CategoryManagementLocalProjection.requireMembership(transaction,
                account: scope.accountId, principal: principalId)
            let projectCheckpoint = try PropertyManagementReportPowerSyncQuery.completedStreamCheckpointMicroseconds(
                transaction: transaction, identity: TransactionExportProjectStreamIdentity())
            let receiptCheckpoint = try PropertyManagementReportPowerSyncQuery.completedStreamCheckpointMicroseconds(
                transaction: transaction, identity: TransactionReceiptStreamIdentity(scope: scope))
            // Priority-one directory/permissions can arrive before the financial
            // working set. Its older checkpoint cannot prove the new scope complete.
            guard receiptCheckpoint >= projectCheckpoint else {
                throw PropertyManagementReportFailure.incompleteReadiness
            }
            let project = try transaction.getOptional(sql: """
                SELECT id,client_id,display_name,lifecycle,revision FROM spike_projects
                WHERE account_id=? AND id=?
                """, parameters: [scope.accountId.rawValue, projectId.rawValue]) { cursor -> [String] in
                    let client = try cursor.getString(name: "client_id")
                    let lifecycle = try cursor.getString(name: "lifecycle")
                    let revision = try cursor.getInt64(name: "revision")
                    guard client == scope.clientId?.rawValue, ["active", "archived"].contains(lifecycle), revision > 0 else {
                        throw TransactionExportSnapshot.Failure.wrongScope
                    }
                    return [try cursor.getString(name: "id"), client,
                            try cursor.getString(name: "display_name"), lifecycle, String(revision)]
                }
            guard let project else { throw TransactionExportSnapshot.Failure.wrongScope }
            let rows = try readRows(transaction: transaction, transactionId: nil, requireCompleteCategories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let rowHash = try ProtectedArtifactSHA256.make(bytes: encoder.encode(rows))
            let version = try ProtectedArtifactSHA256.make(bytes: encoder.encode(project + [rowHash.rawValue]))
            let visibility = try ProtectedArtifactVisibilityScopeID.make(bytes: encoder.encode([
                scope.accountId.rawValue, principalId.rawValue, projectId.rawValue, full ? "full" : "restricted",
                "transaction-export-v1"]))
            return try TransactionExportSnapshot(scope: scope, principalId: principalId, update: .ready(rows),
                orderedTransactionIDs: orderedTransactionIDs, asOf: asOf,
                sourceVersion: .init(validating: version.rawValue), visibilityScopeID: visibility,
                authorityVersion: .init(validating: "transaction-export-v1"))
        }
    }
}

/// Existing auto-subscribed directory, including archived Projects. No new
/// stream or report-sized Item download is needed just to establish the parent.
private struct TransactionExportProjectStreamIdentity: SyncStreamDescription {
    let name = "spike_projects"
    let parameters: JsonParam? = nil
}
