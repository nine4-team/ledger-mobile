import SwiftUI

// MARK: - Transaction Filter/Sort Enums

enum TransactionFilterOption: String, CaseIterable {
    case all
    case needsReview = "needs-review"
    case hasReceipt = "has-receipt"
    case purchase
    case sale
    case returnType = "return"
}

enum TransactionSortOption: String, CaseIterable {
    case dateDesc = "date-desc"
    case dateAsc = "date-asc"
    case amountDesc = "amount-desc"
    case amountAsc = "amount-asc"
}

// MARK: - Transaction Filter/Sort Calculations

enum TransactionFilterSortCalculations {

    static func applyFilter(_ transactions: [Transaction], filter: TransactionFilterOption) -> [Transaction] {
        switch filter {
        case .all:
            return transactions
        case .needsReview:
            return transactions.filter { $0.needsReview == true }
        case .hasReceipt:
            return transactions.filter { $0.hasEmailReceipt == true || !($0.receiptImages ?? []).isEmpty }
        case .purchase:
            return transactions.filter { $0.transactionType == "purchase" }
        case .sale:
            return transactions.filter { $0.transactionType == "sale" }
        case .returnType:
            return transactions.filter { $0.transactionType == "return" }
        }
    }

    static func applySort(_ transactions: [Transaction], sort: TransactionSortOption) -> [Transaction] {
        transactions.sorted(by: sortComparator(for: sort))
    }

    static func applySearch(_ transactions: [Transaction], query: String) -> [Transaction] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return transactions }
        let needle = trimmed.lowercased()
        return transactions.filter { tx in
            let haystack = [
                tx.source ?? "",
                tx.notes ?? "",
                tx.budgetCategoryId ?? "",
            ].joined(separator: " ").lowercased()
            return haystack.contains(needle)
        }
    }

    static func applyAll(
        _ transactions: [Transaction],
        filter: TransactionFilterOption,
        sort: TransactionSortOption,
        search: String
    ) -> [Transaction] {
        let filtered = applyFilter(transactions, filter: filter)
        let searched = applySearch(filtered, query: search)
        return applySort(searched, sort: sort)
    }

    private static func sortComparator(for option: TransactionSortOption) -> (Transaction, Transaction) -> Bool {
        switch option {
        case .dateDesc:
            return { a, b in
                let dateA = a.transactionDate ?? ""
                let dateB = b.transactionDate ?? ""
                if dateA != dateB { return dateA > dateB }
                return (a.id ?? "") > (b.id ?? "")
            }
        case .dateAsc:
            return { a, b in
                let dateA = a.transactionDate ?? ""
                let dateB = b.transactionDate ?? ""
                if dateA != dateB { return dateA < dateB }
                return (a.id ?? "") < (b.id ?? "")
            }
        case .amountDesc:
            return { a, b in
                let amtA = a.amountCents ?? 0
                let amtB = b.amountCents ?? 0
                if amtA != amtB { return amtA > amtB }
                return (a.id ?? "") > (b.id ?? "")
            }
        case .amountAsc:
            return { a, b in
                let amtA = a.amountCents ?? 0
                let amtB = b.amountCents ?? 0
                if amtA != amtB { return amtA < amtB }
                return (a.id ?? "") < (b.id ?? "")
            }
        }
    }

    static func filterLabel(for option: TransactionFilterOption) -> String {
        switch option {
        case .all: return "All"
        case .needsReview: return "Needs Review"
        case .hasReceipt: return "Has Receipt"
        case .purchase: return "Purchase"
        case .sale: return "Sale"
        case .returnType: return "Return"
        }
    }

    static func sortLabel(for option: TransactionSortOption) -> String {
        switch option {
        case .dateDesc: return "Newest"
        case .dateAsc: return "Oldest"
        case .amountDesc: return "Highest Amount"
        case .amountAsc: return "Lowest Amount"
        }
    }
}

// MARK: - SharedTransactionsList

struct SharedTransactionsList: View {
    let transactions: [Transaction]
    var onTransactionPress: ((String) -> Void)?
    var getMenuItems: ((Transaction) -> [ActionMenuItem])?
    var getBulkMenuItems: (() -> [ActionMenuItem])?
    var emptyMessage: String = "No transactions yet"

