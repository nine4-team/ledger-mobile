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
    @State private var selectedProtoItem: ProtoItem?
    @State private var selectedItemId: String?
    @State private var selectedItemProjectId: String?
    @State private var showItemDetail = false

    @State private var itemActions = ItemActionsController()

    // Transaction selection
    @State private var selectedTransactionIds: Set<String> = []
    @State private var showTransactionBulkActions = false
    @State private var showTransactionDeleteConfirmation = false
    @State private var navigationTransaction: Transaction?

    // Space navigation
    @State private var selectedSpaceId: String?
    @State private var selectedSpaceProjectId: String?
    @State private var showSpaceDetail = false

    // Single-transaction actions
    @State private var actionTargetTransactionId: String?
    @State private var showSingleTransactionDeleteConfirmation = false

    private var itemsCount: Int { searchResults.items.count + searchResults.protoItems.count }
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
        searchContent
            .navigationTitle("Search")
            .navBarTitleDisplayMode(.inline)
            .transactionSearchDestination(item: $navigationTransaction)
            .protoItemSearchDestination(item: $selectedProtoItem)
            .navigationDestination(isPresented: $showItemDetail) {
                if let selectedItemId,
                   let item = accountContext.allItems.first(where: { $0.id == selectedItemId }) {
                    ItemDetailView(
                        itemId: selectedItemId,
                        projectId: selectedItemProjectId,
                        initialItem: item
                    )
                } else {
                    ContentUnavailableView("Item Unavailable", systemImage: "cube.box")
                }
            }
            .navigationDestination(isPresented: $showSpaceDetail) {
                if let selectedSpaceId,
                   let space = accountContext.allSpaces.first(where: { $0.id == selectedSpaceId }) {
                    SpaceDetailView(space: space, projectId: selectedSpaceProjectId)
                } else {
                    ContentUnavailableView("Space Unavailable", systemImage: "square.grid.2x2")
                }
            }
            .universalSearchSelectionBar(
                selectedItemIds: $selectedItemIds,
                selectedTransactionIds: $selectedTransactionIds,
                itemTotalCount: searchResults.items.count,
                transactionTotalCount: searchResults.transactions.count,
                selectedItemTotalCents: selectedItemTotalCents,
                selectedTransactionTotalCents: selectedTransactionTotalCents,
                showItemBulkActions: $showItemBulkActions,
                showTransactionBulkActions: $showTransactionBulkActions
            )
            .universalSearchEvents(
                query: $query,
                debouncedQuery: $debouncedQuery,
                selectedTab: $selectedTab,
                searchFocused: $searchFocused,
                selectedItemIds: $selectedItemIds,
                selectedTransactionIds: $selectedTransactionIds,
                transactionsVersion: accountContext.allTransactions.count,
                itemsVersion: accountContext.allItems.count,
                protoItemsVersion: accountContext.allProtoItems.count,
                spacesVersion: accountContext.allSpaces.count,
                onScheduleSearch: scheduleDebouncedSearch,
                onPerformSearch: performSearch,
                onRefreshSearch: refreshActiveSearch
            )
            .universalSearchBackground(searchFocused: $searchFocused, presentationHost: presentationHost)
    }

    private var presentationHost: some View {
        ZStack {
            itemPresentationHost
            transactionPresentationHost
            itemActionSheetsHost
        }
    }

    private var itemPresentationHost: some View {
        EmptyView()
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
    }

    private var transactionPresentationHost: some View {
        EmptyView()
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
    }

    private var itemActionSheetsHost: some View {
        EmptyView()
        .itemActionSheets(
            itemActions,
            spaces: accountContext.allSpaces,
            transactions: accountContext.allTransactions,
            accountId: accountContext.currentAccountId
        )
    }

    private var searchContent: AnyView {
        AnyView(VStack(spacing: 0) {
            searchBar

            if debouncedQuery.isEmpty {
                initialState
            } else {
                resultsView
            }
        })
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
            .scrollDismissesKeyboard(.immediately)
        }
    }

    // MARK: - Tab Content

    private var itemsTab: some View {
        Group {
            if searchResults.items.isEmpty && searchResults.protoItems.isEmpty {
                emptyState(message: "No items found")
            } else {
                ForEach(searchResults.protoItems) { protoItem in
                    ItemDraftCard(
                        protoItem: protoItem,
                        onOpen: { selectedProtoItem = protoItem }
                    )
                }

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
                        projectName: projectName(for: item.projectId) ?? (item.projectId == nil ? "Inventory" : nil),
                        isSelected: isSelected,
                        menuItems: selectedItemIds.isEmpty ? singleItemMenuItems(for: itemId) : []
                    )

                    if selectedItemIds.isEmpty {
                        Button {
                            selectedItemId = itemId
                            selectedItemProjectId = item.projectId
                            showItemDetail = true
                        } label: {
                            card
                        }
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
                    let card = TransactionCard(
                        transaction: transaction,
                        budgetCategoryName: categoryName(for: transaction.budgetCategoryId),
                        projectName: TransactionDisplayCalculations.projectLabel(
                            for: transaction,
                            projects: accountContext.allProjects
                        ),
                        isSelected: isSelected,
                        menuItems: selectedTransactionIds.isEmpty ? singleTransactionMenuItems(for: transaction, txId: txId) : [],
                        onPress: selectedTransactionIds.isEmpty ? {
                            navigationTransaction = transaction
                        } : nil
                    )

                    if selectedTransactionIds.isEmpty {
                        card
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
                    if let spaceId = space.id {
                        Button {
                            selectedSpaceId = spaceId
                            selectedSpaceProjectId = space.projectId
                            showSpaceDetail = true
                        } label: {
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
            includeReturnToInventory: false,
            includeSellToProject: false
        )
    }

    private func singleTransactionMenuItems(for transaction: Transaction, txId: String) -> [ActionMenuItem] {
        TransactionMenuBuilder.buildCardMenu(
            transaction: transaction,
            callbacks: SingleTransactionMenuCallbacks(
                onCopyID: { Clipboard.copy(txId) },
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
                onCopyIDs: { Clipboard.copyLines(selectedItemIds) },
                onDelete: { showItemDeleteConfirmation = true }
            )
        )
    }

    private var transactionBulkActionMenuItems: [ActionMenuItem] {
        TransactionMenuBuilder.buildBulkMenu(
            callbacks: BulkTransactionMenuCallbacks(
                onCopyIDs: { Clipboard.copyLines(selectedTransactionIds) },
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

    private func scheduleDebouncedSearch(_ newValue: String) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            debouncedQuery = newValue
        }
    }

    private func refreshActiveSearch() {
        if !debouncedQuery.isEmpty {
            performSearch(query: debouncedQuery)
        }
    }

    private func performSearch(query: String) {
        searchResults = SearchCalculations.search(
            query: query,
            items: accountContext.allItems,
            protoItems: accountContext.allProtoItems,
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

private struct ProtoItemSearchDestinationModifier: ViewModifier {
    @Binding var item: ProtoItem?

    func body(content: Content) -> some View {
        content.navigationDestination(item: $item) { protoItem in
            ItemQuickDraftDetailView(protoItem: protoItem)
        }
    }
}

private struct TransactionSearchDestinationModifier: ViewModifier {
    @Binding var item: Transaction?

    func body(content: Content) -> some View {
        content.navigationDestination(item: $item) { transaction in
            TransactionDetailView(transaction: transaction)
        }
    }
}

private struct UniversalSearchSelectionBarModifier: ViewModifier {
    @Binding var selectedItemIds: Set<String>
    @Binding var selectedTransactionIds: Set<String>
    let itemTotalCount: Int
    let transactionTotalCount: Int
    let selectedItemTotalCents: Int?
    let selectedTransactionTotalCents: Int?
    @Binding var showItemBulkActions: Bool
    @Binding var showTransactionBulkActions: Bool

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            if !selectedItemIds.isEmpty {
                BulkSelectionBar(
                    selectedCount: selectedItemIds.count,
                    totalCount: itemTotalCount,
                    totalCents: selectedItemTotalCents,
                    onBulkActions: { showItemBulkActions = true },
                    onClear: { selectedItemIds.removeAll() }
                )
            } else if !selectedTransactionIds.isEmpty {
                BulkSelectionBar(
                    selectedCount: selectedTransactionIds.count,
                    totalCount: transactionTotalCount,
                    totalCents: selectedTransactionTotalCents,
                    onBulkActions: { showTransactionBulkActions = true },
                    onClear: { selectedTransactionIds.removeAll() }
                )
            }
        }
    }
}

private struct UniversalSearchEventsModifier: ViewModifier {
    @Binding var query: String
    @Binding var debouncedQuery: String
    @Binding var selectedTab: String
    @Binding var searchFocused: Bool
    @Binding var selectedItemIds: Set<String>
    @Binding var selectedTransactionIds: Set<String>
    let transactionsVersion: Int
    let itemsVersion: Int
    let protoItemsVersion: Int
    let spacesVersion: Int
    let onScheduleSearch: (String) -> Void
    let onPerformSearch: (String) -> Void
    let onRefreshSearch: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    searchFocused = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
                searchFocused = true
            }
            .onChange(of: query) { _, newValue in
                onScheduleSearch(newValue)
            }
            .onChange(of: debouncedQuery) { _, newValue in
                onPerformSearch(newValue)
            }
            .onChange(of: transactionsVersion) { _, _ in
                onRefreshSearch()
            }
            .onChange(of: itemsVersion) { _, _ in
                onRefreshSearch()
            }
            .onChange(of: protoItemsVersion) { _, _ in
                onRefreshSearch()
            }
            .onChange(of: spacesVersion) { _, _ in
                onRefreshSearch()
            }
            .onChange(of: selectedTab) { _, _ in
                selectedItemIds.removeAll()
                selectedTransactionIds.removeAll()
            }
    }
}

private struct UniversalSearchBackgroundModifier<PresentationHost: View>: ViewModifier {
    @Binding var searchFocused: Bool
    let presentationHost: PresentationHost

    func body(content: Content) -> some View {
        content
            .background(
                BrandColors.background
                    .contentShape(Rectangle())
                    .onTapGesture { searchFocused = false }
            )
            .background(presentationHost)
    }
}

private extension View {
    func transactionSearchDestination(item: Binding<Transaction?>) -> some View {
        modifier(TransactionSearchDestinationModifier(item: item))
    }

    func protoItemSearchDestination(item: Binding<ProtoItem?>) -> some View {
        modifier(ProtoItemSearchDestinationModifier(item: item))
    }

    func universalSearchSelectionBar(
        selectedItemIds: Binding<Set<String>>,
        selectedTransactionIds: Binding<Set<String>>,
        itemTotalCount: Int,
        transactionTotalCount: Int,
        selectedItemTotalCents: Int?,
        selectedTransactionTotalCents: Int?,
        showItemBulkActions: Binding<Bool>,
        showTransactionBulkActions: Binding<Bool>
    ) -> some View {
        modifier(UniversalSearchSelectionBarModifier(
            selectedItemIds: selectedItemIds,
            selectedTransactionIds: selectedTransactionIds,
            itemTotalCount: itemTotalCount,
            transactionTotalCount: transactionTotalCount,
            selectedItemTotalCents: selectedItemTotalCents,
            selectedTransactionTotalCents: selectedTransactionTotalCents,
            showItemBulkActions: showItemBulkActions,
            showTransactionBulkActions: showTransactionBulkActions
        ))
    }

    func universalSearchEvents(
        query: Binding<String>,
        debouncedQuery: Binding<String>,
        selectedTab: Binding<String>,
        searchFocused: Binding<Bool>,
        selectedItemIds: Binding<Set<String>>,
        selectedTransactionIds: Binding<Set<String>>,
        transactionsVersion: Int,
        itemsVersion: Int,
        protoItemsVersion: Int,
        spacesVersion: Int,
        onScheduleSearch: @escaping (String) -> Void,
        onPerformSearch: @escaping (String) -> Void,
        onRefreshSearch: @escaping () -> Void
    ) -> some View {
        modifier(UniversalSearchEventsModifier(
            query: query,
            debouncedQuery: debouncedQuery,
            selectedTab: selectedTab,
            searchFocused: searchFocused,
            selectedItemIds: selectedItemIds,
            selectedTransactionIds: selectedTransactionIds,
            transactionsVersion: transactionsVersion,
            itemsVersion: itemsVersion,
            protoItemsVersion: protoItemsVersion,
            spacesVersion: spacesVersion,
            onScheduleSearch: onScheduleSearch,
            onPerformSearch: onPerformSearch,
            onRefreshSearch: onRefreshSearch
        ))
    }

    func universalSearchBackground<PresentationHost: View>(
        searchFocused: Binding<Bool>,
        presentationHost: PresentationHost
    ) -> some View {
        modifier(UniversalSearchBackgroundModifier(
            searchFocused: searchFocused,
            presentationHost: presentationHost
        ))
    }
}
