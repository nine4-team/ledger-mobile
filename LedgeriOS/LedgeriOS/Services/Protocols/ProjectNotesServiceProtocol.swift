import FirebaseFirestore

protocol ProjectNotesServiceProtocol: Sendable {
    func subscribeToProjectNotes(accountId: String, projectId: String, onChange: @escaping ([ProjectNote]) -> Void) -> ListenerRegistration
    func addProjectNote(accountId: String, projectId: String, note: ProjectNote) async throws
    func updateProjectNote(accountId: String, projectId: String, noteId: String, fields: [String: Any]) async throws
    func deleteProjectNote(accountId: String, projectId: String, noteId: String) async throws
}
