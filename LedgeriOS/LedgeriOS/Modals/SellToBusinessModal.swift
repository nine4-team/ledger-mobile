import SwiftUI

/// Sells project-originated items into business inventory.
struct SellToInventoryModal: View {
    let items: [Item]
    let accountId: String
    let onComplete: () -> Void

    @Environment(AuthManager.self) private var authManager
    @Environment(AccountContext.self) private var accountContext
    @Environment(\.dismiss) private var dismiss

    @State private var isSaving = false
    @State private var errorMessage: String?

    private var split: (returnItems: [Item], saleItems: [Item]) {
        InventoryOperationsService.splitByOrigin(items)
    }

    var body: some View {
        FormSheet(
            title: "Sale to Inventory",
            description: "The business will acquire these project-originated items as inventory. A Sale transaction will be recorded using purchase price.",
            primaryAction: FormSheetAction(
                title: "Confirm Sale",
                isLoading: isSaving,
                isDisabled: !split.returnItems.isEmpty,
                action: { performSale() }
            ),
            secondaryAction: FormSheetAction(title: "Cancel") {
                dismiss()
            },
            error: errorMessage
        ) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("\(split.saleItems.count) item\(split.saleItems.count == 1 ? "" : "s") -> Sale to inventory")
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textSecondary)

                if !split.returnItems.isEmpty {
                    Text("Items that originally came from inventory should use Return to Inventory.")
                        .font(Typography.small)
                        .foregroundStyle(StatusColors.missedText)
                }
            }
        }
    }

    private func performSale() {
        guard split.returnItems.isEmpty else {
            errorMessage = "Use Return to Inventory for items that originally came from inventory."
            return
        }

        isSaving = true
        errorMessage = nil
        let service = InventoryOperationsService()
        let itemsToSell = items
        let acctId = accountId
        let inventoryLabel = InventoryOperationsService.inventoryLabel(for: accountContext.account?.name)
        Task {
            do {
                try await service.sellToInventory(
                    items: itemsToSell,
                    accountId: acctId,
                    inventoryLabel: inventoryLabel,
                    userId: authManager.currentUser?.uid
                )
                await MainActor.run {
                    onComplete()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to sell items. Please try again."
                    isSaving = false
                }
            }
        }
    }
}

/// Moves items from a project to business inventory. Routes each item based on
/// origin:
///   - Items that previously passed through inventory → `Return` transaction
///   - Items that originated in this project → `Sale` (direction
///     `.projectToBusiness`), because the business is acquiring them
///
/// Mixed-origin batches write both transactions atomically and show a preview
/// of the split before the user confirms.
struct MoveToInventoryModal: View {
    let items: [Item]
    let accountId: String
    let onComplete: () -> Void

    @Environment(AuthManager.self) private var authManager
    @Environment(AccountContext.self) private var accountContext
    @Environment(\.dismiss) private var dismiss

    @State private var isSaving = false
    @State private var errorMessage: String?

    private var split: (returnItems: [Item], saleItems: [Item]) {
        InventoryOperationsService.splitByOrigin(items)
    }

    private var returnedPaidItemCredits: [InvoiceLineCalculations.ReturnedPaidItemCreditContext] {
        InvoiceLineCalculations.returnedPaidItemCreditContexts(
            for: split.returnItems,
            invoices: accountContext.allInvoices
        )
    }

    private var title: String {
        let (returns, sales) = split
        switch (returns.isEmpty, sales.isEmpty) {
        case (false, true):  return "Return to Inventory"
        case (true, false):  return "Sale to Inventory"
        // Mixed batch: still labeled "Return to Inventory" because that's the
        // user-facing operation name per docs/specs/reassign-vs-sell.md. The
        // description below discloses the per-item routing (Return vs Sale).
        default:             return "Return to Inventory"
        }
    }

    private var description: String {
        let (returns, sales) = split
        if !returns.isEmpty && sales.isEmpty {
            return "These items originally came from inventory and will return there. A Return transaction will be recorded; the source project's budget decreases."
        }
        if returns.isEmpty && !sales.isEmpty {
            return "These items originated in this project. The business will acquire them as inventory. A Sale transaction will be recorded; the project's budget decreases."
        }
        return "Some items came from inventory (recorded as a Return) and others originated in this project (recorded as a Sale to inventory). Both are written atomically and the project's budget decreases by the total."
    }

    private var primaryActionTitle: String {
        let (returns, sales) = split
        switch (returns.isEmpty, sales.isEmpty) {
        case (false, true):  return "Confirm Return"
        case (true, false):  return "Confirm Sale"
        default:             return "Confirm Move"
        }
    }

    var body: some View {
        FormSheet(
            title: title,
            description: description,
            primaryAction: FormSheetAction(
                title: primaryActionTitle,
                isLoading: isSaving,
                action: { performMove() }
            ),
            secondaryAction: FormSheetAction(title: "Cancel") {
                dismiss()
            },
            error: errorMessage
        ) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                let (returns, sales) = split
                if !returns.isEmpty {
                    Text("\(returns.count) item\(returns.count == 1 ? "" : "s") → Return to inventory")
                        .font(Typography.body)
                        .foregroundStyle(BrandColors.textSecondary)
                }
                if !sales.isEmpty {
                    Text("\(sales.count) item\(sales.count == 1 ? "" : "s") → Sale to inventory")
                        .font(Typography.body)
                        .foregroundStyle(BrandColors.textSecondary)
                }
                let credits = returnedPaidItemCredits
                if !credits.isEmpty {
                    Text("\(credits.count) paid item credit\(credits.count == 1 ? "" : "s") will be added as a credit invoice.")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
        }
    }

    private func performMove() {
        isSaving = true
        errorMessage = nil
        let service = InventoryOperationsService()
        let itemsToMove = items
        let acctId = accountId
        let inventoryLabel = InventoryOperationsService.inventoryLabel(for: accountContext.account?.name)
        let credits = returnedPaidItemCredits
        Task {
            do {
                try await service.moveToInventory(
                    items: itemsToMove,
                    accountId: acctId,
                    inventoryLabel: inventoryLabel,
                    userId: authManager.currentUser?.uid,
                    returnedPaidItemCredits: credits
                )
                await MainActor.run {
                    onComplete()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to move items. Please try again."
                    isSaving = false
                }
            }
        }
    }
}
