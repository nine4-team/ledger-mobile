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
    case createdDesc = "created-desc"
    case createdAsc = "created-asc"
    case sourceAsc = "source-asc"
    case sourceDesc = "source-desc"
}

// MARK: - Transaction Grouped Filter State

struct TransactionFilterState {
    var status: Set<String> = []
    var reimbursementStatus: Set<String> = []
    var emailReceipt: Set<String> = []
    var transactionType: Set<String> = []
    var completeness: Set<String> = []
    var budgetCategory: Set<String> = []
    var purchasedBy: Set<String> = []
    var source: Set<String> = []

    var isActive: Bool {
        !status.isEmpty || !reimbursementStatus.isEmpty || !emailReceipt.isEmpty
            || !transactionType.isEmpty || !completeness.isEmpty || !budgetCategory.isEmpty
            || !purchasedBy.isEmpty || !source.isEmpty
    }

    enum FilterGroup {
        case status, reimbursementStatus, emailReceipt, transactionType
        case completeness, budgetCategory, purchasedBy, source
    }

    func selections(for group: FilterGroup) -> Set<String> {
        switch group {
        case .status: return status
        case .reimbursementStatus: return reimbursementStatus
        case .emailReceipt: return emailReceipt
        case .transactionType: return transactionType
        case .completeness: return completeness
        case .budgetCategory: return budgetCategory
        case .purchasedBy: return purchasedBy
        case .source: return source
        }
    }

    mutating func toggle(group: FilterGroup, value: String, optionCount: Int = 0) {
        if value == "all" {
            clearGroup(group)
            return
        }
        var set = selections(for: group)
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
        if optionCount > 0 && set.count >= optionCount {
            set = []
        }
        setGroup(group, to: set)
    }

    private mutating func clearGroup(_ group: FilterGroup) {
        setGroup(group, to: [])
    }

    private mutating func setGroup(_ group: FilterGroup, to value: Set<String>) {
        switch group {
        case .status: status = value
        case .reimbursementStatus: reimbursementStatus = value
        case .emailReceipt: emailReceipt = value
        case .transactionType: transactionType = value
        case .completeness: completeness = value
        case .budgetCategory: budgetCategory = value
        case .purchasedBy: purchasedBy = value
        case .source: source = value
        }
    }
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

    static func applyAllGrouped(
        _ transactions: [Transaction],
        filters: TransactionFilterState,
        sort: TransactionSortOption,
        search: String
    ) -> [Transaction] {
        let filtered = applyGroupedFilters(transactions, filters: filters)
        let searched = applySearch(filtered, query: search)
        return applySort(searched, sort: sort)
    }

    static func applyGroupedFilters(_ transactions: [Transaction], filters: TransactionFilterState) -> [Transaction] {
        guard filters.isActive else { return transactions }
        return transactions.filter { tx in
            if !filters.status.isEmpty {
                let txStatus = transactionStatus(for: tx)
                guard filters.status.contains(txStatus) else { return false }
            }
            if !filters.reimbursementStatus.isEmpty {
                let reimb = tx.reimbursementType ?? ""
                guard filters.reimbursementStatus.contains(reimb) else { return false }
            }
            if !filters.emailReceipt.isEmpty {
                let hasReceipt = tx.hasEmailReceipt == true
                let val = hasReceipt ? "yes" : "no"
                guard filters.emailReceipt.contains(val) else { return false }
            }
            if !filters.transactionType.isEmpty {
                let txType = tx.transactionType ?? ""
                guard filters.transactionType.contains(txType) else { return false }
            }
            if !filters.completeness.isEmpty {
                let needsReview = tx.needsReview == true
                let val = needsReview ? "needs-review" : "complete"
                guard filters.completeness.contains(val) else { return false }
            }
            if !filters.budgetCategory.isEmpty {
                let catId = tx.budgetCategoryId ?? ""
                guard filters.budgetCategory.contains(catId) else { return false }
            }
            if !filters.purchasedBy.isEmpty {
                let purchaser = tx.purchasedBy ?? "missing"
                guard filters.purchasedBy.contains(purchaser) else { return false }
            }
            if !filters.source.isEmpty {
                let src = tx.source ?? ""
                guard filters.source.contains(src) else { return false }
            }
            return true
        }
    }

    private static func transactionStatus(for tx: Transaction) -> String {
        if tx.isCanceled == true { return "canceled" }
        if tx.status == "completed" { return "completed" }
        return "pending"
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
        case .createdDesc:
            return { a, b in
                let dateA = a.createdAt ?? .distantPast
                let dateB = b.createdAt ?? .distantPast
                if dateA != dateB { return dateA > dateB }
                return (a.id ?? "") > (b.id ?? "")
            }
        case .createdAsc:
            return { a, b in
                let dateA = a.createdAt ?? .distantPast
                let dateB = b.createdAt ?? .distantPast
                if dateA != dateB { return dateA < dateB }
                return (a.id ?? "") < (b.id ?? "")
            }
        case .sourceAsc:
            return { a, b in
                let srcA = (a.source ?? "").lowercased()
                let srcB = (b.source ?? "").lowercased()
                if srcA != srcB { return srcA < srcB }
                return (a.id ?? "") < (b.id ?? "")
            }
        case .sourceDesc:
            return { a, b in
                let srcA = (a.source ?? "").lowercased()
                let srcB = (b.source ?? "").lowercased()
                if srcA != srcB { return srcA > srcB }
                return (a.id ?? "") > (b.id ?? "")
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
        case .createdDesc: return "Created (Newest)"
        case .createdAsc: return "Created (Oldest)"
        case .sourceAsc: return "Source (A-Z)"
        case .sourceDesc: return "Source (Z-A)"
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
    @State private var activeFilter: TransactionFilterOption = .all
    @State private var activeSort: TransactionSortOption = .dateDesc
    @State private var selectedIds: Set<String> = []
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
        .sheet(isPresented: $showBulkActionMenu) {
            ActionMenuSheet(
                title: "\(selectedIds.count) selected",
                items: bulkActionMenuItems
            )
            .sheetStyle(.quickMenu)
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        NativeListControlBar(
            searchText: $searchText,
            searchPlaceholder: "Search transactions...",
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
        .padding(.horizontal, Spacing.screenPadding)
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
                transaction: transaction,
                budgetCategoryName: transaction.budgetCategoryId,
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
