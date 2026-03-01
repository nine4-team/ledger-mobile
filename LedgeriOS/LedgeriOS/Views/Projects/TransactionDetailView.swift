import SwiftUI

/// Full transaction detail screen with hero card, Next Steps, 8 collapsible sections,
/// Moved Items, and delete action.
struct TransactionDetailView: View {
    let transaction: Transaction

    @Environment(ProjectContext.self) private var projectContext
    @Environment(AccountContext.self) private var accountContext
    @Environment(\.dismiss) private var dismiss

    // Section expanded states — Receipts expanded by default, all others collapsed
    @State private var expandedSections: Set<String> = ["receipts"]

    // Item list local sort/filter (independent of main transaction list)
    @State private var itemSort: ItemSortOption = .createdDesc
    @State private var itemFilter: ItemFilterOption = .all

    // Modal presentation
    @State private var showEditDetails = false
    @State private var showEditNotes = false
    @State private var showCreateItemsFromList = false
    @State private var showDeleteConfirmation = false
    @State private var showAddItemMenu = false
    @State private var menuPendingAction: (() -> Void)?

    // MARK: - Computed

    private var transactionItems: [Item] {
        let itemIds = transaction.itemIds ?? []
        guard !itemIds.isEmpty else { return [] }
        let idSet = Set(itemIds)
        return projectContext.items.filter { item in
            guard let id = item.id else { return false }
            return idSet.contains(id)
        }
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

    private var filteredSortedItems: [Item] {
        ListFilterSortCalculations.applyAllFilters(
            activeItems,
            filter: itemFilter,
            sort: itemSort,
            search: ""
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
        transaction.budgetCategoryId.flatMap { categoryLookup[$0] }
    }

    private var nextSteps: [TransactionNextStepsCalculations.NextStep] {
        TransactionNextStepsCalculations.computeNextSteps(
            transaction: transaction,
            itemCount: transactionItems.count,
            budgetCategories: categoryLookup
        )
    }

    private var allStepsComplete: Bool {
        TransactionNextStepsCalculations.allStepsComplete(nextSteps)
    }

    private var completeness: TransactionCompletenessCalculations.TransactionCompleteness? {
        TransactionCompletenessCalculations.computeCompleteness(
            transaction: transaction,
            items: activeItems,
            returnedItems: returnedItems,
            soldItems: soldItems
        )
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                heroCard
                nextStepsCard
                sectionsContent
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.lg)
        }
        .background(BrandColors.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(transaction.source ?? "Transaction")
                    .font(Typography.h3)
                    .foregroundStyle(BrandColors.textPrimary)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(BrandColors.destructive)
                }
            }
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
                transaction: transaction,
                budgetCategories: projectContext.budgetCategories,
                onSave: { fields in
                    updateTransaction(fields: fields)
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showEditNotes) {
            EditNotesModal(
                notes: transaction.notes ?? "",
                onSave: { newNotes in
                    updateTransaction(fields: ["notes": newNotes])
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCreateItemsFromList) {
            CreateItemsFromListModal(
                transaction: transaction,
                onCreated: { parsedItems in
                    createItemsFromParsed(parsedItems)
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAddItemMenu, onDismiss: {
            menuPendingAction?()
            menuPendingAction = nil
        }) {
            ActionMenuSheet(
                title: "Add Items",
                items: [
                    ActionMenuItem(id: "create-from-list", label: "Create from List", icon: "doc.text", onPress: {
                        showCreateItemsFromList = true
                    }),
                ],
                onSelectAction: { action in
                    menuPendingAction = action
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(transaction.source ?? "Transaction")
                    .font(Typography.h2)
                    .foregroundStyle(BrandColors.textPrimary)

                Text(TransactionCardCalculations.formattedAmount(
                    amountCents: transaction.amountCents,
                    transactionType: transaction.transactionType
                ))
                .font(.system(.title2, weight: .bold))
                .foregroundStyle(BrandColors.textPrimary)

                Text(TransactionCardCalculations.formattedDate(transaction.transactionDate))
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textSecondary)

                // Badge row
                let badges = TransactionCardCalculations.badgeItems(
                    transactionType: transaction.transactionType,
                    reimbursementType: transaction.reimbursementType,
                    hasEmailReceipt: transaction.hasEmailReceipt ?? false,
                    needsReview: transaction.needsReview ?? false,
                    budgetCategoryName: selectedCategory?.name,
                    status: transaction.status
                )
                if !badges.isEmpty {
                    HStack(spacing: Spacing.sm) {
                        ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                            Badge(text: badge.text, color: badge.color)
                        }
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

                    // Incomplete steps
                    VStack(spacing: Spacing.xs) {
                        ForEach(incompleteSteps) { step in
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: step.sfSymbol)
                                    .font(.system(size: 14))
                                    .foregroundStyle(BrandColors.textSecondary)
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Circle()
                                            .stroke(BrandColors.borderSecondary, lineWidth: 1.5)
                                    )

                                Text(step.label)
                                    .font(Typography.body)
                                    .foregroundStyle(BrandColors.textPrimary)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(BrandColors.textTertiary)
                            }
                            .frame(minHeight: 36)
                        }
                    }

                    // Completed steps (compact)
                    if !completedSteps.isEmpty {
                        Divider()
                        VStack(spacing: Spacing.xs) {
                            ForEach(completedSteps) { step in
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(BrandColors.primary)

                                    Text(step.label)
                                        .font(Typography.caption)
                                        .foregroundStyle(BrandColors.textSecondary)
                                        .strikethrough()
                                }
                                .frame(minHeight: 24)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var sectionsContent: some View {
        VStack(spacing: Spacing.md) {
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
    }

    // 1. Receipts (default expanded)
    private var receiptsSection: some View {
        CollapsibleSection(
            title: "Receipts",
            isExpanded: sectionBinding("receipts"),
            badge: "\(transaction.receiptImages?.count ?? 0)"
        ) {
            if let images = transaction.receiptImages, !images.isEmpty {
                ThumbnailGrid(attachments: images)
                    .padding(.top, Spacing.xs)
            } else {
                Text("No receipts yet")
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textSecondary)
                    .padding(.top, Spacing.xs)
            }
        }
    }

    // 2. Other Images (collapsed)
    private var otherImagesSection: some View {
        CollapsibleSection(
            title: "Other Images",
            isExpanded: sectionBinding("other-images"),
            badge: "\(transaction.otherImages?.count ?? 0)"
        ) {
            if let images = transaction.otherImages, !images.isEmpty {
                ThumbnailGrid(attachments: images)
                    .padding(.top, Spacing.xs)
            } else {
                Text("No other images")
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textSecondary)
                    .padding(.top, Spacing.xs)
            }
        }
    }

    // 3. Notes (collapsed)
    private var notesSection: some View {
        CollapsibleSection(
            title: "Notes",
            isExpanded: sectionBinding("notes"),
            onEdit: { showEditNotes = true }
        ) {
            if let notes = transaction.notes, !notes.isEmpty {
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
                DetailRow(label: "Vendor / Source", value: transaction.source ?? "—")
                DetailRow(label: "Amount", value: TransactionCardCalculations.formattedAmount(
                    amountCents: transaction.amountCents,
                    transactionType: transaction.transactionType
                ))
                DetailRow(label: "Date", value: TransactionCardCalculations.formattedDate(transaction.transactionDate))
                DetailRow(label: "Status", value: displayStatus(transaction.status))
                DetailRow(label: "Purchased By", value: displayPurchasedBy(transaction.purchasedBy))
                DetailRow(label: "Transaction Type", value: displayTransactionType(transaction.transactionType))
                DetailRow(label: "Reimbursement", value: displayReimbursement(transaction.reimbursementType))
                DetailRow(label: "Budget Category", value: selectedCategory?.name ?? "—")
                if selectedCategory?.metadata?.categoryType == .itemized {
                    DetailRow(label: "Email Receipt", value: (transaction.hasEmailReceipt ?? false) ? "Yes" : "No")
                    DetailRow(
                        label: "Subtotal",
                        value: transaction.subtotalCents.map { CurrencyFormatting.formatCentsWithDecimals($0) } ?? "—"
                    )
                    DetailRow(
                        label: "Tax Rate",
                        value: transaction.taxRatePct.map { String(format: "%.2f%%", $0) } ?? "—",
                        showDivider: false
                    )
                } else {
                    DetailRow(label: "Email Receipt", value: (transaction.hasEmailReceipt ?? false) ? "Yes" : "No", showDivider: false)
                }
            }
            .padding(.top, Spacing.xs)
        }
    }

    // 5. Items (collapsed)
    private var itemsSection: some View {
        CollapsibleSection(
            title: "Items",
            isExpanded: sectionBinding("items"),
            badge: "\(activeItems.count)",
            onAdd: { showAddItemMenu = true }
        ) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if !filteredSortedItems.isEmpty {
                    ForEach(filteredSortedItems) { item in
                        ItemCard(
                            name: item.name,
                            sku: item.sku,
                            priceLabel: item.purchasePriceCents.map { CurrencyFormatting.formatCentsWithDecimals($0) }
                        )
                    }
                } else {
                    Text("No items yet")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
            .padding(.top, Spacing.xs)
        }
    }

    // 6. Returned Items (collapsed, conditional)
    @ViewBuilder
    private var returnedItemsSection: some View {
        if !returnedItems.isEmpty {
            CollapsibleSection(
                title: "Returned Items",
                isExpanded: sectionBinding("returned-items"),
                badge: "\(returnedItems.count)"
            ) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(returnedItems) { item in
                        ItemCard(
                            name: item.name,
                            sku: item.sku,
                            priceLabel: item.purchasePriceCents.map { CurrencyFormatting.formatCentsWithDecimals($0) },
                            statusLabel: "Returned"
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
                badge: "\(soldItems.count)"
            ) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(soldItems) { item in
                        ItemCard(
                            name: item.name,
                            sku: item.sku,
                            priceLabel: item.purchasePriceCents.map { CurrencyFormatting.formatCentsWithDecimals($0) },
                            statusLabel: "Sold"
                        )
                    }
                }
                .padding(.top, Spacing.xs)
            }
        }
    }

    // 8. Transaction Audit (collapsed, conditional)
    @ViewBuilder
    private var transactionAuditSection: some View {
        if let comp = completeness {
            CollapsibleSection(
                title: "Transaction Audit",
                isExpanded: sectionBinding("transaction-audit")
            ) {
                VStack(spacing: 0) {
                    DetailRow(label: "Status") {
                        Badge(
                            text: TransactionCompletenessCalculations.statusLabel(comp.status),
                            color: completenessColor(comp.status)
                        )
                    }
                    DetailRow(
                        label: "Items Total",
                        value: CurrencyFormatting.formatCentsWithDecimals(comp.itemsNetTotalCents)
                    )
                    DetailRow(
                        label: "Transaction Subtotal",
                        value: CurrencyFormatting.formatCentsWithDecimals(comp.transactionSubtotalCents)
                    )
                    DetailRow(
                        label: "Variance",
                        value: CurrencyFormatting.formatCentsWithDecimals(comp.varianceCents)
                            + " (\(String(format: "%.1f%%", comp.variancePercent)))",
                        showDivider: false
                    )
                }
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

    private func completenessColor(_ status: TransactionCompletenessCalculations.CompletenessStatus) -> SwiftUI.Color {
        switch status {
        case .complete: return StatusColors.metText
        case .near: return StatusColors.inProgressText
        case .incomplete: return StatusColors.missedText
        case .over: return StatusColors.badgeError
        }
    }

    // MARK: - Actions

    private func updateTransaction(fields: [String: Any]) {
        guard let accountId = accountContext.currentAccountId,
              let transactionId = transaction.id else { return }
        Task {
            try? await TransactionsService(syncTracker: NoOpSyncTracker())
                .updateTransaction(accountId: accountId, transactionId: transactionId, fields: fields)
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
            item.transactionId = transaction.id
            item.budgetCategoryId = transaction.budgetCategoryId
            _ = try? service.createItem(accountId: accountId, item: item)
        }
    }
}
