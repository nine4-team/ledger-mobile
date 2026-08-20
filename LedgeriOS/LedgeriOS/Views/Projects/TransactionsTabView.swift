import SwiftUI

/// Data-driven transaction list replacing `TransactionsTabPlaceholder`.
/// Shows real transactions sorted date-desc with search/sort/filter toolbar.
struct TransactionsTabView: View {
    @Binding var showExportSheet: Bool
    @Environment(ProjectContext.self) private var projectContext
    @Environment(AccountContext.self) private var accountContext

    @State private var searchText = ""
    @State private var activeFilters = TransactionFilterState()
    @State private var activeSort: TransactionSortOption = .dateDesc
    @State private var selectedIds: Set<String> = []
    @State private var showBulkActionMenu = false
    @State private var showNewTransaction = false
    @State private var showSortMenu = false
    @State private var showFilterMenu = false
    @State private var exportedFileURL: URL?
    @State private var selectedTransactionId: String?
    @State private var initialTransaction: Transaction?
    @State private var showTransactionDetail = false
    @State private var expandedInventoryGroups: Set<String> = []

    // Bulk actions
    @State private var showBulkDeleteConfirmation = false

    // Single-transaction actions
    @State private var actionTargetTransactionId: String?
    @State private var showSingleDeleteConfirmation = false

    // MARK: - Computed

    private var processedTransactions: [Transaction] {
        TransactionFilterSortCalculations.applyAllGrouped(
            projectContext.transactions,
            filters: activeFilters,
            sort: activeSort,
            search: searchText
        )
    }

    private var transactionRows: [TransactionListRow] {
        TransactionFilterSortCalculations.groupedRows(
            for: processedTransactions,
            scope: .project
        )
    }

    private var uniqueSources: [String] {
        Array(Set(projectContext.transactions.compactMap(\.source).filter { !$0.isEmpty })).sorted()
    }

    private var budgetCategoryPairs: [(id: String, name: String)] {
        projectContext.budgetCategories.compactMap { cat in
            guard let id = cat.id else { return nil }
            return (id: id, name: cat.name)
        }
    }

    private var categoryLookup: [String: BudgetCategory] {
        Dictionary(
            uniqueKeysWithValues: projectContext.budgetCategories.compactMap { cat in
                guard let id = cat.id else { return nil }
                return (id, cat)
            }
        )
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
                .background(BrandColors.background)
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
        .adaptivePresentation(isPresented: $showNewTransaction, style: .form) {
            if let projectId = projectContext.currentProjectId {
                NewTransactionView(
                    context: .project(projectId),
                    onCreated: { openTransaction($0) }
                )
            }
        }
        .navigationDestination(isPresented: $showTransactionDetail) {
            if let selectedTransactionId {
                TransactionDetailContainer(
                    transactionId: selectedTransactionId,
                    projectId: initialTransaction?.projectId ?? projectContext.currentProjectId,
                    initialTransaction: initialTransaction
                )
            } else {
                ContentUnavailableView("Transaction Unavailable", systemImage: "doc.text")
            }
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
            budgetCategories: budgetCategoryPairs,
            sources: uniqueSources
        ))
        .onReceive(NotificationCenter.default.publisher(for: .createTransaction)) { _ in
            showNewTransaction = true
        }
        .adaptivePresentation(isPresented: $showExportSheet, style: .selectionMenu, onDismiss: {
            if let url = exportedFileURL {
                exportedFileURL = nil
                ShareHelper.share(url: url)
            }
        }) {
            ExportTransactionsModal(
                transactions: processedTransactions,
                categories: projectContext.budgetCategories,
                items: projectContext.items,
                projectId: projectContext.currentProjectId,
                onExport: { url in exportedFileURL = url }
            )
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        NativeListControlBar(
            searchText: $searchText,
            searchPlaceholder: "Search transactions...",
            onAdd: { showNewTransaction = true },
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
                        : "No transactions yet",
                    systemImage: "creditcard"
                )
            }
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(
                    columns: Dimensions.listColumns,
                    alignment: .leading,
                    spacing: Spacing.cardListGap
                ) {
                    ForEach(transactionRows) { row in
                        transactionRow(row)
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.vertical, Spacing.sm)
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
        let catName: String? = {
            guard let catId = transaction.budgetCategoryId else { return nil }
            if catId == "uncategorized" { return "Uncategorized" }
            return categoryLookup[catId]?.name
        }()

        TransactionCard(
            transaction: transaction,
            budgetCategoryName: catName,
            isSelected: Binding(
                get: { selectedIds.contains(txId) },
                set: { if $0 { selectedIds.insert(txId) } else { selectedIds.remove(txId) } }
            ),
            menuItems: selectedIds.isEmpty ? singleTransactionMenuItems(for: transaction, txId: txId) : [],
            onPress: selectedIds.isEmpty ? {
                openTransaction(transaction)
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

    private func openTransaction(_ transaction: Transaction) {
        guard let id = transaction.id else { return }
        selectedTransactionId = id
        initialTransaction = transaction
        showTransactionDetail = true
    }

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
