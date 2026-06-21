import FirebaseFirestore

struct ProjectNotesService: ProjectNotesServiceProtocol {
    private func repo(accountId: String, projectId: String) -> FirestoreRepository<ProjectNote> {
        FirestoreRepository<ProjectNote>(
            path: "accounts/\(accountId)/projects/\(projectId)/notes"
        )
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

    func updateProjectNote(
        accountId: String,
        projectId: String,
        noteId: String,
        fields: [String: Any]
    ) async throws {
        try await repo(accountId: accountId, projectId: projectId).update(id: noteId, fields: fields)
    }

    func deleteProjectNote(
        accountId: String,
        projectId: String,
        noteId: String
    ) async throws {
        try await repo(accountId: accountId, projectId: projectId).delete(id: noteId)
    }
}
