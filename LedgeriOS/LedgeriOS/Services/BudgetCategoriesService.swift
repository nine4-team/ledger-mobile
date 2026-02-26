import FirebaseFirestore

struct BudgetCategoriesService: BudgetCategoriesServiceProtocol {
    let syncTracker: SyncTracking

    private func repo(accountId: String) -> FirestoreRepository<BudgetCategory> {
        FirestoreRepository<BudgetCategory>(path: "accounts/\(accountId)/presets/default/budgetCategories")
    }

    func subscribeToBudgetCategories(accountId: String, onChange: @escaping ([BudgetCategory]) -> Void) -> ListenerRegistration {
        repo(accountId: accountId).subscribe(onChange: onChange)
    }

    func createBudgetCategory(accountId: String, category: BudgetCategory) throws -> String {
        let id = try repo(accountId: accountId).create(category)
        syncTracker.trackPendingWrite()
        return id
    }

    func updateBudgetCategory(accountId: String, categoryId: String, fields: [String: Any]) async throws {
        try await repo(accountId: accountId).update(id: categoryId, fields: fields)
        syncTracker.trackPendingWrite()
    }

    func deleteBudgetCategory(accountId: String, categoryId: String) async throws {
        try await repo(accountId: accountId).delete(id: categoryId)
        syncTracker.trackPendingWrite()
    }
}
