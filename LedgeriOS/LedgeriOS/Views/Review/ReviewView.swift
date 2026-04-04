import SwiftUI

struct ReviewView: View {
    @Environment(AccountContext.self) private var accountContext
    @State private var selectedToggle = "pending"
    @State private var searchText = ""
    @State private var activeSort: TransactionSortOption = .dateDesc
    @Environment(FindStateManager.self) private var findState

    private var pendingTransactions: [Transaction] {
        ReviewCalculations.pendingTransactions(accountContext.allTransactions)
    }

    private var doneTransactions: [Transaction] {
        ReviewCalculations.doneTransactions(accountContext.allTransactions)
    }

    private var displayTransactions: [Transaction] {
        let source = selectedToggle == "pending" ? pendingTransactions : doneTransactions
        return TransactionFilterSortCalculations.applyAll(
            source,
            filter: .all,
            sort: activeSort,
            search: searchText
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Review", selection: $selectedToggle) {
                Text("Pending (\(pendingTransactions.count))").tag("pending")
                Text("Done").tag("done")
            }
            .pickerStyle(.segmented)
            #if os(macOS)
            .labelsHidden()
            #endif
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.sm)

            controlBar

            content
        }
        .navigationTitle("Review")
        .navBarTitleDisplayMode(.inline)
        .navigationDestination(for: Transaction.self) { transaction in
            TransactionDetailView(transaction: transaction)
        }
        .universalAddButton()
        .background(BrandColors.background)
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        NativeListControlBar(
            searchText: $searchText,
            searchPlaceholder: "Search transactions...",
            style: .card
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
                Label(
                    selectedToggle == "pending" ? "All caught up" : "No recent activity",
                    systemImage: selectedToggle == "pending" ? "checkmark.circle" : "clock"
                )
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
                            NavigationLink(value: transaction) {
                                TransactionCard(
                                    transaction: transaction,
                                    budgetCategoryName: transaction.budgetCategoryId
                                )
                            }
                            .buttonStyle(.plain)
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
