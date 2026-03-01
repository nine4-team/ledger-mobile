import SwiftUI

struct InventoryView: View {
    @Environment(InventoryContext.self) private var inventoryContext
    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager

    @State private var selectedTab: String

    private let tabs = [
        TabBarItem(id: "items", label: "Items"),
        TabBarItem(id: "transactions", label: "Transactions"),
        TabBarItem(id: "spaces", label: "Spaces"),
    ]

    init() {
        let saved = UserDefaults.standard.integer(forKey: "inventorySelectedTab")
        let tabIds = ["items", "transactions", "spaces"]
        let initial = saved >= 0 && saved < tabIds.count ? tabIds[saved] : "items"
        _selectedTab = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollableTabBar(selectedId: $selectedTab, items: tabs)

            Group {
                switch selectedTab {
                case "items":
                    InventoryItemsSubTab()
                        .navigationDestination(for: Item.self) { item in
                            ItemDetailView(item: item)
                        }
                case "transactions":
                    InventoryTransactionsSubTab()
                        .navigationDestination(for: Transaction.self) { transaction in
                            TransactionDetailView(transaction: transaction)
                        }
                case "spaces":
                    InventorySpacesSubTab()
                        .navigationDestination(for: Space.self) { space in
                            SpaceDetailView(space: space)
                        }
                default:
                    InventoryItemsSubTab()
                }
            }
        }
        .navigationTitle("Inventory")
        .navigationBarTitleDisplayMode(.large)
        .task {
            guard let accountId = accountContext.currentAccountId else { return }
            inventoryContext.activate(accountId: accountId)
        }
        .onDisappear {
            inventoryContext.deactivate()
        }
        .onChange(of: selectedTab) { _, newValue in
            let tabIds = ["items", "transactions", "spaces"]
            if let index = tabIds.firstIndex(of: newValue) {
                inventoryContext.lastSelectedTab = index
            }
        }
    }
}
