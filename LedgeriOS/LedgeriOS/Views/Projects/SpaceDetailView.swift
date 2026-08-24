import FirebaseFirestore
import SwiftUI

struct SpaceDetailView: View {
    let space: Space
    /// Navigation scope is immutable route context. Do not infer it from a
    /// listener-updated document; a transient/legacy missing `projectId`
    /// would incorrectly switch a project space to inventory data.
    let projectId: String?

    init(space: Space, projectId: String? = nil) {
        self.space = space
        self.projectId = projectId ?? space.projectId
    }

    @Environment(ProjectContext.self) private var projectContext
    @Environment(InventoryContext.self) private var inventoryContext
    @Environment(AccountContext.self) private var accountContext
    @Environment(MediaService.self) private var mediaService
    @Environment(FindStateManager.self) private var findState
    @Environment(\.dismiss) private var dismiss

    // Collapsible section state (all expanded by default)
    @State private var isMediaExpanded = true
    @State private var isNotesExpanded = true
    @State private var isItemsExpanded = true
    @State private var isChecklistsExpanded = true

    // Modal presentation
    @State private var showActionMenu = false
    @State private var showEditDetails = false
    @State private var showEditNotes = false
    @State private var showEditChecklists = false
    @State private var showDeleteConfirmation = false
    @State private var menuPendingAction: (() -> Void)?
    @State private var errorMessage: String?

    // Items picker
    @State private var showAddExistingItems = false
    @State private var itemActions = ItemActionsController()
    @State private var selectedItemIds: Set<String> = []
    @State private var selectedItemId: String?
    @State private var showItemDetail = false

    // Bulk action modals
    @State private var showBulkActionMenu = false
    @State private var showBulkStatusPicker = false
    @State private var showBulkSetSpace = false
    @State private var showBulkReturnToInventory = false
    @State private var showBulkSellToProject = false
    @State private var showBulkReassign = false
    @State private var showBulkTransactionPicker = false
    @State private var showBulkDeleteConfirmation = false

    // Live document subscription
    @State private var liveSpaceData: Space?
    @State private var spaceListener: ListenerRegistration?

    // MARK: - Computed

    private var liveSpace: Space {
        liveSpaceData ?? space
    }

    private var isInventorySpace: Bool {
        projectId == nil
    }

    private var activeItems: [Item] {
        isInventorySpace ? inventoryContext.items : projectContext.items
    }

    private var activeSpaces: [Space] {
        isInventorySpace ? inventoryContext.spaces : projectContext.spaces
    }

    private var activeTransactions: [Transaction] {
        isInventorySpace ? inventoryContext.transactions : projectContext.transactions
    }

    private var itemScope: ItemScope {
        isInventorySpace ? .inventory : .project
    }

    private var spaceItems: [Item] {
        guard let spaceId = liveSpace.id else { return [] }
        return activeItems.filter { $0.spaceId == spaceId }
    }

    private var selectedItems: [Item] {
        activeItems.filter { item in
            guard let id = item.id else { return false }
            return selectedItemIds.contains(id)
        }
    }

    private var selectedItemsCanReturnToInventory: Bool {
        !selectedItems.isEmpty && selectedItems.allSatisfy {
            InventoryOperationsService.cameFromInventory($0)
        }
    }

    private var selectedTotalCents: Int? {
        let pairs = selectedItems.compactMap { item -> (id: String, cents: Int)? in
            guard let id = item.id, let cents = item.normalizedProjectPriceCents else { return nil }
            return (id: id, cents: cents)
        }
        let total = SelectionCalculations.totalCentsForSelected(selectedIds: selectedItemIds, items: pairs)
        return total > 0 ? total : nil
    }

