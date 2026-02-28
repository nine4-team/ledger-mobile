import SwiftUI

struct AccountView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AccountContext.self) private var accountContext

    @State private var businessProfile: BusinessProfile?
    @State private var showingEditProfile = false
    @State private var showingSignOutConfirmation = false

    private let profileService = BusinessProfileService(syncTracker: NoOpSyncTracker())

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Business Profile section
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Business Profile")
                        .sectionLabelStyle()

                    Card {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            DetailRow(
                                label: "Business Name",
                                value: businessProfile?.name ?? accountContext.account?.name ?? "—"
                            )

                            Button {
                                showingEditProfile = true
                            } label: {
                                HStack {
                                    Image(systemName: "pencil")
                                    Text("Edit Profile")
                                }
                                .font(Typography.button)
                                .foregroundStyle(BrandColors.primary)
                            }
                        }
                    }
                }

                // Account Actions section
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Account")
                        .sectionLabelStyle()

                    Card {
                        VStack(spacing: Spacing.md) {
                            Button {
                                accountContext.deactivate()
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.left.arrow.right")
                                    Text("Switch Account")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(BrandColors.textTertiary)
                                }
                                .font(Typography.body)
                                .foregroundStyle(BrandColors.textPrimary)
                            }

                            Divider()

                            Button {
                                showingSignOutConfirmation = true
                            } label: {
                                HStack {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                    Text("Sign Out")
                                    Spacer()
                                }
                                .font(Typography.body)
                                .foregroundStyle(BrandColors.destructive)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .background(BrandColors.background)
        .task { await loadProfile() }
        .sheet(isPresented: $showingEditProfile) {
            EditProfileSheet(
                currentName: businessProfile?.name ?? accountContext.account?.name ?? ""
            ) { name in
                updateProfile(name: name)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Sign out?",
            isPresented: $showingSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                accountContext.deactivate()
                authManager.signOut()
            }
        } message: {
            Text("You will need to sign in again to access your account.")
        }
    }

    // MARK: - Data

    private func loadProfile() async {
        guard let accountId = accountContext.currentAccountId else { return }
        businessProfile = try? await profileService.fetch(accountId: accountId)
    }

    private func updateProfile(name: String) {
        guard let accountId = accountContext.currentAccountId else { return }
        var profile = businessProfile ?? BusinessProfile()
        profile.name = name
        Task {
            try? await profileService.update(accountId: accountId, profile: profile)
            businessProfile = profile
        }
    }
}

// MARK: - Edit Profile Sheet

private struct EditProfileSheet: View {
    let currentName: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var hasSubmitted = false

    init(currentName: String, onSave: @escaping (String) -> Void) {
        self.currentName = currentName
        self.onSave = onSave
        _name = State(initialValue: currentName)
    }

    var body: some View {
        FormSheet(
            title: "Edit Business Profile",
            primaryAction: FormSheetAction(
                title: "Save",
                action: handleSave
            ),
            secondaryAction: FormSheetAction(
                title: "Cancel",
                action: { dismiss() }
            )
        ) {
            FormField(
                label: "Business Name",
                text: $name,
                placeholder: "Your business name"
            )
        }
    }

    private func handleSave() {
        hasSubmitted = true
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        onSave(trimmed)
        dismiss()
    }
}
