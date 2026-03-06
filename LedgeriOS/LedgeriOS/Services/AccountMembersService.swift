import FirebaseFirestore

struct AccountMembersService: AccountMembersServiceProtocol {
    let syncTracker: SyncTracking

    func subscribeToMember(accountId: String, userId: String, onChange: @escaping (AccountMember?) -> Void) -> ListenerRegistration {
        let repo = FirestoreRepository<AccountMember>(path: "accounts/\(accountId)/users")
        return repo.subscribe(id: userId, onChange: onChange)
    }

    func listMembershipsForUser(userId: String) async throws -> [AccountMember] {
        let db = Firestore.firestore()
        let query = db.collectionGroup("users").whereField("uid", isEqualTo: userId)

        // H9: Try cache first for immediate cache-first reads (offline-first principle).
        // Returns cached data instantly if available; falls back to server on cache miss.
        if let cached = try? await query.getDocuments(source: .cache), !cached.documents.isEmpty {
            return parseMembers(cached.documents)
        }

        let snapshot = try await query.getDocuments()
        return parseMembers(snapshot.documents)
    }

    private func parseMembers(_ documents: [QueryDocumentSnapshot]) -> [AccountMember] {
        documents.compactMap { doc in
            do {
                var member = try doc.data(as: AccountMember.self)
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
