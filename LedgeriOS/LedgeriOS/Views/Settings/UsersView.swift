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
    @State private var selectedMember: AccountMember?

    private let membersService = AccountMembersService()
    private let invitesService = InvitesService()

    private var feeCategories: [BudgetCategory] {
        accountContext.allBudgetCategories
            .filter(\.isFeeCategory)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            AdaptiveContentWidth {
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
                                    MemberRow(member: member) {
                                        selectedMember = member
                                    }
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
        }
        .background(BrandColors.background)
        .onAppear { startListening() }
        .onDisappear { stopListening() }
        .adaptivePresentation(isPresented: $showingInviteSheet, style: .quickMenu) {
            InviteUserSheet(feeCategories: feeCategories) { email, role, access, allowedIds in
                createInvite(email: email, role: role, access: access, allowedFeeCategoryIds: allowedIds)
            }
        }
        .adaptivePresentation(item: $selectedMember, style: .form) { member in
            MemberAccessSheet(
                member: member,
                feeCategories: feeCategories,
                currentUserId: authManager.currentUser?.uid
            ) { member, role, access, allowedIds in
                try await updateMemberAccess(member: member, role: role, access: access, allowedFeeCategoryIds: allowedIds)
            }
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

    private func createInvite(
        email: String,
        role: MemberRole,
        access: CompanyFinancialAccess,
        allowedFeeCategoryIds: [String]
    ) {
        guard let accountId = accountContext.currentAccountId,
              let uid = authManager.currentUser?.uid else { return }
        _ = try? invitesService.create(
            accountId: accountId,
            email: email,
            role: role,
            companyFinancialAccess: access,
            allowedFeeCategoryIds: allowedFeeCategoryIds,
            createdByUid: uid
        )
    }

    private func revokeInvite(_ invite: Invite) {
        guard let accountId = accountContext.currentAccountId, let id = invite.id else { return }
        Task { try? await invitesService.revoke(accountId: accountId, inviteId: id) }
    }

    private func updateMemberAccess(
        member: AccountMember,
        role: MemberRole,
        access: CompanyFinancialAccess,
        allowedFeeCategoryIds: [String]
    ) async throws {
        guard let accountId = accountContext.currentAccountId,
              let userId = member.uid ?? member.id else { return }
        try await membersService.updateAccess(
            accountId: accountId,
            userId: userId,
            role: role,
            companyFinancialAccess: access,
            allowedFeeCategoryIds: allowedFeeCategoryIds
        )
    }
}

// MARK: - Member Row

private struct MemberRow: View {
    let member: AccountMember
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
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

                VStack(alignment: .trailing, spacing: Spacing.xs) {
                    Badge(text: (member.role ?? .user).displayLabel)
                    Badge(text: member.resolvedCompanyFinancialAccess.displayLabel)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(BrandColors.textTertiary)
            }
        }
        .buttonStyle(.plain)
        .cardStyle()
    }
}

// MARK: - Member Access Sheet

private struct MemberAccessSheet: View {
    let member: AccountMember
    let feeCategories: [BudgetCategory]
    let currentUserId: String?
    let onSave: (AccountMember, MemberRole, CompanyFinancialAccess, [String]) async throws -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var role: MemberRole
    @State private var access: CompanyFinancialAccess
    @State private var allowedFeeCategoryIds: Set<String>
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        member: AccountMember,
        feeCategories: [BudgetCategory],
        currentUserId: String?,
        onSave: @escaping (AccountMember, MemberRole, CompanyFinancialAccess, [String]) async throws -> Void
    ) {
        self.member = member
        self.feeCategories = feeCategories
        self.currentUserId = currentUserId
        self.onSave = onSave
        _role = State(initialValue: member.role ?? .user)
        _access = State(initialValue: member.resolvedCompanyFinancialAccess)
        _allowedFeeCategoryIds = State(initialValue: member.resolvedAllowedFeeCategoryIds)
    }

    var body: some View {
        FormSheet(
            title: "Access",
            description: member.name ?? member.email,
            primaryAction: FormSheetAction(
                title: isSaving ? "Saving..." : "Save",
                isLoading: isSaving,
                isDisabled: isSaving,
                action: save
            ),
            secondaryAction: FormSheetAction(
                title: "Cancel",
                action: { dismiss() }
            ),
            error: errorMessage
        ) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                accessSectionTitle("Role")
                InlineOptionPicker(selection: $role, options: [
                    InlineOption(id: MemberRole.owner, label: MemberRole.owner.displayLabel),
                    InlineOption(id: MemberRole.admin, label: MemberRole.admin.displayLabel),
                    InlineOption(id: MemberRole.user, label: MemberRole.user.displayLabel),
                ])

                accessSectionTitle("Financial Access")
                InlineOptionPicker(selection: $access, options: [
                    InlineOption(id: CompanyFinancialAccess.full, label: CompanyFinancialAccess.full.displayLabel),
                    InlineOption(id: CompanyFinancialAccess.limited, label: CompanyFinancialAccess.limited.displayLabel),
                    InlineOption(id: CompanyFinancialAccess.none, label: CompanyFinancialAccess.none.displayLabel),
                ])

                if access == .limited {
                    visibleFeeCategoriesSection
                }

                Text(invoiceAccessText)
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textSecondary)
            }
        }
    }

    private var visibleFeeCategoriesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            accessSectionTitle("Visible Fee Categories")

            if feeCategories.isEmpty {
                Text("No fee categories have been created yet.")
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textSecondary)
            } else {
                VStack(spacing: Spacing.xs) {
                    ForEach(feeCategories.compactMap { category -> BudgetCategory? in
                        category.id == nil ? nil : category
                    }) { category in
                        CategoryAccessRow(
                            category: category,
                            isSelected: allowedFeeCategoryIds.contains(category.id ?? "")
                        ) {
                            toggleCategory(category.id)
                        }
                    }
                }
            }
        }
    }

    private var invoiceAccessText: String {
        switch access {
        case .full:
            return "This user can open all invoices and see all company fee activity."
        case .limited:
            return "This user can only open invoices where every fee line is in an allowed category."
        case .none:
            return "This user cannot see company fee transactions or invoices containing company revenue."
        }
    }

    private func accessSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(Typography.label)
            .foregroundStyle(BrandColors.textSecondary)
    }

    private func toggleCategory(_ categoryId: String?) {
        guard let categoryId else { return }
        if allowedFeeCategoryIds.contains(categoryId) {
            allowedFeeCategoryIds.remove(categoryId)
        } else {
            allowedFeeCategoryIds.insert(categoryId)
        }
    }

    private func save() {
        errorMessage = nil

        if member.uid == currentUserId || member.id == currentUserId {
            if role != .owner && role != .admin {
                errorMessage = "You cannot remove your own admin access."
                return
            }
            if access != .full {
                errorMessage = "You cannot reduce your own financial access."
                return
            }
        }

        isSaving = true
        Task {
            do {
                try await onSave(member, role, access, Array(allowedFeeCategoryIds).sorted())
                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to save access. Please try again."
                }
            }
        }
    }
}

