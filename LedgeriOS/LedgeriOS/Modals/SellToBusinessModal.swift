import SwiftUI

/// Sells items from a project into business inventory.
/// Exact description text per FR-8.5.
struct SellToBusinessModal: View {
    let items: [Item]
    let accountId: String
    let onComplete: () -> Void

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var isSaving = false
    @State private var errorMessage: String?

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
            Text("\(items.count) item\(items.count == 1 ? "" : "s") will move to inventory")
                .font(Typography.body)
                .foregroundStyle(BrandColors.textSecondary)
        }
    }

    private func performSale() {
        isSaving = true
        errorMessage = nil
        let service = InventoryOperationsService()
        let itemsToSell = items
        let acctId = accountId
        Task {
            do {
                try await service.sellToBusiness(
                    items: itemsToSell,
                    accountId: acctId,
                    userId: authManager.currentUser?.uid
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
}
