import SwiftUI
import FirebaseAuth

struct RootView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AccountContext.self) private var accountContext
    @Environment(ProjectContext.self) private var projectContext
    @Environment(InventoryContext.self) private var inventoryContext
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(MediaUploadQueue.self) private var mediaUploadQueue
    @Environment(InviteLinkRouter.self) private var inviteLinkRouter

    @State private var inviteErrorMessage: String?
    @State private var isShowingFailedUploads = false

    var body: some View {
        Group {
            if inviteLinkRouter.pendingToken != nil {
                InviteSignupView()
                    #if os(macOS)
                    .frame(minWidth: 400, minHeight: 500)
                    #endif
            } else if !authManager.isAuthenticated {
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
                            if !networkMonitor.isConnected {
                                StatusBanner(
                                    message: "No internet connection. Viewing cached data.",
                                    variant: .warning
                                )
                            }
                            if mediaUploadQueue.failedCount > 0 {
                                StatusBanner(
                                    message: "\(mediaUploadQueue.failedCount) upload\(mediaUploadQueue.failedCount == 1 ? "" : "s") failed. Review to retry or remove.",
                                    variant: .error,
                                    actions: {
                                        Button("Review") { isShowingFailedUploads = true }
                                    }
                                )
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
        .alert("Invite Error", isPresented: .init(
            get: { inviteErrorMessage != nil },
            set: { if !$0 { inviteErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(inviteErrorMessage ?? "")
        }
        .sheet(isPresented: $isShowingFailedUploads) {
            FailedUploadsView()
                .environment(mediaUploadQueue)
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
}

private struct FailedUploadsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MediaUploadQueue.self) private var uploadQueue

    var body: some View {
        NavigationStack {
            Group {
                if uploadQueue.failedUploads.isEmpty {
                    ContentUnavailableView(
                        "No Failed Uploads",
                        systemImage: "checkmark.circle",
                        description: Text("The failed upload queue is clear.")
                    )
                } else {
                    List(uploadQueue.failedUploads) { upload in
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text(upload.fileName ?? "Attachment")
                                .font(Typography.h3)

                            Text("\(displayName(for: upload.entityType)) • \(upload.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(Typography.small)
                                .foregroundStyle(BrandColors.textSecondary)

                            if let error = upload.lastError, !error.isEmpty {
                                Text(error)
                                    .font(Typography.small)
                                    .foregroundStyle(StatusColors.missedText)
                            }

                            HStack(spacing: Spacing.md) {
                                Button("Retry") {
                                    uploadQueue.retryFailedUpload(id: upload.id)
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Remove", role: .destructive) {
                                    uploadQueue.removeFailedUpload(id: upload.id)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, Spacing.xs)
                    }
                }
            }
            .navigationTitle("Failed Uploads")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 320)
        #endif
    }

    private func displayName(for entityType: String) -> String {
        switch entityType {
        case "protoItems": "Item needing assignment"
        case "items": "Item"
        case "projects": "Project"
        case "spaces": "Space"
        case "transactions": "Transaction"
        default: entityType
        }
    }
}

private struct InviteSignupView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AccountContext.self) private var accountContext
    @Environment(InviteLinkRouter.self) private var inviteLinkRouter

    @State private var invite: InvitePreviewResult?
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var isSubmitting = false

    private var passwordsMatch: Bool {
        !confirmPassword.isEmpty && password == confirmPassword
    }

    private var canSubmit: Bool {
        invite != nil && !password.isEmpty && passwordsMatch && !isLoading && !isSubmitting
    }

    var body: some View {
        AdaptiveContentWidth(maxWidth: Dimensions.formMaxWidth) {
            VStack(spacing: Spacing.xl) {
                Spacer()

                VStack(spacing: Spacing.sm) {
                    Text("Ledger")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(BrandColors.primary)

                    Text("Create your password")
                        .font(Typography.h2)
                        .foregroundStyle(BrandColors.textPrimary)
                }

                if isLoading {
                    ProgressView()
                } else {
                    formContent
                }

                Spacer()
            }
            .padding(.horizontal, Spacing.xxl)
        }
        .task(id: inviteLinkRouter.pendingToken) {
            await loadInvite()
        }
    }

    @ViewBuilder
    private var formContent: some View {
        if let invite {
            VStack(spacing: Spacing.md) {
                TextField("Email", text: .constant(invite.email))
                    .textContentType(.emailAddress)
                    .disabled(true)
                    .padding()
                    .background(Color.secondarySystemBackground)
                    .cornerRadius(Dimensions.inputRadius)

                SecureField("Password", text: $password)
                    .textContentType(.newPassword)
                    .padding()
                    .background(Color.secondarySystemBackground)
                    .cornerRadius(Dimensions.inputRadius)

                SecureField("Confirm Password", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .padding()
                    .background(Color.secondarySystemBackground)
                    .cornerRadius(Dimensions.inputRadius)

                if !confirmPassword.isEmpty && !passwordsMatch {
                    Text("Passwords do not match")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    createPasswordAndAcceptInvite()
                } label: {
                    Group {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Create Password")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(BrandColors.primary)
                    .foregroundStyle(.white)
                    .cornerRadius(Dimensions.buttonRadius)
                }
                .disabled(!canSubmit)
            }
        } else {
            VStack(spacing: Spacing.md) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(Typography.body)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button("Back to Sign In") {
                    inviteLinkRouter.clear()
                }
                .font(Typography.button)
            }
        }
    }

    private func loadInvite() async {
        guard !AppRuntime.isUnitTestHost else { return }
        guard let token = inviteLinkRouter.pendingToken else { return }

        isLoading = true
        errorMessage = nil
        invite = nil
        defer { isLoading = false }

        do {
            invite = try await InviteAcceptanceService().previewInvite(token: token)
        } catch let error as InviteAcceptanceError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = "Could not load this invite."
        }
    }

    private func createPasswordAndAcceptInvite() {
        guard passwordsMatch else {
            errorMessage = "Passwords do not match"
            return
        }
        guard let token = inviteLinkRouter.pendingToken, let invite else { return }

        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                try await authManager.signUp(email: invite.email, password: password)
                let result = try await InviteAcceptanceService().acceptInvite(token: token)
                guard let uid = authManager.currentUser?.uid else {
                    throw InviteAcceptanceError.unauthenticated
                }

                inviteLinkRouter.clear()
                await accountContext.discoverAccounts(userId: uid)
                accountContext.selectAccount(accountId: result.accountId, userId: uid)
            } catch let error as InviteAcceptanceError {
                errorMessage = error.userMessage
            } catch {
                errorMessage = friendlyAuthError(error)
            }
            isSubmitting = false
        }
    }

    private func friendlyAuthError(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == AuthErrorDomain,
           nsError.code == AuthErrorCode.emailAlreadyInUse.rawValue {
            return "An account already exists for this email."
        }
        return error.localizedDescription
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
