import SwiftUI

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
        let tuples = processedTransactions.compactMap { tx -> (id: String, cents: Int, type: String?)? in
            guard let id = tx.id, let cents = tx.amountCents else { return nil }
            return (id: id, cents: cents, type: tx.transactionType)
        }
        let total = SelectionCalculations.totalCentsForSelectedTransactions(selectedIds: selectedIds, transactions: tuples)
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
        .adaptivePresentation(isPresented: $showNewTransaction, style: .form) {
            NewTransactionView(context: .inventory)
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
            onAdd: { showNewTransaction = true },
            style: .card
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
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: Dimensions.cardMinWidth), spacing: Spacing.cardListGap)],
                    alignment: .leading,
                    spacing: Spacing.cardListGap
                ) {
                    ForEach(processedTransactions) { transaction in
                        if let txId = transaction.id {
                            if selectedIds.isEmpty {
                                NavigationLink(value: transaction) {
                                    transactionCardContent(for: transaction, txId: txId)
                                }
                                .buttonStyle(.plain)
                            } else {
                                transactionCardContent(for: transaction, txId: txId)
                                    .onTapGesture { toggleSelection(txId) }
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.sm)
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
            menuItems: selectedIds.isEmpty ? singleTransactionMenuItems(for: transaction, txId: txId) : []
        )
    }

    // MARK: - Menu Items

    private func singleTransactionMenuItems(for transaction: Transaction, txId: String) -> [ActionMenuItem] {
        TransactionMenuBuilder.buildCardMenu(
            transaction: transaction,
            callbacks: SingleTransactionMenuCallbacks(
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
