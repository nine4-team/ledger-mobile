import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AccountContext.self) private var accountContext

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
}
