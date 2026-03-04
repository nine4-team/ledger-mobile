import SwiftUI

struct InventoryTransactionsSubTab: View {
    @Environment(InventoryContext.self) private var inventoryContext
    @Environment(AccountContext.self) private var accountContext

    @State private var searchText = ""
    @State private var activeFilter: TransactionFilterOption = .all
    @State private var activeSort: TransactionSortOption = .dateDesc
    @State private var selectedIds: Set<String> = []
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
            Menu {
                Picker("Sort", selection: $activeSort) {
                    ForEach(TransactionSortOption.allCases, id: \.self) { option in
                        Text(TransactionFilterSortCalculations.sortLabel(for: option)).tag(option)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundStyle(activeSort != .dateDesc ? BrandColors.primary : .secondary)
            }
        } filterMenu: {
            Menu {
                Picker("Filter", selection: $activeFilter) {
                    ForEach(TransactionFilterOption.allCases, id: \.self) { option in
                        Text(TransactionFilterSortCalculations.filterLabel(for: option)).tag(option)
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(activeFilter != .all ? BrandColors.primary : .secondary)
            }
        }
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

    // MARK: - Actions

    private func toggleSelection(_ txId: String) {
        if selectedIds.contains(txId) {
            selectedIds.remove(txId)
        } else {
            selectedIds.insert(txId)
        }
    }
}
