import FirebaseFirestore

enum ItemAssociationError: LocalizedError {
    case itemMissingId
    case itemNotFound(String)
    case transactionNotFound(String)
    case invalidBudgetCategory
    case scopeMismatch
    case genericTransactionUpdate
    case unsupportedBulkUpdateField(String)
    case linkedItemCreation
    case genericItemIdsUpdate

    var errorDescription: String? {
        switch self {
        case .itemMissingId: "Item is missing its document ID."
        case .itemNotFound(let id): "Item \(id) was not found."
        case .transactionNotFound(let id): "Transaction \(id) was not found."
        case .invalidBudgetCategory: "Project records require a real budget category; inventory records may not carry one."
        case .scopeMismatch: "The item and transaction must belong to the same project."
        case .genericTransactionUpdate: "Use setTransaction or clearTransaction to change an item's transaction."
        case .unsupportedBulkUpdateField(let field): "Bulk item updates do not support the \(field) field."
        case .linkedItemCreation: "Use createItemsForTransaction to create an item linked to a transaction."
        case .genericItemIdsUpdate: "Change transaction membership through ItemsService."
        }
    }
}

struct ItemsService: ItemsServiceProtocol {
    private static let bulkUpdateFields: Set<String> = ["spaceId", "status"]
    private static let maximumBatchOperationCount = 500

    private let makeBatch: @Sendable () -> any BatchWriting
    private let loadTransaction: @Sendable (_ accountId: String, _ transactionId: String) async throws -> Transaction?

    init(
        makeBatch: @escaping @Sendable () -> any BatchWriting = { FirestoreBatchWriter() },
        loadTransaction: @escaping @Sendable (_ accountId: String, _ transactionId: String) async throws -> Transaction? = { accountId, transactionId in
            try await FirestoreRepository<Transaction>(path: "accounts/\(accountId)/transactions").get(id: transactionId)
        }
    ) {
        self.makeBatch = makeBatch
        self.loadTransaction = loadTransaction
    }

    private static func realCategoryId(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "uncategorized" else { return nil }
        return trimmed
    }

    private static func validateCategory(projectId: String?, categoryId: String?) throws {
        if projectId != nil, realCategoryId(categoryId) == nil {
            throw ItemAssociationError.invalidBudgetCategory
        }
        if projectId == nil, categoryId != nil {
            throw ItemAssociationError.invalidBudgetCategory
        }
    }

    private func repo(accountId: String) -> FirestoreRepository<Item> {
        FirestoreRepository<Item>(path: "accounts/\(accountId)/items")
    }

    private func existingTransactionIds(accountId: String, candidateIds: Set<String>) async throws -> Set<String> {
        var existingIds = Set<String>()
        for transactionId in candidateIds {
            if try await loadTransaction(accountId, transactionId) != nil {
                existingIds.insert(transactionId)
            }
        }
        return existingIds
    }

    func getItem(accountId: String, itemId: String) async throws -> Item? {
        try await repo(accountId: accountId).get(id: itemId)
    }

    func createItem(accountId: String, item: Item) throws -> String {
        if item.transactionId != nil {
            throw ItemAssociationError.linkedItemCreation
        }
        try Self.validateCategory(projectId: item.projectId, categoryId: item.budgetCategoryId)
        let priceNormalized = ItemPricePolicy.normalizedForPersistence(item)
        let id = try repo(accountId: accountId).create(AttachmentPrimaryPolicy.normalized(priceNormalized))
        return id
    }

