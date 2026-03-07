import SwiftUI

struct ItemsTabView: View {
    @Environment(ProjectContext.self) private var projectContext
    @Environment(AccountContext.self) private var accountContext

    @State private var selectedItemIds: Set<String> = []

    // Bulk action modals
    @State private var showBulkStatusPicker = false
    @State private var showBulkSetSpace = false
    @State private var showBulkSellToBusiness = false
    @State private var showBulkSellToProject = false
    @State private var showBulkReassign = false
    @State private var showBulkDeleteConfirmation = false
    @State private var showNewItem = false

    // MARK: - Computed

    private var selectedItems: [Item] {
        projectContext.items.filter { item in
            guard let id = item.id else { return false }
            return selectedItemIds.contains(id)
        }
    }

    // MARK: - Body

    var body: some View {
        SharedItemsList(
            mode: .embedded(items: projectContext.items, onItemPress: { _ in }),
            getMenuItems: { singleItemMenuItems(for: $0) },
            emptyMessage: "No items in this project",
            onAdd: { showNewItem = true },
            getBulkMenuItems: { bulkActionMenuItems },
            selectedIds: $selectedItemIds,
            useNavigationLinks: true,
            emptyIcon: "cube.box"
        )
        .sheet(isPresented: $showBulkStatusPicker) {
            StatusPickerModal { status in updateStatusForSelected(status) }
                .sheetStyle(.quickMenu)
        }
        .sheet(isPresented: $showBulkSetSpace) {
            SetSpaceModal(
                spaces: projectContext.spaces,
                currentSpaceId: nil,
                onSelect: { space in
                    setSpaceForSelected(spaceId: space?.id)
                }
            )
            .sheetStyle(.picker)
        }
        .sheet(isPresented: $showBulkSellToBusiness) {
            if let accountId = accountContext.currentAccountId {
                SellToBusinessModal(items: selectedItems, accountId: accountId) {
                    selectedItemIds.removeAll()
                }
                .sheetStyle(.form)
            }
        }
        .sheet(isPresented: $showBulkSellToProject) {
            if let accountId = accountContext.currentAccountId {
                SellToProjectModal(items: selectedItems, accountId: accountId) {
                    selectedItemIds.removeAll()
                }
                .sheetStyle(.form)
            }
        }
        .sheet(isPresented: $showBulkReassign) {
            ReassignToProjectModal(items: selectedItems) { selectedItemIds.removeAll() }
                .sheetStyle(.form)
        }
        .confirmationDialog("Delete \(selectedItemIds.count) items?", isPresented: $showBulkDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteSelected() }
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $showNewItem) {
            if let projectId = projectContext.currentProjectId {
                NewItemView(context: .project(projectId, spaceId: nil))
                    .sheetStyle(.form)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .createItem)) { _ in
            showNewItem = true
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
            ActionMenuItem(id: "sell-business", label: "Sell to Business", icon: "building.2",
                           onPress: { showBulkSellToBusiness = true }),
            ActionMenuItem(id: "sell-project", label: "Sell to Project", icon: "arrow.right.square",
                           onPress: { showBulkSellToProject = true }),
            ActionMenuItem(id: "reassign", label: "Reassign", icon: "arrow.triangle.2.circlepath",
                           onPress: { showBulkReassign = true }),
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
