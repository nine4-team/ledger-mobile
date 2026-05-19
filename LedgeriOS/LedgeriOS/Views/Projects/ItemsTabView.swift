import SwiftUI
import FirebaseFirestore

struct ItemsTabView: View {
    @Environment(ProjectContext.self) private var projectContext
    @Environment(AccountContext.self) private var accountContext

    @State private var selectedItemIds: Set<String> = []
    @State private var itemActions = ItemActionsController()
    @State private var selectedItemsSubtab = "items"
    @State private var protoItemsListener: ListenerRegistration?
    @State private var projectProtoItems: [ProtoItem] = []

    // Bulk action modals
    @State private var showBulkStatusPicker = false
    @State private var showBulkSetSpace = false
    @State private var showBulkReturnToInventory = false
    @State private var showBulkSellToProject = false
    @State private var showBulkReassign = false
    @State private var showBulkTransactionPicker = false
    @State private var showBulkDeleteConfirmation = false
    @State private var showNewItem = false
    @State private var showNewItemDraft = false
    @State private var showAddItemMenu = false
    @State private var menuPendingAction: (() -> Void)?

    // MARK: - Computed

    private var selectedItems: [Item] {
        projectContext.items.filter { item in
            guard let id = item.id else { return false }
            return selectedItemIds.contains(id)
        }
    }

    private var activeProjectProtoItems: [ProtoItem] {
        projectProtoItems
            .filter { $0.status == nil || $0.status == .open || $0.status == .inReview }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            itemSubtabHeader
                .frame(maxWidth: Dimensions.contentMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.sm)

            if selectedItemsSubtab == "item-drafts" {
                itemDraftsList
            } else {
                realItemsList
            }
        }
        .itemActionSheets(
            itemActions,
            spaces: projectContext.spaces,
            transactions: projectContext.transactions,
            accountId: accountContext.currentAccountId
        )
        // Bulk action sheets
        .adaptivePresentation(isPresented: $showBulkStatusPicker, style: .quickMenu) {
            StatusPickerModal { status in updateStatusForSelected(status) }
        }
        .adaptivePresentation(isPresented: $showBulkSetSpace, style: .picker) {
            SetSpaceModal(
                spaces: projectContext.spaces,
                currentSpaceId: nil,
                onSelect: { space in setSpaceForSelected(spaceId: space?.id) }
            )
        }
        .adaptivePresentation(isPresented: $showBulkTransactionPicker, style: .picker) {
            TransactionPickerModal(
                transactions: projectContext.transactions,
                selectedId: nil,
                onSelect: { tx in
                    if let txId = tx.id { setTransactionForSelected(transactionId: txId) }
                }
            )
        }
        .adaptivePresentation(isPresented: $showBulkReturnToInventory, style: .form) {
            if let accountId = accountContext.currentAccountId {
                MoveToInventoryModal(items: selectedItems, accountId: accountId) {
                    selectedItemIds.removeAll()
                }
            }
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
            if let projectId = projectContext.currentProjectId {
                NewItemView(context: .project(projectId, spaceId: nil))
            }
        }
        .adaptivePresentation(isPresented: $showNewItemDraft, style: .form) {
            if let projectId = projectContext.currentProjectId {
                ItemDraftCaptureSheet(
                    projectId: projectId,
                    projectName: projectContext.project?.name
                )
            }
        }
        .adaptivePresentation(isPresented: $showAddItemMenu, style: .quickMenu, onDismiss: {
            menuPendingAction?()
            menuPendingAction = nil
        }) {
            ActionMenuSheet(
                title: "Add Item",
                items: [
                    ActionMenuItem(id: "item-draft", label: "Item Draft", icon: "camera.badge.ellipsis", onPress: {
                        showNewItemDraft = true
                    }),
                    ActionMenuItem(id: "item", label: "Item", icon: "plus.square.fill", onPress: {
                        showNewItem = true
                    }),
                ],
                onSelectAction: { action in
                    menuPendingAction = action
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .createItem)) { _ in
            showNewItem = true
        }
        .onAppear {
            subscribeToProjectProtoItems()
        }
        .onDisappear {
            protoItemsListener?.remove()
            protoItemsListener = nil
        }
    }

    private var realItemsList: some View {
        SharedItemsList(
            mode: .embedded(items: projectContext.items, onItemPress: { _ in }),
            getMenuItems: { singleItemMenuItems(for: $0) },
            emptyMessage: "No items in this project",
            onAdd: { showAddItemMenu = true },
            getBulkMenuItems: { bulkActionMenuItems },
            selectedIds: $selectedItemIds,
            useNavigationLinks: true,
            emptyIcon: "cube.box"
        )
    }

    private var itemDraftsList: some View {
        VStack(spacing: 0) {
            draftsControlBar
                .padding(.horizontal, Spacing.screenPadding)
                .background(BrandColors.background)

            ScrollView {
                AdaptiveContentWidth {
                    VStack(alignment: .leading, spacing: 0) {
                        if activeProjectProtoItems.isEmpty {
                            ContentUnavailableView {
                                Label("No item drafts yet", systemImage: "camera.badge.ellipsis")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.xl)
                        } else {
                            LazyVStack(alignment: .leading, spacing: Spacing.cardListGap) {
                                ForEach(activeProjectProtoItems) { protoItem in
                                    ItemDraftCard(protoItem: protoItem)
                                }
                            }
                            .padding(.horizontal, Spacing.screenPadding)
                            .padding(.vertical, Spacing.sm)
                        }
                    }
                }
            }
        }
    }

    private var draftsControlBar: some View {
        AddOnlyControlBar(label: "Add item draft") {
            showNewItemDraft = true
        }
    }

    private var itemSubtabHeader: some View {
        ScrollableTabBar(
            selectedId: $selectedItemsSubtab,
            items: [
                TabBarItem(id: "item-drafts", label: "Item Drafts"),
                TabBarItem(id: "items", label: "Items"),
            ]
        )
    }

    // MARK: - Single-Item Menu

    private func singleItemMenuItems(for item: Item) -> [ActionMenuItem] {
        guard let itemId = item.id else { return [] }
        return itemActions.buildMenu(
            for: item,
            scope: .project,
            accountId: accountContext.currentAccountId,
            onSelect: { selectedItemIds.insert(itemId) }
        )
    }

    // MARK: - Bulk Menu

    private var bulkActionMenuItems: [ActionMenuItem] {
        ItemMenuBuilder.buildBulkMenu(
            scope: .project,
            callbacks: BulkItemMenuCallbacks(
                onStatusChange: { _ in showBulkStatusPicker = true },
                onSetTransaction: { showBulkTransactionPicker = true },
                onClearTransaction: { clearTransactionForSelected() },
                onSetSpace: { showBulkSetSpace = true },
                onClearSpace: { clearSpaceForSelected() },
                onReturnToInventory: { showBulkReturnToInventory = true },
                onSellToProject: { showBulkSellToProject = true },
                onReassignToProject: { showBulkReassign = true },
                onCopyIDs: { Clipboard.copyLines(selectedItemIds) },
                onDelete: { showBulkDeleteConfirmation = true }
            )
        )
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

    private func subscribeToProjectProtoItems() {
        guard let accountId = accountContext.currentAccountId,
              let projectId = projectContext.currentProjectId else { return }
        protoItemsListener?.remove()
        protoItemsListener = ProtoItemsService()
            .subscribeToProtoItems(accountId: accountId, scope: .project(projectId)) { protoItems in
                projectProtoItems = protoItems
            }
    }
}
