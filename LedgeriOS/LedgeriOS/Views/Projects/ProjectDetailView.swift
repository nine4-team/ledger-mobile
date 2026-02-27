import SwiftUI

struct ProjectDetailView: View {
    let project: Project
    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager
    @Environment(ProjectContext.self) private var projectContext
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = "budget"
    @State private var showingMenu = false
    @State private var menuPendingAction: (() -> Void)?
    @State private var showingDeleteConfirmation = false

    private let projectService = ProjectService(syncTracker: NoOpSyncTracker())

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
        .sheet(isPresented: $showingMenu, onDismiss: {
            menuPendingAction?()
            menuPendingAction = nil
        }) {
            ActionMenuSheet(
                title: "Project Options",
                items: [
                    ActionMenuItem(id: "edit", label: "Edit Project", icon: "pencil"),
                    ActionMenuItem(
                        id: "export", label: "Export Transactions", icon: "square.and.arrow.up",
                        onPress: { exportTransactionsCSV() }
                    ),
                    ActionMenuItem(
                        id: "delete", label: "Delete Project", icon: "trash",
                        isDestructive: true,
                        onPress: { showingDeleteConfirmation = true }
                    ),
                ],
                onSelectAction: { action in
                    menuPendingAction = action
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Delete Project?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteProject()
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .task(id: project.id) {
            guard let accountId = accountContext.currentAccountId,
                  let projectId = project.id else { return }
            projectContext.activate(
                accountId: accountId,
                projectId: projectId,
                userId: authManager.currentUser?.uid
            )
        }
        .onDisappear {
            projectContext.deactivate()
        }
    }

    // MARK: - Actions

    private func deleteProject() {
        guard let accountId = accountContext.currentAccountId,
              let projectId = project.id else { return }
        Task {
            try? await projectService.deleteProject(accountId: accountId, projectId: projectId)
            dismiss()
        }
    }

    private func exportTransactionsCSV() {
        let csv = TransactionExportCalculations.exportTransactionsCSV(
            transactions: projectContext.transactions,
            categories: projectContext.budgetCategories,
            items: projectContext.items
        )

        let fileName = "transactions-\(project.id ?? "export").csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)
        } catch {
            return
        }

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = scene.windows.first?.rootViewController else { return }

        let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        rootVC.present(activityVC, animated: true)
    }
}
