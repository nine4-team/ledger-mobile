import FirebaseFirestore

struct SpaceReviewNotesService {
    private func repo(accountId: String, spaceId: String) -> FirestoreRepository<SpaceReviewNote> {
        FirestoreRepository<SpaceReviewNote>(
            path: "accounts/\(accountId)/spaces/\(spaceId)/reviewNotes"
        )
    }

    func subscribe(
        accountId: String,
        spaceId: String,
        onChange: @escaping ([SpaceReviewNote]) -> Void
    ) -> ListenerRegistration {
        repo(accountId: accountId, spaceId: spaceId).subscribe(onChange: onChange)
    }

    func add(accountId: String, spaceId: String, note: SpaceReviewNote) throws {
        try SpaceReviewNoteFields.validate(note.visualReference, spaceId: spaceId)
        _ = try repo(accountId: accountId, spaceId: spaceId).create(note)
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
