import FirebaseFirestore

struct ProjectService: ProjectServiceProtocol {
    let syncTracker: SyncTracking

    private func repo(accountId: String) -> FirestoreRepository<Project> {
        FirestoreRepository<Project>(path: "accounts/\(accountId)/projects")
    }

    func getProject(accountId: String, projectId: String) async throws -> Project? {
        try await repo(accountId: accountId).get(id: projectId)
    }

    func createProject(accountId: String, name: String, clientName: String, description: String?) throws -> String {
        var project = Project()
        project.accountId = accountId
        project.name = name
        project.clientName = clientName
        project.description = description
        let id = try repo(accountId: accountId).create(project)
        syncTracker.trackPendingWrite()
        return id
    }

    func updateProject(accountId: String, projectId: String, fields: [String: Any]) async throws {
        try await repo(accountId: accountId).update(id: projectId, fields: fields)
        syncTracker.trackPendingWrite()
    }

    func deleteProject(accountId: String, projectId: String) async throws {
        try await repo(accountId: accountId).delete(id: projectId)
        syncTracker.trackPendingWrite()
    }

    func subscribeToProjects(accountId: String, onChange: @escaping ([Project]) -> Void) -> ListenerRegistration {
        repo(accountId: accountId).subscribe(onChange: onChange)
    }

    func subscribeToProject(accountId: String, projectId: String, onChange: @escaping (Project?) -> Void) -> ListenerRegistration {
        repo(accountId: accountId).subscribe(id: projectId, onChange: onChange)
    }
}
