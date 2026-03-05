import SwiftUI

struct InventoryItemsSubTab: View {
    @Environment(InventoryContext.self) private var inventoryContext
    @Environment(AccountContext.self) private var accountContext

    @State private var selectedItemIds: Set<String> = []

    // Bulk action modals
    @State private var showBulkStatusPicker = false
    @State private var showBulkSetSpace = false
    @State private var showBulkSellToProject = false
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
            useAdaptiveWidth: true,
            emptyIcon: "shippingbox",
            filterScope: .inventory
        )
        .sheet(isPresented: $showBulkStatusPicker) {
            StatusPickerModal { status in updateStatusForSelected(status) }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showBulkSetSpace) {
            SetSpaceModal(
                spaces: inventoryContext.spaces,
                currentSpaceId: nil,
                onSelect: { space in setSpaceForSelected(spaceId: space?.id) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showBulkSellToProject) {
            if let accountId = accountContext.currentAccountId {
                SellToProjectModal(items: selectedItems, accountId: accountId) {
                    selectedItemIds.removeAll()
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .confirmationDialog("Delete \(selectedItemIds.count) items?", isPresented: $showBulkDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteSelected() }
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $showNewItem) {
            NewItemView(context: .inventory)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Menu Items

    private func singleItemMenuItems(for item: Item) -> [ActionMenuItem] {
        guard let itemId = item.id else { return [] }
        return [
            ActionMenuItem(id: "select", label: "Select", icon: "checkmark.circle", onPress: {
                selectedItemIds.insert(itemId)
            }),
        ]
    }

    private var bulkActionMenuItems: [ActionMenuItem] {
        [
            ActionMenuItem(id: "status", label: "Change Status", icon: "flag",
                           onPress: { showBulkStatusPicker = true }),
            ActionMenuItem(id: "space", label: "Set Space", icon: "mappin.and.ellipse",
                           onPress: { showBulkSetSpace = true }),
            ActionMenuItem(id: "sell-project", label: "Sell to Project", icon: "arrow.right.square",
                           onPress: { showBulkSellToProject = true }),
            ActionMenuItem(id: "delete", label: "Delete", icon: "trash", isDestructive: true,
                           onPress: { showBulkDeleteConfirmation = true }),
        ]
    }

    // MARK: - Bulk Actions

    private func updateStatusForSelected(_ status: String) {
        guard let accountId = accountContext.currentAccountId else { return }
        let service = ItemsService(syncTracker: NoOpSyncTracker())
        for item in selectedItems {
            guard let itemId = item.id else { continue }
            Task { try? await service.updateItem(accountId: accountId, itemId: itemId, fields: ["status": status]) }
        }
        selectedItemIds.removeAll()
    }

    private func setSpaceForSelected(spaceId: String?) {
        guard let accountId = accountContext.currentAccountId else { return }
        let service = ItemsService(syncTracker: NoOpSyncTracker())
        let fields: [String: Any] = spaceId != nil ? ["spaceId": spaceId!] : ["spaceId": NSNull()]
        for item in selectedItems {
            guard let itemId = item.id else { continue }
            Task { try? await service.updateItem(accountId: accountId, itemId: itemId, fields: fields) }
        }
        selectedItemIds.removeAll()
    }

    private func deleteSelected() {
        guard let accountId = accountContext.currentAccountId else { return }
        let service = ItemsService(syncTracker: NoOpSyncTracker())
        for item in selectedItems {
            guard let itemId = item.id else { continue }
            Task { try? await service.deleteItem(accountId: accountId, itemId: itemId) }
        }
        selectedItemIds.removeAll()
    }
}
