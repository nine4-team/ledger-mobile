import SwiftUI
import FirebaseFirestore

struct ProjectsListView: View {
    @Environment(AccountContext.self) private var accountContext
    @State private var selectedTab = "active"
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var projects: [Project] = []
    @State private var listener: ListenerRegistration?

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
        .searchable(text: $searchText, isPresented: $isSearching, prompt: "Search projects")
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
                    isSearching = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
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

    /// Build a simplified budget preview from the project's denormalized budgetSummary.
    /// Full per-category progress requires activating ProjectContext (done in detail view).
    private func budgetPreviewFor(_ project: Project) -> [BudgetProgress.CategoryProgress] {
        // The denormalized budgetSummary doesn't have per-category spend data,
        // so we can't show meaningful progress bars in the list.
        // For now, return empty — the detail view shows the real budget breakdown.
        return []
    }
}
