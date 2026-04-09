import SwiftUI
import FirebaseFirestore

struct UniversalSearchView: View {
    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager

    @State private var searchFocused = false
    @State private var query = ""
    @State private var debouncedQuery = ""
    @State private var selectedTab = "items"
    @State private var debounceTask: Task<Void, Never>?
    @State private var searchResults = SearchCalculations.SearchResults(items: [], transactions: [], spaces: [])

    // Item selection
    @State private var selectedItemIds: Set<String> = []
    @State private var showItemBulkActions = false
    @State private var showItemSetSpace = false
    @State private var showItemStatusPicker = false
    @State private var showItemLinkTransaction = false
    @State private var showItemMoveToProject = false
    @State private var showItemDeleteConfirmation = false

    @State private var itemActions = ItemActionsController()

    // Transaction selection
    @State private var selectedTransactionIds: Set<String> = []
    @State private var showTransactionBulkActions = false
    @State private var showTransactionDeleteConfirmation = false

    // Single-transaction actions
    @State private var actionTargetTransactionId: String?
    @State private var showSingleTransactionDeleteConfirmation = false

    private var itemsCount: Int { searchResults.items.count }
    private var transactionsCount: Int { searchResults.transactions.count }
    private var spacesCount: Int { searchResults.spaces.count }

    private var selectedItems: [Item] {
        searchResults.items.filter { selectedItemIds.contains($0.id ?? "") }
    }

    private var selectedTransactions: [Transaction] {
        searchResults.transactions.filter { selectedTransactionIds.contains($0.id ?? "") }
    }

    private var selectedTransactionTotalCents: Int? {
        let total = SelectionCalculations.totalCentsForSelectedTransactions(
            selectedIds: selectedTransactionIds,
            transactions: searchResults.transactions
        )
        return total != 0 ? total : nil
    }

