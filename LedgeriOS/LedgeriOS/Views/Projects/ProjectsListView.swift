import SwiftUI
import FirebaseFirestore

struct ProjectsListView: View {
    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager
    @State private var selectedTab = "active"
    @State private var projects: [Project] = []
    @State private var listener: ListenerRegistration?
    @State private var preferencesListener: ListenerRegistration?
    @State private var projectPreferences: [String: ProjectPreferences] = [:]
    @State private var showNewProject = false

    private let projectService = ProjectService(syncTracker: NoOpSyncTracker())
    private let preferencesService = ProjectPreferencesService()

    private var filteredProjects: [Project] {
        let showArchived = selectedTab == "archived"
        let filtered = ProjectListCalculations.filterByArchiveState(
            projects: projects, showArchived: showArchived
        )
        return ProjectListCalculations.sortByName(filtered)
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
                    AdaptiveContentWidth {
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
                .scrollContentTopFade()
            }
        }
        .navigationTitle("Projects")
        .navBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .leadingNavBar) {
                Button {
                    // Info button — future: show tooltip
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
            ToolbarItem(placement: .trailingNavBar) {
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
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task(id: accountContext.currentAccountId) {
            startListening()
        }
        .onDisappear {
            stopListening()
        }
        .onReceive(NotificationCenter.default.publisher(for: .createProject)) { _ in
            showNewProject = true
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

        if let userId = authManager.currentUser?.uid {
            preferencesListener = preferencesService.subscribeToAllProjectPreferences(
                accountId: accountId,
                userId: userId
            ) { prefs in
                Task { @MainActor in
                    self.projectPreferences = prefs
                }
            }
        }
    }

    private func stopListening() {
        listener?.remove()
        listener = nil
        preferencesListener?.remove()
        preferencesListener = nil
    }

    /// Builds budget preview categories from the project's denormalized budgetSummary.
    /// Shows up to 2 categories ordered by: pinned first, then highest spend percentage.
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

        let pinnedIds: [String]
        if let projectId = project.id {
            pinnedIds = projectPreferences[projectId]?.pinnedBudgetCategoryIds ?? []
        } else {
            pinnedIds = []
        }

        let sorted = ProjectListCalculations.budgetBarCategories(
            categories: allProgress,
            pinnedCategoryIds: pinnedIds
        )
        if pinnedIds.isEmpty {
            return Array(sorted.prefix(1))
        }
        // Show all pinned categories
        return sorted.filter { pinnedIds.contains($0.id) }
    }
}
