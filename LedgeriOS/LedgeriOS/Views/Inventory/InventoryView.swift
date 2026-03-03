import SwiftUI

struct InventoryView: View {
    @Environment(InventoryContext.self) private var inventoryContext
    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager

    @State private var selectedTab: String
    @State private var showAddMenu = false
    @State private var showNewItem = false
    @State private var showNewTransaction = false
    @State private var showNewSpace = false

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
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    // Info button — future: show tooltip
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddMenu = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
        }
        .sheet(isPresented: $showAddMenu) {
            ActionMenuSheet(
                title: "Add New",
                items: [
                    ActionMenuItem(id: "item", label: "Item", icon: "shippingbox", onPress: { showNewItem = true }),
                    ActionMenuItem(id: "transaction", label: "Transaction", icon: "creditcard", onPress: { showNewTransaction = true }),
                    ActionMenuItem(id: "space", label: "Space", icon: "mappin.and.ellipse", onPress: { showNewSpace = true }),
                ]
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showNewItem) {
            Text("New Item — Coming Soon")
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showNewTransaction) {
            Text("New Transaction — Coming Soon")
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showNewSpace) {
            Text("New Space — Coming Soon")
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
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
