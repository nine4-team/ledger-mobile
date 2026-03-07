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

    // Transaction selection
    @State private var selectedTransactionIds: Set<String> = []
    @State private var showTransactionBulkActions = false
    @State private var showTransactionDeleteConfirmation = false

    private var tabs: [TabBarItem] {
        [
            TabBarItem(id: "items", label: "Items (\(searchResults.items.count))"),
            TabBarItem(id: "transactions", label: "Transactions (\(searchResults.transactions.count))"),
            TabBarItem(id: "spaces", label: "Spaces (\(searchResults.spaces.count))"),
        ]
    }

    private var selectedItems: [Item] {
        searchResults.items.filter { selectedItemIds.contains($0.id ?? "") }
    }

    private var selectedTransactions: [Transaction] {
        searchResults.transactions.filter { selectedTransactionIds.contains($0.id ?? "") }
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
                    totalCents: selectedItemTotalCents,
                    onBulkActions: { showItemBulkActions = true },
                    onClear: { selectedItemIds.removeAll() }
                )
            } else if !selectedTransactionIds.isEmpty {
                BulkSelectionBar(
                    selectedCount: selectedTransactionIds.count,
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
        .onChange(of: selectedTab) { _, _ in
            selectedItemIds.removeAll()
            selectedTransactionIds.removeAll()
        }
        .background(BrandColors.background)
        // Item bulk action sheets
        .sheet(isPresented: $showItemBulkActions) {
            ActionMenuSheet(
                title: "\(selectedItemIds.count) Items",
                items: itemBulkActionMenuItems,
                onSelectAction: { action in action() }
            )
            .sheetStyle(.quickMenu)
        }
        .sheet(isPresented: $showItemSetSpace) {
            SetSpaceModal(
                spaces: accountContext.allSpaces,
                currentSpaceId: nil,
                onSelect: { space in setSpaceForSelectedItems(spaceId: space?.id) }
            )
            .sheetStyle(.picker)
        }
        .sheet(isPresented: $showItemStatusPicker) {
            StatusPickerModal { status in setStatusForSelectedItems(status) }
                .sheetStyle(.quickMenu)
        }
        .sheet(isPresented: $showItemLinkTransaction) {
            TransactionPickerModal(
                transactions: accountContext.allTransactions,
                selectedId: nil,
                onSelect: { transaction in linkSelectedItemsToTransaction(transaction) }
            )
            .sheetStyle(.picker)
        }
        .sheet(isPresented: $showItemMoveToProject) {
            ReassignToProjectModal(items: selectedItems) { selectedItemIds.removeAll() }
                .sheetStyle(.form)
        }
        .confirmationDialog("Delete \(selectedItemIds.count) items?", isPresented: $showItemDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteSelectedItems() }
        } message: {
            Text("This action cannot be undone.")
        }
        // Transaction bulk action sheets
        .sheet(isPresented: $showTransactionBulkActions) {
            ActionMenuSheet(
                title: "\(selectedTransactionIds.count) Transactions",
                items: transactionBulkActionMenuItems,
                onSelectAction: { action in action() }
            )
            .sheetStyle(.quickMenu)
        }
        .confirmationDialog("Delete \(selectedTransactionIds.count) transactions?", isPresented: $showTransactionDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteSelectedTransactions() }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        SearchField(
            text: $query,
            placeholder: "Search items, transactions, spaces...",
            isFocused: $searchFocused
        )
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.sm)
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
            ScrollableTabBar(selectedId: $selectedTab, items: tabs)

            ScrollView {
                AdaptiveContentWidth {
                    LazyVStack(spacing: Spacing.cardListGap) {
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
                        menuItems: selectedTransactionIds.isEmpty ? singleTransactionMenuItems(for: txId) : []
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
                            itemCount: itemCount(for: space),
                            showNotes: true
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
        [ActionMenuItem(id: "select", label: "Select", icon: "checkmark.circle", onPress: {
            selectedItemIds.insert(itemId)
        })]
    }

    private func singleTransactionMenuItems(for txId: String) -> [ActionMenuItem] {
        [ActionMenuItem(id: "select", label: "Select", icon: "checkmark.circle", onPress: {
            selectedTransactionIds.insert(txId)
        })]
    }

    // MARK: - Bulk Action Menus

    private var itemBulkActionMenuItems: [ActionMenuItem] {
        [
            ActionMenuItem(id: "link-transaction", label: "Link to Transaction", icon: "link",
                           onPress: { showItemLinkTransaction = true }),
            ActionMenuItem(id: "set-space", label: "Set Space", icon: "mappin.and.ellipse",
                           onPress: { showItemSetSpace = true }),
            ActionMenuItem(id: "status", label: "Change Status", icon: "flag",
                           onPress: { showItemStatusPicker = true }),
            ActionMenuItem(id: "move-project", label: "Move to Project", icon: "arrow.triangle.2.circlepath",
                           onPress: { showItemMoveToProject = true }),
            ActionMenuItem(id: "delete", label: "Delete", icon: "trash", isDestructive: true,
                           onPress: { showItemDeleteConfirmation = true }),
        ]
    }

    private var transactionBulkActionMenuItems: [ActionMenuItem] {
        [
            ActionMenuItem(id: "mark-reviewed", label: "Mark as Reviewed", icon: "checkmark.circle",
                           onPress: { markSelectedTransactionsReviewed() }),
            ActionMenuItem(id: "delete", label: "Delete", icon: "trash", isDestructive: true,
                           onPress: { showTransactionDeleteConfirmation = true }),
        ]
    }

    // MARK: - Item Bulk Actions

    private func setSpaceForSelectedItems(spaceId: String?) {
        guard let accountId = accountContext.currentAccountId else { return }
        let service = ItemsService(syncTracker: NoOpSyncTracker())
        let fields: [String: Any] = spaceId != nil ? ["spaceId": spaceId!] : ["spaceId": NSNull()]
        for item in selectedItems {
            guard let itemId = item.id else { continue }
            Task { try? await service.updateItem(accountId: accountId, itemId: itemId, fields: fields) }
        }
        selectedItemIds.removeAll()
    }

    private func setStatusForSelectedItems(_ status: String) {
        guard let accountId = accountContext.currentAccountId else { return }
        let service = ItemsService(syncTracker: NoOpSyncTracker())
        for item in selectedItems {
            guard let itemId = item.id else { continue }
            Task { try? await service.updateItem(accountId: accountId, itemId: itemId, fields: ["status": status]) }
        }
        selectedItemIds.removeAll()
    }

    private func linkSelectedItemsToTransaction(_ transaction: Transaction) {
        guard let accountId = accountContext.currentAccountId,
              let transactionId = transaction.id else { return }
        let itemIds = selectedItems.compactMap(\.id)
        let service = TransactionsService(syncTracker: NoOpSyncTracker())
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
        let service = ItemsService(syncTracker: NoOpSyncTracker())
        for item in selectedItems {
            guard let itemId = item.id else { continue }
            Task { try? await service.deleteItem(accountId: accountId, itemId: itemId) }
        }
        selectedItemIds.removeAll()
    }

    // MARK: - Transaction Bulk Actions

    private func markSelectedTransactionsReviewed() {
        guard let accountId = accountContext.currentAccountId else { return }
        let service = TransactionsService(syncTracker: NoOpSyncTracker())
        for tx in selectedTransactions {
            guard let txId = tx.id else { continue }
            Task { try? await service.updateTransaction(accountId: accountId, transactionId: txId, fields: ["needsReview": false]) }
        }
        selectedTransactionIds.removeAll()
    }

    private func deleteSelectedTransactions() {
        guard let accountId = accountContext.currentAccountId else { return }
        let service = TransactionsService(syncTracker: NoOpSyncTracker())
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
    }

    private func categoryName(for categoryId: String?) -> String? {
        guard let categoryId else { return nil }
        return accountContext.allBudgetCategories.first(where: { $0.id == categoryId })?.name
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
        accountsService: AccountsService(syncTracker: NoOpSyncTracker()),
        membersService: AccountMembersService(syncTracker: NoOpSyncTracker())
    ))
}
