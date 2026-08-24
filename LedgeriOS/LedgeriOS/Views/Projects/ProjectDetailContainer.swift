import SwiftUI

/// Owns project-scoped state for one project detail surface.
///
/// Each open project detail needs an independent ProjectContext so macOS
/// windows can compare different projects without sharing active budget/items.
///
/// Route identity is the **project ID**, not a mutable `Project` value. The
/// displayed project resolves from live context / account data, falling back to
/// an optional initial snapshot for immediate first paint.
struct ProjectDetailContainer: View {
    let projectId: String
    let initialProject: Project?

    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager
    @State private var projectContext: ProjectContext

    init(projectId: String, initialProject: Project? = nil) {
        self.projectId = projectId
        self.initialProject = initialProject

        let projectService = ProjectService()
        let transactionsService = TransactionsService()
        let itemsService = ItemsService()
        let protoItemsService = ProtoItemsService()
        let spacesService = SpacesService()
        let projectBudgetCategoriesService = ProjectBudgetCategoriesService()

        _projectContext = State(initialValue: ProjectContext(
            projectService: projectService,
            transactionsService: transactionsService,
            itemsService: itemsService,
            protoItemsService: protoItemsService,
            spacesService: spacesService,
            projectBudgetCategoriesService: projectBudgetCategoriesService
        ))
    }

    /// Live project for display. Prefers the focused project listener, then the
    /// account-level list, then the initial snapshot passed at push time.
    private var displayProject: Project? {
        if let project = projectContext.project, project.id == projectId {
            return project
        }
        if let project = NavigationRouteResolution.project(id: projectId, in: accountContext.allProjects) {
            return project
        }
        return initialProject
    }

    var body: some View {
        content
            .environment(projectContext)
            .onAppear {
                PerformanceDiagnostics.shared.setScenario("project-detail")
                PerformanceDiagnostics.shared.event("DetailAppeared", kind: "project")
            }
            .onDisappear {
                PerformanceDiagnostics.shared.event("DetailDisappeared", kind: "project")
            }
            .task(id: activationKey) {
                activateProjectContext()
            }
            .onChange(of: accountContext.member) { _, member in
                updateProjectFinancialContext(member: member)
            }
            .onChange(of: accountContext.rawAllBudgetCategories) { _, _ in
                updateProjectFinancialContext(member: accountContext.member)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let displayProject {
            ProjectDetailView(project: displayProject)
        } else {
            // Project listener hasn't returned yet and there is no cached
            // snapshot. This is first-paint only, not the rename path.
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(BrandColors.background)
        }
    }

    private var activationKey: String {
        [
            accountContext.currentAccountId ?? "",
            projectId,
            authManager.currentUser?.uid ?? ""
        ].joined(separator: "|")
    }

    private func activateProjectContext() {
        guard let accountId = accountContext.currentAccountId else { return }

        NavLifecycleLog.log("ProjectDetailContainer.activate key=\(activationKey)")
        projectContext.activate(
            accountId: accountId,
            projectId: projectId,
            userId: authManager.currentUser?.uid,
            member: accountContext.member,
            rawBudgetCategories: accountContext.rawAllBudgetCategories
        )
    }

    private func updateProjectFinancialContext(member: AccountMember?) {
        projectContext.updateFinancialContext(
            member: member,
            rawBudgetCategories: accountContext.rawAllBudgetCategories
        )
    }
}
