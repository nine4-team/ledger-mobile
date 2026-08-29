import SwiftUI
import FirebaseFirestore

struct ItemFilterCatalog {
    let spaces: [Space]
    let budgetCategories: [BudgetCategory]

    static var empty: ItemFilterCatalog {
        ItemFilterCatalog(spaces: [], budgetCategories: [])
    }
}

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
    var emptyIcon: String = "tray"
    var filterScope: ItemFilterScope?
    var filterCatalog: ItemFilterCatalog = .empty
    var inline: Bool = false
    var pickerItems: [Item]?
    var inlineSectionHeader: AnyView? = nil
    var externalSearchText: Binding<String>?
    var protoItems: [ProtoItem] = []
    var protoItemCard: ((ProtoItem) -> AnyView)?
    var isItemMarkedInPhoto: ((Item) -> Bool)?
    var photoMatchActionTitle: ((Item) -> String?)?
    var photoMatchTargetItemId: String?
    var onPhotoMatchPress: ((Item) -> Void)?
    var showsGroupExpansionControl: Bool = false

    // Firestore (standalone / picker mode)
    var accountId: String?

    @Environment(AccountContext.self) private var accountContext

    @State private var items: [Item] = []
    @State private var searchText = ""
    @State private var activeFilters = ItemFilterState()
    @State private var activeSort: ItemSortOption = .createdDesc
    @State private var internalSelectedIds: Set<String> = []
    @State private var expandedGroups: Set<String> = []
    #if os(macOS)
    @State private var macOSExpandedGroup: ItemGroup?
    #endif
    @State private var showBulkActionMenu = false
    @State private var showSortMenu = false
    @State private var showFilterMenu = false
    @State private var isLoading = true
    @State private var error: String?
    @State private var listener: ListenerRegistration?
    @State private var pendingMoveItem: Item?
    @State private var pendingMoveFromSpaceName: String?

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
        PerformanceDiagnostics.shared.measureAggregate("ListDerivation", kind: "filter-sort-search") {
            ListFilterSortCalculations.applyAllGroupedFilters(
                items,
                filters: activeFilters,
                sort: activeSort,
                search: resolvedSearchText.wrappedValue,
                photoMarkedItemIDs: markedPhotoItemIDs
            )
        }
    }

    private var markedPhotoItemIDs: Set<String> {
        guard filterScope == .spaceDetail, let isItemMarkedInPhoto else { return [] }
        return Set(items.compactMap { item in
            guard isItemMarkedInPhoto(item) else { return nil }
            return item.id
        })
    }

    private var processedProtoItems: [ProtoItem] {
        guard !activeFilters.isActive else { return [] }
        let trimmed = resolvedSearchText.wrappedValue.trimmingCharacters(in: .whitespaces)
        let activeProtoItems = protoItems.filter { $0.status == nil || $0.status == .open || $0.status == .inReview }
        guard !trimmed.isEmpty else { return activeProtoItems }
        return activeProtoItems.filter { SearchCalculations.protoItemMatches(protoItem: $0, query: trimmed) }
    }

    private var hasProcessedResults: Bool {
        !processedProtoItems.isEmpty || !processedItems.isEmpty
    }

    private var hasSourceResults: Bool {
        !protoItems.isEmpty || !items.isEmpty
    }

    private var sourceFilterChoices: [ItemFilterChoice] {
        uniqueTextChoices(
            items.compactMap { item in
                let value = item.currentSource ?? item.source
                guard let value else { return nil }
                let label = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return label.isEmpty ? nil : label
            },
            normalizedID: ItemFilterValues.normalizedText
        )
    }

    private var spaceFilterChoices: [ItemFilterChoice] {
        let referencedIDs = Set(items.compactMap { item -> String? in
            let id = item.spaceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return id.isEmpty ? nil : id
        })
        var choices = filterCatalog.spaces.compactMap { space -> ItemFilterChoice? in
            guard let id = space.id else { return nil }
            guard space.isArchived != true || referencedIDs.contains(id) else { return nil }
            let baseLabel = space.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = baseLabel.isEmpty ? "Unnamed Space" : baseLabel
            let label = space.isArchived == true ? "\(name) (Archived)" : name
            return ItemFilterChoice(id: id, label: label)
        }
        let knownIDs = Set(choices.map(\.id))
        choices.append(contentsOf: referencedIDs.subtracting(knownIDs).map {
            ItemFilterChoice(id: $0, label: "Unknown Space")
        })
        return choices.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    private var budgetCategoryFilterChoices: [ItemFilterChoice] {
        let referencedIDs = Set(items.compactMap { item -> String? in
            let id = item.budgetCategoryId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return id.isEmpty ? nil : id
        })
        var choices = filterCatalog.budgetCategories.compactMap { category -> ItemFilterChoice? in
            guard let id = category.id else { return nil }
            return ItemFilterChoice(id: id, label: category.name)
        }
        let knownIDs = Set(choices.map(\.id))
        choices.append(contentsOf: referencedIDs.subtracting(knownIDs).map {
            ItemFilterChoice(id: $0, label: "Unknown Category")
        })
        return choices.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    private var purchasedByFilterChoices: [ItemFilterChoice] {
        var choices = [
            ItemFilterChoice(id: "client-card", label: "Client"),
            ItemFilterChoice(id: "design-business", label: "Design Business"),
            ItemFilterChoice(id: ItemFilterValues.missing, label: "Not Set"),
        ]
        let knownIDs = Set(choices.map(\.id))
        let customLabels = items.compactMap { item -> String? in
            guard let value = item.purchasedBy?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty,
                  !knownIDs.contains(ItemFilterValues.purchasedBy(for: item)) else { return nil }
            return value
        }
        choices.append(contentsOf: uniqueTextChoices(
            customLabels,
            normalizedID: ItemFilterValues.normalizedText
        ))
        return choices
    }

    private var resolvedSearchText: Binding<String> {
        externalSearchText ?? $searchText
    }

    private func uniqueTextChoices(
        _ labels: [String],
        normalizedID: (String) -> String
    ) -> [ItemFilterChoice] {
        var labelsByID: [String: String] = [:]
        for rawLabel in labels {
            let label = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            let id = normalizedID(label)
            guard !label.isEmpty, !id.isEmpty else { continue }
            if labelsByID[id] == nil {
                labelsByID[id] = label
            }
        }
        return labelsByID
            .map { ItemFilterChoice(id: $0.key, label: $0.value) }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    private var groups: [ItemGroup] {
        PerformanceDiagnostics.shared.measureAggregate("ListDerivation", kind: "grouping") {
            ListFilterSortCalculations.groupItems(processedItems)
        }
    }

    private var sourceGroupsByID: [String: ItemGroup] {
        guard filterScope == .spaceDetail else { return [:] }
        return Dictionary(
            uniqueKeysWithValues: ListFilterSortCalculations.groupItems(items).map { ($0.id, $0) }
        )
    }

    private var showGrouped: Bool {
        ListFilterSortCalculations.shouldShowGrouped(groups)
    }

    private var visibleExpandableGroupIDs: Set<String> {
        ListFilterSortCalculations.expandableGroupIDs(in: groups)
    }

    private var showsVisibleGroupExpansionControl: Bool {
        showsGroupExpansionControl && !visibleExpandableGroupIDs.isEmpty
    }

    private var areAllVisibleGroupsExpanded: Bool {
        let groupIDs = visibleExpandableGroupIDs
        return !groupIDs.isEmpty && groupIDs.isSubset(of: expandedGroups)
    }

    private var visibleGroupExpansionAction: (() -> Void)? {
        guard showsVisibleGroupExpansionControl else { return nil }
        return { toggleVisibleGroupExpansion() }
    }

    private var allVisibleIds: [String] {
        processedItems.compactMap(\.id)
    }

    private var isAllSelected: Bool {
        SelectionCalculations.isAllSelected(selectedIds: resolvedSelectedIds.wrappedValue, allIds: allVisibleIds)
    }

    private var selectedTotalCents: Int? {
        PerformanceDiagnostics.shared.measureAggregate("ListDerivation", kind: "selection-total") {
            let ids = resolvedSelectedIds.wrappedValue
            let pairs = processedItems.compactMap { item -> (id: String, cents: Int)? in
                guard let id = item.id, let cents = item.normalizedProjectPriceCents else { return nil }
                return (id: id, cents: cents)
            }
            let total = SelectionCalculations.totalCentsForSelected(selectedIds: ids, items: pairs)
            return total > 0 ? total : nil
        }
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
        case .picker(let scope, _, _, _, _, _):
            return scope != nil
        case .embedded:
            return false
        }
    }

    // MARK: - Body

    var body: some View {
        let _ = recordBodyEvaluation()
        Group {
            if inline {
                Section {
                    inlineContent
                } header: {
                    VStack(spacing: 0) {
                        if let inlineSectionHeader {
                            inlineSectionHeader
                        }
                        controlBar
                    }
                    .textCase(nil)
                    .background(BrandColors.background
                        .padding(.horizontal, -Spacing.screenPadding))
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
        #if os(macOS)
        .overlay {
            if !inline, let group = macOSExpandedGroup {
                groupExpandedOverlay(for: group)
            }
        }
        #endif
        .task {
            await setupData()
        }
        .onAppear {
            PerformanceDiagnostics.shared.event("ListAppeared", kind: diagnosticMode, count: items.count)
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
        .onChange(of: activeFilters) { _, _ in
            // Bulk actions must never retain items hidden by a newly applied filter.
            resolvedSelectedIds.wrappedValue.formIntersection(Set(allVisibleIds))
        }
        .onChange(of: showsGroupExpansionControl) { _, isEnabled in
            if !isEnabled {
                expandedGroups.removeAll()
            }
        }
        .onDisappear {
            PerformanceDiagnostics.shared.event("ListDisappeared", kind: diagnosticMode, count: items.count)
            listener?.remove()
            listener = nil
        }
        .alert(
            "Move from \(pendingMoveFromSpaceName ?? "another space")?",
            isPresented: Binding(
                get: { pendingMoveItem != nil },
                set: { if !$0 { pendingMoveItem = nil; pendingMoveFromSpaceName = nil } }
            ),
            presenting: pendingMoveItem
        ) { item in
            Button("Stage Move") {
                if let id = item.id { toggleSelection(id) }
                pendingMoveItem = nil
                pendingMoveFromSpaceName = nil
            }
            Button("Cancel", role: .cancel) {
                pendingMoveItem = nil
                pendingMoveFromSpaceName = nil
            }
        } message: { item in
            Text("\(item.displayName) is currently in \(pendingMoveFromSpaceName ?? "another space"). Adding it here will move it.")
        }
        .adaptivePresentation(isPresented: $showBulkActionMenu, style: .quickMenu) {
            ActionMenuSheet(
                title: "\(resolvedSelectedIds.wrappedValue.count) selected",
                items: bulkActionMenuItems
            )
        }
        .background(SortMenu(
            isPresented: $showSortMenu,
            sortOptions: SortMenu.itemSortMenuItems(
                activeSort: activeSort,
                includePhotoCheckmark: filterScope == .spaceDetail,
                onSelect: { activeSort = $0 }
            )
        ))
        .background(ItemFilterMenu(
            isPresented: $showFilterMenu,
            filterState: $activeFilters,
            scope: filterScope ?? (isStandalone ? .inventory : .project),
            spaces: spaceFilterChoices,
            sources: sourceFilterChoices,
            budgetCategories: budgetCategoryFilterChoices,
            purchasedByOptions: purchasedByFilterChoices
        ))
    }

    // MARK: - Control Bar

    @ViewBuilder
    private var controlBar: some View {
        // Backup styles: .capsule (original labeled icons in glass pill),
        // .plain (circle buttons with no background container)
        controlBarInstance(style: .plain)
    }

    @ViewBuilder
    private func controlBarInstance(style: ControlBarStyle) -> some View {
        if isPicker {
            pickerControlBar(style: style)
        } else {
            standardControlBar(style: style)
        }
    }

    private func recordBodyEvaluation() {
        let diagnostics = PerformanceDiagnostics.shared
        guard diagnostics.isEnabled else { return }
        diagnostics.event(
            "ViewBodyEvaluated",
            kind: "shared-items-list.\(diagnosticMode)",
            count: items.count
        )
    }

    @ViewBuilder
    private func standardControlBar(style: ControlBarStyle) -> some View {
        NativeListControlBar(
            searchText: resolvedSearchText,
            searchPlaceholder: "Search items...",
            onAdd: onAdd,
            onToggleGroupExpansion: visibleGroupExpansionAction,
            areGroupsExpanded: areAllVisibleGroupsExpanded,
            style: style
        ) {
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
        } sortMenu: {
            Button { showSortMenu = true } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundStyle(activeSort != .createdDesc ? BrandColors.primary : BrandColors.textSecondary)
            }
        } filterMenu: {
            Button { showFilterMenu = true } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(activeFilters.isActive ? BrandColors.primary : BrandColors.textSecondary)
            }
        }
    }

    /// Picker mode: inline search field next to sort/filter buttons (no toggle).
    @ViewBuilder
    private func pickerControlBar(style: ControlBarStyle) -> some View {
        HStack(spacing: Spacing.sm) {
            SearchField(
                text: resolvedSearchText,
                placeholder: "Search items..."
            )

            Button { showSortMenu = true } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundStyle(activeSort != .createdDesc ? BrandColors.primary : BrandColors.textSecondary)
            }
            .buttonStyle(CircleBarButtonStyle())
            .tint(BrandColors.textSecondary)
            .font(.system(size: 16))
            .imageScale(.medium)
            .background(BrandColors.surface, in: Circle())
            .overlay(Circle().stroke(BrandColors.borderSecondary, lineWidth: Dimensions.borderWidth))
            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)

            Button { showFilterMenu = true } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(activeFilters.isActive ? BrandColors.primary : BrandColors.textSecondary)
            }
            .buttonStyle(CircleBarButtonStyle())
            .tint(BrandColors.textSecondary)
            .font(.system(size: 16))
            .imageScale(.medium)
            .background(BrandColors.surface, in: Circle())
            .overlay(Circle().stroke(BrandColors.borderSecondary, lineWidth: Dimensions.borderWidth))
            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: Dimensions.contentMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
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
        } else if !hasProcessedResults {
            let message = hasSourceResults ? "No items match your filters" : emptyMessage
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
        } else if !hasProcessedResults {
            let message = hasSourceResults ? "No items match your filters" : emptyMessage
            Text(message)
                .font(Typography.small)
                .foregroundStyle(BrandColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, Spacing.xl)
        } else {
            let completeGroupsByID = sourceGroupsByID
            let photoMarkedIDs = markedPhotoItemIDs
            LazyVStack(alignment: .leading, spacing: Spacing.cardListGap) {
                ForEach(processedProtoItems) { protoItem in
                    protoItemRow(for: protoItem)
                }

                if showGrouped {
                    ForEach(groups) { group in
                        if group.count > 1 {
                            groupedCard(
                                for: group,
                                completeGroup: completeGroupsByID[group.id],
                                photoMarkedItemIDs: photoMarkedIDs
                            )
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

    @Environment(FindStateManager.self) private var findState

    @ViewBuilder
    private var itemList: some View {
        let completeGroupsByID = sourceGroupsByID
        let photoMarkedIDs = markedPhotoItemIDs
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: Dimensions.listColumns,
                    alignment: .leading,
                    spacing: Spacing.cardListGap
                ) {
                    ForEach(processedProtoItems) { protoItem in
                        protoItemRow(for: protoItem)
                    }

                    if showGrouped {
                        ForEach(groups) { group in
                            if group.count > 1 {
                                groupedCard(
                                    for: group,
                                    completeGroup: completeGroupsByID[group.id],
                                    photoMarkedItemIDs: photoMarkedIDs
                                )
                            } else if let item = group.items.first {
                                singleItemCard(for: item)
                            }
                        }
                    } else {
                        ForEach(processedItems) { item in
                            singleItemCard(for: item)
                                .id(item.id ?? "")
                        }
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

    // MARK: - macOS Group Overlay

    #if os(macOS)
    @ViewBuilder
    private func groupExpandedOverlay(for group: ItemGroup) -> some View {
        ZStack {
            // Dimmed background — tap to dismiss
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation { macOSExpandedGroup = nil }
                }

            // Centered card panel
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text(group.name)
                        .font(Typography.h2)
                        .foregroundStyle(BrandColors.textPrimary)
                    Spacer()
                    Text("×\(group.count)")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                    Button {
                        withAnimation { macOSExpandedGroup = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(BrandColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(Spacing.md)

                CardDivider()

                // Scrollable item cards
                ScrollView {
                    VStack(spacing: Spacing.cardListGap) {
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                            if let itemId = item.id {
                                let selectionBinding = Binding(
                                    get: { resolvedSelectedIds.wrappedValue.contains(itemId) },
                                    set: { if $0 { resolvedSelectedIds.wrappedValue.insert(itemId) } else { resolvedSelectedIds.wrappedValue.remove(itemId) } }
                                )
                                ItemCard(
                                    item: item,
                                    priceLabel: displayPrice(for: item),
                                    budgetCategoryName: categoryName(for: item.budgetCategoryId),
                                    indexLabel: "\(index + 1)/\(group.items.count)",
                                    statusOverride: item.status?.displayLabel,
                                    isSelected: selectionBinding,
                                    isMarkedInPhoto: isItemMarkedInPhoto?(item) ?? false,
                                    photoMatchActionTitle: photoMatchActionTitle?(item),
                                    isPhotoMatchTarget: photoMatchTargetItemId == item.id,
                                    onPhotoMatchPress: onPhotoMatchPress.map { action in { action(item) } },
                                    onPress: { handleItemPress(item) },
                                    menuItems: getMenuItems?(item) ?? [],
                                    warningMessage: getWarning?(item)
                                )
                            }
                        }
                    }
                    .padding(Spacing.md)
                }
            }
            .frame(width: 480)
            .frame(maxHeight: 600)
            .background(BrandColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Dimensions.cardRadius)
                    .stroke(BrandColors.borderSecondary, lineWidth: Dimensions.borderWidth)
            )
            .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
        }
        .transition(.opacity)
    }
    #endif

    // MARK: - Item Cards

    @ViewBuilder
    private func protoItemRow(for protoItem: ProtoItem) -> some View {
        if let protoItemCard {
            protoItemCard(protoItem)
        }
    }

    @ViewBuilder
    private func singleItemCard(for item: Item) -> some View {
        // Issue 5: Skip items with nil IDs entirely
        if let itemId = item.id {
            let ids = resolvedSelectedIds.wrappedValue
            let menuItems = getMenuItems?(item) ?? []
            let warning = getWarning?(item)

            if isPicker {
                pickerItemCard(for: item, itemId: itemId, isItemSelected: ids.contains(itemId))
            } else {
                ItemCard(
                    item: item,
                    priceLabel: displayPrice(for: item),
                    budgetCategoryName: categoryName(for: item.budgetCategoryId),
                    isSelected: Binding(
                        get: { resolvedSelectedIds.wrappedValue.contains(itemId) },
                        set: { if $0 { resolvedSelectedIds.wrappedValue.insert(itemId) } else { resolvedSelectedIds.wrappedValue.remove(itemId) } }
                    ),
                    isMarkedInPhoto: isItemMarkedInPhoto?(item) ?? false,
                    photoMatchActionTitle: photoMatchActionTitle?(item),
                    isPhotoMatchTarget: photoMatchTargetItemId == item.id,
                    onPhotoMatchPress: onPhotoMatchPress.map { action in { action(item) } },
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
        if case .picker(_, let eligibilityCheck, let onAddSingle, let addedIds, _, let otherSpaceNameForItem) = mode {
            let isAdded = addedIds.contains(itemId)
            let isEligible = eligibilityCheck?(item) ?? true
            let otherSpaceName = isAdded ? nil : otherSpaceNameForItem?(item)
            let isInOtherSpace = otherSpaceName != nil
            let statusOverride: String? = isAdded ? "Added" : nil

            Button {
                if isAdded { return }
                if let name = otherSpaceName, !isItemSelected {
                    pendingMoveItem = item
                    pendingMoveFromSpaceName = name
                    return
                }
                if let onAddSingle {
                    onAddSingle(item)
                } else if isEligible {
                    toggleSelection(itemId)
                }
            } label: {
                ItemCard(
                    item: item,
                    priceLabel: displayPrice(for: item),
                    budgetCategoryName: categoryName(for: item.budgetCategoryId),
                    statusOverride: statusOverride,
                    isSelected: isAdded
                        ? .constant(true)
                        : Binding(
                            get: { isItemSelected },
                            set: { _ in
                                if let name = otherSpaceName, !isItemSelected {
                                    pendingMoveItem = item
                                    pendingMoveFromSpaceName = name
                                } else {
                                    toggleSelection(itemId)
                                }
                            }
                        ),
                    accent: isInOtherSpace && !isItemSelected
                )
            }
            .buttonStyle(.plain)
            .disabled(!isEligible && !isAdded)
            .opacity(isAdded ? 0.55 : (isEligible ? 1 : 0.5))
        }
    }

    @ViewBuilder
    private func groupedCard(
        for group: ItemGroup,
        completeGroup: ItemGroup?,
        photoMarkedItemIDs: Set<String>
    ) -> some View {
        // Issue 4: Use compactMap to only include items with valid IDs
        let ids = resolvedSelectedIds.wrappedValue
        let validItems = group.items.filter { $0.id != nil }
        let groupSelected = !validItems.isEmpty && validItems.allSatisfy { ids.contains($0.id!) }
        let totalLabel = group.totalCents > 0 ? CurrencyFormatting.formatCentsWithDecimals(group.totalCents) : nil

        let itemPriceLabels = group.items.map { displayPrice(for: $0) }
        let collapsedPrice = group.count > 1
            ? ItemCardCalculations.groupedCollapsedPrice(totalLabel: totalLabel, itemPriceLabels: itemPriceLabels)
            : (totalLabel, nil as String?)
        let displayedPriceLabel: String? = {
            let combined = [collapsedPrice.0, collapsedPrice.1].compactMap { $0 }.joined()
            return combined.isEmpty ? nil : combined
        }()

        let summaryItem = group.items.first(where: { ItemCardCalculations.primaryImage(from: $0.images) != nil }) ?? group.items.first
        let summaryImage = ItemCardCalculations.primaryImage(from: summaryItem?.images)
        let spaceName = groupedSpaceName(for: group)
        let isGroupMarkedInPhoto = ListFilterSortCalculations.isGroupFullyMarkedInPhoto(
            completeGroup ?? group,
            markedItemIDs: photoMarkedItemIDs
        )

        let selectionBinding = Binding(
            get: { groupSelected },
            set: { selected in
                for item in group.items {
                    if let id = item.id {
                        if selected { resolvedSelectedIds.wrappedValue.insert(id) } else { resolvedSelectedIds.wrappedValue.remove(id) }
                    }
                }
            }
        )
        let onSelectedChange: (Bool) -> Void = { selected in
            for item in group.items {
                if let id = item.id {
                    if selected { resolvedSelectedIds.wrappedValue.insert(id) } else { resolvedSelectedIds.wrappedValue.remove(id) }
                }
            }
        }

        GroupedItemCard(
            name: group.name,
            thumbnailUrl: summaryImage?.url,
            thumbnailSmUrl: summaryImage?.thumbnailUrlSm,
            countLabel: "×\(group.count)",
            totalLabel: totalLabel,
            sku: summaryItem?.sku,
            sourceLabel: summaryItem?.currentSource ?? summaryItem?.source,
            spaceName: spaceName,
            priceLabel: displayedPriceLabel,
            isMarkedInPhoto: isGroupMarkedInPhoto,
            isExpanded: inlineGroupExpansionBinding(for: group),
            isSelected: selectionBinding,
            onSelectedChange: onSelectedChange,
            onPress: groupedCardPressAction(for: group),
            itemCount: validItems.count
        ) {
            groupedCardExpandedContent(for: group)
        }
    }

    private func inlineGroupExpansionBinding(for group: ItemGroup) -> Binding<Bool>? {
        #if os(macOS)
        if !inline {
            return nil
        }
        #endif

        return Binding(
            get: { expandedGroups.contains(group.id) },
            set: { if $0 { expandedGroups.insert(group.id) } else { expandedGroups.remove(group.id) } }
        )
    }

    private func toggleVisibleGroupExpansion() {
        withAnimation {
            expandedGroups = ListFilterSortCalculations.toggledExpandedGroupIDs(
                expandedGroupIDs: expandedGroups,
                visibleGroupIDs: visibleExpandableGroupIDs
            )
        }
    }

    private func groupedCardPressAction(for group: ItemGroup) -> (() -> Void)? {
        #if os(macOS)
        if !inline {
            return { withAnimation { macOSExpandedGroup = group } }
        }
        #endif

        return nil
    }

    private func groupedSpaceName(for group: ItemGroup) -> String? {
        PerformanceDiagnostics.shared.measureAggregate("CardLookup", kind: "grouped-space") {
            let names = Set(group.items.compactMap { item -> String? in
                guard
                    let spaceId = item.spaceId,
                    let name = accountContext.spaceName(for: spaceId),
                    !name.isEmpty
                else {
                    return nil
                }
                return name
            })

            if names.count > 1 {
                return "Multiple spaces"
            }
            return names.first
        }
    }

    @ViewBuilder
    private func groupedCardExpandedContent(for group: ItemGroup) -> some View {
        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
            if let itemId = item.id {
                let selectionBinding = Binding(
                    get: { resolvedSelectedIds.wrappedValue.contains(itemId) },
                    set: { if $0 { resolvedSelectedIds.wrappedValue.insert(itemId) } else { resolvedSelectedIds.wrappedValue.remove(itemId) } }
                )
                ItemCard(
                    item: item,
                    priceLabel: displayPrice(for: item),
                    budgetCategoryName: categoryName(for: item.budgetCategoryId),
                    indexLabel: "\(index + 1)/\(group.items.count)",
                    statusOverride: item.status?.displayLabel,
                    isSelected: selectionBinding,
                    isMarkedInPhoto: isItemMarkedInPhoto?(item) ?? false,
                    photoMatchActionTitle: photoMatchActionTitle?(item),
                    isPhotoMatchTarget: photoMatchTargetItemId == item.id,
                    onPhotoMatchPress: onPhotoMatchPress.map { action in { action(item) } },
                    onPress: { handleItemPress(item) },
                    menuItems: getMenuItems?(item) ?? [],
                    warningMessage: getWarning?(item)
                )
            }
        }
    }

    // MARK: - Bottom Bar

    @ViewBuilder
    private var bottomBar: some View {
        if isPicker {
            pickerBottomBar
        } else if !resolvedSelectedIds.wrappedValue.isEmpty {
            BulkSelectionBar(
                selectedCount: resolvedSelectedIds.wrappedValue.count,
                totalCount: processedItems.count,
                totalCents: selectedTotalCents,
                onBulkActions: {
                    PerformanceDiagnostics.shared.event(
                        "BulkActionMenuTriggered",
                        kind: diagnosticMode,
                        count: resolvedSelectedIds.wrappedValue.count
                    )
                    showBulkActionMenu = true
                },
                onClear: { resolvedSelectedIds.wrappedValue.removeAll() }
            )
        }
    }

    @ViewBuilder
    private var pickerBottomBar: some View {
        if case .picker(_, _, _, _, let onAddSelected, _) = mode, !resolvedSelectedIds.wrappedValue.isEmpty {
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
            .background(BrandColors.background)
        }
    }

    // MARK: - Data Setup

    private func setupData() async {
        let interval = PerformanceDiagnostics.shared.beginInterval(
            "ListSetup",
            kind: diagnosticMode,
            count: embeddedSourceItems.count + (pickerItems?.count ?? 0)
        )
        defer { PerformanceDiagnostics.shared.endInterval(interval, value: items.count) }
        switch mode {
        case .standalone(let scope):
            await setupStandaloneListener(scope: scope)
        case .embedded(let providedItems, _):
            items = providedItems
            isLoading = false
        case .picker(let scope, _, _, _, _, _):
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

        let service = ItemsService()
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
        return PerformanceDiagnostics.shared.measureAggregate("CardLookup", kind: "category") {
            accountContext.budgetCategoryName(for: categoryId)
        }
    }

    private func displayPrice(for item: Item) -> String? {
        item.normalizedProjectPriceCents.map(CurrencyFormatting.formatCentsWithDecimals)
    }

    private var diagnosticMode: String {
        switch mode {
        case .standalone: "items.standalone"
        case .embedded: "items.embedded"
        case .picker: "items.picker"
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
            scope: nil,
            eligibilityCheck: { _ in true },
            onAddSingle: nil,
            addedIds: [],
            onAddSelected: { print("Add selected") },
            otherSpaceNameForItem: nil
        )
    )
}

#Preview("Empty State") {
    SharedItemsList(
        mode: .embedded(items: [], onItemPress: { _ in }),
        emptyMessage: "No items match your filters"
    )
}
