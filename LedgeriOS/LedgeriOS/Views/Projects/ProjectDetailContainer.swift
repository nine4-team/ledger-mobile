import SwiftUI

/// Owns project-scoped state for one project detail surface.
///
/// Each open project detail needs an independent ProjectContext so macOS
/// windows can compare different projects without sharing active budget/items.
struct ProjectDetailContainer: View {
    let project: Project

    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager
    @State private var projectContext: ProjectContext

    init(project: Project) {
        self.project = project

        let projectService = ProjectService()
        let transactionsService = TransactionsService()
        let itemsService = ItemsService()
        let spacesService = SpacesService()
        let budgetCategoriesService = BudgetCategoriesService()
        let projectBudgetCategoriesService = ProjectBudgetCategoriesService()

        _projectContext = State(initialValue: ProjectContext(
            projectService: projectService,
            transactionsService: transactionsService,
            itemsService: itemsService,
            spacesService: spacesService,
            budgetCategoriesService: budgetCategoriesService,
            projectBudgetCategoriesService: projectBudgetCategoriesService
        ))
    }

    var body: some View {
        ProjectDetailView(project: project)
            .environment(projectContext)
            .task(id: activationKey) {
                activateProjectContext()
            }
            .onChange(of: accountContext.member) { _, member in
                projectContext.updateFinancialAccess(member: member)
            }
    }

    private var activationKey: String {
        [
            accountContext.currentAccountId ?? "",
            project.id ?? "",
            authManager.currentUser?.uid ?? ""
        ].joined(separator: "|")
    }

    private func activateProjectContext() {
        guard let accountId = accountContext.currentAccountId,
              let projectId = project.id else { return }

        projectContext.activate(
            accountId: accountId,
            projectId: projectId,
            userId: authManager.currentUser?.uid,
            member: accountContext.member
        )
    }
}
