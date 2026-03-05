import SwiftUI

struct InventoryItemsSubTab: View {
    @Environment(InventoryContext.self) private var inventoryContext
    @Environment(AccountContext.self) private var accountContext

    @State private var searchText = ""
    @State private var activeFilters: Set<ItemFilterOption> = []
    @State private var activeSort: ItemSortOption = .createdDesc
    @State private var selectedItemIds: Set<String> = []
    @State private var expandedGroups: Set<String> = []
    @State private var showBulkActionMenu = false
    @State private var showBulkStatusPicker = false
    @State private var showBulkSetSpace = false
    @State private var showBulkSellToProject = false
    @State private var showBulkDeleteConfirmation = false
    @State private var showNewItem = false
    @State private var showSortMenu = false
    @State private var showFilterMenu = false

    // MARK: - Computed

    private var processedItems: [Item] {
        ListFilterSortCalculations.applyAllMultiFilters(
            inventoryContext.items,
            filters: activeFilters,
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

    private var allVisibleIds: [String] {
        processedItems.compactMap(\.id)
    }

    private var isAllSelected: Bool {
        SelectionCalculations.isAllSelected(selectedIds: selectedItemIds, allIds: allVisibleIds)
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
            if !selectedItemIds.isEmpty {
                ListSelectionInfo(
                    text: SelectionCalculations.selectionLabel(
                        count: selectedItemIds.count,
                        total: processedItems.count
                    )
                )
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xs)
            }

            content
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            controlBar
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
            NewItemView(context: .inventory)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .background(SortMenu(
            isPresented: $showSortMenu,
            sortOptions: SortMenu.itemSortMenuItems(
                activeSort: activeSort,
                onSelect: { activeSort = $0 }
            )
        ))
        .background(FilterMenu(
            isPresented: $showFilterMenu,
            filters: FilterMenu.filterMenuItems(
                activeFilters: activeFilters,
                scope: .inventory,
                onToggle: { option in
                    if activeFilters.contains(option) {
                        activeFilters.remove(option)
                    } else {
                        activeFilters.insert(option)
                    }
                }
            ),
            closeOnItemPress: false
        ))
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        NativeListControlBar(
            searchText: $searchText,
            searchPlaceholder: "Search items...",
            onAdd: { showNewItem = true }
        ) {
            if !processedItems.isEmpty {
                Button {
                    selectedItemIds = SelectionCalculations.selectAllToggle(
                        selectedIds: selectedItemIds,
                        allIds: allVisibleIds
                    )
                } label: {
                    SelectorCircle(isSelected: isAllSelected, indicator: .check)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Select all")
            }
        } sortMenu: {
            Button { showSortMenu = true } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundStyle(activeSort != .createdDesc ? BrandColors.primary : .secondary)
            }
        } filterMenu: {
            Button { showFilterMenu = true } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(!activeFilters.isEmpty ? BrandColors.primary : .secondary)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if processedItems.isEmpty {
            ContentUnavailableView {
                Label(
                    !activeFilters.isEmpty || !searchText.isEmpty
                        ? "No items match your filters"
                        : "No inventory items yet",
                    systemImage: "shippingbox"
                )
            }
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                AdaptiveContentWidth {
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
                    .padding(.bottom, Spacing.sm)
                }
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
                        item: item,
                        priceLabel: displayPrice(for: item),
                        budgetCategoryName: categoryName(for: item.budgetCategoryId),
                        isSelected: Binding(
                            get: { selectedItemIds.contains(itemId) },
                            set: { if $0 { selectedItemIds.insert(itemId) } else { selectedItemIds.remove(itemId) } }
                        ),
                        menuItems: singleItemMenuItems(for: item)
                    )
                }
                .buttonStyle(.plain)
            } else {
                ItemCard(
                    item: item,
                    priceLabel: displayPrice(for: item),
                    budgetCategoryName: categoryName(for: item.budgetCategoryId),
                    isSelected: Binding(
                        get: { selectedItemIds.contains(itemId) },
                        set: { if $0 { selectedItemIds.insert(itemId) } else { selectedItemIds.remove(itemId) } }
                    )
                )
                .onTapGesture { toggleSelection(itemId) }
            }
        }
    }

    @ViewBuilder
    private func expandableGroupCard(for group: ItemGroup) -> some View {
        let validItems = group.items.filter { $0.id != nil }
        let groupSelected = !validItems.isEmpty && validItems.allSatisfy { selectedItemIds.contains($0.id!) }
        let totalLabel = group.totalCents > 0
            ? CurrencyFormatting.formatCentsWithDecimals(group.totalCents) : nil
        let summaryItem = group.items.first(where: { $0.images?.first?.url != nil }) ?? group.items.first

        GroupedItemCard(
            name: group.name,
            thumbnailUrl: summaryItem?.images?.first?.url,
            countLabel: "×\(group.count)",
            totalLabel: totalLabel,
            sku: summaryItem?.sku,
            sourceLabel: summaryItem?.source,
            priceLabel: totalLabel,
            isExpanded: Binding(
                get: { expandedGroups.contains(group.id) },
                set: { if $0 { expandedGroups.insert(group.id) } else { expandedGroups.remove(group.id) } }
            ),
            isSelected: Binding(
                get: { groupSelected },
                set: { selected in
                    for item in group.items {
                        if let id = item.id {
                            if selected { selectedItemIds.insert(id) } else { selectedItemIds.remove(id) }
                        }
                    }
                }
            ),
            items: group.items.compactMap { item in
                guard let id = item.id else { return nil }
                return ItemCardData(
                    id: id,
                    name: item.displayName,
                    sku: item.sku,
                    sourceLabel: item.source,
                    priceLabel: displayPrice(for: item),
                    statusLabel: item.status,
                    budgetCategoryName: categoryName(for: item.budgetCategoryId),
                    thumbnailUri: item.images?.first?.url,
                    isSelected: selectedItemIds.contains(id),
                    menuItems: singleItemMenuItems(for: item)
                )
            },
            onItemPress: { cardData in
                if let item = group.items.first(where: { $0.id == cardData.id }) {
                    if !selectedItemIds.isEmpty, let id = item.id {
                        toggleSelection(id)
                    }
                }
            },
            onItemSelectedChange: { id, selected in
                if selected { selectedItemIds.insert(id) } else { selectedItemIds.remove(id) }
            }
        )
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

    private func categoryName(for categoryId: String?) -> String? {
        guard let categoryId else { return nil }
        return accountContext.allBudgetCategories.first(where: { $0.id == categoryId })?.name
    }

    private func displayPrice(for item: Item) -> String? {
        if let price = item.purchasePriceCents {
            return CurrencyFormatting.formatCentsWithDecimals(price)
        }
        return nil
    }
}
