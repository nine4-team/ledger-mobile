import FirebaseFirestore

struct AccountMembersService: AccountMembersServiceProtocol {
    let syncTracker: SyncTracking

    func subscribeToMember(accountId: String, userId: String, onChange: @escaping (AccountMember?) -> Void) -> ListenerRegistration {
        let repo = FirestoreRepository<AccountMember>(path: "accounts/\(accountId)/users")
        return repo.subscribe(id: userId, onChange: onChange)
    }

    func listMembershipsForUser(userId: String) async throws -> [AccountMember] {
        let db = Firestore.firestore()
        print("🟡 Firestore settings — host: \(db.settings.host), ssl: \(db.settings.isSSLEnabled)")
        let snapshot = try await db.collectionGroup("users")
            .whereField("uid", isEqualTo: userId)
            .getDocuments()
        print("🟡 collectionGroup query returned \(snapshot.documents.count) docs")
        for doc in snapshot.documents {
            print("🟡   doc path: \(doc.reference.path), data: \(doc.data())")
        }

        return snapshot.documents.compactMap { doc in
            do {
                var member = try doc.data(as: AccountMember.self)
                // Populate accountId from parent path if nil on the doc
                if member.accountId == nil {
                    member.accountId = doc.reference.parent.parent?.documentID
                }
                return member
            } catch {
                print("🔴 AccountMember decode failed for \(doc.reference.path): \(error)")
                return nil
            }
        }
    }
}
