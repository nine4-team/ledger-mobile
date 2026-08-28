import FirebaseFirestore

struct TransactionDeletionNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

enum TransactionDeletionError: LocalizedError {
    case linkedItems(count: Int)

    var errorDescription: String? {
        switch self {
        case .linkedItems(let count):
            let noun = count == 1 ? "item" : "items"
            return "This transaction still has \(count) \(noun) attached. Move or remove the transaction from the attached \(noun), then try again."
        }
    }
}

struct TransactionsService: TransactionsServiceProtocol {
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

    private static func isRealCategory(_ value: String?) -> Bool {
        guard let value else { return false }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.lowercased() != "uncategorized"
    }

    private static func validateCategory(projectId: String?, categoryId: String?) throws {
        if projectId != nil, !isRealCategory(categoryId) {
            throw ItemAssociationError.invalidBudgetCategory
        }
        if projectId == nil, categoryId != nil {
            throw ItemAssociationError.invalidBudgetCategory
        }
    }

    static func deletionNotice(for transaction: Transaction) -> TransactionDeletionNotice? {
        let count = transaction.itemIds?.count ?? 0
        guard count > 0 else { return nil }
        return TransactionDeletionNotice(
            title: "Can’t Delete This Transaction",
            message: TransactionDeletionError.linkedItems(count: count).localizedDescription
        )
    }

    static func deletionNotice(for transactions: [Transaction]) -> TransactionDeletionNotice? {
        let blockedCount = transactions.filter { !($0.itemIds ?? []).isEmpty }.count
        guard blockedCount > 0 else { return nil }
        let noun = blockedCount == 1 ? "transaction still has" : "transactions still have"
        return TransactionDeletionNotice(
            title: "Some Transactions Can’t Be Deleted",
            message: "\(blockedCount) selected \(noun) items attached. Move those items or remove their transaction, then try again."
        )
    }

    static func failureNotice(for error: Error) -> TransactionDeletionNotice {
        if let deletionError = error as? TransactionDeletionError {
            return TransactionDeletionNotice(
                title: "Can’t Delete This Transaction",
                message: deletionError.localizedDescription
            )
        }
        return TransactionDeletionNotice(
            title: "Couldn’t Delete Transaction",
            message: "Something went wrong while deleting this transaction. Please try again."
        )
    }

    /// Payload for correcting an ordinary transaction into business inventory.
    /// `updateTransaction` atomically clears canonical item ownership.
    static func moveToInventoryCorrectionFields() -> [String: Any] {
        [
            "projectId": NSNull(),
            "budgetCategoryId": NSNull(),
        ]
    }

    private func repo(accountId: String) -> FirestoreRepository<Transaction> {
        FirestoreRepository<Transaction>(path: "accounts/\(accountId)/transactions")
    }

    func getTransaction(accountId: String, transactionId: String) async throws -> Transaction? {
        try await repo(accountId: accountId).get(id: transactionId)
    }

    func createTransaction(accountId: String, transaction: Transaction) throws -> String {
        try Self.validateCategory(projectId: transaction.projectId, categoryId: transaction.budgetCategoryId)
        let normalized = normalizedAttachments(in: transaction)
        return try repo(accountId: accountId).create(normalized, additionalFields: extraFields(for: normalized))
    }

    /// Pre-allocate a transaction ID without writing. Lets callers (e.g. the
    /// New Transaction sheet) reference the future doc in Storage paths before
    /// the document itself is created.
    func newTransactionId(accountId: String) -> String {
        repo(accountId: accountId).newDocumentId()
    }

    func createTransaction(accountId: String, id: String, transaction: Transaction) throws {
        try Self.validateCategory(projectId: transaction.projectId, categoryId: transaction.budgetCategoryId)
        let normalized = normalizedAttachments(in: transaction)
        try repo(accountId: accountId).create(id: id, normalized, additionalFields: extraFields(for: normalized))
    }

