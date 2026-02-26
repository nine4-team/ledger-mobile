import FirebaseFirestore

struct AccountMembersService: AccountMembersServiceProtocol {
    let syncTracker: SyncTracking

    func subscribeToMember(accountId: String, userId: String, onChange: @escaping (AccountMember?) -> Void) -> ListenerRegistration {
        let repo = FirestoreRepository<AccountMember>(path: "accounts/\(accountId)/users")
        return repo.subscribe(id: userId, onChange: onChange)
    }
}
