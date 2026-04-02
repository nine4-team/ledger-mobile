import FirebaseFirestore

struct AccountsService: AccountsServiceProtocol {
    func getAccount(accountId: String) async throws -> Account? {
        let repo = FirestoreRepository<Account>(path: "accounts")
        return try await repo.get(id: accountId)
    }

    func subscribeToAccount(accountId: String, onChange: @escaping (Account?) -> Void) -> ListenerRegistration {
        let repo = FirestoreRepository<Account>(path: "accounts")
        return repo.subscribe(id: accountId, onChange: onChange)
    }

    func updateAccount(accountId: String, fields: [String: Any]) async throws {
        let repo = FirestoreRepository<Account>(path: "accounts")
        try await repo.update(id: accountId, fields: fields)
    }
}
