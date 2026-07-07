import SwiftUI

struct ProjectDetailView: View {
    let project: Project
    @Environment(AccountContext.self) private var accountContext
    @Environment(ProjectContext.self) private var projectContext
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = "items"
    @State private var showingMenu = false
    @State private var menuPendingAction: (() -> Void)?
    @State private var showingDeleteConfirmation = false
    @State private var showingArchiveConfirmation = false
    @State private var showingEditProject = false
    @State private var showExportSheet = false
    @State private var showExportSheetAllTransactions = false
    @State private var exportedFileURL: URL?
    @State private var errorMessage: String?
    @State private var showQuickNote = false

    var body: some View {
        VStack(spacing: 0) {
            PinnedBudgetsSection()
                .frame(maxWidth: Dimensions.contentMaxWidth)
                .frame(maxWidth: .infinity)
            ScrollableTabBar(selectedId: $selectedTab, items: [
                TabBarItem(id: "items", label: "Items"),
                TabBarItem(id: "transactions", label: "Transactions"),
                TabBarItem(id: "spaces", label: "Spaces"),
                TabBarItem(id: "notes", label: "Notes"),
                TabBarItem(id: "finances", label: "Finances"),
            ])
            .frame(maxWidth: Dimensions.contentMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.sm)

            Group {
                switch selectedTab {
                case "items":
                    ItemsTabView()
                case "transactions":
                    TransactionsTabView(showExportSheet: $showExportSheet)
                case "spaces":
                    SpacesTabView()
                case "notes":
                    NotesTabView()
                case "finances":
                    FinancesTabView()
                        .navigationDestination(for: Invoice.self) { invoice in
                            InvoiceDetailView(invoice: invoice)
                        }
                default:
                    ItemsTabView()
                }
            }
        }
        .navigationDestination(for: ItemRoute.self) { route in
            ItemDetailView(
                itemId: route.id,
                projectId: route.projectId,
                initialItem: projectContext.items.first { $0.id == route.id }
            )
        }
        // TODO(stable-id-navigation): FinancesTabView still pushes `Item` values.
        // Remove this destination once the finance/invoice routes are migrated in
        // a follow-up milestone.
        .navigationDestination(for: Item.self) { item in
            ItemDetailView(item: item)
        }
        .navigationDestination(for: Transaction.self) { transaction in
            TransactionDetailView(transaction: transaction)
        }
        .navigationDestination(for: Space.self) { space in
            SpaceDetailView(space: space)
        }
        .navBarTitleDisplayMode(.inline)
        #if os(macOS)
        .navigationTitle(project.name.isEmpty ? "Project" : project.name)
        .navigationSubtitle(project.clientName)
        #endif
        .toolbar {
            #if canImport(UIKit)
            ToolbarItem(placement: .principal) {
                VStack(spacing: Spacing.xs) {
                    Text(project.name.isEmpty ? "Project" : project.name)
                        .font(Typography.h3)
                        .foregroundStyle(BrandColors.textPrimary)
                    Text(project.clientName.isEmpty ? "" : project.clientName)
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
            #endif
            ToolbarItem(placement: .trailingNavBar) {
                Button {
                    showQuickNote = true
                } label: {
                    Image(systemName: "note.text")
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
            ToolbarItem(placement: .trailingNavBar) {
                Button {
                    showingMenu = true
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
        }
        .adaptivePresentation(isPresented: $showingMenu, style: .quickMenu, onDismiss: {
            menuPendingAction?()
            menuPendingAction = nil
        }) {
            ActionMenuSheet(
                title: "Project Options",
                items: [
                    ActionMenuItem(id: "edit", label: "Edit Project", icon: "pencil", onPress: {
                        showingEditProject = true
                    }),
                    ActionMenuItem(
                        id: "export", label: "Export Transactions", icon: "square.and.arrow.up",
                        onPress: {
                            if selectedTab == "transactions" {
                                showExportSheet = true
                            } else {
                                showExportSheetAllTransactions = true
                            }
                        }
                    ),
                    // H2: Archive is preferred over deletion — keeps data intact
                    ActionMenuItem(
                        id: "archive",
                        label: project.isArchived == true ? "Unarchive Project" : "Archive Project",
                        icon: project.isArchived == true ? "arrow.uturn.up.circle" : "archivebox",
                        onPress: { showingArchiveConfirmation = true }
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
        }
        .adaptivePresentation(isPresented: $showQuickNote, style: .form) {
            QuickNoteModal()
        }
        .adaptivePresentation(isPresented: $showingEditProject, style: .form) {
            EditProjectModal(
                project: project,
                existingBudgetCategories: projectContext.projectBudgetCategories
            )
        }
        .adaptivePresentation(isPresented: $showExportSheetAllTransactions, style: .selectionMenu, onDismiss: {
            if let url = exportedFileURL {
                exportedFileURL = nil
                ShareHelper.share(url: url)
            }
        }) {
            ExportTransactionsModal(
                transactions: projectContext.transactions,
                categories: projectContext.budgetCategories,
                items: projectContext.items,
                projectId: projectContext.currentProjectId,
                onExport: { url in exportedFileURL = url }
            )
        }
        .confirmationDialog("Delete Project?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteProject()
            }
        } message: {
            // H22: Warn about orphaned items when project has data
            let itemCount = projectContext.items.count
            if itemCount > 0 {
                Text("This will delete the project and orphan \(itemCount) item\(itemCount == 1 ? "" : "s"). Consider archiving instead to preserve data.")
            } else {
                Text("This action cannot be undone.")
            }
        }
        .confirmationDialog(
            project.isArchived == true ? "Unarchive Project?" : "Archive Project?",
            isPresented: $showingArchiveConfirmation
        ) {
            Button(project.isArchived == true ? "Unarchive" : "Archive") {
                toggleArchive()
            }
        } message: {
            if project.isArchived == true {
                Text("This project will be restored to active status.")
            } else {
                Text("Archived projects are hidden from the main list but all data is preserved.")
            }
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .background(BrandColors.background)
    }

    // MARK: - Actions

    private func deleteProject() {
        guard let accountId = accountContext.currentAccountId,
              let projectId = project.id else { return }
        Task {
            do {
                try await projectContext.deleteProject(accountId: accountId, projectId: projectId)
                dismiss()
            } catch {
                errorMessage = "Failed to delete project. Please try again."
            }
        }
    }

    private func toggleArchive() {
        guard let accountId = accountContext.currentAccountId,
              let projectId = project.id else { return }
        let nextArchived = !(project.isArchived == true)
        Task {
            do {
                try await projectContext.archiveProject(
                    accountId: accountId,
                    projectId: projectId,
                    isArchived: nextArchived
                )
                if nextArchived { dismiss() }
            } catch {
                errorMessage = "Failed to \(nextArchived ? "archive" : "unarchive") project. Please try again."
            }
        }
    }

}
