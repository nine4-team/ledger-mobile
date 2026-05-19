import SwiftUI
import FirebaseFirestore

/// Full transaction detail screen with hero card, Next Steps, 8 collapsible sections,
/// and delete action.
struct TransactionDetailView: View {
    let transaction: Transaction

    @Environment(ProjectContext.self) private var projectContext
    @Environment(AccountContext.self) private var accountContext
    @Environment(MediaService.self) private var mediaService
    @Environment(FindStateManager.self) private var findState
    @Environment(\.dismiss) private var dismiss

    // Section expanded states — all expanded by default
    @State private var expandedSections: Set<String> = ["receipts", "other-images", "notes", "details", "returned-items", "sold-items", "transaction-audit"]
    @State private var selectedTransactionTab = "details"
    @State private var selectedItemsSubtab = "items"

    // Items picker
    @State private var showAddExistingItems = false
    // Modal presentation
    @State private var showActionMenu = false
    @State private var showEditDetails = false
    @State private var showEditNotes = false
    @State private var showCreateItemsFromImages = false
    @State private var showDeleteConfirmation = false
    @State private var showAddItemMenu = false
    @State private var showCreateNewItem = false
    @State private var showCreateItemDraft = false
    @State private var showReassign = false
    @State private var menuPendingAction: (() -> Void)?

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

    // MARK: - Computed

    private var currentTransaction: Transaction {
        var tx = liveTransaction ?? projectContext.transactions.first(where: { $0.id == transaction.id }) ?? transaction
        let pendingIds = pendingCreatedItems.compactMap(\.id)
        if !pendingIds.isEmpty {
            var ids = tx.itemIds ?? []
            let existingIds = Set(ids)
            ids.append(contentsOf: pendingIds.filter { !existingIds.contains($0) })
            tx.itemIds = ids
        }
        return tx
    }

    private var transactionItems: [Item] {
        guard let ids = currentTransaction.itemIds, !ids.isEmpty else { return [] }
        let idSet = Set(ids)
        let fromContext = projectContext.items.filter { idSet.contains($0.id ?? "") }
        let contextIds = Set(fromContext.compactMap(\.id))
        let external = resolvedExternalItems.filter {
            guard let id = $0.id else { return false }
            return idSet.contains(id) && !contextIds.contains(id)
        }
        let resolvedIds = contextIds.union(external.compactMap(\.id))
        let pending = pendingCreatedItems.filter {
            guard let id = $0.id else { return false }
            return idSet.contains(id) && !resolvedIds.contains(id)
        }
        return fromContext + external + pending
    }

    private var activeItems: [Item] {
        if currentTransaction.isReturnTransaction {
            return transactionItems
        }
        // Sale transactions show all items regardless of status. Items in a sale's
        // itemIds may have status "returned" (returned to vendor while in inventory)
        // or "sold" (sold to another project) — but they still belong to this
        // transaction until moved via lineage. The status-based filter only applies
        // to purchase transactions where returned/sold items have been moved out
        // and are tracked via lineage in separate sections.
        if currentTransaction.transactionType == .sale {
            return transactionItems
        }
        return transactionItems.filter { $0.status != .returned && $0.status != .sold }
    }

    private var returnedItems: [Item] { lineageReturnedItems }
    private var soldItems: [Item] { lineageSoldItems }

