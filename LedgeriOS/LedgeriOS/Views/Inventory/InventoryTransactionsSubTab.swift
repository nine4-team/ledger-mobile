import SwiftUI

struct InventoryTransactionsSubTab: View {
    @Environment(InventoryContext.self) private var inventoryContext
    @Environment(AccountContext.self) private var accountContext

    @State private var searchText = ""
    @State private var isSearchVisible = false
    @State private var activeFilter: TransactionFilterOption = .all
    @State private var activeSort: TransactionSortOption = .dateDesc
    @State private var selectedIds: Set<String> = []
    @State private var showFilterMenu = false
    @State private var showSortMenu = false
    @State private var showBulkActionMenu = false
    @State private var showNewTransaction = false

    // MARK: - Computed

    private var processedTransactions: [Transaction] {
        TransactionFilterSortCalculations.applyAll(
            inventoryContext.transactions,
            filter: activeFilter,
            sort: activeSort,
            search: searchText
        )
    }

    private var allVisibleIds: [String] {
        processedTransactions.compactMap(\.id)
    }

    private var isAllSelected: Bool {
        SelectionCalculations.isAllSelected(selectedIds: selectedIds, allIds: allVisibleIds)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            controlBar

            if !processedTransactions.isEmpty {
                selectAllRow
            }

            if !selectedIds.isEmpty {
                ListSelectionInfo(
                    text: SelectionCalculations.selectionLabel(
                        count: selectedIds.count,
                        total: processedTransactions.count
                    )
                )
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xs)
            }

            content
        }
        .safeAreaInset(edge: .bottom) {
            if !selectedIds.isEmpty {
                BulkSelectionBar(
                    selectedCount: selectedIds.count,
                    totalCents: nil,
                    onBulkActions: { showBulkActionMenu = true },
                    onClear: { selectedIds.removeAll() }
                )
            }
        }
        .background(filterMenuPresenter)
        .background(sortMenuPresenter)
        .sheet(isPresented: $showBulkActionMenu) {
            ActionMenuSheet(
                title: "\(selectedIds.count) selected",
                items: [
                    ActionMenuItem(id: "clear-selection", label: "Clear Selection", icon: "xmark.circle", onPress: {
                        selectedIds.removeAll()
                    }),
                ]
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showNewTransaction) {
            Text("New Transaction — Coming Soon")
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        ListControlBar(
            searchText: $searchText,
            isSearchVisible: $isSearchVisible,
            actions: controlActions
        )
        .padding(.horizontal, Spacing.screenPadding)
    }

    private var controlActions: [ControlAction] {
        [
            ControlAction(
                id: "search",
                title: "",
                icon: "magnifyingglass",
                isActive: isSearchVisible,
                appearance: .iconOnly
            ) {
                withAnimation {
                    isSearchVisible.toggle()
                    if !isSearchVisible { searchText = "" }
                }
            },
            ControlAction(
                id: "sort",
                title: activeSort != .dateDesc ? TransactionFilterSortCalculations.sortLabel(for: activeSort) : "Sort",
                icon: "arrow.up.arrow.down",
                isActive: activeSort != .dateDesc,
                action: { showSortMenu = true }
            ),
            ControlAction(
                id: "filter",
                title: activeFilter != .all ? "Filter (1)" : "Filter",
                icon: "line.3.horizontal.decrease",
                isActive: activeFilter != .all,
                action: { showFilterMenu = true }
            ),
            ControlAction(
                id: "add",
                title: "",
                variant: .primary,
                icon: "plus",
                appearance: .iconOnly,
                action: { showNewTransaction = true }
            ),
        ]
    }

    // MARK: - Select All

    private var selectAllRow: some View {
        ListSelectAllRow(
            isChecked: isAllSelected,
            onToggle: {
                selectedIds = SelectionCalculations.selectAllToggle(
                    selectedIds: selectedIds,
                    allIds: allVisibleIds
                )
            }
        )
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if processedTransactions.isEmpty {
            ContentUnavailableView {
                Label(
                    activeFilter != .all || !searchText.isEmpty
                        ? "No transactions match your filters"
                        : "No inventory transactions yet",
                    systemImage: "creditcard"
                )
            }
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: Spacing.cardListGap) {
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
                .padding(.vertical, Spacing.sm)
            }
        }
    }

    @ViewBuilder
    private func transactionCardContent(for transaction: Transaction, txId: String) -> some View {
        TransactionCard(
            id: txId,
            source: transaction.source ?? "",
            amountCents: transaction.amountCents,
            transactionDate: transaction.transactionDate,
            notes: transaction.notes,
            budgetCategoryName: nil,
            transactionType: transaction.transactionType,
            needsReview: transaction.needsReview ?? false,
            reimbursementType: transaction.reimbursementType,
            hasEmailReceipt: transaction.hasEmailReceipt ?? false,
            status: transaction.status,
            itemCount: transaction.itemIds?.count
        )
    }

    // MARK: - Filter/Sort Menus

    private var filterMenuPresenter: some View {
        EmptyView()
            .sheet(isPresented: $showFilterMenu) {
                ActionMenuSheet(
                    title: "Filter",
                    items: filterMenuItems,
                    closeOnItemPress: true
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
    }

    private var sortMenuPresenter: some View {
        EmptyView()
            .sheet(isPresented: $showSortMenu) {
                ActionMenuSheet(
                    title: "Sort By",
                    items: sortMenuItems,
                    closeOnItemPress: true
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
    }

    private var filterMenuItems: [ActionMenuItem] {
        TransactionFilterOption.allCases.map { option in
            ActionMenuItem(
                id: option.rawValue,
                label: TransactionFilterSortCalculations.filterLabel(for: option),
                icon: activeFilter == option ? "checkmark.circle.fill" : "circle",
                onPress: { activeFilter = option }
            )
        }
    }

    private var sortMenuItems: [ActionMenuItem] {
        TransactionSortOption.allCases.map { option in
            ActionMenuItem(
                id: option.rawValue,
                label: TransactionFilterSortCalculations.sortLabel(for: option),
                icon: activeSort == option ? "checkmark" : nil,
                onPress: { activeSort = option }
            )
        }
    }

    // MARK: - Actions

    private func toggleSelection(_ txId: String) {
        if selectedIds.contains(txId) {
            selectedIds.remove(txId)
        } else {
            selectedIds.insert(txId)
        }
    }
}
