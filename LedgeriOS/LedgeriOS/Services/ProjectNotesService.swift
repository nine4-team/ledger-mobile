import FirebaseFirestore

struct ProjectNotesService: ProjectNotesServiceProtocol {
    private func repo(accountId: String, projectId: String) -> NotesService {
        NotesService(accountId: accountId, scope: .project(projectId))
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
        try repo(accountId: accountId, projectId: projectId).add(note)
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

/// The single persistence implementation. Adapters retain existing call-site APIs.
struct NotesService {
    let accountId: String
    let scope: NoteScope

    private var repository: FirestoreRepository<LedgerNote> {
        FirestoreRepository(path: scope.collectionPath(accountId: accountId))
    }

    func subscribe(onChange: @escaping ([LedgerNote]) -> Void) -> ListenerRegistration {
        repository.subscribe(onChange: onChange)
    }

    func add(_ note: LedgerNote) throws {
        if let spaceId = scope.spaceId {
            try NoteFields.validate(note.visualReference, spaceId: spaceId)
        }
        _ = try repository.create(note)
    }

    func update(id: String, fields: [String: Any]) async throws {
        try await repository.update(id: id, fields: fields)
    }

    func delete(id: String) async throws {
        try await repository.delete(id: id)
    }
}
