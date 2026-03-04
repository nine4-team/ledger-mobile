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

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
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
        .safeAreaInset(edge: .top) {
            controlBar
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
            onAdd: { showNewTransaction = true }
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
                AdaptiveContentWidth {
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
            itemCount: transaction.itemIds?.count,
            isSelected: Binding(
                get: { selectedIds.contains(txId) },
                set: { if $0 { selectedIds.insert(txId) } else { selectedIds.remove(txId) } }
            ),
            menuItems: selectedIds.isEmpty ? singleTransactionMenuItems(for: txId) : []
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

    private func singleTransactionMenuItems(for txId: String) -> [ActionMenuItem] {
        [
            ActionMenuItem(id: "select", label: "Select", icon: "checkmark.circle", onPress: {
                selectedIds.insert(txId)
            }),
        ]
    }
}
