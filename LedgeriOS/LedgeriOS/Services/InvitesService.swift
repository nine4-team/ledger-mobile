import FirebaseFirestore

struct InvitesService: InvitesServiceProtocol {
    let syncTracker: SyncTracking

    private func repo(accountId: String) -> FirestoreRepository<Invite> {
        FirestoreRepository<Invite>(path: "accounts/\(accountId)/invites")
    }

    func subscribe(accountId: String, onChange: @escaping ([Invite]) -> Void) -> ListenerRegistration {
        let collectionRef = Firestore.firestore().collection("accounts/\(accountId)/invites")
        return collectionRef
            .whereField("revokedAt", isEqualTo: NSNull())
            .addSnapshotListener { snapshot, error in
                guard let docs = snapshot?.documents else { return }
                let invites = docs.compactMap { try? $0.data(as: Invite.self) }
                onChange(invites)
            }
    }

    func create(accountId: String, email: String, role: String, createdByUid: String) throws -> String {
        var invite = Invite()
        invite.accountId = accountId
        invite.email = email
        invite.role = role
        invite.token = UUID().uuidString
        invite.createdByUid = createdByUid
        let id = try repo(accountId: accountId).create(invite)
        syncTracker.trackPendingWrite()
        return id
    }

    func revoke(accountId: String, inviteId: String) async throws {
        try await repo(accountId: accountId).update(id: inviteId, fields: [
            "revokedAt": FieldValue.serverTimestamp()
        ])
        syncTracker.trackPendingWrite()
    }
}