private struct CategoryAccessRow: View {
    let category: BudgetCategory
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: Spacing.md) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? BrandColors.primary : BrandColors.textSecondary)
                    .font(.title3)

                Text(category.name)
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textPrimary)

                Spacer()
            }
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, Spacing.md)
            .formInputStyle()
        }
        .buttonStyle(.plain)
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
                    HStack(spacing: Spacing.xs) {
                        Badge(text: inviteRoleLabel)
                        Badge(text: invite.resolvedCompanyFinancialAccess.displayLabel)
                    }
                }

                Spacer()

                HStack(spacing: Spacing.md) {
                    Button {
                        Clipboard.copy(invite.inviteLink?.absoluteString ?? invite.email)
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
                        .foregroundStyle(BrandColors.textPrimary)
                }
            }
        }
    }

    private var inviteRoleLabel: String {
        MemberRole(rawValue: invite.role)?.displayLabel ?? invite.role.capitalized
    }
}

// MARK: - Invite User Sheet

private struct InviteUserSheet: View {
    let feeCategories: [BudgetCategory]
    let onInvite: (String, MemberRole, CompanyFinancialAccess, [String]) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var role: MemberRole = .user
    @State private var access: CompanyFinancialAccess = .none
    @State private var allowedFeeCategoryIds: Set<String> = []
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

                    InlineOptionPicker(selection: $role, options: [
                        InlineOption(id: MemberRole.user, label: MemberRole.user.displayLabel),
                        InlineOption(id: MemberRole.admin, label: MemberRole.admin.displayLabel),
                    ])
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Financial Access")
                        .font(Typography.label)
                        .foregroundStyle(BrandColors.textSecondary)

                    InlineOptionPicker(selection: $access, options: [
                        InlineOption(id: CompanyFinancialAccess.full, label: CompanyFinancialAccess.full.displayLabel),
                        InlineOption(id: CompanyFinancialAccess.limited, label: CompanyFinancialAccess.limited.displayLabel),
                        InlineOption(id: CompanyFinancialAccess.none, label: CompanyFinancialAccess.none.displayLabel),
                    ])
                }

                if access == .limited {
                    visibleFeeCategoriesSection
                }
            }
        }
        .onChange(of: role) {
            if role == .admin, access == .none {
                access = .full
            } else if role == .user, access == .full {
                access = .none
            }
        }
    }

    private var visibleFeeCategoriesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Visible Fee Categories")
                .font(Typography.label)
                .foregroundStyle(BrandColors.textSecondary)

            if feeCategories.isEmpty {
                Text("No fee categories have been created yet.")
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textSecondary)
            } else {
                VStack(spacing: Spacing.xs) {
                    ForEach(feeCategories.compactMap { category -> BudgetCategory? in
                        category.id == nil ? nil : category
                    }) { category in
                        CategoryAccessRow(
                            category: category,
                            isSelected: allowedFeeCategoryIds.contains(category.id ?? "")
                        ) {
                            toggleCategory(category.id)
                        }
                    }
                }
            }
        }
    }

    private func handleInvite() {
        hasSubmitted = true
        guard emailError == nil else { return }
        onInvite(
            email.trimmingCharacters(in: .whitespaces).lowercased(),
            role,
            access,
            Array(allowedFeeCategoryIds).sorted()
        )
        dismiss()
    }

    private func toggleCategory(_ categoryId: String?) {
        guard let categoryId else { return }
        if allowedFeeCategoryIds.contains(categoryId) {
            allowedFeeCategoryIds.remove(categoryId)
        } else {
            allowedFeeCategoryIds.insert(categoryId)
        }
    }
}
