import SwiftUI

struct AccountGateView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AccountContext.self) private var accountContext

    var body: some View {
        Group {
            if accountContext.isDiscovering {
                loadingView
            } else if accountContext.discoveredAccounts.isEmpty {
                noAccountsView
            } else {
                accountPickerView
            }
        }
        .task {
            guard let uid = authManager.currentUser?.uid else { return }

            // Fast path: if we have a persisted account, activate immediately
            if let lastId = accountContext.lastSelectedAccountId {
                accountContext.selectAccount(accountId: lastId, userId: uid)
                return
            }

            // Otherwise, discover accounts
            await accountContext.discoverAccounts(userId: uid)

            // Auto-select if exactly one account
            if accountContext.discoveredAccounts.count == 1,
               let only = accountContext.discoveredAccounts.first {
                accountContext.selectAccount(accountId: only.id, userId: uid)
            }
        }
    }

    // MARK: - Sub-views

    private var loadingView: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
            Text("Loading accounts…")
                .font(Typography.body)
                .foregroundStyle(BrandColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrandColors.background)
    }

    private var noAccountsView: some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: "building.2")
                .font(.system(size: 48))
                .foregroundStyle(BrandColors.textTertiary)

            Text("No Accounts Found")
                .font(Typography.h1)
                .foregroundStyle(BrandColors.textPrimary)

            Text("You don't belong to any accounts yet.")
                .font(Typography.body)
                .foregroundStyle(BrandColors.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                // Stub — account creation is a future feature
            } label: {
                Text("Create Account")
                    .font(Typography.button)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(BrandColors.primary, in: RoundedRectangle(cornerRadius: Dimensions.buttonRadius))
            }

            Button("Sign Out", role: .destructive) {
                authManager.signOut()
            }
            .font(Typography.button)
        }
        .padding(.horizontal, Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrandColors.background)
    }

    private var accountPickerView: some View {
        VStack(spacing: Spacing.xl) {
            Text("Select Account")
                .font(Typography.h1)
                .foregroundStyle(BrandColors.textPrimary)
                .padding(.top, Spacing.xxxl)

            LazyVStack(spacing: Spacing.cardListGap) {
                ForEach(accountContext.discoveredAccounts) { account in
                    Button {
                        guard let uid = authManager.currentUser?.uid else { return }
                        accountContext.selectAccount(accountId: account.id, userId: uid)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(account.name)
                                    .font(Typography.h3)
                                    .foregroundStyle(BrandColors.textPrimary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(BrandColors.textTertiary)
                        }
                        .padding(Spacing.cardPadding)
                        .background(BrandColors.surface, in: RoundedRectangle(cornerRadius: Dimensions.cardRadius))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.screenPadding)

            Spacer()

            Button("Sign Out", role: .destructive) {
                authManager.signOut()
            }
            .font(Typography.button)
            .padding(.bottom, Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrandColors.background)
    }
}

#Preview {
    AccountGateView()
        .environment(AuthManager())
        .environment(AccountContext(
            accountsService: AccountsService(syncTracker: NoOpSyncTracker()),
            membersService: AccountMembersService(syncTracker: NoOpSyncTracker())
        ))
}
