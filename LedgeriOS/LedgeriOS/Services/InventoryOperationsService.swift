import FirebaseFirestore

// MARK: - Errors

enum InventoryOperationError: Error {
    /// Reserved for legacy callers that try to perform an unsupported correction.
    case crossScopeReassign

    /// Batch exceeds the 100-item cap. Firestore batch writes allow 500 docs;
    /// 100 items keeps us well under with item updates + txn writes + lineage edges.
    case batchSizeExceeded

    /// sellItemsFromProjectToProject requires all items to be in the same source project.
    case mixedSourceProjects

    /// sellItemsFromProjectToProject source and destination are the same project.
    case sameSourceAndDestination

    /// sellItemsFromProjectToProject requires all items to be in a project (not inventory).
    case itemsNotInProject

    /// Inventory movement writers require persisted item documents with IDs.
    case itemsMissingIds

    /// Source project egress needs the item's current project budget category
    /// so the source project budget can subtract from the right category.
    case missingSourceBudgetCategory

    /// A destination assignment references an item outside the movement.
    case invalidDestinationSpaceAssignment

    /// A requested destination space does not exist.
    case destinationSpaceNotFound

    /// A requested destination space belongs to another project or inventory.
    case destinationSpaceScopeMismatch
}

struct InventorySpaceScope: Sendable, Equatable {
    let projectId: String?
}

// MARK: - Service

