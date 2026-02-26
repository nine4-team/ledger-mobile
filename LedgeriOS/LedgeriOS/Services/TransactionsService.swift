import FirebaseFirestore

struct TransactionsService: TransactionsServiceProtocol {
    let syncTracker: SyncTracking

    private func repo(accountId: String) -> FirestoreRepository<Transaction> {
        FirestoreRepository<Transaction>(path: "accounts/\(accountId)/transactions")
    }

    func getTransaction(accountId: String, transactionId: String) async throws -> Transaction? {
        try await repo(accountId: accountId).get(id: transactionId)
    }

    func createTransaction(accountId: String, transaction: Transaction) throws -> String {
        let id = try repo(accountId: accountId).create(transaction)
        syncTracker.trackPendingWrite()
        return id
    }

    func updateTransaction(accountId: String, transactionId: String, fields: [String: Any]) async throws {
        try await repo(accountId: accountId).update(id: transactionId, fields: fields)
        syncTracker.trackPendingWrite()
    }

    func deleteTransaction(accountId: String, transactionId: String) async throws {
        try await repo(accountId: accountId).delete(id: transactionId)
        syncTracker.trackPendingWrite()
    }

    func subscribeToTransactions(accountId: String, scope: ListScope, onChange: @escaping ([Transaction]) -> Void) -> ListenerRegistration {
        let r = repo(accountId: accountId)
        switch scope {
        case .project(let projectId):
            return r.subscribe(where: "projectId", isEqualTo: projectId, onChange: onChange)
        case .inventory:
            return r.subscribe(where: "isCanonicalInventory", isEqualTo: true, onChange: onChange)
        case .all:
            return r.subscribe(onChange: onChange)
        }
    }

    func subscribeToTransaction(accountId: String, transactionId: String, onChange: @escaping (Transaction?) -> Void) -> ListenerRegistration {
        repo(accountId: accountId).subscribe(id: transactionId, onChange: onChange)
    }
}
