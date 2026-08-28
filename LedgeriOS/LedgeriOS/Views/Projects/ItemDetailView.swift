import FirebaseFirestore
import SwiftUI

struct ItemDetailView: View {
    let itemId: String
    let projectId: String?
    let initialItem: Item?

    @State private var isContentReady = false

    init(itemId: String, projectId: String? = nil, initialItem: Item? = nil) {
        self.itemId = itemId
        self.projectId = projectId
        self.initialItem = initialItem
    }

    init(item: Item) {
        self.init(itemId: item.id ?? "", projectId: item.projectId, initialItem: item)
    }

    var body: some View {
        Group {
            if isContentReady {
                ItemDetailContentView(
                    itemId: itemId,
                    projectId: projectId,
                    initialItem: initialItem
                )
            } else {
                BrandColors.background
                    .ignoresSafeArea()
            }
        }
        .task {
            // Keep the large detail graph out of the navigation push transaction.
            await Task.yield()
            guard !Task.isCancelled else { return }
            isContentReady = true
        }
    }
}

private struct ItemDetailContentView: View {
    /// Route identity is the item ID. The displayed item resolves from the
    /// focused listener, then project/account context, then the initial
    /// snapshot — never from a mutable model held as route identity.
    let itemId: String
    let projectId: String?
    let initialItem: Item?

    /// Primary initializer — item detail is addressable by stable ID.
    init(itemId: String, projectId: String? = nil, initialItem: Item? = nil) {
        self.itemId = itemId
        self.projectId = projectId
        self.initialItem = initialItem
    }

    // TODO(stable-id-navigation): Temporary compatibility for call sites still
    // pushing mutable `Item` values (inventory, search, transaction detail,
    // finances). Remove once those routes migrate to stable IDs.
    init(item: Item) {
        self.init(itemId: item.id ?? "", projectId: item.projectId, initialItem: item)
    }

    @Environment(ProjectContext.self) private var projectContext
    @Environment(InventoryContext.self) private var inventoryContext
    @Environment(AccountContext.self) private var accountContext
    @Environment(MediaService.self) private var mediaService
    @Environment(FindStateManager.self) private var findState
    @Environment(\.dismiss) private var dismiss

    // Collapsible section state
    @State private var isMediaExpanded = true
    @State private var isNotesExpanded = true
    @State private var isDetailsExpanded = true
    @State private var isHistoryExpanded = true

    // Live document subscription
    @State private var liveItemData: Item?
    /// Set true only when the focused listener reports the document is gone.
    @State private var itemMissing = false
    @State private var itemListener: ListenerRegistration?
    @State private var itemListenerTracked = false
    @State private var liveTransactionData: Transaction?
    @State private var transactionListener: ListenerRegistration?
    @State private var transactionListenerTracked = false
    @State private var transactionLookupCompleted = false
    @State private var lineageEdges: [LineageEdge] = []
    @State private var lineageTransactions: [String: Transaction] = [:]
    @State private var lineageLoadTask: Task<Void, Never>?
    @State private var lineageTaskTracked = false
    @State private var lineageGeneration = UUID()
    @State private var selectedTransactionId: String?
    @State private var initialTransaction: Transaction?
    @State private var showTransactionDetail = false
    @State private var selectedSpaceId: String?
    @State private var selectedSpaceProjectId: String?
    @State private var showSpaceDetail = false

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

    /// Live item for display. Prefers the focused listener, then project /
    /// account context, then the initial snapshot. Keeps showing the last known
    /// item while the listener refreshes so edits never blank the screen.
    private var liveItem: Item {
        if let liveItemData, liveItemData.id == itemId { return liveItemData }
        if let resolved = NavigationRouteResolution.item(
            id: itemId,
            projectItems: projectContext.items,
            accountItems: accountContext.allItems
        ) {
            return resolved
        }
        return initialItem ?? Item()
    }

