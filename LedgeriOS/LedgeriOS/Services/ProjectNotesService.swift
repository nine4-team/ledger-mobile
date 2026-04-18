import FirebaseFirestore

struct ProjectNotesService: ProjectNotesServiceProtocol {
    private func repo(accountId: String, projectId: String) -> FirestoreRepository<ProjectNote> {
        FirestoreRepository<ProjectNote>(
            path: "accounts/\(accountId)/projects/\(projectId)/notes"
        )
    }

    private func collectionRef(accountId: String, projectId: String) -> CollectionReference {
        Firestore.firestore()
            .collection("accounts/\(accountId)/projects/\(projectId)/notes")
    }

    func subscribeToProjectNotes(
        accountId: String,
        projectId: String,
        onChange: @escaping ([ProjectNote]) -> Void
    ) -> ListenerRegistration {
        repo(accountId: accountId, projectId: projectId).subscribe(onChange: onChange)
    }

    func addProjectNote(
        accountId: String,
        projectId: String,
        note: ProjectNote
    ) async throws {
        _ = try repo(accountId: accountId, projectId: projectId).create(note)
    }

    func deleteProjectNote(
        accountId: String,
        projectId: String,
        noteId: String
    ) async throws {
        let docRef = collectionRef(accountId: accountId, projectId: projectId).document(noteId)
        try await docRef.delete()
    }
}
