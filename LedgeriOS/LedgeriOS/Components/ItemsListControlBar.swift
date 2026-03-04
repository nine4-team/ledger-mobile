import SwiftUI

struct ItemsListControlBar<LeftElement: View>: View {
    @Binding var searchText: String
    @Binding var isSearchVisible: Bool
    var onSort: () -> Void
    var onFilter: () -> Void
    var onAdd: (() -> Void)?
    var activeFilterCount: Int = 0
    var activeSortLabel: String?
    @ViewBuilder var leftElement: () -> LeftElement

    init(
        searchText: Binding<String>,
        isSearchVisible: Binding<Bool>,
        onSort: @escaping () -> Void,
        onFilter: @escaping () -> Void,
        onAdd: (() -> Void)? = nil,
        activeFilterCount: Int = 0,
        activeSortLabel: String? = nil,
        @ViewBuilder leftElement: @escaping () -> LeftElement = { EmptyView() }
    ) {
        self._searchText = searchText
        self._isSearchVisible = isSearchVisible
        self.onSort = onSort
        self.onFilter = onFilter
        self.onAdd = onAdd
        self.activeFilterCount = activeFilterCount
        self.activeSortLabel = activeSortLabel
        self.leftElement = leftElement
    }

    var body: some View {
        ListControlBar(
            searchText: $searchText,
            isSearchVisible: $isSearchVisible,
            actions: actions,
            leftElement: leftElement
        )
    }

    private var actions: [ControlAction] {
        var items: [ControlAction] = [
            ControlAction(
                id: "search",
                title: "",
                icon: "magnifyingglass",
                isActive: isSearchVisible,
                appearance: .iconOnly
            ) {
                withAnimation {
                    isSearchVisible.toggle()
                    if !isSearchVisible { searchText = "" }
                }
            },
            ControlAction(
                id: "sort",
                title: activeSortLabel ?? "Sort",
                icon: "arrow.up.arrow.down",
                isActive: activeSortLabel != nil,
                action: onSort
            ),
            ControlAction(
                id: "filter",
                title: activeFilterCount > 0 ? "Filter (\(activeFilterCount))" : "Filter",
                icon: "line.3.horizontal.decrease",
                isActive: activeFilterCount > 0,
                action: onFilter
            ),
        ]

        if let onAdd {
            items.append(
                ControlAction(
                    id: "add",
                    title: "",
                    variant: .primary,
                    icon: "plus",
                    appearance: .iconOnly,
                    action: onAdd
                )
            )
        }

        return items
    }
}

// MARK: - Previews

#Preview("Default") {
    @Previewable @State var search = ""
    @Previewable @State var showSearch = false

    ItemsListControlBar(
        searchText: $search,
        isSearchVisible: $showSearch,
        onSort: {},
        onFilter: {},
        onAdd: {}
    )
    .padding(Spacing.screenPadding)
}

#Preview("Active Filters") {
    @Previewable @State var search = ""
    @Previewable @State var showSearch = true

    ItemsListControlBar(
        searchText: $search,
        isSearchVisible: $showSearch,
        onSort: {},
        onFilter: {},
        onAdd: {},
        activeFilterCount: 2,
        activeSortLabel: "A-Z"
    )
    .padding(Spacing.screenPadding)
}

#Preview("With Select All") {
    @Previewable @State var search = ""
    @Previewable @State var showSearch = false
    @Previewable @State var allSelected = false

    ItemsListControlBar(
        searchText: $search,
        isSearchVisible: $showSearch,
        onSort: {},
        onFilter: {},
        onAdd: {}
    ) {
        Button { allSelected.toggle() } label: {
            SelectorCircle(isSelected: allSelected, indicator: .check)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select all")
    }
    .padding(Spacing.screenPadding)
}

#Preview("No Add Button") {
    @Previewable @State var search = ""
    @Previewable @State var showSearch = false

    ItemsListControlBar(
        searchText: $search,
        isSearchVisible: $showSearch,
        onSort: {},
        onFilter: {}
    )
    .padding(Spacing.screenPadding)
}
