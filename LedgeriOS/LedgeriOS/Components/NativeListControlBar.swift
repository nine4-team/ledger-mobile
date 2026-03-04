import SwiftUI

struct NativeListControlBar<SelectAllContent: View, SortContent: View, FilterContent: View>: View {
    @Binding var searchText: String
    var searchPlaceholder: String = "Search..."
    var onAdd: (() -> Void)?
    @ViewBuilder var selectAll: () -> SelectAllContent
    @ViewBuilder var sortMenu: () -> SortContent
    @ViewBuilder var filterMenu: () -> FilterContent

    @State private var isSearchExpanded = false
    @State private var isSearchFocused = false
    @State private var capsuleWidth: CGFloat = 0

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
            .background(GeometryReader { geo in
                Color.clear.preference(key: CapsuleWidthKey.self, value: geo.size.width)
            })

            if isSearchExpanded {
                SearchField(
                    text: $searchText,
                    placeholder: searchPlaceholder,
                    isFocused: $isSearchFocused,
                    style: .overlay,
                    onDismiss: {
                        withAnimation(.spring(duration: 0.3)) {
                            isSearchExpanded = false
                            isSearchFocused = false
                        }
                    }
                )
                .frame(width: capsuleWidth > 0 ? capsuleWidth : nil)
            }
        }
        .onPreferenceChange(CapsuleWidthKey.self) { capsuleWidth = $0 }
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
}

// MARK: - Preference Key

private struct CapsuleWidthKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
