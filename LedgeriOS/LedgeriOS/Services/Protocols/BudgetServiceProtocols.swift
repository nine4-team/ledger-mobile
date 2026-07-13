import FirebaseFirestore

// MARK: - AccountsService

protocol AccountsServiceProtocol: Sendable {
    func getAccount(accountId: String) async throws -> Account?
    func subscribeToAccount(accountId: String, onChange: @escaping (Account?) -> Void) -> ListenerRegistration
    func createAccount(name: String) async throws -> String
    func updateAccount(accountId: String, fields: [String: Any]) async throws
}

// MARK: - BudgetCategoriesService

protocol BudgetCategoriesServiceProtocol: Sendable {
    func subscribeToBudgetCategories(accountId: String, onChange: @escaping ([BudgetCategory]) -> Void) -> ListenerRegistration
    func createBudgetCategory(accountId: String, category: BudgetCategory) throws -> String
    func updateBudgetCategory(accountId: String, categoryId: String, fields: [String: Any]) async throws
    func deleteBudgetCategory(accountId: String, categoryId: String) async throws
}

// MARK: - ProjectBudgetCategoriesService

protocol ProjectBudgetCategoriesServiceProtocol: Sendable {
    func subscribeToProjectBudgetCategories(accountId: String, projectId: String, onChange: @escaping ([ProjectBudgetCategory]) -> Void) -> ListenerRegistration
    func setProjectBudgetCategory(accountId: String, projectId: String, categoryId: String, budgetCents: Int, userId: String?) async throws
    func deleteProjectBudgetCategory(accountId: String, projectId: String, categoryId: String) async throws
}

// MARK: - FeeInstallmentsService

protocol FeeInstallmentsServiceProtocol: Sendable {
    func subscribeToFeeInstallments(accountId: String, projectId: String, onChange: @escaping ([FeeInstallment]) -> Void) -> ListenerRegistration

    func createFeeInstallment(
        accountId: String,
        projectId: String,
        budgetCategoryId: String,
        label: String,
        amountCents: Int,
        sortOrder: Int?,
        projectBudgetCategory: ProjectBudgetCategory?,
        existingInstallments: [FeeInstallment],
        userId: String?
    ) async throws -> String

    func updateFeeInstallment(
        accountId: String,
        projectId: String,
        installmentId: String,
        budgetCategoryId: String,
        label: String,
        amountCents: Int,
        sortOrder: Int?,
        projectBudgetCategory: ProjectBudgetCategory?,
        existingInstallments: [FeeInstallment],
        userId: String?
    ) async throws

    func deleteFeeInstallment(accountId: String, projectId: String, installmentId: String) async throws
}

// MARK: - AccountMembersService

protocol AccountMembersServiceProtocol: Sendable {
    func subscribeToMember(accountId: String, userId: String, onChange: @escaping (AccountMember?) -> Void) -> ListenerRegistration
    func listMembershipsForUser(userId: String) async throws -> [AccountMember]
    func updateAccess(accountId: String, userId: String, role: MemberRole, companyFinancialAccess: CompanyFinancialAccess, allowedFeeCategoryIds: [String]) async throws
}
