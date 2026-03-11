import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AccountContext.self) private var accountContext
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(MediaUploadQueue.self) private var mediaUploadQueue

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
        .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
            if !isAuthenticated {
                accountContext.deactivate()
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AuthManager())
        .environment(AccountContext(
            accountsService: AccountsService(),
            membersService: AccountMembersService()
        ))
        .environment(NetworkMonitor())
        .environment(MediaUploadQueue(mediaService: MediaService()))
}
