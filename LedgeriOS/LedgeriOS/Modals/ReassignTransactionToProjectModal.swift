import SwiftUI
import FirebaseFirestore

/// Moves a transaction to a different project by updating its projectId and
/// budget category together. Moving across projects changes budget scope, so
/// the old category (which belongs to the source scope) can't carry over — the
/// user must pick a category in the destination project or the cost lands
/// uncategorized and drops out of budget tracking.
struct ReassignTransactionToProjectModal: View {
    let transaction: Transaction
    let onComplete: () -> Void

    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var step = 1
    @State private var destinationProject: Project?
    @State private var destinationCategoryId: String?
    @State private var destinationProjectBudgetCategories: [ProjectBudgetCategory] = []
    @State private var categoriesListener: ListenerRegistration?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let error = errorMessage {
                Text(error)
                    .font(Typography.small)
                    .foregroundStyle(StatusColors.missedText)
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.bottom, Spacing.sm)
            }

            switch step {
            case 2:
                categoryStep
            default:
                ProjectPickerList { project in
                    destinationProject = project
                    loadDestinationCategories(for: project)
                    step = 2
                }
            }
        }
        .disabled(isSaving)
        .onDisappear {
            categoriesListener?.remove()
            categoriesListener = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            if step > 1 {
                Button {
                    step = 1
                    destinationCategoryId = nil
                    errorMessage = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(BrandColors.primary)
                }
                .buttonStyle(.plain)
            }

            Text(step == 2 ? "Budget Category" : "Move to Project")
                .font(Typography.h2)
                .foregroundStyle(BrandColors.textPrimary)

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(BrandColors.textTertiary)
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, Spacing.screenPadding)
        .padding(.bottom, Spacing.md)
    }

    // MARK: - Step 2: Category + confirm

    private var categoryStep: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Pick a budget category in \(destinationProject?.name ?? "the destination project"). This cost is tracked against that category's budget.")
                .font(Typography.small)
                .foregroundStyle(BrandColors.textSecondary)
                .padding(.horizontal, Spacing.screenPadding)

            CategoryPickerList(
                categories: destinationCategories,
                selectedId: destinationCategoryId,
                onSelect: { category in
                    destinationCategoryId = category?.id
                },
                autoDismissOnSelect: false
            )

            Spacer()

            AppButton(
                title: "Move Transaction",
                isLoading: isSaving,
                action: { move() }
            )
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.screenPadding)
        }
    }

    /// Categories enabled in the destination project. Falls back to all account
    /// categories when the project has none set up yet, so the picker is never
    /// empty; a chosen-but-unenabled category is enabled on confirm.
    private var destinationCategories: [BudgetCategory] {
        let enabledIds = Set(destinationProjectBudgetCategories.compactMap(\.id))
        let enabled = accountContext.allBudgetCategories.filter { cat in
            guard let id = cat.id else { return false }
            return enabledIds.contains(id)
        }
        return enabled.isEmpty ? accountContext.allBudgetCategories : enabled
    }

    // MARK: - Data

    private func loadDestinationCategories(for project: Project) {
        guard let accountId = accountContext.currentAccountId,
              let projectId = project.id else { return }
        categoriesListener?.remove()
        destinationProjectBudgetCategories = []
        categoriesListener = ProjectBudgetCategoriesService()
            .subscribeToProjectBudgetCategories(accountId: accountId, projectId: projectId) { pbc in
                Task { @MainActor in
                    destinationProjectBudgetCategories = pbc
                }
            }
    }

    // MARK: - Action

    private func move() {
        guard let accountId = accountContext.currentAccountId,
              let transactionId = transaction.id,
              let project = destinationProject,
              let projectId = project.id else { return }

        guard let categoryId = destinationCategoryId, !categoryId.isEmpty else {
            errorMessage = "Select a budget category for this transaction."
            return
        }

        isSaving = true
        errorMessage = nil
        let enabledIds = Set(destinationProjectBudgetCategories.compactMap(\.id))
        let needsEnable = !enabledIds.contains(categoryId)
        let userId = authManager.currentUser?.uid

        Task {
            do {
                // Enable the category for the destination project if it isn't
                // already — merge with budgetCents: 0 only creates the missing
                // doc; it never runs against an existing allocation.
                if needsEnable {
                    try await ProjectBudgetCategoriesService().setProjectBudgetCategory(
                        accountId: accountId,
                        projectId: projectId,
                        categoryId: categoryId,
                        budgetCents: 0,
                        userId: userId
                    )
                }

                try await TransactionsService().updateTransaction(
                    accountId: accountId,
                    transactionId: transactionId,
                    fields: [
                        "projectId": projectId,
                        "budgetCategoryId": categoryId,
                    ]
                )
                await MainActor.run {
                    onComplete()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to move transaction. Please try again."
                    isSaving = false
                }
            }
        }
    }
}
