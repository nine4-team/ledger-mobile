import SwiftUI

struct ProjectDetailView: View {
    let project: Project
    @Environment(AccountContext.self) private var accountContext
    @Environment(ProjectContext.self) private var projectContext
    @State private var selectedTab = "budget"
    @State private var showingMenu = false

    private let tabs = [
        TabBarItem(id: "budget", label: "Budget"),
        TabBarItem(id: "items", label: "Items"),
        TabBarItem(id: "transactions", label: "Transactions"),
        TabBarItem(id: "spaces", label: "Spaces"),
        TabBarItem(id: "accounting", label: "Accounting"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollableTabBar(selectedId: $selectedTab, items: tabs)

            Group {
                switch selectedTab {
                case "budget":
                    BudgetTabView()
                case "items":
                    ItemsTabPlaceholder()
                case "transactions":
                    TransactionsTabPlaceholder()
                case "spaces":
                    SpacesTabPlaceholder()
                case "accounting":
                    AccountingTabPlaceholder()
                default:
                    BudgetTabView()
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(project.name.isEmpty ? "Project" : project.name)
                        .font(Typography.h3)
                        .foregroundStyle(BrandColors.textPrimary)
                    Text(project.clientName.isEmpty ? "" : project.clientName)
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingMenu = true
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
        }
        .confirmationDialog("Project Options", isPresented: $showingMenu) {
            Button("Edit Project") {
                // Future: navigate to edit
            }
            Button("Export Transactions") {
                // Future: CSV export
            }
            Button("Delete Project", role: .destructive) {
                // Future: delete flow
            }
        }
        .task(id: project.id) {
            guard let accountId = accountContext.currentAccountId,
                  let projectId = project.id else { return }
            projectContext.activate(accountId: accountId, projectId: projectId)
        }
        .onDisappear {
            projectContext.deactivate()
        }
    }
}
