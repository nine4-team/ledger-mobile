import SwiftUI

struct ReviewView: View {
    @Environment(AccountContext.self) private var accountContext
    @State private var selectedBucketId: String = "unassigned"
    @State private var searchText = ""
    @State private var activeSort: TransactionSortOption = .dateDesc
    @State private var selectedTransaction: Transaction?
    @Environment(FindStateManager.self) private var findState

    private static let unassignedId = "unassigned"
    private static let inventoryId = "inventory"
    private static let projectIdPrefix = "project:"

    private var pendingTransactions: [Transaction] {
        ReviewCalculations.pendingTransactions(accountContext.allTransactions)
    }

    private var activeProjects: [Project] {
        accountContext.allProjects
            .filter { $0.isArchived != true }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var bucketCounts: [ReviewCalculations.PendingBucket: Int] {
        ReviewCalculations.counts(pendingTransactions)
    }

    private var currentBucket: ReviewCalculations.PendingBucket {
        if selectedBucketId == Self.inventoryId { return .inventory }
        if selectedBucketId.hasPrefix(Self.projectIdPrefix) {
            return .project(String(selectedBucketId.dropFirst(Self.projectIdPrefix.count)))
        }
        return .unassigned
    }

    private var tabItems: [TabBarItem] {
        var items: [TabBarItem] = []
        let unassignedCount = bucketCounts[.unassigned] ?? 0
        let inventoryCount = bucketCounts[.inventory] ?? 0
        items.append(TabBarItem(id: Self.unassignedId, label: "Unassigned (\(unassignedCount))"))
        items.append(TabBarItem(id: Self.inventoryId, label: "Inventory (\(inventoryCount))"))
        for project in activeProjects {
            guard let pid = project.id else { continue }
            let count = bucketCounts[.project(pid)] ?? 0
            items.append(TabBarItem(id: Self.projectIdPrefix + pid, label: "\(project.name) (\(count))"))
        }
        return items
    }

    private var displayTransactions: [Transaction] {
        let bucketed = ReviewCalculations.filter(pendingTransactions, bucket: currentBucket)
        return TransactionFilterSortCalculations.applyAll(
            bucketed,
            filter: .all,
            sort: activeSort,
            search: searchText
        )
    }

    private var emptyStateTitle: String {
        if pendingTransactions.isEmpty { return "All caught up" }
        switch currentBucket {
        case .unassigned: return "Nothing unassigned"
        case .inventory: return "Nothing in Inventory"
        case .project(let id):
            let name = accountContext.allProjects.first(where: { $0.id == id })?.name ?? "project"
            return "Nothing in \(name)"
        }
    }

    private var emptyStateIcon: String {
        pendingTransactions.isEmpty ? "checkmark.circle" : "tray"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollableTabBar(selectedId: $selectedBucketId, items: tabItems)
                .frame(maxWidth: Dimensions.contentMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)

            controlBar

            content
        }
        .navigationTitle("Review")
        .navBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedTransaction) { transaction in
            TransactionDetailView(transaction: transaction)
        }
        .background(BrandColors.background)
        .onChange(of: activeProjects.map { $0.id ?? "" }) { _, _ in
            let validIds = Set(tabItems.map(\.id))
            if !validIds.contains(selectedBucketId) {
                selectedBucketId = Self.unassignedId
            }
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        NativeListControlBar(
            searchText: $searchText,
            searchPlaceholder: "Search transactions...",
            style: .plain
        ) {
            EmptyView()
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
            EmptyView()
        }
        .padding(.horizontal, Spacing.screenPadding)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if displayTransactions.isEmpty {
            ContentUnavailableView {
                Label(emptyStateTitle, systemImage: emptyStateIcon)
            }
            .frame(maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(
                        columns: Dimensions.listColumns,
                        alignment: .leading,
                        spacing: Spacing.cardListGap
                    ) {
                        ForEach(displayTransactions) { transaction in
                            TransactionCard(
                                transaction: transaction,
                                budgetCategoryName: accountContext.allBudgetCategories
                                    .first(where: { $0.id == transaction.budgetCategoryId })?.name,
                                assignmentLabel: ReviewCalculations.assignmentLabel(
                                    for: transaction,
                                    projects: accountContext.allProjects
                                ),
                                projectName: TransactionDisplayCalculations.projectLabel(
                                    for: transaction,
                                    projects: accountContext.allProjects
                                ),
                                onPress: {
                                    selectedTransaction = transaction
                                }
                            )
                            .id(transaction.id ?? "")
                        }
                    }
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.vertical, Spacing.sm)
                }
                .onReceive(findState.scrollToPublisher) { matchID in
                    withAnimation { proxy.scrollTo(matchID, anchor: .center) }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ReviewView()
    }
    .environment(AccountContext(
        accountsService: AccountsService(),
        membersService: AccountMembersService()
    ))
    .environment(FindStateManager())
}