    private var selectedItemTotalCents: Int? {
        let pairs = searchResults.items.compactMap { item -> (id: String, cents: Int)? in
            guard let id = item.id, let cents = ItemDetailCalculations.displayPrice(for: item) else { return nil }
            return (id: id, cents: cents)
        }
        let total = SelectionCalculations.totalCentsForSelected(selectedIds: selectedItemIds, items: pairs)
        return total > 0 ? total : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            if debouncedQuery.isEmpty {
                initialState
            } else {
                resultsView
            }
        }
        .navigationTitle("Search")
        .navBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !selectedItemIds.isEmpty {
                BulkSelectionBar(
                    selectedCount: selectedItemIds.count,
                    totalCount: searchResults.items.count,
                    totalCents: selectedItemTotalCents,
                    onBulkActions: { showItemBulkActions = true },
                    onClear: { selectedItemIds.removeAll() }
                )
            } else if !selectedTransactionIds.isEmpty {
                BulkSelectionBar(
                    selectedCount: selectedTransactionIds.count,
                    totalCount: searchResults.transactions.count,
                    totalCents: selectedTransactionTotalCents,
                    onBulkActions: { showTransactionBulkActions = true },
                    onClear: { selectedTransactionIds.removeAll() }
                )
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                searchFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            searchFocused = true
        }
        .onChange(of: query) { _, newValue in
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                debouncedQuery = newValue
            }
        }
        .onChange(of: debouncedQuery) { _, newValue in
            performSearch(query: newValue)
        }
        .onChange(of: accountContext.allTransactions.count) { _, _ in
            if !debouncedQuery.isEmpty { performSearch(query: debouncedQuery) }
        }
        .onChange(of: accountContext.allItems.count) { _, _ in
            if !debouncedQuery.isEmpty { performSearch(query: debouncedQuery) }
        }
        .onChange(of: accountContext.allSpaces.count) { _, _ in
            if !debouncedQuery.isEmpty { performSearch(query: debouncedQuery) }
        }
        .onChange(of: selectedTab) { _, _ in
            selectedItemIds.removeAll()
            selectedTransactionIds.removeAll()
        }
        .universalAddButton()
        .background(BrandColors.background)
        // Item bulk action sheets
        .adaptivePresentation(isPresented: $showItemBulkActions, style: .quickMenu) {
            ActionMenuSheet(
                title: "\(selectedItemIds.count) Items",
                items: itemBulkActionMenuItems,
                onSelectAction: { action in action() }
            )
        }
        .adaptivePresentation(isPresented: $showItemSetSpace, style: .picker) {
            SetSpaceModal(
                spaces: accountContext.allSpaces,
                currentSpaceId: nil,
                onSelect: { space in setSpaceForSelectedItems(spaceId: space?.id) }
            )
        }
        .adaptivePresentation(isPresented: $showItemStatusPicker, style: .quickMenu) {
            StatusPickerModal { status in setStatusForSelectedItems(status) }
        }
        .adaptivePresentation(isPresented: $showItemLinkTransaction, style: .picker) {
            TransactionPickerModal(
                transactions: accountContext.allTransactions,
                selectedId: nil,
                onSelect: { transaction in linkSelectedItemsToTransaction(transaction) }
            )
        }
        .adaptivePresentation(isPresented: $showItemMoveToProject, style: .form) {
            ReassignToProjectModal(items: selectedItems) { selectedItemIds.removeAll() }
        }
        .confirmationDialog("Delete \(selectedItemIds.count) items?", isPresented: $showItemDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteSelectedItems() }
        } message: {
            Text("This action cannot be undone.")
        }
        // Transaction bulk action sheets
        .adaptivePresentation(isPresented: $showTransactionBulkActions, style: .quickMenu) {
            ActionMenuSheet(
                title: "\(selectedTransactionIds.count) Transactions",
                items: transactionBulkActionMenuItems,
                onSelectAction: { action in action() }
            )
        }
        .confirmationDialog("Delete \(selectedTransactionIds.count) transactions?", isPresented: $showTransactionDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteSelectedTransactions() }
        } message: {
            Text("This action cannot be undone.")
        }
        .confirmationDialog("Delete transaction?", isPresented: $showSingleTransactionDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteSingleTransaction() }
        } message: {
            Text("This action cannot be undone.")
        }
        .itemActionSheets(
            itemActions,
            spaces: accountContext.allSpaces,
            transactions: accountContext.allTransactions,
            accountId: accountContext.currentAccountId
        )
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        SearchControlBar(
            searchText: $query,
            searchPlaceholder: "Search items, transactions, spaces...",
            isFocused: $searchFocused
        )
        .onChange(of: query) { _, newValue in
            if newValue.isEmpty {
                debouncedQuery = ""
                searchResults = SearchCalculations.SearchResults(items: [], transactions: [], spaces: [])
            }
        }
    }

    // MARK: - Initial State

    private var initialState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(BrandColors.textSecondary)
            Text("Start typing to search")
                .font(Typography.body)
                .foregroundStyle(BrandColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results View

    private var resultsView: some View {
        VStack(spacing: 0) {
            SegmentedControl(selection: $selectedTab, options: [
                SegmentOption(id: "items", label: "Items (\(itemsCount))"),
                SegmentOption(id: "transactions", label: "Transactions (\(transactionsCount))"),
                SegmentOption(id: "spaces", label: "Spaces (\(spacesCount))"),
            ])
            .frame(maxWidth: Dimensions.contentMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.sm)

            ScrollView {
                LazyVGrid(
                    columns: Dimensions.listColumns,
                    alignment: .leading,
                    spacing: Spacing.cardListGap
                ) {
                    switch selectedTab {
                    case "items":
                        itemsTab
                    case "transactions":
                        transactionsTab
                    case "spaces":
                        spacesTab
                    default:
                        itemsTab
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.vertical, Spacing.md)
            }
            .scrollContentTopFade()
        }
    }

    // MARK: - Tab Content

    private var itemsTab: some View {
        Group {
            if searchResults.items.isEmpty {
                emptyState(message: "No items found")
            } else {
                ForEach(searchResults.items) { item in
                    let itemId = item.id ?? ""
                    let isSelected = Binding(
                        get: { selectedItemIds.contains(itemId) },
                        set: { selected in
                            if selected { selectedItemIds.insert(itemId) }
                            else { selectedItemIds.remove(itemId) }
                        }
                    )
                    let card = ItemCard(
                        item: item,
                        priceLabel: ItemDetailCalculations.displayPrice(for: item).map {
                            CurrencyFormatting.formatCentsWithDecimals($0)
                        },
                        budgetCategoryName: categoryName(for: item.budgetCategoryId),
                        projectName: projectName(for: item.projectId),
                        isSelected: isSelected,
                        menuItems: selectedItemIds.isEmpty ? singleItemMenuItems(for: itemId) : []
                    )

                    if selectedItemIds.isEmpty {
                        NavigationLink(value: item) { card }
                            .buttonStyle(.plain)
                    } else {
                        card
                            .onTapGesture { isSelected.wrappedValue.toggle() }
                    }
                }
            }
        }
    }

    private var transactionsTab: some View {
        Group {
            if searchResults.transactions.isEmpty {
                emptyState(message: "No transactions found")
            } else {
                ForEach(searchResults.transactions) { transaction in
                    let txId = transaction.id ?? ""
                    let isSelected = Binding(
                        get: { selectedTransactionIds.contains(txId) },
                        set: { selected in
                            if selected { selectedTransactionIds.insert(txId) }
                            else { selectedTransactionIds.remove(txId) }
                        }
                    )
                    let displayTransaction: Transaction = {
                        var tx = transaction
                        tx.source = SearchCalculations.transactionDisplayName(for: transaction)
                        return tx
                    }()
                    let card = TransactionCard(
                        transaction: displayTransaction,
                        budgetCategoryName: categoryName(for: transaction.budgetCategoryId),
                        isSelected: isSelected,
                        menuItems: selectedTransactionIds.isEmpty ? singleTransactionMenuItems(for: transaction, txId: txId) : []
                    )

                    if selectedTransactionIds.isEmpty {
                        NavigationLink(value: transaction) { card }
                            .buttonStyle(.plain)
                    } else {
                        card
                            .onTapGesture { isSelected.wrappedValue.toggle() }
                    }
                }
            }
        }
    }

    private var spacesTab: some View {
        Group {
            if searchResults.spaces.isEmpty {
                emptyState(message: "No spaces found")
            } else {
                ForEach(searchResults.spaces) { space in
                    NavigationLink(value: space) {
                        SpaceCard(
                            space: space,
                            itemCount: itemCount(for: space)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Empty State

    private func emptyState(message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(BrandColors.textTertiary)
            Text(message)
                .font(Typography.body)
                .foregroundStyle(BrandColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.xxxl)
    }

    // MARK: - Single Item Menu Items

    private func singleItemMenuItems(for itemId: String) -> [ActionMenuItem] {
        guard let item = searchResults.items.first(where: { $0.id == itemId }) else { return [] }
        // Search scope — sell modals need ProjectContext which isn't available here,
        // so we omit sell callbacks. Reassign to Project works via AccountContext.
        return itemActions.buildMenu(
            for: item,
            scope: .search,
            accountId: accountContext.currentAccountId,
            onSelect: { selectedItemIds.insert(itemId) },
            includeSellToBusiness: false,
            includeSellToProject: false
        )
    }

    private func singleTransactionMenuItems(for transaction: Transaction, txId: String) -> [ActionMenuItem] {
        TransactionMenuBuilder.buildCardMenu(
            transaction: transaction,
            callbacks: SingleTransactionMenuCallbacks(
                onDelete: {
                    actionTargetTransactionId = txId
                    showSingleTransactionDeleteConfirmation = true
                }
            )
        )
    }

    // MARK: - Bulk Action Menus

    private var itemBulkActionMenuItems: [ActionMenuItem] {
        ItemMenuBuilder.buildBulkMenu(
            scope: .search,
            callbacks: BulkItemMenuCallbacks(
                onStatusChange: { _ in showItemStatusPicker = true },
                onSetTransaction: { showItemLinkTransaction = true },
                onClearTransaction: { clearTransactionForSelectedItems() },
                onSetSpace: { showItemSetSpace = true },
                onClearSpace: { clearSpaceForSelectedItems() },
                onReassignToProject: { showItemMoveToProject = true },
                onDelete: { showItemDeleteConfirmation = true }
            )
        )
    }

    private var transactionBulkActionMenuItems: [ActionMenuItem] {
        TransactionMenuBuilder.buildBulkMenu(
            callbacks: BulkTransactionMenuCallbacks(
                onDelete: { showTransactionDeleteConfirmation = true }
            )
        )
    }

    // MARK: - Item Bulk Actions

    private func setSpaceForSelectedItems(spaceId: String?) {
        guard let accountId = accountContext.currentAccountId else { return }
        let service = ItemsService()
        nonisolated(unsafe) let fields: [String: Any] = spaceId != nil ? ["spaceId": spaceId!] : ["spaceId": NSNull()]
        for item in selectedItems {
            guard let itemId = item.id else { continue }
            Task { try? await service.updateItem(accountId: accountId, itemId: itemId, fields: fields) }
        }
        selectedItemIds.removeAll()
    }

    private func setStatusForSelectedItems(_ status: ItemStatus) {
        guard let accountId = accountContext.currentAccountId else { return }
        let service = ItemsService()
        for item in selectedItems {
            guard let itemId = item.id else { continue }
            Task { try? await service.updateItem(accountId: accountId, itemId: itemId, fields: ["status": status.rawValue]) }
        }
        selectedItemIds.removeAll()
    }

    private func linkSelectedItemsToTransaction(_ transaction: Transaction) {
        guard let accountId = accountContext.currentAccountId,
              let transactionId = transaction.id else { return }
        let itemIds = selectedItems.compactMap(\.id)
        let service = TransactionsService()
        Task {
            try? await service.updateTransaction(
                accountId: accountId,
                transactionId: transactionId,
                fields: ["itemIds": FieldValue.arrayUnion(itemIds), "updatedAt": FieldValue.serverTimestamp()]
            )
        }
        selectedItemIds.removeAll()
    }

    private func deleteSelectedItems() {
        guard let accountId = accountContext.currentAccountId else { return }
        let service = ItemsService()
        let items = Array(selectedItems)
        Task { try? await service.deleteItems(accountId: accountId, items: items) }
        selectedItemIds.removeAll()
    }

    private func clearSpaceForSelectedItems() {
        guard let accountId = accountContext.currentAccountId else { return }
        let service = ItemsService()
        for item in selectedItems {
            guard let itemId = item.id else { continue }
            Task { try? await service.updateItem(accountId: accountId, itemId: itemId, fields: ["spaceId": NSNull()]) }
        }
        selectedItemIds.removeAll()
    }

    private func clearTransactionForSelectedItems() {
        guard let accountId = accountContext.currentAccountId else { return }
        let service = ItemsService()
        for item in selectedItems {
            guard let itemId = item.id else { continue }
            Task { try? await service.updateItem(accountId: accountId, itemId: itemId, fields: ["transactionId": NSNull()]) }
        }
        selectedItemIds.removeAll()
    }

    // MARK: - Transaction Actions

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
        selectedTransactionIds.removeAll()
    }

    // MARK: - Helpers

    private func performSearch(query: String) {
        searchResults = SearchCalculations.search(
            query: query,
            items: accountContext.allItems,
            transactions: accountContext.allTransactions,
            spaces: accountContext.allSpaces,
            categories: accountContext.allBudgetCategories
        )
        autoSwitchTab()
    }

    /// If the current tab has no results but exactly one other tab does, switch to it.
    private func autoSwitchTab() {
        let currentCount: Int = switch selectedTab {
        case "items": itemsCount
        case "transactions": transactionsCount
        case "spaces": spacesCount
        default: 0
        }
        guard currentCount == 0 else { return }

        let tabsWithResults = [
            ("items", itemsCount),
            ("transactions", transactionsCount),
            ("spaces", spacesCount),
        ].filter { $0.1 > 0 }

        if tabsWithResults.count == 1 {
            selectedTab = tabsWithResults[0].0
        }
    }

    private func categoryName(for categoryId: String?) -> String? {
        guard let categoryId else { return nil }
        if categoryId == "uncategorized" { return "Uncategorized" }
        return accountContext.allBudgetCategories.first(where: { $0.id == categoryId })?.name
    }

    private func projectName(for projectId: String?) -> String? {
        guard let projectId else { return nil }
        return accountContext.allProjects.first(where: { $0.id == projectId })?.name
    }

    private func itemCount(for space: Space) -> Int {
        guard let spaceId = space.id else { return 0 }
        return accountContext.allItems.filter { $0.spaceId == spaceId }.count
    }
}

#Preview {
    NavigationStack {
        UniversalSearchView()
    }
    .environment(AccountContext(
        accountsService: AccountsService(),
        membersService: AccountMembersService()
    ))
}
