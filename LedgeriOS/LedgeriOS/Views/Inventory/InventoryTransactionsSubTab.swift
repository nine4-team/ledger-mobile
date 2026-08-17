import SwiftUI

private struct InventoryPurchaseIntentRow: Identifiable {
    let transaction: Transaction
    let projectName: String
    let categoryName: String?
    let state: InventoryPurchaseIntentState

    var id: String { transaction.id ?? UUID().uuidString }
}

struct InventoryTransactionsSubTab: View {
    @Environment(InventoryContext.self) private var inventoryContext
    @Environment(AccountContext.self) private var accountContext

    @State private var searchText = ""
    @State private var activeFilters = TransactionFilterState()
    @State private var activeSort: TransactionSortOption = .dateDesc
    @State private var selectedIds: Set<String> = []
    @State private var showBulkActionMenu = false
    @State private var showNewTransaction = false
    @State private var showSortMenu = false
    @State private var showFilterMenu = false
    @State private var navigationTransaction: Transaction?
    @State private var expandedInventoryGroups: Set<String> = []

    // Single-transaction actions
    @State private var actionTargetTransactionId: String?
    @State private var showSingleDeleteConfirmation = false

    // Bulk actions
    @State private var showBulkDeleteConfirmation = false

    // MARK: - Computed

    private var processedTransactions: [Transaction] {
        TransactionFilterSortCalculations.applyAllGrouped(
            inventoryContext.transactions,
            filters: activeFilters,
            sort: activeSort,
            search: searchText
        )
    }

    private var transactionRows: [TransactionListRow] {
        TransactionFilterSortCalculations.groupedRows(
            for: processedTransactions.filter { transaction in
                guard let id = transaction.id else { return true }
                return !plannedPurchaseIntentIds.contains(id)
            },
            scope: .inventory
        )
    }

    private var plannedPurchaseIntentIds: Set<String> {
        Set(plannedPurchaseIntents.map(\.id))
    }

    private var plannedPurchaseIntents: [InventoryPurchaseIntentRow] {
        processedTransactions.compactMap { transaction in
            guard transaction.purchaseHandling == .inventoryResale,
                  transaction.inventoryIntentResolvedAt == nil,
                  let intendedProjectId = transaction.intendedProjectId else { return nil }

            let project = accountContext.allProjects.first { $0.id == intendedProjectId }
            let category = transaction.intendedBudgetCategoryId.flatMap { categoryId in
                accountContext.allBudgetCategories.first { $0.id == categoryId }
            }
            let activeItems = (transaction.itemIds ?? []).compactMap { itemId in
                inventoryContext.items.first { $0.id == itemId }
            }

            let state = InventoryPurchaseIntentCalculations.state(
                transaction: transaction,
                activeItems: activeItems,
                projectExists: project != nil,
                categoryExists: category != nil
            )

            return InventoryPurchaseIntentRow(
                transaction: transaction,
                projectName: project?.name ?? "Unavailable project",
                categoryName: category?.name,
                state: state
            )
        }
    }

    private var uniqueSources: [String] {
        Array(Set(inventoryContext.transactions.compactMap(\.source).filter { !$0.isEmpty })).sorted()
    }

    private var allVisibleIds: [String] {
        processedTransactions.compactMap(\.id)
    }

    private var isAllSelected: Bool {
        SelectionCalculations.isAllSelected(selectedIds: selectedIds, allIds: allVisibleIds)
    }

    private var selectedTransactionTotalCents: Int? {
        let total = SelectionCalculations.totalCentsForSelectedTransactions(
            selectedIds: selectedIds,
            transactions: processedTransactions
        )
        return total != 0 ? total : nil
    }

