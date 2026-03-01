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

    private var tabs: [TabBarItem] {
        var items = [
            TabBarItem(id: "general", label: "General"),
            TabBarItem(id: "presets", label: "Presets"),
        ]
        if isAdmin {
            items.append(TabBarItem(id: "users", label: "Users"))
        }
        if isOwner {
            items.append(TabBarItem(id: "account", label: "Account"))
        }
        return items
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollableTabBar(selectedId: $selectedTab, items: tabs)

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
    }
}

// MARK: - General Settings

private struct GeneralSettingsView: View {
    @Environment(AccountContext.self) private var accountContext
    @AppStorage("colorSchemePreference") private var colorSchemePreference = "system"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Theme Selection
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Appearance")
                        .sectionLabelStyle()

                    SegmentedControl(
                        selection: $colorSchemePreference,
                        options: [
                            SegmentOption(id: "system", label: "System", icon: Image(systemName: "gear")),
                            SegmentOption(id: "light", label: "Light", icon: Image(systemName: "sun.max")),
                            SegmentOption(id: "dark", label: "Dark", icon: Image(systemName: "moon")),
                        ]
                    )
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
            }
            .padding(Spacing.screenPadding)
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
                Picker("Preset Type", selection: $selectedPreset) {
                    Text("Categories").tag("categories")
                    Text("Templates").tag("templates")
                    Text("Vendors").tag("vendors")
                }
                .pickerStyle(.segmented)
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
                accountsService: AccountsService(syncTracker: NoOpSyncTracker()),
                membersService: AccountMembersService(syncTracker: NoOpSyncTracker())
            ))
    }
}
