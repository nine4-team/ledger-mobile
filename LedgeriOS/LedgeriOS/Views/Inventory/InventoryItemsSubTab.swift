import SwiftUI

struct InventoryItemsSubTab: View {
    @Environment(InventoryContext.self) private var inventoryContext
    @Environment(AccountContext.self) private var accountContext

    @State private var searchText = ""
    @State private var isSearchVisible = false
    @State private var activeFilter: ItemFilterOption = .all
    @State private var activeSort: ItemSortOption = .createdDesc
    @State private var selectedItemIds: Set<String> = []
    @State private var expandedGroups: Set<String> = []
    @State private var showFilterMenu = false
    @State private var showSortMenu = false
    @State private var showBulkActionMenu = false
    @State private var showBulkStatusPicker = false
    @State private var showBulkSetSpace = false
    @State private var showBulkSellToProject = false
    @State private var showBulkDeleteConfirmation = false
    @State private var showNewItem = false

    // MARK: - Computed

    private var processedItems: [Item] {
        ListFilterSortCalculations.applyAllFilters(
            inventoryContext.items,
            filter: activeFilter,
            sort: activeSort,
            search: searchText
        )
    }

    private var groups: [ItemGroup] {
        ListFilterSortCalculations.groupItems(processedItems)
    }

    private var showGrouped: Bool {
        ListFilterSortCalculations.shouldShowGrouped(groups)
    }

    private var selectedItems: [Item] {
        inventoryContext.items.filter { item in
            guard let id = item.id else { return false }
            return selectedItemIds.contains(id)
        }
    }