    private var canSaveAsTemplate: Bool {
        guard let member = accountContext.member else { return false }
        return SpaceDetailCalculations.canSaveAsTemplate(userRole: member.role?.rawValue ?? "")
    }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                AdaptiveContentWidth {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        sectionsArea
                    }
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.vertical, Spacing.sm)
                }
            }
            .onReceive(findState.scrollToPublisher) { matchID in
                withAnimation { proxy.scrollTo(matchID, anchor: .center) }
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
        .findEntity(id: space.id)
        .navBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(liveSpace.name.isEmpty ? "Space" : liveSpace.name)
                    .font(Typography.h3)
                    .foregroundStyle(BrandColors.textPrimary)
                    .lineLimit(1)
            }
            ToolbarItem(placement: .trailingNavBar) {
                Button {
                    showActionMenu = true
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
        }
        .adaptivePresentation(isPresented: $showActionMenu, style: .quickMenu, onDismiss: {
            menuPendingAction?()
            menuPendingAction = nil
        }) {
            ActionMenuSheet(
                title: liveSpace.name.isEmpty ? "Space" : liveSpace.name,
                items: actionMenuItems,
                onSelectAction: { action in menuPendingAction = action }
            )
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
        .adaptivePresentation(isPresented: $showEditDetails, style: .form) {
            EditSpaceDetailsModal(space: liveSpace) { name, notes in
                updateSpace(fields: ["name": name, "notes": notes ?? NSNull()])
            }
        }
        .adaptivePresentation(isPresented: $showEditNotes, style: .form) {
            EditNotesModal(notes: liveSpace.notes ?? "") { newNotes in
                updateSpace(fields: ["notes": newNotes])
            }
        }
        .adaptivePresentation(isPresented: $showEditChecklists, style: .form) {
            EditChecklistModal(space: liveSpace) { updatedChecklists in
                saveChecklists(updatedChecklists)
            }
        }
        .adaptivePresentation(isPresented: $showAddExistingItems, style: .fullSheet) {
            AddExistingItemsPicker(
                context: .space(liveSpace),
                projectId: projectId,
                onDismiss: { showAddExistingItems = false }
            )
        }
        .confirmationDialog("Delete Space?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteSpace()
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .itemActionSheets(
            itemActions,
            spaces: activeSpaces,
            transactions: activeTransactions,
            accountId: accountContext.currentAccountId
        )
        .adaptivePresentation(isPresented: $showBulkStatusPicker, style: .quickMenu) {
            StatusPickerModal { status in updateStatusForSelected(status) }
        }
        .adaptivePresentation(isPresented: $showBulkSetSpace, style: .picker) {
            SetSpaceModal(
                spaces: activeSpaces,
                currentSpaceId: liveSpace.id,
                onSelect: { space in setSpaceForSelected(spaceId: space?.id) }
            )
        }
        .adaptivePresentation(isPresented: $showBulkTransactionPicker, style: .picker) {
            TransactionPickerModal(
                transactions: activeTransactions,
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
                SellItemsModal(items: selectedItems, accountId: accountId) {
                    selectedItemIds.removeAll()
                }
            }
        }
        .adaptivePresentation(isPresented: $showBulkReassign, style: .form) {
            ReassignToProjectModal(items: selectedItems) {
                selectedItemIds.removeAll()
            }
        }
        .confirmationDialog("Delete \(selectedItemIds.count) items?", isPresented: $showBulkDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteSelected() }
        } message: {
            Text("This action cannot be undone.")
        }
        .navigationDestination(isPresented: $showItemDetail) {
            if let selectedItemId,
               let item = activeItems.first(where: { $0.id == selectedItemId }) {
                ItemDetailView(
                    itemId: selectedItemId,
                    projectId: projectId,
                    initialItem: item
                )
            } else {
                ContentUnavailableView("Item Unavailable", systemImage: "cube.box")
            }
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task { startSpaceListener() }
        .onDisappear { spaceListener?.remove() }
        .background(BrandColors.background)
    }

    // MARK: - Collapsible Sections

    private var sectionsArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            CollapsibleSection(title: "MEDIA", isExpanded: $isMediaExpanded) {
                mediaContent
            }

            Divider()
                .padding(.vertical, Spacing.xs)

            CollapsibleSection(
                title: "NOTES",
                isExpanded: $isNotesExpanded,
                onEdit: { showEditNotes = true }
            ) {
                notesContent
            }

            Divider()
                .padding(.vertical, Spacing.xs)

            CollapsibleSection(
                title: "ITEMS",
                isExpanded: $isItemsExpanded,
                badge: "\(spaceItems.count)",
                badgeColor: BrandColors.primary
            ) {
                itemsContent
            }

            Divider()
                .padding(.vertical, Spacing.xs)

            CollapsibleSection(
                title: "CHECKLISTS",
                isExpanded: $isChecklistsExpanded,
                badge: "\(liveSpace.checklists?.count ?? 0)",
                onEdit: { showEditChecklists = true }
            ) {
                checklistsContent
            }
        }
        .cardStyle()
    }

    // MARK: - Media

    @ViewBuilder
    private var mediaContent: some View {
        MediaGallerySection(
            title: "",
            attachments: liveSpace.images ?? [],
            onUploadAttachment: { data in
                try await uploadImage(data)
            },
            onRemoveAttachment: { attachment in
                removeImage(attachment)
            },
            onSetPrimary: { attachment in
                setPrimaryImage(attachment)
            }
        )
        .padding(.top, Spacing.xs)
    }

    // MARK: - Notes

    @ViewBuilder
    private var notesContent: some View {
        if let notes = liveSpace.notes, !notes.isEmpty {
            SelectableNoteText(text: notes, style: .body)
                .padding(.top, Spacing.xs)
        } else {
            Text("No notes")
                .font(Typography.small)
                .foregroundStyle(BrandColors.textSecondary)
                .padding(.top, Spacing.xs)
        }
    }

    // MARK: - Items

    @ViewBuilder
    private var itemsContent: some View {
        SharedItemsList(
            mode: .embedded(items: spaceItems, onItemPress: { itemId in
                selectedItemId = itemId
                showItemDetail = true
            }),
            getMenuItems: { spaceItemMenuItems(for: $0) },
            emptyMessage: "No items in this space",
            onAdd: { showAddExistingItems = true },
            getBulkMenuItems: { bulkActionMenuItems },
            selectedIds: $selectedItemIds,
            filterScope: .spaceDetail,
            inline: true
        )
        .padding(.top, Spacing.xs)
    }

    private func spaceItemMenuItems(for item: Item) -> [ActionMenuItem] {
        guard let itemId = item.id else { return [] }
        return itemActions.buildMenu(
            for: item,
            scope: itemScope,
            menuContext: .space,
            accountId: accountContext.currentAccountId,
            onSelect: { selectedItemIds.insert(itemId) }
        )
    }

    // MARK: - Checklists

    @ViewBuilder
    private var checklistsContent: some View {
        let checklists = liveSpace.checklists ?? []
        if checklists.isEmpty {
            Text("No checklists")
                .font(Typography.small)
                .foregroundStyle(BrandColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, Spacing.xl)
        } else {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                ForEach(checklists) { checklist in
                    checklistView(checklist)
                }
            }
            .padding(.top, Spacing.xs)
        }
    }

    @ViewBuilder
    private func checklistView(_ checklist: Checklist) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            FindableText(checklist.name)
                .font(Typography.label)
                .foregroundStyle(BrandColors.textPrimary)

            ForEach(checklist.items) { item in
                Button {
                    toggleChecklistItem(checklistId: checklist.id, itemId: item.id)
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(item.isChecked ? BrandColors.primary : BrandColors.textTertiary)

                        FindableText(item.text)
                            .font(Typography.body)
                            .foregroundStyle(item.isChecked ? BrandColors.textSecondary : BrandColors.textPrimary)
                            .strikethrough(item.isChecked)
                    }
                }
                .buttonStyle(.plain)
            }

            if !checklist.items.isEmpty {
                let checked = checklist.items.filter(\.isChecked).count
                let total = checklist.items.count
                ProgressBar(
                    percentage: Double(checked) / Double(total) * 100,
                    fillColor: BrandColors.primary,
                    height: 4
                )
            }
        }
    }

    // MARK: - Action Menu

    private var actionMenuItems: [ActionMenuItem] {
        var items: [ActionMenuItem] = [
            ActionMenuItem(id: "edit", label: "Edit Space", icon: "pencil", onPress: {
                showEditDetails = true
            }),
            ActionMenuItem(id: "notes", label: "Edit Notes", icon: "note.text", onPress: {
                showEditNotes = true
            }),
            ActionMenuItem(id: "checklists", label: "Edit Checklists", icon: "checklist", onPress: {
                showEditChecklists = true
            }),
        ]

        if canSaveAsTemplate {
            items.append(ActionMenuItem(
                id: "template",
                label: "Save as Template",
                icon: "doc.on.doc",
                onPress: { saveAsTemplate() }
            ))
        }

        items.append(ActionMenuItem(
            id: "delete",
            label: "Delete Space",
            icon: "trash",
            isDestructive: true,
            onPress: { showDeleteConfirmation = true }
        ))

        return items
    }

    private var bulkActionMenuItems: [ActionMenuItem] {
        ItemMenuBuilder.buildBulkMenu(
            context: .space,
            scope: itemScope,
            callbacks: BulkItemMenuCallbacks(
                onStatusChange: { _ in showBulkStatusPicker = true },
                onSetTransaction: { showBulkTransactionPicker = true },
                onClearTransaction: { clearTransactionForSelected() },
                onSetSpace: { showBulkSetSpace = true },
                onClearSpace: { clearSpaceForSelected() },
                onReturnToInventory: selectedItemsCanReturnToInventory && !isInventorySpace
                    ? { showBulkReturnToInventory = true }
                    : nil,
                onSellToProject: { showBulkSellToProject = true },
                onReassignToProject: { showBulkReassign = true },
                onCopyIDs: { Clipboard.copyLines(selectedItemIds) },
                onDelete: { showBulkDeleteConfirmation = true }
            )
        )
    }

    // MARK: - Actions

    private func startSpaceListener() {
        guard spaceListener == nil,
              let accountId = accountContext.currentAccountId,
              let spaceId = space.id else { return }
        spaceListener = SpacesService()
            .subscribeToSpace(accountId: accountId, spaceId: spaceId) { updatedSpace in
                self.liveSpaceData = updatedSpace
            }
    }

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

    private func updateSpace(fields: [String: Any]) {
        guard let accountId = accountContext.currentAccountId,
              let spaceId = space.id else {
            print("⚠️ updateSpace skipped — missing accountId or spaceId")
            return
        }
        let service = SpacesService()
        nonisolated(unsafe) let f = fields
        Task {
            do {
                try await service.updateSpace(accountId: accountId, spaceId: spaceId, fields: f)
            } catch {
                print("🔴 updateSpace failed: \(error)")
            }
        }
    }

    private func saveChecklists(_ checklists: [Checklist]) {
        let encoded = checklists.map { checklist -> [String: Any] in
            [
                "id": checklist.id,
                "name": checklist.name,
                "items": checklist.items.map { item -> [String: Any] in
                    [
                        "id": item.id,
                        "text": item.text,
                        "isChecked": item.isChecked,
                    ]
                },
            ]
        }
        updateSpace(fields: ["checklists": encoded])
    }

    private func toggleChecklistItem(checklistId: String, itemId: String) {
        guard var checklists = liveSpace.checklists else { return }
        guard let ci = checklists.firstIndex(where: { $0.id == checklistId }),
              let ii = checklists[ci].items.firstIndex(where: { $0.id == itemId }) else { return }
        checklists[ci].items[ii].isChecked.toggle()
        saveChecklists(checklists)
    }

    private func uploadImage(_ data: Data) async throws {
        guard let accountId = accountContext.currentAccountId,
              let spaceId = space.id else { return }
        let filename = "\(UUID().uuidString).jpg"
        let path = mediaService.uploadPath(
            accountId: accountId,
            entityType: "spaces",
            entityId: spaceId,
            filename: filename
        )

        // H7: Write placeholder first so the Firestore record survives upload failures
        var images = liveSpace.images ?? []
        let isPrimary = images.isEmpty
        images.append(AttachmentRef(url: "", fileName: filename, isPrimary: isPrimary, isUploading: true))
        updateSpace(fields: ["images": images.map(attachmentDict)])

        // Upload bytes (H8: MediaService retries on transient failures)
        let url = try await mediaService.uploadImage(data, path: path)

        // Replace placeholder with real URL
        var updatedImages = liveSpace.images ?? []
        if let idx = updatedImages.firstIndex(where: { $0.fileName == filename }) {
            updatedImages[idx].url = url
            updatedImages[idx].isUploading = nil
        } else {
            // Listener hasn't reflected the placeholder yet — append the resolved ref directly
            updatedImages.append(AttachmentRef(url: url, fileName: filename, isPrimary: isPrimary))
        }
        updateSpace(fields: ["images": updatedImages.map(attachmentDict)])
    }

    private func removeImage(_ attachment: AttachmentRef) {
        var images = liveSpace.images ?? []
        images.removeAll { $0.url == attachment.url }
        updateSpace(fields: ["images": images.map(attachmentDict)])
        Task {
            try? await mediaService.deleteImage(url: attachment.url)
        }
    }

    private func setPrimaryImage(_ attachment: AttachmentRef) {
        guard var images = liveSpace.images else { return }
        images = images.map { img in
            var copy = img
            copy.isPrimary = (img.url == attachment.url)
            return copy
        }
        updateSpace(fields: ["images": images.map(attachmentDict)])
    }

    private func attachmentDict(_ ref: AttachmentRef) -> [String: Any] {
        var dict: [String: Any] = [
            "url": ref.url,
            "kind": ref.kind.rawValue,
        ]
        if let fileName = ref.fileName { dict["fileName"] = fileName }
        if let contentType = ref.contentType { dict["contentType"] = contentType }
        if let isPrimary = ref.isPrimary { dict["isPrimary"] = isPrimary }
        if let isUploading = ref.isUploading { dict["isUploading"] = isUploading }
        return dict
    }

    private func saveAsTemplate() {
        // SpaceTemplatesService not yet built (WP13) — show placeholder alert
        errorMessage = "Template saved! (Template service coming soon)"
    }


    private func deleteSpace() {
        guard let accountId = accountContext.currentAccountId,
              let spaceId = space.id else { return }
        let service = SpacesService()
        Task {
            do {
                try await service.deleteSpace(accountId: accountId, spaceId: spaceId)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run { errorMessage = "Failed to delete space." }
            }
        }
    }

    private func deleteSelected() {
        guard let accountId = accountContext.currentAccountId else { return }
        let service = ItemsService()
        let items = Array(selectedItems)
        Task { try? await service.deleteItems(accountId: accountId, items: items) }
        selectedItemIds.removeAll()
    }

}
