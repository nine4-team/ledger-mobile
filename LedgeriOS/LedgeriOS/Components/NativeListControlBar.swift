import SwiftUI

struct NativeListControlBar<SelectAllContent: View, SortContent: View, FilterContent: View>: View {
    @Binding var searchText: String
    var searchPlaceholder: String = "Search..."
    var onAdd: (() -> Void)?
    @ViewBuilder var selectAll: () -> SelectAllContent
    @ViewBuilder var sortMenu: () -> SortContent
    @ViewBuilder var filterMenu: () -> FilterContent

    init(
        searchText: Binding<String>,
        searchPlaceholder: String = "Search...",
        onAdd: (() -> Void)? = nil,
        @ViewBuilder selectAll: @escaping () -> SelectAllContent = { EmptyView() },
        @ViewBuilder sortMenu: @escaping () -> SortContent = { EmptyView() },
        @ViewBuilder filterMenu: @escaping () -> FilterContent = { EmptyView() }
    ) {
        self._searchText = searchText
        self.searchPlaceholder = searchPlaceholder
        self.onAdd = onAdd
        self.selectAll = selectAll
        self.sortMenu = sortMenu
        self.filterMenu = filterMenu
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.sm) {
                selectAll()

                searchField

                sortMenu()
                filterMenu()

                if let onAdd {
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(BrandColors.primary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add")
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.sm)

            Divider()
        }
        .background(.bar)
    }

    private var searchField: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))

            TextField(searchPlaceholder, text: $searchText)
                .font(Typography.input)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Previews

#Preview("Search + Add (Spaces)") {
    NativeListControlBar(
        searchText: .constant(""),
        searchPlaceholder: "Search spaces...",
        onAdd: {}
    )
}

#Preview("Full (Items/Transactions)") {
    @Previewable @State var sort = ItemSortOption.createdDesc
    @Previewable @State var filter = ItemFilterOption.all
    @Previewable @State var allSelected = false

    NativeListControlBar(
        searchText: .constant(""),
        searchPlaceholder: "Search items...",
        onAdd: {}
    ) {
        Button { allSelected.toggle() } label: {
            SelectorCircle(isSelected: allSelected, indicator: .check)
        }
        .buttonStyle(.plain)
    } sortMenu: {
        Menu {
            Picker("Sort", selection: $sort) {
                ForEach(ItemSortOption.allCases, id: \.self) { option in
                    Text(ListFilterSortCalculations.sortLabel(for: option)).tag(option)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .foregroundStyle(sort != .createdDesc ? BrandColors.primary : .secondary)
        }
    } filterMenu: {
        Menu {
            Picker("Filter", selection: $filter) {
                ForEach(ItemFilterOption.allCases, id: \.self) { option in
                    Text(ListFilterSortCalculations.filterLabel(for: option)).tag(option)
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .foregroundStyle(filter != .all ? BrandColors.primary : .secondary)
        }
    }
}

#Preview("With Search Text") {
    NativeListControlBar(
        searchText: .constant("Pillow"),
        searchPlaceholder: "Search items...",
        onAdd: {}
    )
}
