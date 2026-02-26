import FirebaseFirestore

struct SpacesService: SpacesServiceProtocol {
    let syncTracker: SyncTracking

    private func repo(accountId: String) -> FirestoreRepository<Space> {
        FirestoreRepository<Space>(path: "accounts/\(accountId)/spaces")
    }

    func getSpace(accountId: String, spaceId: String) async throws -> Space? {
        try await repo(accountId: accountId).get(id: spaceId)
    }

    func createSpace(accountId: String, space: Space) throws -> String {
        let id = try repo(accountId: accountId).create(space)
        syncTracker.trackPendingWrite()
        return id
    }

    func updateSpace(accountId: String, spaceId: String, fields: [String: Any]) async throws {
        try await repo(accountId: accountId).update(id: spaceId, fields: fields)
        syncTracker.trackPendingWrite()
    }

    func deleteSpace(accountId: String, spaceId: String) async throws {
        try await repo(accountId: accountId).delete(id: spaceId)
        syncTracker.trackPendingWrite()
    }

    func subscribeToSpaces(accountId: String, scope: ListScope, onChange: @escaping ([Space]) -> Void) -> ListenerRegistration {
        let r = repo(accountId: accountId)
        switch scope {
        case .project(let projectId):
            return r.subscribe(where: "projectId", isEqualTo: projectId, onChange: onChange)
        case .inventory:
            return r.subscribe(where: "projectId", isEqualTo: NSNull(), onChange: onChange)
        case .all:
            return r.subscribe(onChange: onChange)
        }
    }

    func subscribeToSpace(accountId: String, spaceId: String, onChange: @escaping (Space?) -> Void) -> ListenerRegistration {
        repo(accountId: accountId).subscribe(id: spaceId, onChange: onChange)
    }
}
