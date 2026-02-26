import FirebaseFirestore

// MARK: - AccountsService

protocol AccountsServiceProtocol {
    func getAccount(accountId: String) async throws -> Account?
    func subscribeToAccount(accountId: String, onChange: @escaping (Account?) -> Void) -> ListenerRegistration
}

// MARK: - BudgetCategoriesService

protocol BudgetCategoriesServiceProtocol {
    func subscribeToBudgetCategories(accountId: String, onChange: @escaping ([BudgetCategory]) -> Void) -> ListenerRegistration
    func createBudgetCategory(accountId: String, category: BudgetCategory) throws -> String
    func updateBudgetCategory(accountId: String, categoryId: String, fields: [String: Any]) async throws
    func deleteBudgetCategory(accountId: String, categoryId: String) async throws
}

// MARK: - ProjectBudgetCategoriesService

protocol ProjectBudgetCategoriesServiceProtocol {
    func subscribeToProjectBudgetCategories(accountId: String, projectId: String, onChange: @escaping ([ProjectBudgetCategory]) -> Void) -> ListenerRegistration
    func setProjectBudgetCategory(accountId: String, projectId: String, categoryId: String, budgetCents: Int, userId: String?) async throws
}

// MARK: - AccountMembersService

protocol AccountMembersServiceProtocol {
    func subscribeToMember(accountId: String, userId: String, onChange: @escaping (AccountMember?) -> Void) -> ListenerRegistration
}
