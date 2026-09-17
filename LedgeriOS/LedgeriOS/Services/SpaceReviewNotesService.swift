import FirebaseFirestore

struct SpaceReviewNotesService {
    private func repo(accountId: String, spaceId: String) -> NotesService {
        NotesService(accountId: accountId, scope: .space(spaceId))
    }

    func subscribe(
        accountId: String,
        spaceId: String,
        onChange: @escaping ([SpaceReviewNote]) -> Void
    ) -> ListenerRegistration {
        repo(accountId: accountId, spaceId: spaceId).subscribe(onChange: onChange)
    }

    func add(accountId: String, spaceId: String, note: SpaceReviewNote) throws {
        try repo(accountId: accountId, spaceId: spaceId).add(note)
    }

    func update(
        accountId: String,
        spaceId: String,
        noteId: String,
        text: String,
        visualReference: SpaceNoteVisualReference?
    ) async throws {
        try SpaceReviewNoteFields.validate(visualReference, spaceId: spaceId)
        try await repo(accountId: accountId, spaceId: spaceId).update(
            id: noteId,
            fields: SpaceReviewNoteFields.update(text: text, visualReference: visualReference)
        )
    }

    func delete(accountId: String, spaceId: String, noteId: String) async throws {
        try await repo(accountId: accountId, spaceId: spaceId).delete(id: noteId)
    }
}
