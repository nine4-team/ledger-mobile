import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AccountContext.self) private var accountContext
    @Environment(ProjectContext.self) private var projectContext
    @Environment(InventoryContext.self) private var inventoryContext
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(MediaUploadQueue.self) private var mediaUploadQueue
    @Environment(InviteLinkRouter.self) private var inviteLinkRouter

    @State private var isAcceptingInvite = false
    @State private var inviteErrorMessage: String?

    private var inviteTaskId: String {
        "\(authManager.currentUser?.uid ?? "signed-out"):\(inviteLinkRouter.pendingToken ?? "none")"
    }

    var body: some View {
        Group {
            if !authManager.isAuthenticated {
                AuthView()
                    #if os(macOS)
                    .frame(minWidth: 400, minHeight: 500)
                    #endif
            } else if accountContext.currentAccountId == nil {
                AccountGateView()
                    #if os(macOS)
                    .frame(minWidth: 400, minHeight: 500)
                    #endif
            } else {
                MainTabView()
                    #if os(macOS)
                    .frame(minWidth: 800, minHeight: 600)
                    #endif
                    // H6: Show offline banner when connectivity is lost
                    // Show upload status when images are pending/failed
                    .safeAreaInset(edge: .top) {
                        VStack(spacing: Spacing.xs) {
                            if isAcceptingInvite {
                                StatusBanner(
                                    message: "Joining account...",
                                    variant: .info
                                )
                            }
                            if !networkMonitor.isConnected {
                                StatusBanner(
                                    message: "No internet connection. Viewing cached data.",
                                    variant: .warning
                                )
                            }
                            if mediaUploadQueue.failedCount > 0 {
                                StatusBanner(
                                    message: "\(mediaUploadQueue.failedCount) upload\(mediaUploadQueue.failedCount == 1 ? "" : "s") failed",
                                    variant: .error
                                )
                                .onTapGesture { mediaUploadQueue.retryFailed() }
                            } else if mediaUploadQueue.isProcessing, mediaUploadQueue.pendingCount > 0 {
                                StatusBanner(
                                    message: "Uploading \(mediaUploadQueue.pendingCount) image\(mediaUploadQueue.pendingCount == 1 ? "" : "s")…",
                                    variant: .info
                                )
                            }
                        }
                        .padding(.horizontal, Spacing.screenPadding)
                        .padding(.top, Spacing.xs)
                        .animation(.easeInOut(duration: 0.25), value: networkMonitor.isConnected)
                        .animation(.easeInOut(duration: 0.25), value: mediaUploadQueue.pendingCount)
                        .animation(.easeInOut(duration: 0.25), value: mediaUploadQueue.failedCount)
                    }
            }
        }
        .animation(.default, value: authManager.isAuthenticated)
        .animation(.default, value: accountContext.currentAccountId)
        .task(id: inviteTaskId) {
            await acceptPendingInviteIfPossible()
        }
        .alert("Invite Error", isPresented: .init(
            get: { inviteErrorMessage != nil },
            set: { if !$0 { inviteErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(inviteErrorMessage ?? "")
        }
        .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
            if !isAuthenticated {
                accountContext.deactivate()
                projectContext.deactivate()
                inventoryContext.deactivate()
            }
        }
        .onChange(of: accountContext.currentAccountId) { oldAccountId, newAccountId in
            if oldAccountId != nil, oldAccountId != newAccountId {
                projectContext.deactivate()
                inventoryContext.deactivate()
            }
        }
    }

    private func acceptPendingInviteIfPossible() async {
        guard !AppRuntime.isUnitTestHost else { return }

        guard !isAcceptingInvite,
              let token = inviteLinkRouter.pendingToken,
              let uid = authManager.currentUser?.uid else {
            return
        }

        isAcceptingInvite = true
        defer { isAcceptingInvite = false }

        do {
            let result = try await InviteAcceptanceService().acceptInvite(token: token)
            inviteLinkRouter.clear()
            await accountContext.discoverAccounts(userId: uid)
            accountContext.selectAccount(accountId: result.accountId, userId: uid)
        } catch {
            inviteErrorMessage = "Could not accept this invite. It may be expired, revoked, or already used."
        }
    }
}

#Preview {
    let projectService = ProjectService()
    let transactionsService = TransactionsService()
    let itemsService = ItemsService()
    let spacesService = SpacesService()
    let budgetCategoriesService = BudgetCategoriesService()
    let projectBudgetCategoriesService = ProjectBudgetCategoriesService()

    RootView()
        .environment(AuthManager())
        .environment(AccountContext(
            accountsService: AccountsService(),
            membersService: AccountMembersService(),
            itemsService: itemsService,
            transactionsService: transactionsService,
            spacesService: spacesService,
            budgetCategoriesService: budgetCategoriesService,
            projectService: projectService,
            invoicesService: InvoiceService()
        ))
        .environment(ProjectContext(
            projectService: projectService,
            transactionsService: transactionsService,
            itemsService: itemsService,
            spacesService: spacesService,
            budgetCategoriesService: budgetCategoriesService,
            projectBudgetCategoriesService: projectBudgetCategoriesService
        ))
        .environment(InventoryContext(
            itemsService: itemsService,
            transactionsService: transactionsService,
            spacesService: spacesService
        ))
        .environment(NetworkMonitor())
        .environment(MediaUploadQueue(mediaService: MediaService()))
        .environment(InviteLinkRouter())
}
