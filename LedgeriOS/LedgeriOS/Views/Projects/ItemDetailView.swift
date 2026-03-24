import FirebaseFirestore
import SwiftUI

struct ItemDetailView: View {
    let item: Item

    @Environment(ProjectContext.self) private var projectContext
    @Environment(AccountContext.self) private var accountContext
    @Environment(MediaService.self) private var mediaService
    @Environment(\.dismiss) private var dismiss

    // Collapsible section state
    @State private var isMediaExpanded = true
    @State private var isNotesExpanded = false
    @State private var isDetailsExpanded = false

    // Live document subscription
    @State private var liveItemData: Item?
    @State private var itemListener: ListenerRegistration?

    // Modal presentation
    @State private var showActionMenu = false
    @State private var showEditDetails = false
    @State private var showEditNotes = false
    @State private var showSetSpace = false
    @State private var showReassign = false
    @State private var showSellToBusiness = false
    @State private var showSellToProject = false
    @State private var showTransactionPicker = false
    @State private var showReturnTransactionPicker = false
    @State private var showMakeCopies = false
    @State private var showStatusPicker = false
    @State private var showDeleteConfirmation = false

    // Sheet-on-sheet sequencing
    @State private var menuPendingAction: (() -> Void)?

    // Image pinning
    @State private var pinnedAttachment: AttachmentRef?

    // MARK: - Computed

    private var liveItem: Item { liveItemData ?? item }

