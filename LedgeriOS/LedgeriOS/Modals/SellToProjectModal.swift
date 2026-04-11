import SwiftUI
import FirebaseFirestore

/// Two-step flow for selling items to a project.
/// Steps: (1) pick destination project, (2) pick budget category + confirm.
/// One category applies to the entire batch.
struct SellToProjectModal: View {
    let items: [Item]
    let accountId: String
    let onComplete: () -> Void

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var step = 1
    @State private var destinationProject: Project?
    @State private var destinationCategoryId: String?
    @State private var isSaving = false
    @State private var errorMessage: String?
    /// Budget categories fetched independently for the destination project step.
    @State private var accountCategories: [BudgetCategory] = []
    @State private var categoriesListener: ListenerRegistration?

    private static let descriptionText = "A sale record will be created for financial tracking. One budget category applies to all items in this batch."

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepHeader

            switch step {
            case 1:
                step1DestinationProject
            case 2:
                step2CategoryAndConfirm
            default:
                EmptyView()
            }
        }
        .onDisappear {
            categoriesListener?.remove()
            categoriesListener = nil
        }
    }

    // MARK: - Header

    private var stepHeader: some View {
        HStack {
            if step > 1 {
                Button {
                    step -= 1
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(BrandColors.primary)
                }
                .buttonStyle(.plain)
            }

            Text(stepTitle)
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

    private var stepTitle: String {
        switch step {
        case 1: return "Sell to Project"
        case 2: return "Budget Category"
        default: return "Sell to Project"
        }
    }

    // MARK: - Step 1: Pick destination project

    private var step1DestinationProject: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(Self.descriptionText)
                .font(Typography.small)
                .foregroundStyle(BrandColors.textSecondary)
                .padding(.horizontal, Spacing.screenPadding)

            ProjectPickerList { project in
                destinationProject = project
                loadAccountCategories()
                step = 2
            }
        }
    }

    // MARK: - Step 2: Category + confirm

    private var step2CategoryAndConfirm: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Select a budget category in \(destinationProject?.name ?? "destination project")")
                .font(Typography.small)
                .foregroundStyle(BrandColors.textSecondary)
                .padding(.horizontal, Spacing.screenPadding)

            if let error = errorMessage {
                Text(error)
                    .font(Typography.small)
                    .foregroundStyle(StatusColors.missedText)
                    .padding(.horizontal, Spacing.screenPadding)
            }

            CategoryPickerList(
                categories: accountCategories,
                selectedId: destinationCategoryId,
                onSelect: { category in
                    destinationCategoryId = category?.id
                },
                autoDismissOnSelect: false
            )

            Spacer()

            VStack(spacing: Spacing.sm) {
                AppButton(
                    title: "Confirm Sale",
                    isLoading: isSaving,
                    action: { performSale() }
                )
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.screenPadding)
        }
    }

    // MARK: - Action

    private func performSale() {
        guard let project = destinationProject, let projectId = project.id else { return }

        guard let categoryId = destinationCategoryId, !categoryId.isEmpty else {
            errorMessage = "Select a budget category for this sale."
            return
        }

        isSaving = true
        errorMessage = nil
        let service = InventoryOperationsService()
        let itemsToSell = items
        let acctId = accountId
        Task {
            do {
                try await service.sellToProject(
                    items: itemsToSell,
                    destinationProjectId: projectId,
                    budgetCategoryId: categoryId,
                    accountId: acctId,
                    userId: authManager.currentUser?.uid
                )
                await MainActor.run {
                    onComplete()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed: \(error.localizedDescription)"
                    isSaving = false
                }
            }
        }
    }

    private func loadAccountCategories() {
        categoriesListener?.remove()
        let service = BudgetCategoriesService()
        categoriesListener = service.subscribeToBudgetCategories(accountId: accountId) { categories in
            Task { @MainActor in
                accountCategories = categories
            }
        }
    }
}