    func createItemsForTransaction(
        accountId: String,
        transactionId: String,
        budgetCategoryId: String?,
        items: [Item],
        onCommitError: @escaping @Sendable ([String], Error) -> Void = { _, error in
            print("🔴 createItemsForTransaction failed: \(error)")
        }
    ) throws -> [Item] {
        guard !items.isEmpty else { return [] }
        let categoryId = Self.realCategoryId(budgetCategoryId)
        for item in items {
            try Self.validateCategory(projectId: item.projectId, categoryId: categoryId)
        }

        let batch = makeBatch()
        let itemRepo = repo(accountId: accountId)
        let itemIds = items.map { _ in itemRepo.newDocumentId() }
        var createdItems: [Item] = []
        let itemsPath = "accounts/\(accountId)/items"
        let txPath = "accounts/\(accountId)/transactions/\(transactionId)"

        for (itemId, sourceItem) in zip(itemIds, items) {
            let priceNormalized = ItemPricePolicy.normalizedForPersistence(sourceItem)
            var item = AttachmentPrimaryPolicy.normalized(priceNormalized)
            item.id = itemId
            item.accountId = accountId
            item.transactionId = transactionId
            item.budgetCategoryId = categoryId
            createdItems.append(item)

            var fields = try Firestore.Encoder().encode(item)
            fields["accountId"] = accountId
            fields["transactionId"] = transactionId
            fields["projectId"] = item.projectId as Any? ?? NSNull()
            fields["budgetCategoryId"] = categoryId as Any? ?? NSNull()

            batch.setData(fields, forDocumentAt: "\(itemsPath)/\(itemId)", merge: false)
        }

        batch.updateData(
            ["itemIds": FieldValue.arrayUnion(itemIds),
             "updatedAt": FieldValue.serverTimestamp()],
            forDocumentAt: txPath
        )

        batch.commit { error in
            onCommitError(itemIds, error)
        }
        return createdItems
    }

    func updateItem(accountId: String, itemId: String, fields: [String: Any]) async throws {
        if fields.keys.contains("transactionId") {
            throw ItemAssociationError.genericTransactionUpdate
        }
        let itemRepo = repo(accountId: accountId)
        guard let existing = try await itemRepo.get(id: itemId) else {
            throw ItemAssociationError.itemNotFound(itemId)
        }
        let nextProjectId: String? = fields.keys.contains("projectId")
            ? fields["projectId"] as? String
            : existing.projectId
        let nextCategoryId: String? = fields.keys.contains("budgetCategoryId")
            ? fields["budgetCategoryId"] as? String
            : existing.budgetCategoryId
        try Self.validateCategory(projectId: nextProjectId, categoryId: nextCategoryId)
        if let transactionId = existing.transactionId {
            guard let transaction = try await loadTransaction(accountId, transactionId) else {
                throw ItemAssociationError.transactionNotFound(transactionId)
            }
            guard transaction.projectId == nextProjectId else { throw ItemAssociationError.scopeMismatch }
            if nextProjectId != nil,
               Self.realCategoryId(transaction.budgetCategoryId) != Self.realCategoryId(nextCategoryId) {
                throw ItemAssociationError.invalidBudgetCategory
            }
        }
        let normalizedFields = ItemPricePolicy.normalizedUpdateFields(
            existing: existing,
            fields: fields
        )
        let attachmentNormalizedFields = AttachmentPrimaryPolicy.normalizedFields(
            normalizedFields,
            attachmentFieldNames: ["images"]
        )
        try await itemRepo.update(id: itemId, fields: attachmentNormalizedFields)
    }

    /// Updates status or space metadata for the supplied live item snapshots.
    /// Association fields use dedicated operations because they also mutate
    /// transaction membership and category invariants.
    func updateItems(accountId: String, items: [Item], fields: [String: Any]) async throws {
        guard !items.isEmpty, !fields.isEmpty else { return }

        if let unsupportedField = fields.keys
            .filter({ !Self.bulkUpdateFields.contains($0) })
            .sorted()
            .first {
            throw ItemAssociationError.unsupportedBulkUpdateField(unsupportedField)
        }

        var seenItemIds = Set<String>()
        var updates: [(itemId: String, fields: [String: Any])] = []
        updates.reserveCapacity(items.count)

        for item in items {
            guard let itemId = item.id else { throw ItemAssociationError.itemMissingId }
            guard seenItemIds.insert(itemId).inserted else { continue }
            updates.append((itemId, fields))
        }

        let itemsPath = "accounts/\(accountId)/items"
        for startIndex in stride(
            from: 0,
            to: updates.count,
            by: Self.maximumBatchOperationCount
        ) {
            let batch = makeBatch()
            let endIndex = min(startIndex + Self.maximumBatchOperationCount, updates.count)
            for update in updates[startIndex..<endIndex] {
                batch.updateData(
                    update.fields,
                    forDocumentAt: "\(itemsPath)/\(update.itemId)"
                )
            }
            try await batch.commit()
        }
    }

