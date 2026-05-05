import FirebaseFirestore

struct TransactionsService: TransactionsServiceProtocol {
    private func repo(accountId: String) -> FirestoreRepository<Transaction> {
        FirestoreRepository<Transaction>(path: "accounts/\(accountId)/transactions")
    }

    func getTransaction(accountId: String, transactionId: String) async throws -> Transaction? {
        try await repo(accountId: accountId).get(id: transactionId)
    }

    func createTransaction(accountId: String, transaction: Transaction) throws -> String {
        let id = try repo(accountId: accountId).create(transaction)
        writeNullProjectIdIfNeeded(accountId: accountId, transactionId: id, transaction: transaction)
        return id
    }

    /// Pre-allocate a transaction ID without writing. Lets callers (e.g. the
    /// New Transaction sheet) reference the future doc in Storage paths before
    /// the document itself is created.
    func newTransactionId(accountId: String) -> String {
        repo(accountId: accountId).newDocumentId()
    }

    func createTransaction(accountId: String, id: String, transaction: Transaction) throws {
        try repo(accountId: accountId).create(id: id, transaction)
        writeNullProjectIdIfNeeded(accountId: accountId, transactionId: id, transaction: transaction)
    }

    private func writeNullProjectIdIfNeeded(accountId: String, transactionId: String, transaction: Transaction) {
        // Firebase Codable encoder omits nil optionals instead of writing null.
        // Inventory transactions need projectId: null so the inventory scope query matches.
        guard transaction.projectId == nil else { return }
        Firestore.firestore()
            .document("accounts/\(accountId)/transactions/\(transactionId)")
            .updateData(["projectId": NSNull()])
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
