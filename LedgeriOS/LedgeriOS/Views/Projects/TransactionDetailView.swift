import SwiftUI
import FirebaseFirestore

/// Full transaction detail screen with hero card, Next Steps, 8 collapsible sections,
/// Moved Items, and delete action.
struct TransactionDetailView: View {
    let transaction: Transaction

    @Environment(ProjectContext.self) private var projectContext
    @Environment(AccountContext.self) private var accountContext
    @Environment(MediaService.self) private var mediaService
    @Environment(\.dismiss) private var dismiss

    // Section expanded states — Receipts expanded by default, all others collapsed
    @State private var expandedSections: Set<String> = ["receipts"]

    // Items picker
    @State private var showAddExistingItems = false
    @State private var pickerSelectedIds: Set<String> = []

    // Modal presentation
    @State private var showActionMenu = false
    @State private var showEditDetails = false
    @State private var showEditNotes = false
    @State private var showCreateItemsFromList = false
    @State private var showDeleteConfirmation = false
    @State private var showAddItemMenu = false
    @State private var menuPendingAction: (() -> Void)?

    // Items section filter/sort/search
    @State private var itemsSearchText = ""
    @State private var itemsActiveFilters: Set<ItemFilterOption> = []
    @State private var itemsActiveSort: ItemSortOption = .createdDesc
    @State private var itemsSelectedIds: Set<String> = []
    @State private var itemsShowSortMenu = false
    @State private var itemsShowFilterMenu = false

    // MARK: - Computed

    private var currentTransaction: Transaction {
        projectContext.transactions.first(where: { $0.id == transaction.id }) ?? transaction
    }

    private var transactionItems: [Item] {
        guard let ids = currentTransaction.itemIds, !ids.isEmpty else { return [] }
        let idSet = Set(ids)
        return projectContext.items.filter { idSet.contains($0.id ?? "") }
    }

    private var activeItems: [Item] {
        transactionItems.filter { $0.status != "returned" && $0.status != "sold" }
    }

    private var returnedItems: [Item] {
        transactionItems.filter { $0.status == "returned" }
    }

    private var soldItems: [Item] {
        transactionItems.filter { $0.status == "sold" }
    }

