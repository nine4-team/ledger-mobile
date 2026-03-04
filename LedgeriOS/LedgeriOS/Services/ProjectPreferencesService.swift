import FirebaseFirestore

struct ProjectPreferencesService: Sendable {

    /// Subscribes to a single project preferences document for the current user.
    /// Path: accounts/{accountId}/users/{userId}/projectPreferences/{projectId}
    func subscribeToProjectPreferences(
        accountId: String,
        userId: String,
        projectId: String,
        onChange: @escaping (ProjectPreferences?) -> Void
    ) -> ListenerRegistration {
        let db = Firestore.firestore()
        let docRef = db.collection("accounts/\(accountId)/users/\(userId)/projectPreferences")
            .document(projectId)

        return docRef.addSnapshotListener { snapshot, error in
            guard let snapshot, snapshot.exists else {
                onChange(nil)
                return
            }
            let prefs = try? snapshot.data(as: ProjectPreferences.self)
            onChange(prefs)
        }
    }

    /// Subscribes to all project preferences for the current user.
    /// Returns a lookup of projectId → ProjectPreferences.
    func subscribeToAllProjectPreferences(
        accountId: String,
        userId: String,
        onChange: @escaping ([String: ProjectPreferences]) -> Void
    ) -> ListenerRegistration {
        let db = Firestore.firestore()
        let collectionRef = db.collection("accounts/\(accountId)/users/\(userId)/projectPreferences")

        return collectionRef.addSnapshotListener { snapshot, _ in
            guard let docs = snapshot?.documents else {
                onChange([:])
                return
            }
            var lookup: [String: ProjectPreferences] = [:]
            for doc in docs {
                if let prefs = try? doc.data(as: ProjectPreferences.self) {
                    lookup[doc.documentID] = prefs
                }
            }
            onChange(lookup)
        }
    }

    /// Updates the pinned budget category IDs for a project.
    /// Path: accounts/{accountId}/users/{userId}/projectPreferences/{projectId}
    func updatePinnedCategories(
        accountId: String,
        userId: String,
        projectId: String,
        pinnedIds: [String]
    ) async throws {
        let db = Firestore.firestore()
        let docRef = db.collection("accounts/\(accountId)/users/\(userId)/projectPreferences")
            .document(projectId)
        try await docRef.setData(["pinnedBudgetCategoryIds": pinnedIds], merge: true)
    }
}
