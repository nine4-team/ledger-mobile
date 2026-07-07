import SwiftUI

// MARK: - App Section

enum AppSection: String, CaseIterable {
    case projects
    case review
    case search
    case settings
}

// MARK: - Main Tab View

struct MainTabView: View {
    @SceneStorage("selectedTab") private var selectedTab: AppSection = .projects
    @Environment(FindStateManager.self) private var findState
    @Environment(AccountContext.self) private var accountContext
    @Environment(InventoryContext.self) private var inventoryContext

    var body: some View {
        #if os(macOS)
        macOSBody
        #else
        iOSBody
        #endif
    }

    // MARK: - macOS (NavigationSplitView)

    /// On macOS, `.tabViewStyle(.sidebarAdaptable)` creates an implicit column
    /// layout that intercepts NavigationLink before the inner NavigationStack
    /// can handle it. Using an explicit NavigationSplitView gives us proper
    /// NavigationStack behavior in the detail column.
    #if os(macOS)
    private var macOSBody: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Label("Projects", systemImage: "folder").tag(AppSection.projects)
                Label("Review", systemImage: "checklist").tag(AppSection.review)
                Label("Search", systemImage: "magnifyingglass").tag(AppSection.search)
                Label("Settings", systemImage: "gear").tag(AppSection.settings)
            }
            .navigationTitle("")
        } detail: {
            NavigationStack {
                switch selectedTab {
                case .projects:
                    ProjectsListView()
                        .navigationDestination(for: ProjectRoute.self) { route in
                            ProjectDetailContainer(
                                projectId: route.id,
                                initialProject: NavigationRouteResolution.project(
                                    id: route.id, in: accountContext.allProjects
                                )
                            )
                        }
                        .navigationDestination(for: AppDestination.self) { dest in
                            switch dest {
                            case .inventory: InventoryView()
                            }
                        }
                case .review:
                    ReviewView()
                case .search:
                    UniversalSearchView()
                        .navigationDestination(for: Item.self) { item in
                            ItemDetailView(item: item)
                        }
                        .navigationDestination(for: Transaction.self) { transaction in
                            TransactionDetailView(transaction: transaction)
                        }
                        .navigationDestination(for: Space.self) { space in
                            SpaceSearchDetailView(space: space)
                        }
                case .settings:
                    SettingsView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    AccountToolbarMenu()
                }
            }
        }
        .tint(BrandColors.primary)
        .overlay(alignment: findOverlayAlignment) {
            if findState.isActive {
                FindOverlayBar()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: findState.isActive)
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
            selectedTab = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            selectedTab = .search
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleFindOverlay)) { _ in
            findState.toggle()
        }
        .onChange(of: selectedTab) { _, _ in
            findState.deactivate()
        }
        .task(id: accountContext.currentAccountId) {
            // Keep InventoryContext live for the whole signed-in session so
            // inventory counts on the Projects screen are accurate immediately,
            // not just after the user visits the Inventory tab.
            guard let accountId = accountContext.currentAccountId else {
                inventoryContext.deactivate()
                return
            }
            inventoryContext.activate(accountId: accountId)
        }
    }
    #endif

    // MARK: - iOS (TabView)

    private var iOSBody: some View {
        TabView(selection: $selectedTab) {
            Tab("Projects", systemImage: "folder", value: .projects) {
                NavigationStack {
                    ProjectsListView()
                        .navigationDestination(for: ProjectRoute.self) { route in
                            ProjectDetailContainer(
                                projectId: route.id,
                                initialProject: NavigationRouteResolution.project(
                                    id: route.id, in: accountContext.allProjects
                                )
                            )
                        }
                        .navigationDestination(for: AppDestination.self) { dest in
                            switch dest {
                            case .inventory: InventoryView()
                            }
                        }
                }
            }

            Tab("Review", systemImage: "checklist", value: .review) {
                NavigationStack {
                    ReviewView()
                }
            }

            Tab("Search", systemImage: "magnifyingglass", value: .search) {
                NavigationStack {
                    UniversalSearchView()
                        .navigationDestination(for: Item.self) { item in
                            ItemDetailView(item: item)
                        }
                        .navigationDestination(for: Transaction.self) { transaction in
                            TransactionDetailView(transaction: transaction)
                        }
                        .navigationDestination(for: Space.self) { space in
                            SpaceSearchDetailView(space: space)
                        }
                }
            }

            Tab("Settings", systemImage: "gear", value: .settings) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(BrandColors.primary)
        .overlay(alignment: findOverlayAlignment) {
            if findState.isActive {
                FindOverlayBar()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: findState.isActive)
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
            selectedTab = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            selectedTab = .search
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleFindOverlay)) { _ in
            findState.toggle()
        }
        .onChange(of: selectedTab) { _, _ in
            findState.deactivate()
        }
        .task(id: accountContext.currentAccountId) {
            // Keep InventoryContext live for the whole signed-in session so
            // inventory counts on the Projects screen are accurate immediately,
            // not just after the user visits the Inventory tab.
            guard let accountId = accountContext.currentAccountId else {
                inventoryContext.deactivate()
                return
            }
            inventoryContext.activate(accountId: accountId)
        }
    }
    private var findOverlayAlignment: Alignment {
        #if os(macOS)
        .topTrailing
        #else
        .top
        #endif
    }
}

#Preview {
    MainTabView()
        .environment(AuthManager())
        .environment(AccountContext(
            accountsService: AccountsService(),
            membersService: AccountMembersService()
        ))
        .environment(FindStateManager())
}
