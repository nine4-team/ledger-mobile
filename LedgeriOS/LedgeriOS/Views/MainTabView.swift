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
            accountsService: AccountsService(syncTracker: NoOpSyncTracker()),
            membersService: AccountMembersService(syncTracker: NoOpSyncTracker())
        ))
}
