import SwiftUI
import FirebaseFirestore

/// Multi-step flow for selling items to another project.
/// Steps: (1) pick destination project, (2) destination category, (3) source category.
/// Exact description text per FR-8.6.
struct SellToProjectModal: View {
    let items: [Item]
    let accountId: String
    let onComplete: () -> Void

    @Environment(ProjectContext.self) private var projectContext
    @Environment(\.dismiss) private var dismiss

    @State private var step = 1
    @State private var destinationProject: Project?
    @State private var destinationCategoryId: String?
    @State private var sourceCategoryId: String?
    @State private var isSaving = false
    @State private var errorMessage: String?
    /// Budget categories fetched independently for the destination project step.
    /// Categories are account-level presets, but we fetch them separately to avoid
    /// coupling to the source project's ProjectContext.
    @State private var accountCategories: [BudgetCategory] = []
    @State private var categoriesListener: ListenerRegistration?

    private static let descriptionText = "Sale and purchase records will be created for financial tracking. If you're just fixing a misallocation, use Reassign instead."

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepHeader

            switch step {
            case 1:
                step1DestinationProject
            case 2:
                step2DestinationCategory
            case 3:
                step3SourceCategory
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
        case 2: return "Destination Category"
        case 3: return "Source Category"
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

    // MARK: - Step 2: Destination category

    private var step2DestinationCategory: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Select a budget category in \(destinationProject?.name ?? "destination project") (optional)")
                .font(Typography.small)
                .foregroundStyle(BrandColors.textSecondary)
                .padding(.horizontal, Spacing.screenPadding)

            CategoryPickerList(
                categories: accountCategories,
                selectedId: destinationCategoryId,
                onSelect: { category in
                    destinationCategoryId = category?.id
                    step = 3
                }
            )
        }
    }

    // MARK: - Step 3: Source category + confirm

    private var step3SourceCategory: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Select a budget category in the source project (optional)")
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
                categories: projectContext.budgetCategories,
                selectedId: sourceCategoryId,
                onSelect: { category in
                    sourceCategoryId = category?.id
                }
            )

            Spacer()

            VStack(spacing: Spacing.sm) {
                AppButton(
                    title: "Confirm Sale",
                    isLoading: isSaving,
                    action: { performSale() }
                )
                AppButton(title: "Skip", variant: .secondary) {
                    performSale()
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.screenPadding)
        }
    }

    // MARK: - Action

    private func performSale() {
        guard let project = destinationProject, let projectId = project.id else { return }
        isSaving = true
        errorMessage = nil
        let service = InventoryOperationsService()
        let itemsToSell = items
        let acctId = accountId
        let srcCatId = sourceCategoryId
        let destCatId = destinationCategoryId
        Task {
            do {
                try await service.sellToProject(
                    items: itemsToSell,
                    destinationProjectId: projectId,
                    accountId: acctId,
                    sourceCategoryId: srcCatId,
                    destinationCategoryId: destCatId
                )
                await MainActor.run {
                    onComplete()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to complete sale. Please try again."
                    isSaving = false
                }
            }
        }
    }

    private func loadAccountCategories() {
        categoriesListener?.remove()
        let service = BudgetCategoriesService(syncTracker: NoOpSyncTracker())
        categoriesListener = service.subscribeToBudgetCategories(accountId: accountId) { categories in
            Task { @MainActor in
                accountCategories = categories
            }
        }
    }
}
