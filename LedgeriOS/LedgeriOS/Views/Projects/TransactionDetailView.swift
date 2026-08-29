import SwiftUI
import FirebaseFirestore

enum TransactionDetailScope: Hashable {
    case project(String)
    case inventory

    init(projectId: String?) {
        if let projectId {
            self = .project(projectId)
        } else {
            self = .inventory
        }
    }

    var projectId: String? {
        guard case .project(let projectId) = self else { return nil }
        return projectId
    }
}

enum TransactionDetailResolution {
    /// Resolves canonical transaction membership in `itemIds` order. Scoped
    /// collection data wins over first-paint and exceptional fallback copies.
    static func linkedItems(
        itemIds: [String]?,
        scopedItems: [Item],
        initialItems: [Item],
        externalItems: [Item],
        pendingItems: [Item]
    ) -> [Item] {
        guard let itemIds, !itemIds.isEmpty else { return [] }

        var byId: [String: Item] = [:]
        for source in [pendingItems, externalItems, initialItems, scopedItems] {
            for item in source {
                guard let id = item.id else { continue }
                byId[id] = item
            }
        }

        var seen = Set<String>()
        return itemIds.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return byId[id]
        }
    }
}

/// Establishes the collection scope required by transaction detail.
///
/// Project-origin navigation reuses its already-active ProjectContext. Search,
/// Review, and other cross-project entry points get an isolated context for the
/// transaction's project. Inventory transactions use the session InventoryContext.
struct TransactionDetailContainer: View {
    let transactionId: String
    let projectId: String?
    let initialTransaction: Transaction?

    @State private var isContentReady = false

    init(
        transactionId: String,
        projectId: String?,
        initialTransaction: Transaction? = nil
    ) {
        self.transactionId = transactionId
        self.projectId = projectId
        self.initialTransaction = initialTransaction
    }

    var body: some View {
        Group {
            if isContentReady {
                TransactionDetailContainerContent(
                    transactionId: transactionId,
                    projectId: projectId,
                    initialTransaction: initialTransaction
                )
            } else {
                BrandColors.background
                    .ignoresSafeArea()
            }
        }
        .task {
            // Keep the large detail and scoped-context graph out of the navigation push transaction.
            await Task.yield()
            guard !Task.isCancelled else { return }
            isContentReady = true
        }
    }
}

private struct TransactionDetailContainerContent: View {
    let transactionId: String
    let scope: TransactionDetailScope
    let initialTransaction: Transaction?

    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager
    @Environment(ProjectContext.self) private var ambientProjectContext
    @State private var scopedProjectContext: ProjectContext

    init(
        transactionId: String,
        projectId: String?,
        initialTransaction: Transaction? = nil
    ) {
        self.transactionId = transactionId
        self.scope = TransactionDetailScope(projectId: projectId)
        self.initialTransaction = initialTransaction

        _scopedProjectContext = State(initialValue: ProjectContext(
            projectService: ProjectService(),
            transactionsService: TransactionsService(),
            itemsService: ItemsService(),
            protoItemsService: ProtoItemsService(),
            spacesService: SpacesService(),
            projectBudgetCategoriesService: ProjectBudgetCategoriesService()
        ))
    }

    var body: some View {
        switch scope {
        case .inventory:
            detail
        case .project(let projectId):
            if ambientProjectContext.currentProjectId == projectId {
                detail
            } else {
                detail
                    .environment(scopedProjectContext)
                    .task(id: activationKey(projectId: projectId)) {
                        guard let accountId = accountContext.currentAccountId else { return }
                        scopedProjectContext.activate(
                            accountId: accountId,
                            projectId: projectId,
                            userId: authManager.currentUser?.uid,
                            member: accountContext.member,
                            rawBudgetCategories: accountContext.rawAllBudgetCategories
                        )
                    }
                    .onChange(of: accountContext.member) { _, member in
                        scopedProjectContext.updateFinancialContext(
                            member: member,
                            rawBudgetCategories: accountContext.rawAllBudgetCategories
                        )
                    }
                    .onChange(of: accountContext.rawAllBudgetCategories) { _, categories in
                        scopedProjectContext.updateFinancialContext(
                            member: accountContext.member,
                            rawBudgetCategories: categories
                        )
                    }
            }
        }
    }

    private var detail: some View {
        TransactionDetailView(
            transactionId: transactionId,
            scope: scope,
            initialTransaction: initialTransaction,
            initialItems: initialLinkedItems
        )
    }

    /// AccountContext is already live for Search/Review. These are first-paint
    /// snapshots only; the working collection remains ProjectContext or
    /// InventoryContext.
    private var initialLinkedItems: [Item] {
        guard let itemIds = initialTransaction?.itemIds, !itemIds.isEmpty else { return [] }
        let ids = Set(itemIds)
        return accountContext.allItems.filter { ids.contains($0.id ?? "") }
    }

    private func activationKey(projectId: String) -> String {
        [
            accountContext.currentAccountId ?? "",
            projectId,
            authManager.currentUser?.uid ?? "",
        ].joined(separator: "|")
    }
}

/// Full transaction detail screen with hero card, Next Steps, 8 collapsible sections,
/// and delete action.
struct TransactionDetailView: View {
    let transactionId: String
    let scope: TransactionDetailScope
    let initialTransaction: Transaction
    let initialItems: [Item]

    init(
        transactionId: String,
        scope: TransactionDetailScope,
        initialTransaction: Transaction? = nil,
        initialItems: [Item] = []
    ) {
        self.transactionId = transactionId
        self.scope = scope
        var fallback = initialTransaction ?? Transaction()
        fallback.id = transactionId
        self.initialTransaction = fallback
        self.initialItems = initialItems
    }

    @Environment(ProjectContext.self) private var projectContext
    @Environment(InventoryContext.self) private var inventoryContext
    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager
    @Environment(MediaService.self) private var mediaService
    @Environment(FindStateManager.self) private var findState
    @Environment(\.dismiss) private var dismiss

    // Section expanded states — all expanded by default
    @State private var expandedSections: Set<String> = ["receipts", "item-drafts", "notes", "details", "items", "returned-items", "sold-items", "transaction-audit"]

    // Items picker
    @State private var showAddExistingItems = false
    // Modal presentation
    @State private var showActionMenu = false
    @State private var showEditDetails = false
    @State private var showEditNotes = false
    @State private var showCreateItemsFromImages = false
    @State private var showDeleteConfirmation = false
    @State private var transactionDeletionNotice: TransactionDeletionNotice?
    @State private var showAddItemMenu = false
    @State private var showCreateNewItem = false
    @State private var showCreateItemDraft = false
    @State private var selectedProtoItem: ProtoItem?
    @State private var selectedNavigationItemId: String?
    @State private var initialNavigationItem: Item?
    @State private var showItemDetail = false
    @State private var selectedItemIds: Set<String> = []
    @State private var itemActions = ItemActionsController()
    @State private var protoItemPendingDelete: ProtoItem?
    @State private var protoItemPendingConvert: ProtoItem?
    @State private var protoItemPendingMerge: ProtoItem?
    @State private var protoItemToast: (id: String, message: String)?
    @State private var protoItemToastTask: Task<Void, Never>?
    @State private var showReassign = false
    @State private var menuPendingAction: (() -> Void)?

