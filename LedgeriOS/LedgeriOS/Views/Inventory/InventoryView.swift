import SwiftUI

struct InventoryView: View {
    @Environment(InventoryContext.self) private var inventoryContext
    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager

    @State private var selectedTab: String
    init() {
        let saved = UserDefaults.standard.integer(forKey: "inventorySelectedTab")
        let tabIds = ["items", "transactions", "spaces"]
        let initial = saved >= 0 && saved < tabIds.count ? tabIds[saved] : "items"
        _selectedTab = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            SegmentedControl(selection: $selectedTab, options: [
                SegmentOption(id: "items", label: "Items"),
                SegmentOption(id: "transactions", label: "Transactions"),
                SegmentOption(id: "spaces", label: "Spaces"),
            ])
            .frame(maxWidth: Dimensions.contentMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.sm)

            Group {
                switch selectedTab {
                case "items":
                    InventoryItemsSubTab()
                case "transactions":
                    InventoryTransactionsSubTab()
                case "spaces":
                    InventorySpacesSubTab()
                default:
                    InventoryItemsSubTab()
                }
            }
        }
        .navigationDestination(for: Item.self) { item in
            ItemDetailView(item: item)
        }
        .navigationDestination(for: Transaction.self) { transaction in
            TransactionDetailView(transaction: transaction)
        }
        .navigationDestination(for: SpaceRoute.self) { route in
            if let space = route.initialSpace ?? NavigationRouteResolution.space(
                id: route.id,
                projectSpaces: inventoryContext.spaces,
                accountSpaces: accountContext.allSpaces
            ) {
                SpaceDetailView(space: space, projectId: route.projectId)
            } else {
                ContentUnavailableView("Space Unavailable", systemImage: "square.grid.2x2")
            }
        }
        .navigationTitle("Inventory")
        .navBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .leadingNavBar) {
                Button {
                    // Info button — future: show tooltip
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            let tabIds = ["items", "transactions", "spaces"]
            if let index = tabIds.firstIndex(of: newValue) {
                inventoryContext.lastSelectedTab = index
            }
        }
        .background(BrandColors.background)
    }
}