    private var selectedTransactions: [Transaction] {
        processedTransactions.filter { tx in
            guard let id = tx.id else { return false }
            return selectedIds.contains(id)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .scrollContentTopFade()
        .safeAreaInset(edge: .top, spacing: 0) {
            controlBar
        }
        .safeAreaInset(edge: .bottom) {
            if !selectedIds.isEmpty {
                BulkSelectionBar(
                    selectedCount: selectedIds.count,
                    totalCount: processedTransactions.count,
                    totalCents: selectedTransactionTotalCents,
                    onBulkActions: { showBulkActionMenu = true },
                    onClear: { selectedIds.removeAll() }
                )
            }
        }
        .adaptivePresentation(isPresented: $showBulkActionMenu, style: .quickMenu) {
            ActionMenuSheet(
                title: "\(selectedIds.count) selected",
                items: bulkActionMenuItems,
                onSelectAction: { action in action() }
            )
        }
        .confirmationDialog("Delete \(selectedIds.count) transactions?", isPresented: $showBulkDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteSelectedTransactions() }
        } message: {
            Text("This action cannot be undone.")
        }
        .confirmationDialog("Delete transaction?", isPresented: $showSingleDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteSingleTransaction() }
        } message: {
            Text("This action cannot be undone.")
        }
        .onChange(of: showNewTransaction) { _, newValue in
            print("🟡 [TxSubTab] showNewTransaction changed to \(newValue)")
        }
        .adaptivePresentation(isPresented: $showNewTransaction, style: .form) {
            let _ = print("🟢 [TxSubTab] NewTransactionView sheet body evaluated")
            NewTransactionView(
                context: .inventory,
                onCreated: { navigationTransaction = $0 }
            )
        }
        .navigationDestination(item: $navigationTransaction) { tx in
            TransactionDetailView(transaction: tx)
        }
        .background(SortMenu(
            isPresented: $showSortMenu,
            sortOptions: SortMenu.transactionSortMenuItems(
                activeSort: activeSort,
                onSelect: { activeSort = $0 }
            )
        ))
        .background(TransactionFilterMenu(
            isPresented: $showFilterMenu,
            filterState: $activeFilters,
            sources: uniqueSources
        ))
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        NativeListControlBar(
            searchText: $searchText,
            searchPlaceholder: "Search transactions...",
            onAdd: {
                print("🟡 [TxSubTab] inline + tapped, setting showNewTransaction = true")
                showNewTransaction = true
            },
            style: .plain
        ) {
            if !processedTransactions.isEmpty {
                Button {
                    selectedIds = SelectionCalculations.selectAllToggle(
                        selectedIds: selectedIds,
                        allIds: allVisibleIds
                    )
                } label: {
                    SelectorCircle(isSelected: isAllSelected, indicator: .check)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Select all")
            }
        } sortMenu: {
            Button { showSortMenu = true } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundStyle(activeSort != .dateDesc ? BrandColors.primary : .secondary)
            }
        } filterMenu: {
            Button { showFilterMenu = true } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(activeFilters.isActive ? BrandColors.primary : .secondary)
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if processedTransactions.isEmpty {
            ContentUnavailableView {
                Label(
                    activeFilters.isActive || !searchText.isEmpty
                        ? "No transactions match your filters"
                        : "No inventory transactions yet",
                    systemImage: "creditcard"
                )
            }
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if !plannedPurchaseIntents.isEmpty {
                        plannedForProjectsSection
                    }

                    if !transactionRows.isEmpty {
                        LazyVGrid(
                            columns: Dimensions.listColumns,
                            alignment: .leading,
                            spacing: Spacing.cardListGap
                        ) {
                            ForEach(transactionRows) { row in
                                transactionRow(row)
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.sm)
            }
        }
    }

    private var plannedForProjectsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Planned for Projects")
                    .font(Typography.h3)
                    .foregroundStyle(BrandColors.textPrimary)
                Spacer()
                Text("\(plannedPurchaseIntents.count)")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
            }

            Text("Inventory purchases that still need items entered, priced, or sold to their intended project.")
                .font(Typography.small)
                .foregroundStyle(BrandColors.textSecondary)

