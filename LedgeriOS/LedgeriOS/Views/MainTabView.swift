import SwiftUI

struct MainTabView: View {
    @SceneStorage("selectedTab") private var selectedTab = Tab.projects.rawValue

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ProjectsListView()
                    .navigationDestination(for: Project.self) { project in
                        ProjectDetailView(project: project)
                    }
            }
            .tabItem {
                Label("Projects", systemImage: "house")
            }
            .tag(Tab.projects.rawValue)

            NavigationStack {
                InventoryPlaceholderView()
            }
            .tabItem {
                Label("Inventory", systemImage: "shippingbox")
            }
            .tag(Tab.inventory.rawValue)

            NavigationStack {
                SearchPlaceholderView()
            }
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }
            .tag(Tab.search.rawValue)

            NavigationStack {
                SettingsPlaceholderView()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(Tab.settings.rawValue)
        }
        .tint(BrandColors.primary)
    }
}

// MARK: - Tab Enum

extension MainTabView {
    enum Tab: String {
        case projects
        case inventory
        case search
        case settings
    }
}

#Preview {
    MainTabView()
        .environment(AuthManager())
        .environment(AccountContext(
            accountsService: AccountsService(syncTracker: NoOpSyncTracker()),
            membersService: AccountMembersService(syncTracker: NoOpSyncTracker())
        ))
}
