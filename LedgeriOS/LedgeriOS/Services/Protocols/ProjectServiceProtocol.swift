import FirebaseFirestore

protocol ProjectServiceProtocol: Sendable {
    func getProject(accountId: String, projectId: String) async throws -> Project?
    func createProject(accountId: String, name: String, clientName: String, description: String?) throws -> String
    func updateProject(accountId: String, projectId: String, fields: [String: Any]) async throws
    func deleteProject(accountId: String, projectId: String) async throws
    func subscribeToProjects(accountId: String, onChange: @escaping ([Project]) -> Void) -> ListenerRegistration
    func subscribeToProject(accountId: String, projectId: String, onChange: @escaping (Project?) -> Void) -> ListenerRegistration
}
