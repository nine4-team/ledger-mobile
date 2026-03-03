import SwiftUI
import FirebaseFirestore

struct ProjectsListView: View {
    @Environment(AccountContext.self) private var accountContext
    @State private var selectedTab = "active"
    @State private var searchText = ""
    @State private var projects: [Project] = []
    @State private var listener: ListenerRegistration?
    @State private var showNewProject = false

    private let projectService = ProjectService(syncTracker: NoOpSyncTracker())

    private var filteredProjects: [Project] {
        let showArchived = selectedTab == "archived"
        let filtered = ProjectListCalculations.filterByArchiveState(
            projects: projects, showArchived: showArchived
        )
        let searched = ProjectListCalculations.filterBySearch(
            projects: filtered, query: searchText
        )
        return ProjectListCalculations.sortByName(searched)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollableTabBar(
                selectedId: $selectedTab,
                items: [
                    TabBarItem(id: "active", label: "Active"),
                    TabBarItem(id: "archived", label: "Archived"),
                ]
            )

            if filteredProjects.isEmpty {
                ContentUnavailableView(
                    selectedTab == "archived"
                        ? "No Archived Projects"
                        : "No Active Projects",
                    systemImage: "house",
                    description: Text(
                        selectedTab == "archived"
                            ? "No archived projects yet."
                            : "No active projects yet."
                    )
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.cardListGap) {
                        ForEach(filteredProjects) { project in
                            NavigationLink(value: project) {
                                ProjectCard(
                                    project: project,
                                    budgetPreview: budgetPreviewFor(project)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.vertical, Spacing.md)
                }
            }
        }
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    // Info button — future: show tooltip
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showNewProject = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
        }
        .sheet(isPresented: $showNewProject) {
            NewProjectView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task(id: accountContext.currentAccountId) {
            startListening()
        }
        .onDisappear {
            stopListening()
        }
    }

    // MARK: - Data

    private func startListening() {
        stopListening()
        guard let accountId = accountContext.currentAccountId else { return }
        listener = projectService.subscribeToProjects(accountId: accountId) { newProjects in
            Task { @MainActor in
                self.projects = newProjects
            }
        }
    }

    private func stopListening() {
        listener?.remove()
        listener = nil
    }

    /// Builds budget preview categories from the project's denormalized budgetSummary.
    /// Shows up to 2 categories ordered by: pinned first, then highest spend percentage.
    /// Pinning is not available in the list (requires per-project subscription), so pinned IDs are empty.
    private func budgetPreviewFor(_ project: Project) -> [BudgetProgress.CategoryProgress] {
        guard let summary = project.budgetSummary,
              let categories = summary.categories else { return [] }

        let allProgress: [BudgetProgress.CategoryProgress] = categories.compactMap { catId, catData in
            guard catData.isArchived != true else { return nil }
            return BudgetProgress.CategoryProgress(
                id: catId,
                name: catData.name ?? "",
                budgetCents: catData.budgetCents ?? 0,
                spentCents: catData.spentCents ?? 0,
                categoryType: BudgetCategoryType(rawValue: catData.categoryType ?? "") ?? .general,
                excludeFromOverallBudget: catData.excludeFromOverallBudget ?? false
            )
        }

        return Array(ProjectListCalculations.budgetBarCategories(
            categories: allProgress,
            pinnedCategoryIds: []
        ).prefix(2))
    }
}
