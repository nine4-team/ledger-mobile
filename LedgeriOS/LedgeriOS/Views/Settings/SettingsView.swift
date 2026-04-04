import SwiftUI

struct SettingsView: View {
    @Environment(AccountContext.self) private var accountContext
    @State private var selectedTab = "general"

    private var isAdmin: Bool {
        accountContext.member?.role == .owner || accountContext.member?.role == .admin
    }

    private var isOwner: Bool {
        accountContext.member?.role == .owner
    }

    var body: some View {
        VStack(spacing: 0) {
            SegmentedControl(selection: $selectedTab, options: {
                var opts = [
                    SegmentOption(id: "general", label: "General"),
                    SegmentOption(id: "presets", label: "Presets"),
                ]
                if isAdmin { opts.append(SegmentOption(id: "users", label: "Users")) }
                if isOwner { opts.append(SegmentOption(id: "account", label: "Account")) }
                return opts
            }())
            .frame(maxWidth: Dimensions.contentMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.sm)

            Group {
                switch selectedTab {
                case "general":
                    GeneralSettingsView()
                case "presets":
                    PresetsSettingsView(isAdmin: isAdmin)
                case "users":
                    UsersView()
                case "account":
                    AccountView()
                default:
                    GeneralSettingsView()
                }
            }
        }
        .navigationTitle("Settings")
        .navBarTitleDisplayMode(.inline)
    }
}

// MARK: - General Settings

private struct GeneralSettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AccountContext.self) private var accountContext
    @AppStorage("colorSchemePreference") private var colorSchemePreference = "system"

    var body: some View {
        ScrollView {
            AdaptiveContentWidth {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    // Theme Selection
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Appearance")
                            .sectionLabelStyle()

                        InlineOptionPicker(selection: $colorSchemePreference, options: [
                            InlineOption(id: "system", label: "System"),
                            InlineOption(id: "light", label: "Light"),
                            InlineOption(id: "dark", label: "Dark"),
                        ])
                    }

                    // Account Info
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Account Info")
                            .sectionLabelStyle()

                        Card {
                            VStack(spacing: Spacing.md) {
                                if let account = accountContext.account {
                                    DetailRow(label: "Account", value: account.name)
                                }
                                if let member = accountContext.member {
                                    DetailRow(label: "Role", value: member.role?.rawValue.capitalized ?? "—")
                                    if let email = member.email {
                                        DetailRow(label: "Email", value: email)
                                    }
                                }
                            }
                        }
                    }

                    // Debug
                    NavigationLink("Firestore Test") {
                        FirestoreTestView()
                    }
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.primary)

                    // Sign Out
                    Button("Sign Out") {
                        authManager.signOut()
                    }
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.primary)
                }
                .padding(Spacing.screenPadding)
            }
        }
        .background(BrandColors.background)
    }
}

// MARK: - Presets Settings (sub-tabs)

private struct PresetsSettingsView: View {
    let isAdmin: Bool
    @State private var selectedPreset = "categories"

    var body: some View {
        if isAdmin {
            VStack(spacing: 0) {
                SegmentedControl(selection: $selectedPreset, options: [
                    SegmentOption(id: "categories", label: "Categories"),
                    SegmentOption(id: "templates", label: "Templates"),
                    SegmentOption(id: "vendors", label: "Vendors"),
                ])
                .frame(maxWidth: Dimensions.contentMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.vertical, Spacing.sm)

                Group {
                    switch selectedPreset {
                    case "categories":
                        BudgetCategoryManagementView()
                    case "templates":
                        SpaceTemplateManagementView()
                    case "vendors":
                        VendorDefaultsView()
                    default:
                        BudgetCategoryManagementView()
                    }
                }
            }
        } else {
            VStack(spacing: Spacing.lg) {
                Spacer()
                Image(systemName: "lock")
                    .font(.system(size: 32))
                    .foregroundStyle(BrandColors.textTertiary)
                Text("Presets are only configurable by account administrators.")
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textSecondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding(Spacing.screenPadding)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(AuthManager())
            .environment(AccountContext(
                accountsService: AccountsService(),
                membersService: AccountMembersService()
            ))
    }
}
