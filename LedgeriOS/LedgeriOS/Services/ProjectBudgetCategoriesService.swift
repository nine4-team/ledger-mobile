import FirebaseFirestore

struct ProjectBudgetCategoriesService: ProjectBudgetCategoriesServiceProtocol {
    private func repo(accountId: String, projectId: String) -> FirestoreRepository<ProjectBudgetCategory> {
        FirestoreRepository<ProjectBudgetCategory>(
            path: "accounts/\(accountId)/projects/\(projectId)/budgetCategories"
        )
    }

    private func collectionRef(accountId: String, projectId: String) -> CollectionReference {
        Firestore.firestore()
            .collection("accounts/\(accountId)/projects/\(projectId)/budgetCategories")
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
        let docRef = collectionRef(accountId: accountId, projectId: projectId).document(categoryId)
        var fields: [String: Any] = [
            "budgetCents": budgetCents,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let userId {
            fields["updatedBy"] = userId
        }
        try await docRef.setData(fields, merge: true)
    }

    func deleteProjectBudgetCategory(
        accountId: String,
        projectId: String,
        categoryId: String
    ) async throws {
        let docRef = collectionRef(accountId: accountId, projectId: projectId).document(categoryId)
        try await docRef.delete()
    }
}