            LazyVGrid(
                columns: Dimensions.listColumns,
                alignment: .leading,
                spacing: Spacing.cardListGap
            ) {
                ForEach(plannedPurchaseIntents) { intent in
                    Button {
                        navigationTransaction = intent.transaction
                    } label: {
                        Card(accent: true) {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                HStack {
                                    Text(intent.projectName)
                                        .font(Typography.body.weight(.semibold))
                                        .foregroundStyle(BrandColors.textPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(BrandColors.textSecondary)
                                }
                                if let source = intent.transaction.source, !source.isEmpty {
                                    Text(source)
                                        .font(Typography.small)
                                        .foregroundStyle(BrandColors.textSecondary)
                                }
                                if let categoryName = intent.categoryName {
                                    Text(categoryName)
                                        .font(Typography.small)
                                        .foregroundStyle(BrandColors.textSecondary)
                                }
                                Label(intent.state.label, systemImage: intent.state.icon)
                                    .font(Typography.small.weight(.semibold))
                                    .foregroundStyle(intent.state == .readyToSell
                                                     ? BrandColors.primary
                                                     : BrandColors.textSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func transactionRow(_ row: TransactionListRow) -> some View {
        switch row {
        case .transaction(let transaction):
            transactionNavigationCard(for: transaction)
        case .inventoryGroup(let group):
            InventoryTransactionGroupCard(
                group: group,
                isExpanded: Binding(
                    get: { expandedInventoryGroups.contains(group.id) },
                    set: { isExpanded in
                        if isExpanded {
                            expandedInventoryGroups.insert(group.id)
                        } else {
                            expandedInventoryGroups.remove(group.id)
                        }
                    }
                ),
                isSelected: Binding(
                    get: { !group.transactionIds.isEmpty && Set(group.transactionIds).isSubset(of: selectedIds) },
                    set: { isSelected in setGroupSelection(group, isSelected: isSelected) }
                ),
                onSelectAll: { isSelected in setGroupSelection(group, isSelected: isSelected) }
            ) {
                ForEach(group.transactions) { transaction in
                    transactionNavigationCard(for: transaction)
                }
            }
        }
    }

    @ViewBuilder
    private func transactionNavigationCard(for transaction: Transaction) -> some View {
        if let txId = transaction.id {
            if selectedIds.isEmpty {
                transactionCardContent(for: transaction, txId: txId)
            } else {
                transactionCardContent(for: transaction, txId: txId)
                    .onTapGesture { toggleSelection(txId) }
            }
        }
    }

    @ViewBuilder
    private func transactionCardContent(for transaction: Transaction, txId: String) -> some View {
        TransactionCard(
            transaction: transaction,
            isSelected: Binding(
                get: { selectedIds.contains(txId) },
                set: { if $0 { selectedIds.insert(txId) } else { selectedIds.remove(txId) } }
            ),
            menuItems: selectedIds.isEmpty ? singleTransactionMenuItems(for: transaction, txId: txId) : [],
            onPress: selectedIds.isEmpty ? {
                navigationTransaction = transaction
            } : nil
        )
    }

    // MARK: - Menu Items

    private func singleTransactionMenuItems(for transaction: Transaction, txId: String) -> [ActionMenuItem] {
        TransactionMenuBuilder.buildCardMenu(
            transaction: transaction,
            callbacks: SingleTransactionMenuCallbacks(
                onCopyID: { Clipboard.copy(txId) },
                onDelete: {
                    actionTargetTransactionId = txId
                    showSingleDeleteConfirmation = true
                }
            )
        )
    }

    private var bulkActionMenuItems: [ActionMenuItem] {
        TransactionMenuBuilder.buildBulkMenu(
            callbacks: BulkTransactionMenuCallbacks(
                onCopyIDs: { Clipboard.copyLines(selectedIds) },
                onDelete: { showBulkDeleteConfirmation = true }
            )
        )
    }

    // MARK: - Actions

    private func toggleSelection(_ txId: String) {
        if selectedIds.contains(txId) {
            selectedIds.remove(txId)
        } else {
            selectedIds.insert(txId)
        }
    }

    private func setGroupSelection(_ group: InventoryTransactionGroup, isSelected: Bool) {
        if isSelected {
            selectedIds.formUnion(group.transactionIds)
        } else {
            selectedIds.subtract(group.transactionIds)
        }
    }

    private func deleteSingleTransaction() {
        guard let accountId = accountContext.currentAccountId,
              let txId = actionTargetTransactionId else { return }
        let service = TransactionsService()
        Task { try? await service.deleteTransaction(accountId: accountId, transactionId: txId) }
    }

    private func deleteSelectedTransactions() {
        guard let accountId = accountContext.currentAccountId else { return }
        let service = TransactionsService()
        for tx in selectedTransactions {
            guard let txId = tx.id else { continue }
            Task { try? await service.deleteTransaction(accountId: accountId, transactionId: txId) }
        }
        selectedIds.removeAll()
    }
}