    /// Inventory transactions need an explicit `projectId: null` so the inventory
    /// scope query (`projectId == NSNull()`) matches. The Codable encoder would
    /// otherwise omit the field. `createdAt`/`updatedAt` are server-stamped here
    /// — `transactionDate` is a separate user-picked purchase date and must not
    /// be confused with the creation timestamp. Returning these via
    /// `additionalFields` lets the repository write them in the same `setData`
    /// call as the rest of the document — splitting it across create + updateData
    /// races the snapshot listener and can leave the doc invisible to scope queries.
    private func extraFields(for transaction: Transaction) -> [String: Any] {
        var fields: [String: Any] = [
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if transaction.projectId == nil {
            fields["projectId"] = NSNull()
        }
        return fields
    }

    func updateTransaction(accountId: String, transactionId: String, fields: [String: Any]) async throws {
        if fields.keys.contains("itemIds") {
            throw ItemAssociationError.genericItemIdsUpdate
        }
        let normalizedFields = AttachmentPrimaryPolicy.normalizedFields(
            fields,
            attachmentFieldNames: ["receiptImages", "otherImages", "transactionImages"]
        )
        if normalizedFields["projectId"] is NSNull {
            guard let existing = try await loadTransaction(accountId, transactionId) else {
                throw ItemAssociationError.transactionNotFound(transactionId)
            }
            let batch = makeBatch()
            var transactionFields = normalizedFields
            transactionFields["budgetCategoryId"] = NSNull()
            transactionFields["itemIds"] = [String]()
            batch.updateData(transactionFields, forDocumentAt: "accounts/\(accountId)/transactions/\(transactionId)")
            for itemId in existing.itemIds ?? [] {
                batch.updateData(
                    ["transactionId": NSNull(), "updatedAt": FieldValue.serverTimestamp()],
                    forDocumentAt: "accounts/\(accountId)/items/\(itemId)"
                )
                batch.setDataAutoId(
                    [
                        "accountId": accountId,
                        "itemId": itemId,
                        "fromTransactionId": transactionId,
                        "movementKind": "correction",
                        "source": "app",
                        "note": "Cleared transaction association during inventory-scope correction",
                        "createdAt": FieldValue.serverTimestamp(),
                    ],
                    inCollection: "accounts/\(accountId)/lineageEdges"
                )
            }
            try await batch.commit()
            return
        }
        if normalizedFields.keys.contains("projectId") || normalizedFields.keys.contains("budgetCategoryId") {
            guard let existing = try await loadTransaction(accountId, transactionId) else {
                throw ItemAssociationError.transactionNotFound(transactionId)
            }
            let nextProjectId = normalizedFields["projectId"] as? String ?? existing.projectId
            let nextCategoryId = normalizedFields["budgetCategoryId"] as? String ?? existing.budgetCategoryId
            try Self.validateCategory(projectId: nextProjectId, categoryId: nextCategoryId)
            if nextProjectId != existing.projectId || nextCategoryId != existing.budgetCategoryId {
                let batch = makeBatch()
                batch.updateData(normalizedFields, forDocumentAt: "accounts/\(accountId)/transactions/\(transactionId)")
                for itemId in existing.itemIds ?? [] {
                    var itemFields: [String: Any] = [
                        "projectId": nextProjectId as Any? ?? NSNull(),
                        "budgetCategoryId": nextCategoryId as Any? ?? NSNull(),
                        "updatedAt": FieldValue.serverTimestamp(),
                    ]
                    if nextProjectId != existing.projectId { itemFields["spaceId"] = NSNull() }
                    batch.updateData(
                        itemFields,
                        forDocumentAt: "accounts/\(accountId)/items/\(itemId)"
                    )
                    if nextProjectId != existing.projectId {
                        batch.setDataAutoId(
                            [
                                "accountId": accountId,
                                "itemId": itemId,
                                "fromTransactionId": transactionId,
                                "toTransactionId": transactionId,
                                "fromProjectId": existing.projectId as Any? ?? NSNull(),
                                "toProjectId": nextProjectId as Any? ?? NSNull(),
                                "movementKind": "correction",
                                "source": "app",
                                "note": "Moved with transaction project correction",
                                "createdAt": FieldValue.serverTimestamp(),
                            ],
                            inCollection: "accounts/\(accountId)/lineageEdges"
                        )
                    }
                }
                try await batch.commit()
                return
            }
        }
        try await repo(accountId: accountId).update(id: transactionId, fields: normalizedFields)
    }

    private func normalizedAttachments(in transaction: Transaction) -> Transaction {
        var normalized = transaction
        if let attachments = transaction.receiptImages {
            normalized.receiptImages = AttachmentPrimaryPolicy.normalized(attachments)
        }
        if let attachments = transaction.otherImages {
            normalized.otherImages = AttachmentPrimaryPolicy.normalized(attachments)
        }
        if let attachments = transaction.transactionImages {
            normalized.transactionImages = AttachmentPrimaryPolicy.normalized(attachments)
        }
        return normalized
    }

    func deleteTransaction(accountId: String, transactionId: String) async throws {
        guard let transaction = try await loadTransaction(accountId, transactionId) else {
            throw ItemAssociationError.transactionNotFound(transactionId)
        }
        if Self.deletionNotice(for: transaction) != nil {
            throw TransactionDeletionError.linkedItems(count: transaction.itemIds?.count ?? 0)
        }
        do {
            try await repo(accountId: accountId).delete(id: transactionId)
        } catch {
            // The Firestore rule closes the race between this read and delete.
            // Re-read once so a newly attached item still gets the useful
            // explanation instead of a generic permission error.
            if let latest = try? await loadTransaction(accountId, transactionId),
               Self.deletionNotice(for: latest) != nil {
                throw TransactionDeletionError.linkedItems(count: latest.itemIds?.count ?? 0)
            }
            throw error
        }
    }

    func subscribeToTransactions(accountId: String, scope: ListScope, onChange: @escaping ([Transaction]) -> Void) -> ListenerRegistration {
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

    func subscribeToTransaction(accountId: String, transactionId: String, onChange: @escaping (Transaction?) -> Void) -> ListenerRegistration {
        repo(accountId: accountId).subscribe(id: transactionId, onChange: onChange)
    }
}
