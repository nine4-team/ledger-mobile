import FirebaseFirestore

// MARK: - Errors

enum InventoryOperationError: Error {
    /// Caller tried to use `reassignToProject` for a cross-scope (different project) move.
    /// Cross-scope moves are sells — use `sellToProject` instead.
    case crossScopeReassign
}

// MARK: - Service

/// Multi-step atomic Firestore operations for inventory movements:
/// sell to business, sell to project, reassign (within-scope), reassign to inventory.
///
/// ## Canonical Sale Transactions
/// Items moving between scopes (project ↔ business inventory) create or update a deterministic
/// "canonical sale transaction" with ID: `SALE_{projectId}_{direction}_{budgetCategoryId}`.
/// Items are grouped by budgetCategoryId — each group goes to its own canonical sale.
///
/// ## Direction Rules (M17)
/// - Items WITH a projectId → moving OUT of a project → direction: `project_to_business`
/// - Items WITHOUT a projectId → moving INTO a project → direction: `business_to_project`
struct InventoryOperationsService {
    private let db = Firestore.firestore()

    // MARK: - Sell to Business

    /// Moves items from a project into business inventory.
    /// Creates or updates canonical sale transactions, grouped by budget category (H12).
    /// Items without a `budgetCategoryId` fall back to `overrideCategoryId` (H13).
    func sellToBusiness(
        items: [Item],
        accountId: String,
        userId: String? = nil,
        overrideCategoryId: String? = nil
    ) async throws {
        guard !items.isEmpty else { return }

        let batch = db.batch()
        let itemsRef = db.collection("accounts/\(accountId)/items")
        let txRef = db.collection("accounts/\(accountId)/transactions")
        let edgesRef = db.collection("accounts/\(accountId)/lineageEdges")

        // Group items by (projectId, resolvedCategoryId) so each group
        // maps to exactly one canonical sale transaction (H12).
        let groups = Self.groupForSale(items: items, override: overrideCategoryId)

        for (groupKey, groupItems) in groups {
            let saleId = Self.canonicalSaleId(
                projectId: groupKey.projectId,
                direction: "project_to_business",
                categoryId: groupKey.categoryId
            )
            let saleDocRef = txRef.document(saleId)
            let amountDelta = Self.amountDelta(for: groupItems) // H11
            // setData(merge:true) creates doc if missing, updates fields if exists.
            // FieldValue.arrayUnion + increment handle idempotent accumulation.
            batch.setData([
                "projectId": groupKey.projectId,
                "type": "Sale",                           // C1: use "type" not "transactionType"
                "isCanonicalInventorySale": true,
                "inventorySaleDirection": "project_to_business",  // C2: only valid directions
                "budgetCategoryId": groupKey.categoryId,
                "itemIds": FieldValue.arrayUnion(groupItems.compactMap(\.id)),
                "amountCents": FieldValue.increment(Int64(amountDelta)),  // H11
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
            ] as [String: Any], forDocument: saleDocRef, merge: true)
        }

        for item in items {
            guard let itemId = item.id,
                  let projectId = item.projectId else { continue }

            let categoryId = item.budgetCategoryId ?? overrideCategoryId ?? "uncategorized"
            let saleId = Self.canonicalSaleId(
                projectId: projectId,
                direction: "project_to_business",
                categoryId: categoryId
            )

            // Update item: clear projectId/spaceId, set status and link to canonical sale
            batch.updateData([
                "projectId": NSNull(),
                "spaceId": NSNull(),
                "status": "purchased",
                "transactionId": saleId,
                "updatedAt": FieldValue.serverTimestamp(),
            ], forDocument: itemsRef.document(itemId))

            // Remove item from its source transaction's itemIds (C5)
            if let fromTxId = item.transactionId {
                batch.updateData(
                    ["itemIds": FieldValue.arrayRemove([itemId])],
                    forDocument: txRef.document(fromTxId)
                )
            }

            // Lineage edge
            var edge: [String: Any] = [
                "accountId": accountId,
                "itemId": itemId,
                "fromProjectId": projectId,
                "toTransactionId": saleId,
                "movementKind": "sold",
                "source": "app",
                "createdAt": FieldValue.serverTimestamp(),
            ]
            if let fromTxId = item.transactionId { edge["fromTransactionId"] = fromTxId }  // M2
            if let userId { edge["createdBy"] = userId }                                    // M3
            batch.setData(edge, forDocument: edgesRef.document())
        }

        try await batch.commit()
    }

