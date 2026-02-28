import SwiftUI

/// Sells items from a project into business inventory.
/// Exact description text per FR-8.5.
struct SellToBusinessModal: View {
    let items: [Item]
    let accountId: String
    let onComplete: () -> Void

    @Environment(ProjectContext.self) private var projectContext
    @Environment(\.dismiss) private var dismiss

    @State private var isSaving = false
    @State private var errorMessage: String?

    // Category assignment for items without a category
    @State private var selectedCategoryId: String?

    private static let descriptionText = "This will move items from the project into business inventory. A sale record will be created for financial tracking. If you're just fixing a misallocation, use Reassign instead."

    var body: some View {
        FormSheet(
            title: "Sell to Business",
            description: Self.descriptionText,
            primaryAction: FormSheetAction(
                title: "Confirm Sale",
                isLoading: isSaving,
                action: { performSale() }
            ),
            secondaryAction: FormSheetAction(title: "Cancel") {
                dismiss()
            },
            error: errorMessage
        ) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Summary
                Text("\(items.count) item\(items.count == 1 ? "" : "s") will move to inventory")
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textSecondary)

                // Optional category picker for budget tracking
                if !projectContext.budgetCategories.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Budget Category (Optional)")
                            .font(Typography.label)
                            .foregroundStyle(BrandColors.textSecondary)

                        CategoryPickerList(
                            categories: projectContext.budgetCategories,
                            selectedId: selectedCategoryId,
                            onSelect: { category in
                                selectedCategoryId = category?.id
                            }
                        )
                        .frame(maxHeight: 200)
                    }
                }
            }
        }
    }

    private func performSale() {
        isSaving = true
        errorMessage = nil
        let service = InventoryOperationsService()
        Task {
            do {
                try await service.sellToBusiness(items: items, accountId: accountId)
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
}
