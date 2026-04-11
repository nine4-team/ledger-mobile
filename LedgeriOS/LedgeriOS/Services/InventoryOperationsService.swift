import FirebaseFirestore

// MARK: - Errors

enum InventoryOperationError: Error {
    /// Caller tried to use `reassignToProject` for a cross-scope (different project) move.
    /// Cross-scope moves are sells — use `sellToProject` instead.
    case crossScopeReassign

    /// Batch exceeds the 100-item cap. Firestore batch writes allow 500 docs;
    /// 100 items keeps us well under with item updates + txn writes + lineage edges.
    case batchSizeExceeded

    /// moveBetweenProjects requires all items to be in the same source project.
    case mixedSourceProjects

    /// moveBetweenProjects source and destination are the same project.
    case sameSourceAndDestination

    /// moveBetweenProjects requires all items to be in a project (not inventory).
    case itemsNotInProject
}

// MARK: - Service

/// Multi-step atomic Firestore operations for inventory movements:
/// sell to project, return to inventory, move between projects,
/// reassign (within-scope), return to transaction.
///
/// ## Per-Batch Sale Transactions
/// Each sell action creates ONE new immutable Sale transaction with an auto-ID.
/// Shape fields (amountCents, itemIds, budgetCategoryId, type, source, projectId)
/// are frozen at creation and never mutated. Sales only go business → project.
///
/// ## Returning to Inventory
/// Items moving from a project back to business inventory create a Return
/// transaction. The `source` label defaults to `"Business Inventory"`, but
/// callers can pass `inventoryLabel: "[Account Name] Inventory"` (built via
/// `InventoryOperationsService.inventoryLabel(for:)`) for a branded label.
/// Items have their budgetCategoryId wiped (inventory items have no category).
///
/// ## Batch Cap
/// All operations are capped at 100 items per call.
struct InventoryOperationsService {
    private static let maxBatchItems = 100

    /// Default source label used when a caller doesn't supply one.
    /// Kept as the static fallback for accounts without a configured name.
    static let defaultInventoryLabel = "Business Inventory"

    /// Produces the source label for inventory-originating Sale and Return
    /// transactions. Prefers `"[Account Name] Inventory"` when a non-empty
    /// account name is provided, otherwise falls back to
    /// `defaultInventoryLabel` (`"Business Inventory"`).
    ///
    /// Whitespace-only names are treated as empty. The trailing " Inventory"
    /// suffix is always appended so the resulting label is recognizable as
    /// an inventory source in transaction filters.
    static func inventoryLabel(for accountName: String?) -> String {
        let trimmed = accountName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultInventoryLabel : "\(trimmed) Inventory"
    }

    private let makeBatch: @Sendable () -> any BatchWriting

    init(makeBatch: @escaping @Sendable () -> any BatchWriting = { FirestoreBatchWriter() }) {
        self.makeBatch = makeBatch
    }

    // MARK: - Sell to Project

