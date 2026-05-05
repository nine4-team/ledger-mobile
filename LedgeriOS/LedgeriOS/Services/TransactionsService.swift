import FirebaseFirestore

struct TransactionsService: TransactionsServiceProtocol {
    private func repo(accountId: String) -> FirestoreRepository<Transaction> {
        FirestoreRepository<Transaction>(path: "accounts/\(accountId)/transactions")
    }

    func getTransaction(accountId: String, transactionId: String) async throws -> Transaction? {
        try await repo(accountId: accountId).get(id: transactionId)
    }

    func createTransaction(accountId: String, transaction: Transaction) throws -> String {
        try repo(accountId: accountId).create(transaction, additionalFields: extraFields(for: transaction))
    }

    /// Pre-allocate a transaction ID without writing. Lets callers (e.g. the
    /// New Transaction sheet) reference the future doc in Storage paths before
    /// the document itself is created.
    func newTransactionId(accountId: String) -> String {
        repo(accountId: accountId).newDocumentId()
    }

    func createTransaction(accountId: String, id: String, transaction: Transaction) throws {
        try repo(accountId: accountId).create(id: id, transaction, additionalFields: extraFields(for: transaction))
    }

    /// Inventory transactions need an explicit `projectId: null` so the inventory
    /// scope query (`projectId == NSNull()`) matches. The Codable encoder would
    /// otherwise omit the field. Returning these via `additionalFields` lets the
    /// repository write them in the same `setData` call as the rest of the
    /// document — splitting it across create + updateData races the snapshot
    /// listener and can leave the doc invisible to scope queries.
    private func extraFields(for transaction: Transaction) -> [String: Any] {
        transaction.projectId == nil ? ["projectId": NSNull()] : [:]
    }

    func updateTransaction(accountId: String, transactionId: String, fields: [String: Any]) async throws {
        try await repo(accountId: accountId).update(id: transactionId, fields: fields)
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
