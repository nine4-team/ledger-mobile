import FirebaseFirestore
import SwiftUI

struct ItemDetailView: View {
    let item: Item

    @Environment(ProjectContext.self) private var projectContext
    @Environment(AccountContext.self) private var accountContext
    @Environment(MediaService.self) private var mediaService
    @Environment(FindStateManager.self) private var findState
    @Environment(\.dismiss) private var dismiss

    // Collapsible section state
    @State private var isMediaExpanded = true
    @State private var isNotesExpanded = true
    @State private var isDetailsExpanded = true

    // Live document subscription
    @State private var liveItemData: Item?
    @State private var itemListener: ListenerRegistration?

    // Modal presentation
    @State private var showActionMenu = false
    @State private var showEditDetails = false
    @State private var showEditNotes = false
    @State private var showSetSpace = false
    @State private var showReassign = false
    @State private var showReturnToInventory = false
    @State private var showSellToProject = false
    @State private var showTransactionPicker = false
    @State private var showReturnTransactionPicker = false
    @State private var showMakeCopies = false
    @State private var showStatusPicker = false
    @State private var showDeleteConfirmation = false
    @State private var showRenameItem = false

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
            ScrollViewReader { proxy in
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
                .onReceive(findState.scrollToPublisher) { matchID in
                    withAnimation { proxy.scrollTo(matchID, anchor: .center) }
                }
            }
        }
        .findEntity(id: item.id)
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
        // Rename Item
        .adaptivePresentation(isPresented: $showRenameItem, style: .picker) {
            RenameItemModal(currentName: liveItem.displayName) { newName in
                updateItem(fields: ["name": newName])
            }
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
        // Move to Inventory (origin-aware: Return or Sale)
        .adaptivePresentation(isPresented: $showReturnToInventory, style: .form) {
            if let accountId = accountContext.currentAccountId {
                MoveToInventoryModal(items: [liveItem], accountId: accountId) {
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
            HStack {
                FindableText(liveItem.displayName.isEmpty ? "Unnamed Item" : liveItem.displayName)
                    .font(Typography.h2)
                    .foregroundStyle(BrandColors.textPrimary)
                Spacer()
                Button { showRenameItem = true } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(BrandColors.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rename item")
            }

            heroDetailRow(label: "Project", value: linkedProjectName)
            HStack(spacing: Spacing.xs) {
                Text("Transaction:")
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textSecondary)
                if let tx = linkedTransaction {
                    NavigationLink(value: tx) {
                        FindableText(linkedTransactionLabel)
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
                        FindableText(space.name)
                            .font(Typography.small)
                            .foregroundStyle(BrandColors.primary)
                    }
                } else {
                    Text("None")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textPrimary)
                }
            }
            heroDetailRow(label: "Purchaser", value: purchaserLabel)
            heroDetailRow(label: "Budget Category", value: linkedBudgetCategoryName)
        }
        .cardStyle()
    }

    @ViewBuilder
    private func heroDetailRow(label: String, value: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Text("\(label):")
                .font(Typography.small)
                .foregroundStyle(BrandColors.textSecondary)
            FindableText(value)
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

    private var linkedProjectName: String {
        if let projectId = liveItem.projectId {
            // Check current project context first
            if projectContext.project?.id == projectId {
                return projectContext.project?.name ?? "Unknown Project"
            }
            // Fall back to account-level project list
            return accountContext.allProjects.first(where: { $0.id == projectId })?.name ?? "Unknown Project"
        }
        return "Inventory"
    }

    private var linkedBudgetCategoryName: String {
        guard let categoryId = liveItem.budgetCategoryId else { return "None" }
        return projectContext.budgetCategories.first(where: { $0.id == categoryId })?.name ?? "None"
    }

    private var purchaserLabel: String {
        let raw = liveItem.purchasedBy?.trimmingCharacters(in: .whitespaces) ?? ""
        if raw.isEmpty {
            return liveItem.projectId == nil ? "Business" : "Client"
        }
        return raw.lowercased().contains("business") ? "Business" : "Client"
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
                title: "DETAILS",
                isExpanded: $isDetailsExpanded,
                onEdit: { showEditDetails = true }
            ) {
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
            sourceImages: linkedTransactionImages,
            sourceImagesTitle: "Transaction Images",
            onAddSourceImages: { attachments in
                addImagesFromTransaction(attachments)
            },
            onRemoveAttachment: { attachment in
                removeImage(attachment)
            },
            onSetPrimary: { attachment in
                setPrimaryImage(attachment)
            },
            onPinImage: { attachment in
                pinnedAttachment = attachment
            }
        )
        .padding(.top, Spacing.xs)
    }

    @ViewBuilder
    private var notesContent: some View {
        NotesContent(notes: liveItem.notes)
            .padding(.top, Spacing.xs)
    }

    private var derivedBillingLabel: String {
        guard let id = liveItem.id else { return "Unbilled" }
        if let status = firstNonVoidedInvoiceStatus(forItemId: id, in: accountContext.allInvoices) {
            return status.displayLabel
        }
        return "Unbilled"
    }

    @ViewBuilder
    private var detailsContent: some View {
        VStack(spacing: 0) {
            DetailRow(label: "Status", value: liveItem.status?.displayLabel ?? "—")
            DetailRow(label: "Billing", value: derivedBillingLabel)
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
        // Edit Details, Edit Notes, and Status each have dedicated affordances
        // (Details pencil, Notes pencil, toolbar status capsule) — the kebab
        // is reserved for Make Copies, relational actions, and Delete.
        let hasTx = liveItem.transactionId != nil
        let hasSpace = liveItem.spaceId != nil
        return ItemMenuBuilder.buildSingleItemMenu(
            context: .detail,
            scope: itemScope,
            callbacks: SingleItemMenuCallbacks(
                onSetTransaction: { showTransactionPicker = true },
                onClearTransaction: hasTx ? { clearItemField("transactionId") } : nil,
                onMoveToReturnTransaction: { showReturnTransactionPicker = true },
                onSetSpace: { showSetSpace = true },
                onClearSpace: hasSpace ? { clearItemField("spaceId") } : nil,
                onReturnToInventory: itemScope == .project ? { showReturnToInventory = true } : nil,
                onSellToProject: { showSellToProject = true },
                onReassignToProject: { showReassign = true },
                onMakeCopies: { showMakeCopies = true },
                onCopyID: liveItem.id.map { id in { Clipboard.copy(id) } },
                onDelete: { showDeleteConfirmation = true }
            ),
            currentStatus: liveItem.status?.rawValue
        )
    }

    // MARK: - Helpers

    private var linkedTransaction: Transaction? {
        guard let transactionId = liveItem.transactionId else { return nil }
        return projectContext.transactions.first(where: { $0.id == transactionId })
    }

    private var linkedTransactionImages: [AttachmentRef] {
        guard let linkedTransaction else { return [] }
        var seenUrls = Set<String>()
        return ((linkedTransaction.receiptImages ?? [])
            + (linkedTransaction.otherImages ?? []))
            .compactMap { attachment in
                guard attachment.kind == .image,
                      !attachment.url.isEmpty,
                      seenUrls.insert(attachment.url).inserted else {
                    return nil
                }
                return attachment
            }
    }

    private var linkedSpace: Space? {
        guard let spaceId = liveItem.spaceId else { return nil }
        return projectContext.spaces.first(where: { $0.id == spaceId })
    }

    private var spaceName: String {
        guard let spaceId = liveItem.spaceId else { return "None" }
        return projectContext.spaces.first(where: { $0.id == spaceId })?.name ?? "None"
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

    private func addImagesFromTransaction(_ attachments: [AttachmentRef]) {
        guard !attachments.isEmpty else { return }

        var images = liveItem.images ?? []
        var existingUrls = Set(images.map(\.url))
        var shouldMarkPrimary = !images.contains { $0.isPrimary == true }

        for attachment in attachments where !existingUrls.contains(attachment.url) {
            var copy = attachment
            copy.kind = .image
            copy.isUploading = nil
            copy.isPrimary = shouldMarkPrimary
            shouldMarkPrimary = false
            images.append(copy)
            existingUrls.insert(attachment.url)
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
        if let thumbnailUrlSm = ref.thumbnailUrlSm { dict["thumbnailUrlSm"] = thumbnailUrlSm }
        if let thumbnailUrlMd = ref.thumbnailUrlMd { dict["thumbnailUrlMd"] = thumbnailUrlMd }
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
        nonisolated(unsafe) let f = fields
        Task {
            do {
                try await service.updateItem(accountId: accountId, itemId: itemId, fields: f)
            } catch {
                print("🔴 updateItem failed: \(error)")
            }
        }
    }

    private func toggleBookmark() {
        updateItem(fields: ["bookmark": !(liveItem.bookmark ?? false)])
    }

    private func deleteItem() {
        guard let accountId = accountContext.currentAccountId else { return }
        let service = ItemsService()
        Task {
            try? await service.deleteItem(accountId: accountId, item: item)
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