    /// Atomically moves items between canonical transaction membership arrays.
    /// A linked item always inherits the destination transaction's category.
    func setTransaction(
        accountId: String,
        items: [Item],
        transactionId: String,
        userId: String? = nil
    ) async throws {
        guard !items.isEmpty else { return }
        guard let destination = try await loadTransaction(accountId, transactionId) else {
            throw ItemAssociationError.transactionNotFound(transactionId)
        }
        try Self.validateCategory(
            projectId: destination.projectId,
            categoryId: destination.budgetCategoryId
        )
        let destinationCategoryId = Self.realCategoryId(destination.budgetCategoryId)

        // Deleted transactions can leave stale item back-references in legacy
        // data. Only detach from source transactions that still exist so a
        // reassignment does not fail or recreate an empty transaction document.
        let sourceTransactionIds = Set(items.compactMap { item -> String? in
            guard let sourceId = item.transactionId, sourceId != transactionId else { return nil }
            return sourceId
        })
        let existingSourceTransactionIds = try await existingTransactionIds(
            accountId: accountId,
            candidateIds: sourceTransactionIds
        )

        let batch = makeBatch()
        let itemsPath = "accounts/\(accountId)/items"
        let transactionsPath = "accounts/\(accountId)/transactions"
        let edgesPath = "accounts/\(accountId)/lineageEdges"
        var destinationItemIds: [String] = []

        for item in items {
            guard let itemId = item.id else { throw ItemAssociationError.itemMissingId }
            guard item.projectId == destination.projectId else { throw ItemAssociationError.scopeMismatch }
            destinationItemIds.append(itemId)

            var itemFields: [String: Any] = [
                "transactionId": transactionId,
                "budgetCategoryId": destinationCategoryId as Any? ?? NSNull(),
                "updatedAt": FieldValue.serverTimestamp(),
            ]
            if destination.isReturnTransaction {
                itemFields["status"] = ItemStatus.returned.rawValue
            }
            batch.updateData(itemFields, forDocumentAt: "\(itemsPath)/\(itemId)")

            if let oldTransactionId = item.transactionId,
               oldTransactionId != transactionId,
               existingSourceTransactionIds.contains(oldTransactionId) {
                batch.updateData(
                    ["itemIds": FieldValue.arrayRemove([itemId]), "updatedAt": FieldValue.serverTimestamp()],
                    forDocumentAt: "\(transactionsPath)/\(oldTransactionId)"
                )
            }

            if item.transactionId != transactionId {
                var edge: [String: Any] = [
                    "accountId": accountId,
                    "itemId": itemId,
                    "toTransactionId": transactionId,
                    "fromProjectId": item.projectId as Any? ?? NSNull(),
                    "toProjectId": destination.projectId as Any? ?? NSNull(),
                    "movementKind": "correction",
                    "source": "app",
                    "note": "Set transaction association",
                    "createdAt": FieldValue.serverTimestamp(),
                ]
                if let oldTransactionId = item.transactionId { edge["fromTransactionId"] = oldTransactionId }
                if let userId { edge["createdBy"] = userId }
                batch.setDataAutoId(edge, inCollection: edgesPath)
            }
        }

        batch.updateData(
            ["itemIds": FieldValue.arrayUnion(destinationItemIds), "updatedAt": FieldValue.serverTimestamp()],
            forDocumentAt: "\(transactionsPath)/\(transactionId)"
        )
        try await batch.commit()
    }

