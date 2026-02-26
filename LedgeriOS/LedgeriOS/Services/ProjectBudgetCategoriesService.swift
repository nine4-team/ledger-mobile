import FirebaseFirestore

struct ProjectBudgetCategoriesService: ProjectBudgetCategoriesServiceProtocol {
    let syncTracker: SyncTracking

    private func repo(accountId: String, projectId: String) -> FirestoreRepository<ProjectBudgetCategory> {
        FirestoreRepository<ProjectBudgetCategory>(
            path: "accounts/\(accountId)/projects/\(projectId)/budgetCategories"
        )
    }

    func subscribeToProjectBudgetCategories(
        accountId: String,
        projectId: String,
        onChange: @escaping ([ProjectBudgetCategory]) -> Void
    ) -> ListenerRegistration {
        repo(accountId: accountId, projectId: projectId).subscribe(onChange: onChange)
    }

    func setProjectBudgetCategory(
        accountId: String,
        projectId: String,
        categoryId: String,
        budgetCents: Int,
        userId: String?
    ) async throws {
        let r = repo(accountId: accountId, projectId: projectId)
        var fields: [String: Any] = ["budgetCents": budgetCents]
        if let userId {
            fields["updatedBy"] = userId
        }
        try await r.update(id: categoryId, fields: fields)
        syncTracker.trackPendingWrite()
    }
}
