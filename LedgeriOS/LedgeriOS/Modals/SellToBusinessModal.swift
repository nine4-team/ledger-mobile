import SwiftUI

/// Returns items from a project back to business inventory.
/// Creates a Return transaction; items have budgetCategoryId wiped.
struct ReturnToInventoryModal: View {
    let items: [Item]
    let accountId: String
    let onComplete: () -> Void

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var isSaving = false
    @State private var errorMessage: String?

    private static let descriptionText = "This will move items from the project back to business inventory. A return record will be created for financial tracking. The items' budget category will be cleared."

    var body: some View {
        FormSheet(
            title: "Return to Inventory",
            description: Self.descriptionText,
            primaryAction: FormSheetAction(
                title: "Confirm Return",
                isLoading: isSaving,
                action: { performReturn() }
            ),
            secondaryAction: FormSheetAction(title: "Cancel") {
                dismiss()
            },
            error: errorMessage
        ) {
            Text("\(items.count) item\(items.count == 1 ? "" : "s") will return to inventory")
                .font(Typography.body)
                .foregroundStyle(BrandColors.textSecondary)
        }
    }

    private func performReturn() {
        isSaving = true
        errorMessage = nil
        let service = InventoryOperationsService()
        let itemsToReturn = items
        let acctId = accountId
        Task {
            do {
                try await service.returnToInventory(
                    items: itemsToReturn,
                    accountId: acctId,
                    userId: authManager.currentUser?.uid
                )
                await MainActor.run {
                    onComplete()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to return items. Please try again."
                    isSaving = false
                }
            }
        }
    }
}
