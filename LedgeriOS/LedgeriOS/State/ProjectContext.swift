import FirebaseFirestore

@MainActor
@Observable
final class ProjectContext {
    var currentProjectId: String?
    var project: Project?
    var projects: [Project] = []
    var transactions: [Transaction] = []
    var items: [Item] = []
    var spaces: [Space] = []
    var budgetCategories: [BudgetCategory] = []
    var projectBudgetCategories: [ProjectBudgetCategory] = []
    var budgetProgress: BudgetProgress?

    private var listeners: [ListenerRegistration] = []
    private let projectService: ProjectServiceProtocol
    private let transactionsService: TransactionsServiceProtocol
    private let itemsService: ItemsServiceProtocol
    private let spacesService: SpacesServiceProtocol
    private let budgetCategoriesService: BudgetCategoriesServiceProtocol
    private let projectBudgetCategoriesService: ProjectBudgetCategoriesServiceProtocol
    private let budgetProgressService: BudgetProgressService

    init(
        projectService: ProjectServiceProtocol,
        transactionsService: TransactionsServiceProtocol,
        itemsService: ItemsServiceProtocol,
        spacesService: SpacesServiceProtocol,
        budgetCategoriesService: BudgetCategoriesServiceProtocol,
        projectBudgetCategoriesService: ProjectBudgetCategoriesServiceProtocol,
        budgetProgressService: BudgetProgressService = BudgetProgressService()
    ) {
        self.projectService = projectService
        self.transactionsService = transactionsService
        self.itemsService = itemsService
        self.spacesService = spacesService
        self.budgetCategoriesService = budgetCategoriesService
        self.projectBudgetCategoriesService = projectBudgetCategoriesService
        self.budgetProgressService = budgetProgressService
    }

    /// Activate subscriptions for a project. Call from `.task(id: projectId)` —
    /// SwiftUI auto-cancels on disappear or ID change.
    func activate(accountId: String, projectId: String) {
        deactivate()
        currentProjectId = projectId

        // 1. Project detail
        listeners.append(
            projectService.subscribeToProject(accountId: accountId, projectId: projectId) { [weak self] project in
                Task { @MainActor in self?.project = project }
            }
        )

        // 2. Projects list (for sibling navigation)
        listeners.append(
            projectService.subscribeToProjects(accountId: accountId) { [weak self] projects in
                Task { @MainActor in self?.projects = projects }
            }
        )

        // 3. Transactions scoped to project
        listeners.append(
            transactionsService.subscribeToTransactions(accountId: accountId, scope: .project(projectId)) { [weak self] transactions in
                Task { @MainActor in
                    self?.transactions = transactions
                    self?.recomputeBudgetProgress()
                }
            }
        )

        // 4. Items scoped to project
        listeners.append(
            itemsService.subscribeToItems(accountId: accountId, scope: .project(projectId)) { [weak self] items in
                Task { @MainActor in self?.items = items }
            }
        )

        // 5. Spaces scoped to project
        listeners.append(
            spacesService.subscribeToSpaces(accountId: accountId, scope: .project(projectId)) { [weak self] spaces in
                Task { @MainActor in self?.spaces = spaces }
            }
        )

        // 6. Budget categories (account-level presets)
        listeners.append(
            budgetCategoriesService.subscribeToBudgetCategories(accountId: accountId) { [weak self] categories in
                Task { @MainActor in
                    self?.budgetCategories = categories
                    self?.recomputeBudgetProgress()
                }
            }
        )

        // 7. Project budget categories
        listeners.append(
            projectBudgetCategoriesService.subscribeToProjectBudgetCategories(
                accountId: accountId,
                projectId: projectId
            ) { [weak self] pbc in
                Task { @MainActor in
                    self?.projectBudgetCategories = pbc
                    self?.recomputeBudgetProgress()
                }
            }
        )
    }

    func deactivate() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        currentProjectId = nil
        project = nil
        projects = []
        transactions = []
        items = []
        spaces = []
        budgetCategories = []
        projectBudgetCategories = []
        budgetProgress = nil
    }

    private func recomputeBudgetProgress() {
        budgetProgress = budgetProgressService.buildBudgetProgress(
            transactions: transactions,
            categories: budgetCategories,
            projectBudgetCategories: projectBudgetCategories
        )
    }
}
