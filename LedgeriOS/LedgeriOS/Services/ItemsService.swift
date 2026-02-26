import FirebaseFirestore

struct ItemsService: ItemsServiceProtocol {
    let syncTracker: SyncTracking

    private func repo(accountId: String) -> FirestoreRepository<Item> {
        FirestoreRepository<Item>(path: "accounts/\(accountId)/items")
    }

    func getItem(accountId: String, itemId: String) async throws -> Item? {
        try await repo(accountId: accountId).get(id: itemId)
    }

    func createItem(accountId: String, item: Item) throws -> String {
        let id = try repo(accountId: accountId).create(item)
        syncTracker.trackPendingWrite()
        return id
    }

    func updateItem(accountId: String, itemId: String, fields: [String: Any]) async throws {
        try await repo(accountId: accountId).update(id: itemId, fields: fields)
        syncTracker.trackPendingWrite()
    }

    func deleteItem(accountId: String, itemId: String) async throws {
        try await repo(accountId: accountId).delete(id: itemId)
        syncTracker.trackPendingWrite()
    }

    func subscribeToItems(accountId: String, scope: ListScope, onChange: @escaping ([Item]) -> Void) -> ListenerRegistration {
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

    func subscribeToItem(accountId: String, itemId: String, onChange: @escaping (Item?) -> Void) -> ListenerRegistration {
        repo(accountId: accountId).subscribe(id: itemId, onChange: onChange)
    }
}