    private var processedActiveItems: [Item] {
        ListFilterSortCalculations.applyAllMultiFilters(
            activeItems,
            filters: itemsActiveFilters,
            sort: itemsActiveSort,
            search: itemsSearchText
        )
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

    private var completeness: TransactionCompletenessCalculations.TransactionCompleteness? {
        TransactionCompletenessCalculations.computeCompleteness(
            transaction: currentTransaction,
            items: activeItems,
            returnedItems: returnedItems,
            soldItems: soldItems
        )
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            AdaptiveContentWidth {
                LazyVStack(spacing: Spacing.md, pinnedViews: [.sectionHeaders]) {
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
                    itemsSection
                    returnedItemsSection
                    soldItemsSection
                    transactionAuditSection
                    movedItemsSection
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.vertical, Spacing.lg)
            }
        }
        .background(BrandColors.background)
        .background(SortMenu(
            isPresented: $itemsShowSortMenu,
            sortOptions: SortMenu.itemSortMenuItems(activeSort: itemsActiveSort, onSelect: { itemsActiveSort = $0 })
        ))
        .background(FilterMenu(
            isPresented: $itemsShowFilterMenu,
            filters: FilterMenu.filterMenuItems(
                activeFilters: itemsActiveFilters,
                scope: .project,
                onToggle: { option in
                    if itemsActiveFilters.contains(option) { itemsActiveFilters.remove(option) }
                    else { itemsActiveFilters.insert(option) }
                }
            ),
            closeOnItemPress: false
        ))
        .navBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .trailingNavBar) {
                Button { showActionMenu = true } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
        }
        .sheet(isPresented: $showActionMenu, onDismiss: {
            menuPendingAction?()
            menuPendingAction = nil
        }) {
            ActionMenuSheet(
                title: currentTransaction.source ?? "Transaction",
                items: actionMenuItems,
                onSelectAction: { action in menuPendingAction = action }
            )
            .sheetStyle(.quickMenu)
        }
        .confirmationDialog("Delete Transaction?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteTransaction()
            }
        } message: {
            Text("This action cannot be undone. All linked items will be unlinked.")
        }
        .sheet(isPresented: $showEditDetails) {
            EditTransactionDetailsModal(
                transaction: currentTransaction,
                budgetCategories: projectContext.budgetCategories,
                onSave: { fields in
                    updateTransaction(fields: fields)
                }
            )
            .sheetStyle(.form)
        }
        .sheet(isPresented: $showEditNotes) {
            EditNotesModal(
                notes: currentTransaction.notes ?? "",
                onSave: { newNotes in
                    updateTransaction(fields: ["notes": newNotes])
                }
            )
            .sheetStyle(.form)
        }
        .sheet(isPresented: $showCreateItemsFromList) {
            CreateItemsFromListModal(
                transaction: currentTransaction,
                onCreated: { parsedItems in
                    createItemsFromParsed(parsedItems)
                }
            )
            .sheetStyle(.form)
        }
        .sheet(isPresented: $showAddItemMenu, onDismiss: {
            menuPendingAction?()
            menuPendingAction = nil
        }) {
            ActionMenuSheet(
                title: "Add Items",
                items: [
                    ActionMenuItem(id: "add-existing", label: "Add Existing Items", icon: "plus.square.on.square", onPress: {
                        showAddExistingItems = true
                    }),
                    ActionMenuItem(id: "create-from-list", label: "Create from List", icon: "doc.text", onPress: {
                        showCreateItemsFromList = true
                    }),
                ],
                onSelectAction: { action in
                    menuPendingAction = action
                }
            )
            .sheetStyle(.quickMenu)
        }
        .sheet(isPresented: $showAddExistingItems) {
            NavigationStack {
                SharedItemsList(
                    mode: .picker(
                        scope: nil,
                        eligibilityCheck: nil,
                        onAddSingle: nil,
                        addedIds: Set(currentTransaction.itemIds ?? []),
                        onAddSelected: { addExistingItemsToTransaction() }
                    ),
                    emptyMessage: "No items available",
                    selectedIds: $pickerSelectedIds,
                    emptyIcon: "shippingbox",
                    filterScope: .project,
                    pickerItems: projectContext.items.filter { item in
                        guard let id = item.id else { return false }
                        return !(currentTransaction.itemIds ?? []).contains(id)
                    }
                )
                .navigationTitle("Add Existing Items")
                .navBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showAddExistingItems = false }
                    }
                }
            }
            .sheetStyle(.fullSheet)
        }
    }

    // MARK: - Badges

    @ViewBuilder
    private var badgesRow: some View {
        let badges = TransactionCardCalculations.badgeItems(
            transactionType: currentTransaction.transactionType,
            reimbursementType: currentTransaction.reimbursementType,
            hasEmailReceipt: currentTransaction.hasEmailReceipt ?? false,
            needsReview: currentTransaction.needsReview ?? false,
            budgetCategoryName: currentTransaction.budgetCategoryId.flatMap { categoryLookup[$0]?.name },
            status: currentTransaction.status
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
                Text(TransactionDisplayCalculations.displayName(for: currentTransaction))
                    .font(Typography.h2)
                    .foregroundStyle(BrandColors.textPrimary)

                HStack(spacing: Spacing.xs) {
                    Text("Amount:")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                    Text(TransactionDisplayCalculations.formattedAmount(for: currentTransaction))
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textPrimary)
                }

                HStack(spacing: Spacing.xs) {
                    Text("Date:")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                    Text(TransactionDisplayCalculations.formattedDate(for: currentTransaction))
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textPrimary)
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
        HStack(spacing: Spacing.sm) {
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
                onRemoveAttachment: { attachment in
                    removeReceiptImage(attachment)
                },
                onSetPrimary: { attachment in
                    setReceiptPrimary(attachment)
                },
                emptyStateMessage: "No receipts yet"
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
                emptyStateMessage: "No other images"
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
            if let notes = currentTransaction.notes, !notes.isEmpty {
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
                DetailRow(label: "Status", value: displayStatus(currentTransaction.status))
                DetailRow(label: "Purchased By", value: displayPurchasedBy(currentTransaction.purchasedBy))
                DetailRow(label: "Transaction Type", value: displayTransactionType(currentTransaction.transactionType))
                DetailRow(label: "Reimbursement", value: displayReimbursement(currentTransaction.reimbursementType))
                DetailRow(label: "Budget Category", value: selectedCategory?.name ?? "—")
                if selectedCategory?.metadata?.categoryType == .itemized {
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

    // 5. Items — Section with pinned composite header (collapse toggle + control bar)
    private var itemsSection: some View {
        Section {
            if expandedSections.contains("items") {
                if processedActiveItems.isEmpty {
                    Text(activeItems.isEmpty ? "No items yet" : "No items match your filters")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, Spacing.xl)
                } else {
                    ForEach(processedActiveItems) { item in
                        if let itemId = item.id {
                            if itemsSelectedIds.isEmpty {
                                NavigationLink(value: item) {
                                    ItemCard(
                                        item: item,
                                        priceLabel: item.purchasePriceCents.map { CurrencyFormatting.formatCentsWithDecimals($0) },
                                        isSelected: Binding(
                                            get: { itemsSelectedIds.contains(itemId) },
                                            set: { if $0 { itemsSelectedIds.insert(itemId) } else { itemsSelectedIds.remove(itemId) } }
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                            } else {
                                ItemCard(
                                    item: item,
                                    priceLabel: item.purchasePriceCents.map { CurrencyFormatting.formatCentsWithDecimals($0) },
                                    isSelected: Binding(
                                        get: { itemsSelectedIds.contains(itemId) },
                                        set: { if $0 { itemsSelectedIds.insert(itemId) } else { itemsSelectedIds.remove(itemId) } }
                                    ),
                                    onPress: {
                                        if itemsSelectedIds.contains(itemId) { itemsSelectedIds.remove(itemId) }
                                        else { itemsSelectedIds.insert(itemId) }
                                    }
                                )
                            }
                        }
                    }
                }
            }
        } header: {
            itemsSectionHeader
        }
    }

    private var itemsSectionHeader: some View {
        VStack(spacing: 0) {
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

            if expandedSections.contains("items") {
                let allIds = processedActiveItems.compactMap(\.id)
                let isAllSelected = !allIds.isEmpty && allIds.allSatisfy { itemsSelectedIds.contains($0) }
                NativeListControlBar(
                    searchText: $itemsSearchText,
                    searchPlaceholder: "Search items...",
                    onAdd: { showAddItemMenu = true },
                    style: .card
                ) {
                    Button {
                        itemsSelectedIds = isAllSelected ? [] : Set(allIds)
                    } label: {
                        SelectorCircle(isSelected: isAllSelected, indicator: .check)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Select all")
                } sortMenu: {
                    Button { itemsShowSortMenu = true } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundStyle(itemsActiveSort != .createdDesc ? BrandColors.primary : .secondary)
                    }
                } filterMenu: {
                    Button { itemsShowFilterMenu = true } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .foregroundStyle(!itemsActiveFilters.isEmpty ? BrandColors.primary : .secondary)
                    }
                }
            }
        }
        .background(BrandColors.background)
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
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(returnedItems) { item in
                        ItemCard(
                            item: item,
                            priceLabel: item.purchasePriceCents.map { CurrencyFormatting.formatCentsWithDecimals($0) },
                            statusOverride: "Returned"
                        )
                    }
                }
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
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(soldItems) { item in
                        ItemCard(
                            item: item,
                            priceLabel: item.purchasePriceCents.map { CurrencyFormatting.formatCentsWithDecimals($0) },
                            statusOverride: "Sold"
                        )
                    }
                }
                .padding(.top, Spacing.xs)
            }
        }
    }

    // 8. Transaction Audit (collapsed, conditional)
    // H17: Only show for itemized categories — audit tracks item price completeness against receipt,
    // which is only meaningful when the transaction has itemized items with individual prices.
    @ViewBuilder
    private var transactionAuditSection: some View {
        if let comp = completeness,
           selectedCategory?.metadata?.categoryType == .itemized {
            CollapsibleSection(
                title: "Transaction Audit",
                isExpanded: sectionBinding("transaction-audit"),
                statusBadge: comp.status != .complete ? "Needs Review" : nil
            ) {
                TransactionAuditPanel(
                    completeness: comp,
                    hasExplicitSubtotal: (currentTransaction.subtotalCents ?? 0) > 0,
                    itemsMissingPrice: transactionItems.filter { ($0.purchasePriceCents ?? 0) == 0 }
                )
                .padding(.top, Spacing.xs)
            }
        }
    }

    // Moved Items (non-collapsible, 50% opacity)
    // LineageEdgesService may be a stub — show empty section if no edges
    @ViewBuilder
    private var movedItemsSection: some View {
        // Stub: LineageEdgesService not yet implemented. Show nothing until edges exist.
        EmptyView()
    }

    // MARK: - Action Menu

    private var actionMenuItems: [ActionMenuItem] {
        // H10: Canonical inventory sale transactions are system-generated and must not be edited.
        let isCanonicalSale = currentTransaction.isCanonicalInventorySale == true
        var items: [ActionMenuItem] = []
        if !isCanonicalSale {
            items.append(ActionMenuItem(id: "edit", label: "Edit Details", icon: "pencil", onPress: {
                showEditDetails = true
            }))
            items.append(ActionMenuItem(id: "notes", label: "Edit Notes", icon: "note.text", onPress: {
                showEditNotes = true
            }))
        }
        items.append(ActionMenuItem(id: "delete", label: "Delete Transaction", icon: "trash",
                                    isDestructive: true, onPress: {
            showDeleteConfirmation = true
        }))
        return items
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

    private func displayStatus(_ status: String?) -> String {
        switch status?.lowercased() {
        case "pending": return "Pending"
        case "completed": return "Completed"
        case "canceled": return "Canceled"
        case "inventory-only": return "Inventory Only"
        default: return "—"
        }
    }

    private func displayPurchasedBy(_ value: String?) -> String {
        switch value?.lowercased() {
        case "client-card": return "Client Card"
        case "design-business": return "Design Business"
        case "missing": return "Missing"
        default: return "—"
        }
    }

    private func displayTransactionType(_ value: String?) -> String {
        switch value?.lowercased() {
        case "purchase": return "Purchase"
        case "sale": return "Sale"
        case "return": return "Return"
        case "to-inventory": return "To Inventory"
        default: return "—"
        }
    }

    private func displayReimbursement(_ value: String?) -> String {
        switch value?.lowercased() {
        case "owed-to-client": return "Owed to Client"
        case "owed-to-company": return "Owed to Business"
        case "none": return "None"
        default: return "—"
        }
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

    private func updateTransaction(fields: [String: Any]) {
        guard let accountId = accountContext.currentAccountId,
              let transactionId = transaction.id else {
            print("⚠️ updateTransaction skipped — missing accountId or transactionId")
            return
        }
        Task {
            do {
                try await TransactionsService(syncTracker: NoOpSyncTracker())
                    .updateTransaction(accountId: accountId, transactionId: transactionId, fields: fields)
            } catch {
                print("🔴 updateTransaction failed: \(error)")
            }
        }
    }

    private func addExistingItemsToTransaction() {
        guard let accountId = accountContext.currentAccountId,
              let transactionId = transaction.id else { return }

        let newIds = Array(pickerSelectedIds)
        guard !newIds.isEmpty else {
            showAddExistingItems = false
            return
        }

        let budgetCategoryId = currentTransaction.budgetCategoryId
        let db = Firestore.firestore()
        let batch = db.batch()
        let itemsRef = db.collection("accounts/\(accountId)/items")
        let txRef = db.collection("accounts/\(accountId)/transactions")

        // C8: Use a single WriteBatch so all item updates + transaction itemIds are atomic.
        for itemId in newIds {
            var fields: [String: Any] = [
                "transactionId": transactionId,
                "updatedAt": FieldValue.serverTimestamp(),
            ]
            if let budgetCategoryId { fields["budgetCategoryId"] = budgetCategoryId }
            // Backfill projectPriceCents for legacy items missing it
            if let item = projectContext.items.first(where: { $0.id == itemId }),
               item.projectPriceCents == nil,
               let purchasePrice = item.purchasePriceCents {
                fields["projectPriceCents"] = purchasePrice
            }
            batch.updateData(fields, forDocument: itemsRef.document(itemId))
        }

        // Atomically add all new itemIds to the transaction
        batch.updateData(
            ["itemIds": FieldValue.arrayUnion(newIds), "updatedAt": FieldValue.serverTimestamp()],
            forDocument: txRef.document(transactionId)
        )

        pickerSelectedIds.removeAll()
        showAddExistingItems = false

        Task {
            do {
                try await batch.commit()
            } catch {
                print("🔴 addExistingItemsToTransaction batch failed: \(error)")
            }
        }
    }

    private func deleteTransaction() {
        guard let accountId = accountContext.currentAccountId,
              let transactionId = transaction.id else { return }
        Task {
            try? await TransactionsService(syncTracker: NoOpSyncTracker())
                .deleteTransaction(accountId: accountId, transactionId: transactionId)
            dismiss()
        }
    }

    private func createItemsFromParsed(_ parsedItems: [ReceiptListParser.ParsedItem]) {
        guard let accountId = accountContext.currentAccountId,
              let projectId = projectContext.currentProjectId else { return }
        let service = ItemsService(syncTracker: NoOpSyncTracker())
        for parsed in parsedItems {
            var item = Item()
            item.accountId = accountId
            item.projectId = projectId
            item.name = parsed.name
            item.sku = parsed.sku
            item.purchasePriceCents = parsed.priceCents
            item.projectPriceCents = parsed.priceCents
            item.transactionId = currentTransaction.id
            item.budgetCategoryId = currentTransaction.budgetCategoryId
            _ = try? service.createItem(accountId: accountId, item: item)
        }
    }
}