/// Multi-step atomic Firestore operations for inventory movements:
/// purchase into project, sell to inventory, return to inventory, move to inventory
/// (origin-aware split), sell project items to project, reassign (within-scope),
/// return to transaction.
///
/// ## Per-Batch Inventory Movement Transactions
/// Inventory → project creates ONE new Purchase transaction with an auto-ID.
/// Project → inventory acquisition creates ONE new Sale transaction.
/// Accounting shape fields (amountCents, budgetCategoryId, type, source,
/// projectId) are frozen at creation and never mutated. `itemIds` tracks
/// current membership and can change when items leave via returns/sales.
///
/// Inventory movement direction is implicit in the transaction shape:
///   - Inventory → project: `type == .purchase`, `source` is the inventory
///     label, and `budgetCategoryId` is set (destination category).
///   - Project → inventory acquisition: `type == .sale`, `source` is the
///     inventory label, and `budgetCategoryId` is the source project category.
///
/// This leverages the invariant `item.projectId == null ↔ item.budgetCategoryId == null`.
///
/// ## Return vs. Sale-to-Inventory (project → inventory)
/// Items leaving a project for inventory take one of two financial paths:
///   - **Return-to-Inventory**: item originally came from inventory and is
///     going home. Creates a `Return` transaction.
///   - **Sale-to-Inventory**: item originated in the project (was never in
///     inventory before). The business is acquiring it. Creates a `Sale`
///     transaction with `inventorySaleDirection = .projectToBusiness`.
///
/// Origin is derived from `Item.currentSource` vs. `Item.source`: when
/// `currentSource == source` (or currentSource is nil), the item was never
/// moved through inventory → Sale-to-Inventory. Otherwise → Return.
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
    private let loadSpaceScope: @Sendable (_ accountId: String, _ spaceId: String) async throws -> InventorySpaceScope?

    init(
        makeBatch: @escaping @Sendable () -> any BatchWriting = { FirestoreBatchWriter() },
        loadSpaceScope: @escaping @Sendable (_ accountId: String, _ spaceId: String) async throws -> InventorySpaceScope? = { accountId, spaceId in
            let snapshot = try await Firestore.firestore()
                .document("accounts/\(accountId)/spaces/\(spaceId)")
                .getDocument()
            guard snapshot.exists else { return nil }
            return InventorySpaceScope(projectId: snapshot.data()?["projectId"] as? String)
        }
    ) {
        self.makeBatch = makeBatch
        self.loadSpaceScope = loadSpaceScope
    }

    private static func requireItemIds(_ items: [Item]) throws -> [String] {
        let ids = items.compactMap(\.id)
        guard ids.count == items.count else { throw InventoryOperationError.itemsMissingIds }
        return ids
    }

    private static func sourceCategoryGroups(_ items: [Item]) throws -> [(categoryId: String, items: [Item])] {
        var order: [String] = []
        var groups: [String: [Item]] = [:]

        for item in items {
            guard let rawCategoryId = item.budgetCategoryId?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawCategoryId.isEmpty else {
                throw InventoryOperationError.missingSourceBudgetCategory
            }
            if groups[rawCategoryId] == nil {
                order.append(rawCategoryId)
                groups[rawCategoryId] = []
            }
            groups[rawCategoryId]?.append(item)
        }

        return order.map { ($0, groups[$0] ?? []) }
    }

    private func validatedDestinationSpaceIds(
        items: [Item],
        destinationProjectId: String,
        destinationSpaceIdsByItem: [String: String],
        accountId: String
    ) async throws -> [String: String] {
        guard !destinationSpaceIdsByItem.isEmpty else { return [:] }
        let itemIds = Set(try Self.requireItemIds(items))
        guard Set(destinationSpaceIdsByItem.keys).isSubset(of: itemIds) else {
            throw InventoryOperationError.invalidDestinationSpaceAssignment
        }

        var scopesBySpaceId: [String: InventorySpaceScope] = [:]
        var normalized: [String: String] = [:]
        for (itemId, spaceId) in destinationSpaceIdsByItem {
            let trimmed = spaceId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw InventoryOperationError.destinationSpaceNotFound
            }
            let scope: InventorySpaceScope
            if let cached = scopesBySpaceId[trimmed] {
                scope = cached
            } else {
                guard let loaded = try await loadSpaceScope(accountId, trimmed) else {
                    throw InventoryOperationError.destinationSpaceNotFound
                }
                scopesBySpaceId[trimmed] = loaded
                scope = loaded
            }
            guard scope.projectId == destinationProjectId else {
                throw InventoryOperationError.destinationSpaceScopeMismatch
            }
            normalized[itemId] = trimmed
        }
        return normalized
    }

    // MARK: - Sell to Project

    /// Purchases items from business inventory (or another project) into a destination project.
    /// Creates ONE new Purchase transaction per call. No long-lived aggregators.
    ///
    /// The Purchase transaction's accounting shape (amountCents,
    /// budgetCategoryId, projectId, type, source) is frozen at creation.
    func sellToProject(
        items: [Item],
        destinationProjectId: String,
        budgetCategoryId: String,
        accountId: String,
        inventoryLabel: String = Self.defaultInventoryLabel,
        userId: String? = nil,
        notes: String? = nil,
        resolveInventoryIntentTransactionId: String? = nil,
        destinationSpaceIdsByItem: [String: String] = [:]
    ) async throws {
        guard !items.isEmpty else { return }
        guard items.count <= Self.maxBatchItems else {
            throw InventoryOperationError.batchSizeExceeded
        }
        let itemIds = try Self.requireItemIds(items)
        let validatedSpaceIds = try await validatedDestinationSpaceIds(
            items: items,
            destinationProjectId: destinationProjectId,
            destinationSpaceIdsByItem: destinationSpaceIdsByItem,
            accountId: accountId
        )

        let batch = makeBatch()
        let itemsPath = "accounts/\(accountId)/items"
        let txPath = "accounts/\(accountId)/transactions"
        let edgesPath = "accounts/\(accountId)/lineageEdges"
        let pbcPath = "accounts/\(accountId)/projects/\(destinationProjectId)/budgetCategories"

        // Frozen amount snapshot
        let totals = Self.computeBatchTotals(items)

        // 1. Create new Purchase transaction (auto-ID, frozen accounting shape)
        let purchaseId = UUID().uuidString
        let purchaseDocPath = "\(txPath)/\(purchaseId)"
        let today = Self.todayDateString()
        var purchaseFields: [String: Any] = [
            "type": "Purchase",
            "source": inventoryLabel,
            "projectId": destinationProjectId,
            "budgetCategoryId": budgetCategoryId,
            "amountCents": totals.amountCents,
            "subtotalCents": totals.subtotalCents,
            "itemIds": itemIds,
            "isComplete": true,
            "transactionDate": today,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if let notes { purchaseFields["notes"] = notes }
        if let userId { purchaseFields["createdBy"] = userId }
        batch.setData(purchaseFields, forDocumentAt: purchaseDocPath, merge: false)

        // 2. Update each item
        for item in items {
            guard let itemId = item.id else { continue }

            var itemUpdate: [String: Any] = [
                "projectId": destinationProjectId,
                "budgetCategoryId": budgetCategoryId,
                "status": "purchased",
                "transactionId": purchaseId,
                "spaceId": NSNull(),
                // Immediate source denormalized for search. Original `source`
                // (vendor) is intentionally left untouched — preserved for returns.
                "currentSource": inventoryLabel,
                "updatedAt": FieldValue.serverTimestamp(),
            ]
            if let destinationSpaceId = validatedSpaceIds[itemId] {
                itemUpdate["spaceId"] = destinationSpaceId
            }
            let projectPrice = Self.projectPriceForMovement(item)
            if projectPrice > 0 {
                itemUpdate["projectPriceCents"] = projectPrice
            }
            batch.updateData(itemUpdate, forDocumentAt: "\(itemsPath)/\(itemId)")

            // 3. Remove item from its source transaction's active membership.
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
                "toTransactionId": purchaseId,
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


        if let resolveInventoryIntentTransactionId {
            var resolutionFields: [String: Any] = [
                "inventoryIntentResolvedAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
            ]
            if let userId { resolutionFields["updatedBy"] = userId }
            batch.updateData(
                resolutionFields,
                forDocumentAt: "\(txPath)/\(resolveInventoryIntentTransactionId)"
            )
        }

        try await batch.commit()
    }

    // MARK: - Return to Inventory

    /// Moves items from a project back to business inventory.
    /// Creates a Return transaction whose `source` defaults to
    /// `"Business Inventory"`; pass `inventoryLabel` for a branded label.
    /// Items have budgetCategoryId and projectId wiped (inventory invariant).
    ///
    /// `returnedPaidItemCredits` — runtime invoice contexts for items already
    /// charged on a paid invoice. These create created-invoice credit lines in the
    /// same batch as the return. Pass an empty array when no paid credits apply.
    func returnToInventory(
        items: [Item],
        accountId: String,
        inventoryLabel: String = Self.defaultInventoryLabel,
        userId: String? = nil,
        notes: String? = nil,
        returnedPaidItemCredits: [InvoiceLineCalculations.ReturnedPaidItemCreditContext] = []
    ) async throws {
        guard !items.isEmpty else { return }
        guard items.count <= Self.maxBatchItems else {
            throw InventoryOperationError.batchSizeExceeded
        }
        _ = try Self.requireItemIds(items)

        let batch = makeBatch()
        let itemsPath = "accounts/\(accountId)/items"
        let txPath = "accounts/\(accountId)/transactions"
        let edgesPath = "accounts/\(accountId)/lineageEdges"

        let today = Self.todayDateString()
        let categoryGroups = try Self.sourceCategoryGroups(items)

        for group in categoryGroups {
            let groupItemIds = group.items.compactMap(\.id)
            let returnAmount = group.items.reduce(0) { $0 + ($1.purchasePriceCents ?? 0) }
            let sourceProjectId: Any = group.items.first?.projectId as Any? ?? NSNull()

            // 1. Create Return transaction
            let returnId = UUID().uuidString
            let returnDocPath = "\(txPath)/\(returnId)"
            var returnFields: [String: Any] = [
                "type": "Return",
                "source": inventoryLabel,
                "projectId": sourceProjectId,
                "budgetCategoryId": group.categoryId,
                "amountCents": returnAmount,
                "subtotalCents": returnAmount,
                "itemIds": groupItemIds,
                "status": "completed",
                "transactionDate": today,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
            ]
            if let notes { returnFields["notes"] = notes }
            if let userId { returnFields["createdBy"] = userId }
            batch.setData(returnFields, forDocumentAt: returnDocPath, merge: false)

            // 2. Update each item
            for item in group.items {
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

                // 3. Remove from source transaction's active membership.
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
        }

        // 5. Draft invoice credits for items previously charged on a paid invoice.
        Self.appendReturnedPaidItemCredits(
            returnedItems: items,
            returnedPaidItemCredits: returnedPaidItemCredits,
            accountId: accountId,
            batch: batch,
            userId: userId
        )

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
        _ = try Self.requireItemIds(items)

        let batch = makeBatch()
        let itemsPath = "accounts/\(accountId)/items"
        let txPath = "accounts/\(accountId)/transactions"
        let edgesPath = "accounts/\(accountId)/lineageEdges"

        let today = Self.todayDateString()
        let categoryGroups = try Self.sourceCategoryGroups(items)

        for group in categoryGroups {
            let totals = Self.computePurchasePriceTotals(group.items)
            let sourceProjectId: Any = group.items.first?.projectId as Any? ?? NSNull()

            // 1. Create Sale transaction (project → inventory direction).
            let saleId = UUID().uuidString
            var saleFields: [String: Any] = [
                "type": "Sale",
                "source": inventoryLabel,
                "projectId": sourceProjectId,
                "budgetCategoryId": group.categoryId,
                "amountCents": totals.amountCents,
                "subtotalCents": totals.subtotalCents,
                "itemIds": group.items.compactMap(\.id),
                "isComplete": true,
                "transactionDate": today,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
            ]
            if let notes { saleFields["notes"] = notes }
            if let userId { saleFields["createdBy"] = userId }
            batch.setData(saleFields, forDocumentAt: "\(txPath)/\(saleId)", merge: false)

            // 2. Update each item — lands in inventory
            for item in group.items {
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

                // 3. Remove from source transaction's active membership.
                if let fromTxId = item.transactionId {
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
        notes: String? = nil,
        returnedPaidItemCredits: [InvoiceLineCalculations.ReturnedPaidItemCreditContext] = []
    ) async throws {
        guard !items.isEmpty else { return }
        guard items.count <= Self.maxBatchItems else {
            throw InventoryOperationError.batchSizeExceeded
        }
        _ = try Self.requireItemIds(items)

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
                notes: notes,
                returnedPaidItemCredits: returnedPaidItemCredits
            )
            return
        }

        // Mixed: write both transactions + item updates in one atomic batch.
        let batch = makeBatch()
        let itemsPath = "accounts/\(accountId)/items"
        let txPath = "accounts/\(accountId)/transactions"
        let edgesPath = "accounts/\(accountId)/lineageEdges"

        let today = Self.todayDateString()

        let returnGroups = try Self.sourceCategoryGroups(split.returnItems)
        let saleGroups = try Self.sourceCategoryGroups(split.saleItems)
        var returnTxByItemId: [String: String] = [:]
        var saleTxByItemId: [String: String] = [:]

        // Return legs
        for group in returnGroups {
            let returnId = UUID().uuidString
            let returnAmount = group.items.reduce(0) { $0 + ($1.purchasePriceCents ?? 0) }
            let returnSourceProjectId: Any = group.items.first?.projectId as Any? ?? NSNull()
            var returnFields: [String: Any] = [
                "type": "Return",
                "source": inventoryLabel,
                "projectId": returnSourceProjectId,
                "budgetCategoryId": group.categoryId,
                "amountCents": returnAmount,
                "subtotalCents": returnAmount,
                "itemIds": group.items.compactMap(\.id),
                "status": "completed",
                "transactionDate": today,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
            ]
            if let notes { returnFields["notes"] = notes }
            if let userId { returnFields["createdBy"] = userId }
            batch.setData(returnFields, forDocumentAt: "\(txPath)/\(returnId)", merge: false)
            for item in group.items {
                if let itemId = item.id { returnTxByItemId[itemId] = returnId }
            }
        }

        // Sale legs
        for group in saleGroups {
            let saleId = UUID().uuidString
            let saleTotals = Self.computePurchasePriceTotals(group.items)
            let saleSourceProjectId: Any = group.items.first?.projectId as Any? ?? NSNull()
            var saleFields: [String: Any] = [
                "type": "Sale",
                "source": inventoryLabel,
                "projectId": saleSourceProjectId,
                "budgetCategoryId": group.categoryId,
                "amountCents": saleTotals.amountCents,
                "subtotalCents": saleTotals.subtotalCents,
                "itemIds": group.items.compactMap(\.id),
                "isComplete": true,
                "transactionDate": today,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
            ]
            if let notes { saleFields["notes"] = notes }
            if let userId { saleFields["createdBy"] = userId }
            batch.setData(saleFields, forDocumentAt: "\(txPath)/\(saleId)", merge: false)
            for item in group.items {
                if let itemId = item.id { saleTxByItemId[itemId] = saleId }
            }
        }

        // Item updates + lineage edges
        for item in split.returnItems {
            guard let itemId = item.id else { continue }
            guard let returnId = returnTxByItemId[itemId] else { continue }
            batch.updateData([
                "projectId": NSNull(),
                "budgetCategoryId": NSNull(),
                "spaceId": NSNull(),
                "status": "purchased",
                "transactionId": returnId,
                "currentSource": inventoryLabel,
                "updatedAt": FieldValue.serverTimestamp(),
            ], forDocumentAt: "\(itemsPath)/\(itemId)")

            if let fromTxId = item.transactionId {
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
            guard let saleId = saleTxByItemId[itemId] else { continue }
            batch.updateData([
                "projectId": NSNull(),
                "budgetCategoryId": NSNull(),
                "spaceId": NSNull(),
                "status": "purchased",
                "transactionId": saleId,
                "currentSource": inventoryLabel,
                "updatedAt": FieldValue.serverTimestamp(),
            ], forDocumentAt: "\(itemsPath)/\(itemId)")

            if let fromTxId = item.transactionId {
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

        // Draft invoice credits only apply to the Return leg.
        Self.appendReturnedPaidItemCredits(
            returnedItems: split.returnItems,
            returnedPaidItemCredits: returnedPaidItemCredits,
            accountId: accountId,
            batch: batch,
            userId: userId
        )

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

    // MARK: - Sell Items From Project to Project

    /// Sells items from one project to another in a single atomic batch.
    /// The sale decomposes into two hops through inventory:
    ///
    /// **First hop (origin-aware):** items that previously passed through
    /// inventory leave the source project as a `Return` transaction; items
    /// that originated in the source project leave as a `Sale` (direction
    /// `.projectToBusiness`). Mixed batches write both first-hop transactions.
    ///
    /// **Second hop:** one `Purchase` transaction from inventory
    /// covering all items, landing them in the destination project.
    ///
    /// All items must be in the same source project.
    func sellItemsFromProjectToProject(
        items: [Item],
        destinationProjectId: String,
        destinationCategoryId: String,
        accountId: String,
        inventoryLabel: String = Self.defaultInventoryLabel,
        userId: String? = nil,
        notes: String? = nil,
        destinationSpaceIdsByItem: [String: String] = [:]
    ) async throws {
        guard !items.isEmpty else { return }
        guard items.count <= Self.maxBatchItems else {
            throw InventoryOperationError.batchSizeExceeded
        }
        let itemIds = try Self.requireItemIds(items)

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

        let validatedSpaceIds = try await validatedDestinationSpaceIds(
            items: items,
            destinationProjectId: destinationProjectId,
            destinationSpaceIdsByItem: destinationSpaceIdsByItem,
            accountId: accountId
        )

        let batch = makeBatch()
        let itemsPath = "accounts/\(accountId)/items"
        let txPath = "accounts/\(accountId)/transactions"
        let edgesPath = "accounts/\(accountId)/lineageEdges"
        let pbcPath = "accounts/\(accountId)/projects/\(destinationProjectId)/budgetCategories"

        let split = Self.splitByOrigin(items)
        let today = Self.todayDateString()

        let returnGroups = try Self.sourceCategoryGroups(split.returnItems)
        let saleGroups = try Self.sourceCategoryGroups(split.saleItems)
        var returnTxByItemId: [String: String] = [:]
        var saleTxByItemId: [String: String] = [:]

        // 1a. First hop — Return leg (items that came from inventory)
        for group in returnGroups {
            let id = UUID().uuidString
            let returnTotals = Self.computePurchasePriceTotals(group.items)
            var returnFields: [String: Any] = [
                "type": "Return",
                "source": inventoryLabel,
                "projectId": sourceProjectId,
                "budgetCategoryId": group.categoryId,
                "amountCents": returnTotals.amountCents,
                "subtotalCents": returnTotals.subtotalCents,
                "itemIds": group.items.compactMap(\.id),
                "status": "completed",
                "transactionDate": today,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
            ]
            if let notes { returnFields["notes"] = notes }
            if let userId { returnFields["createdBy"] = userId }
            batch.setData(returnFields, forDocumentAt: "\(txPath)/\(id)", merge: false)
            for item in group.items {
                if let itemId = item.id { returnTxByItemId[itemId] = id }
            }
        }

        // 1b. First hop — Sale-to-Inventory leg (items that originated here).
        for group in saleGroups {
            let id = UUID().uuidString
            let saleTotals = Self.computePurchasePriceTotals(group.items)
            var saleFields: [String: Any] = [
                "type": "Sale",
                "source": inventoryLabel,
                "projectId": sourceProjectId,
                "budgetCategoryId": group.categoryId,
                "amountCents": saleTotals.amountCents,
                "subtotalCents": saleTotals.subtotalCents,
                "itemIds": group.items.compactMap(\.id),
                "isComplete": true,
                "transactionDate": today,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
            ]
            if let notes { saleFields["notes"] = notes }
            if let userId { saleFields["createdBy"] = userId }
            batch.setData(saleFields, forDocumentAt: "\(txPath)/\(id)", merge: false)
            for item in group.items {
                if let itemId = item.id { saleTxByItemId[itemId] = id }
            }
        }

        // 2. Second hop — Purchase transaction (from inventory) covers all items
        let destPurchaseId = UUID().uuidString
        let totals = Self.computeBatchTotals(items)
        var destPurchaseFields: [String: Any] = [
            "type": "Purchase",
            "source": inventoryLabel,
            "projectId": destinationProjectId,
            "budgetCategoryId": destinationCategoryId,
            "amountCents": totals.amountCents,
            "subtotalCents": totals.subtotalCents,
            "itemIds": itemIds,
            "isComplete": true,
            "transactionDate": today,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if let notes { destPurchaseFields["notes"] = notes }
        if let userId { destPurchaseFields["createdBy"] = userId }
        batch.setData(destPurchaseFields, forDocumentAt: "\(txPath)/\(destPurchaseId)", merge: false)

        // 3. Update each item (lands in destination project) + lineage edges
        for item in items {
            guard let itemId = item.id else { continue }

            var itemUpdate: [String: Any] = [
                "projectId": destinationProjectId,
                "budgetCategoryId": destinationCategoryId,
                "status": "purchased",
                "transactionId": destPurchaseId,
                "spaceId": NSNull(),
                // sellItemsFromProjectToProject is modeled as two hops through inventory,
                // so the immediate source lands on the inventory label.
                "currentSource": inventoryLabel,
                "updatedAt": FieldValue.serverTimestamp(),
            ]
            if let destinationSpaceId = validatedSpaceIds[itemId] {
                itemUpdate["spaceId"] = destinationSpaceId
            }
            let projectPrice = Self.projectPriceForMovement(item)
            if projectPrice > 0 {
                itemUpdate["projectPriceCents"] = projectPrice
            }
            batch.updateData(itemUpdate, forDocumentAt: "\(itemsPath)/\(itemId)")

            // Remove from source transaction's active membership.
            if let fromTxId = item.transactionId {
                batch.updateData(
                    ["itemIds": FieldValue.arrayRemove([itemId])],
                    forDocumentAt: "\(txPath)/\(fromTxId)"
                )
            }

            // First-hop lineage edge — "returned" or "soldToInventory" per origin
            let cameFrom = Self.cameFromInventory(item)
            let firstHopTxId = cameFrom ? returnTxByItemId[itemId] : saleTxByItemId[itemId]
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

            // Second-hop lineage edge — purchased from inventory into destination
            var soldEdge: [String: Any] = [
                "accountId": accountId,
                "itemId": itemId,
                "fromProjectId": sourceProjectId,
                "toProjectId": destinationProjectId,
                "toTransactionId": destPurchaseId,
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

    // MARK: - Reassign to Project (correction only — no financial movement)

    /// Corrects items into a destination transaction/project. No financial records
    /// are created — this is for fixing misallocations, not selling inventory.
    func reassignToProject(
        items: [Item],
        destinationTransactionId: String,
        destinationProjectId: String,
        destinationBudgetCategoryId: String? = nil,
        accountId: String,
        userId: String? = nil
    ) async throws {
        guard !items.isEmpty else { return }
        _ = try Self.requireItemIds(items)

        let batch = makeBatch()
        let itemsPath = "accounts/\(accountId)/items"
        let txPath = "accounts/\(accountId)/transactions"
        let edgesPath = "accounts/\(accountId)/lineageEdges"
        let pbcPath = "accounts/\(accountId)/projects/\(destinationProjectId)/budgetCategories"

        for item in items {
            guard let itemId = item.id else { continue }

            // Update item's transaction link and corrected project scope.
            var itemUpdate: [String: Any] = [
                "projectId": destinationProjectId,
                "transactionId": destinationTransactionId,
                "spaceId": NSNull(),
                "updatedAt": FieldValue.serverTimestamp(),
            ]
            if let categoryId = destinationBudgetCategoryId {
                itemUpdate["budgetCategoryId"] = categoryId
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
                "fromProjectId": item.projectId as Any? ?? NSNull(),
                "toProjectId": destinationProjectId,
                "movementKind": "correction",
                "source": "app",
                "note": "Reassigned to project transaction",
                "createdAt": FieldValue.serverTimestamp(),
            ]
            if let fromTxId = item.transactionId { edge["fromTransactionId"] = fromTxId }
            if let userId { edge["createdBy"] = userId }
            batch.setDataAutoId(edge, inCollection: edgesPath)
        }

        if let categoryId = destinationBudgetCategoryId, categoryId != "uncategorized" {
            var catFields: [String: Any] = ["updatedAt": FieldValue.serverTimestamp()]
            if let userId { catFields["updatedBy"] = userId }
            batch.setData(catFields, forDocumentAt: "\(pbcPath)/\(categoryId)", merge: true)
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
        _ = try Self.requireItemIds(items)

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

    /// Frozen project-price snapshot for a batch of items.
    /// Matches mcp-server/src/tools/inventory-operations.ts `computeProjectPriceTotals`.
    ///
    /// Missing project prices are initialized from a positive purchase price.
    /// - `subtotalCents`: sum of resolved project prices
    /// - `amountCents`: sum of per-item price-with-tax. If taxRatePct > 0,
    ///   each item contributes round(price * (1 + taxRatePct / 100)). Otherwise, price.
    static func computeBatchTotals(_ items: [Item]) -> (subtotalCents: Int, amountCents: Int) {
        var subtotalCents = 0
        var amountCents = 0
        for item in items {
            let price = projectPriceForMovement(item)
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

    static func projectPriceForMovement(_ item: Item) -> Int {
        if let projectPrice = item.projectPriceCents, projectPrice > 0 {
            return projectPrice
        }
        if let purchasePrice = item.purchasePriceCents, purchasePrice > 0 {
            return purchasePrice
        }
        return 0
    }

    /// Frozen purchase-price snapshot for standalone project→inventory moves.
    static func computePurchasePriceTotals(_ items: [Item]) -> (subtotalCents: Int, amountCents: Int) {
        let subtotalCents = items.reduce(0) { $0 + ($1.purchasePriceCents ?? 0) }
        return (subtotalCents, subtotalCents)
    }

    /// Today's date as a yyyy-MM-dd string for `transactionDate`.
    static func todayDateString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date())
    }

    /// Append ordinary created-invoice credit lines for returning items that were
    /// previously charged on a paid invoice. This does not create transactions.
    static func appendReturnedPaidItemCredits(
        returnedItems: [Item],
        returnedPaidItemCredits: [InvoiceLineCalculations.ReturnedPaidItemCreditContext],
        accountId: String,
        batch: any BatchWriting,
        userId: String?
    ) {
        let returnedItemIds = Set(returnedItems.compactMap(\.id))
        let credits = returnedPaidItemCredits.filter { returnedItemIds.contains($0.itemId) }
        InvoiceService.appendReturnedPaidItemCreditInvoices(
            accountId: accountId,
            credits: credits,
            batch: batch,
            userId: userId
        )
    }
}