    /// Clears transaction ownership while preserving a project item's real category.
    func clearTransaction(accountId: String, items: [Item], userId: String? = nil) async throws {
        let linkedItems = items.filter { $0.transactionId != nil }
        guard !linkedItems.isEmpty else { return }
        for item in linkedItems {
            try Self.validateCategory(projectId: item.projectId, categoryId: item.budgetCategoryId)
            guard item.id != nil else { throw ItemAssociationError.itemMissingId }
        }

        let existingSourceTransactionIds = try await existingTransactionIds(
            accountId: accountId,
            candidateIds: Set(linkedItems.compactMap(\.transactionId))
        )

        let batch = makeBatch()
        let itemsPath = "accounts/\(accountId)/items"
        let transactionsPath = "accounts/\(accountId)/transactions"
        let edgesPath = "accounts/\(accountId)/lineageEdges"

        for item in linkedItems {
            guard let itemId = item.id, let oldTransactionId = item.transactionId else { continue }
            batch.updateData(
                ["transactionId": NSNull(), "updatedAt": FieldValue.serverTimestamp()],
                forDocumentAt: "\(itemsPath)/\(itemId)"
            )
            if existingSourceTransactionIds.contains(oldTransactionId) {
                batch.updateData(
                    ["itemIds": FieldValue.arrayRemove([itemId]), "updatedAt": FieldValue.serverTimestamp()],
                    forDocumentAt: "\(transactionsPath)/\(oldTransactionId)"
                )
            }
            var edge: [String: Any] = [
                "accountId": accountId,
                "itemId": itemId,
                "fromTransactionId": oldTransactionId,
                "fromProjectId": item.projectId as Any? ?? NSNull(),
                "toProjectId": item.projectId as Any? ?? NSNull(),
                "movementKind": "correction",
                "source": "app",
                "note": "Cleared transaction association",
                "createdAt": FieldValue.serverTimestamp(),
            ]
            if let userId { edge["createdBy"] = userId }
            batch.setDataAutoId(edge, inCollection: edgesPath)
        }
        try await batch.commit()
    }

    func deleteItem(accountId: String, item: Item) async throws {
        try await deleteItems(accountId: accountId, items: [item])
    }

    func deleteItems(accountId: String, items: [Item]) async throws {
        guard !items.isEmpty else { return }

        let existingSourceTransactionIds = try await existingTransactionIds(
            accountId: accountId,
            candidateIds: Set(items.compactMap(\.transactionId))
        )

        let batch = makeBatch()
        let itemsPath = "accounts/\(accountId)/items"
        let txPath = "accounts/\(accountId)/transactions"

        for item in items {
            guard let itemId = item.id else { continue }

            batch.deleteDocument(atPath: "\(itemsPath)/\(itemId)")

            if let transactionId = item.transactionId,
               existingSourceTransactionIds.contains(transactionId) {
                batch.updateData(
                    ["itemIds": FieldValue.arrayRemove([itemId]),
                     "updatedAt": FieldValue.serverTimestamp()],
                    forDocumentAt: "\(txPath)/\(transactionId)"
                )
            }
        }

        try await batch.commit()
    }

    func subscribeToItems(accountId: String, scope: ListScope, onChange: @escaping ([Item]) -> Void) -> ListenerRegistration {
        let r = repo(accountId: accountId)
        switch scope {
        case .project(let projectId):
            return r.subscribe(where: "projectId", isEqualTo: projectId, onChange: onChange)
        case .inventory:
            return r.subscribe(where: "projectId", isEqualTo: NSNull(), onChange: onChange)
        case .all:
            return r.subscribe(onChange: onChange)
        }
    }

    func subscribeToItem(accountId: String, itemId: String, onChange: @escaping (Item?) -> Void) -> ListenerRegistration {
        repo(accountId: accountId).subscribe(id: itemId, onChange: onChange)
    }
}
