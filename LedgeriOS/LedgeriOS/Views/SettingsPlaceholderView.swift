import SwiftUI

struct SettingsPlaceholderView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AccountContext.self) private var accountContext

    var body: some View {
        List {
            Section("Account") {
                if let account = accountContext.account {
                    LabeledContent("Name", value: account.name)
                }
                if let member = accountContext.member {
                    LabeledContent("Role", value: member.role?.rawValue.capitalized ?? "—")
                    if let email = member.email {
                        LabeledContent("Email", value: email)
                    }
                }
            }

            Section {
                Button("Switch Account") {
                    accountContext.deactivate()
                }
            }

            Section("Debug") {
                NavigationLink("Firestore Test") {
                    FirestoreTestView()
                }
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    authManager.signOut()
                }
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsPlaceholderView()
            .environment(AuthManager())
            .environment(AccountContext(
                accountsService: AccountsService(syncTracker: NoOpSyncTracker()),
                membersService: AccountMembersService(syncTracker: NoOpSyncTracker())
            ))
    }
}
