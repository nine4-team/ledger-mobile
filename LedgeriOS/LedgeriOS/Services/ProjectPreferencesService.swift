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
}
