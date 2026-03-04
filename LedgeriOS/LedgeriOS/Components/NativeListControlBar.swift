import SwiftUI

struct NativeListControlBar<SelectAllContent: View, SortContent: View, FilterContent: View>: View {
    @Binding var searchText: String
    var searchPlaceholder: String = "Search..."
    var onAdd: (() -> Void)?
    @ViewBuilder var selectAll: () -> SelectAllContent
    @ViewBuilder var sortMenu: () -> SortContent
    @ViewBuilder var filterMenu: () -> FilterContent

    @State private var isSearchExpanded = false
    @FocusState private var isSearchFocused: Bool

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
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                selectAll()

                Spacer(minLength: 0)

                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        isSearchExpanded = true
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                }
                .tint(.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Search")

                sortMenu()
                    .imageScale(.large)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())

                filterMenu()
                    .imageScale(.large)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())

                if let onAdd {
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .imageScale(.large)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                    .tint(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Add")
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .modifier(CapsuleGlassModifier())

            if isSearchExpanded {
                searchField
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.sm)
        .onChange(of: isSearchExpanded) { _, expanded in
            if expanded {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isSearchFocused = true
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 15))

            TextField(searchPlaceholder, text: $searchText)
                .font(.subheadline)
                .focused($isSearchFocused)

            Button {
                if searchText.isEmpty {
                    withAnimation(.spring(duration: 0.3)) {
                        isSearchExpanded = false
                        isSearchFocused = false
                    }
                } else {
                    searchText = ""
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 7)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Glass Material

private struct CapsuleGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(in: .capsule)
        } else {
            content
                .background(.bar)
                .clipShape(Capsule(style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
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
