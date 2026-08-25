import SwiftUI

struct InventoryItemsSubTab: View {
    @Environment(InventoryContext.self) private var inventoryContext
    @Environment(AccountContext.self) private var accountContext

    @State private var selectedItemIds: Set<String> = []
    @State private var itemActions = ItemActionsController()
    @State private var selectedProtoItem: ProtoItem?
    @State private var selectedItemId: String?
    @State private var showItemDetail = false

    // Bulk action modals
    @State private var showBulkStatusPicker = false
    @State private var showBulkSetSpace = false
    @State private var showBulkSellToProject = false
    @State private var showBulkTransactionPicker = false
    @State private var showBulkReassign = false
    @State private var showBulkDeleteConfirmation = false
    @State private var showNewItem = false

    // MARK: - Computed

    private var selectedItems: [Item] {
        inventoryContext.items.filter { item in
            guard let id = item.id else { return false }
            return selectedItemIds.contains(id)
        }
    }

    // MARK: - Body

    var body: some View {
        SharedItemsList(
            mode: .embedded(items: inventoryContext.items, onItemPress: { itemId in
                selectedItemId = itemId
                showItemDetail = true
            }),
            getMenuItems: { singleItemMenuItems(for: $0) },
            emptyMessage: "No inventory items yet",
            onAdd: { showNewItem = true },
            getBulkMenuItems: { bulkActionMenuItems },
            selectedIds: $selectedItemIds,
            emptyIcon: "shippingbox",
            filterScope: .inventory,
            protoItems: inventoryContext.protoItems,
            protoItemCard: { protoItem in
                AnyView(
                    ItemDraftCard(
                        protoItem: protoItem,
                        onOpen: { selectedProtoItem = protoItem }
                    )
                )
            }
        )
        .navigationDestination(item: $selectedProtoItem) { protoItem in
            ItemQuickDraftDetailView(protoItem: protoItem)
        }
        .navigationDestination(isPresented: $showItemDetail) {
            if let selectedItemId,
               let item = inventoryContext.items.first(where: { $0.id == selectedItemId }) {
                ItemDetailView(itemId: selectedItemId, projectId: nil, initialItem: item)
            } else {
                ContentUnavailableView("Item Unavailable", systemImage: "cube.box")
            }
        }
        .itemActionSheets(
            itemActions,
            spaces: inventoryContext.spaces,
            transactions: inventoryContext.transactions,
            accountId: accountContext.currentAccountId
        )
        // Bulk action sheets
        .adaptivePresentation(isPresented: $showBulkStatusPicker, style: .quickMenu) {
            StatusPickerModal { status in updateStatusForSelected(status) }
        }
        .adaptivePresentation(isPresented: $showBulkSetSpace, style: .picker) {
            SetSpaceModal(
                spaces: inventoryContext.spaces,
                currentSpaceId: nil,
                onSelect: { space in setSpaceForSelected(spaceId: space?.id) }
            )
        }
        .adaptivePresentation(isPresented: $showBulkTransactionPicker, style: .picker) {
            TransactionPickerModal(
                transactions: inventoryContext.transactions,
                selectedId: nil,
                onSelect: { tx in
                    if let txId = tx.id { setTransactionForSelected(transactionId: txId) }
                }
            )
        }
        .adaptivePresentation(isPresented: $showBulkSellToProject, style: .form) {
            if let accountId = accountContext.currentAccountId {
                SellItemsModal(items: selectedItems, accountId: accountId) {
                    selectedItemIds.removeAll()
                }
            }
        }
        .adaptivePresentation(isPresented: $showBulkReassign, style: .form) {
            ReassignToProjectModal(items: selectedItems) { selectedItemIds.removeAll() }
        }
        .confirmationDialog("Delete \(selectedItemIds.count) items?", isPresented: $showBulkDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteSelected() }
        } message: {
            Text("This action cannot be undone.")
        }
        .adaptivePresentation(isPresented: $showNewItem, style: .form) {
            NewItemView(context: .inventory)
        }
    }

    // MARK: - Single-Item Menu

    private func singleItemMenuItems(for item: Item) -> [ActionMenuItem] {
        guard let itemId = item.id else { return [] }
        return itemActions.buildMenu(
            for: item,
            scope: .inventory,
            accountId: accountContext.currentAccountId,
            onSelect: { selectedItemIds.insert(itemId) }
        )
    }

    // MARK: - Bulk Menu

    private var bulkActionMenuItems: [ActionMenuItem] {
        ItemMenuBuilder.buildBulkMenu(
            scope: .inventory,
            callbacks: BulkItemMenuCallbacks(
                onStatusChange: { _ in showBulkStatusPicker = true },
                onSetTransaction: { showBulkTransactionPicker = true },
                onClearTransaction: { clearTransactionForSelected() },
                onSetSpace: { showBulkSetSpace = true },
                onClearSpace: { clearSpaceForSelected() },
                onSellToProject: { showBulkSellToProject = true },
                onReassignToProject: { showBulkReassign = true },
                onCopyIDs: { Clipboard.copyLines(selectedItemIds) },
                onDelete: { showBulkDeleteConfirmation = true }
            )
        )
    }

    // MARK: - Bulk Actions

    private func updateStatusForSelected(_ status: ItemStatus) {
        updateSelectedItems(fields: ["status": status.rawValue])
    }

    private func setSpaceForSelected(spaceId: String?) {
        updateSelectedItems(fields: ["spaceId": spaceId as Any? ?? NSNull()])
    }

    private func clearSpaceForSelected() {
        updateSelectedItems(fields: ["spaceId": NSNull()])
    }

    private func updateSelectedItems(fields: [String: Any]) {
        guard let accountId = accountContext.currentAccountId else { return }
        let items = selectedItems
        nonisolated(unsafe) let updateFields = fields
        Task {
            do {
                try await ItemsService().updateItems(
                    accountId: accountId,
                    items: items,
                    fields: updateFields
                )
            } catch {
                print("Bulk item update failed: \(error)")
            }
        }
        selectedItemIds.removeAll()
    }

    private func setTransactionForSelected(transactionId: String) {
        guard let accountId = accountContext.currentAccountId else { return }
        let items = Array(selectedItems)
        Task { try? await ItemsService().setTransaction(accountId: accountId, items: items, transactionId: transactionId) }
        selectedItemIds.removeAll()
    }

    private func clearTransactionForSelected() {
        guard let accountId = accountContext.currentAccountId else { return }
        let items = Array(selectedItems)
        Task { try? await ItemsService().clearTransaction(accountId: accountId, items: items) }
        selectedItemIds.removeAll()
    }

    private func deleteSelected() {
        guard let accountId = accountContext.currentAccountId else { return }
        let service = ItemsService()
        let items = Array(selectedItems)
        Task { try? await service.deleteItems(accountId: accountId, items: items) }
        selectedItemIds.removeAll()
    }
}
