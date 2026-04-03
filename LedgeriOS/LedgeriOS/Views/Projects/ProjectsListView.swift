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
    @Environment(FindStateManager.self) private var findState
    @Environment(InventoryContext.self) private var inventoryContext

    private let projectService = ProjectService()
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
            Picker("Projects", selection: $selectedTab) {
                Text("Active").tag("active")
                Text("Archived").tag("archived")
            }
            .pickerStyle(.segmented)
            #if os(macOS)
            .labelsHidden()
            #endif
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.sm)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: Spacing.cardListGap) {
                        if selectedTab == "active" {
                            NavigationLink(value: AppDestination.inventory) {
                                InventoryPinnedCard()
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, Spacing.screenPadding)
                        }

                        if filteredProjects.isEmpty {
                            ContentUnavailableView(
                                selectedTab == "archived"
                                    ? "No Archived Projects"
                                    : "No Projects Yet",
                                systemImage: "house",
                                description: Text(
                                    selectedTab == "archived"
                                        ? "No archived projects yet."
                                        : "Create a project to get started."
                                )
                            )
                        } else {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: Dimensions.cardMinWidth), spacing: Spacing.cardListGap)],
                                alignment: .leading,
                                spacing: Spacing.cardListGap
                            ) {
                                ForEach(filteredProjects) { project in
                                    NavigationLink(value: project) {
                                        ProjectCard(
                                            project: project,
                                            budgetPreview: budgetPreviewFor(project)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .id(project.id ?? "")
                                }
                            }
                            .padding(.horizontal, Spacing.screenPadding)
                        }
                    }
                    .padding(.top, Spacing.md)
                    .padding(.bottom, Spacing.md)
                }
                .scrollContentTopFade()
                .onChange(of: findState.currentMatchID) { _, matchID in
                    if let matchID {
                        withAnimation { proxy.scrollTo(matchID, anchor: .center) }
                    }
                }
                .onChange(of: findState.debouncedQuery) { _, _ in
                    registerProjectFindMatches()
                }
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
        }
        .adaptivePresentation(isPresented: $showNewProject, style: .form) {
            NewProjectView()
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
        .universalAddButton()
        .background(BrandColors.background)
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
    /// Fallback chain: (1) pinned categories, (2) Furnishings only, (3) Overall Budget.
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

        // No categories with activity → show Overall Budget
        if sorted.isEmpty {
            let totalBudget = summary.totalBudgetCents ?? 0
            let totalSpent = summary.spentCents ?? 0
            guard totalBudget > 0 || totalSpent != 0 else { return [] }
            return [BudgetProgress.CategoryProgress(
                id: "overall",
                name: "Overall Budget",
                budgetCents: totalBudget,
                spentCents: totalSpent,
                categoryType: .general,
                excludeFromOverallBudget: false
            )]
        }

        // Has pinned categories → show only those (plus overall if pinned)
        if !pinnedIds.isEmpty {
            var result = sorted.filter { pinnedIds.contains($0.id) }
            if pinnedIds.contains("overall") {
                let included = allProgress.filter { !$0.excludeFromOverallBudget }
                let totalBudget = included.reduce(0) { $0 + $1.budgetCents }
                let totalSpent = included.reduce(0) { $0 + $1.spentCents }
                if totalBudget > 0 || totalSpent != 0 {
                    result.append(BudgetProgress.CategoryProgress(
                        id: "overall",
                        name: "Overall Budget",
                        budgetCents: totalBudget,
                        spentCents: totalSpent,
                        categoryType: .general,
                        excludeFromOverallBudget: false
                    ))
                }
            }
            return result
        }

        // Nothing pinned → fall back to Furnishings only
        if let furnishings = sorted.first(where: { $0.name.localizedCaseInsensitiveCompare("Furnishings") == .orderedSame }) {
            return [furnishings]
        }

        // No Furnishings category → fall back to Overall Budget
        let totalBudget = summary.totalBudgetCents ?? 0
        let totalSpent = summary.spentCents ?? 0
        guard totalBudget > 0 || totalSpent != 0 else { return [] }
        return [BudgetProgress.CategoryProgress(
            id: "overall",
            name: "Overall Budget",
            budgetCents: totalBudget,
            spentCents: totalSpent,
            categoryType: .general,
            excludeFromOverallBudget: false
        )]
    }

    private func registerProjectFindMatches() {
        let query = findState.debouncedQuery
        guard !query.isEmpty else {
            findState.registerMatches([], source: "projects")
            return
        }
        let entities: [(id: String, texts: [String])] = filteredProjects.compactMap { project -> (id: String, texts: [String])? in
            guard let id = project.id else { return nil }
            return (id: id, texts: [project.name, project.clientName])
        }
        let matches = FindMatchCalculations.computeMatches(query: query, entities: entities)
        findState.registerMatches(matches, source: "projects")
    }
}
