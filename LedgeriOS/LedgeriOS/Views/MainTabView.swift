import SwiftUI

// MARK: - App Section

enum AppSection: String, CaseIterable {
    case projects
    case inventory
    case search
    case settings
}

// MARK: - Main Tab View

struct MainTabView: View {
    @SceneStorage("selectedTab") private var selectedTab: AppSection = .projects

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
                Label("Inventory", systemImage: "archivebox").tag(AppSection.inventory)
                Label("Search", systemImage: "magnifyingglass").tag(AppSection.search)
                Label("Settings", systemImage: "gear").tag(AppSection.settings)
            }
            .navigationTitle("")
        } detail: {
            NavigationStack {
                switch selectedTab {
                case .projects:
                    ProjectsListView()
                        .navigationDestination(for: Project.self) { project in
                            ProjectDetailView(project: project)
                        }
                case .inventory:
                    InventoryView()
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
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
            selectedTab = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            selectedTab = .search
        }
    }
    #endif

    // MARK: - iOS (TabView)

    private var iOSBody: some View {
        TabView(selection: $selectedTab) {
            Tab("Projects", systemImage: "folder", value: .projects) {
                NavigationStack {
                    ProjectsListView()
                        .navigationDestination(for: Project.self) { project in
                            ProjectDetailView(project: project)
                        }
                }
            }

            Tab("Inventory", systemImage: "archivebox", value: .inventory) {
                NavigationStack {
                    InventoryView()
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
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
            selectedTab = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            selectedTab = .search
        }
    }
}

#Preview {
    MainTabView()
        .environment(AuthManager())
        .environment(AccountContext(
            accountsService: AccountsService(),
            membersService: AccountMembersService()
        ))
}
