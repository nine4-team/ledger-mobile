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
            PerformanceDiagnostics.shared.event("ContextActivationEarlyReturn", kind: "project", count: listeners.count)
            updateFinancialAccess(member: member)
            return
        }

        let isNewProject = currentProjectId != projectId || activeAccountId != accountId
        NavLifecycleLog.log("ProjectContext.activate restart project=\(projectId) isNewProject=\(isNewProject)")
        PerformanceDiagnostics.shared.event("ContextActivationStart", kind: "project", count: listeners.count)
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
                let receivedAt = DispatchTime.now().uptimeNanoseconds
                Task { @MainActor in
                    guard let self else { return }
                    self.publish(kind: "project.detail", receivedAt: receivedAt, count: project == nil ? 0 : 1) {
                        self.project = project
                    }
                }
            }
        )

        // 2. Projects list (for sibling navigation)
        listeners.append(
            projectService.subscribeToProjects(accountId: accountId) { [weak self] projects in
                let receivedAt = DispatchTime.now().uptimeNanoseconds
                Task { @MainActor in
                    guard let self else { return }
                    self.publish(kind: "project.projects", receivedAt: receivedAt, count: projects.count) {
                        self.projects = projects
                    }
                }
            }
        )

        // 3. Transactions scoped to project
        listeners.append(
            transactionsService.subscribeToTransactions(accountId: accountId, scope: .project(projectId)) { [weak self] transactions in
                let receivedAt = DispatchTime.now().uptimeNanoseconds
                Task { @MainActor in
                    guard let self else { return }
                    self.publish(kind: "project.transactions", receivedAt: receivedAt, count: transactions.count) {
                        self.rawTransactions = transactions
                        self.applyFinancialAccess()
                    }
                }
            }
        )

        // 4. Items scoped to project
        listeners.append(
            itemsService.subscribeToItems(accountId: accountId, scope: .project(projectId)) { [weak self] items in
                let receivedAt = DispatchTime.now().uptimeNanoseconds
                Task { @MainActor in
                    guard let self else { return }
                    self.publish(kind: "project.items", receivedAt: receivedAt, count: items.count) {
                        self.items = items
                    }
                }
            }
        )

        // 5. Proto-items scoped to project
        if let protoItemsService {
            listeners.append(
                protoItemsService.subscribeToProtoItems(accountId: accountId, scope: .project(projectId)) { [weak self] protoItems in
                    let receivedAt = DispatchTime.now().uptimeNanoseconds
                    Task { @MainActor in
                        guard let self else { return }
                        self.publish(kind: "project.proto-items", receivedAt: receivedAt, count: protoItems.count) {
                            self.protoItems = protoItems
                        }
                    }
                }
            )
        }

        // 6. Spaces scoped to project
        listeners.append(
            spacesService.subscribeToSpaces(accountId: accountId, scope: .project(projectId)) { [weak self] spaces in
                let receivedAt = DispatchTime.now().uptimeNanoseconds
                Task { @MainActor in
                    guard let self else { return }
                    self.publish(kind: "project.spaces", receivedAt: receivedAt, count: spaces.count) {
                        self.spaces = spaces
                    }
                }
            }
        )

        // 6. Budget categories (account-level presets)
        listeners.append(
            budgetCategoriesService.subscribeToBudgetCategories(accountId: accountId) { [weak self] categories in
                let receivedAt = DispatchTime.now().uptimeNanoseconds
                Task { @MainActor in
                    guard let self else { return }
                    self.publish(kind: "project.categories", receivedAt: receivedAt, count: categories.count) {
                        self.rawBudgetCategories = categories
                        self.applyFinancialAccess()
                    }
                }
            }
        )

        // 7. Project budget categories
        listeners.append(
            projectBudgetCategoriesService.subscribeToProjectBudgetCategories(
                accountId: accountId,
                projectId: projectId
            ) { [weak self] pbc in
                let receivedAt = DispatchTime.now().uptimeNanoseconds
                Task { @MainActor in
                    guard let self else { return }
                    self.publish(kind: "project.budget-categories", receivedAt: receivedAt, count: pbc.count) {
                        self.projectBudgetCategories = pbc
                        self.recomputeBudgetProgress()
                    }
                }
            }
        )

        // 8. Fee installments
        listeners.append(
            feeInstallmentsService.subscribeToFeeInstallments(
                accountId: accountId,
                projectId: projectId
            ) { [weak self] installments in
                let receivedAt = DispatchTime.now().uptimeNanoseconds
                Task { @MainActor in
                    guard let self else { return }
                    self.publish(kind: "project.fee-installments", receivedAt: receivedAt, count: installments.count) {
                        self.feeInstallments = installments
                    }
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
                    let receivedAt = DispatchTime.now().uptimeNanoseconds
                    Task { @MainActor in
                        guard let self else { return }
                        self.publish(kind: "project.preferences", receivedAt: receivedAt, count: prefs == nil ? 0 : 1) {
                            self.projectPreferences = prefs
                        }
                    }
                }
            )
        }

        // 10. Notes scoped to project
        listeners.append(
            projectNotesService.subscribeToProjectNotes(
                accountId: accountId,
                projectId: projectId
            ) { [weak self] notes in
                let receivedAt = DispatchTime.now().uptimeNanoseconds
                Task { @MainActor in
                    guard let self else { return }
                    self.publish(kind: "project.notes", receivedAt: receivedAt, count: notes.count) {
                        self.notes = notes
                    }
                }
            }
        )
        PerformanceDiagnostics.shared.event("ContextActivationComplete", kind: "project", count: listeners.count)
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
        PerformanceDiagnostics.shared.event("ContextListenersStopped", kind: "project")
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
        ProjectBudgetCategoryResolver.resolve(
            projectBudgetCategoryRows: projectBudgetCategories,
            accountBudgetCategories: budgetCategories
        )
    }

    private func recomputeBudgetProgress() {
        let interval = PerformanceDiagnostics.shared.beginInterval(
            "BudgetProgress",
            kind: "project",
            count: transactions.count + budgetCategories.count + projectBudgetCategories.count
        )
        budgetProgress = budgetProgressService.buildBudgetProgress(
            transactions: transactions,
            categories: budgetCategories,
            projectBudgetCategories: projectBudgetCategories
        )
        PerformanceDiagnostics.shared.endInterval(interval)
    }

    private func applyFinancialAccess() {
        let interval = PerformanceDiagnostics.shared.beginInterval(
            "FinancialAccess",
            kind: "project",
            count: rawTransactions.count + rawBudgetCategories.count
        )
        let policy = FinancialAccessPolicy(member: financialAccessMember)
        budgetCategories = policy.visibleCategories(rawBudgetCategories)
        transactions = policy.visibleTransactions(rawTransactions, categories: rawBudgetCategories)
        recomputeBudgetProgress()
        PerformanceDiagnostics.shared.endInterval(
            interval,
            value: transactions.count + budgetCategories.count
        )
    }

    private func publish(kind: String, receivedAt: UInt64, count: Int, update: () -> Void) {
        let queueDelayMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - receivedAt) / 1_000_000
        PerformanceDiagnostics.shared.duration(
            "MainActorDelivery",
            kind: kind,
            milliseconds: queueDelayMilliseconds,
            count: count
        )
        let interval = PerformanceDiagnostics.shared.beginInterval("ContextPublish", kind: kind, count: count)
        update()
        PerformanceDiagnostics.shared.endInterval(interval)
    }
}