    var body: some View {
        PinnedImageLayout(
            pinnedAttachment: pinnedAttachment,
            allImages: (liveItem.images ?? []).filter { $0.kind == .image },
            onClose: { pinnedAttachment = nil },
            onChangeImage: { pinnedAttachment = $0 }
        ) {
            ScrollView {
                AdaptiveContentWidth {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        heroCard
                        sectionsArea
                    }
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.vertical, Spacing.sm)
                }
            }
        }
        .background(BrandColors.background)
        .toolbar {
            ToolbarItem(placement: .trailingNavBar) {
                dispositionButton
            }
            ToolbarItem(placement: .trailingNavBar) {
                bookmarkButton
            }
            ToolbarItem(placement: .trailingNavBar) {
                menuButton
            }
        }
        // Action menu sheet
        .adaptivePresentation(isPresented: $showActionMenu, style: .selectionMenu, onDismiss: {
            menuPendingAction?()
            menuPendingAction = nil
        }) {
            ActionMenuSheet(
                title: liveItem.displayName.isEmpty ? "Item" : liveItem.displayName,
                items: actionMenuItems,
                onSelectAction: { action in menuPendingAction = action }
            )
        }
        // Edit Details
        .adaptivePresentation(isPresented: $showEditDetails, style: .form) {
            EditItemDetailsModal(item: liveItem) { fields in
                updateItem(fields: fields)
            }
        }
        // Edit Notes
        .adaptivePresentation(isPresented: $showEditNotes, style: .form) {
            EditNotesModal(notes: liveItem.notes ?? "") { newNotes in
                updateItem(fields: ["notes": newNotes])
            }
        }
        // Set Space
        .adaptivePresentation(isPresented: $showSetSpace, style: .picker) {
            SetSpaceModal(
                spaces: projectContext.spaces,
                currentSpaceId: liveItem.spaceId,
                onSelect: { space in
                    let fields: [String: Any] = space != nil ? ["spaceId": space!.id ?? ""] : ["spaceId": NSNull()]
                    updateItem(fields: fields)
                }
            )
        }
        // Reassign
        .adaptivePresentation(isPresented: $showReassign, style: .form) {
            ReassignToProjectModal(items: [liveItem]) { }
        }
        // Sell to Business
        .adaptivePresentation(isPresented: $showSellToBusiness, style: .form) {
            if let accountId = accountContext.currentAccountId {
                SellToBusinessModal(items: [liveItem], accountId: accountId) {
                    dismiss()
                }
            }
        }
        // Sell to Project
        .adaptivePresentation(isPresented: $showSellToProject, style: .form) {
            if let accountId = accountContext.currentAccountId {
                SellToProjectModal(items: [liveItem], accountId: accountId) {
                    dismiss()
                }
            }
        }
        // Transaction Picker
        .adaptivePresentation(isPresented: $showTransactionPicker, style: .picker) {
            TransactionPickerModal(
                transactions: projectContext.transactions,
                selectedId: liveItem.transactionId
            ) { transaction in
                updateItem(fields: ["transactionId": transaction.id ?? ""])
            }
        }
        // Return Transaction Picker
        .adaptivePresentation(isPresented: $showReturnTransactionPicker, style: .picker) {
            ReturnTransactionPickerModal(
                transactions: projectContext.transactions,
                selectedId: liveItem.transactionId
            ) { transaction in
                guard let accountId = accountContext.currentAccountId,
                      let txId = transaction.id else { return }
                let itemSnapshot = liveItem
                let service = InventoryOperationsService()
                Task {
                    do {
                        try await service.returnToTransaction(
                            items: [itemSnapshot],
                            destinationTransactionId: txId,
                            accountId: accountId
                        )
                    } catch {
                        print("🔴 returnToTransaction failed: \(error)")
                    }
                }
            }
        }
        // Make Copies
        .adaptivePresentation(isPresented: $showMakeCopies, style: .quickMenu) {
            if let accountId = accountContext.currentAccountId {
                MakeCopiesModal(item: liveItem, accountId: accountId)
            }
        }
        // Status Picker
        .adaptivePresentation(isPresented: $showStatusPicker, style: .quickMenu) {
            StatusPickerModal(currentStatus: liveItem.status) { status in
                updateItem(fields: ["status": status.rawValue])
            }
        }
        // Delete confirmation
        .confirmationDialog("Delete Item?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteItem()
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .navigationDestination(for: Transaction.self) { transaction in
            TransactionDetailView(transaction: transaction)
        }
        .navigationDestination(for: Space.self) { space in
            SpaceDetailView(space: space)
        }
        .onAppear { startItemListener() }
        .onDisappear { itemListener?.remove() }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(liveItem.displayName.isEmpty ? "Unnamed Item" : liveItem.displayName)
                .font(Typography.h2)
                .foregroundStyle(BrandColors.textPrimary)

            heroDetailRow(label: "Budget Category", value: linkedBudgetCategoryName)
            HStack(spacing: Spacing.xs) {
                Text("Transaction:")
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textSecondary)
                if let tx = linkedTransaction {
                    NavigationLink(value: tx) {
                        Text(linkedTransactionLabel)
                            .font(Typography.small)
                            .foregroundStyle(BrandColors.primary)
                    }
                } else {
                    Text("None")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textPrimary)
                }
            }
            HStack(spacing: Spacing.xs) {
                Text("Space:")
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textSecondary)
                if let space = linkedSpace {
                    NavigationLink(value: space) {
                        Text(space.name)
                            .font(Typography.small)
                            .foregroundStyle(BrandColors.primary)
                    }
                } else {
                    Text("None")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textPrimary)
                }
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private func heroDetailRow(label: String, value: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Text("\(label):")
                .font(Typography.small)
                .foregroundStyle(BrandColors.textSecondary)
            Text(value)
                .font(Typography.small)
                .foregroundStyle(BrandColors.textPrimary)
        }
    }

    private var linkedTransactionLabel: String {
        guard let transactionId = liveItem.transactionId else { return "None" }
        guard let tx = projectContext.transactions.first(where: { $0.id == transactionId }) else {
            return "None"
        }
        let source = tx.source ?? "Transaction"
        let amount = TransactionCardCalculations.formattedAmount(
            amountCents: tx.amountCents,
            transactionType: tx.transactionType
        )
        return "\(source) - \(amount)"
    }

    private var linkedBudgetCategoryName: String {
        guard let categoryId = liveItem.budgetCategoryId else { return "None" }
        return projectContext.budgetCategories.first(where: { $0.id == categoryId })?.name ?? "None"
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

            CollapsibleSection(title: "DETAILS", isExpanded: $isDetailsExpanded) {
                detailsContent
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private var mediaContent: some View {
        MediaGallerySection(
            title: "",
            attachments: liveItem.images ?? [],
            onUploadAttachment: { data in
                try await uploadImage(data)
            },
            onRemoveAttachment: { attachment in
                removeImage(attachment)
            },
            onSetPrimary: { attachment in
                setPrimaryImage(attachment)
            },
            onPinImage: { attachment in
                pinnedAttachment = attachment
            },
            emptyStateMessage: "No images yet"
        )
        .padding(.top, Spacing.xs)
    }

    @ViewBuilder
    private var notesContent: some View {
        if let notes = liveItem.notes, !notes.isEmpty {
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

    @ViewBuilder
    private var detailsContent: some View {
        VStack(spacing: 0) {
            DetailRow(label: "Status", value: liveItem.status?.displayLabel ?? "—")
            DetailRow(label: "Space", value: spaceNameForDetails)
            DetailRow(label: "Source", value: liveItem.source ?? "—")
            DetailRow(label: "SKU", value: liveItem.sku ?? "—")
            DetailRow(label: "Purchase Price", value: liveItem.purchasePriceCents.map { CurrencyFormatting.formatCentsWithDecimals($0) } ?? "—")
            DetailRow(label: "Project Price", value: liveItem.projectPriceCents.map { CurrencyFormatting.formatCentsWithDecimals($0) } ?? "—")
            DetailRow(label: "Market Value", value: liveItem.marketValueCents.map { CurrencyFormatting.formatCentsWithDecimals($0) } ?? "—")
            if let date = liveItem.createdAt {
                DetailRow(label: "Created", value: DateFormatter.shortDate.string(from: date), showDivider: false)
            }
        }
        .padding(.top, Spacing.xs)
    }

    // MARK: - Toolbar Buttons

    private var dispositionButton: some View {
        Button {
            showStatusPicker = true
        } label: {
            Text(liveItem.status?.displayLabel ?? "No Status")
                .font(Typography.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(BrandColors.primary.opacity(0.15))
                .foregroundStyle(BrandColors.primary)
                .clipShape(Capsule())
        }
    }

    private var bookmarkButton: some View {
        Button {
            toggleBookmark()
        } label: {
            Image(systemName: liveItem.bookmark == true ? "bookmark.fill" : "bookmark")
                .foregroundStyle(liveItem.bookmark == true ? BrandColors.primary : BrandColors.textSecondary)
        }
    }

    private var menuButton: some View {
        Button {
            showActionMenu = true
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(BrandColors.textSecondary)
        }
    }

    // MARK: - Action Menu

    /// Scope derived from whether item belongs to a project or business inventory.
    private var itemScope: ItemScope {
        liveItem.projectId != nil ? .project : .inventory
    }

    private var actionMenuItems: [ActionMenuItem] {
        // Detail-specific actions first
        var items: [ActionMenuItem] = [
            ActionMenuItem(id: "edit", label: "Edit Details", icon: "pencil", onPress: {
                showEditDetails = true
            }),
            ActionMenuItem(id: "notes", label: "Edit Notes", icon: "note.text", onPress: {
                showEditNotes = true
            }),
        ]

        // Shared actions via builder (Status, Transaction, Space, Sell, Reassign, Delete)
        let hasStatus = liveItem.status != nil
        let hasTx = liveItem.transactionId != nil
        let hasSpace = liveItem.spaceId != nil
        let isReturnStatus = liveItem.status == .toReturn || liveItem.status == .returned

        items += ItemMenuBuilder.buildSingleItemMenu(
            context: .detail,
            scope: itemScope,
            callbacks: SingleItemMenuCallbacks(
                onStatusChange: { _ in showStatusPicker = true },
                onClearStatus: hasStatus ? { clearItemField("status") } : nil,
                onSetTransaction: { showTransactionPicker = true },
                onClearTransaction: hasTx ? { clearItemField("transactionId") } : nil,
                onMoveToReturnTransaction: isReturnStatus ? { showReturnTransactionPicker = true } : nil,
                onSetSpace: { showSetSpace = true },
                onClearSpace: hasSpace ? { clearItemField("spaceId") } : nil,
                onSellToBusiness: itemScope == .project ? { showSellToBusiness = true } : nil,
                onSellToProject: { showSellToProject = true },
                onReassignToInventory: itemScope == .project ? { showReassign = true } : nil,
                onReassignToProject: { showReassign = true },
                onMakeCopies: { showMakeCopies = true },
                onDelete: { showDeleteConfirmation = true }
            ),
            currentStatus: liveItem.status?.rawValue
        )

        return items
    }

    // MARK: - Helpers

    private var linkedTransaction: Transaction? {
        guard let transactionId = liveItem.transactionId else { return nil }
        return projectContext.transactions.first(where: { $0.id == transactionId })
    }

    private var linkedSpace: Space? {
        guard let spaceId = liveItem.spaceId else { return nil }
        return projectContext.spaces.first(where: { $0.id == spaceId })
    }

    private var spaceName: String {
        guard let spaceId = liveItem.spaceId else { return "None" }
        return projectContext.spaces.first(where: { $0.id == spaceId })?.name ?? "None"
    }

    private var spaceNameForDetails: String {
        guard let spaceId = liveItem.spaceId else { return "—" }
        return projectContext.spaces.first(where: { $0.id == spaceId })?.name ?? "—"
    }

    // MARK: - Image Management

    private func uploadImage(_ data: Data) async throws {
        guard let accountId = accountContext.currentAccountId,
              let itemId = item.id else { return }
        let filename = "\(UUID().uuidString).jpg"
        let path = mediaService.uploadPath(
            accountId: accountId,
            entityType: "items",
            entityId: itemId,
            filename: filename
        )

        // H7: Write placeholder first so the Firestore record survives upload failures
        var images = liveItem.images ?? []
        let isPrimary = images.isEmpty
        images.append(AttachmentRef(url: "", fileName: filename, isPrimary: isPrimary, isUploading: true))
        updateItem(fields: ["images": images.map(attachmentDict)])

        // Upload bytes (H8: MediaService retries on transient failures)
        let url = try await mediaService.uploadImage(data, path: path)

        // Replace placeholder with real URL
        var updatedImages = liveItem.images ?? []
        if let idx = updatedImages.firstIndex(where: { $0.fileName == filename }) {
            updatedImages[idx].url = url
            updatedImages[idx].isUploading = nil
        } else {
            // Listener hasn't reflected the placeholder yet — append the resolved ref directly
            updatedImages.append(AttachmentRef(url: url, fileName: filename, isPrimary: isPrimary))
        }
        updateItem(fields: ["images": updatedImages.map(attachmentDict)])
    }

    private func removeImage(_ attachment: AttachmentRef) {
        var images = liveItem.images ?? []
        images.removeAll { $0.url == attachment.url }
        updateItem(fields: ["images": images.map(attachmentDict)])
        Task {
            try? await mediaService.deleteImage(url: attachment.url)
        }
    }

    private func setPrimaryImage(_ attachment: AttachmentRef) {
        guard var images = liveItem.images else { return }
        images = images.map { img in
            var copy = img
            copy.isPrimary = (img.url == attachment.url)
            return copy
        }
        updateItem(fields: ["images": images.map(attachmentDict)])
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

    // MARK: - Actions

    private func startItemListener() {
        guard let accountId = accountContext.currentAccountId,
              let itemId = item.id else { return }
        itemListener = ItemsService()
            .subscribeToItem(accountId: accountId, itemId: itemId) { updatedItem in
                self.liveItemData = updatedItem
            }
    }

    private func clearItemField(_ fieldName: String) {
        updateItem(fields: [fieldName: NSNull()])
    }

    private func updateItem(fields: [String: Any]) {
        guard let accountId = accountContext.currentAccountId,
              let itemId = item.id else {
            print("⚠️ updateItem skipped — missing accountId or itemId")
            return
        }
        let service = ItemsService()
        Task {
            do {
                try await service.updateItem(accountId: accountId, itemId: itemId, fields: fields)
            } catch {
                print("🔴 updateItem failed: \(error)")
            }
        }
    }

    private func toggleBookmark() {
        updateItem(fields: ["bookmark": !(liveItem.bookmark ?? false)])
    }

    private func deleteItem() {
        guard let accountId = accountContext.currentAccountId,
              let itemId = item.id else { return }
        let service = ItemsService()
        Task {
            try? await service.deleteItem(accountId: accountId, itemId: itemId)
            await MainActor.run { dismiss() }
        }
    }
}

// MARK: - DateFormatter helper

private extension DateFormatter {
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