    private var isProjectPriceLocked: Bool {
        InvoiceLineCalculations.isProjectPriceLocked(
            itemId: itemId,
            projectId: liveItem.projectId,
            invoices: accountContext.allInvoices
        )
    }

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
        .findEntity(id: itemId)
        .background(BrandColors.background)
        .overlay {
            if itemMissing {
                ContentUnavailableView(
                    "Item Unavailable",
                    systemImage: "cube.box",
                    description: Text("This item no longer exists.")
                )
                .background(BrandColors.background)
            }
        }
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
            EditItemDetailsModal(
                item: liveItem,
                isProjectPriceLocked: isProjectPriceLocked
            ) { fields in
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
        // Sell
        .adaptivePresentation(isPresented: $showSellToProject, style: .form) {
            if let accountId = accountContext.currentAccountId {
                SellItemsModal(items: [liveItem], accountId: accountId) {
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
                guard let accountId = accountContext.currentAccountId,
                      let transactionId = transaction.id else { return }
                let item = liveItem
                Task { try? await ItemsService().setTransaction(accountId: accountId, items: [item], transactionId: transactionId) }
            }
        }
        // Return Transaction Picker
        .adaptivePresentation(isPresented: $showReturnTransactionPicker, style: .picker) {
            ReturnTransactionPickerModal(
                transactions: projectContext.transactions,
                selectedId: liveItem.transactionId
            ) { transaction in
                guard let accountId = accountContext.currentAccountId,
                      let txId = transaction.id,
                      let categoryId = transaction.budgetCategoryId else { return }
                let itemSnapshot = liveItem
                let service = InventoryOperationsService()
                Task {
                    do {
                        try await service.returnToTransaction(
                            items: [itemSnapshot],
                            destinationTransactionId: txId,
                            destinationBudgetCategoryId: categoryId,
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
        .navigationDestination(isPresented: $showTransactionDetail) {
            if let selectedTransactionId {
                TransactionDetailContainer(
                    transactionId: selectedTransactionId,
                    projectId: initialTransaction?.projectId,
                    initialTransaction: initialTransaction
                )
            } else {
                ContentUnavailableView("Transaction Unavailable", systemImage: "doc.text")
            }
        }
        .navigationDestination(isPresented: $showSpaceDetail) {
            if let selectedSpaceId,
               let space = NavigationRouteResolution.space(
                id: selectedSpaceId,
                projectSpaces: selectedSpaceProjectId == nil ? inventoryContext.spaces : projectContext.spaces,
                accountSpaces: accountContext.allSpaces
            ) {
                SpaceDetailView(space: space, projectId: selectedSpaceProjectId)
            } else {
                ContentUnavailableView("Space Unavailable", systemImage: "square.grid.2x2")
            }
        }
        .onAppear {
            NavLifecycleLog.log("ItemDetailView.onAppear itemId=\(itemId)")
            PerformanceDiagnostics.shared.setScenario("item-detail")
            PerformanceDiagnostics.shared.event("DetailAppeared", kind: "item")
            startItemListener()
            startTransactionListener(for: normalizedTransactionId)
            loadItemLineage()
        }
        .onChange(of: normalizedTransactionId) { _, transactionId in
            startTransactionListener(for: transactionId)
            loadItemLineage()
        }
        .onChange(of: liveItem.id) { _, _ in
            loadItemLineage()
        }
        .onDisappear {
            NavLifecycleLog.log("ItemDetailView.onDisappear itemId=\(itemId)")
            PerformanceDiagnostics.shared.event("DetailDisappeared", kind: "item")
            PerformanceDiagnostics.shared.setScenario("project-items")
            stopItemListener()
            stopTransactionListener()
            stopLineageTask()
        }
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
                switch transactionLinkDisplayState {
                case .linked:
                    if let tx = linkedTransaction {
                        Button {
                            openTransaction(tx)
                        } label: {
                            FindableText(linkedTransactionLabel)
                                .font(Typography.small)
                                .foregroundStyle(BrandColors.primary)
                        }
                        .buttonStyle(.plain)
                    }
                case .none:
                    Text("None")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textPrimary)
                case .loading:
                    Text("Loading...")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textPrimary)
                case .missing:
                    Text("Missing transaction")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textPrimary)
                }
            }
            HStack(spacing: Spacing.xs) {
                Text("Space:")
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textSecondary)
                if let space = linkedSpace {
                    Button {
                        if let spaceId = space.id {
                            selectedSpaceId = spaceId
                            selectedSpaceProjectId = space.projectId
                            showSpaceDetail = true
                        }
                    } label: {
                        FindableText(space.name)
                            .font(Typography.small)
                            .foregroundStyle(BrandColors.primary)
                    }
                    .buttonStyle(.plain)
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
        guard let tx = linkedTransaction else { return "None" }
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

            if lineageChain.count > 1 {
                Divider()
                    .padding(.vertical, Spacing.xs)

                CollapsibleSection(title: "HISTORY", isExpanded: $isHistoryExpanded) {
                    historyContent
                }
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private var mediaContent: some View {
        MediaGallerySection(
            title: "",
            attachments: liveItem.images ?? [],
            onUploadAttachmentFile: { upload in
                try await uploadImage(upload)
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
        if let status = firstNonCanceledInvoiceStatus(forItemId: id, in: accountContext.allInvoices) {
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
            DetailRow(label: "Project Price", value: liveItem.normalizedProjectPriceCents.map { CurrencyFormatting.formatCentsWithDecimals($0) } ?? "—")
            DetailRow(label: "Market Value", value: liveItem.marketValueCents.map { CurrencyFormatting.formatCentsWithDecimals($0) } ?? "—")
            if let date = liveItem.createdAt {
                DetailRow(label: "Created", value: DateFormatter.shortDate.string(from: date), showDivider: false)
            }
        }
        .padding(.top, Spacing.xs)
    }

    @ViewBuilder
    private var historyContent: some View {
        itemLineageChain
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
        let hasTx = normalizedTransactionId != nil
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
                onReturnToInventory: itemScope == .project && InventoryOperationsService.cameFromInventory(liveItem)
                    ? { showReturnToInventory = true }
                    : nil,
                onSellToProject: { showSellToProject = true },
                onReassignToProject: { showReassign = true },
                onMakeCopies: { showMakeCopies = true },
                onCopyID: liveItem.id.map { id in { Clipboard.copy(id) } },
                onDelete: { showDeleteConfirmation = true }
            ),
            currentStatus: liveItem.status?.rawValue,
            projectDestinationPresentation: .resolve(
                for: [liveItem],
                transactions: accountContext.allTransactions,
                projects: accountContext.allProjects
            )
        )
    }

    // MARK: - Helpers

    private var normalizedTransactionId: String? {
        ItemDetailCalculations.normalizedTransactionId(liveItem.transactionId)
    }

    private var transactionLinkDisplayState: ItemDetailCalculations.TransactionLinkDisplayState {
        ItemDetailCalculations.transactionLinkDisplayState(
            transactionId: liveItem.transactionId,
            hasResolvedTransaction: linkedTransaction != nil,
            lookupCompleted: transactionLookupCompleted
        )
    }

    private var linkedTransaction: Transaction? {
        guard let transactionId = normalizedTransactionId else { return nil }
        return (liveTransactionData?.id == transactionId ? liveTransactionData : nil)
            ?? projectContext.transactions.first(where: { $0.id == transactionId })
            ?? accountContext.allTransactions.first(where: { $0.id == transactionId })
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

    private var lineageChain: [Transaction] {
        var orderedIds: [String] = []
        var seenIds = Set<String>()

        func append(_ transactionId: String?) {
            guard let transactionId, seenIds.insert(transactionId).inserted else { return }
            orderedIds.append(transactionId)
        }

        for edge in lineageEdges {
            append(edge.fromTransactionId)
            append(edge.toTransactionId)
        }
        append(normalizedTransactionId)

        return orderedIds.compactMap { transactionId in
            resolvedLineageTransaction(for: transactionId)
        }
    }

    private func resolvedLineageTransaction(for transactionId: String) -> Transaction? {
        if liveTransactionData?.id == transactionId { return liveTransactionData }
        return lineageTransactions[transactionId]
            ?? projectContext.transactions.first(where: { $0.id == transactionId })
            ?? accountContext.allTransactions.first(where: { $0.id == transactionId })
    }

    @ViewBuilder
    private var itemLineageChain: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Lineage:")
                .font(Typography.caption)
                .foregroundStyle(BrandColors.textSecondary)
            ZStack(alignment: .trailing) {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: Spacing.xs) {
                        ForEach(Array(lineageChain.enumerated()), id: \.offset) { index, transaction in
                            if index > 0 {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10))
                                    .foregroundStyle(BrandColors.textTertiary)
                            }
                            Button {
                                openTransaction(transaction)
                            } label: {
                                Text(lineageTransactionLabel(transaction))
                                    .font(Typography.caption.weight(.medium))
                                    .foregroundStyle(BrandColors.primary)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.trailing, Spacing.lg)
                }

                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [BrandColors.surface.opacity(0), BrandColors.surface],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 28)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(BrandColors.textTertiary)
                        .frame(width: 14)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func lineageTransactionLabel(_ transaction: Transaction) -> String {
        let type = transaction.transactionType?.displayLabel ?? "Transaction"
        let source = transaction.source?.trimmingCharacters(in: .whitespacesAndNewlines)
        let amount = TransactionCardCalculations.formattedAmount(
            amountCents: transaction.amountCents,
            transactionType: transaction.transactionType
        )
        if let source, !source.isEmpty {
            return "\(type): \(source) \(amount)"
        }
        return "\(type): \(amount)"
    }

    private var linkedSpace: Space? {
        guard let spaceId = liveItem.spaceId else { return nil }
        let scopedSpaces = liveItem.projectId == nil ? inventoryContext.spaces : projectContext.spaces
        return scopedSpaces.first(where: { $0.id == spaceId })
            ?? accountContext.allSpaces.first(where: { $0.id == spaceId })
    }

    private var spaceName: String {
        guard let spaceId = liveItem.spaceId else { return "None" }
        let scopedSpaces = liveItem.projectId == nil ? inventoryContext.spaces : projectContext.spaces
        return scopedSpaces.first(where: { $0.id == spaceId })?.name
            ?? accountContext.allSpaces.first(where: { $0.id == spaceId })?.name
            ?? "None"
    }

    // MARK: - Image Management

    private func uploadImage(_ upload: AttachmentUpload) async throws {
        guard let accountId = accountContext.currentAccountId,
              !itemId.isEmpty else { return }
        let filename = upload.storageFileName
        let path = mediaService.uploadPath(
            accountId: accountId,
            entityType: "items",
            entityId: itemId,
            filename: filename
        )

        // H7: Write placeholder first so the Firestore record survives upload failures
        var images = liveItem.images ?? []
        let isPrimary = images.isEmpty
        images.append(AttachmentRef(
            url: "",
            fileName: upload.displayFileName,
            contentType: upload.contentType,
            isPrimary: isPrimary,
            isUploading: true
        ))
        updateItem(fields: ["images": images.map(attachmentDict)])

        // Upload bytes (H8: MediaService retries on transient failures)
        let url = try await mediaService.uploadData(upload.data, path: path, contentType: upload.contentType)
        let thumbnails = await mediaService.uploadThumbnails(
            for: upload.data,
            originalPath: path,
            contentType: upload.contentType
        )

        // Replace placeholder with real URL
        var updatedImages = liveItem.images ?? []
        if let idx = updatedImages.firstIndex(where: { $0.url.isEmpty && $0.fileName == upload.displayFileName }) {
            updatedImages[idx].url = url
            updatedImages[idx].thumbnailUrlSm = thumbnails.sm
            updatedImages[idx].thumbnailUrlMd = thumbnails.md
            updatedImages[idx].isUploading = nil
        } else {
            // Listener hasn't reflected the placeholder yet — append the resolved ref directly
            updatedImages.append(AttachmentRef(
                url: url,
                thumbnailUrlSm: thumbnails.sm,
                thumbnailUrlMd: thumbnails.md,
                fileName: upload.displayFileName,
                contentType: upload.contentType,
                isPrimary: isPrimary
            ))
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
        stopItemListener()
        guard let accountId = accountContext.currentAccountId,
              !itemId.isEmpty else { return }
        NavLifecycleLog.log("ItemDetailView.startItemListener itemId=\(itemId)")
        PerformanceDiagnostics.shared.event("FocusedListenerStarted", kind: "item")
        itemListener = ItemsService()
            .subscribeToItem(accountId: accountId, itemId: itemId) { updatedItem in
                PerformanceDiagnostics.shared.event("FocusedListenerValue", kind: "item")
                if let updatedItem {
                    self.liveItemData = updatedItem
                    self.itemMissing = false
                } else {
                    // Document deleted — show a non-loading unavailable state
                    // rather than spinning or holding stale content forever.
                    self.liveItemData = nil
                    self.itemMissing = true
                }
            }
        itemListenerTracked = true
        PerformanceDiagnostics.shared.adjustCounter("focused-item-listeners", delta: 1)
    }

    private func startTransactionListener(for transactionId: String?) {
        stopTransactionListener()
        liveTransactionData = nil
        transactionLookupCompleted = transactionId == nil

        guard let accountId = accountContext.currentAccountId,
              let transactionId else { return }

        PerformanceDiagnostics.shared.event("FocusedListenerStarted", kind: "transaction")
        transactionListener = TransactionsService()
            .subscribeToTransaction(accountId: accountId, transactionId: transactionId) { transaction in
                PerformanceDiagnostics.shared.event("FocusedListenerValue", kind: "transaction")
                self.liveTransactionData = transaction
                self.transactionLookupCompleted = true
            }
        transactionListenerTracked = true
        PerformanceDiagnostics.shared.adjustCounter("focused-transaction-listeners", delta: 1)
    }

    private func loadItemLineage() {
        stopLineageTask()
        guard let accountId = accountContext.currentAccountId,
              let itemId = liveItem.id else {
            lineageEdges = []
            lineageTransactions = [:]
            return
        }

        let generation = UUID()
        lineageGeneration = generation
        lineageTaskTracked = true
        PerformanceDiagnostics.shared.adjustCounter("lineage-tasks", delta: 1)
        let startedAt = DispatchTime.now().uptimeNanoseconds
        lineageLoadTask = Task {
            do {
                let edges = try await LineageEdgesService().edges(forItem: itemId, accountId: accountId)
                var transactionIds = Set<String>()
                for edge in edges {
                    if let fromTransactionId = edge.fromTransactionId {
                        transactionIds.insert(fromTransactionId)
                    }
                    if let toTransactionId = edge.toTransactionId {
                        transactionIds.insert(toTransactionId)
                    }
                }
                if let currentTransactionId = ItemDetailCalculations.normalizedTransactionId(liveItem.transactionId) {
                    transactionIds.insert(currentTransactionId)
                }

                let service = TransactionsService()
                var resolved: [String: Transaction] = [:]
                for transactionId in transactionIds {
                    if let local = resolvedLineageTransaction(for: transactionId) {
                        resolved[transactionId] = local
                    } else if let fetched = try? await service.getTransaction(accountId: accountId, transactionId: transactionId) {
                        resolved[transactionId] = fetched
                    }
                }

                guard !Task.isCancelled else { return }
                await MainActor.run {
                    lineageEdges = edges
                    lineageTransactions = resolved
                    finishLineageTask(
                        generation: generation,
                        startedAt: startedAt,
                        count: edges.count,
                        value: resolved.count
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    lineageEdges = []
                    lineageTransactions = [:]
                    finishLineageTask(
                        generation: generation,
                        startedAt: startedAt,
                        count: 0,
                        value: -1
                    )
                }
            }
        }
    }

    private func stopItemListener() {
        itemListener?.remove()
        itemListener = nil
        guard itemListenerTracked else { return }
        itemListenerTracked = false
        PerformanceDiagnostics.shared.adjustCounter("focused-item-listeners", delta: -1)
    }

    private func stopTransactionListener() {
        transactionListener?.remove()
        transactionListener = nil
        guard transactionListenerTracked else { return }
        transactionListenerTracked = false
        PerformanceDiagnostics.shared.adjustCounter("focused-transaction-listeners", delta: -1)
    }

    private func stopLineageTask() {
        lineageLoadTask?.cancel()
        lineageLoadTask = nil
        lineageGeneration = UUID()
        guard lineageTaskTracked else { return }
        lineageTaskTracked = false
        PerformanceDiagnostics.shared.adjustCounter("lineage-tasks", delta: -1)
        PerformanceDiagnostics.shared.event("LineageLoadCancelled", kind: "item-detail")
    }

    private func finishLineageTask(
        generation: UUID,
        startedAt: UInt64,
        count: Int,
        value: Int
    ) {
        guard lineageGeneration == generation else { return }
        lineageLoadTask = nil
        if lineageTaskTracked {
            lineageTaskTracked = false
            PerformanceDiagnostics.shared.adjustCounter("lineage-tasks", delta: -1)
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
        PerformanceDiagnostics.shared.duration(
            "LineageLoad",
            kind: "item-detail",
            milliseconds: elapsed,
            count: count,
            value: value
        )
    }

    private func clearItemField(_ fieldName: String) {
        updateItem(fields: [fieldName: NSNull()])
    }

    private func openTransaction(_ transaction: Transaction) {
        guard let id = transaction.id else { return }
        selectedTransactionId = id
        initialTransaction = transaction
        showTransactionDetail = true
    }

    private func updateItem(fields: [String: Any]) {
        guard let accountId = accountContext.currentAccountId,
              !itemId.isEmpty else {
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
        let itemSnapshot = liveItem
        Task {
            try? await service.deleteItem(accountId: accountId, item: itemSnapshot)
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
