import FirebaseFirestore

@MainActor
@Observable
final class ProjectContext {
    var currentProjectId: String?
    var project: Project?
    var projects: [Project] = []
    var transactions: [Transaction] = []
    var items: [Item] = []
    var protoItems: [ProtoItem] = []
    var spaces: [Space] = []
    var budgetCategories: [BudgetCategory] = []
    var projectBudgetCategories: [ProjectBudgetCategory] = []
    var feeInstallments: [FeeInstallment] = []
    var budgetProgress: BudgetProgress?
    var projectPreferences: ProjectPreferences?
    var notes: [ProjectNote] = []

    private var financialAccessMember: AccountMember?
    private var rawTransactions: [Transaction] = []
    private var rawBudgetCategories: [BudgetCategory] = []
    private var activeAccountId: String?
    private var activeUserId: String?
    private var listeners: [ListenerRegistration] = []
    private let projectService: ProjectServiceProtocol
    private let transactionsService: TransactionsServiceProtocol
    private let itemsService: ItemsServiceProtocol
    private let protoItemsService: ProtoItemsServiceProtocol?
    private let spacesService: SpacesServiceProtocol
    private let budgetCategoriesService: BudgetCategoriesServiceProtocol
    private let projectBudgetCategoriesService: ProjectBudgetCategoriesServiceProtocol
    private let feeInstallmentsService: FeeInstallmentsServiceProtocol
    private let budgetProgressService: BudgetProgressService
    private let projectPreferencesService: ProjectPreferencesService
    private let projectNotesService: ProjectNotesServiceProtocol

    init(
        projectService: ProjectServiceProtocol,
        transactionsService: TransactionsServiceProtocol,
        itemsService: ItemsServiceProtocol,
        protoItemsService: ProtoItemsServiceProtocol? = nil,
        spacesService: SpacesServiceProtocol,
        budgetCategoriesService: BudgetCategoriesServiceProtocol,
        projectBudgetCategoriesService: ProjectBudgetCategoriesServiceProtocol,
        feeInstallmentsService: FeeInstallmentsServiceProtocol = FeeInstallmentsService(),
        budgetProgressService: BudgetProgressService = BudgetProgressService(),
        projectPreferencesService: ProjectPreferencesService = ProjectPreferencesService(),
        projectNotesService: ProjectNotesServiceProtocol = ProjectNotesService()
    ) {
        self.projectService = projectService
        self.transactionsService = transactionsService
        self.itemsService = itemsService
        self.protoItemsService = protoItemsService
        self.spacesService = spacesService
        self.budgetCategoriesService = budgetCategoriesService
        self.projectBudgetCategoriesService = projectBudgetCategoriesService
        self.feeInstallmentsService = feeInstallmentsService
        self.budgetProgressService = budgetProgressService
        self.projectPreferencesService = projectPreferencesService
        self.projectNotesService = projectNotesService
    }