    // Bulk item actions
    @State private var showBulkActionMenu = false
    @State private var showBulkStatusPicker = false
    @State private var showBulkSetSpace = false
    @State private var showBulkReturnToInventory = false
    @State private var showBulkSellToProject = false
    @State private var showBulkReassign = false
    @State private var showBulkTransactionPicker = false
    @State private var showBulkDeleteConfirmation = false

    // Image pinning
    @State private var pinnedAttachment: AttachmentRef?
    @State private var pinnedImageSource: [AttachmentRef] = []

    // Lineage-based returned/sold items
    @State private var lineageReturnedItems: [Item] = []
    @State private var lineageSoldItems: [Item] = []

    // Items fetched outside project context (e.g. inventory items in project_to_business sales)
    @State private var resolvedExternalItems: [Item] = []

    // Expanded groups within returned/sold sections
    @State private var expandedReturnedGroups: Set<String> = []
    @State private var expandedSoldGroups: Set<String> = []

    // Document-level listener for this transaction (query listeners don't reliably
    // fire after updateData on an already-matching document).
    @State private var liveTransaction: Transaction?
    @State private var transactionListener: ListenerRegistration?
    @State private var protoItemsListener: ListenerRegistration?
    @State private var transactionProtoItems: [ProtoItem] = []
    @State private var pendingCreatedItems: [Item] = []

    // Enabled budget categories for THIS transaction's project, loaded on demand
    // when the ambient project context isn't the transaction's project (the
    // detail screen is reachable from Inventory, Search, and Review).
    @State private var transactionProjectBudgetCategoryRows: [ProjectBudgetCategory] = []
    @State private var budgetCategoriesListener: ListenerRegistration?

    // MARK: - Computed

    private var scopedItems: [Item] {
        switch scope {
        case .project:
            return projectContext.items
        case .inventory:
            return inventoryContext.items
        }
    }

    private var scopedTransactions: [Transaction] {
        switch scope {
        case .project:
            return projectContext.transactions
        case .inventory:
            return inventoryContext.transactions
        }
    }

    private var scopedSpaces: [Space] {
        switch scope {
        case .project:
            return projectContext.spaces
        case .inventory:
            return inventoryContext.spaces
        }
    }

    private var scopedProject: Project? {
        guard let projectId = scope.projectId else { return nil }
        if projectContext.project?.id == projectId {
            return projectContext.project
        }
        return accountContext.allProjects.first { $0.id == projectId }
    }

    private func itemScope(for item: Item) -> ItemScope {
        item.projectId == nil ? .inventory : .project
    }

    private var selectedItemsScope: ItemScope? {
        guard !selectedItems.isEmpty else { return nil }
        if selectedItems.allSatisfy({ $0.projectId == nil }) { return .inventory }
        if selectedItems.allSatisfy({ $0.projectId != nil }) { return .project }
        return nil
    }

    private var itemFilterScope: ItemFilterScope {
        switch scope {
        case .project: return .project
        case .inventory: return .inventory
        }
    }

    private var itemCreationContext: ItemCreationContext {
        if let projectId = transactionProjectId {
            return .project(projectId, spaceId: nil)
        }
        return .inventory
    }

    private var currentTransaction: Transaction {
        var tx = liveTransaction
            ?? scopedTransactions.first(where: { $0.id == transactionId })
            ?? initialTransaction
        let pendingIds = pendingCreatedItems.compactMap(\.id)
        if !pendingIds.isEmpty {
            var ids = tx.itemIds ?? []
            let existingIds = Set(ids)
            ids.append(contentsOf: pendingIds.filter { !existingIds.contains($0) })
            tx.itemIds = ids
        }
        return tx
    }

    private var transactionProjectId: String? {
        currentTransaction.projectId ?? scope.projectId
    }

    /// Raw project budget rows for the transaction's project. Detail can be
    /// opened outside that project, so fall back to the on-demand subscription.
    private var projectBudgetCategoryRows: [ProjectBudgetCategory] {
        guard let projectId = currentTransaction.projectId else { return [] }
        if projectContext.currentProjectId == projectId {
            return projectContext.projectBudgetCategories
        }
        return transactionProjectBudgetCategoryRows
    }

    /// Display/edit-ready budget categories enabled for this transaction's
    /// project. Project rows define scope; account categories provide name/type.
    private var projectBudgetCategories: [BudgetCategory] {
        guard currentTransaction.projectId != nil else {
            return accountContext.allBudgetCategories
        }
        return ProjectBudgetCategoryResolver.resolve(
            projectBudgetCategoryRows: projectBudgetCategoryRows,
            accountBudgetCategories: accountContext.allBudgetCategories
        )
    }

    private func subscribeProjectCategoriesIfNeeded() {
        budgetCategoriesListener?.remove()
        budgetCategoriesListener = nil
        transactionProjectBudgetCategoryRows = []
        guard let accountId = accountContext.currentAccountId,
              let projectId = currentTransaction.projectId,
              projectId != projectContext.currentProjectId else { return }
        budgetCategoriesListener = ProjectBudgetCategoriesService()
            .subscribeToProjectBudgetCategories(accountId: accountId, projectId: projectId) { pbc in
                transactionProjectBudgetCategoryRows = pbc
            }
    }

    private var transactionItems: [Item] {
        TransactionDetailResolution.linkedItems(
            itemIds: currentTransaction.itemIds,
            scopedItems: scopedItems,
            initialItems: initialItems,
            externalItems: resolvedExternalItems,
            pendingItems: pendingCreatedItems
        )
    }

    private var activeItems: [Item] {
        if currentTransaction.isReturnTransaction {
            return transactionItems
        }
        return transactionItems.filter { $0.status != .returned && $0.status != .sold }
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
        let pairs = activeItems.compactMap { item -> (id: String, cents: Int)? in
            guard let id = item.id, let cents = item.normalizedProjectPriceCents else { return nil }
            return (id, cents)
        }
        let total = SelectionCalculations.totalCentsForSelected(selectedIds: selectedItemIds, items: pairs)
        return total > 0 ? total : nil
    }

    private var returnedItems: [Item] { lineageReturnedItems }
    private var soldItems: [Item] { lineageSoldItems }