    private var activeTransactionProtoItems: [ProtoItem] {
        transactionProtoItems
            .filter { $0.status == nil || $0.status == .open || $0.status == .inReview }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    private var categoryLookup: [String: BudgetCategory] {
        Dictionary(
            uniqueKeysWithValues: projectContext.budgetCategories.compactMap { cat in
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
                            ScrollableTabBar(
                                selectedId: $selectedTransactionTab,
                                items: [
                                    TabBarItem(id: "details", label: "Details"),
                                    TabBarItem(id: "items", label: "Items"),
                                ]
                            )

                            if selectedTransactionTab == "details" {
                                detailsTabContent
                            } else {
                                itemsTabContent
                            }
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
        .findEntity(id: transaction.id)
        .background(BrandColors.background)
        .navigationDestination(for: Item.self) { item in
            ItemDetailView(item: item)
        }
        .task(id: transaction.id) {
            await loadLineageItems()
            await loadExternalItems()
        }
        .onAppear {
            guard let accountId = accountContext.currentAccountId,
                  let transactionId = transaction.id else { return }
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
        }
        .onDisappear {
            transactionListener?.remove()
            transactionListener = nil
            protoItemsListener?.remove()
            protoItemsListener = nil
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
        .confirmationDialog("Delete Transaction?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteTransaction()
            }
        } message: {
            Text("This action cannot be undone. All linked items will be unlinked.")
        }
        .adaptivePresentation(isPresented: $showEditDetails, style: .form) {
            EditTransactionDetailsModal(
                transaction: currentTransaction,
                budgetCategories: projectContext.enabledBudgetCategories,
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
                items: {
                    var items = [
                        ActionMenuItem(id: "item-draft", label: "Item Draft", icon: "camera.badge.ellipsis", onPress: {
                            showCreateItemDraft = true
                        }),
                        ActionMenuItem(id: "create-new", label: "Create New Item", icon: "plus.square.fill", onPress: {
                            showCreateNewItem = true
                        }),
                        ActionMenuItem(id: "add-existing", label: "Add Existing Items", icon: "plus.square.on.square", onPress: {
                            showAddExistingItems = true
                        }),
                    ]
                    let hasImages = !(currentTransaction.receiptImages ?? []).isEmpty
                        || !(currentTransaction.otherImages ?? []).isEmpty
                        || !(currentTransaction.transactionImages ?? []).isEmpty
                    if hasImages {
                        items.append(ActionMenuItem(id: "create-from-images", label: "Create from Images", icon: "photo.on.rectangle.angled", onPress: {
                            showCreateItemsFromImages = true
                        }))
                    }
                    return items
                }(),
                onSelectAction: { action in
                    menuPendingAction = action
                }
            )
        }
        .adaptivePresentation(isPresented: $showCreateNewItem, style: .form) {
            if let projectId = projectContext.currentProjectId {
                NewItemView(
                    context: .project(projectId, spaceId: nil),
                    initialTransactionId: currentTransaction.id
                )
            }
        }
        .adaptivePresentation(isPresented: $showCreateItemDraft, style: .form) {
            if let projectId = projectContext.currentProjectId {
                ItemDraftCaptureSheet(
                    projectId: projectId,
                    projectName: projectContext.project?.name,
                    transactionId: currentTransaction.id,
                    transactionName: TransactionDisplayCalculations.displayName(for: currentTransaction)
                )
            }
        }
        .adaptivePresentation(isPresented: $showAddExistingItems, style: .fullSheet) {
            AddExistingItemsPicker(
                context: .transaction(currentTransaction),
                projectId: projectContext.project?.id,
                onDismiss: { showAddExistingItems = false }
            )
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
            inventorySaleDirection: currentTransaction.inventorySaleDirection
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
            selectedTransactionTab = "items"
            selectedItemsSubtab = "items"
            showAddItemMenu = true
        case "receipt":
            selectedTransactionTab = "details"
            expandedSections.insert("receipts")
        default:
            // budget-category, amount, purchased-by, tax-rate all edit via details modal
            showEditDetails = true
        }
    }

    // MARK: - Tabs

    @ViewBuilder
    private var detailsTabContent: some View {
        VStack(spacing: Spacing.lg) {
            badgesRow
            heroCard
            nextStepsCard
        }
        .animation(.easeInOut(duration: 0.3), value: allStepsComplete)
        .padding(.bottom, Spacing.xs)

        receiptsSection
        otherImagesSection
        notesSection
        detailsSection
        transactionAuditSection
    }

    @ViewBuilder
    private var itemsTabContent: some View {
        compactTransactionContext
        itemSubtabHeader

        if selectedItemsSubtab == "item-drafts" {
            itemDraftsList
        } else {
            realItemsList
            returnedItemsSection
            soldItemsSection
        }
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
                onUploadAttachment: { data in
                    try await uploadReceiptImage(data)
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
                onUploadAttachment: { data in
                    try await uploadOtherImage(data)
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
                DetailRow(label: "Transaction Type", value: displayTransactionType(currentTransaction.transactionType))
                DetailRow(label: "Payable", value: displayPayable(currentTransaction.reimbursementType))
                DetailRow(label: "Budget Category", value: selectedCategory?.name ?? (currentTransaction.budgetCategoryId == "uncategorized" ? "Uncategorized" : "—"))
                if currentTransaction.needsItemizedAudit {
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

    @ViewBuilder
    private var realItemsList: some View {
        SharedItemsList(
            mode: .embedded(items: activeItems, onItemPress: { _ in }),
            emptyMessage: "No items yet",
            useNavigationLinks: true,
            filterScope: .project,
            inline: true
        )
    }

    @ViewBuilder
    private var itemDraftsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if activeTransactionProtoItems.isEmpty {
                ContentUnavailableView {
                    Label("No item drafts yet", systemImage: "camera.badge.ellipsis")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xl)
            } else {
                VStack(alignment: .leading, spacing: Spacing.cardListGap) {
                    ForEach(activeTransactionProtoItems) { protoItem in
                        ItemDraftCard(protoItem: protoItem)
                    }
                }
                .padding(.top, Spacing.sm)
            }
        }
    }

    private var compactTransactionContext: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                FindableText(TransactionDisplayCalculations.displayName(for: currentTransaction))
                    .font(Typography.body.weight(.semibold))
                    .foregroundStyle(BrandColors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: Spacing.xs) {
                    FindableText(TransactionCardCalculations.formattedDate(currentTransaction.transactionDate))
                    Text("·")
                    FindableText(TransactionDisplayCalculations.projectLabel(
                        for: currentTransaction,
                        projects: accountContext.allProjects
                    ))
                }
                .font(Typography.caption)
                .foregroundStyle(BrandColors.textSecondary)
                .lineLimit(1)
            }

            Spacer(minLength: Spacing.sm)

            FindableText(TransactionDisplayCalculations.formattedAmount(for: currentTransaction))
                .font(Typography.body.weight(.semibold))
                .foregroundStyle(BrandColors.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(BrandColors.surface, in: RoundedRectangle(cornerRadius: Dimensions.buttonRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Dimensions.buttonRadius)
                .stroke(BrandColors.borderSecondary, lineWidth: Dimensions.borderWidth)
        )
    }

    private var itemSubtabHeader: some View {
        ZStack(alignment: .trailing) {
            ScrollableTabBar(
                selectedId: $selectedItemsSubtab,
                items: [
                    TabBarItem(id: "item-drafts", label: "Item Drafts"),
                    TabBarItem(id: "items", label: "Items"),
                ]
            )

            addItemButton
        }
    }

    private var addItemButton: some View {
        Button {
            showAddItemMenu = true
        } label: {
            Image(systemName: "plus")
                .fontWeight(.medium)
                .foregroundStyle(BrandColors.textSecondary)
        }
        .buttonStyle(CircleBarButtonStyle())
        .tint(BrandColors.textSecondary)
        .font(.system(size: 16))
        .imageScale(.medium)
        .background(BrandColors.surface, in: Circle())
        .overlay(Circle().stroke(BrandColors.borderSecondary, lineWidth: Dimensions.borderWidth))
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
        .accessibilityLabel("Add item")
        .padding(.bottom, Spacing.xs)
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
                                statusOverride: statusOverride
                            )
                        }
                    }
                } else if let item = group.items.first {
                    ItemCard(
                        item: item,
                        priceLabel: item.purchasePriceCents.map { CurrencyFormatting.formatCentsWithDecimals($0) },
                        statusOverride: statusOverride
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

    // 8. Transaction Audit (collapsed, conditional)
    // Only show for itemized categories when audit data is stored by Cloud Function.
    @ViewBuilder
    private var transactionAuditSection: some View {
        if let audit = storedAudit,
           currentTransaction.needsItemizedAudit {
            CollapsibleSection(
                title: "Transaction Audit",
                isExpanded: sectionBinding("transaction-audit"),
                statusBadge: currentTransaction.isComplete != true ? "Needs Review" : nil
            ) {
                TransactionAuditPanel(
                    audit: audit,
                    hasExplicitSubtotal: (currentTransaction.subtotalCents ?? 0) > 0,
                    itemsMissingPrice: transactionItems.filter { ($0.purchasePriceCents ?? 0) == 0 },
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
                onReassignToInventory: { returnToInventory() },
                onReassignToProject: { showReassign = true },
                onCopyID: currentTransaction.id.map { id in { Clipboard.copy(id) } },
                onDelete: { showDeleteConfirmation = true }
            )
        )
    }

    // MARK: - Lineage

    private func loadLineageItems() async {
        guard let accountId = accountContext.currentAccountId,
              let transactionId = transaction.id else { return }

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
                      (kind == "returned" || kind == "sold"),
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
            let soldIds = Set(latestByItem.filter { $0.value.movementKind == "sold" }.keys)

            // Resolve items from project context (returned items stay in same project)
            let returnedFromContext = projectContext.items.filter { returnedIds.contains($0.id ?? "") }

            // Sold items may have left the project — try context first, then fetch missing
            var soldResolved = projectContext.items.filter { soldIds.contains($0.id ?? "") }
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

            lineageReturnedItems = returnedFromContext
            lineageSoldItems = soldResolved
        } catch {
            // Fail silently — sections just won't show. Offline-first: no spinner.
        }
    }

    /// Fetch items not in project context (e.g. inventory items in project_to_business canonical sales).
    private func loadExternalItems() async {
        guard let accountId = accountContext.currentAccountId,
              let ids = currentTransaction.itemIds, !ids.isEmpty else { return }
        let idSet = Set(ids)
        let contextIds = Set(projectContext.items.compactMap(\.id).filter { idSet.contains($0) })
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

    private func displayTransactionType(_ value: TransactionType?) -> String {
        value?.displayLabel ?? "—"
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

    private func uploadReceiptImage(_ data: Data) async throws {
        guard let accountId = accountContext.currentAccountId,
              let transactionId = transaction.id else { return }
        let filename = "\(UUID().uuidString).jpg"
        let path = mediaService.uploadPath(
            accountId: accountId,
            entityType: "transactions",
            entityId: transactionId,
            filename: filename
        )
        let url = try await mediaService.uploadImage(data, path: path)
        var images = currentTransaction.receiptImages ?? []
        let isPrimary = images.isEmpty
        images.append(AttachmentRef(url: url, isPrimary: isPrimary))
        updateTransaction(fields: ["receiptImages": images.map(attachmentDict)])
    }

    private func uploadReceiptPDF(_ data: Data, fileName: String) async throws {
        guard let accountId = accountContext.currentAccountId,
              let transactionId = transaction.id else { return }
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

    private func uploadOtherImage(_ data: Data) async throws {
        guard let accountId = accountContext.currentAccountId,
              let transactionId = transaction.id else { return }
        let filename = "\(UUID().uuidString).jpg"
        let path = mediaService.uploadPath(
            accountId: accountId,
            entityType: "transactions",
            entityId: transactionId,
            filename: filename
        )
        let url = try await mediaService.uploadImage(data, path: path)
        var images = currentTransaction.otherImages ?? []
        let isPrimary = images.isEmpty
        images.append(AttachmentRef(url: url, isPrimary: isPrimary))
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
        return dict
    }

    // MARK: - Actions

    private func returnToInventory() {
        guard let accountId = accountContext.currentAccountId else { return }
        let items = transactionItems
        guard !items.isEmpty else { return }
        let inventoryLabel = InventoryOperationsService.inventoryLabel(for: accountContext.account?.name)
        Task {
            do {
                try await InventoryOperationsService().moveToInventory(
                    items: items,
                    accountId: accountId,
                    inventoryLabel: inventoryLabel
                )
                await MainActor.run { dismiss() }
            } catch {
                print("🔴 moveToInventory failed: \(error)")
            }
        }
    }

    private func updateTransaction(fields: [String: Any]) {
        guard let accountId = accountContext.currentAccountId,
              let transactionId = transaction.id else {
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
        guard let accountId = accountContext.currentAccountId,
              let transactionId = transaction.id else { return }
        Task {
            try? await TransactionsService()
                .deleteTransaction(accountId: accountId, transactionId: transactionId)
            dismiss()
        }
    }

    private func createItemsFromImageGroups(_ groups: [ImageGroup]) {
        guard let accountId = accountContext.currentAccountId,
              let projectId = projectContext.currentProjectId,
              let transactionId = transaction.id else { return }

        let items = groups.map { group -> Item in
            var images = group.images
            if !images.isEmpty { images[0].isPrimary = true }

            var item = Item()
            item.accountId = accountId
            item.projectId = projectId
            item.status = .purchased
            item.transactionId = transactionId
            item.budgetCategoryId = currentTransaction.budgetCategoryId
            item.images = images
            return item
        }

        selectedTransactionTab = "items"
        selectedItemsSubtab = "items"
        do {
            let createdItems = try ItemsService().createItemsForTransaction(
                accountId: accountId,
                transactionId: transactionId,
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
