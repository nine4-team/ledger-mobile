import SwiftUI
import FirebaseFirestore

struct ItemsTabView: View {
    @Environment(ProjectContext.self) private var projectContext
    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager
    @Environment(MediaService.self) private var mediaService

    @State private var selectedItemIds: Set<String> = []
    @State private var itemActions = ItemActionsController()
    @State private var expandedSections: Set<String> = ["item-drafts", "items"]
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
    @State private var showBulkActionMenu = false
    @State private var showNewItem = false
    @State private var showNewItemDraft = false
    @State private var showAddItemMenu = false
    @State private var selectedProtoItem: ProtoItem?
    @State private var protoItemPendingDelete: ProtoItem?
    @State private var protoItemPendingConvert: ProtoItem?
    @State private var protoItemPendingMerge: ProtoItem?
    @State private var protoItemToast: (id: String, message: String)?
    @State private var protoItemToastTask: Task<Void, Never>?
    @State private var menuPendingAction: (() -> Void)?

    // MARK: - Computed

    private var selectedItems: [Item] {
        projectContext.items.filter { item in
            guard let id = item.id else { return false }
            return selectedItemIds.contains(id)
        }
    }

    private var selectedTotalCents: Int? {
        let pairs = projectContext.items.compactMap { item -> (id: String, cents: Int)? in
            guard let id = item.id, let cents = item.projectPriceCents ?? item.purchasePriceCents else { return nil }
            return (id: id, cents: cents)
        }
        let total = SelectionCalculations.totalCentsForSelected(selectedIds: selectedItemIds, items: pairs)
        return total > 0 ? total : nil
    }

