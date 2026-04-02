import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import PhotosUI
#endif

struct AccountView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AccountContext.self) private var accountContext
    @Environment(MediaService.self) private var mediaService

    @State private var showingEditProfile = false
    @State private var showingSignOutConfirmation = false
    @State private var showingLogoPicker = false
    @State private var isUploadingLogo = false
    #if canImport(UIKit)
    @State private var logoPickerItem: PhotosPickerItem?
    #endif

    private let accountsService = AccountsService()

    var body: some View {
        ScrollView {
            AdaptiveContentWidth {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    // Business Profile section
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Business Profile")
                            .sectionLabelStyle()

                        Card {
                            VStack(alignment: .leading, spacing: Spacing.md) {
                                // Logo
                                HStack(spacing: Spacing.md) {
                                    logoButton
                                        .overlay {
                                            if isUploadingLogo {
                                                RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                                                    .fill(.ultraThinMaterial)
                                                    .frame(width: 64, height: 64)
                                                    .overlay(ProgressView())
                                            }
                                        }

                                    VStack(alignment: .leading, spacing: Spacing.xs) {
                                        Text(accountContext.account?.name ?? "—")
                                            .font(Typography.h3)
                                            .foregroundStyle(BrandColors.textPrimary)
                                        Text("Tap logo to change")
                                            .font(Typography.caption)
                                            .foregroundStyle(BrandColors.textTertiary)
                                    }
                                }

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
                                    .foregroundStyle(BrandColors.textPrimary)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xl)
            }
        }
        .background(BrandColors.background)
        .adaptivePresentation(isPresented: $showingEditProfile, style: .quickMenu) {
            EditProfileSheet(
                currentName: accountContext.account?.name ?? ""
            ) { name in
                updateAccountName(name)
            }
        }
        #if canImport(UIKit)
        .onChange(of: logoPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    await uploadLogo(data)
                }
            }
        }
        #endif
        #if canImport(AppKit)
        .fileImporter(
            isPresented: $showingLogoPicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task {
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                if let data = try? Data(contentsOf: url) {
                    await uploadLogo(data)
                }
            }
        }
        #endif
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

    // MARK: - Logo Button

    @ViewBuilder
    private var logoButton: some View {
        let logoThumbnail = Group {
            if let logoUrl = accountContext.account?.logo?.url, !logoUrl.isEmpty {
                FirebaseImage(url: logoUrl, contentMode: .fill) {
                    ProgressView()
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
            } else {
                RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                    .fill(BrandColors.inputBackground)
                    .overlay(
                        Image(systemName: "building.2")
                            .font(.system(size: 24))
                            .foregroundStyle(BrandColors.textTertiary)
                    )
                    .frame(width: 64, height: 64)
            }
        }

        #if canImport(UIKit)
        PhotosPicker(selection: $logoPickerItem, matching: .images) {
            logoThumbnail
        }
        .buttonStyle(.plain)
        #else
        Button { showingLogoPicker = true } label: {
            logoThumbnail
        }
        .buttonStyle(.plain)
        #endif
    }

    // MARK: - Data

    private func updateAccountName(_ name: String) {
        guard let accountId = accountContext.currentAccountId else { return }
        Task {
            try? await accountsService.updateAccount(accountId: accountId, fields: ["name": name])
        }
    }

    private func uploadLogo(_ data: Data) async {
        guard let accountId = accountContext.currentAccountId else { return }
        isUploadingLogo = true
        defer { isUploadingLogo = false }

        do {
            let filename = "logo_\(UUID().uuidString).jpg"
            let path = mediaService.uploadPath(
                accountId: accountId,
                entityType: "account",
                entityId: accountId,
                filename: filename
            )
            let url = try await mediaService.uploadImage(data, path: path)
            let logo: [String: Any] = ["url": url, "kind": "image"]
            try await accountsService.updateAccount(accountId: accountId, fields: ["logo": logo])
        } catch {
            print("Logo upload failed: \(error)")
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