    /// Sells items from business inventory (or another project) into a destination project.
    /// Creates ONE new immutable Sale transaction per call. No long-lived aggregators.
    ///
    /// The Sale transaction's shape (amountCents, itemIds, budgetCategoryId, projectId,
    /// type, source) is frozen at creation — Firestore security rules enforce this.
    func sellToProject(
        items: [Item],
        destinationProjectId: String,
        budgetCategoryId: String,
        accountId: String,
        inventoryLabel: String = Self.defaultInventoryLabel,
        userId: String? = nil,
        notes: String? = nil
    ) async throws {
        guard !items.isEmpty else { return }
        guard items.count <= Self.maxBatchItems else {
            throw InventoryOperationError.batchSizeExceeded
        }

        let batch = makeBatch()
        let itemsPath = "accounts/\(accountId)/items"
        let txPath = "accounts/\(accountId)/transactions"
        let edgesPath = "accounts/\(accountId)/lineageEdges"
        let pbcPath = "accounts/\(accountId)/projects/\(destinationProjectId)/budgetCategories"

        // Frozen amount snapshot
        let totals = Self.computeBatchTotals(items)

        // 1. Create new Sale transaction (auto-ID via UUID, frozen shape)
        let saleId = UUID().uuidString
        let saleDocPath = "\(txPath)/\(saleId)"
        let today = Self.todayDateString()
        var saleFields: [String: Any] = [
            "type": "Sale",
            "source": inventoryLabel,
            "projectId": destinationProjectId,
            "budgetCategoryId": budgetCategoryId,
            "amountCents": totals.amountCents,
            "subtotalCents": totals.subtotalCents,
            "itemIds": items.compactMap(\.id),
            "status": "completed",
            "isComplete": true,
            "transactionDate": today,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if let notes { saleFields["notes"] = notes }
        if let userId { saleFields["createdBy"] = userId }
        batch.setData(saleFields, forDocumentAt: saleDocPath, merge: false)

        // 2. Update each item
        for item in items {
            guard let itemId = item.id else { continue }

            var itemUpdate: [String: Any] = [
                "projectId": destinationProjectId,
                "budgetCategoryId": budgetCategoryId,
                "status": "purchased",
                "transactionId": saleId,
                "spaceId": NSNull(),
                "updatedAt": FieldValue.serverTimestamp(),
            ]
            // Backfill projectPriceCents for legacy items missing it
            if item.projectPriceCents == nil, let purchasePrice = item.purchasePriceCents {
                itemUpdate["projectPriceCents"] = purchasePrice
            }
            batch.updateData(itemUpdate, forDocumentAt: "\(itemsPath)/\(itemId)")

            // 3. Remove item from its source transaction's itemIds
            if let fromTxId = item.transactionId {
                batch.updateData(
                    ["itemIds": FieldValue.arrayRemove([itemId])],
                    forDocumentAt: "\(txPath)/\(fromTxId)"
                )
            }

            // 4. Lineage edge (sold)
            var edge: [String: Any] = [
                "accountId": accountId,
                "itemId": itemId,
                "toProjectId": destinationProjectId,
                "toTransactionId": saleId,
                "movementKind": "sold",
                "source": "app",
                "createdAt": FieldValue.serverTimestamp(),
            ]
            if let fromProjectId = item.projectId { edge["fromProjectId"] = fromProjectId }
            if let fromTxId = item.transactionId { edge["fromTransactionId"] = fromTxId }
            if let userId { edge["createdBy"] = userId }
            batch.setDataAutoId(edge, inCollection: edgesPath)
        }

        // 5. Auto-enable destination budget category
        if budgetCategoryId != "uncategorized" {
            var catFields: [String: Any] = ["updatedAt": FieldValue.serverTimestamp()]
            if let userId { catFields["updatedBy"] = userId }
            batch.setData(catFields, forDocumentAt: "\(pbcPath)/\(budgetCategoryId)", merge: true)
        }

        try await batch.commit()
    }

    // MARK: - Return to Inventory

    /// Moves items from a project back to business inventory.
    /// Creates a Return transaction whose `source` defaults to
    /// `"Business Inventory"`; pass `inventoryLabel` for a branded label.
    /// Items have budgetCategoryId and projectId wiped (inventory invariant).
    func returnToInventory(
        items: [Item],
        accountId: String,
        inventoryLabel: String = Self.defaultInventoryLabel,
        userId: String? = nil,
        notes: String? = nil
    ) async throws {
        guard !items.isEmpty else { return }
        guard items.count <= Self.maxBatchItems else {
            throw InventoryOperationError.batchSizeExceeded
        }

        let batch = makeBatch()
        let itemsPath = "accounts/\(accountId)/items"
        let txPath = "accounts/\(accountId)/transactions"
        let edgesPath = "accounts/\(accountId)/lineageEdges"

        // Return amount uses purchasePriceCents (what the business actually paid)
        let returnAmount = items.reduce(0) { $0 + ($1.purchasePriceCents ?? 0) }

        // Determine source projectId for the Return transaction (budget impact)
        let sourceProjectId: Any = items.first?.projectId as Any? ?? NSNull()

        // 1. Create Return transaction
        let returnId = UUID().uuidString
        let returnDocPath = "\(txPath)/\(returnId)"
        let today = Self.todayDateString()
        var returnFields: [String: Any] = [
            "type": "Return",
            "source": inventoryLabel,
            "projectId": sourceProjectId,
            "amountCents": returnAmount,
            "itemIds": items.compactMap(\.id),
            "status": "completed",
            "transactionDate": today,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if let notes { returnFields["notes"] = notes }
        if let userId { returnFields["createdBy"] = userId }
        batch.setData(returnFields, forDocumentAt: returnDocPath, merge: false)

        // 2. Update each item
        for item in items {
            guard let itemId = item.id else { continue }

            batch.updateData([
                "projectId": NSNull(),
                "budgetCategoryId": NSNull(),
                "spaceId": NSNull(),
                "status": "purchased",
                "transactionId": returnId,
                "updatedAt": FieldValue.serverTimestamp(),
            ], forDocumentAt: "\(itemsPath)/\(itemId)")

            // 3. Remove from source transaction's itemIds
            if let fromTxId = item.transactionId {
                batch.updateData(
                    ["itemIds": FieldValue.arrayRemove([itemId])],
                    forDocumentAt: "\(txPath)/\(fromTxId)"
                )
            }

            // 4. Lineage edge (returned)
            var edge: [String: Any] = [
                "accountId": accountId,
                "itemId": itemId,
                "toTransactionId": returnId,
                "movementKind": "returned",
                "source": "app",
                "createdAt": FieldValue.serverTimestamp(),
            ]
            if let fromProjectId = item.projectId { edge["fromProjectId"] = fromProjectId }
            if let fromTxId = item.transactionId { edge["fromTransactionId"] = fromTxId }
            if let userId { edge["createdBy"] = userId }
            batch.setDataAutoId(edge, inCollection: edgesPath)
        }

        try await batch.commit()
    }

    // MARK: - Move Between Projects

    /// Moves items from one project to another in a single atomic batch.
    /// Under the hood: one Return (from source) + one Sale (to destination).
    /// All items must be in the same source project.
    func moveBetweenProjects(
        items: [Item],
        destinationProjectId: String,
        destinationCategoryId: String,
        accountId: String,
        inventoryLabel: String = Self.defaultInventoryLabel,
        userId: String? = nil,
        notes: String? = nil
    ) async throws {
        guard !items.isEmpty else { return }
        guard items.count <= Self.maxBatchItems else {
            throw InventoryOperationError.batchSizeExceeded
        }

        // All items must be in a project
        let stray = items.filter { $0.projectId == nil }
        guard stray.isEmpty else { throw InventoryOperationError.itemsNotInProject }

        // All items must be in the same source project
        let sourceProjects = Set(items.compactMap(\.projectId))
        guard sourceProjects.count == 1 else { throw InventoryOperationError.mixedSourceProjects }
        let sourceProjectId = sourceProjects.first!

        guard sourceProjectId != destinationProjectId else {
            throw InventoryOperationError.sameSourceAndDestination
        }

        let batch = makeBatch()
        let itemsPath = "accounts/\(accountId)/items"
        let txPath = "accounts/\(accountId)/transactions"
        let edgesPath = "accounts/\(accountId)/lineageEdges"
        let pbcPath = "accounts/\(accountId)/projects/\(destinationProjectId)/budgetCategories"

        let totals = Self.computeBatchTotals(items)
        let returnAmount = items.reduce(0) { $0 + ($1.purchasePriceCents ?? 0) }
        let itemIdList = items.compactMap(\.id)
        let today = Self.todayDateString()

        // 1a. Return transaction (from source project)
        let returnId = UUID().uuidString
        var returnFields: [String: Any] = [
            "type": "Return",
            "source": inventoryLabel,
            "projectId": sourceProjectId,
            "amountCents": returnAmount,
            "itemIds": itemIdList,
            "status": "completed",
            "transactionDate": today,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if let notes { returnFields["notes"] = notes }
        if let userId { returnFields["createdBy"] = userId }
        batch.setData(returnFields, forDocumentAt: "\(txPath)/\(returnId)", merge: false)

        // 1b. Sale transaction (to destination project)
        let saleId = UUID().uuidString
        var saleFields: [String: Any] = [
            "type": "Sale",
            "source": inventoryLabel,
            "projectId": destinationProjectId,
            "budgetCategoryId": destinationCategoryId,
            "amountCents": totals.amountCents,
            "subtotalCents": totals.subtotalCents,
            "itemIds": itemIdList,
            "status": "completed",
            "isComplete": true,
            "transactionDate": today,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if let notes { saleFields["notes"] = notes }
        if let userId { saleFields["createdBy"] = userId }
        batch.setData(saleFields, forDocumentAt: "\(txPath)/\(saleId)", merge: false)

        // 2. Update each item (lands in destination project)
        for item in items {
            guard let itemId = item.id else { continue }

            var itemUpdate: [String: Any] = [
                "projectId": destinationProjectId,
                "budgetCategoryId": destinationCategoryId,
                "status": "purchased",
                "transactionId": saleId,
                "spaceId": NSNull(),
                "updatedAt": FieldValue.serverTimestamp(),
            ]
            if item.projectPriceCents == nil, let purchasePrice = item.purchasePriceCents {
                itemUpdate["projectPriceCents"] = purchasePrice
            }
            batch.updateData(itemUpdate, forDocumentAt: "\(itemsPath)/\(itemId)")

            // 3. Remove from source transaction's itemIds
            if let fromTxId = item.transactionId {
                batch.updateData(
                    ["itemIds": FieldValue.arrayRemove([itemId])],
                    forDocumentAt: "\(txPath)/\(fromTxId)"
                )
            }

            // 4. Lineage edges — one "returned" + one "sold" per item
            var returnEdge: [String: Any] = [
                "accountId": accountId,
                "itemId": itemId,
                "fromProjectId": sourceProjectId,
                "toTransactionId": returnId,
                "movementKind": "returned",
                "source": "app",
                "createdAt": FieldValue.serverTimestamp(),
            ]
            if let fromTxId = item.transactionId { returnEdge["fromTransactionId"] = fromTxId }
            if let userId { returnEdge["createdBy"] = userId }
            batch.setDataAutoId(returnEdge, inCollection: edgesPath)

            var soldEdge: [String: Any] = [
                "accountId": accountId,
                "itemId": itemId,
                "fromProjectId": sourceProjectId,
                "toProjectId": destinationProjectId,
                "toTransactionId": saleId,
                "movementKind": "sold",
                "source": "app",
                "createdAt": FieldValue.serverTimestamp(),
            ]
            if let fromTxId = item.transactionId { soldEdge["fromTransactionId"] = fromTxId }
            if let userId { soldEdge["createdBy"] = userId }
            batch.setDataAutoId(soldEdge, inCollection: edgesPath)
        }

        // 5. Auto-enable destination budget category
        if destinationCategoryId != "uncategorized" {
            var catFields: [String: Any] = ["updatedAt": FieldValue.serverTimestamp()]
            if let userId { catFields["updatedBy"] = userId }
            batch.setData(catFields, forDocumentAt: "\(pbcPath)/\(destinationCategoryId)", merge: true)
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
        destinationBudgetCategoryId: String? = nil,
        accountId: String,
        userId: String? = nil
    ) async throws {
        guard !items.isEmpty else { return }

        // C4: Reassign is within-scope only. All items must already be in the destination project.
        let crossScope = items.contains { $0.projectId != destinationProjectId }
        if crossScope { throw InventoryOperationError.crossScopeReassign }

        let batch = makeBatch()
        let itemsPath = "accounts/\(accountId)/items"
        let txPath = "accounts/\(accountId)/transactions"
        let edgesPath = "accounts/\(accountId)/lineageEdges"

        for item in items {
            guard let itemId = item.id else { continue }

            // Update item's transaction link (projectId stays the same)
            var itemUpdate: [String: Any] = [
                "transactionId": destinationTransactionId,
                "updatedAt": FieldValue.serverTimestamp(),
            ]
            if item.budgetCategoryId == nil, let categoryId = destinationBudgetCategoryId {
                itemUpdate["budgetCategoryId"] = categoryId
            }
            if item.projectPriceCents == nil, let purchasePrice = item.purchasePriceCents {
                itemUpdate["projectPriceCents"] = purchasePrice
            }
            batch.updateData(itemUpdate, forDocumentAt: "\(itemsPath)/\(itemId)")

            // C5: Move item between transaction itemIds arrays
            if let fromTxId = item.transactionId {
                batch.updateData(
                    ["itemIds": FieldValue.arrayRemove([itemId])],
                    forDocumentAt: "\(txPath)/\(fromTxId)"
                )
            }
            batch.updateData(
                ["itemIds": FieldValue.arrayUnion([itemId])],
                forDocumentAt: "\(txPath)/\(destinationTransactionId)"
            )

            // Correction intent edge (audit association edge is created server-side
            // by onItemTransactionIdChanged when the item's transactionId changes)
            var edge: [String: Any] = [
                "accountId": accountId,
                "itemId": itemId,
                "toTransactionId": destinationTransactionId,
                "fromProjectId": destinationProjectId,
                "toProjectId": destinationProjectId,
                "movementKind": "correction",
                "source": "app",
                "note": "Reassigned to transaction",
                "createdAt": FieldValue.serverTimestamp(),
            ]
            if let fromTxId = item.transactionId { edge["fromTransactionId"] = fromTxId }
            if let userId { edge["createdBy"] = userId }
            batch.setDataAutoId(edge, inCollection: edgesPath)
        }

        try await batch.commit()
    }

    // MARK: - Return to Transaction

    /// Moves items to a return-type transaction within the same project.
    /// Manages `itemIds` arrays atomically. Creates a `"returned"` lineage edge
    /// client-side for immediate offline-first UI (the server also creates one
    /// via `onItemTransactionIdChanged`, but the client edge lands faster).
    func returnToTransaction(
        items: [Item],
        destinationTransactionId: String,
        destinationBudgetCategoryId: String? = nil,
        accountId: String,
        userId: String? = nil
    ) async throws {
        guard !items.isEmpty else { return }

        let batch = makeBatch()
        let itemsPath = "accounts/\(accountId)/items"
        let txPath = "accounts/\(accountId)/transactions"
        let edgesPath = "accounts/\(accountId)/lineageEdges"

        for item in items {
            guard let itemId = item.id else { continue }

            // Update item's transaction link and status (projectId stays the same)
            var itemUpdate: [String: Any] = [
                "transactionId": destinationTransactionId,
                "status": ItemStatus.returned.rawValue,
                "updatedAt": FieldValue.serverTimestamp(),
            ]
            if item.budgetCategoryId == nil, let categoryId = destinationBudgetCategoryId {
                itemUpdate["budgetCategoryId"] = categoryId
            }
            if item.projectPriceCents == nil, let purchasePrice = item.purchasePriceCents {
                itemUpdate["projectPriceCents"] = purchasePrice
            }
            batch.updateData(itemUpdate, forDocumentAt: "\(itemsPath)/\(itemId)")

            // Move item between transaction itemIds arrays
            if let fromTxId = item.transactionId {
                batch.updateData(
                    ["itemIds": FieldValue.arrayRemove([itemId])],
                    forDocumentAt: "\(txPath)/\(fromTxId)"
                )
            }
            batch.updateData(
                ["itemIds": FieldValue.arrayUnion([itemId])],
                forDocumentAt: "\(txPath)/\(destinationTransactionId)"
            )

            // "returned" intent edge
            var edge: [String: Any] = [
                "accountId": accountId,
                "itemId": itemId,
                "toTransactionId": destinationTransactionId,
                "movementKind": "returned",
                "source": "app",
                "createdAt": FieldValue.serverTimestamp(),
            ]
            if let fromTxId = item.transactionId { edge["fromTransactionId"] = fromTxId }
            if let projectId = item.projectId {
                edge["fromProjectId"] = projectId
                edge["toProjectId"] = projectId  // same project — returns don't cross scopes
            }
            if let userId { edge["createdBy"] = userId }
            batch.setDataAutoId(edge, inCollection: edgesPath)
        }

        try await batch.commit()
    }

    // MARK: - Pure Helpers (internal for testability)

    /// Frozen amount snapshot for a batch of items.
    /// Matches mcp-server/src/tools/inventory-operations.ts `computeBatchTotals`.
    ///
    /// - `subtotalCents`: sum of (projectPriceCents ?? purchasePriceCents ?? 0)
    /// - `amountCents`: sum of per-item price-with-tax. If taxRatePct > 0,
    ///   each item contributes round(price * (1 + taxRatePct / 100)). Otherwise, price.
    static func computeBatchTotals(_ items: [Item]) -> (subtotalCents: Int, amountCents: Int) {
        var subtotalCents = 0
        var amountCents = 0
        for item in items {
            let price = item.projectPriceCents ?? item.purchasePriceCents ?? 0
            let rate = item.taxRatePct ?? 0
            subtotalCents += price
            if rate > 0 {
                amountCents += Int((Double(price) * (1 + rate / 100)).rounded())
            } else {
                amountCents += price
            }
        }
        return (subtotalCents, amountCents)
    }

    /// Today's date as a yyyy-MM-dd string for `transactionDate`.
    static func todayDateString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date())
    }
}
