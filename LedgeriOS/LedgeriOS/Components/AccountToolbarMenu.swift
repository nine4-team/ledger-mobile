#if os(macOS)
import SwiftUI

struct AccountToolbarMenu: View {
    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        Menu {
            if accountContext.discoveredAccounts.isEmpty {
                Text("Loading...")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(accountContext.discoveredAccounts) { account in
                    Button {
                        guard let userId = authManager.currentUser?.uid else { return }
                        accountContext.selectAccount(accountId: account.id, userId: userId)
                    } label: {
                        HStack {
                            Text(account.name)
                            if account.id == accountContext.currentAccountId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            Label(
                accountContext.account?.name ?? "Account",
                systemImage: "person.crop.circle"
            )
        }
    }
}
#endif
