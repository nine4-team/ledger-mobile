import SwiftUI

/// Owns all single-item action sheet state for a list view. One instance per view.
///
/// Pair with `.itemActionSheets(...)` modifier — the modifier binds each sheet
/// to the matching `Item?` property here, and `buildMenu(for:)` wires
/// `SingleItemMenuCallbacks` to flip those properties (or perform inline writes).
///
/// This consolidates the kebab-menu wiring that was previously duplicated across
/// `ItemsTabView`, `InventoryItemsSubTab`, `SpaceDetailView`, and `UniversalSearchView`.
@MainActor
@Observable
final class ItemActionsController {
    // MARK: - Sheet targets

    var statusPickerItem: Item?
    var setSpaceItem: Item?
    var transactionPickerItem: Item?
    var returnToInventoryItem: Item?
    var sellToProjectItem: Item?
    var reassignItem: Item?
    var makeCopiesItem: Item?
    var deleteConfirmItem: Item?

    // MARK: - Menu

    /// Build a kebab-menu item list for `item`. All callbacks are wired to flip
    /// this controller's own state, so the caller just hands the result to
    /// `SharedItemsList`'s `getMenuItems`.
    ///
    /// - Parameters:
    ///   - item: The item the menu is being built for.
    ///   - scope: Whether the caller is in a project, inventory, or search context.
    ///   - menuContext: Where the menu is surfaced (list vs. space vs. detail).
    ///   - accountId: Used for inline clear writes (clear space / clear transaction).
    ///   - onSelect: Optional bulk-selection callback (caller wires to its `Set<String>`).
    ///   - includeReturnToInventory: Surface the "Return to Inventory" action. Default: project items that originally came from inventory.
    ///   - includeSellToProject: Surface the "Sell" action. Default: true for project/inventory.
    func buildMenu(
        for item: Item,
        scope: ItemScope,
        menuContext: ItemMenuContext = .list,
        accountId: String?,
        onSelect: (() -> Void)? = nil,
        includeReturnToInventory: Bool? = nil,
        includeSellToProject: Bool? = nil
    ) -> [ActionMenuItem] {
        let wantsReturnToInventory = includeReturnToInventory ?? (
            scope == .project && InventoryOperationsService.cameFromInventory(item)
        )
        let wantsSellToProject = includeSellToProject ?? (scope == .project || scope == .inventory)

        let callbacks = SingleItemMenuCallbacks(
            onSelect: onSelect,
            onStatusChange: { [weak self] _ in self?.statusPickerItem = item },
            onSetTransaction: { [weak self] in self?.transactionPickerItem = item },
            onClearTransaction: { [weak self] in
                self?.clearTransaction(item, accountId: accountId)
            },
            onSetSpace: { [weak self] in self?.setSpaceItem = item },
            onClearSpace: { [weak self] in
                self?.updateItem(item, accountId: accountId, fields: ["spaceId": NSNull()])
            },
            onReturnToInventory: wantsReturnToInventory
                ? { [weak self] in self?.returnToInventoryItem = item }
                : nil,
            onSellToProject: wantsSellToProject
                ? { [weak self] in self?.sellToProjectItem = item }
                : nil,
            onReassignToProject: { [weak self] in self?.reassignItem = item },
            onMakeCopies: { [weak self] in self?.makeCopiesItem = item },
            onCopyID: item.id.map { id in { Clipboard.copy(id) } },
            onDelete: { [weak self] in self?.deleteConfirmItem = item }
        )

        return ItemMenuBuilder.buildSingleItemMenu(
            context: menuContext,
            scope: scope,
            callbacks: callbacks,
            currentStatus: item.status?.rawValue
        )
    }

    // MARK: - Writes

    /// Inline update helper used by clear-transaction / clear-space menu actions.
    func updateItem(_ item: Item, accountId: String?, fields: [String: Any]) {
        guard let accountId, let itemId = item.id else { return }
        let service = ItemsService()
        nonisolated(unsafe) let f = fields
        Task { try? await service.updateItem(accountId: accountId, itemId: itemId, fields: f) }
    }

    func setTransaction(_ transactionId: String, for item: Item, accountId: String?) {
        guard let accountId else { return }
        Task { try? await ItemsService().setTransaction(accountId: accountId, items: [item], transactionId: transactionId) }
    }

    func clearTransaction(_ item: Item, accountId: String?) {
        guard let accountId else { return }
        Task { try? await ItemsService().clearTransaction(accountId: accountId, items: [item]) }
    }

    /// Performs the delete for `deleteConfirmItem`, then clears it.
    func performDelete(accountId: String?) {
        guard let accountId, let item = deleteConfirmItem else { return }
        let service = ItemsService()
        Task { try? await service.deleteItem(accountId: accountId, item: item) }
        deleteConfirmItem = nil
    }
}
