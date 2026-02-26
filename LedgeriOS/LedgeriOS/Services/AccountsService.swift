import FirebaseFirestore

struct AccountsService: AccountsServiceProtocol {
    let syncTracker: SyncTracking

    func getAccount(accountId: String) async throws -> Account? {
        let repo = FirestoreRepository<Account>(path: "accounts")
        return try await repo.get(id: accountId)
    }

    func subscribeToAccount(accountId: String, onChange: @escaping (Account?) -> Void) -> ListenerRegistration {
        let repo = FirestoreRepository<Account>(path: "accounts")
        return repo.subscribe(id: accountId, onChange: onChange)
    }
}