    private var activeProjectProtoItems: [ProtoItem] {
        projectProtoItems
            .filter { $0.status == nil || $0.status == .open || $0.status == .inReview }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            AdaptiveContentWidth {
                LazyVStack(spacing: Spacing.md, pinnedViews: [.sectionHeaders]) {
                    itemDraftsSection
                    itemsSection
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.vertical, Spacing.lg)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !selectedItemIds.isEmpty {
                BulkSelectionBar(
                    selectedCount: selectedItemIds.count,
                    totalCents: selectedTotalCents,
                    onBulkActions: { showBulkActionMenu = true },
                    onClear: { selectedItemIds.removeAll() }
                )
            }
        }
        .adaptivePresentation(isPresented: $showBulkActionMenu, style: .quickMenu) {
            ActionMenuSheet(
                title: "\(selectedItemIds.count) selected",
                items: bulkActionMenuItems + [
                    ActionMenuItem(id: "clear-selection", label: "Clear Selection", icon: "xmark.circle", onPress: {
                        selectedItemIds.removeAll()
                    })
                ]
            )
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
                    ActionMenuItem(id: "item-draft", label: "Item Quick Draft", icon: "camera.badge.ellipsis", onPress: {
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
        .adaptivePresentation(item: $protoItemPendingConvert, style: .form) { protoItem in
            NewItemView(
                context: protoItem.projectId.map { .project($0, spaceId: nil) } ?? .inventory,
                initialTransactionId: protoItem.transactionId,
                initialName: protoItem.name,
                initialImageRefs: protoItem.photos ?? [],
                onCreated: { itemIds in
                    if let itemId = itemIds.first {
                        Task { await convertProtoItem(protoItem, itemId: itemId) }
                    }
                }
            )
        }
        .adaptivePresentation(item: $protoItemPendingMerge, style: .fullSheet) { protoItem in
            ItemQuickDraftMergePicker(
                protoItem: protoItem,
                items: dedupeItems(projectContext.items + accountContext.allItems),
                onMerge: { item in
                    Task { await mergeProtoItem(protoItem, into: item) }
                }
            )
        }
        .navigationDestination(item: $selectedProtoItem) { protoItem in
            ItemQuickDraftDetailView(protoItem: protoItem)
        }
        .confirmationDialog(
            "Delete Item Quick Draft?",
            isPresented: Binding(
                get: { protoItemPendingDelete != nil },
                set: { if !$0 { protoItemPendingDelete = nil } }
            )
        ) {
            Button("Delete Draft", role: .destructive) {
                if let protoItem = protoItemPendingDelete {
                    Task { await deleteProtoItem(protoItem) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the draft and its media. This cannot be undone.")
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
            protoItemToastTask?.cancel()
            protoItemToastTask = nil
        }
    }

    private var itemDraftsSection: some View {
        CollapsibleSection(
            title: "Item Quick Drafts",
            isExpanded: sectionBinding("item-drafts"),
            badge: "\(activeProjectProtoItems.count)",
            onAdd: { showNewItemDraft = true }
        ) {
            VStack(alignment: .leading, spacing: Spacing.cardListGap) {
                if activeProjectProtoItems.isEmpty {
                    ContentUnavailableView {
                        Label("No item quick drafts yet", systemImage: "camera.badge.ellipsis")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xl)
                } else {
                    ForEach(activeProjectProtoItems) { protoItem in
                        ItemDraftCard(
                            protoItem: protoItem,
                            onOpen: { selectedProtoItem = protoItem },
                            onConvert: { protoItemPendingConvert = protoItem },
                            onMerge: { protoItemPendingMerge = protoItem },
                            toastMessage: protoItem.id == protoItemToast?.id ? protoItemToast?.message : nil,
                            onToggleFromInventory: { toggleFromInventory(protoItem) },
                            onDelete: { protoItemPendingDelete = protoItem }
                        )
                    }
                }
            }
            .padding(.top, Spacing.xs)
        }
    }

    @ViewBuilder
    private var itemsSection: some View {
        if expandedSections.contains("items") {
            SharedItemsList(
                mode: .embedded(items: projectContext.items, onItemPress: { _ in }),
                getMenuItems: { singleItemMenuItems(for: $0) },
                emptyMessage: "No items in this project",
                onAdd: { showAddItemMenu = true },
                getBulkMenuItems: { bulkActionMenuItems },
                selectedIds: $selectedItemIds,
                useNavigationLinks: true,
                emptyIcon: "cube.box",
                filterScope: .project,
                inline: true,
                inlineSectionHeader: AnyView(itemsSectionHeader)
            )
        } else {
            itemsSectionHeader
        }
    }

    private var itemsSectionHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                sectionBinding("items").wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(BrandColors.textTertiary)
                    .rotationEffect(.degrees(expandedSections.contains("items") ? 90 : 0))
                    .animation(.easeInOut(duration: 0.25), value: expandedSections.contains("items"))
                Text("Items")
                    .sectionLabelStyle()
                Text("\(projectContext.items.count)")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.primary)
                Spacer()
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(BrandColors.background
            .padding(.horizontal, -Spacing.screenPadding))
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

    private func sectionBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(key) },
            set: { isExpanded in
                if isExpanded {
                    expandedSections.insert(key)
                } else {
                    expandedSections.remove(key)
                }
            }
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

    private func toggleFromInventory(_ protoItem: ProtoItem) {
        guard let accountId = accountContext.currentAccountId,
              let protoItemId = protoItem.id else { return }
        let isRemoving = protoItem.sourceHint == .fromInventory
        showProtoItemToast(
            protoItemId: protoItemId,
            message: isRemoving ? "Removed \"From Inventory\" Marker." : "Marked \"From Inventory\""
        )
        let nextValue = isRemoving
            ? ProtoItemSourceHint.unknown.rawValue
            : ProtoItemSourceHint.fromInventory.rawValue
        Task {
            do {
                try await ProtoItemsService().updateProtoItem(
                    accountId: accountId,
                    protoItemId: protoItemId,
                    fields: ["sourceHint": nextValue]
                )
            } catch {
                // Keep the capture flow light; failed writes leave the current state unchanged.
            }
        }
    }

    private func showProtoItemToast(protoItemId: String, message: String) {
        protoItemToastTask?.cancel()
        protoItemToast = (protoItemId, message)
        protoItemToastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled {
                protoItemToast = nil
            }
        }
    }

    private func mergeProtoItem(_ protoItem: ProtoItem, into item: Item) async {
        guard let accountId = accountContext.currentAccountId,
              protoItem.id != nil,
              let itemId = item.id else { return }
        let mergedImages = mergeAttachments(existing: item.images ?? [], incoming: protoItem.photos ?? [])
        try? await ItemsService().updateItem(
            accountId: accountId,
            itemId: itemId,
            fields: ["images": mergedImages.map(attachmentDict)]
        )
        await convertProtoItem(protoItem, itemId: itemId)
        protoItemPendingMerge = nil
    }

    private func convertProtoItem(_ protoItem: ProtoItem, itemId: String) async {
        guard let accountId = accountContext.currentAccountId,
              let protoItemId = protoItem.id else { return }
        try? await ProtoItemsService().convertProtoItem(
            accountId: accountId,
            protoItemId: protoItemId,
            convertedItemId: itemId,
            userId: authManager.currentUser?.uid
        )
        protoItemPendingConvert = nil
    }

    private func deleteProtoItem(_ protoItem: ProtoItem) async {
        guard let accountId = accountContext.currentAccountId,
              let protoItemId = protoItem.id else { return }
        try? await ProtoItemsService().deleteProtoItem(accountId: accountId, protoItemId: protoItemId)
        for photo in protoItem.photos ?? [] where !photo.url.isEmpty {
            try? await mediaService.deleteImage(url: photo.url)
        }
        protoItemPendingDelete = nil
    }

    private func attachmentDict(_ ref: AttachmentRef) -> [String: Any] {
        var dict: [String: Any] = [
            "url": ref.url,
            "kind": ref.kind.rawValue,
        ]
        if let thumbnailUrlSm = ref.thumbnailUrlSm { dict["thumbnailUrlSm"] = thumbnailUrlSm }
        if let thumbnailUrlMd = ref.thumbnailUrlMd { dict["thumbnailUrlMd"] = thumbnailUrlMd }
        if let fileName = ref.fileName { dict["fileName"] = fileName }
        if let contentType = ref.contentType { dict["contentType"] = contentType }
        if let isPrimary = ref.isPrimary { dict["isPrimary"] = isPrimary }
        if let isUploading = ref.isUploading { dict["isUploading"] = isUploading }
        return dict
    }

}
