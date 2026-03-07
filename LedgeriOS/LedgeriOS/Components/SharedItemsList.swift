import SwiftUI
import FirebaseFirestore

struct SharedItemsList: View {
    let mode: ItemsListMode
    var onItemPress: ((String) -> Void)?
    var getMenuItems: ((Item) -> [ActionMenuItem])?
    var emptyMessage: String = "No items yet"
    var getWarning: ((Item) -> String?)?

    // New capabilities
    var onAdd: (() -> Void)?
    var getBulkMenuItems: (() -> [ActionMenuItem])?
    var selectedIds: Binding<Set<String>>?
    var useNavigationLinks: Bool = false
    var emptyIcon: String = "tray"
    var filterScope: ItemFilterScope?
    var inline: Bool = false
    var pickerItems: [Item]?

    // Firestore (standalone / picker mode)
    var accountId: String?

    @Environment(AccountContext.self) private var accountContext

    @State private var items: [Item] = []
    @State private var searchText = ""
    @State private var activeFilters: Set<ItemFilterOption> = []
    @State private var activeSort: ItemSortOption = .createdDesc
    @State private var internalSelectedIds: Set<String> = []
    @State private var expandedGroups: Set<String> = []
    @State private var showBulkActionMenu = false
    @State private var showSortMenu = false
    @State private var showFilterMenu = false
    @State private var isLoading = true
    @State private var error: String?
    @State private var listener: ListenerRegistration?

    // MARK: - Resolved Selection Binding

    private var resolvedSelectedIds: Binding<Set<String>> {
        selectedIds ?? $internalSelectedIds
    }

    // MARK: - Computed

    /// Extracts items from embedded mode so we can observe changes with .onChange.
    private var embeddedSourceItems: [Item] {
        if case .embedded(let providedItems, _) = mode { return providedItems }
        return []
    }