    /// Activate subscriptions for a project. Re-entering the same account/project/user
    /// keeps the current listeners and cached data alive.
    func activate(accountId: String, projectId: String, userId: String? = nil, member: AccountMember? = nil) {
        if activeAccountId == accountId,
           currentProjectId == projectId,
           activeUserId == userId,
           !listeners.isEmpty {
            NavLifecycleLog.log("ProjectContext.activate early-return (same project=\(projectId))")
            updateFinancialAccess(member: member)
            return
        }

        let isNewProject = currentProjectId != projectId || activeAccountId != accountId
        NavLifecycleLog.log("ProjectContext.activate restart project=\(projectId) isNewProject=\(isNewProject)")
        stopListeners()
        if isNewProject {
            clearData()
        }
        activeAccountId = accountId
        activeUserId = userId
        currentProjectId = projectId
        financialAccessMember = member

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
                    self?.rawTransactions = transactions
                    self?.applyFinancialAccess()
                }
            }
        )

        // 4. Items scoped to project
        listeners.append(
            itemsService.subscribeToItems(accountId: accountId, scope: .project(projectId)) { [weak self] items in
                Task { @MainActor in self?.items = items }
            }
        )

        // 5. Proto-items scoped to project
        if let protoItemsService {
            listeners.append(
                protoItemsService.subscribeToProtoItems(accountId: accountId, scope: .project(projectId)) { [weak self] protoItems in
                    Task { @MainActor in self?.protoItems = protoItems }
                }
            )
        }

        // 6. Spaces scoped to project
        listeners.append(
            spacesService.subscribeToSpaces(accountId: accountId, scope: .project(projectId)) { [weak self] spaces in
                Task { @MainActor in self?.spaces = spaces }
            }
        )

        // 6. Budget categories (account-level presets)
        listeners.append(
            budgetCategoriesService.subscribeToBudgetCategories(accountId: accountId) { [weak self] categories in
                Task { @MainActor in
                    self?.rawBudgetCategories = categories
                    self?.applyFinancialAccess()
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

        // 8. Fee installments
        listeners.append(
            feeInstallmentsService.subscribeToFeeInstallments(
                accountId: accountId,
                projectId: projectId
            ) { [weak self] installments in
                Task { @MainActor in
                    self?.feeInstallments = installments
                }
            }
        )

        // 9. Project preferences (pinned categories)
        if let userId {
            listeners.append(
                projectPreferencesService.subscribeToProjectPreferences(
                    accountId: accountId,
                    userId: userId,
                    projectId: projectId
                ) { [weak self] prefs in
                    Task { @MainActor in self?.projectPreferences = prefs }
                }
            )
        }

        // 10. Notes scoped to project
        listeners.append(
            projectNotesService.subscribeToProjectNotes(
                accountId: accountId,
                projectId: projectId
            ) { [weak self] notes in
                Task { @MainActor in
                    self?.notes = notes
                }
            }
        )
    }

    func deleteProject(accountId: String, projectId: String) async throws {
        try await projectService.deleteProject(accountId: accountId, projectId: projectId)
    }

    /// Archive or unarchive a project. Preferred over deletion (H2).
    func archiveProject(accountId: String, projectId: String, isArchived: Bool) async throws {
        try await projectService.updateProject(
            accountId: accountId,
            projectId: projectId,
            fields: ["isArchived": isArchived]
        )
    }

    func addNote(accountId: String, projectId: String, text: String, source: String, userId: String?, userName: String?) async throws {
        var note = ProjectNote()
        note.text = text
        note.source = source
        note.createdBy = userId ?? ""
        note.createdByName = userName ?? ""
        note.createdAt = Date()
        try await projectNotesService.addProjectNote(accountId: accountId, projectId: projectId, note: note)
    }

    func updateNote(accountId: String, projectId: String, noteId: String, text: String) async throws {
        try await projectNotesService.updateProjectNote(
            accountId: accountId,
            projectId: projectId,
            noteId: noteId,
            fields: [
                "text": text,
                "updatedAt": Date()
            ]
        )
    }

    func deleteNote(accountId: String, projectId: String, noteId: String) async throws {
        try await projectNotesService.deleteProjectNote(
            accountId: accountId,
            projectId: projectId,
            noteId: noteId
        )
    }

    func stopListeners() {
        if !listeners.isEmpty {
            NavLifecycleLog.log("ProjectContext.stopListeners count=\(listeners.count) project=\(currentProjectId ?? "nil")")
        }
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }

    func deactivate() {
        NavLifecycleLog.log("ProjectContext.deactivate project=\(currentProjectId ?? "nil")")
        stopListeners()
        clearData()
    }

    func updateFinancialAccess(member: AccountMember?) {
        financialAccessMember = member
        applyFinancialAccess()
    }

    private func clearData() {
        activeAccountId = nil
        activeUserId = nil
        currentProjectId = nil
        project = nil
        projects = []
        transactions = []
        items = []
        protoItems = []
        spaces = []
        budgetCategories = []
        projectBudgetCategories = []
        feeInstallments = []
        budgetProgress = nil
        projectPreferences = nil
        notes = []
        financialAccessMember = nil
        rawTransactions = []
        rawBudgetCategories = []
    }

    /// Budget categories enabled for this project (have a ProjectBudgetCategory document).
    var enabledBudgetCategories: [BudgetCategory] {
        let enabledIds = Set(projectBudgetCategories.compactMap(\.id))
        return budgetCategories.filter { cat in
            guard let id = cat.id else { return false }
            return enabledIds.contains(id)
        }
    }

    private func recomputeBudgetProgress() {
        budgetProgress = budgetProgressService.buildBudgetProgress(
            transactions: transactions,
            categories: budgetCategories,
            projectBudgetCategories: projectBudgetCategories
        )
    }

    private func applyFinancialAccess() {
        let policy = FinancialAccessPolicy(member: financialAccessMember)
        budgetCategories = policy.visibleCategories(rawBudgetCategories)
        transactions = policy.visibleTransactions(rawTransactions, categories: rawBudgetCategories)
        recomputeBudgetProgress()
    }
}
