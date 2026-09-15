import Foundation
import LedgerTargetCore
import PowerSync

struct TransactionReceiptStreamIdentity: SyncStreamDescription, Sendable {
    let name = "transaction_receipts"
    let parameters: JsonParam?

    init(scope: TransactionScope) {
        parameters = ["account_id": .string(scope.accountId.rawValue),
            "scope_kind": .string(scope.ownerKind == .project ? "project" : "business_inventory"),
            "project_id": scope.projectId.map { .string($0.rawValue) } ?? .null]
    }
}

/// A read-only view of a completed downloaded scope. Subscription lifetime is
/// owned by the workspace runtime, as with the existing report download.
struct TransactionReceiptPowerSyncQuery: TransactionReceiptReading {
    let database: any PowerSyncDatabaseProtocol
    let principalId: PrincipalID
    let scope: TransactionScope

    func watch(transactionId: TransactionID,
               receive: @Sendable @escaping (TransactionReceiptUpdate) async -> Bool) async throws {
        let identity = TransactionReceiptStreamIdentity(scope: scope)
        try await withOwnedSyncStreamWatch(subscribe: {
            try await database.syncStream(name: identity.name, params: identity.parameters).subscribe()
        }, observe: {
            let changes = try database.watch(sql: """
                SELECT EXISTS(SELECT 1 FROM spike_account_memberships WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_transactions WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM transaction_receipt_items WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_items WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_budget_categories WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_local_operations WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_operation_results WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_item_placements WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_spaces WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM item_image_sets WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM ps_stream_subscriptions WHERE stream_name='transaction_receipts')
                """, parameters: Array(repeating: scope.accountId.rawValue, count: 10)) { try $0.getInt(index: 0) }
            for try await _ in changes {
                try Task.checkCancellation()
                let update: TransactionReceiptUpdate
                do { update = .ready(try await read(transactionId: transactionId)) }
                catch PropertyManagementReportFailure.incompleteReadiness { update = .incomplete }
                catch TransactionReceiptSnapshot.Failure.scopeMismatch { update = .unavailable }
                guard await receive(update) else { return }
            }
        })
    }

    func read(transactionId: TransactionID) async throws -> TransactionReceiptSnapshot {
        try await database.readTransaction { transaction in
            let full = try CategoryManagementLocalProjection.requireMembership(transaction,
                account: scope.accountId, principal: principalId)
            _ = try PropertyManagementReportPowerSyncQuery.completedStreamCheckpoint(transaction: transaction,
                identity: TransactionReceiptStreamIdentity(scope: scope))
            let categories = try CategoryManagementLocalProjection.read(transaction, account: scope.accountId,
                principal: principalId, fullFinancialAccess: full)
            let rows = try transaction.getAll(sql: """
                SELECT id,account_id,project_id,client_id,scope_kind,type,role,origin,
                    amount_minor_units,currency,category_id,non_item_receipt_lines
                FROM spike_transactions WHERE account_id=? AND id=?
                """, parameters: [scope.accountId.rawValue, transactionId.rawValue]) { cursor in
                    let categoryId = try cursor.getString(name: "category_id")
                    guard try cursor.getString(name: "origin") == "vendor_payment",
                          try cursor.getString(name: "role") == "standalone",
                          let category = categories.first(where: { $0.id.rawValue == categoryId }) else {
                        throw TransactionReceiptSnapshot.Failure.scopeMismatch
                    }
                    let lines = try cursor.getString(name: "non_item_receipt_lines")
                    return ["accountId": scope.accountId.rawValue, "principalId": principalId.rawValue,
                        "transactionId": try cursor.getString(name: "id"),
                        "scopeKind": try cursor.getString(name: "scope_kind"),
                        "projectId": try cursor.getStringOptional(name: "project_id") as Any? ?? NSNull(),
                        "clientId": try cursor.getStringOptional(name: "client_id") as Any? ?? NSNull(),
                        "type": try cursor.getString(name: "type"),
                        "amountMinorUnits": try cursor.getString(name: "amount_minor_units"),
                        "currency": try cursor.getString(name: "currency"),
                        "category": ["id": category.id.rawValue, "name": category.name.rawValue,
                            "kind": category.kind.rawValue, "revision": String(category.revision)],
                        "nonItemReceiptLines": try JSONSerialization.jsonObject(with: Data(lines.utf8))] as [String: Any]
                }
            guard rows.count == 1 else { throw TransactionReceiptSnapshot.Failure.scopeMismatch }
            var wire = rows[0]
            let currency = wire["currency"] as? String
            wire["items"] = try transaction.getAll(sql: """
                SELECT evidence.item_id,evidence.currency,evidence.amount_minor_units,evidence.membership_kind,
                    COALESCE(item.name,item.description) AS item_name,item.sku AS item_sku,
                    item.source AS item_source,item.current_source AS item_current_source,
                    space.display_name AS current_space_name, CAST(images.expected_count AS TEXT) AS image_count
                FROM transaction_receipt_items evidence
                LEFT JOIN spike_items item ON item.account_id=evidence.account_id AND item.id=evidence.item_id
                LEFT JOIN spike_item_placements placement ON placement.account_id=evidence.account_id
                    AND placement.item_id=evidence.item_id AND placement.ended_at IS NULL
                LEFT JOIN spike_spaces space ON space.account_id=placement.account_id AND space.id=placement.space_id
                    AND space.scope_kind=placement.scope_kind AND space.project_id IS placement.project_id
                LEFT JOIN item_image_sets images ON images.account_id=evidence.account_id AND images.item_id=evidence.item_id
                WHERE evidence.account_id=? AND evidence.transaction_id=? ORDER BY evidence.item_id
                """, parameters: [scope.accountId.rawValue, transactionId.rawValue]) { cursor in
                    guard try cursor.getString(name: "currency") == currency else {
                        throw TransactionReceiptSnapshot.Failure.invalidEvidence
                    }
                    return ["itemId": try cursor.getString(name: "item_id"),
                        "name": try cursor.getStringOptional(name: "item_name") as Any? ?? NSNull(),
                        "sku": try cursor.getStringOptional(name: "item_sku") as Any? ?? NSNull(),
                        "source": try cursor.getStringOptional(name: "item_source") as Any? ?? NSNull(),
                        "currentSource": try cursor.getStringOptional(name: "item_current_source") as Any? ?? NSNull(),
                        "currentSpaceName": try cursor.getStringOptional(name: "current_space_name") as Any? ?? NSNull(),
                        "imageCount": try cursor.getStringOptional(name: "image_count") as Any? ?? NSNull(),
                        "amountMinorUnits": try cursor.getStringOptional(name: "amount_minor_units") as Any? ?? NSNull(),
                        "membershipKind": try cursor.getString(name: "membership_kind")] as [String: Any]
                }
            let receipt = try JSONDecoder().decode(TransactionReceiptSnapshot.self,
                from: JSONSerialization.data(withJSONObject: wire))
            try receipt.validate(accountId: scope.accountId, principalId: principalId, transactionId: transactionId)
            guard receipt.classification.scope == scope else { throw TransactionReceiptSnapshot.Failure.scopeMismatch }
            return receipt
        }
    }
}