    private var processedItems: [Item] {
        ListFilterSortCalculations.applyAllMultiFilters(
            items,
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
        SelectionCalculations.isAllSelected(selectedIds: resolvedSelectedIds.wrappedValue, allIds: allVisibleIds)
    }

    private var selectedTotalCents: Int? {
        let ids = resolvedSelectedIds.wrappedValue
        let pairs = processedItems.compactMap { item -> (id: String, cents: Int)? in
            guard let id = item.id, let cents = item.projectPriceCents ?? item.purchasePriceCents else { return nil }
            return (id: id, cents: cents)
        }
        let total = SelectionCalculations.totalCentsForSelected(selectedIds: ids, items: pairs)
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

    private var needsFirestoreData: Bool {
        switch mode {
        case .standalone:
            return true
        case .picker(let scope, _, _, _, _):
            return scope != nil
        case .embedded:
            return false
        }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if inline {
                VStack(spacing: 0) {
                    controlBar
                    inlineContent
                }
            } else {
                VStack(spacing: 0) {
                    content
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    controlBar
                        .padding(.horizontal, Spacing.screenPadding)
                        .background(BrandColors.background)
                }
                .safeAreaInset(edge: .bottom) {
                    bottomBar
                }
            }
        }
        .task {
            await setupData()
        }
        .onChange(of: embeddedSourceItems) { _, newItems in
            if !newItems.isEmpty || !isStandalone {
                items = newItems
            }
        }
        .onChange(of: pickerItems ?? []) { _, newItems in
            if isPicker {
                items = newItems
            }
        }
        .onDisappear {
            listener?.remove()
            listener = nil
        }
        .sheet(isPresented: $showBulkActionMenu) {
            ActionMenuSheet(
                title: "\(resolvedSelectedIds.wrappedValue.count) selected",
                items: bulkActionMenuItems
            )
            .sheetStyle(.quickMenu)
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
                scope: filterScope ?? (isStandalone ? .inventory : .project),
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

    @ViewBuilder
    private var controlBar: some View {
        // Backup styles: .capsule (original labeled icons in glass pill),
        // .plain (circle buttons with no background container)
        controlBarInstance(style: .card)
    }

    @ViewBuilder
    private func controlBarInstance(style: ControlBarStyle) -> some View {
        NativeListControlBar(
            searchText: $searchText,
            searchPlaceholder: "Search items...",
            onAdd: onAdd,
            style: style
        ) {
            if !isPicker {
                Button {
                    resolvedSelectedIds.wrappedValue = SelectionCalculations.selectAllToggle(
                        selectedIds: resolvedSelectedIds.wrappedValue,
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
        if isLoading && needsFirestoreData {
            LoadingScreen(message: "Loading items...")
        } else if let error {
            ErrorRetryView(
                message: error,
                onRetry: { Task { await setupData() } }
            )
        } else if processedItems.isEmpty {
            let message = !items.isEmpty ? "No items match your filters" : emptyMessage
            ContentUnavailableView {
                Label(message, systemImage: emptyIcon)
            }
            .frame(maxHeight: .infinity)
        } else {
            itemList
        }
    }

    @ViewBuilder
    private var inlineContent: some View {
        if isLoading && needsFirestoreData {
            LoadingScreen(message: "Loading items...")
        } else if let error {
            ErrorRetryView(
                message: error,
                onRetry: { Task { await setupData() } }
            )
        } else if processedItems.isEmpty {
            let message = !items.isEmpty ? "No items match your filters" : emptyMessage
            Text(message)
                .font(Typography.small)
                .foregroundStyle(BrandColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, Spacing.xl)
        } else {
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
            .padding(.top, Spacing.sm)
        }
    }

    @ViewBuilder
    private var itemList: some View {
        ScrollView {
            AdaptiveContentWidth {
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
    }

    // MARK: - Item Cards

    @ViewBuilder
    private func singleItemCard(for item: Item) -> some View {
        // Issue 5: Skip items with nil IDs entirely
        if let itemId = item.id {
            let ids = resolvedSelectedIds.wrappedValue
            let menuItems = getMenuItems?(item) ?? []
            let warning = getWarning?(item)

            if isPicker {
                pickerItemCard(for: item, itemId: itemId, isItemSelected: ids.contains(itemId))
            } else if useNavigationLinks && ids.isEmpty {
                NavigationLink(value: item) {
                    ItemCard(
                        item: item,
                        priceLabel: displayPrice(for: item),
                        budgetCategoryName: categoryName(for: item.budgetCategoryId),
                        isSelected: Binding(
                            get: { resolvedSelectedIds.wrappedValue.contains(itemId) },
                            set: { if $0 { resolvedSelectedIds.wrappedValue.insert(itemId) } else { resolvedSelectedIds.wrappedValue.remove(itemId) } }
                        ),
                        menuItems: menuItems,
                        warningMessage: warning
                    )
                }
                .buttonStyle(.plain)
            } else {
                ItemCard(
                    item: item,
                    priceLabel: displayPrice(for: item),
                    budgetCategoryName: categoryName(for: item.budgetCategoryId),
                    isSelected: Binding(
                        get: { resolvedSelectedIds.wrappedValue.contains(itemId) },
                        set: { if $0 { resolvedSelectedIds.wrappedValue.insert(itemId) } else { resolvedSelectedIds.wrappedValue.remove(itemId) } }
                    ),
                    onPress: { handleItemPress(item) },
                    menuItems: menuItems,
                    warningMessage: warning
                )
                .onTapGesture {
                    if !ids.isEmpty {
                        toggleSelection(itemId)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pickerItemCard(for item: Item, itemId: String, isItemSelected: Bool) -> some View {
        if case .picker(_, let eligibilityCheck, let onAddSingle, let addedIds, _) = mode {
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
                        Text(item.displayName)
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
        // Issue 4: Use compactMap to only include items with valid IDs
        let ids = resolvedSelectedIds.wrappedValue
        let validItems = group.items.filter { $0.id != nil }
        let groupSelected = !validItems.isEmpty && validItems.allSatisfy { ids.contains($0.id!) }
        let totalLabel = group.totalCents > 0 ? CurrencyFormatting.formatCentsWithDecimals(group.totalCents) : nil

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
                            if selected { resolvedSelectedIds.wrappedValue.insert(id) } else { resolvedSelectedIds.wrappedValue.remove(id) }
                        }
                    }
                }
            ),
            onSelectedChange: { selected in
                for item in group.items {
                    if let id = item.id {
                        if selected { resolvedSelectedIds.wrappedValue.insert(id) } else { resolvedSelectedIds.wrappedValue.remove(id) }
                    }
                }
            },
            items: group.items.compactMap { item in
                // Issue 4: Skip items with nil IDs instead of UUID fallback
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
                    warningMessage: getWarning?(item),
                    isSelected: ids.contains(id),
                    menuItems: getMenuItems?(item) ?? []
                )
            },
            onItemPress: { cardData in
                if let item = group.items.first(where: { $0.id == cardData.id }) {
                    handleItemPress(item)
                }
            },
            onItemSelectedChange: { id, selected in
                if selected { resolvedSelectedIds.wrappedValue.insert(id) } else { resolvedSelectedIds.wrappedValue.remove(id) }
            }
        )
    }

    // MARK: - Bottom Bar

    @ViewBuilder
    private var bottomBar: some View {
        if isPicker {
            pickerBottomBar
        } else if !resolvedSelectedIds.wrappedValue.isEmpty {
            BulkSelectionBar(
                selectedCount: resolvedSelectedIds.wrappedValue.count,
                totalCents: selectedTotalCents,
                onBulkActions: { showBulkActionMenu = true },
                onClear: { resolvedSelectedIds.wrappedValue.removeAll() }
            )
        }
    }

    @ViewBuilder
    private var pickerBottomBar: some View {
        if case .picker(_, _, _, _, let onAddSelected) = mode, !resolvedSelectedIds.wrappedValue.isEmpty {
            HStack {
                Text("\(resolvedSelectedIds.wrappedValue.count) selected")
                    .font(Typography.body)
                    .fontWeight(.bold)
                    .foregroundStyle(BrandColors.textPrimary)

                Spacer()

                // Issue 3: Clear selection after adding
                AppButton(title: "Add Selected") {
                    onAddSelected?()
                    resolvedSelectedIds.wrappedValue.removeAll()
                }
                .fixedSize()
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.sm)
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
        case .picker(let scope, _, _, _, _):
            if let pickerItems {
                items = pickerItems
                isLoading = false
            } else if let scope {
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

        if !resolvedSelectedIds.wrappedValue.isEmpty && !isPicker {
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
        if resolvedSelectedIds.wrappedValue.contains(itemId) {
            resolvedSelectedIds.wrappedValue.remove(itemId)
        } else {
            resolvedSelectedIds.wrappedValue.insert(itemId)
        }
    }

    private var bulkActionMenuItems: [ActionMenuItem] {
        var items = getBulkMenuItems?() ?? []
        items.append(
            ActionMenuItem(id: "clear-selection", label: "Clear Selection", icon: "xmark.circle", onPress: {
                resolvedSelectedIds.wrappedValue.removeAll()
            })
        )
        return items
    }

    // MARK: - Helpers

    private func categoryName(for categoryId: String?) -> String? {
        guard let categoryId else { return nil }
        return accountContext.allBudgetCategories.first(where: { $0.id == categoryId })?.name
    }

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
            scope: nil,
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