    // MARK: - Sell to Project

    /// Two-hop sell: source project → business inventory → destination project.
    /// Creates or updates canonical sales for BOTH hops, grouped by budget category (H12).
    ///
    /// - Items with their own `budgetCategoryId` use it for both hops.
    /// - `sourceCategoryId` / `destinationCategoryId` are overrides for items without a category.
    func sellToProject(
        items: [Item],
        destinationProjectId: String,
        accountId: String,
        userId: String? = nil,
        sourceCategoryId: String? = nil,
        destinationCategoryId: String? = nil
    ) async throws {
        guard !items.isEmpty else { return }

        let batch = db.batch()
        let itemsRef = db.collection("accounts/\(accountId)/items")
        let txRef = db.collection("accounts/\(accountId)/transactions")
        let edgesRef = db.collection("accounts/\(accountId)/lineageEdges")

        for item in items {
            guard let itemId = item.id else { continue }

            let srcCatId = item.budgetCategoryId ?? sourceCategoryId ?? "uncategorized"
            let dstCatId = item.budgetCategoryId ?? destinationCategoryId ?? "uncategorized"
            let amountDelta = item.purchasePriceCents ?? 0

            // Hop 1: source project → business inventory (only if item was in a project)
            if let srcProjectId = item.projectId {
                let srcSaleId = Self.canonicalSaleId(
                    projectId: srcProjectId,
                    direction: "project_to_business",   // C2: valid direction
                    categoryId: srcCatId
                )
                batch.setData([
                    "projectId": srcProjectId,
                    "type": "Sale",                     // C1
                    "isCanonicalInventorySale": true,
                    "inventorySaleDirection": "project_to_business",
                    "budgetCategoryId": srcCatId,
                    "itemIds": FieldValue.arrayUnion([itemId]),
                    "amountCents": FieldValue.increment(Int64(amountDelta)),
                    "createdAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp(),
                ] as [String: Any], forDocument: txRef.document(srcSaleId), merge: true)
            }

            // Hop 2: business inventory → destination project
            let dstSaleId = Self.canonicalSaleId(
                projectId: destinationProjectId,
                direction: "business_to_project",       // C2: valid direction (M17)
                categoryId: dstCatId
            )
            batch.setData([
                "projectId": destinationProjectId,
                "type": "Sale",                         // C1
                "isCanonicalInventorySale": true,
                "inventorySaleDirection": "business_to_project",
                "budgetCategoryId": dstCatId,
                "itemIds": FieldValue.arrayUnion([itemId]),
                "amountCents": FieldValue.increment(Int64(amountDelta)),
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
            ] as [String: Any], forDocument: txRef.document(dstSaleId), merge: true)

            // Update item: move to destination, link to destination canonical sale
            var itemUpdate: [String: Any] = [
                "projectId": destinationProjectId,
                "spaceId": NSNull(),
                "transactionId": dstSaleId,
                "updatedAt": FieldValue.serverTimestamp(),
            ]
            // Backfill projectPriceCents for legacy items missing it
            if item.projectPriceCents == nil, let purchasePrice = item.purchasePriceCents {
                itemUpdate["projectPriceCents"] = purchasePrice
            }
            batch.updateData(itemUpdate, forDocument: itemsRef.document(itemId))

            // Remove item from its source transaction's itemIds (C5)
            if let fromTxId = item.transactionId {
                batch.updateData(
                    ["itemIds": FieldValue.arrayRemove([itemId])],
                    forDocument: txRef.document(fromTxId)
                )
            }

            // Lineage edge
            var edge: [String: Any] = [
                "accountId": accountId,
                "itemId": itemId,
                "toProjectId": destinationProjectId,
                "toTransactionId": dstSaleId,
                "movementKind": "sold",
                "source": "app",
                "createdAt": FieldValue.serverTimestamp(),
            ]
            if let srcProjectId = item.projectId { edge["fromProjectId"] = srcProjectId }
            if let fromTxId = item.transactionId { edge["fromTransactionId"] = fromTxId }  // M2
            if let userId { edge["createdBy"] = userId }                                    // M3
            batch.setData(edge, forDocument: edgesRef.document())
        }

        try await batch.commit()
    }

