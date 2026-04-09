import SwiftUI

struct InventoryItemsSubTab: View {
    @Environment(InventoryContext.self) private var inventoryContext
    @Environment(AccountContext.self) private var accountContext

    @State private var selectedItemIds: Set<String> = []

    // Single-item action target
    @State private var actionTargetItem: Item?

    // Single-item action modals
    @State private var showSingleStatusPicker = false
    @State private var showSingleSetSpace = false
    @State private var showSingleTransactionPicker = false
    @State private var showSingleSellToProject = false
    @State private var showSingleReassign = false
    @State private var showSingleDeleteConfirmation = false

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
            mode: .embedded(items: inventoryContext.items, onItemPress: { _ in }),
            getMenuItems: { singleItemMenuItems(for: $0) },
            emptyMessage: "No inventory items yet",
            onAdd: { showNewItem = true },
            getBulkMenuItems: { bulkActionMenuItems },
            selectedIds: $selectedItemIds,
            useNavigationLinks: true,
            emptyIcon: "shippingbox",
            filterScope: .inventory
        )
        // Single-item action sheets
        .adaptivePresentation(isPresented: $showSingleStatusPicker, style: .quickMenu) {
            StatusPickerModal(currentStatus: actionTargetItem?.status) { status in
                updateItemField(actionTargetItem, fields: ["status": status.rawValue])
            }
        }
        .adaptivePresentation(isPresented: $showSingleSetSpace, style: .picker) {
            SetSpaceModal(
                spaces: inventoryContext.spaces,
                currentSpaceId: actionTargetItem?.spaceId,
                onSelect: { space in
                    let fields: [String: Any] = space?.id != nil ? ["spaceId": space!.id!] : ["spaceId": NSNull()]
                    updateItemField(actionTargetItem, fields: fields)
                }
            )
        }
        .adaptivePresentation(isPresented: $showSingleTransactionPicker, style: .picker) {
            TransactionPickerModal(
                transactions: inventoryContext.transactions,
                selectedId: actionTargetItem?.transactionId,
                onSelect: { tx in
                    if let txId = tx.id {
                        updateItemField(actionTargetItem, fields: ["transactionId": txId])
                    }
                }
            )
        }
        .adaptivePresentation(isPresented: $showSingleSellToProject, style: .form) {
            if let accountId = accountContext.currentAccountId, let item = actionTargetItem {
                SellToProjectModal(items: [item], accountId: accountId) {}
            } else {
                Color.red
                    .overlay(Text("DEBUG: missing \(accountContext.currentAccountId == nil ? "accountId" : "item")").foregroundStyle(.white))
            }
        }
        .adaptivePresentation(isPresented: $showSingleReassign, style: .form) {
            if let item = actionTargetItem {
                ReassignToProjectModal(items: [item]) {}
            }
        }
        .confirmationDialog("Delete item?", isPresented: $showSingleDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteSingleItem() }
        } message: {
            Text("This action cannot be undone.")
        }
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
                SellToProjectModal(items: selectedItems, accountId: accountId) {
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
        return ItemMenuBuilder.buildSingleItemMenu(
            context: .list,
            scope: .inventory,
            callbacks: SingleItemMenuCallbacks(
                onSelect: { selectedItemIds.insert(itemId) },
                onStatusChange: { _ in actionTargetItem = item; showSingleStatusPicker = true },
                onSetTransaction: { actionTargetItem = item; showSingleTransactionPicker = true },
                onClearTransaction: { updateItemField(item, fields: ["transactionId": NSNull()]) },
                onSetSpace: { actionTargetItem = item; showSingleSetSpace = true },
                onClearSpace: { updateItemField(item, fields: ["spaceId": NSNull()]) },
                onSellToProject: {
                    actionTargetItem = item
                    showSingleSellToProject = true
                },
                onReassignToProject: { actionTargetItem = item; showSingleReassign = true },
                onDelete: { actionTargetItem = item; showSingleDeleteConfirmation = true }
            ),
            currentStatus: item.status?.rawValue
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
                onDelete: { showBulkDeleteConfirmation = true }
            )
        )
    }

    // MARK: - Single-Item Actions

    private func updateItemField(_ item: Item?, fields: [String: Any]) {
        guard let accountId = accountContext.currentAccountId,
              let itemId = item?.id else { return }
        let service = ItemsService()
        nonisolated(unsafe) let f = fields
        Task { try? await service.updateItem(accountId: accountId, itemId: itemId, fields: f) }
    }

    private func deleteSingleItem() {
        guard let accountId = accountContext.currentAccountId,
              let item = actionTargetItem else { return }
        let service = ItemsService()
        Task { try? await service.deleteItem(accountId: accountId, item: item) }
    }

    // MARK: - Bulk Actions

    private func updateStatusForSelected(_ status: ItemStatus) {
        guard let accountId = accountContext.currentAccountId else { return }
        let service = ItemsService()
        for item in selectedItems {
            guard let itemId = item.id else { continue }
            Task { try? await service.updateItem(accountId: accountId, itemId: itemId, fields: ["status": status.rawValue]) }
        }
        selectedItemIds.removeAll()
    }

    private func setSpaceForSelected(spaceId: String?) {
        guard let accountId = accountContext.currentAccountId else { return }
        let service = ItemsService()
        nonisolated(unsafe) let fields: [String: Any] = spaceId != nil ? ["spaceId": spaceId!] : ["spaceId": NSNull()]
        for item in selectedItems {
            guard let itemId = item.id else { continue }
            Task { try? await service.updateItem(accountId: accountId, itemId: itemId, fields: fields) }
        }
        selectedItemIds.removeAll()
    }

    private func clearSpaceForSelected() {
        guard let accountId = accountContext.currentAccountId else { return }
        let service = ItemsService()
        for item in selectedItems {
            guard let itemId = item.id else { continue }
            Task { try? await service.updateItem(accountId: accountId, itemId: itemId, fields: ["spaceId": NSNull()]) }
        }
        selectedItemIds.removeAll()
    }

    private func setTransactionForSelected(transactionId: String) {
        guard let accountId = accountContext.currentAccountId else { return }
        let service = ItemsService()
        for item in selectedItems {
            guard let itemId = item.id else { continue }
            Task { try? await service.updateItem(accountId: accountId, itemId: itemId, fields: ["transactionId": transactionId]) }
        }
        selectedItemIds.removeAll()
    }

    private func clearTransactionForSelected() {
        guard let accountId = accountContext.currentAccountId else { return }
        let service = ItemsService()
        for item in selectedItems {
            guard let itemId = item.id else { continue }
            Task { try? await service.updateItem(accountId: accountId, itemId: itemId, fields: ["transactionId": NSNull()]) }
        }
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
