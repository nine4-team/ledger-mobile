import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AccountContext.self) private var accountContext

    var body: some View {
        Group {
            if !authManager.isAuthenticated {
                AuthView()
            } else if accountContext.currentAccountId == nil {
                AccountGateView()
            } else {
                MainTabView()
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
