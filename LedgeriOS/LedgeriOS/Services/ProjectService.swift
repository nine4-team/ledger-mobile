import FirebaseFirestore

struct ProjectService: ProjectServiceProtocol {
    private func repo(accountId: String) -> FirestoreRepository<Project> {
        FirestoreRepository<Project>(path: "accounts/\(accountId)/projects")
    }

    func getProject(accountId: String, projectId: String) async throws -> Project? {
        try await repo(accountId: accountId).get(id: projectId)
    }

    func createProject(accountId: String, name: String, clientName: String, description: String?, paymentMethodLast4: String? = nil) throws -> String {
        var project = Project()
        project.accountId = accountId
        project.name = name
        project.clientName = clientName
        project.description = description
        project.paymentMethodLast4 = paymentMethodLast4
        let id = try repo(accountId: accountId).create(project)
        return id
    }

    func updateProject(accountId: String, projectId: String, fields: [String: Any]) async throws {
        try await repo(accountId: accountId).update(id: projectId, fields: fields)
    }

    func deleteProject(accountId: String, projectId: String) async throws {
        try await repo(accountId: accountId).delete(id: projectId)
    }

    func subscribeToProjects(accountId: String, onChange: @escaping ([Project]) -> Void) -> ListenerRegistration {
        repo(accountId: accountId).subscribe(onChange: onChange)
    }

    func subscribeToProject(accountId: String, projectId: String, onChange: @escaping (Project?) -> Void) -> ListenerRegistration {
        repo(accountId: accountId).subscribe(id: projectId, onChange: onChange)
    }
}