    // MARK: - Reassign to Project (within-scope only — C4)

    /// Moves items to a different transaction within the **same** project scope.
    /// No financial records are created — corrects misallocations within a project.
    ///
    /// Throws `InventoryOperationError.crossScopeReassign` if any item has a different
    /// `projectId` than `destinationProjectId`. Cross-scope moves are sells, not reassigns.
    func reassignToProject(
        items: [Item],
        destinationTransactionId: String,
        destinationProjectId: String,
        accountId: String
    ) async throws {
        guard !items.isEmpty else { return }

        // C4: Reassign is within-scope only. All items must already be in the destination project.
        let crossScope = items.contains { $0.projectId != destinationProjectId }
        if crossScope { throw InventoryOperationError.crossScopeReassign }

        let batch = db.batch()
        let itemsRef = db.collection("accounts/\(accountId)/items")
        let txRef = db.collection("accounts/\(accountId)/transactions")

        for item in items {
            guard let itemId = item.id else { continue }

            // Update item's transaction link (projectId stays the same)
            var itemUpdate: [String: Any] = [
                "transactionId": destinationTransactionId,
                "updatedAt": FieldValue.serverTimestamp(),
            ]
            if item.projectPriceCents == nil, let purchasePrice = item.purchasePriceCents {
                itemUpdate["projectPriceCents"] = purchasePrice
            }
            batch.updateData(itemUpdate, forDocument: itemsRef.document(itemId))

            // C5: Move item between transaction itemIds arrays
            if let fromTxId = item.transactionId {
                batch.updateData(
                    ["itemIds": FieldValue.arrayRemove([itemId])],
                    forDocument: txRef.document(fromTxId)
                )
            }
            batch.updateData(
                ["itemIds": FieldValue.arrayUnion([itemId])],
                forDocument: txRef.document(destinationTransactionId)
            )
        }

        try await batch.commit()
    }

    // MARK: - Reassign to Inventory

    /// Moves items back to business inventory without financial records.
    func reassignToInventory(items: [Item], accountId: String) async throws {
        guard !items.isEmpty else { return }

        let batch = db.batch()
        let itemsRef = db.collection("accounts/\(accountId)/items")
        let txRef = db.collection("accounts/\(accountId)/transactions")

        for item in items {
            guard let itemId = item.id else { continue }
            batch.updateData([
                "projectId": NSNull(),
                "updatedAt": FieldValue.serverTimestamp(),
            ], forDocument: itemsRef.document(itemId))

            // C5: Remove item from its source transaction's itemIds
            if let fromTxId = item.transactionId {
                batch.updateData(
                    ["itemIds": FieldValue.arrayRemove([itemId])],
                    forDocument: txRef.document(fromTxId)
                )
            }
        }

        try await batch.commit()
    }

    // MARK: - Pure Helpers (internal for testability)

    /// Builds the deterministic canonical sale transaction ID (H1).
    static func canonicalSaleId(projectId: String, direction: String, categoryId: String) -> String {
        "SALE_\(projectId)_\(direction)_\(categoryId)"
    }

    /// Sum of `purchasePriceCents` for a group of items (H11).
    static func amountDelta(for items: [Item]) -> Int {
        items.reduce(0) { $0 + ($1.purchasePriceCents ?? 0) }
    }

    /// Groups items by (projectId, resolvedCategoryId) for canonical sale batching (H12).
    /// Items without a `projectId` are skipped (can't create a project_to_business sale).
    static func groupForSale(
        items: [Item],
        override: String?
    ) -> [SaleGroupKey: [Item]] {
        var groups: [SaleGroupKey: [Item]] = [:]
        for item in items {
            guard let projectId = item.projectId else { continue }
            let categoryId = item.budgetCategoryId ?? override ?? "uncategorized"
            let key = SaleGroupKey(projectId: projectId, categoryId: categoryId)
            groups[key, default: []].append(item)
        }
        return groups
    }

    /// Key for grouping items into a single canonical sale transaction.
    struct SaleGroupKey: Hashable {
        let projectId: String
        let categoryId: String
    }
}
