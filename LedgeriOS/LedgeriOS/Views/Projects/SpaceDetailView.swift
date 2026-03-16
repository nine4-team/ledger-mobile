import FirebaseFirestore
import SwiftUI

struct SpaceDetailView: View {
    let space: Space

    @Environment(ProjectContext.self) private var projectContext
    @Environment(AccountContext.self) private var accountContext
    @Environment(MediaService.self) private var mediaService
    @Environment(\.dismiss) private var dismiss

    // Collapsible section state (Media expanded by default, others collapsed)
    @State private var isMediaExpanded = true
    @State private var isNotesExpanded = false
    @State private var isItemsExpanded = false
    @State private var isChecklistsExpanded = false

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
    // Single-item actions (from item kebab within space)
    @State private var actionTargetItem: Item?
    @State private var showItemStatusPicker = false
    @State private var showItemSetSpace = false
    @State private var showItemTransactionPicker = false
    @State private var showItemSellToBusiness = false
    @State private var showItemSellToProject = false
    @State private var showItemReassign = false
    @State private var showItemDeleteConfirmation = false

    // Live document subscription
    @State private var liveSpaceData: Space?
    @State private var spaceListener: ListenerRegistration?

    // MARK: - Computed

    private var liveSpace: Space {
        liveSpaceData ?? space
    }

    private var spaceItems: [Item] {
        projectContext.items.filter { $0.spaceId == space.id }
    }

    private var canSaveAsTemplate: Bool {
        guard let member = accountContext.member else { return false }
        return member.role == .owner || member.role == .admin
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            AdaptiveContentWidth {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    sectionsArea
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.vertical, Spacing.sm)
            }
        }
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
                projectId: projectContext.project?.id,
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
        // Item action sheets (from item kebab within space)
        .adaptivePresentation(isPresented: $showItemStatusPicker, style: .quickMenu) {
            StatusPickerModal(currentStatus: actionTargetItem?.status) { status in
                updateItemField(actionTargetItem, fields: ["status": status])
            }
        }
        .adaptivePresentation(isPresented: $showItemSetSpace, style: .picker) {
            SetSpaceModal(
                spaces: projectContext.spaces,
                currentSpaceId: actionTargetItem?.spaceId,
                onSelect: { s in
                    let fields: [String: Any] = s?.id != nil ? ["spaceId": s!.id!] : ["spaceId": NSNull()]
                    updateItemField(actionTargetItem, fields: fields)
                }
            )
        }
        .adaptivePresentation(isPresented: $showItemTransactionPicker, style: .picker) {
            TransactionPickerModal(
                transactions: projectContext.transactions,
                selectedId: actionTargetItem?.transactionId,
                onSelect: { tx in
                    if let txId = tx.id {
                        updateItemField(actionTargetItem, fields: ["transactionId": txId])
                    }
                }
            )
        }
        .adaptivePresentation(isPresented: $showItemSellToBusiness, style: .form) {
            if let accountId = accountContext.currentAccountId, let item = actionTargetItem {
                SellToBusinessModal(items: [item], accountId: accountId) {}
            }
        }
        .adaptivePresentation(isPresented: $showItemSellToProject, style: .form) {
            if let accountId = accountContext.currentAccountId, let item = actionTargetItem {
                SellToProjectModal(items: [item], accountId: accountId) {}
            }
        }
        .adaptivePresentation(isPresented: $showItemReassign, style: .form) {
            if let item = actionTargetItem {
                ReassignToProjectModal(items: [item]) {}
            }
        }
        .confirmationDialog("Delete item?", isPresented: $showItemDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteActionTargetItem() }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .navigationDestination(for: Item.self) { item in
            ItemDetailView(item: item)
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
            },
            emptyStateMessage: "No images yet"
        )
        .padding(.top, Spacing.xs)
    }

    // MARK: - Notes

    @ViewBuilder
    private var notesContent: some View {
        if let notes = liveSpace.notes, !notes.isEmpty {
            Text(notes)
                .font(Typography.body)
                .foregroundStyle(BrandColors.textPrimary)
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
            mode: .embedded(items: spaceItems, onItemPress: { _ in }),
            getMenuItems: { spaceItemMenuItems(for: $0) },
            emptyMessage: "No items in this space",
            onAdd: { showAddExistingItems = true },
            useNavigationLinks: true,
            filterScope: .spaceDetail,
            inline: true
        )
        .padding(.top, Spacing.xs)
    }

    private func spaceItemMenuItems(for item: Item) -> [ActionMenuItem] {
        guard item.id != nil else { return [] }
        return ItemMenuBuilder.buildSingleItemMenu(
            context: .space,
            scope: .project,
            callbacks: SingleItemMenuCallbacks(
                onStatusChange: { _ in actionTargetItem = item; showItemStatusPicker = true },
                onSetTransaction: { actionTargetItem = item; showItemTransactionPicker = true },
                onClearTransaction: { updateItemField(item, fields: ["transactionId": NSNull()]) },
                onSetSpace: { actionTargetItem = item; showItemSetSpace = true },
                onClearSpace: { updateItemField(item, fields: ["spaceId": NSNull()]) },
                onSellToBusiness: { actionTargetItem = item; showItemSellToBusiness = true },
                onSellToProject: { actionTargetItem = item; showItemSellToProject = true },
                onReassignToProject: { actionTargetItem = item; showItemReassign = true },
                onDelete: { actionTargetItem = item; showItemDeleteConfirmation = true }
            ),
            currentStatus: item.status
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
            Text(checklist.name)
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

                        Text(item.text)
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

    private func updateSpace(fields: [String: Any]) {
        guard let accountId = accountContext.currentAccountId,
              let spaceId = space.id else {
            print("⚠️ updateSpace skipped — missing accountId or spaceId")
            return
        }
        let service = SpacesService()
        Task {
            do {
                try await service.updateSpace(accountId: accountId, spaceId: spaceId, fields: fields)
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


    private func updateItemField(_ item: Item?, fields: [String: Any]) {
        guard let accountId = accountContext.currentAccountId,
              let itemId = item?.id else { return }
        let service = ItemsService()
        Task { try? await service.updateItem(accountId: accountId, itemId: itemId, fields: fields) }
    }

    private func deleteActionTargetItem() {
        guard let accountId = accountContext.currentAccountId,
              let itemId = actionTargetItem?.id else { return }
        let service = ItemsService()
        Task { try? await service.deleteItem(accountId: accountId, itemId: itemId) }
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

}
