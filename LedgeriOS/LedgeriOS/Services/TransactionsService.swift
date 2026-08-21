import FirebaseFirestore

struct TransactionsService: TransactionsServiceProtocol {
    private func repo(accountId: String) -> FirestoreRepository<Transaction> {
        FirestoreRepository<Transaction>(path: "accounts/\(accountId)/transactions")
    }

    func getTransaction(accountId: String, transactionId: String) async throws -> Transaction? {
        try await repo(accountId: accountId).get(id: transactionId)
    }

    func createTransaction(accountId: String, transaction: Transaction) throws -> String {
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
        let normalizedFields = AttachmentPrimaryPolicy.normalizedFields(
            fields,
            attachmentFieldNames: ["receiptImages", "otherImages", "transactionImages"]
        )
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
        try await repo(accountId: accountId).delete(id: transactionId)
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