    private var activeTransactionProtoItems: [ProtoItem] {
        transactionProtoItems
            .filter { $0.status == nil || $0.status == .open || $0.status == .inReview }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    private var hasTransactionImages: Bool {
        !(currentTransaction.receiptImages ?? []).isEmpty
            || !(currentTransaction.otherImages ?? []).isEmpty
            || !(currentTransaction.transactionImages ?? []).isEmpty
    }

    private var categoryLookup: [String: BudgetCategory] {
        Dictionary(
            uniqueKeysWithValues: projectBudgetCategories.compactMap { cat in
                guard let id = cat.id else { return nil }
                return (id, cat)
            }
        )
    }

    private var selectedCategory: BudgetCategory? {
        currentTransaction.budgetCategoryId.flatMap { categoryLookup[$0] }
    }

    private var nextSteps: [TransactionNextStepsCalculations.NextStep] {
        TransactionNextStepsCalculations.computeNextSteps(
            transaction: currentTransaction,
            itemCount: transactionItems.count,
            budgetCategories: categoryLookup
        )
    }

    private var allStepsComplete: Bool {
        TransactionNextStepsCalculations.allStepsComplete(nextSteps)
    }

    private var storedAudit: TransactionAudit? {
        currentTransaction.audit
    }

    private var auditUsesProjectPrice: Bool {
        currentTransaction.transactionType == .purchase
            && currentTransaction.isInventoryMovement
    }

    // MARK: - Body

    var body: some View {
        PinnedImageLayout(
            pinnedAttachment: pinnedAttachment,
            allImages: pinnedImageSource,
            onClose: { pinnedAttachment = nil },
            onChangeImage: { pinnedAttachment = $0 }
        ) {
            ScrollViewReader { proxy in
                ScrollView {
                    AdaptiveContentWidth {
                        LazyVStack(spacing: Spacing.md, pinnedViews: [.sectionHeaders]) {
                            VStack(spacing: Spacing.lg) {
                                badgesRow
                                heroCard
                            }
                            .animation(.easeInOut(duration: 0.3), value: allStepsComplete)
                            .padding(.bottom, Spacing.xs)

                            receiptsSection
                            notesSection
                            detailsSection
                            itemDraftsSection
                            itemsSection
                            returnedItemsSection
                            soldItemsSection
                            transactionAuditSection
                            nextStepsCard
                        }
                        .padding(.horizontal, Spacing.screenPadding)
                        .padding(.vertical, Spacing.lg)
                    }
                }
                .onReceive(findState.scrollToPublisher) { matchID in
                    withAnimation { proxy.scrollTo(matchID, anchor: .center) }
                }
            }
        }
        .findEntity(id: transactionId)
        .background(BrandColors.background)
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
        .navigationDestination(item: $selectedProtoItem) { protoItem in
            ItemQuickDraftDetailView(protoItem: protoItem)
        }
        .navigationDestination(isPresented: $showItemDetail) {
            if let selectedNavigationItemId {
                ItemDetailView(
                    itemId: selectedNavigationItemId,
                    projectId: initialNavigationItem?.projectId,
                    initialItem: initialNavigationItem
                )
            } else {
                ContentUnavailableView("Item Unavailable", systemImage: "cube.box")
            }
        }
        .task(id: transactionId) {
            await loadLineageItems()
            await loadExternalItems()
        }
        .onAppear {
            guard let accountId = accountContext.currentAccountId else { return }
            transactionListener?.remove()
            transactionListener = TransactionsService()
                .subscribeToTransaction(accountId: accountId, transactionId: transactionId) { tx in
                    liveTransaction = tx
                }
            protoItemsListener?.remove()
            protoItemsListener = ProtoItemsService()
                .subscribeToProtoItemsForTransaction(accountId: accountId, transactionId: transactionId) { protoItems in
                    transactionProtoItems = protoItems
                }
            subscribeProjectCategoriesIfNeeded()
        }
        .onDisappear {
            transactionListener?.remove()
            transactionListener = nil
            protoItemsListener?.remove()
            protoItemsListener = nil
            budgetCategoriesListener?.remove()
            budgetCategoriesListener = nil
            protoItemToastTask?.cancel()
            protoItemToastTask = nil
        }
        .onChange(of: currentTransaction.projectId) { _, _ in
            subscribeProjectCategoriesIfNeeded()
        }
        #if canImport(UIKit)
        .toolbarBackground(BrandColors.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
        .navBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .trailingNavBar) {
                Button { showActionMenu = true } label: {
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
                title: currentTransaction.source ?? "Transaction",
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
        .itemActionSheets(
            itemActions,
            spaces: scopedSpaces,
            transactions: scopedTransactions,
            accountId: accountContext.currentAccountId,
            onActionComplete: { selectedItemIds.removeAll() }
        )
        .confirmationDialog("Delete Transaction?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteTransaction()
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert(item: $transactionDeletionNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .adaptivePresentation(isPresented: $showEditDetails, style: .form) {
            EditTransactionDetailsModal(
                transaction: currentTransaction,
                budgetCategories: projectBudgetCategories,
                isAccountingLocked: currentTransaction.isInventoryMovement,
                onSave: { fields in
                    updateTransaction(fields: fields)
                }
            )
        }
        .adaptivePresentation(isPresented: $showEditNotes, style: .form) {
            EditNotesModal(
                notes: currentTransaction.notes ?? "",
                onSave: { newNotes in
                    updateTransaction(fields: ["notes": newNotes])
                }
            )
        }
        .adaptivePresentation(isPresented: $showReassign, style: .form) {
            ReassignTransactionToProjectModal(
                transaction: currentTransaction,
                onComplete: { dismiss() }
            )
        }
        .adaptivePresentation(isPresented: $showCreateItemsFromImages, style: .fullSheet) {
            CreateItemsFromImagesModal(
                transaction: currentTransaction,
                onCreated: { groups in
                    createItemsFromImageGroups(groups)
                }
            )
        }
        .adaptivePresentation(isPresented: $showAddItemMenu, style: .quickMenu, onDismiss: {
            menuPendingAction?()
            menuPendingAction = nil
        }) {
            ActionMenuSheet(
                title: "Add Item",
                items: TransactionMenuBuilder.buildItemCreationMenu(
                    callbacks: TransactionItemCreationMenuCallbacks(
                        onCreateQuickDraft: { showCreateItemDraft = true },
                        onCreateItem: { showCreateNewItem = true },
                        onAddExisting: { showAddExistingItems = true },
                        onCreateFromImages: hasTransactionImages
                            ? { showCreateItemsFromImages = true }
                            : nil
                    )
                ),
                onSelectAction: { action in
                    menuPendingAction = action
                }
            )
        }
        .adaptivePresentation(isPresented: $showCreateNewItem, style: .form) {
            NewItemView(
                context: itemCreationContext,
                initialTransactionId: currentTransaction.id,
                onCreated: { itemIds in mergeCreatedItemIds(itemIds) }
            )
        }
        .adaptivePresentation(isPresented: $showCreateItemDraft, style: .form) {
            ItemDraftCaptureSheet(
                projectId: transactionProjectId,
                projectName: scopedProject?.name,
                transactionId: currentTransaction.id,
                transactionName: TransactionDisplayCalculations.displayName(for: currentTransaction)
            )
        }
        .adaptivePresentation(item: $protoItemPendingConvert, style: .form) { protoItem in
            NewItemView(
                context: protoItem.projectId.map { .project($0, spaceId: nil) } ?? .inventory,
                initialTransactionId: protoItem.transactionId,
                initialName: protoItem.name,
                initialSku: protoItem.sku,
                initialSkuCandidates: protoItem.extracted?.skuCandidates ?? [],
                initialQuantity: protoItem.quantity,
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
                items: dedupeItems(scopedItems + accountContext.allItems),
                filterCatalog: ItemFilterCatalog(
                    spaces: accountContext.allSpaces,
                    budgetCategories: accountContext.allBudgetCategories
                ),
                onMerge: { item in
                    Task { await mergeProtoItem(protoItem, into: item) }
                }
            )
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
        .adaptivePresentation(isPresented: $showAddExistingItems, style: .fullSheet) {
            AddExistingItemsPicker(
                context: .transaction(currentTransaction),
                projectId: transactionProjectId,
                onDismiss: { showAddExistingItems = false }
            )
        }
        .adaptivePresentation(isPresented: $showBulkStatusPicker, style: .quickMenu) {
            StatusPickerModal { status in updateStatusForSelected(status) }
        }
        .adaptivePresentation(isPresented: $showBulkSetSpace, style: .picker) {
            SetSpaceModal(
                spaces: scopedSpaces,
                currentSpaceId: nil,
                onSelect: { space in setSpaceForSelected(spaceId: space?.id) }
            )
        }
        .adaptivePresentation(isPresented: $showBulkTransactionPicker, style: .picker) {
            TransactionPickerModal(
                transactions: scopedTransactions,
                selectedId: currentTransaction.id,
                onSelect: { tx in
                    if let txId = tx.id { setTransactionForSelected(transactionId: txId) }
                }
            )
        }
        .adaptivePresentation(isPresented: $showBulkReturnToInventory, style: .form) {
            if let accountId = accountContext.currentAccountId {
                MoveToInventoryModal(items: selectedItems, accountId: accountId) {
                    selectedItemIds.removeAll()
                    Task { await loadLineageItems() }
                }
            }
        }
        .adaptivePresentation(isPresented: $showBulkSellToProject, style: .form) {
            if let accountId = accountContext.currentAccountId {
                SellItemsModal(items: selectedItems, accountId: accountId) {
                    selectedItemIds.removeAll()
                    Task {
                        await loadLineageItems()
                        await loadExternalItems()
                    }
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
    }

    // MARK: - Badges

    @ViewBuilder
    private var badgesRow: some View {
        let badges = TransactionCardCalculations.badgeItems(
            transactionType: currentTransaction.transactionType,
            reimbursementType: currentTransaction.reimbursementType,
            hasEmailReceipt: currentTransaction.hasEmailReceipt ?? false,
            isComplete: currentTransaction.isComplete,
            status: currentTransaction.status,
            isCanonicalInventorySale: currentTransaction.isCanonicalInventorySale,
            inventorySaleDirection: currentTransaction.inventorySaleDirection,
            budgetCategoryId: currentTransaction.budgetCategoryId
        )
        if !badges.isEmpty {
            HStack(spacing: Spacing.sm) {
                Spacer(minLength: 0)
                ForEach(badges, id: \.text) { badge in
                    Badge(
                        text: badge.text,
                        color: badge.color,
                        backgroundOpacity: badge.backgroundOpacity,
                        borderOpacity: badge.borderOpacity
                    )
                }
            }
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                FindableText(TransactionDisplayCalculations.displayName(for: currentTransaction))
                    .font(Typography.h2)
                    .foregroundStyle(BrandColors.textPrimary)

                HStack(spacing: Spacing.xs) {
                    Text("Amount:")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                    FindableText(TransactionDisplayCalculations.formattedAmount(for: currentTransaction))
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textPrimary)
                }

                HStack(spacing: Spacing.xs) {
                    Text("Date:")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                    FindableText(TransactionCardCalculations.formattedDate(currentTransaction.transactionDate))
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textPrimary)
                }

                HStack(spacing: Spacing.xs) {
                    Text("Project:")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                    FindableText(TransactionDisplayCalculations.projectLabel(
                        for: currentTransaction,
                        projects: accountContext.allProjects
                    ))
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textPrimary)
                }

                let displayCategoryName = selectedCategory?.name
                    ?? (currentTransaction.budgetCategoryId == "uncategorized" ? "Uncategorized" : nil)
                if let displayCategoryName, !displayCategoryName.isEmpty {
                    HStack(spacing: Spacing.xs) {
                        Text("Budget Category:")
                            .font(Typography.small)
                            .foregroundStyle(BrandColors.textSecondary)
                        FindableText(displayCategoryName)
                            .font(Typography.small)
                            .foregroundStyle(BrandColors.textPrimary)
                    }
                }
            }
        }
    }

    // MARK: - Next Steps Card

    @ViewBuilder
    private var nextStepsCard: some View {
        if !allStepsComplete {
            let completedCount = nextSteps.filter(\.completed).count
            let totalCount = nextSteps.count
            let progress = totalCount > 0 ? Double(completedCount) / Double(totalCount) : 0
            let incompleteSteps = nextSteps.filter { !$0.completed }
            let completedSteps = nextSteps.filter(\.completed)

            Card {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // Header with progress ring
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Next Steps")
                                .font(Typography.body.weight(.semibold))
                                .foregroundStyle(BrandColors.textPrimary)
                            Text("\(completedCount)/\(totalCount) complete")
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.textSecondary)
                        }
                        Spacer()
                        ProgressRing(progress: progress)
                    }

                    VStack(spacing: Spacing.xs) {
                        ForEach(incompleteSteps) { step in
                            nextStepRow(step)
                        }

                        if !completedSteps.isEmpty && !incompleteSteps.isEmpty {
                            Divider()
                        }

                        ForEach(completedSteps) { step in
                            nextStepRow(step)
                        }
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    @ViewBuilder
    private func nextStepRow(_ step: TransactionNextStepsCalculations.NextStep) -> some View {
        let content = HStack(spacing: Spacing.sm) {
            Group {
                if step.completed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(BrandColors.primary)
                } else {
                    Image(systemName: step.sfSymbol)
                        .font(.system(size: 14))
                        .foregroundStyle(BrandColors.textSecondary)
                        .overlay(
                            Circle()
                                .stroke(BrandColors.borderSecondary, lineWidth: 1.5)
                        )
                }
            }
            .frame(width: 24, height: 24)

            Text(step.label)
                .font(step.completed ? Typography.caption : Typography.body)
                .foregroundStyle(step.completed ? BrandColors.textSecondary : BrandColors.textPrimary)
                .strikethrough(step.completed)

            Spacer()

            if !step.completed {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(BrandColors.textTertiary)
            }
        }
        .frame(minHeight: step.completed ? 28 : 36)

        if step.completed {
            content
        } else {
            Button { handleNextStepTap(step) } label: { content }
                .buttonStyle(.plain)
        }
    }

    private func handleNextStepTap(_ step: TransactionNextStepsCalculations.NextStep) {
        switch step.id {
        case "items":
            expandedSections.insert("items")
            showAddItemMenu = true
        case "receipt":
            expandedSections.insert("receipts")
        default:
            // budget-category, amount, purchased-by, tax-rate all edit via details modal
            showEditDetails = true
        }
    }

    private func toggleFromInventory(_ protoItem: ProtoItem) {
        guard let accountId = accountContext.currentAccountId,
              let protoItemId = protoItem.id else { return }
        let isRemoving = protoItem.usesInventoryRouting
        showProtoItemToast(
            protoItemId: protoItemId,
            message: isRemoving ? "Removed \"From Inventory\" Marker." : "Marked \"From Inventory\""
        )
        let nextValue = !isRemoving
        Task {
            do {
                try await ProtoItemsService().updateProtoItem(
                    accountId: accountId,
                    protoItemId: protoItemId,
                    fields: ["isFromInventory": nextValue]
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

    // MARK: - Sections

    // 1. Receipts (default expanded)
    private var receiptsSection: some View {
        CollapsibleSection(
            title: "Receipts",
            isExpanded: sectionBinding("receipts"),
            badge: "\(currentTransaction.receiptImages?.count ?? 0)"
        ) {
            MediaGallerySection(
                title: "",
                attachments: currentTransaction.receiptImages ?? [],
                onUploadAttachmentFile: { upload in
                    try await uploadReceiptImage(upload)
                },
                onUploadDocument: { data, fileName in
                    try await uploadReceiptPDF(data, fileName: fileName)
                },
                onRemoveAttachment: { attachment in
                    removeReceiptImage(attachment)
                },
                onSetPrimary: { attachment in
                    setReceiptPrimary(attachment)
                },
                onPinImage: { attachment in
                    pinImage(attachment, from: currentTransaction.receiptImages ?? [])
                }
            )
            .padding(.top, Spacing.xs)
        }
    }

    // 2. Other Images (collapsed)
    private var otherImagesSection: some View {
        CollapsibleSection(
            title: "Other Images",
            isExpanded: sectionBinding("other-images"),
            badge: "\(currentTransaction.otherImages?.count ?? 0)"
        ) {
            MediaGallerySection(
                title: "",
                attachments: currentTransaction.otherImages ?? [],
                onUploadAttachmentFile: { upload in
                    try await uploadOtherImage(upload)
                },
                onRemoveAttachment: { attachment in
                    removeOtherImage(attachment)
                },
                onSetPrimary: { attachment in
                    setOtherPrimary(attachment)
                },
                onPinImage: { attachment in
                    pinImage(attachment, from: currentTransaction.otherImages ?? [])
                }
            )
            .padding(.top, Spacing.xs)
        }
    }

    // 3. Notes (collapsed)
    private var notesSection: some View {
        CollapsibleSection(
            title: "Notes",
            isExpanded: sectionBinding("notes"),
            onEdit: { showEditNotes = true }
        ) {
            NotesContent(notes: currentTransaction.notes)
                .padding(.top, Spacing.xs)
        }
    }

    // 4. Details (collapsed)
    private var detailsSection: some View {
        CollapsibleSection(
            title: "Details",
            isExpanded: sectionBinding("details"),
            onEdit: { showEditDetails = true }
        ) {
            VStack(spacing: 0) {
                DetailRow(label: "Vendor / Source", value: currentTransaction.source ?? "—")
                DetailRow(label: "Amount", value: TransactionCardCalculations.formattedAmount(
                    amountCents: currentTransaction.amountCents,
                    transactionType: currentTransaction.transactionType
                ))
                DetailRow(label: "Date", value: TransactionCardCalculations.formattedDate(currentTransaction.transactionDate))
                DetailRow(label: "Created", value: TransactionCardCalculations.formattedCreatedDate(currentTransaction.createdAt))
                DetailRow(label: "Status", value: displayStatus(currentTransaction.status))
                DetailRow(label: "Purchased By", value: displayPurchasedBy(currentTransaction.purchasedBy))
                DetailRow(label: "Transaction Type", value: displayTransactionType(for: currentTransaction))
                DetailRow(label: "Payable", value: displayPayable(currentTransaction.reimbursementType))
                DetailRow(label: "Budget Category", value: selectedCategory?.name ?? (currentTransaction.budgetCategoryId == "uncategorized" ? "Uncategorized" : "—"))
                if currentTransaction.needsItemizedAudit(category: selectedCategory) {
                    DetailRow(label: "Email Receipt", value: (currentTransaction.hasEmailReceipt ?? false) ? "Yes" : "No")
                    DetailRow(
                        label: "Subtotal",
                        value: currentTransaction.subtotalCents.map { CurrencyFormatting.formatCentsWithDecimals($0) } ?? "—"
                    )
                    DetailRow(
                        label: "Tax Rate",
                        value: currentTransaction.taxRatePct.map { String(format: "%.2f%%", $0) } ?? "—",
                        showDivider: false
                    )
                } else {
                    DetailRow(label: "Email Receipt", value: (currentTransaction.hasEmailReceipt ?? false) ? "Yes" : "No", showDivider: false)
                }
            }
            .padding(.top, Spacing.xs)
        }
    }

    private var itemDraftsSection: some View {
        CollapsibleSection(
            title: "Item Quick Drafts",
            isExpanded: sectionBinding("item-drafts"),
            badge: "\(activeTransactionProtoItems.count)",
            onAdd: { showCreateItemDraft = true }
        ) {
            VStack(alignment: .leading, spacing: Spacing.cardListGap) {
                if activeTransactionProtoItems.isEmpty {
                    ContentUnavailableView {
                        Label("No item quick drafts yet", systemImage: "camera.badge.ellipsis")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xl)
                } else {
                    ForEach(activeTransactionProtoItems) { protoItem in
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

    // 5. Items — composite pinned header (items label + control bar)
    @ViewBuilder
    private var itemsSection: some View {
        if expandedSections.contains("items") {
            SharedItemsList(
                mode: .embedded(items: activeItems, onItemPress: { itemId in
                    if let item = activeItems.first(where: { $0.id == itemId }) {
                        openItem(item)
                    }
                }),
                getMenuItems: { singleItemMenuItems(for: $0) },
                emptyMessage: "No items yet",
                onAdd: { showAddItemMenu = true },
                getBulkMenuItems: { bulkActionMenuItems },
                selectedIds: $selectedItemIds,
                filterScope: itemFilterScope,
                filterCatalog: ItemFilterCatalog(
                    spaces: scopedSpaces,
                    budgetCategories: projectBudgetCategories
                ),
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
                Text("\(activeItems.count)")
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

    // 6. Returned Items (collapsed, conditional)
    @ViewBuilder
    private var returnedItemsSection: some View {
        if !returnedItems.isEmpty {
            CollapsibleSection(
                title: "Returned Items",
                isExpanded: sectionBinding("returned-items"),
                badge: "\(returnedItems.count)",
                badgeColor: BrandColors.primary
            ) {
                groupedItemCards(
                    for: returnedItems,
                    expandedGroups: $expandedReturnedGroups
                )
                .padding(.top, Spacing.xs)
            }
        }
    }

    // 7. Sold Items (collapsed, conditional)
    @ViewBuilder
    private var soldItemsSection: some View {
        if !soldItems.isEmpty {
            CollapsibleSection(
                title: "Sold Items",
                isExpanded: sectionBinding("sold-items"),
                badge: "\(soldItems.count)",
                badgeColor: BrandColors.primary
            ) {
                groupedItemCards(
                    for: soldItems,
                    statusOverride: "Sold",
                    expandedGroups: $expandedSoldGroups
                )
                .padding(.top, Spacing.xs)
            }
        }
    }

    // MARK: - Grouped Item Cards Helper

    @ViewBuilder
    private func groupedItemCards(
        for items: [Item],
        statusOverride: String? = nil,
        expandedGroups: Binding<Set<String>>
    ) -> some View {
        let groups = ListFilterSortCalculations.groupItems(items)
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(groups) { group in
                if group.count > 1 {
                    let summaryItem = group.items.first(where: { ItemCardCalculations.primaryImage(from: $0.images) != nil }) ?? group.items.first
                    let summaryImage = ItemCardCalculations.primaryImage(from: summaryItem?.images)
                    let totalLabel = group.totalCents > 0 ? CurrencyFormatting.formatCentsWithDecimals(group.totalCents) : nil
                    let spaceName = groupedSpaceName(for: group)
                    GroupedItemCard(
                        name: group.name,
                        thumbnailUrl: summaryImage?.url,
                        thumbnailSmUrl: summaryImage?.thumbnailUrlSm,
                        countLabel: "×\(group.count)",
                        totalLabel: totalLabel,
                        sku: summaryItem?.sku,
                        sourceLabel: summaryItem?.currentSource ?? summaryItem?.source,
                        spaceName: spaceName,
                        priceLabel: totalLabel,
                        isExpanded: Binding(
                            get: { expandedGroups.wrappedValue.contains(group.id) },
                            set: { if $0 { expandedGroups.wrappedValue.insert(group.id) } else { expandedGroups.wrappedValue.remove(group.id) } }
                        ),
                        itemCount: group.count
                    ) {
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                            ItemCard(
                                item: item,
                                priceLabel: item.purchasePriceCents.map { CurrencyFormatting.formatCentsWithDecimals($0) },
                                indexLabel: "\(index + 1)/\(group.count)",
                                statusOverride: statusOverride,
                                onPress: { openItem(item) }
                            )
                        }
                    }
                } else if let item = group.items.first {
                    ItemCard(
                        item: item,
                        priceLabel: item.purchasePriceCents.map { CurrencyFormatting.formatCentsWithDecimals($0) },
                        statusOverride: statusOverride,
                        onPress: { openItem(item) }
                    )
                }
            }
        }
    }

    private func groupedSpaceName(for group: ItemGroup) -> String? {
        let names = Set(group.items.compactMap { item -> String? in
            guard
                let spaceId = item.spaceId,
                let name = accountContext.allSpaces.first(where: { $0.id == spaceId })?.name,
                !name.isEmpty
            else {
                return nil
            }
            return name
        })

        if names.count > 1 {
            return "Multiple spaces"
        }
        return names.first
    }

    // MARK: - Item Menus

    private func singleItemMenuItems(for item: Item) -> [ActionMenuItem] {
        guard let itemId = item.id else { return [] }
        return itemActions.buildMenu(
            for: item,
            scope: itemScope(for: item),
            menuContext: .transaction,
            accountId: accountContext.currentAccountId,
            onSelect: { selectedItemIds.insert(itemId) },
            projectDestinationPresentation: .resolve(
                for: [item],
                transactions: accountContext.allTransactions,
                projects: accountContext.allProjects
            )
        )
    }

    // 8. Transaction Audit (collapsed, conditional)
    // Only show for itemized categories when audit data is stored by Cloud Function.
    @ViewBuilder
    private var transactionAuditSection: some View {
        if let audit = storedAudit,
           currentTransaction.needsItemizedAudit(category: selectedCategory) {
            CollapsibleSection(
                title: "Transaction Audit",
                isExpanded: sectionBinding("transaction-audit"),
                statusBadge: currentTransaction.isComplete != true ? "Needs Review" : nil
            ) {
                TransactionAuditPanel(
                    audit: audit,
                    hasExplicitSubtotal: (currentTransaction.subtotalCents ?? 0) > 0,
                    usesProjectPrice: auditUsesProjectPrice,
                    itemsMissingPrice: transactionItems.filter { item in
                        if auditUsesProjectPrice {
                            return (item.normalizedProjectPriceCents ?? 0) <= 0
                        }
                        return (item.purchasePriceCents ?? 0) <= 0
                    },
                    itemsCount: transactionItems.count + returnedItems.count + soldItems.count
                )
                .padding(.top, Spacing.xs)
            }
        }
    }

    // MARK: - Action Menu

    private var actionMenuItems: [ActionMenuItem] {
        TransactionMenuBuilder.buildDetailMenu(
            transaction: currentTransaction,
            callbacks: SingleTransactionMenuCallbacks(
                onReassignToInventory: { correctTransactionToInventory() },
                onReassignToProject: { showReassign = true },
                onCopyID: currentTransaction.id.map { id in { Clipboard.copy(id) } },
                onDelete: { requestDeleteTransaction() }
            )
        )
    }

    private var bulkActionMenuItems: [ActionMenuItem] {
        let selectedScope = selectedItemsScope
        return ItemMenuBuilder.buildBulkMenu(
            context: .transaction,
            scope: selectedScope ?? .search,
            callbacks: BulkItemMenuCallbacks(
                onStatusChange: { _ in showBulkStatusPicker = true },
                onSetTransaction: { showBulkTransactionPicker = true },
                onClearTransaction: { clearTransactionForSelected() },
                onSetSpace: { showBulkSetSpace = true },
                onClearSpace: { clearSpaceForSelected() },
                onReturnToInventory: selectedScope == .project && selectedItemsCanReturnToInventory
                    ? { showBulkReturnToInventory = true }
                    : nil,
                onSellToProject: selectedScope == nil ? nil : { showBulkSellToProject = true },
                onReassignToProject: { showBulkReassign = true },
                onCopyIDs: { Clipboard.copyLines(selectedItemIds) },
                onDelete: { showBulkDeleteConfirmation = true }
            ),
            projectDestinationPresentation: .resolve(
                for: selectedItems,
                transactions: accountContext.allTransactions,
                projects: accountContext.allProjects
            )
        )
    }

    // MARK: - Lineage

    private func loadLineageItems() async {
        guard let accountId = accountContext.currentAccountId else { return }

        do {
            let edges = try await LineageEdgesService()
                .edges(forTransaction: transactionId, accountId: accountId)

            // Filter to edges where THIS transaction is the source (items that LEFT)
            let currentItemIds = Set(currentTransaction.itemIds ?? [])

            // Group by itemId, keep latest by createdAt, split by movementKind
            var latestByItem: [String: LineageEdge] = [:]
            for edge in edges {
                guard let itemId = edge.itemId,
                      edge.fromTransactionId == transactionId,
                      let kind = edge.movementKind,
                      (kind == "returned" || kind == "sold" || kind == "soldToInventory"),
                      !currentItemIds.contains(itemId) else { continue }

                if let existing = latestByItem[itemId] {
                    if (edge.createdAt ?? .distantPast) > (existing.createdAt ?? .distantPast) {
                        latestByItem[itemId] = edge
                    }
                } else {
                    latestByItem[itemId] = edge
                }
            }

            let returnedIds = Set(latestByItem.filter { $0.value.movementKind == "returned" }.keys)
            let soldIds = Set(latestByItem.filter {
                $0.value.movementKind == "sold" || $0.value.movementKind == "soldToInventory"
            }.keys)

            var returnedResolved = scopedItems.filter { returnedIds.contains($0.id ?? "") }
            let foundReturnedIds = Set(returnedResolved.compactMap(\.id))
            let missingReturnedIds = returnedIds.subtracting(foundReturnedIds)
            if !missingReturnedIds.isEmpty {
                let service = ItemsService()
                for itemId in missingReturnedIds {
                    if let item = try? await service.getItem(accountId: accountId, itemId: itemId) {
                        returnedResolved.append(item)
                    }
                }
            }

            // Sold items may have left the project — try context first, then fetch missing
            var soldResolved = scopedItems.filter { soldIds.contains($0.id ?? "") }
            let foundSoldIds = Set(soldResolved.compactMap(\.id))
            let missingSoldIds = soldIds.subtracting(foundSoldIds)
            if !missingSoldIds.isEmpty {
                let service = ItemsService()
                for itemId in missingSoldIds {
                    if let item = try? await service.getItem(accountId: accountId, itemId: itemId) {
                        soldResolved.append(item)
                    }
                }
            }

            lineageReturnedItems = returnedResolved
            lineageSoldItems = soldResolved
        } catch {
            // Fail silently — sections just won't show. Offline-first: no spinner.
        }
    }

    /// Canonical inventory movements can legitimately link items outside the
    /// transaction's collection scope. Only those transactions use focused
    /// fallback reads; an unloaded context must never turn into N item reads.
    private func loadExternalItems() async {
        guard let accountId = accountContext.currentAccountId,
              currentTransaction.isCanonicalInventorySale == true,
              let ids = currentTransaction.itemIds, !ids.isEmpty else { return }
        let idSet = Set(ids)
        let contextIds = Set(scopedItems.compactMap(\.id).filter { idSet.contains($0) })
        let missingIds = idSet.subtracting(contextIds)
        guard !missingIds.isEmpty else { return }

        let service = ItemsService()
        var fetched: [Item] = []
        for itemId in missingIds {
            if let item = try? await service.getItem(accountId: accountId, itemId: itemId) {
                fetched.append(item)
            }
        }
        resolvedExternalItems = fetched
    }

    // MARK: - Helpers

    private func openItem(_ item: Item) {
        guard let id = item.id else { return }
        selectedNavigationItemId = id
        initialNavigationItem = item
        showItemDetail = true
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

    private func displayStatus(_ status: TransactionStatus?) -> String {
        status?.displayLabel ?? "—"
    }

    private func displayPurchasedBy(_ value: String?) -> String {
        switch value?.lowercased() {
        case "client-card": return "Client Card"
        case "design-business": return "Design Business"
        case "missing": return "Missing"
        default: return "—"
        }
    }

    private func displayTransactionType(for transaction: Transaction) -> String {
        if transaction.transactionType == .sale,
           transaction.inventorySaleDirection == .businessToProject {
            return TransactionType.purchase.displayLabel
        }
        return transaction.transactionType?.displayLabel ?? "—"
    }

    private func displayPayable(_ value: String?) -> String {
        switch value?.lowercased() {
        case "owed-to-client": return "To Client"
        case "owed-to-company": return "To Business"
        case "none": return "None"
        default: return "—"
        }
    }

    // MARK: - Image Pinning

    private func pinImage(_ attachment: AttachmentRef, from source: [AttachmentRef]) {
        pinnedAttachment = attachment
        pinnedImageSource = source.filter { $0.kind == .image || $0.kind == .pdf }
    }

    // MARK: - Image Management (Receipts)

    private func uploadReceiptImage(_ upload: AttachmentUpload) async throws {
        guard let accountId = accountContext.currentAccountId else { return }
        let filename = upload.storageFileName
        let path = mediaService.uploadPath(
            accountId: accountId,
            entityType: "transactions",
            entityId: transactionId,
            filename: filename
        )
        let url = try await mediaService.uploadData(upload.data, path: path, contentType: upload.contentType)
        let thumbnails = await mediaService.uploadThumbnails(
            for: upload.data,
            originalPath: path,
            contentType: upload.contentType
        )
        var images = currentTransaction.receiptImages ?? []
        let isPrimary = images.isEmpty
        images.append(AttachmentRef(
            url: url,
            thumbnailUrlSm: thumbnails.sm,
            thumbnailUrlMd: thumbnails.md,
            fileName: upload.displayFileName,
            contentType: upload.contentType,
            isPrimary: isPrimary
        ))
        updateTransaction(fields: ["receiptImages": images.map(attachmentDict)])
    }

    private func uploadReceiptPDF(_ data: Data, fileName: String) async throws {
        guard let accountId = accountContext.currentAccountId else { return }
        let storageFileName = "\(UUID().uuidString).pdf"
        let path = mediaService.uploadPath(
            accountId: accountId,
            entityType: "transactions",
            entityId: transactionId,
            filename: storageFileName
        )
        let url = try await mediaService.uploadData(data, path: path, contentType: "application/pdf")
        var images = currentTransaction.receiptImages ?? []
        let isPrimary = images.isEmpty
        images.append(AttachmentRef(
            url: url,
            kind: .pdf,
            fileName: fileName,
            contentType: "application/pdf",
            isPrimary: isPrimary
        ))
        updateTransaction(fields: ["receiptImages": images.map(attachmentDict)])
    }

    private func removeReceiptImage(_ attachment: AttachmentRef) {
        var images = currentTransaction.receiptImages ?? []
        images.removeAll { $0.url == attachment.url }
        updateTransaction(fields: ["receiptImages": images.map(attachmentDict)])
        Task {
            try? await mediaService.deleteImage(url: attachment.url)
        }
    }

    private func setReceiptPrimary(_ attachment: AttachmentRef) {
        guard var images = currentTransaction.receiptImages else { return }
        images = images.map { img in
            var copy = img
            copy.isPrimary = (img.url == attachment.url)
            return copy
        }
        updateTransaction(fields: ["receiptImages": images.map(attachmentDict)])
    }

    // MARK: - Image Management (Other Images)

    private func uploadOtherImage(_ upload: AttachmentUpload) async throws {
        guard let accountId = accountContext.currentAccountId else { return }
        let filename = upload.storageFileName
        let path = mediaService.uploadPath(
            accountId: accountId,
            entityType: "transactions",
            entityId: transactionId,
            filename: filename
        )
        let url = try await mediaService.uploadData(upload.data, path: path, contentType: upload.contentType)
        let thumbnails = await mediaService.uploadThumbnails(
            for: upload.data,
            originalPath: path,
            contentType: upload.contentType
        )
        var images = currentTransaction.otherImages ?? []
        let isPrimary = images.isEmpty
        images.append(AttachmentRef(
            url: url,
            thumbnailUrlSm: thumbnails.sm,
            thumbnailUrlMd: thumbnails.md,
            fileName: upload.displayFileName,
            contentType: upload.contentType,
            isPrimary: isPrimary
        ))
        updateTransaction(fields: ["otherImages": images.map(attachmentDict)])
    }

    private func removeOtherImage(_ attachment: AttachmentRef) {
        var images = currentTransaction.otherImages ?? []
        images.removeAll { $0.url == attachment.url }
        updateTransaction(fields: ["otherImages": images.map(attachmentDict)])
        Task {
            try? await mediaService.deleteImage(url: attachment.url)
        }
    }

    private func setOtherPrimary(_ attachment: AttachmentRef) {
        guard var images = currentTransaction.otherImages else { return }
        images = images.map { img in
            var copy = img
            copy.isPrimary = (img.url == attachment.url)
            return copy
        }
        updateTransaction(fields: ["otherImages": images.map(attachmentDict)])
    }

    private func attachmentDict(_ ref: AttachmentRef) -> [String: Any] {
        var dict: [String: Any] = [
            "url": ref.url,
            "kind": ref.kind.rawValue,
        ]
        if let fileName = ref.fileName { dict["fileName"] = fileName }
        if let contentType = ref.contentType { dict["contentType"] = contentType }
        if let isPrimary = ref.isPrimary { dict["isPrimary"] = isPrimary }
        if let thumbnailUrlSm = ref.thumbnailUrlSm { dict["thumbnailUrlSm"] = thumbnailUrlSm }
        if let thumbnailUrlMd = ref.thumbnailUrlMd { dict["thumbnailUrlMd"] = thumbnailUrlMd }
        return dict
    }

    // MARK: - Actions

    private func correctTransactionToInventory() {
        guard let accountId = accountContext.currentAccountId,
              let transactionId = currentTransaction.id else { return }
        Task {
            do {
                try await TransactionsService().updateTransaction(
                    accountId: accountId,
                    transactionId: transactionId,
                    fields: TransactionsService.moveToInventoryCorrectionFields()
                )
                await MainActor.run { dismiss() }
            } catch {
                print("🔴 correctTransactionToInventory failed: \(error)")
            }
        }
    }

    private func updateStatusForSelected(_ status: ItemStatus) {
        updateSelectedItems(fields: ["status": status.rawValue])
    }

    private func setSpaceForSelected(spaceId: String?) {
        updateSelectedItems(fields: ["spaceId": spaceId as Any? ?? NSNull()])
    }

    private func clearSpaceForSelected() {
        updateSelectedItems(fields: ["spaceId": NSNull()])
    }

    private func updateSelectedItems(fields: [String: Any]) {
        guard let accountId = accountContext.currentAccountId else { return }
        let items = selectedItems
        nonisolated(unsafe) let updateFields = fields
        Task {
            do {
                try await ItemsService().updateItems(
                    accountId: accountId,
                    items: items,
                    fields: updateFields
                )
            } catch {
                print("Bulk item update failed: \(error)")
            }
        }
        selectedItemIds.removeAll()
    }

    private func setTransactionForSelected(transactionId: String) {
        guard let accountId = accountContext.currentAccountId else { return }
        let items = Array(selectedItems)
        Task { try? await ItemsService().setTransaction(accountId: accountId, items: items, transactionId: transactionId) }
        selectedItemIds.removeAll()
    }

    private func clearTransactionForSelected() {
        guard let accountId = accountContext.currentAccountId else { return }
        let items = Array(selectedItems)
        Task { try? await ItemsService().clearTransaction(accountId: accountId, items: items) }
        selectedItemIds.removeAll()
    }

    private func deleteSelected() {
        guard let accountId = accountContext.currentAccountId else { return }
        let items = Array(selectedItems)
        Task { try? await ItemsService().deleteItems(accountId: accountId, items: items) }
        selectedItemIds.removeAll()
    }

    private func updateTransaction(fields: [String: Any]) {
        guard let accountId = accountContext.currentAccountId else {
            print("⚠️ updateTransaction skipped — missing accountId or transactionId")
            return
        }
        nonisolated(unsafe) let f = fields
        Task {
            do {
                try await TransactionsService()
                    .updateTransaction(accountId: accountId, transactionId: transactionId, fields: f)
            } catch {
                print("🔴 updateTransaction failed: \(error)")
            }
        }
    }


    private func deleteTransaction() {
        guard let accountId = accountContext.currentAccountId else { return }
        Task {
            do {
                try await TransactionsService()
                    .deleteTransaction(accountId: accountId, transactionId: transactionId)
                dismiss()
            } catch {
                transactionDeletionNotice = TransactionsService.failureNotice(for: error)
            }
        }
    }

    private func requestDeleteTransaction() {
        if let notice = TransactionsService.deletionNotice(for: currentTransaction) {
            transactionDeletionNotice = notice
            return
        }
        showDeleteConfirmation = true
    }

    private func createItemsFromImageGroups(_ groups: [ImageGroup]) {
        guard let accountId = accountContext.currentAccountId else { return }

        let projectId = transactionProjectId
        let budgetCategoryId = projectId == nil ? nil : currentTransaction.budgetCategoryId

        let items = groups.map { group -> Item in
            var images = group.images
            if !images.isEmpty { images[0].isPrimary = true }

            var item = Item()
            item.accountId = accountId
            item.projectId = projectId
            item.status = .purchased
            item.transactionId = transactionId
            item.budgetCategoryId = budgetCategoryId
            item.images = images
            return item
        }

        expandedSections.insert("items")
        do {
            let createdItems = try ItemsService().createItemsForTransaction(
                accountId: accountId,
                transactionId: transactionId,
                budgetCategoryId: budgetCategoryId,
                items: items,
                onCommitError: { itemIds, error in
                    Task { @MainActor in
                        removePendingCreatedItemIds(itemIds)
                        print("🔴 createItemsFromImageGroups failed: \(error)")
                    }
                }
            )
            mergeCreatedItems(createdItems)
        } catch {
            print("🔴 createItemsFromImageGroups failed: \(error)")
        }
    }

    private func mergeCreatedItems(_ items: [Item]) {
        pendingCreatedItems.append(contentsOf: items)
        mergeCreatedItemIds(items.compactMap(\.id))
    }

    private func mergeCreatedItemIds(_ itemIds: [String]) {
        guard !itemIds.isEmpty else { return }

        var tx = currentTransaction
        var ids = tx.itemIds ?? []
        let existingIds = Set(ids)
        ids.append(contentsOf: itemIds.filter { !existingIds.contains($0) })
        tx.itemIds = ids
        liveTransaction = tx
    }

    private func removePendingCreatedItemIds(_ itemIds: [String]) {
        let ids = Set(itemIds)
        pendingCreatedItems.removeAll { item in
            guard let id = item.id else { return true }
            return ids.contains(id)
        }
    }

}
