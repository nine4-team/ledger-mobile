import SwiftUI
import FirebaseFirestore

struct SharedItemsList: View {
    let mode: ItemsListMode
    var onItemPress: ((String) -> Void)?
    var getMenuItems: ((Item) -> [ActionMenuItem])?
    var emptyMessage: String = "No items yet"
    var getWarning: ((Item) -> String?)?

    // Firestore (standalone mode)
    var accountId: String?

    @State private var items: [Item] = []
    @State private var searchText = ""
    @State private var isSearchVisible = false
    @State private var activeFilter: ItemFilterOption = .all
    @State private var activeSort: ItemSortOption = .createdDesc
    @State private var activeFilters: Set<ItemFilterOption> = []
    @State private var selectedIds: Set<String> = []
    @State private var showFilterMenu = false
    @State private var showSortMenu = false
    @State private var showBulkActionMenu = false
    @State private var isLoading = true
    @State private var error: String?
    @State private var listener: ListenerRegistration?

    // MARK: - Computed

    private var processedItems: [Item] {
        ListFilterSortCalculations.applyAllFilters(
            items,
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

    private var allVisibleIds: [String] {
        processedItems.compactMap(\.id)
    }

    private var isAllSelected: Bool {
        SelectionCalculations.isAllSelected(selectedIds: selectedIds, allIds: allVisibleIds)
    }

    private var selectedTotalCents: Int? {
        let pairs = processedItems.compactMap { item -> (id: String, cents: Int)? in
            guard let id = item.id, let cents = item.projectPriceCents ?? item.purchasePriceCents else { return nil }
            return (id: id, cents: cents)
        }
        let total = SelectionCalculations.totalCentsForSelected(selectedIds: selectedIds, items: pairs)
        return total > 0 ? total : nil
    }

    private var isPicker: Bool {
        if case .picker = mode { return true }
        return false
    }

    private var isStandalone: Bool {
        if case .standalone = mode { return true }
        return false
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            controlBar

            if !processedItems.isEmpty && !isPicker {
                selectAllRow
            }

            if !selectedIds.isEmpty {
                ListSelectionInfo(
                    text: SelectionCalculations.selectionLabel(
                        count: selectedIds.count,
                        total: processedItems.count
                    )
                )
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xs)
            }

            content
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .task {
            await setupData()
        }
        .onDisappear {
            listener?.remove()
            listener = nil
        }
        .background(FilterMenu(
            isPresented: $showFilterMenu,
            filters: FilterMenu.filterMenuItems(
                activeFilters: activeFilters,
                onToggle: { option in toggleFilter(option) }
            )
        ))
        .background(SortMenu(
            isPresented: $showSortMenu,
            sortOptions: SortMenu.sortMenuItems(
                activeSort: activeSort,
                onSelect: { option in activeSort = option }
            )
        ))
        .sheet(isPresented: $showBulkActionMenu) {
            ActionMenuSheet(
                title: "\(selectedIds.count) selected",
                items: bulkActionMenuItems
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Control Bar

    @ViewBuilder
    private var controlBar: some View {
        ItemsListControlBar(
            searchText: $searchText,
            isSearchVisible: $isSearchVisible,
            onSort: { showSortMenu = true },
            onFilter: { showFilterMenu = true },
            activeFilterCount: activeFilters.count,
            activeSortLabel: activeSort != .createdDesc ? sortLabel(for: activeSort) : nil
        )
        .padding(.horizontal, Spacing.screenPadding)
    }

    // MARK: - Select All Row

    private var selectAllRow: some View {
        ListSelectAllRow(
            isChecked: isAllSelected,
            onToggle: {
                selectedIds = SelectionCalculations.selectAllToggle(
                    selectedIds: selectedIds,
                    allIds: allVisibleIds
                )
            }
        )
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading && isStandalone {
            LoadingScreen(message: "Loading items...")
        } else if let error {
            ErrorRetryView(
                message: error,
                onRetry: { Task { await setupData() } }
            )
        } else if processedItems.isEmpty {
            ContentUnavailableView {
                Label(emptyMessage, systemImage: "tray")
            }
            .frame(maxHeight: .infinity)
        } else {
            itemList
        }
    }

    @ViewBuilder
    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.cardListGap) {
                if showGrouped {
                    ForEach(groups) { group in
                        if group.count > 1 {
                            groupedCard(for: group)
                        } else if let item = group.items.first {
                            singleItemCard(for: item)
                        }
                    }
                } else {
                    ForEach(processedItems) { item in
                        singleItemCard(for: item)
                    }
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.sm)
        }
    }

    // MARK: - Item Cards

    @ViewBuilder
    private func singleItemCard(for item: Item) -> some View {
        let itemId = item.id ?? ""
        let isItemSelected = selectedIds.contains(itemId)
        let menuItems = getMenuItems?(item) ?? []
        let warning = getWarning?(item)

        if isPicker {
            pickerItemCard(for: item, itemId: itemId, isItemSelected: isItemSelected)
        } else {
            ItemCard(
                name: item.name,
                sku: item.sku,
                sourceLabel: item.source,
                priceLabel: displayPrice(for: item),
                thumbnailUri: item.images?.first?.url,
                isSelected: isItemSelected ? .constant(true) : selectedIds.isEmpty ? nil : .constant(false),
                bookmarked: item.bookmark == true,
                onPress: { handleItemPress(item) },
                menuItems: menuItems,
                warningMessage: warning
            )
            .onTapGesture {
                if !selectedIds.isEmpty {
                    toggleSelection(itemId)
                }
            }
        }
    }

    @ViewBuilder
    private func pickerItemCard(for item: Item, itemId: String, isItemSelected: Bool) -> some View {
        if case .picker(let eligibilityCheck, let onAddSingle, let addedIds, _) = mode {
            let isAdded = addedIds.contains(itemId)
            let isEligible = eligibilityCheck?(item) ?? true

            Button {
                if isAdded { return }
                if let onAddSingle {
                    onAddSingle(item)
                } else if isEligible {
                    toggleSelection(itemId)
                }
            } label: {
                HStack(spacing: Spacing.md) {
                    if isAdded {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 22))
                    } else {
                        SelectorCircle(isSelected: isItemSelected, indicator: .check)
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(item.name)
                            .font(Typography.body)
                            .foregroundStyle(isEligible || isAdded ? BrandColors.textPrimary : BrandColors.textDisabled)
                            .lineLimit(2)

                        if let price = displayPrice(for: item) {
                            Text(price)
                                .font(Typography.small)
                                .foregroundStyle(BrandColors.textSecondary)
                        }
                    }

                    Spacer()

                    if let url = item.images?.first?.url, let imageUrl = URL(string: url) {
                        AsyncImage(url: imageUrl) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFill()
                            } else {
                                Color(BrandColors.surfaceTertiary)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(Spacing.cardPadding)
                .cardStyle()
            }
            .buttonStyle(.plain)
            .disabled(!isEligible && !isAdded)
            .opacity(isEligible || isAdded ? 1 : 0.5)
        }
    }

    @ViewBuilder
    private func groupedCard(for group: ItemGroup) -> some View {
        let groupSelected = group.items.allSatisfy { selectedIds.contains($0.id ?? "") }
        let totalLabel = group.totalCents > 0 ? CurrencyFormatting.formatCentsWithDecimals(group.totalCents) : nil

        GroupedItemCard(
            name: group.name,
            thumbnailUrl: group.items.first?.images?.first?.url,
            countLabel: "\(group.count) items",
            totalLabel: totalLabel,
            isSelected: groupSelected ? .constant(true) : .constant(false),
            onSelectedChange: { selected in
                for item in group.items {
                    if let id = item.id {
                        if selected {
                            selectedIds.insert(id)
                        } else {
                            selectedIds.remove(id)
                        }
                    }
                }
            },
            items: group.items.map { item in
                ItemCardData(
                    id: item.id ?? UUID().uuidString,
                    name: item.name,
                    sku: item.sku,
                    sourceLabel: item.source,
                    priceLabel: displayPrice(for: item),
                    thumbnailUri: item.images?.first?.url,
                    warningMessage: getWarning?(item)
                )
            },
            onItemPress: { cardData in
                if let item = group.items.first(where: { $0.id == cardData.id }) {
                    handleItemPress(item)
                }
            }
        )
    }

    // MARK: - Bottom Bar

    @ViewBuilder
    private var bottomBar: some View {
        if isPicker {
            pickerBottomBar
        } else if !selectedIds.isEmpty {
            BulkSelectionBar(
                selectedCount: selectedIds.count,
                totalCents: selectedTotalCents,
                onBulkActions: { showBulkActionMenu = true },
                onClear: { selectedIds.removeAll() }
            )
        }
    }

    @ViewBuilder
    private var pickerBottomBar: some View {
        if case .picker(_, _, _, let onAddSelected) = mode, !selectedIds.isEmpty {
            HStack {
                Text("\(selectedIds.count) selected")
                    .font(Typography.body)
                    .fontWeight(.bold)
                    .foregroundStyle(BrandColors.textPrimary)

                Spacer()

                AppButton(title: "Add Selected") {
                    onAddSelected?()
                }
                .fixedSize()
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.sm)
            .background(BrandColors.surface)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(BrandColors.border)
                    .frame(height: Dimensions.borderWidth)
            }
        }
    }

    // MARK: - Data Setup

    private func setupData() async {
        switch mode {
        case .standalone(let scope):
            await setupStandaloneListener(scope: scope)
        case .embedded(let providedItems, _):
            items = providedItems
            isLoading = false
        case .picker(_, _, _, _):
            // Picker can use standalone data or embedded data
            // If accountId is provided, fetch from Firestore
            if let accountId, case .standalone(let scope) = mode {
                await setupStandaloneListener(scope: scope)
            } else {
                isLoading = false
            }
        }
    }

    private func setupStandaloneListener(scope: ListScope) async {
        guard let accountId else {
            error = "No account selected"
            isLoading = false
            return
        }

        listener?.remove()
        isLoading = true
        error = nil

        let service = ItemsService(syncTracker: NoOpSyncTracker())
        listener = service.subscribeToItems(accountId: accountId, scope: scope) { [self] newItems in
            Task { @MainActor in
                self.items = newItems
                self.isLoading = false
            }
        }
    }

    // MARK: - Actions

    private func handleItemPress(_ item: Item) {
        guard let itemId = item.id else { return }

        if !selectedIds.isEmpty && !isPicker {
            toggleSelection(itemId)
            return
        }

        switch mode {
        case .embedded(_, let onPress):
            onPress(itemId)
        default:
            onItemPress?(itemId)
        }
    }

    private func toggleSelection(_ itemId: String) {
        if selectedIds.contains(itemId) {
            selectedIds.remove(itemId)
        } else {
            selectedIds.insert(itemId)
        }
    }

    private func toggleFilter(_ option: ItemFilterOption) {
        if activeFilters.contains(option) {
            activeFilters.remove(option)
        } else {
            activeFilters.insert(option)
        }
        activeFilter = activeFilters.first ?? .all
    }

    private var bulkActionMenuItems: [ActionMenuItem] {
        [
            ActionMenuItem(id: "clear-selection", label: "Clear Selection", icon: "xmark.circle", onPress: {
                selectedIds.removeAll()
            }),
        ]
    }

    // MARK: - Helpers

    private func displayPrice(for item: Item) -> String? {
        if let price = item.projectPriceCents, price != item.purchasePriceCents {
            return CurrencyFormatting.formatCentsWithDecimals(price)
        } else if let price = item.purchasePriceCents {
            return CurrencyFormatting.formatCentsWithDecimals(price)
        } else if let price = item.projectPriceCents {
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

// MARK: - Previews

#Preview("Standalone (Mock Data)") {
    SharedItemsList(
        mode: .standalone(scope: .all),
        emptyMessage: "No items in this project"
    )
}

#Preview("Embedded with Items") {
    let mockItems = [
        Item(name: "Gold metal branch decor", source: "Ross", sku: "400293670643", purchasePriceCents: 1099),
        Item(name: "Blue-gray matte pottery vase", source: "Homegoods", sku: "373346", purchasePriceCents: 2499),
        Item(name: "Beige/lime green velvet pillow", source: "Joon Loloi", projectPriceCents: 2400),
    ]

    SharedItemsList(
        mode: .embedded(items: mockItems, onItemPress: { id in print("Tapped \(id)") }),
        getMenuItems: { _ in
            [
                ActionMenuItem(id: "edit", label: "Edit", icon: "pencil"),
                ActionMenuItem(id: "delete", label: "Delete", icon: "trash", isDestructive: true),
            ]
        }
    )
}

#Preview("Picker Mode") {
    let mockItems = [
        Item(name: "Sofa", purchasePriceCents: 89900),
        Item(name: "Coffee Table", purchasePriceCents: 35000),
        Item(name: "Floor Lamp", purchasePriceCents: 20100),
    ]

    SharedItemsList(
        mode: .picker(
            eligibilityCheck: { _ in true },
            onAddSingle: nil,
            addedIds: [],
            onAddSelected: { print("Add selected") }
        )
    )
}

#Preview("Empty State") {
    SharedItemsList(
        mode: .embedded(items: [], onItemPress: { _ in }),
        emptyMessage: "No items match your filters"
    )
}
