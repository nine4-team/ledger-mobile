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
/// sell to project, sell to inventory, return to inventory, move to inventory
/// (origin-aware split), move between projects, reassign (within-scope),
/// return to transaction.
///
/// ## Per-Batch Sale Transactions (Bidirectional)
/// Each sell action creates ONE new immutable Sale transaction with an auto-ID.
/// Shape fields (amountCents, itemIds, budgetCategoryId, type, source,
/// projectId) are frozen at creation and never mutated.
///
/// Sale direction is implicit in the transaction shape — no dedicated field:
///   - Inventory → project: `source` is the inventory label AND
///     `budgetCategoryId` is set (destination category).
///   - Project → inventory: `source` is the inventory label AND
///     `budgetCategoryId` is absent (inventory items have no category).
///
/// This leverages the invariant `item.projectId == null ↔ item.budgetCategoryId == null`.
///
/// ## Return vs. Sale-to-Inventory (project → inventory)
/// Items moving from a project back to inventory take one of two paths:
///   - **Return-to-Inventory**: item originally came from inventory and is
///     going home. Creates a `Return` transaction.
///   - **Sale-to-Inventory**: item originated in the project (was never in
///     inventory before). The business is acquiring it. Creates a `Sale`
///     transaction with `inventorySaleDirection = .projectToBusiness`.
///
/// Origin is derived from `Item.currentSource` vs. `Item.source`: when
/// `currentSource == source` (or currentSource is nil), the item was never
/// moved through inventory → Sale-to-Inventory. Otherwise → Return.
/// `moveToInventory(items:)` applies the routing automatically.
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

    /// Returns `true` if the item's most recent scope entry was inventory,
    /// meaning a project→inventory move should be a Return (item going home).
    /// Returns `false` if the item originated in its current project and has
    /// never passed through inventory, meaning a project→inventory move should
    /// be a Sale-to-Inventory (business acquiring the item).
    ///
    /// Rule: `currentSource != source` ⇒ touched inventory (currentSource was
    /// overwritten with the inventory label on a prior sell/return/move).
    /// Legacy items with `currentSource == nil` fall back to `source`, which
    /// matches the original vendor → treated as originated-here.
    static func cameFromInventory(_ item: Item) -> Bool {
        let current = (item.currentSource ?? item.source ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let original = (item.source ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { return false }
        return current != original
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

        // Pre-fetch source tx types — frozen types (Sale, Return) must not have
        // their itemIds array mutated (Firestore rules reject; spec says immutable).
        let frozenSources = try await Self.frozenSourceTxIds(
            items: items, batch: batch, txPath: txPath
        )

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
                // Immediate source denormalized for search. Original `source`
                // (vendor) is intentionally left untouched — preserved for returns.
                "currentSource": inventoryLabel,
                "updatedAt": FieldValue.serverTimestamp(),
            ]
            // Backfill projectPriceCents for legacy items missing it
            if item.projectPriceCents == nil, let purchasePrice = item.purchasePriceCents {
                itemUpdate["projectPriceCents"] = purchasePrice
            }
            batch.updateData(itemUpdate, forDocumentAt: "\(itemsPath)/\(itemId)")

            // 3. Remove item from its source transaction's itemIds — skipped
            // when source is a frozen Sale/Return (itemIds is immutable there).
            if let fromTxId = item.transactionId, !frozenSources.contains(fromTxId) {
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

        let frozenSources = try await Self.frozenSourceTxIds(
            items: items, batch: batch, txPath: txPath
        )

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
                // Immediate source becomes the inventory label now that the
                // item is back in inventory. Original `source` (vendor) is
                // preserved so the designer can still route a return to the
                // store it was originally bought from.
                "currentSource": inventoryLabel,
                "updatedAt": FieldValue.serverTimestamp(),
            ], forDocumentAt: "\(itemsPath)/\(itemId)")

            // 3. Remove from source transaction's itemIds — skipped for
            // frozen Sale/Return sources.
            if let fromTxId = item.transactionId, !frozenSources.contains(fromTxId) {
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

    // MARK: - Sell to Inventory

    /// Sells project-originated items from a project into business inventory.
    /// Used when the business acquires items that were never previously in
    /// inventory (e.g. the designer bought them for the project; the business
    /// is now taking them on as inventory). Creates a `Sale` transaction with
    /// `inventorySaleDirection = .projectToBusiness`.
    ///
    /// Budget effect: the source project's budget decreases by
    /// `-1 × amountCents` (same sign as Return-to-Inventory).
    ///
    /// All items must be in the same source project and must have the
    /// originated-here property (`cameFromInventory(item) == false`). The
    /// caller (typically `moveToInventory`) is responsible for this check;
    /// this method does not re-validate origin.
    func sellToInventory(
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

        let frozenSources = try await Self.frozenSourceTxIds(
            items: items, batch: batch, txPath: txPath
        )

        let totals = Self.computeBatchTotals(items)
        let sourceProjectId: Any = items.first?.projectId as Any? ?? NSNull()

        // 1. Create Sale transaction (project → inventory direction).
        // Direction is encoded implicitly: `source` is the inventory label and
        // `budgetCategoryId` is absent (inventory items have no category). A
        // Sale with a set budgetCategoryId goes inventory → project.
        let saleId = UUID().uuidString
        let today = Self.todayDateString()
        var saleFields: [String: Any] = [
            "type": "Sale",
            "source": inventoryLabel,
            "projectId": sourceProjectId,
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
        batch.setData(saleFields, forDocumentAt: "\(txPath)/\(saleId)", merge: false)

        // 2. Update each item — lands in inventory
        for item in items {
            guard let itemId = item.id else { continue }

            batch.updateData([
                "projectId": NSNull(),
                "budgetCategoryId": NSNull(),
                "spaceId": NSNull(),
                "status": "purchased",
                "transactionId": saleId,
                // The business acquired the item; its immediate source is now
                // the inventory label. Original `source` (vendor) is preserved.
                "currentSource": inventoryLabel,
                "updatedAt": FieldValue.serverTimestamp(),
            ], forDocumentAt: "\(itemsPath)/\(itemId)")

            // 3. Remove from source transaction's itemIds — skipped for frozen sources
            if let fromTxId = item.transactionId, !frozenSources.contains(fromTxId) {
                batch.updateData(
                    ["itemIds": FieldValue.arrayRemove([itemId])],
                    forDocumentAt: "\(txPath)/\(fromTxId)"
                )
            }

            // 4. Lineage edge — acquired into inventory (sold from project to business)
            var edge: [String: Any] = [
                "accountId": accountId,
                "itemId": itemId,
                "toTransactionId": saleId,
                "movementKind": "soldToInventory",
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

    // MARK: - Move to Inventory (origin-aware routing)

    /// Moves items from a project to business inventory, routing each item to
    /// the right transaction type based on its origin:
    ///   - Items that passed through inventory before → Return transaction
    ///   - Items that originated in this project → Sale transaction
    ///     (`inventorySaleDirection = .projectToBusiness`)
    ///
    /// Mixed-origin batches write both transactions in a single atomic Firestore
    /// batch. Pre-computes the split so the UI can show a preview before this
    /// method is called (see `splitByOrigin`).
    func moveToInventory(
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

        let split = Self.splitByOrigin(items)

        // Single-path batches reuse the dedicated writers for simplicity.
        if split.returnItems.isEmpty {
            try await sellToInventory(
                items: split.saleItems,
                accountId: accountId,
                inventoryLabel: inventoryLabel,
                userId: userId,
                notes: notes
            )
            return
        }
        if split.saleItems.isEmpty {
            try await returnToInventory(
                items: split.returnItems,
                accountId: accountId,
                inventoryLabel: inventoryLabel,
                userId: userId,
                notes: notes
            )
            return
        }

        // Mixed: write both transactions + item updates in one atomic batch.
        let batch = makeBatch()
        let itemsPath = "accounts/\(accountId)/items"
        let txPath = "accounts/\(accountId)/transactions"
        let edgesPath = "accounts/\(accountId)/lineageEdges"

        let frozenSources = try await Self.frozenSourceTxIds(
            items: items, batch: batch, txPath: txPath
        )
        let today = Self.todayDateString()

        // Return leg
        let returnId = UUID().uuidString
        let returnAmount = split.returnItems.reduce(0) { $0 + ($1.purchasePriceCents ?? 0) }
        let returnSourceProjectId: Any = split.returnItems.first?.projectId as Any? ?? NSNull()
        var returnFields: [String: Any] = [
            "type": "Return",
            "source": inventoryLabel,
            "projectId": returnSourceProjectId,
            "amountCents": returnAmount,
            "itemIds": split.returnItems.compactMap(\.id),
            "status": "completed",
            "transactionDate": today,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if let notes { returnFields["notes"] = notes }
        if let userId { returnFields["createdBy"] = userId }
        batch.setData(returnFields, forDocumentAt: "\(txPath)/\(returnId)", merge: false)

        // Sale leg (project → inventory). Direction encoded implicitly by
        // absent `budgetCategoryId` — see sellToInventory.
        let saleId = UUID().uuidString
        let saleTotals = Self.computeBatchTotals(split.saleItems)
        let saleSourceProjectId: Any = split.saleItems.first?.projectId as Any? ?? NSNull()
        var saleFields: [String: Any] = [
            "type": "Sale",
            "source": inventoryLabel,
            "projectId": saleSourceProjectId,
            "amountCents": saleTotals.amountCents,
            "subtotalCents": saleTotals.subtotalCents,
            "itemIds": split.saleItems.compactMap(\.id),
            "status": "completed",
            "isComplete": true,
            "transactionDate": today,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if let notes { saleFields["notes"] = notes }
        if let userId { saleFields["createdBy"] = userId }
        batch.setData(saleFields, forDocumentAt: "\(txPath)/\(saleId)", merge: false)

        // Item updates + lineage edges
        for item in split.returnItems {
            guard let itemId = item.id else { continue }
            batch.updateData([
                "projectId": NSNull(),
                "budgetCategoryId": NSNull(),
                "spaceId": NSNull(),
                "status": "purchased",
                "transactionId": returnId,
                "currentSource": inventoryLabel,
                "updatedAt": FieldValue.serverTimestamp(),
            ], forDocumentAt: "\(itemsPath)/\(itemId)")

            if let fromTxId = item.transactionId, !frozenSources.contains(fromTxId) {
                batch.updateData(
                    ["itemIds": FieldValue.arrayRemove([itemId])],
                    forDocumentAt: "\(txPath)/\(fromTxId)"
                )
            }

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

        for item in split.saleItems {
            guard let itemId = item.id else { continue }
            batch.updateData([
                "projectId": NSNull(),
                "budgetCategoryId": NSNull(),
                "spaceId": NSNull(),
                "status": "purchased",
                "transactionId": saleId,
                "currentSource": inventoryLabel,
                "updatedAt": FieldValue.serverTimestamp(),
            ], forDocumentAt: "\(itemsPath)/\(itemId)")

            if let fromTxId = item.transactionId, !frozenSources.contains(fromTxId) {
                batch.updateData(
                    ["itemIds": FieldValue.arrayRemove([itemId])],
                    forDocumentAt: "\(txPath)/\(fromTxId)"
                )
            }

            var edge: [String: Any] = [
                "accountId": accountId,
                "itemId": itemId,
                "toTransactionId": saleId,
                "movementKind": "soldToInventory",
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

    /// Partitions items by origin into the Return leg (from inventory) and
    /// Sale leg (originated in project). Preserves input order within each leg.
    static func splitByOrigin(_ items: [Item]) -> (returnItems: [Item], saleItems: [Item]) {
        var returnItems: [Item] = []
        var saleItems: [Item] = []
        for item in items {
            if cameFromInventory(item) {
                returnItems.append(item)
            } else {
                saleItems.append(item)
            }
        }
        return (returnItems, saleItems)
    }

    // MARK: - Move Between Projects

    /// Moves items from one project to another in a single atomic batch.
    /// The move decomposes into two hops through inventory:
    ///
    /// **First hop (origin-aware):** items that previously passed through
    /// inventory leave the source project as a `Return` transaction; items
    /// that originated in the source project leave as a `Sale` (direction
    /// `.projectToBusiness`). Mixed batches write both first-hop transactions.
    ///
    /// **Second hop:** one `Sale` transaction (direction `.businessToProject`)
    /// covering all items, landing them in the destination project.
    ///
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

        let frozenSources = try await Self.frozenSourceTxIds(
            items: items, batch: batch, txPath: txPath
        )

        let split = Self.splitByOrigin(items)
        let today = Self.todayDateString()

        // 1a. First hop — Return leg (items that came from inventory)
        var returnId: String? = nil
        if !split.returnItems.isEmpty {
            let id = UUID().uuidString
            returnId = id
            let returnAmount = split.returnItems.reduce(0) { $0 + ($1.purchasePriceCents ?? 0) }
            var returnFields: [String: Any] = [
                "type": "Return",
                "source": inventoryLabel,
                "projectId": sourceProjectId,
                "amountCents": returnAmount,
                "itemIds": split.returnItems.compactMap(\.id),
                "status": "completed",
                "transactionDate": today,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
            ]
            if let notes { returnFields["notes"] = notes }
            if let userId { returnFields["createdBy"] = userId }
            batch.setData(returnFields, forDocumentAt: "\(txPath)/\(id)", merge: false)
        }

        // 1b. First hop — Sale-to-Inventory leg (items that originated here).
        // Direction (project → inventory) encoded implicitly via absent
        // `budgetCategoryId`.
        var firstSaleId: String? = nil
        if !split.saleItems.isEmpty {
            let id = UUID().uuidString
            firstSaleId = id
            let saleTotals = Self.computeBatchTotals(split.saleItems)
            var saleFields: [String: Any] = [
                "type": "Sale",
                "source": inventoryLabel,
                "projectId": sourceProjectId,
                "amountCents": saleTotals.amountCents,
                "subtotalCents": saleTotals.subtotalCents,
                "itemIds": split.saleItems.compactMap(\.id),
                "status": "completed",
                "isComplete": true,
                "transactionDate": today,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
            ]
            if let notes { saleFields["notes"] = notes }
            if let userId { saleFields["createdBy"] = userId }
            batch.setData(saleFields, forDocumentAt: "\(txPath)/\(id)", merge: false)
        }

        // 2. Second hop — Sale transaction (to destination project) covers all items
        let destSaleId = UUID().uuidString
        let totals = Self.computeBatchTotals(items)
        let itemIdList = items.compactMap(\.id)
        var destSaleFields: [String: Any] = [
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
        if let notes { destSaleFields["notes"] = notes }
        if let userId { destSaleFields["createdBy"] = userId }
        batch.setData(destSaleFields, forDocumentAt: "\(txPath)/\(destSaleId)", merge: false)

        // 3. Update each item (lands in destination project) + lineage edges
        for item in items {
            guard let itemId = item.id else { continue }

            var itemUpdate: [String: Any] = [
                "projectId": destinationProjectId,
                "budgetCategoryId": destinationCategoryId,
                "status": "purchased",
                "transactionId": destSaleId,
                "spaceId": NSNull(),
                // moveBetweenProjects is modeled as two hops through inventory,
                // so the immediate source lands on the inventory label.
                "currentSource": inventoryLabel,
                "updatedAt": FieldValue.serverTimestamp(),
            ]
            if item.projectPriceCents == nil, let purchasePrice = item.purchasePriceCents {
                itemUpdate["projectPriceCents"] = purchasePrice
            }
            batch.updateData(itemUpdate, forDocumentAt: "\(itemsPath)/\(itemId)")

            // Remove from source transaction's itemIds — skipped for frozen sources
            if let fromTxId = item.transactionId, !frozenSources.contains(fromTxId) {
                batch.updateData(
                    ["itemIds": FieldValue.arrayRemove([itemId])],
                    forDocumentAt: "\(txPath)/\(fromTxId)"
                )
            }

            // First-hop lineage edge — "returned" or "soldToInventory" per origin
            let cameFrom = Self.cameFromInventory(item)
            let firstHopTxId = cameFrom ? returnId : firstSaleId
            let firstHopKind = cameFrom ? "returned" : "soldToInventory"
            if let firstHopTxId {
                var firstEdge: [String: Any] = [
                    "accountId": accountId,
                    "itemId": itemId,
                    "fromProjectId": sourceProjectId,
                    "toTransactionId": firstHopTxId,
                    "movementKind": firstHopKind,
                    "source": "app",
                    "createdAt": FieldValue.serverTimestamp(),
                ]
                if let fromTxId = item.transactionId { firstEdge["fromTransactionId"] = fromTxId }
                if let userId { firstEdge["createdBy"] = userId }
                batch.setDataAutoId(firstEdge, inCollection: edgesPath)
            }

            // Second-hop lineage edge — "sold" into destination
            var soldEdge: [String: Any] = [
                "accountId": accountId,
                "itemId": itemId,
                "fromProjectId": sourceProjectId,
                "toProjectId": destinationProjectId,
                "toTransactionId": destSaleId,
                "movementKind": "sold",
                "source": "app",
                "createdAt": FieldValue.serverTimestamp(),
            ]
            if let fromTxId = item.transactionId { soldEdge["fromTransactionId"] = fromTxId }
            if let userId { soldEdge["createdBy"] = userId }
            batch.setDataAutoId(soldEdge, inCollection: edgesPath)
        }

        // 4. Auto-enable destination budget category
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

    /// Returns the set of source transaction IDs whose `type` is "Sale" or
    /// "Return" — these have frozen shape fields per Firestore rules, so
    /// the service must not attempt `arrayRemove` on their `itemIds`.
    ///
    /// Deduplicates across items so the same source is fetched once.
    static func frozenSourceTxIds(
        items: [Item],
        batch: any BatchWriting,
        txPath: String
    ) async throws -> Set<String> {
        let uniqueSourceIds = Set(items.compactMap(\.transactionId))
        guard !uniqueSourceIds.isEmpty else { return [] }

        var frozen: Set<String> = []
        for txId in uniqueSourceIds {
            let type = try await batch.stringField("type", atPath: "\(txPath)/\(txId)")
            if type == "Sale" || type == "Return" {
                frozen.insert(txId)
            }
        }
        return frozen
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