    private var selectedTotalCents: Int? {
        let total = selectedItems.compactMap { $0.purchasePriceCents }.reduce(0, +)
        return total > 0 ? total : nil
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            content
        }
        .safeAreaInset(edge: .bottom) {
            if !selectedItemIds.isEmpty {
                BulkSelectionBar(
                    selectedCount: selectedItemIds.count,
                    totalCents: selectedTotalCents,
                    onBulkActions: { showBulkActionMenu = true },
                    onClear: { selectedItemIds.removeAll() }
                )
            }
        }
        .background(FilterMenu(
            isPresented: $showFilterMenu,
            filters: FilterMenu.filterMenuItems(
                activeFilter: activeFilter,
                onSelect: { activeFilter = $0 }
            ),
            closeOnItemPress: true
        ))
        .background(SortMenu(
            isPresented: $showSortMenu,
            sortOptions: SortMenu.sortMenuItems(
                activeSort: activeSort,
                onSelect: { activeSort = $0 }
            )
        ))
        .sheet(isPresented: $showBulkActionMenu) {
            ActionMenuSheet(title: "\(selectedItemIds.count) Items Selected", items: bulkActionMenuItems)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showBulkStatusPicker) {
            StatusPickerModal { status in updateStatusForSelected(status) }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showBulkSetSpace) {
            SetSpaceModal(
                spaces: inventoryContext.spaces,
                currentSpaceId: nil,
                onSelect: { space in setSpaceForSelected(spaceId: space?.id) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showBulkSellToProject) {
            if let accountId = accountContext.currentAccountId {
                SellToProjectModal(items: selectedItems, accountId: accountId) {
                    selectedItemIds.removeAll()
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .confirmationDialog("Delete \(selectedItemIds.count) items?", isPresented: $showBulkDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteSelected() }
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $showNewItem) {
            Text("New Item — Coming Soon")
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        ItemsListControlBar(
            searchText: $searchText,
            isSearchVisible: $isSearchVisible,
            onSort: { showSortMenu = true },
            onFilter: { showFilterMenu = true },
            onAdd: { showNewItem = true },
            activeFilterCount: activeFilter != .all ? 1 : 0,
            activeSortLabel: activeSort != .createdDesc ? sortLabel(for: activeSort) : nil
        )
        .padding(.horizontal, Spacing.screenPadding)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if processedItems.isEmpty {
            ContentUnavailableView {
                Label(
                    activeFilter != .all || !searchText.isEmpty
                        ? "No items match your filters"
                        : "No inventory items yet",
                    systemImage: "shippingbox"
                )
            }
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: Spacing.cardListGap) {
                    if showGrouped {
                        ForEach(groups) { group in
                            if group.count > 1 {
                                expandableGroupCard(for: group)
                            } else if let item = group.items.first {
                                itemRow(for: item)
                            }
                        }
                    } else {
                        ForEach(processedItems) { item in
                            itemRow(for: item)
                        }
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.vertical, Spacing.sm)
            }
        }
    }

    // MARK: - Item Cards

    @ViewBuilder
    private func itemRow(for item: Item) -> some View {
        if let itemId = item.id {
            if selectedItemIds.isEmpty {
                NavigationLink(value: item) {
                    ItemCard(
                        name: item.name,
                        sku: item.sku,
                        sourceLabel: item.source,
                        priceLabel: displayPrice(for: item),
                        thumbnailUri: item.images?.first?.url,
                        bookmarked: item.bookmark == true,
                        menuItems: singleItemMenuItems(for: item)
                    )
                }
                .buttonStyle(.plain)
            } else {
                ItemCard(
                    name: item.name,
                    sku: item.sku,
                    sourceLabel: item.source,
                    priceLabel: displayPrice(for: item),
                    thumbnailUri: item.images?.first?.url,
                    isSelected: .constant(selectedItemIds.contains(itemId)),
                    bookmarked: item.bookmark == true
                )
                .onTapGesture { toggleSelection(itemId) }
            }
        }
    }

    @ViewBuilder
    private func expandableGroupCard(for group: ItemGroup) -> some View {
        let isExpanded = expandedGroups.contains(group.id)
        VStack(spacing: Spacing.xs) {
            GroupedItemCard(
                name: group.name,
                thumbnailUrl: group.items.first?.images?.first?.url,
                countLabel: "\(group.count) items",
                totalLabel: group.totalCents > 0
                    ? CurrencyFormatting.formatCentsWithDecimals(group.totalCents) : nil,
                isSelected: .constant(false),
                onSelectedChange: { _ in },
                items: group.items.compactMap { item in
                    guard let id = item.id else { return nil }
                    return ItemCardData(
                        id: id,
                        name: item.name,
                        sku: item.sku,
                        sourceLabel: item.source,
                        priceLabel: displayPrice(for: item),
                        thumbnailUri: item.images?.first?.url
                    )
                },
                onItemPress: { _ in }
            )
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded { expandedGroups.remove(group.id) }
                    else { expandedGroups.insert(group.id) }
                }
            }

            if isExpanded {
                ForEach(group.items) { item in
                    itemRow(for: item)
                        .padding(.leading, Spacing.md)
                }
            }
        }
    }

    // MARK: - Menu Items

    private func singleItemMenuItems(for item: Item) -> [ActionMenuItem] {
        guard let itemId = item.id else { return [] }
        return [
            ActionMenuItem(id: "select", label: "Select", icon: "checkmark.circle", onPress: {
                selectedItemIds.insert(itemId)
            }),
        ]
    }

    private var bulkActionMenuItems: [ActionMenuItem] {
        [
            ActionMenuItem(id: "status", label: "Change Status", icon: "flag",
                           onPress: { showBulkStatusPicker = true }),
            ActionMenuItem(id: "space", label: "Set Space", icon: "mappin.and.ellipse",
                           onPress: { showBulkSetSpace = true }),
            ActionMenuItem(id: "sell-project", label: "Sell to Project", icon: "arrow.right.square",
                           onPress: { showBulkSellToProject = true }),
            ActionMenuItem(id: "delete", label: "Delete", icon: "trash", isDestructive: true,
                           onPress: { showBulkDeleteConfirmation = true }),
        ]
    }

    // MARK: - Bulk Actions

    private func updateStatusForSelected(_ status: String) {
        guard let accountId = accountContext.currentAccountId else { return }
        let service = ItemsService(syncTracker: NoOpSyncTracker())
        for item in selectedItems {
            guard let itemId = item.id else { continue }
            Task { try? await service.updateItem(accountId: accountId, itemId: itemId, fields: ["status": status]) }
        }
        selectedItemIds.removeAll()
    }

    private func setSpaceForSelected(spaceId: String?) {
        guard let accountId = accountContext.currentAccountId else { return }
        let service = ItemsService(syncTracker: NoOpSyncTracker())
        let fields: [String: Any] = spaceId != nil ? ["spaceId": spaceId!] : ["spaceId": NSNull()]
        for item in selectedItems {
            guard let itemId = item.id else { continue }
            Task { try? await service.updateItem(accountId: accountId, itemId: itemId, fields: fields) }
        }
        selectedItemIds.removeAll()
    }

    private func deleteSelected() {
        guard let accountId = accountContext.currentAccountId else { return }
        let service = ItemsService(syncTracker: NoOpSyncTracker())
        for item in selectedItems {
            guard let itemId = item.id else { continue }
            Task { try? await service.deleteItem(accountId: accountId, itemId: itemId) }
        }
        selectedItemIds.removeAll()
    }

    private func toggleSelection(_ itemId: String) {
        if selectedItemIds.contains(itemId) { selectedItemIds.remove(itemId) }
        else { selectedItemIds.insert(itemId) }
    }

    // MARK: - Helpers

    private func displayPrice(for item: Item) -> String? {
        if let price = item.purchasePriceCents {
            return CurrencyFormatting.formatCentsWithDecimals(price)
        }
        return nil
    }

    private func sortLabel(for option: ItemSortOption) -> String {
        switch option {
        case .createdDesc: return "Newest"
        case .createdAsc: return "Oldest"
        case .alphabeticalAsc: return "A-Z"
        case .alphabeticalDesc: return "Z-A"
        }
    }
}
