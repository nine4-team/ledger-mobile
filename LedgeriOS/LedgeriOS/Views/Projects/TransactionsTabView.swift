import SwiftUI

/// Data-driven transaction list replacing `TransactionsTabPlaceholder`.
/// Shows real transactions sorted date-desc with search/sort/filter toolbar.
struct TransactionsTabView: View {
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

    // MARK: - Computed

    private var processedTransactions: [Transaction] {
        TransactionFilterSortCalculations.applyAllGrouped(
            projectContext.transactions,
            filters: activeFilters,
            sort: activeSort,
            search: searchText
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
        .scrollContentTopFade()
        .safeAreaInset(edge: .top, spacing: 0) {
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
            .sheetStyle(.quickMenu)
        }
        .sheet(isPresented: $showNewTransaction) {
            if let projectId = projectContext.currentProjectId {
                NewTransactionView(context: .project(projectId))
                    .sheetStyle(.form)
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
        let catName = transaction.budgetCategoryId.flatMap { categoryLookup[$0]?.name }

        TransactionCard(
            transaction: transaction,
            budgetCategoryName: catName,
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
