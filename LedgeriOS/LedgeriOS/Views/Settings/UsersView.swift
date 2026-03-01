import SwiftUI
import FirebaseFirestore

struct UsersView: View {
    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager

    @State private var members: [AccountMember] = []
    @State private var invites: [Invite] = []
    @State private var membersListener: ListenerRegistration?
    @State private var invitesListener: ListenerRegistration?
    @State private var showingInviteSheet = false
    @State private var revokeTarget: Invite?

    private let membersService = AccountMembersService(syncTracker: NoOpSyncTracker())
    private let invitesService = InvitesService(syncTracker: NoOpSyncTracker())

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Members section
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Team Members")
                        .sectionLabelStyle()

                    if members.isEmpty {
                        Text("No team members found.")
                            .font(Typography.body)
                            .foregroundStyle(BrandColors.textSecondary)
                    } else {
                        LazyVStack(spacing: Spacing.cardListGap) {
                            ForEach(members) { member in
                                MemberRow(member: member)
                            }
                        }
                    }
                }

                // Pending Invitations section
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack {
                        Text("Pending Invitations")
                            .sectionLabelStyle()

                        Spacer()

                        Button {
                            showingInviteSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                Text("Invite")
                            }
                            .font(Typography.buttonSmall)
                            .foregroundStyle(BrandColors.primary)
                        }
                    }

                    if invites.isEmpty {
                        Text("No pending invitations.")
                            .font(Typography.body)
                            .foregroundStyle(BrandColors.textSecondary)
                    } else {
                        LazyVStack(spacing: Spacing.cardListGap) {
                            ForEach(invites) { invite in
                                InviteRow(invite: invite) {
                                    revokeTarget = invite
                                }
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
        .onAppear { startListening() }
        .onDisappear { stopListening() }
        .sheet(isPresented: $showingInviteSheet) {
            InviteUserSheet { email, role in
                createInvite(email: email, role: role)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Revoke this invitation?",
            isPresented: Binding(
                get: { revokeTarget != nil },
                set: { if !$0 { revokeTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Revoke", role: .destructive) {
                if let target = revokeTarget {
                    revokeInvite(target)
                    revokeTarget = nil
                }
            }
        }
    }

    // MARK: - Data

    private func startListening() {
        guard let accountId = accountContext.currentAccountId else { return }

        // Subscribe to members via a collection group query
        let membersRef = Firestore.firestore().collection("accounts/\(accountId)/users")
        membersListener = membersRef.addSnapshotListener { snapshot, _ in
            guard let docs = snapshot?.documents else { return }
            self.members = docs.compactMap { try? $0.data(as: AccountMember.self) }
        }

        invitesListener = invitesService.subscribe(accountId: accountId) { invites in
            self.invites = invites
        }
    }

    private func stopListening() {
        membersListener?.remove()
        invitesListener?.remove()
    }

    private func createInvite(email: String, role: String) {
        guard let accountId = accountContext.currentAccountId,
              let uid = authManager.currentUser?.uid else { return }
        _ = try? invitesService.create(accountId: accountId, email: email, role: role, createdByUid: uid)
    }

    private func revokeInvite(_ invite: Invite) {
        guard let accountId = accountContext.currentAccountId, let id = invite.id else { return }
        Task { try? await invitesService.revoke(accountId: accountId, inviteId: id) }
    }
}

// MARK: - Member Row

private struct MemberRow: View {
    let member: AccountMember

    var body: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(member.name ?? member.email ?? "Unknown")
                        .font(Typography.body)
                        .foregroundStyle(BrandColors.textPrimary)
                    if let email = member.email, member.name != nil {
                        Text(email)
                            .font(Typography.small)
                            .foregroundStyle(BrandColors.textSecondary)
                    }
                }

                Spacer()

                if let role = member.role {
                    Badge(text: role.rawValue.capitalized)
                }
            }
        }
    }
}

// MARK: - Invite Row

private struct InviteRow: View {
    let invite: Invite
    let onRevoke: () -> Void

    @State private var showingCopied = false

    var body: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(invite.email)
                        .font(Typography.body)
                        .foregroundStyle(BrandColors.textPrimary)
                    Badge(text: invite.role.capitalized)
                }

                Spacer()

                HStack(spacing: Spacing.md) {
                    Button {
                        UIPasteboard.general.string = invite.email
                        showingCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showingCopied = false
                        }
                    } label: {
                        Image(systemName: showingCopied ? "checkmark" : "doc.on.doc")
                            .foregroundStyle(showingCopied ? .green : BrandColors.textSecondary)
                    }
                    .buttonStyle(.plain)

                    Button("Revoke") { onRevoke() }
                        .font(Typography.buttonSmall)
                        .foregroundStyle(BrandColors.destructive)
                }
            }
        }
    }
}

// MARK: - Invite User Sheet

private struct InviteUserSheet: View {
    let onInvite: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var role = "user"
    @State private var hasSubmitted = false

    private var emailError: String? {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Email is required" }
        if !trimmed.contains("@") { return "Enter a valid email address" }
        return nil
    }

    var body: some View {
        FormSheet(
            title: "Invite User",
            primaryAction: FormSheetAction(
                title: "Send Invite",
                action: handleInvite
            ),
            secondaryAction: FormSheetAction(
                title: "Cancel",
                action: { dismiss() }
            ),
            error: hasSubmitted ? emailError : nil
        ) {
            VStack(spacing: Spacing.lg) {
                FormField(
                    label: "Email",
                    text: $email,
                    placeholder: "user@example.com",
                    errorText: hasSubmitted ? emailError : nil
                )

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Role")
                        .font(Typography.label)
                        .foregroundStyle(BrandColors.textSecondary)

                    Picker("Role", selection: $role) {
                        Text("User").tag("user")
                        Text("Admin").tag("admin")
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private func handleInvite() {
        hasSubmitted = true
        guard emailError == nil else { return }
        onInvite(email.trimmingCharacters(in: .whitespaces).lowercased(), role)
        dismiss()
    }
}