    @State private var searchText = ""
    @State private var isSearchVisible = false
    @State private var activeFilter: TransactionFilterOption = .all
    @State private var activeSort: TransactionSortOption = .dateDesc
    @State private var selectedIds: Set<String> = []
    @State private var showFilterMenu = false
    @State private var showSortMenu = false
    @State private var showBulkActionMenu = false

    // MARK: - Computed

    private var processedTransactions: [Transaction] {
        TransactionFilterSortCalculations.applyAll(
            transactions,
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

    private var selectedTotalCents: Int? {
        let pairs = processedTransactions.compactMap { tx -> (id: String, cents: Int)? in
            guard let id = tx.id, let cents = tx.amountCents else { return nil }
            return (id: id, cents: cents)
        }
        let total = SelectionCalculations.totalCentsForSelected(selectedIds: selectedIds, items: pairs)
        return total > 0 ? total : nil
    }

    // Issue 6: Combine custom bulk actions with default clear-selection
    private var bulkActionMenuItems: [ActionMenuItem] {
        var items = getBulkMenuItems?() ?? []
        items.append(
            ActionMenuItem(id: "clear-selection", label: "Clear Selection", icon: "xmark.circle", onPress: {
                selectedIds.removeAll()
            })
        )
        return items
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
                    totalCents: selectedTotalCents,
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
                items: bulkActionMenuItems
            )
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
                Label(emptyMessage, systemImage: "creditcard")
            }
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: Spacing.cardListGap) {
                    ForEach(processedTransactions) { transaction in
                        transactionCard(for: transaction)
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.vertical, Spacing.sm)
            }
        }
    }

    @ViewBuilder
    private func transactionCard(for transaction: Transaction) -> some View {
        // Issue 5: Skip transactions with nil IDs
        if let txId = transaction.id {
            let isSelected = selectedIds.contains(txId)
            let menuItems = getMenuItems?(transaction) ?? []

            TransactionCard(
                id: txId,
                source: transaction.source ?? "",
                amountCents: transaction.amountCents,
                transactionDate: transaction.transactionDate,
                notes: transaction.notes,
                budgetCategoryName: transaction.budgetCategoryId,
                transactionType: transaction.transactionType,
                needsReview: transaction.needsReview ?? false,
                reimbursementType: transaction.reimbursementType,
                hasEmailReceipt: transaction.hasEmailReceipt ?? false,
                status: transaction.status,
                itemCount: transaction.itemIds?.count,
                isSelected: isSelected ? .constant(true) : selectedIds.isEmpty ? nil : .constant(false),
                menuItems: menuItems,
                onPress: {
                    if !selectedIds.isEmpty {
                        toggleSelection(txId)
                    } else {
                        onTransactionPress?(txId)
                    }
                }
            )
        }
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

    // Issue 2: Single-select filter — selecting a new filter replaces the old one
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

// MARK: - Previews

#Preview("With Transactions") {
    let mockTransactions = [
        Transaction(
            transactionDate: "2026-02-02",
            amountCents: 14194,
            source: "Amazon",
            notes: "1 king sham for MBR, ochre king quilt set",
            transactionType: "purchase",
            needsReview: true
        ),
        Transaction(
            transactionDate: "2026-01-28",
            amountCents: 44620,
            source: "Wayfair",
            notes: "Replacement king bed for MBR",
            transactionType: "purchase",
            hasEmailReceipt: true
        ),
        Transaction(
            transactionDate: "2026-01-15",
            amountCents: 8997,
            source: "Homegoods",
            transactionType: "purchase"
        ),
    ]

    SharedTransactionsList(
        transactions: mockTransactions,
        onTransactionPress: { id in print("Tapped \(id)") },
        getMenuItems: { _ in
            [
                ActionMenuItem(id: "edit", label: "Edit", icon: "pencil"),
                ActionMenuItem(id: "delete", label: "Delete", icon: "trash", isDestructive: true),
            ]
        }
    )
}

#Preview("Empty") {
    SharedTransactionsList(
        transactions: [],
        emptyMessage: "No transactions match your filters"
    )
}
