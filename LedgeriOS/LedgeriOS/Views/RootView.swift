import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AccountContext.self) private var accountContext
    @Environment(NetworkMonitor.self) private var networkMonitor

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
                    .safeAreaInset(edge: .top) {
                        if !networkMonitor.isConnected {
                            StatusBanner(
                                message: "No internet connection. Viewing cached data.",
                                variant: .warning
                            )
                            .padding(.horizontal, Spacing.screenPadding)
                            .padding(.top, Spacing.xs)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: networkMonitor.isConnected)
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
            accountsService: AccountsService(syncTracker: NoOpSyncTracker()),
            membersService: AccountMembersService(syncTracker: NoOpSyncTracker())
        ))
        .environment(NetworkMonitor())
}
