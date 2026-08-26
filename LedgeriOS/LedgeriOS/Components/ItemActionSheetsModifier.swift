import SwiftUI

/// Attaches every single-item action sheet to a view, bound to an
/// `ItemActionsController`. Pair with `ItemActionsController.buildMenu(for:)`
/// to get the matching kebab menu items.
///
/// All sheets are wired unconditionally. Views that don't surface a
/// given action simply never flip the corresponding `Item?`, so the
/// unused sheet stays dormant.
private struct ItemActionSheetsModifier: ViewModifier {
    @Bindable var controller: ItemActionsController
    let spaces: [Space]
    let transactions: [Transaction]
    let accountId: String?
    let onActionComplete: (() -> Void)?

    private var deleteConfirmBinding: Binding<Bool> {
        Binding(
            get: { controller.deleteConfirmItem != nil },
            set: { if !$0 { controller.deleteConfirmItem = nil } }
        )
    }

    func body(content: Content) -> some View {
        content
            .adaptivePresentation(item: $controller.statusPickerItem, style: .quickMenu) { item in
                StatusPickerModal(currentStatus: item.status) { status in
                    controller.updateItem(item, accountId: accountId, fields: ["status": status.rawValue])
                }
            }
            .adaptivePresentation(item: $controller.setSpaceItem, style: .picker) { item in
                SetSpaceModal(
                    spaces: spaces,
                    currentSpaceId: item.spaceId,
                    onSelect: { space in
                        let fields: [String: Any] = space?.id != nil
                            ? ["spaceId": space!.id!]
                            : ["spaceId": NSNull()]
                        controller.updateItem(item, accountId: accountId, fields: fields)
                    }
                )
            }
            .adaptivePresentation(item: $controller.transactionPickerItem, style: .picker) { item in
                TransactionPickerModal(
                    transactions: transactions,
                    selectedId: item.transactionId,
                    onSelect: { tx in
                        if let txId = tx.id {
                            controller.setTransaction(txId, for: item, accountId: accountId)
                        }
                    }
                )
            }
            .adaptivePresentation(item: $controller.returnToInventoryItem, style: .form) { item in
                if let accountId {
                    MoveToInventoryModal(items: [item], accountId: accountId) {
                        onActionComplete?()
                    }
                }
            }
            .adaptivePresentation(item: $controller.sellToProjectItem, style: .form) { item in
                if let accountId {
                    SellItemsModal(items: [item], accountId: accountId) {
                        onActionComplete?()
                    }
                }
            }
            .adaptivePresentation(item: $controller.reassignItem, style: .form) { item in
                ReassignToProjectModal(items: [item]) {
                    onActionComplete?()
                }
            }
            .adaptivePresentation(item: $controller.makeCopiesItem, style: .quickMenu) { item in
                if let accountId {
                    MakeCopiesModal(item: item, accountId: accountId)
                }
            }
            .confirmationDialog("Delete item?", isPresented: deleteConfirmBinding) {
                Button("Delete", role: .destructive) {
                    controller.performDelete(accountId: accountId)
                }
            } message: {
                Text("This action cannot be undone.")
            }
    }
}

extension View {
    /// Wire every single-item action sheet to `controller`. Place once on the
    /// list view that owns the kebab-menu items.
    func itemActionSheets(
        _ controller: ItemActionsController,
        spaces: [Space],
        transactions: [Transaction],
        accountId: String?,
        onActionComplete: (() -> Void)? = nil
    ) -> some View {
        modifier(ItemActionSheetsModifier(
            controller: controller,
            spaces: spaces,
            transactions: transactions,
            accountId: accountId,
            onActionComplete: onActionComplete
        ))
    }
}
