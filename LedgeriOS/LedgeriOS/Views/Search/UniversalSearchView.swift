import SwiftUI

struct UniversalSearchView: View {
    @Environment(AccountContext.self) private var accountContext

    @State private var searchFocused = false
    @State private var query = ""
    @State private var debouncedQuery = ""
    @State private var selectedTab = "items"
    @State private var debounceTask: Task<Void, Never>?
    @State private var searchResults = SearchCalculations.SearchResults(items: [], transactions: [], spaces: [])

    private var tabs: [TabBarItem] {
        [
            TabBarItem(id: "items", label: "Items (\(searchResults.items.count))"),
            TabBarItem(id: "transactions", label: "Transactions (\(searchResults.transactions.count))"),
            TabBarItem(id: "spaces", label: "Spaces (\(searchResults.spaces.count))"),
        ]
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
                    NavigationLink(value: item) {
                        ItemCard(
                            item: item,
                            priceLabel: item.purchasePriceCents.map {
                                CurrencyFormatting.formatCentsWithDecimals($0)
                            },
                            budgetCategoryName: categoryName(for: item.budgetCategoryId)
                        )
                    }
                    .buttonStyle(.plain)
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
                    NavigationLink(value: transaction) {
                        TransactionCard(
                            transaction: {
                                var tx = transaction
                                tx.source = SearchCalculations.transactionDisplayName(for: transaction)
                                return tx
                            }(),
                            budgetCategoryName: categoryName(for: transaction.budgetCategoryId)
                        )
                    }
                    .buttonStyle(.plain)
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
                            showNotes: true,
                            onPress: {}
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
